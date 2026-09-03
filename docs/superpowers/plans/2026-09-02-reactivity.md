# Reactivity (M4 spec 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an `@Observable` model mutation mark a `Window` dirty and draw exactly one frame, with observer registrations bounded at one outstanding session regardless of how many frames are drawn between writes.

**Architecture:** `Window.drawFrameIfNeeded` wraps its existing `renderRoot(frame)` call in `withObservationTracking`. Because that API is one-shot and offers no cancellation, a private `@Observable` sentinel is read inside every session and written at the top of every frame, which fires — and thereby removes — all previously armed sessions. The dirty callback is `nonisolated` and reaches the `@MainActor` window synchronously when already on the main thread, via a `Task` otherwise.

**Tech Stack:** Swift 6.3, `Observation` (`withObservationTracking`, `@Observable`), Swift Testing, Metal. Package floor is `.macOS(.v14)` — unchanged, and already above `Observation`'s.

**Spec:** `docs/superpowers/specs/2026-09-02-reactivity-design.md`

> **PARTLY SUPERSEDED DURING EXECUTION — read `docs/superpowers/2026-09-02-reactivity-decisions.md` beside this plan, in particular `RX-Q` and `RX-H`.** This plan is kept as written, including text later measured to be false, because two rulings cite that text as evidence and correcting it in place would destroy what they cite. The plan is not the record of what shipped; the decisions doc is.

## Global Constraints

- **Read the test summary line, never the exit status.** `swift test --no-parallel`, unfiltered, and read `Test run with N tests in 1 suite passed after …`. A run that dies mid-suite prints no summary line and exits non-zero in a way that is easy to misread.
- **Baseline is 782 tests, 87 goldens, 32 `swiftc -typecheck` guards, warning-free.** Verify with `find Tests -name "*.json" | wc -l` = 87 and a full-log `grep -ci "warning:"` = 0.
- **No golden may move and none may be added.** This spec touches no layout code. A moved golden means something reached the engine that should not have — stop and report, do not regenerate.
- **Assert counts, never wall-clock times.** A committed millisecond baseline flakes on a loaded box.
- **`hasActiveAnimations` must not exist in `Sources/` at this plan's last commit.** An always-false stored property with no writer is the declared-but-inert trap; M4 spec 3 introduces it together with its writer.
- **A mutation that reddens nothing is a broken instrument or it is the finding.** Prove a mutant behaves differently before banking a coverage gap. Where a task says "run this mutation", run it and report the actual output — never predict it.
- **Anything a mutation teaches must be walked back to the mutated LINE in the same pass**, not only into the task report.
- **`Window` is `@MainActor public final class`** (`Sources/MetalUI/Window.swift:7-8`). Anything reachable from a `@Sendable` closure must be `nonisolated`.
- Do not add a `Style` property, a `StyledElement` requirement, or a public modifier anywhere in this plan.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Sources/MetalUI/RedrawSentinel.swift` (create) | The private `@Observable` liveness token whose write flushes armed observation sessions. One type, no behaviour. | 1 |
| `Sources/MetalUI/Window.swift` (modify) | The frame-loop ordering, the `nonisolated` dirty callback, the two counters. | 1, 2, 3 |
| `Tests/MetalUITests/ObservationTests.swift` (create) | Every assertion this spec owns. New file rather than extending `FrameLoopTests`, which already owns the pre-existing pause coverage. | 2, 3, 4 |
| `Sources/MetalUIDemo/main.swift` (modify) | `showModal` moves from a top-level `var` onto an `@Observable` model; the atexit counter summary. | 5 |
| `CLAUDE.md`, `docs/superpowers/2026-09-02-reactivity-decisions.md` (create) | The record. | 6 |

---

### Task 1: The sentinel and the counters

**Files:**
- Create: `Sources/MetalUI/RedrawSentinel.swift`
- Modify: `Sources/MetalUI/Window.swift` — add stored properties near `framesDrawn` (currently line 136)
- Test: none in this task. This task adds storage that nothing reads yet; Task 2 wires it and Task 3 asserts it. Splitting it out keeps Task 2's diff to the frame loop alone.

**Interfaces:**
- Produces: `final class RedrawSentinel` (`@Observable`, `internal`, one property `var tick: Int = 0`); `Window.pausesEntered: Int` and `Window.observationDirtyings: Int`, both `public private(set)`; `Window.isFlushing: Bool`, `private`; `Window.redrawSentinel: RedrawSentinel`, `private let`.

- [ ] **Step 1: Create the sentinel**

Create `Sources/MetalUI/RedrawSentinel.swift`:

```swift
import Observation

/// A liveness token whose only purpose is to be written once per frame, so that
/// every `withObservationTracking` session armed by a previous frame fires and
/// is thereby **removed**.
///
/// **Why this exists at all.** `withObservationTracking` installs an observer
/// per tracked property per call and removes it only when `onChange` fires. It
/// offers no cancellation: it returns nothing and exposes no handle, and
/// `ObservationRegistrar`'s install path is not public for arbitrary models. So
/// re-registering every frame — which design spec §4.4 prescribes, calling the
/// one-shot behaviour "ideal, since we re-register every frame" — accumulates
/// one observer per *drawn frame* on every property that has not changed.
///
/// **Measured** on a standalone probe (`swiftc -O -swift-version 6`), reading
/// one `@Observable` property across N frames and then writing it once: N = 1
/// gives 1 `onChange` call, N = 10 gives 10, N = 1000 gives 1000. Linear, no
/// plateau. MetalUI's common case is the pathological one — scrolling a list
/// draws frames continuously while the document model is static.
///
/// With this sentinel read inside every session and written at the top of every
/// frame, the same probe gives **1** at every N up to 10,000, with N−1 flush
/// callbacks: exactly one session outstanding at any moment.
///
/// `internal`, and deliberately not `public`: it is a mechanism, not API. See
/// `Window.drawFrameIfNeeded` for the three orderings that make it work.
@Observable
final class RedrawSentinel {
    /// Incremented with `&+=` rather than `+=`. This is a liveness token and
    /// never a quantity, and a window running for weeks must not trap on
    /// overflow.
    var tick: Int = 0
}
```

- [ ] **Step 2: Add the stored properties to `Window`**

In `Sources/MetalUI/Window.swift`, immediately after the `framesDrawn` declaration (currently line 136, following its `/// Test observability: how many frames actually reached the GPU.` comment), insert:

```swift
    /// How many times the loop has found nothing to do and paused the display
    /// link. Test and debug observability, not API.
    public private(set) var pausesEntered: Int = 0

    /// How many times an `@Observable` change has marked this window dirty,
    /// **excluding** the per-frame sentinel flush.
    ///
    /// This is the only observable that can distinguish "one dirty-marking per
    /// write" from "N of them" — `needsRedraw` is a `Bool` and cannot. It is
    /// what `theObserverSetIsBoundedRegardlessOfFramesDrawn` reads, and
    /// removing `redrawSentinel` takes it from 1 to N.
    ///
    /// Test and debug observability, not API. Delete both counters in the same
    /// change that lands a real profiling story.
    public private(set) var observationDirtyings: Int = 0
```

Then add, near the `private var lastTick: Double = 0` declaration (currently line 337):

```swift
    /// Written once per frame to flush observation sessions armed by previous
    /// frames. See `RedrawSentinel` for why, with the measurement.
    private let redrawSentinel = RedrawSentinel()

    /// True only for the duration of the sentinel write in
    /// `drawFrameIfNeeded`, so `markDirtyFromObservation` can tell a flush from
    /// a real change.
    ///
    /// **Behaviourally redundant today and kept anyway** — measured: deleting
    /// this guard changes `needsRedraw`, `framesDrawn` and the pause record not
    /// at all, because the `needsRedraw = false` on the line after the flush
    /// already absorbs the spurious dirty. It shows up only in
    /// `observationDirtyings`: 0 across 1000 drawn frames with the guard, 999
    /// without. It is kept because it makes the correctness independent of the
    /// flush happening to run on the main thread, rather than resting on that.
    private var isFlushing = false
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no warnings. `RedrawSentinel` is unreferenced except by `Window`'s stored property, and an unused `private let` produces no warning in Swift.

- [ ] **Step 4: Run the suite to confirm nothing moved**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 782 tests in 1 suite passed after …`. This task adds no test and changes no behaviour.

- [ ] **Step 5: Commit**

```bash
git add Sources/MetalUI/RedrawSentinel.swift Sources/MetalUI/Window.swift
git commit -m "feat: the redraw sentinel and the two reactivity counters

Storage only. RedrawSentinel is the @Observable liveness token whose per-frame
write flushes observation sessions armed by earlier frames; its doc carries the
measurement that motivates it (1000 frames give 1000 onChange calls for one
write without it, 1 with it, at every N up to 10,000).

Window gains pausesEntered and observationDirtyings, both public private(set)
test observability, plus the private isFlushing flag. Nothing reads any of them
yet — the frame loop is Task 2.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 2: The dirty callback and the frame-loop ordering

**Files:**
- Modify: `Sources/MetalUI/Window.swift` — `setNeedsRedraw` (line 444), `drawFrameIfNeeded` (line 449), plus one new `nonisolated` method
- Test: `Tests/MetalUITests/ObservationTests.swift` (create)

**Interfaces:**
- Consumes: `RedrawSentinel`, `Window.isFlushing`, `Window.pausesEntered`, `Window.observationDirtyings` from Task 1.
- Produces: `Window.markDirtyFromObservation()` — `nonisolated private func`, no parameters, returns `Void`. Callable from any thread.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/ObservationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --no-parallel --filter "mutatingAnObservedModelMarksTheWindowDirty|mutatingAnUnreadPropertyDoesNotDirtyTheWindow" 2>&1 | tail -20`

Expected: `mutatingAnObservedModelMarksTheWindowDirty` **FAILS** — `needsRedraw` is `false` and `observationDirtyings` is 0, because nothing tracks anything yet. `mutatingAnUnreadPropertyDoesNotDirtyTheWindow` **PASSES** — it asserts the absence of a behaviour that does not exist yet, so it is vacuously green.

**Record both outcomes in the task report.** The second test being green on arrival is expected and is not a defect: it is a control that becomes meaningful once the first passes. Do not "fix" it.

- [ ] **Step 3: Add the dirty callback**

In `Sources/MetalUI/Window.swift`, immediately after `setNeedsRedraw()` (currently ending line 447), add:

```swift
    /// The `withObservationTracking` callback: something a frame read has
    /// changed, so the next frame must be built.
    ///
    /// **`nonisolated` is forced, not chosen.** `withObservationTracking`'s
    /// `onChange` is `@Sendable` and fires on the *mutating* thread, which may
    /// be any thread, so this cannot be `@MainActor` and cannot touch a stored
    /// property directly. Both branches below re-enter the actor before reading
    /// `isFlushing` or writing anything.
    ///
    /// **The two branches differ in latency, not in outcome.** A main-thread
    /// mutation — the demo, every test, any main-actor model — marks the window
    /// dirty *synchronously*, before the write it is reacting to has even
    /// landed. An off-thread mutation costs one main-actor hop first.
    ///
    /// **The synchronous branch is load-bearing for the idle criterion, not an
    /// optimisation.** The per-frame sentinel flush runs on the main thread and
    /// fires this method; under an always-hop implementation that callback
    /// would land *after* `drawFrameIfNeeded`'s `needsRedraw = false`, marking
    /// the window dirty on every single frame forever and destroying the
    /// display-link pause this milestone exists to deliver. The `isFlushing`
    /// guard is what makes that independent of thread affinity rather than
    /// resting on it.
    nonisolated private func markDirtyFromObservation() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                guard !self.isFlushing else { return }
                self.observationDirtyings += 1
                self.setNeedsRedraw()
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self, !self.isFlushing else { return }
                self.observationDirtyings += 1
                self.setNeedsRedraw()
            }
        }
    }
```

`Foundation` supplies `Thread`; `Window.swift` reaches it transitively through `Metal`. If the build reports `cannot find 'Thread' in scope`, add `import Foundation` at the top rather than reaching for another predicate.

- [ ] **Step 4: Rewrite the frame loop's opening**

In `drawFrameIfNeeded()`, replace the guard and the `needsRedraw = false` / `stateTable.clearDirty()` pair (currently lines 450-467, ending at `stateTable.clearDirty()`) with:

```swift
        guard needsRedraw else {
            // Nothing to do: let the display idle rather than spinning.
            platformWindow.setDisplayLinkPaused(true)
            pausesEntered += 1
            return
        }

        // Flush every observation session armed by an earlier frame, so
        // registrations stay bounded at one outstanding session instead of
        // growing with frames drawn. See `RedrawSentinel` for the measurement.
        //
        // THREE ORDERINGS ARE LOAD-BEARING HERE.
        //
        // 1. The flush is INSIDE the dirty branch, after the guard above. A
        //    clean, paused window must keep its one armed session — that
        //    session is what wakes it. Flushing before the guard disarms an
        //    idle window and it never redraws again.
        // 2. The flush PRECEDES `needsRedraw = false`. Any dirty the flush
        //    produces is absorbed by that clear. Moving the clear above the
        //    flush leaves the window permanently dirty at full frame rate.
        // 3. `redrawSentinel.tick` is READ inside the tracked closure below.
        //    That is what arms the next flush; a frame that does not read it
        //    cannot be flushed and rejoins the accumulating case.
        isFlushing = true
        redrawSentinel.tick &+= 1
        isFlushing = false

        needsRedraw = false
        // Cleared HERE, before `renderRoot` runs below — not after the frame
        // is built. **This ordering has no production consequence**: a
        // `@State` write made during `renderRoot` fires `onWrite` →
        // `setNeedsRedraw()` regardless of where this call sits, nothing
        // clears `needsRedraw` again before this function returns, so the
        // write is unswallowable either way. The same argument covers an
        // `@Observable` change arriving during the build. What the ordering
        // actually protects is `isDirty` itself, which is otherwise-inert test
        // observability (see `StateTable.isDirty`'s doc): clearing it AFTER
        // `renderRoot` would raise it during the render and immediately
        // clear it again on the next line, so a test reading it back would
        // never see a write made during that frame. Clearing first keeps
        // that observable coherent with the "a write during a frame is not
        // lost" claim it exists to let a test check.
        stateTable.clearDirty()
```

- [ ] **Step 5: Wrap the render in a tracking session**

Find the call to `renderRoot(frame)` in `drawFrameIfNeeded` and wrap it:

```swift
        withObservationTracking {
            // Reading the sentinel arms the next frame's flush; see ordering
            // note 3 above. Everything the element tree reads during all three
            // phases is tracked too, which is what makes an `@Observable`
            // model a dependency with no opt-in.
            _ = redrawSentinel.tick
            renderRoot(frame)
        } onChange: { [weak self] in
            self?.markDirtyFromObservation()
        }
```

Add `import Observation` to the top of `Window.swift`, after `import Metal`.

**Do not change anything between the tracking session and `present()`.** If `renderRoot(frame)` is not a bare statement at that point, wrap exactly the statement that calls it and leave the surrounding code alone; a diff that also reorders presentation is a diff this task's review cannot separate from the tracking change.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --no-parallel --filter "mutatingAnObservedModelMarksTheWindowDirty|mutatingAnUnreadPropertyDoesNotDirtyTheWindow" 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 7: Run the whole suite unfiltered**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 784 tests in 1 suite passed after …` (782 + 2).

Then confirm no golden moved:

```bash
git status --short -- 'Tests/**/*.json'; find Tests -name "*.json" | wc -l
```
Expected: empty output, and `87`.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUI/Window.swift Tests/MetalUITests/ObservationTests.swift
git commit -m "feat: track the frame build with withObservationTracking

An @Observable property read anywhere during a frame build is now a dependency
of that frame; mutating it marks the window dirty with no opt-in, no
registration and no annotation on the framework side. This closes the single
gap in design spec §4.4 — withObservationTracking appeared nowhere in Sources/.

markDirtyFromObservation is nonisolated because onChange is @Sendable and fires
on the mutating thread. It re-enters the main actor synchronously when already
there and via a Task otherwise. The synchronous branch is load-bearing rather
than an optimisation: the per-frame sentinel flush runs on main, and an
always-hop callback would land after needsRedraw = false and re-dirty every
frame forever.

Three orderings in drawFrameIfNeeded are load-bearing and each is commented
with what breaks if it moves.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 3: The accumulation bound, and the two mutations that prove it

**Files:**
- Modify: `Tests/MetalUITests/ObservationTests.swift`
- Test: same file

**Interfaces:**
- Consumes: `ProbeModel`, `Window.observationDirtyings`, `Window.pausesEntered` from Tasks 1-2.

This is the task the spec calls out as the one that would rot silently: a redundant dirty-marking is behaviourally invisible, so every other test here stays green if the sentinel is removed.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MetalUITests/ObservationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `swift test --no-parallel --filter "theObserverSetIsBoundedRegardlessOfFramesDrawn|aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying|anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame" 2>&1 | tail -20`
Expected: all three PASS. They are written after the implementation deliberately — Task 2's two tests are this spec's red-first pair, and these three are bounds on an implementation that must already exist for the bound to be measurable at all.

- [ ] **Step 3: MUTATION — remove the sentinel, and record what actually happens**

In `Sources/MetalUI/Window.swift`, comment out **both** sentinel lines: the `redrawSentinel.tick &+= 1` write and the `_ = redrawSentinel.tick` read inside the tracked closure.

Run: `swift test --no-parallel 2>&1 | tail -20`

Expected: `theObserverSetIsBoundedRegardlessOfFramesDrawn` FAILS, reporting 200 where 1 was expected.

**Report the actual output, including which OTHER tests failed or did not.** The prediction is that no other test moves; if others do, that is the finding and it goes in the report. Restore both lines afterwards and re-run to confirm green.

- [ ] **Step 4: MUTATION — delete the `isFlushing` guard, and record what actually happens**

In `markDirtyFromObservation`, delete the `guard !self.isFlushing else { return }` line from **both** branches.

Run: `swift test --no-parallel 2>&1 | tail -20`

Expected: `aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying` FAILS reporting 199, and **`idleWindowPausesTheDisplayLinkAndDirtyingResumesIt` stays green** — that is the corrected claim, and confirming it is the point of running this. Report the actual output. Restore and re-run.

- [ ] **Step 5: Run the whole suite unfiltered**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 787 tests in 1 suite passed after …` (784 + 3).

- [ ] **Step 6: Commit**

```bash
git add Tests/MetalUITests/ObservationTests.swift
git commit -m "test: the accumulation bound, the flush guard, and waking a paused window

theObserverSetIsBoundedRegardlessOfFramesDrawn is the assertion this spec
exists to protect: a redundant dirty-marking is behaviourally invisible, so
removing the sentinel leaves every other test green. It is a differential over
two frame counts rather than a single number, because a single-count assertion
cannot distinguish a bounded implementation from an accumulating one.

aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying pins the
isFlushing guard in its corrected form. The spec's first draft claimed deleting
that guard would redden the pre-existing idle test; measured, it reddens
nothing behavioural, and shows up only in the counter.

Both mutations were run rather than predicted; results are in the task report.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 4: The two hop branches, `@State` composition, and the windowed-`List` consequence

**Files:**
- Modify: `Tests/MetalUITests/ObservationTests.swift`
- Test: same file

**Interfaces:**
- Consumes: everything from Tasks 1-3. No production change in this task.

- [ ] **Step 1: Write the tests**

Append to `Tests/MetalUITests/ObservationTests.swift`:

```swift
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
            "the hop must not have completed yet — if this is already true, the \
             off-thread branch is not hopping and MainActor.assumeIsolated \
             would have trapped instead")

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
```

If `window.stateTable` or `StateTable.write(_:_:)` is not reachable under `@testable import MetalUI` with those exact spellings, read `Sources/MetalUI/StateTable.swift` and `Tests/MetalUITests/StateTests.swift` and use whatever spelling `StateTests` already uses to write a value — do **not** widen an access level to make this compile. The assertion is about the two paths being independent, not about any particular write API.

- [ ] **Step 2: Run them**

Run: `swift test --no-parallel --filter "aMainThreadMutationMarksTheWindowDirtySynchronously|anOffThreadMutationMarksTheWindowDirtyAfterAHop|stateAndObservableAreIndependentDirtySources" 2>&1 | tail -20`
Expected: all three PASS.

**If `anOffThreadMutationMarksTheWindowDirtyAfterAHop`'s first `#expect` fails**, the off-thread branch is not being taken. That is a real finding about `Thread.isMainThread` under a detached task on this runtime, not a test to relax: report it, and do not weaken the assertion to make it pass.

- [ ] **Step 3: MUTATION — collapse both branches to the hop, and record what happens**

Replace `markDirtyFromObservation`'s body with only the `Task { @MainActor … }` branch (delete the `Thread.isMainThread` test and the `MainActor.assumeIsolated` branch).

Run: `swift test --no-parallel 2>&1 | tail -30`

Expected: this is the spec's central claim and the one worth seeing fail. `aMainThreadMutationMarksTheWindowDirtySynchronously` must FAIL, and — because the flush's callback now lands *after* `needsRedraw = false` — **the idle tests should fail too**, including the pre-existing `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`.

**Report exactly which tests failed.** If the idle tests stay green, the spec's §4.2 argument is wrong and that is a finding that must be written into the record, not smoothed over. Restore and re-run.

- [ ] **Step 4: Write the `List` consequence test**

Spec §3 records that a windowed `List` does not build off-screen rows, so their model reads are not tracked. Append:

```swift
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

    let (window, _) = try makeFakeWindow(device: device, size: 64) {
        ScrollView(.vertical, elementID: ElementID("list")) {
            List(rows, rowHeight: Pixels(20)) { row in
                Box().background(.surface)
                     .height(Pixels(Float(row.model.label.count)))
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: the window must be clean")

    // Row 199 is far outside a 64pt viewport at offset 0, so its builder never
    // ran and nothing read `models[199].label`.
    rows[199].model.label += "x"

    #expect(!window.needsRedraw,
            "an off-screen row's datum is not a dependency of a frame that \
             never built that row")
    #expect(window.observationDirtyings == 0)
}
```

If this does not compile — a `rowHeight:` label that differs, a `ScrollView` initializer that differs — read `Sources/MetalUI/List.swift` and `Tests/MetalUITests/ListTests.swift` and use the spellings `ListTests` already uses rather than inventing one. The assertion is about tracking, not about the list's own API. Note that `ListTests` writes `px(28)` for its row height, which is a local helper in that file and is **not** available here; `Pixels(20)` is the same thing spelled out.

- [ ] **Step 5: Run the whole suite unfiltered**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 791 tests in 1 suite passed after …` (787 + 4).

```bash
git status --short -- 'Tests/**/*.json'; find Tests -name "*.json" | wc -l
```
Expected: empty, and `87`.

- [ ] **Step 6: Commit**

```bash
git add Tests/MetalUITests/ObservationTests.swift
git commit -m "test: both hop branches, @State composition, and the windowed-List consequence

The two hop tests are branch tests rather than outcome tests: the main-thread
one asserts dirtiness with no await at all, the off-thread one asserts still-
clean immediately and dirty after a yield. Asserting only one half of either
would pass under an implementation that hopped in both cases.

anOffScreenListRowsModelReadIsNotTracked records spec §3's consequence as the
documented behaviour it is. It is the same 'not produced, not seen' mechanism
as divergences 12 and 17, in a third place, and SwiftUI's List does the same
thing — so it is not a divergence.

The branch-collapse mutation was run rather than predicted; results are in the
task report.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 5: The demo — `showModal` onto an `@Observable` model, and the instrumented run

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift` — `showModal` at line 44, its reader around line 674, its writer around line 892

**Interfaces:**
- Consumes: `Window.framesDrawn`, `Window.pausesEntered`, `Window.observationDirtyings`.
- Produces: nothing other code depends on.

The demo hook is deliberately free: no new visible affordance. This one file carries every milestone's exit criteria, and CLAUDE.md records that a per-look affordance taxes every future look.

- [ ] **Step 1: Replace the top-level `var` with an observable model**

`Sources/MetalUIDemo/main.swift:44` currently reads `var showModal = false`. Replace that declaration — keeping the existing explanatory comment block above it — with:

```swift
/// The demo's application model, and the reason it exists is M4 spec 1 rather
/// than the modal.
///
/// `showModal` was a top-level `var` until 2026-09-02. It redrew only because
/// the keymap action that wrote it happened to sit on a path that calls
/// `Window.setNeedsRedraw()` afterwards — the variable itself marked nothing.
/// Moving it onto an `@Observable` model proves the reactivity integration **by
/// removing an explicit dirty-marking**: the action below now mutates the model
/// and nothing else, and the modal still appears.
///
/// That is a stronger demonstration than a new control would be, and it costs
/// the demo no new visible element.
@Observable
final class DemoModel {
    var showModal = false
}

let demoModel = DemoModel()
```

Add `import Observation` to the file's imports.

- [ ] **Step 2: Update the reader and the writer**

Change the `if showModal {` around line 674 to `if demoModel.showModal {`, the `.onClick { showModal = false }` around line 737 to `.onClick { demoModel.showModal = false }`, and the `showModal.toggle()` around line 892 to `demoModel.showModal.toggle()`.

Then run `grep -n "showModal" Sources/MetalUIDemo/main.swift` and confirm **every** remaining occurrence is either `demoModel.showModal` or prose inside a comment. A bare `showModal` left anywhere is a compile error, which is the point — there is no way to half-do this.

- [ ] **Step 3: Remove the now-redundant dirty-marking, if the action has one**

Read the keymap action handler that toggles the modal. If it calls `window.setNeedsRedraw()` explicitly *for the modal's sake*, delete that call — its removal is the demonstration. **If the call also serves another binding on the same path (the theme toggle, for instance), leave it and say so in the task report**: the demonstration then rests on the model write alone being sufficient, which the tests already establish, and forcing the deletion would break an unrelated binding.

- [ ] **Step 4: Add the instrumented summary**

At the point where the demo installs its keymap (near line 889, where `window.theme` is toggled), add a binding on **Q** that prints the counters and terminates, and make the same print run on normal quit:

```swift
    // M4 spec 1's instrument. Every other figure for the idle pause is against
    // the fake platform window; this is the only thing that observes the real
    // CADisplayLink pausing. It is a printed COUNT, not a human judgement —
    // see the spec's §7.
    func printReactivitySummary() {
        print("""

        --- reactivity counters ---
        frames drawn:          \(window.framesDrawn)
        pauses entered:        \(window.pausesEntered)
        observation dirtyings: \(window.observationDirtyings)
        ---------------------------
        """)
    }
    atexit_b { MainActor.assumeIsolated { printReactivitySummary() } }
```

If `atexit_b` is unavailable or trips strict concurrency, use `NSApplication`'s termination path instead — `applicationWillTerminate`, or the existing quit handling the demo's close button already uses. **Do not** spin a timer to print periodically; the summary is once, at exit.

- [ ] **Step 5: Build the demo warning-free**

```bash
swift build --target MetalUIDemo 2>&1 | tee /tmp/demobuild.log | tail -20
grep -ci "warning:" /tmp/demobuild.log
```
Expected: `Build complete!` and `0`.

- [ ] **Step 6: Run the demo and confirm the counters print**

```bash
swift run MetalUIDemo
```

Leave the window untouched for about ten seconds, press **M** twice, then quit. Confirm the summary prints and that **pauses entered is greater than zero** — that is the whole point of the instrument. Record the three numbers in the task report.

If the process cannot be driven interactively in this environment, say so in the report and leave step 6 for the human-verification task rather than substituting a headless proxy. A headless run does not observe a real `CADisplayLink`, which is the only thing this step exists for.

- [ ] **Step 7: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | tail -5`
Expected: `Test run with 791 tests in 1 suite passed after …` — unchanged; this task adds no test.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUIDemo/main.swift
git commit -m "demo: showModal moves onto an @Observable model, plus the counter summary

showModal was a top-level var that marked nothing; it redrew only because the
keymap path that wrote it happens to call setNeedsRedraw afterwards. Moving it
onto an @Observable model demonstrates the integration by REMOVING an explicit
dirty-marking rather than by adding a control — which matters, because this one
file carries every milestone's exit criteria and a new affordance would tax
every future look.

The exit summary prints frames drawn, pauses entered and observation dirtyings.
It is the only instrument that observes a real CADisplayLink pausing; every
other figure in this spec is against the fake platform window.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

### Task 6: The record

**Files:**
- Create: `docs/superpowers/2026-09-02-reactivity-decisions.md`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-08-24-metalui-design.md` — §4.4

**Interfaces:**
- Consumes: every measurement from Tasks 1-5.

- [ ] **Step 1: Write the decisions doc**

Create `docs/superpowers/2026-09-02-reactivity-decisions.md`, following the shape of `docs/superpowers/2026-09-01-tombstones-decisions.md`: one row per ruling, each with its reasoning and what it costs if wrong. **Prefix every ruling `RX-`** and letter them (`RX-A`, `RX-B`, …), matching this project's convention that a bare `RX-3` is a typo rather than a citation.

At minimum, one ruling each for: the sentinel and its measurement; the `isFlushing` guard being kept despite being behaviourally unobservable; the synchronous hop branch being load-bearing for the idle criterion; `hasActiveAnimations` deliberately not declared; the windowed-`List` consequence not being a divergence; and the demo's `showModal` move being chosen over a new affordance.

Include the actual numbers from Tasks 3, 4 and 5's mutation runs, not the ones this plan predicted.

- [ ] **Step 2: Correct design spec §4.4**

`docs/superpowers/specs/2026-08-24-metalui-design.md` §4.4 says `withObservationTracking`'s one-shot nature is "normally an annoyance, here ideal, since we re-register every frame." **That is measurably wrong** and the binding-authority spec must say so.

Add a correction block below that bullet, in the style §4.3 and §9 already use (a `>`-quoted block naming the date, the ruling ids and what changed). State: re-registering every frame accumulates linearly; there is no public cancellation API; the sentinel bounds it; and the measurement. **Correct in place with the original claim visible** — do not silently rewrite the bullet.

- [ ] **Step 3: Update `CLAUDE.md`**

Add, in the appropriate existing sections rather than as a new top-level block:

- A bullet on reactivity beside the `@State` bullet, stating that `@Observable` is now a second independent dirty source, that the tracked region is the whole frame build, and that the sentinel bounds registrations — with the measurement.
- The windowed-`List` consequence in the `List` bullet, as documented behaviour and explicitly **not** a divergence.
- The Build section's climb for this spec: baseline 782, and the per-task figures each task actually read.
- A note that `hasActiveAnimations` does not exist and why, so a reader of §4.4 does not go looking for it.

**Do not add a row to the declared-but-inert table for `pausesEntered` / `observationDirtyings`.** They have production writers and test readers, which is not that table's shape; the `StateTable.isDirty` row is the closest precedent and it is there because it has *no* reader at all.

- [ ] **Step 4: Verify every claim in the record by running it**

For each grep or count this task writes into `CLAUDE.md` or the decisions doc, **run it and paste the real output** rather than carrying a number forward. In particular:

```bash
swift test --no-parallel 2>&1 | tail -3
find Tests -name "*.json" | wc -l
grep -rn "hasActiveAnimations" Sources/ | wc -l
grep -rn "withObservationTracking" Sources/
for f in Tests/MetalUITests/PhaseSeparationTests.swift Tests/MetalUITests/ErasureCompileGuards.swift Tests/MetalUITests/ElementGroupTrapTests.swift Tests/MetalUICoreTests/UnitSafetyTests.swift Tests/MetalUITests/AXNodeTests.swift; do echo -n "$f "; grep -c canTypecheck $f; done
```

Expected: the suite line, `87`, `0`, one or more `Window.swift` hits, and the guard counts summing to 32 (with `UnitSafetyTests` reading 3 because one is a comment).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/
git commit -m "docs: the reactivity record, and a correction to design spec 4.4

The binding-authority spec called withObservationTracking's one-shot behaviour
'ideal, since we re-register every frame'. Measured, that is wrong: it
accumulates one observer per drawn frame per unchanged property, linearly, and
there is no public cancellation API. Corrected in place with the original claim
visible, per this repo's rule about false claims.

Decisions doc carries rulings RX-A onward with the mutation results actually
observed rather than the ones the plan predicted.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FN1rUy2Qkdyd53wiM3pKnK"
```

---

## Expected final state

- **791 tests**, 87 goldens, 32 typecheck guards, warning-free.
- `grep -rn "withObservationTracking" Sources/` returns at least one hit in `Window.swift`.
- `grep -rn "hasActiveAnimations" Sources/` returns **0**.
- No golden file modified or added at any point.
- Design spec §4.4 carries a correction block; `CLAUDE.md` carries the reactivity bullet and the climb.
- M4's "display link paused while idle" criterion is closed for the question it was written to answer, pending the human-run counter report from Task 5 step 6.
