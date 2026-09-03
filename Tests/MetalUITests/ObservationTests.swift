import Testing
import Metal
import Observation
@testable import MetalUI
import MetalUICore

/// A stand-in for an application's own model. `@Observable` and mutated from
/// tests; nothing in the framework knows this type exists, which is the point —
/// there is no opt-in, no registration and no annotation on the framework side.
@Observable
final class ProbeModel {
    var label: String = "a"
    var untouched: Int = 0
}

/// Spec §3 and §4: an `@Observable` property read anywhere during a frame build
/// becomes a dependency of that frame, and mutating it marks the window dirty.
///
/// This is the assertion the whole spec exists for: before it, `grep -rn
/// "withObservationTracking" Sources/` returned nothing and no model could
/// dirty a window at all.
@MainActor
@Test func mutatingAnObservedModelMarksTheWindowDirty() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    // Drain the initial dirty state so the next write is the only cause.
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: the window must be clean")

    model.label = "bb"

    #expect(window.needsRedraw,
            "an @Observable property read during the frame build must dirty the window")
    #expect(window.observationDirtyings == 1,
            "exactly one dirty-marking for one write, not zero and not several")
}

/// Spec §4.2: a property the frame build never reads is not a dependency.
/// Without this, a passing sibling test could be explained by the window
/// dirtying on *any* observable write anywhere, which is not what
/// `withObservationTracking` promises and not what §3 specifies.
@MainActor
@Test func mutatingAnUnreadPropertyDoesNotDirtyTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: the window must be clean")

    model.untouched += 1        // never read by the content closure

    #expect(!window.needsRedraw,
            "a property no frame read is not a dependency of any frame")
    #expect(window.observationDirtyings == 0)
}

/// Spec §2 and §6.2 assertion 3. `withObservationTracking` installs an observer
/// per tracked property per call and removes it only when `onChange` fires, and
/// there is **no public cancellation API**. Re-registering every frame — which
/// design spec §4.4 prescribes — therefore accumulates one observer per drawn
/// frame on every property that has not changed, and MetalUI's common case
/// (scrolling a list while the document is static) is the pathological one.
///
/// `Window.redrawSentinel` bounds it at exactly one outstanding session.
///
/// **This is the assertion that would rot silently.** Removing the sentinel
/// leaves every other test in this file green, because a redundant
/// dirty-marking changes no behaviour anyone can observe. Measured on a
/// standalone prototype of this exact shape: 1000 drawn frames then one write
/// gives an `observationDirtyings` delta of **1** with the sentinel and
/// **1000** without it.
@MainActor
@Test func theObserverSetIsBoundedRegardlessOfFramesDrawn() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")

    // Two windows rather than a loop over one, so the low and high frame counts
    // are compared as a differential. A single-count assertion cannot tell a
    // bounded implementation from an accumulating one — the whole defect is
    // that the number GROWS.
    for framesToDraw in [1, 200] {
        let model = ProbeModel()
        let (window, _) = try makeFakeWindow(device: device) {
            Box().background(.surface).width(Pixels(10))
                 .height(Pixels(Float(model.label.count)))
        }

        for _ in 0..<framesToDraw {
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
        }

        let before = window.observationDirtyings
        model.label += "x"

        #expect(window.observationDirtyings - before == 1,
                """
                one write must produce exactly one dirty-marking, not one per \
                frame drawn since the last change. Drew \(framesToDraw) frames \
                and got \(window.observationDirtyings - before). If this reads \
                \(framesToDraw), `Window.redrawSentinel` is not being written \
                or not being read inside the tracked closure.
                """)
    }
}

/// Spec §6.2 assertion 4, in its **corrected** form.
///
/// The spec's first draft said deleting `Window.isFlushing`'s guard would
/// redden the pre-existing idle test. Measured on a standalone prototype: it
/// reddens nothing behavioural. `needsRedraw`, `framesDrawn` and the pause
/// record are byte-identical with and without the guard, because the
/// `needsRedraw = false` on the line after the flush already absorbs the
/// spurious dirty.
///
/// So the pin is a counter assertion, and it is semantically meaningful in its
/// own right rather than a mutation trap: **a frame that changes no observed
/// property reports no observation-dirtying.** With the guard deleted this
/// reads 199 rather than 0.
@MainActor
@Test func aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    for _ in 0..<200 {
        window.setNeedsRedraw()          // dirtied by something that is not the model
        window.drawFrameIfNeeded()
    }

    #expect(window.observationDirtyings == 0,
            """
            the per-frame sentinel flush must not count as an observation \
            change. Got \(window.observationDirtyings) across 200 frames; if \
            this reads 199, `isFlushing` is not guarding \
            `markDirtyFromObservation`.
            """)
}

/// Spec §6.2 assertion 1's new half. The pre-existing
/// `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt` (`FrameLoopTests.swift`)
/// already pins that an idle tick pauses and that `setNeedsRedraw()` resumes.
/// What is new is that an **observable write** must be able to wake a *paused*
/// window — the path that did not exist before this spec.
@MainActor
@Test func anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, platformWindow) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    window.drawFrameIfNeeded()                       // drain the initial dirty
    window.drawFrameIfNeeded()                       // idle: this one pauses
    try #require(platformWindow.pauseCalls.last == true,
                 "set up: the link must be paused before the write")
    let framesBefore = window.framesDrawn
    let pausesBefore = window.pausesEntered

    model.label = "woken"

    #expect(platformWindow.pauseCalls.last == false, "the write must resume the link")

    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == framesBefore + 1, "exactly one frame, not zero and not two")

    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == framesBefore + 1, "and then the window idles again")
    #expect(window.pausesEntered == pausesBefore + 1, "having paused exactly once more")
}

/// Spec §4.2, the synchronous branch. A main-actor mutation — the demo, every
/// other test in this file, any main-actor model — marks the window dirty
/// *before the write it is reacting to has landed*, with no suspension point
/// between the two. Asserting immediately after the write, with no `await`, is
/// what makes this a test of the branch rather than of the outcome.
@MainActor
@Test func aMainThreadMutationMarksTheWindowDirtySynchronously() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw)

    model.label = "sync"

    #expect(window.needsRedraw, "no hop: dirty on the same statement")
    #expect(window.observationDirtyings == 1)
}

/// Spec §4.2, the hop branch. An off-thread mutation cannot touch `@MainActor`
/// state, so it must go through a `Task`. The observable difference is exactly
/// the suspension: still clean immediately after the write, dirty after a yield.
///
/// The two halves are what make this a test of the BRANCH. Asserting only the
/// second half would pass under an implementation that hopped in both cases,
/// and asserting only the first would pass under one that dropped the callback
/// entirely.
@MainActor
@Test func anOffThreadMutationMarksTheWindowDirtyAfterAHop() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw)

    // A detached task is what puts the mutation on some other thread. `model`
    // is @Observable and not isolated, so this is exactly what an application
    // mutating its model from a background context would do.
    let done = Task.detached {
        model.label = "async"
    }
    await done.value

    // The write has landed, but the main actor has not yet run the hop's body,
    // because this function has not suspended in a way that lets it.
    #expect(!window.needsRedraw,
            "the hop must not have completed yet — if this is already true, the off-thread branch is not hopping and MainActor.assumeIsolated would have trapped instead")

    // One yield is enough: the hop's Task is already enqueued on the main actor.
    await Task.yield()

    #expect(window.needsRedraw, "after a hop, the window is dirty")
    #expect(window.observationDirtyings == 1)
}

/// Spec §4.4. `@State` and `@Observable` are two independent dirty sources and
/// neither suppresses the other. `StateTable` holds no `@Observable` property,
/// so a `@State` write registers nothing with the observation machinery; an
/// observation change touches no `StateTable` entry.
@MainActor
@Test func stateAndObservableAreIndependentDirtySources() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw)

    // A @State write goes through StateTable.onWrite, not through observation.
    window.stateTable.write(GlobalElementID.child(of: nil, at: 0, name: nil), 1)
    #expect(window.needsRedraw, "a @State write still dirties the window")
    #expect(window.observationDirtyings == 0,
            "and does NOT go through the observation path")

    let framesBefore = window.framesDrawn
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == framesBefore + 1)

    model.label = "both"
    #expect(window.needsRedraw, "an observable write still dirties the window")
    #expect(window.observationDirtyings == 1, "through the observation path this time")
}

/// Spec §3's recorded consequence. A `List` builds only the rows intersecting
/// the viewport, so an off-screen row's builder never runs and its model reads
/// are never tracked. **Mutating an off-screen row's datum marks nothing
/// dirty.**
///
/// Correct — there is nothing on screen to redraw, and scrolling to the row
/// rebuilds and re-reads it — but it is the same "not produced ⇒ not seen"
/// mechanism that produced divergences 12 and 17, arriving in a third place.
/// Asserted as the documented behaviour it is, not as a defect: SwiftUI's
/// `List` does the same thing for the same reason, so no oracle disagrees.
@MainActor
@Test func anOffScreenListRowsModelReadIsNotTracked() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    // `List` requires `Data.Element: Identifiable`, so the rows are a struct
    // carrying an id and a reference to its own observable model — the shape
    // `ListTests`' own `Item` already uses.
    struct Row: Identifiable { let id: Int; let model: ProbeModel }
    let rows = (0..<200).map { Row(id: $0, model: ProbeModel()) }

    // `startsDisplayLink: true` plus one simulated tick, matching
    // `ScrollIndicatorTests`' own idiom: with no tick ever simulated,
    // `Window.lastTick` and `ScrollState.lastScrollTime` both default to 0, so
    // the indicator's `age = lastTick - lastScrollTime` is stuck at 0 — inside
    // its fully-opaque window — and `Frame.wantsAnotherFrame` stays true
    // forever, which is a property of an un-ticked fake window with a
    // scrollable `ScrollView` in it and has nothing to do with this test's
    // own subject.
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 64, startsDisplayLink: true) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            List(rows, rowHeight: Pixels(20)) { row in
                Box().background(.surface)
                     .height(Pixels(Float(row.model.label.count)))
            }
        }
    }
    window.drawFrameIfNeeded()
    platformWindow.simulateTick(timestamp: 100)
    try #require(!window.needsRedraw, "set up: the window must be clean")

    // Row 199 is far outside a 64pt viewport at offset 0, so its builder never
    // ran and nothing read `models[199].label`.
    rows[199].model.label += "x"

    #expect(!window.needsRedraw,
            "an off-screen row's datum is not a dependency of a frame that never built that row")
    #expect(window.observationDirtyings == 0)
}
