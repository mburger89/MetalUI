import Testing
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
/// **What it does not cover** is the half that is genuinely untestable, and it
/// is the visible half: `AppKitWindow.syncSurfaceGeometry` resizes the
/// `CAMetalLayer` whether or not anyone redraws, so a window whose `onResize`
/// went nowhere would present a *correctly sized* drawable holding the previous
/// frame's pixels — stale content, stretched or letterboxed, until some other
/// event happened to dirty it. No test in this repo can see that; drag the demo
/// window's corner.
@MainActor
@Test func resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeWindow(device: device)

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
    let seen: Counts

    @MainActor final class Counts { var values: [Int] = [] }

    func requestLayout(_ id: GlobalElementID?,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        let node = pass.requestNode(style: style, children: [])
        pass.withState(id, initial: 0) { (value: inout Int) in
            value += 1
            seen.values.append(value)
        }
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
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
