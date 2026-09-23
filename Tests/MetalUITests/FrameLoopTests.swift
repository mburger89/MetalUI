import Testing
import Foundation
import AppKit
import Metal
import MetalUICore
import MetalUIRender
@testable import MetalUI

@MainActor
@Test func windowDrawsOnlyWhenDirty() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let app = try App(device: device)
    let window = try app.openWindow(title: "Loop",
                                    size: Size(width: Pixels(200), height: Pixels(200)),
                                    startsDisplayLink: false) {
        Box().width(Pixels(10)).height(Pixels(10)).background(.accent)
    }

    // `openWindow` paints once eagerly, so the window is already clean and one
    // frame is already on screen — a window that opens occluded (where the
    // display link never fires) must not sit blank.
    #expect(!window.needsRedraw)
    let afterFirst = window.framesDrawn
    #expect(afterFirst == 1)

    // Clean window does no work.
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == afterFirst)

    // Marking dirty schedules exactly one more.
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == afterFirst + 1)
}

@MainActor
@Test func multipleDirtyMarksCoalesceIntoOneFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let app = try App(device: device)
    let window = try app.openWindow(title: "Coalesce",
                                    size: Size(width: Pixels(100), height: Pixels(100)),
                                    startsDisplayLink: false) { Box() }

    let base = window.framesDrawn

    // Many invalidations before the next tick must collapse into one frame, and
    // the ticks that follow must find nothing to do: N dirty marks plus M ticks
    // cost exactly one frame, not N and not M.
    for _ in 0..<5 { window.setNeedsRedraw() }
    for _ in 0..<8 { window.drawFrameIfNeeded() }
    #expect(window.framesDrawn == base + 1)

    // And the window is left clean, so a further burst of ticks is free.
    #expect(!window.needsRedraw)
    for _ in 0..<8 { window.drawFrameIfNeeded() }
    #expect(window.framesDrawn == base + 1)
}

// ---------------------------------------------------------------------------
// Failure, idle and resize paths, driven through test doubles.
//
// The AppKit surface only produces a drawable for a window that is actually on
// screen, so none of these paths is reachable through `App.openWindow`.
// `Window.init` is internal, so `@testable import MetalUI` can inject fakes
// without any production change — see `makeFakeWindow` in `Fakes.swift`.
// ---------------------------------------------------------------------------

@MainActor
private func makeWindow(device: any MTLDevice)
    throws -> (Window, FakePlatformWindow) {
    try makeFakeWindow(device: device) { Box().background(.surface) }
}

/// Spec 3.2: "A skipped frame never clears dirty state." A missing drawable is
/// an everyday condition, so the loop must stay dirty and retry rather than
/// dropping the frame permanently — a window that swallowed the dirty flag here
/// would freeze until the next unrelated input event.
@MainActor
@Test func skippedFrameKeepsDirtyStateAndRetriesSuccessfully() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeWindow(device: device)

    platformWindow.fakeSurface.failsNextFrame = true
    window.drawFrameIfNeeded()

    // The surface was asked, refused, and nothing reached the GPU.
    #expect(platformWindow.fakeSurface.nextFrameCalls == 1)
    #expect(window.framesDrawn == 0)
    #expect(platformWindow.fakeSurface.presentCalls == 0)
    // The dirty flag survived the skip.
    #expect(window.needsRedraw)

    // And the retry actually draws: asserting the flag alone would still pass
    // if the loop had wedged itself into never drawing again.
    platformWindow.fakeSurface.failsNextFrame = false
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 1)
    #expect(platformWindow.fakeSurface.presentCalls == 1)
    #expect(!window.needsRedraw)
}

/// Spec 4.4: an idle window permits display downclocking. The loop must pause
/// the display link when it finds nothing to do, and resume it at every
/// dirty-marking site.
@MainActor
@Test func idleWindowPausesTheDisplayLinkAndDirtyingResumesIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeWindow(device: device)

    // Drain the initial dirty state so the next tick finds a clean window.
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)

    let beforeIdle = platformWindow.pauseCalls.count
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 1)                              // no extra work
    #expect(Array(platformWindow.pauseCalls[beforeIdle...]) == [true])

    // Any dirty mark must un-pause, or the window would stay asleep.
    let beforeDirty = platformWindow.pauseCalls.count
    window.setNeedsRedraw()
    #expect(Array(platformWindow.pauseCalls[beforeDirty...]) == [false])
}

// ---------------------------------------------------------------------------
// Resize, and the state table's owner.
// ---------------------------------------------------------------------------

/// The brief predicted that ignoring the resize event would redden nothing.
/// It reddens this.
///
/// **This one drives the fake; the real AppKit path is covered separately** by
/// `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` below. This test
/// stays because the fake is the only way to choose an arbitrary content size
/// without reaching through `NSApplication.shared.windows`.
///
/// The residual that no test reaches is **one step narrower than an earlier
/// version of this comment claimed**. It said a window whose `onResize` went
/// nowhere "would present a correctly sized drawable holding the previous
/// frame's pixels — no test in this repo can see that". The first half is
/// reachable: the test below asserts precisely that the window is dirtied and
/// reflows. Only the last step is a display property — that the stale pixels are
/// *visible to someone*. Drag the demo window's corner for that one.
@MainActor
@Test func resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    // Stage 6b (`LR-DG`): the root must answer the WINDOW's size at every size
    // this test drives, on both authorities — that is what "lays out at the new
    // size" reads. R-fill (declaring the window's extent on the root) would
    // make the rect follow the declaration rather than the window and hollow
    // the test out, so the root is a greedy flexible frame instead: it fills
    // its proposal under the proposal authority (`FR-A`, `FR-M`) and fills the
    // window under the legacy one (`FR-O`, both maximums infinite), and the
    // background written after the frame paints the frame's box (`OM-C`).
    let (window, platformWindow) = try makeFakeWindow(device: device) {
        Box().frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity)).background(.surface)
    }

    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)
    #expect(window.lastScene.rects[0].bounds.size.width == 64)
    #expect(window.lastScene.rects[0].bounds.size.height == 64)

    // Deliberately non-square, and neither extent equal to the old one: a
    // square target would pass against a window that transposed the two.
    platformWindow.simulateResize(to: Size(width: Pixels(120), height: Pixels(48)))
    #expect(window.needsRedraw, "a resize must mark §4.4's dirty flag")

    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 2)
    #expect(window.lastScene.rects[0].bounds.size.width == 120)
    #expect(window.lastScene.rects[0].bounds.size.height == 48)
}

/// An element that counts how many frames it has been through, via §4.3's
/// cross-frame state.
@MainActor
private struct FrameCounter: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID? = ElementID("counter")
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()
    let seen: Counts

    @MainActor final class Counts { var values: [Int] = [] }

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        // A native leaf since stage 6a (record §38, disposition R); `style` is
        // never set by any caller, so the leaf answers `Style()`'s 0×0.
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID
        pass.withState(id, initial: 0) { (value: inout Int) in
            value += 1
            seen.values.append(value)
        }
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {}
}

/// §4.3, at the level where it can now go wrong for the first time.
///
/// The `StateTable` is owned by the **window** and handed to every `Frame`. A
/// window that let each frame construct its own would give every element fresh
/// state on every frame — an app that silently forgets — and `Frame.init`
/// defaults the parameter, so the mistake is one deleted argument away. Every
/// existing state test builds a single `Frame` by hand and cannot see it.
@MainActor
@Test func crossFrameStateSurvivesFromOneWindowFrameToTheNext() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let counts = FrameCounter.Counts()
    let (window, _) = try makeFakeWindow(device: device) { FrameCounter(seen: counts) }

    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()

    #expect(window.framesDrawn == 3)
    // 1, 2, 3 — not 1, 1, 1, which is what a per-frame table gives.
    #expect(counts.values == [1, 2, 3])
}

/// The resize path end to end, through a **real** `AppKitPlatform` window.
///
/// The fake-driven test above proves `Window` reacts to an `onResize` callback.
/// This proves the callback actually arrives, and that the frame built after it
/// lays out at the new size — the two halves fail separately, and the AppKit
/// half had no coverage at all: deleting `onResize?(contentSize, …)` from
/// `syncSurfaceGeometry` left 297 tests green.
///
/// The scene is in `ScaledPixels`, so the expectation multiplies by the window's
/// own backing scale rather than assuming 1 — on a Retina display a hard-coded
/// 320 would fail for a reason that has nothing to do with resizing.
@MainActor
@Test func aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let app = try App(device: device)
    let title = "Reflow \(UUID().uuidString)"
    let window = try app.openWindow(title: title,
                                    size: Size(width: Pixels(400), height: Pixels(300)),
                                    startsDisplayLink: false) {
        Box().frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity)).background(.surface)
    }
    // Stage 6b (`LR-DG`): the root must answer the WINDOW's size at every size
    // this test drives, on both authorities — that is what "lays out at the new
    // size" reads. R-fill (declaring the window's extent on the root) would
    // make the rect follow the declaration rather than the window and hollow
    // the test out, so the root is a greedy flexible frame instead: it fills
    // its proposal under the proposal authority (`FR-A`, `FR-M`) and fills the
    // window under the legacy one (`FR-O`, both maximums infinite), and the
    // background written after the frame paints the frame's box (`OM-C`).
    let nsWindow = try #require(NSApplication.shared.windows.first { $0.title == title })
    let scale = Float(nsWindow.backingScaleFactor)

    // **Do not close this window.** `App.openWindow` wires `onClose` to
    // `NSApplication.shared.terminate` — M0's "closing the last window must end
    // the process", since there is no app delegate and no menu bar. A tidy
    // `defer { nsWindow.close() }` here ends the *test process* instead: the run
    // exits 0 having silently skipped every test after this one, which is how
    // this comment came to be written. The platform-level tests may close
    // theirs, because `AppKitPlatform.openWindow` sets no `onClose`.

    // `openWindow` paints once eagerly, so the window is already clean.
    #expect(!window.needsRedraw)
    #expect(window.lastScene.rects[0].bounds.size.width == 400 * scale)
    #expect(window.lastScene.rects[0].bounds.size.height == 300 * scale)

    nsWindow.setContentSize(NSSize(width: 320, height: 140))
    #expect(window.needsRedraw, "the real AppKit resize did not reach the window")

    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 2)
    // Non-square, and neither extent shared with the original, so a transposed
    // or stale size reddens rather than coinciding.
    #expect(window.lastScene.rects[0].bounds.size.width == 320 * scale)
    #expect(window.lastScene.rects[0].bounds.size.height == 140 * scale)
}

// ---------------------------------------------------------------------------
// `Window.onInput` — the hook the demo's theme toggle hangs off.
// ---------------------------------------------------------------------------

/// Three claims that fail separately, which is why they are asserted separately:
/// the handler is called with the event, its answer comes back out of
/// `PlatformWindow.onInput`, and the window repaints regardless of that answer.
///
/// **"Comes back out of `PlatformWindow.onInput`" is as far as the answer
/// goes.** The fake returns it to this test; production's `MetalHostView`
/// discards it (`_ = onInput?(…)`, no `super` call), so AppKit never reads it.
///
/// Dropping the forwarding and returning `false` left 297 tests green before
/// this existed — and the demo's space-bar theme toggle, the only interactive
/// feature in the milestone-1 exit criterion, would have died silently.
@MainActor
@Test func inputReachesTheHandlerAndTheAnswerReachesTheHost() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeWindow(device: device)
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)

    var seen: [String] = []
    window.onInput = { event in
        guard case .keyDown(let key) = event else { return false }
        seen.append(key.charactersIgnoringModifiers)
        return key.charactersIgnoringModifiers == " "
    }

    let handled = platformWindow.simulateInput(
        .keyDown(KeyEvent(charactersIgnoringModifiers: " ", characters: " ",
                          timestamp: 0)))
    #expect(seen == [" "], "the event never reached the handler")
    #expect(handled, "the handler's answer did not come back out of PlatformWindow.onInput (production's MetalHostView discards it, so this fake is its only reader)")
    #expect(window.needsRedraw)

    // Unhandled events are forwarded too, and still repaint: the window cannot
    // know whether the handler changed anything, so it must assume it did.
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)

    let unhandled = platformWindow.simulateInput(
        .keyDown(KeyEvent(charactersIgnoringModifiers: "x", characters: "x",
                          timestamp: 0)))
    #expect(seen == [" ", "x"])
    #expect(!unhandled, "an unhandled event was reported as handled")
    #expect(window.needsRedraw)
}

/// The default, with no handler attached. Without this, a `Window` that dropped
/// input entirely would pass the test above by never being asked.
@MainActor
@Test func aWindowWithNoInputHandlerReportsUnhandledAndStillRepaints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platformWindow) = try makeWindow(device: device)
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw)
    #expect(window.onInput == nil)

    let handled = platformWindow.simulateInput(
        .keyDown(KeyEvent(charactersIgnoringModifiers: "q", characters: "q",
                          timestamp: 0)))
    #expect(!handled)
    #expect(window.needsRedraw, "input must dirty the window even with no handler — that is how M0's redraw-on-input behaviour survives")
}
