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
                                    startsDisplayLink: false) { scene, _, _ in
        scene.insert(MUIRect(
            bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(10), height: ScaledPixels(10))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(200), height: ScaledPixels(200))),
            background: .white, borderColor: .white,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
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
                                    startsDisplayLink: false) { _, _, _ in }

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
