import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIDemoContent
@testable import MetalUI
@testable import MetalUIRender

// Round 2 item 5 (`DT-A`, `DT-B`, `DT-C`, `DT-F`; record 141): the Metal half of `drawText`. A real
// `Window` over `FakePlatformWindow`, whose renderer is a real `MetalWindowRenderer` drawing into a
// `.shared` texture the test reads back. The surface's draw calls `drawText` on the context the
// renderer hands it; the renderer then runs one MetalUI-owned pass per surface that recorded text.
// No test sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ResolvedHolder {
    var value: TextMeasurer.ResolvedText?
}

private struct Reading: Component {
    let holder: ResolvedHolder
    let text: Text
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = holder.value = measurer.resolve(text)
        Box().frame(width: 1, height: 1)
    }
}

@MainActor private final class Count { var value = 0 }

/// `side` x `side` device pixels at `scale`, `build` run with the surface.
@MainActor private func window<Root: Element>(side: Int = 64, scale: Float = 1,
                                              _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: side, content: content)
    if scale != 1 {
        platform.scaleFactor = scale
        platform.fakeSurface.scaleFactor = scale
        platform.simulateResize(to: Size(width: px(Float(side) / scale), height: px(Float(side) / scale)))
    }
    return (window, platform)
}

/// A window whose surface fills it and draws `text` at `point` (topLeading) over `prelude`.
@MainActor private func surfaceWindow(_ text: Text, at point: Point<Pixels>, side: Int = 64, scale: Float = 1,
                                      calls: Count = Count(), drawsText: Bool = true,
                                      prelude: (@MainActor (any GPUSurfaceContext) -> Void)? = nil) throws
    -> (Window, FakePlatformWindow) {
    let holder = ResolvedHolder()
    let extent = px(Float(side) / scale)
    return try window(side: side, scale: scale) {
        ZStack(alignment: .topLeading) {
            Reading(holder: holder, text: text)
            GPUSurface(redraw: .onDemand) { ctx in
                calls.value += 1
                prelude?(ctx)
                if drawsText, let resolved = holder.value { ctx.drawText(resolved, at: point, anchor: .topLeading) }
            }
            .frame(width: extent, height: extent)
        }
        .frame(width: extent, height: extent)
    }
}

/// The same text as an ordinary `Text` at `point`.
@MainActor private func textWindow(_ text: Text, at point: Point<Pixels>, side: Int = 64, scale: Float = 1) throws
    -> (Window, FakePlatformWindow) {
    let extent = px(Float(side) / scale)
    return try window(side: side, scale: scale) {
        text.proposalLayout().padding(Edges(top: point.y, right: px(0), bottom: px(0), left: point.x))
            .frame(width: extent, height: extent, alignment: .topLeading)
    }
}

private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int, side: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

@MainActor private func label() -> Text { Text("Hg 42") }

/// **7** (`DT-C`, `DT-J`). The surface's text reads back equal to the same `Text` drawn by MetalUI at that
/// device position, premultiplied bytes over a transparent clear on both sides, at scale 1 and 2.
/// Mutation: the pass's viewport is the window's size, not the target's (the pixels shift).
@Test @MainActor func aSurfaceTextReadsBackEqualToTheSameTextDrawnByMetalUI() throws {
    for (point, scale) in [(Point(x: px(4), y: px(3)), Float(1)), (Point(x: px(2), y: px(1)), Float(2))] {
        let (surface, surfacePlatform) = try surfaceWindow(label(), at: point, side: 96, scale: scale)
        let (plain, plainPlatform) = try textWindow(label(), at: point, side: 96, scale: scale)
        surface.drawFrameIfNeeded()
        plain.drawFrameIfNeeded()
        let a = surfacePlatform.fakeSurface.readPixels(), b = plainPlatform.fakeSurface.readPixels()
        try #require(b.contains { $0 != 0 }, "set up: the plain Text drew ink at scale \(scale)")
        let diff = a.indices.filter { a[$0] != b[$0] }
        let inkA = stride(from: 3, to: a.count, by: 4).filter { a[$0] != 0 }.count
        let inkB = stride(from: 3, to: b.count, by: 4).filter { b[$0] != 0 }.count
        let maxDelta = diff.map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0
        let xs = diff.map { ($0 / 4) % 64 }, ys = diff.map { ($0 / 4) / 64 }
        #expect(a == b, """
            scale \(scale): \(diff.count) bytes differ, max delta \(maxDelta), ink pixels \(inkA) vs \(inkB), \
            x \(xs.min() ?? 0)...\(xs.max() ?? 0) y \(ys.min() ?? 0)...\(ys.max() ?? 0)
            """)
    }
}

/// **8** (`DT-A`). The text is drawn over the app's own drawing: the app clears opaque red, then `drawText`;
/// the red survives away from the ink and the ink is on top. Mutation: the text pass's load action `.clear`.
@Test @MainActor func textIsDrawnOverTheAppsOwnDrawing() throws {
    let (window, platform) = try surfaceWindow(label(), at: Point(x: px(4), y: px(3))) { ctx in
        ctx.clear(red: 1, green: 0, blue: 0, alpha: 1)
    }
    window.drawFrameIfNeeded()
    let pixels = platform.fakeSurface.readPixels()
    #expect(rgba(pixels, 60, 60, side: 64) == [255, 0, 0, 255], "the app's red survives away from the text")
    let inked = (0..<64).flatMap { y in (0..<64).map { x in rgba(pixels, x, y, side: 64) } }
        .filter { $0 != [255, 0, 0, 255] }
    #expect(!inked.isEmpty, "the text is drawn on top of the red")
}

/// **9** (`DT-B`). A glyph first inserted by a surface draw is uploaded before the text pass: the
/// readback of a first frame whose only glyphs come from `drawText` is not blank. Mutation: move
/// `renderer.upload` back before the draws (blank glyphs).
@Test @MainActor func aGlyphFirstInsertedByASurfaceDrawIsUploadedBeforeTheTextPass() throws {
    let (window, platform) = try surfaceWindow(Text("Wq"), at: Point(x: px(4), y: px(3)))
    window.drawFrameIfNeeded()
    try #require(window.lastScene.glyphs.isEmpty, "set up: the scene has no glyph of its own")
    let pixels = platform.fakeSurface.readPixels()
    #expect(pixels.contains { $0 != 0 }, "the first frame shows the surface's text")
    #expect(platform.windowRenderer.renderer.lastSurfaceTextPasses == 1)
}

/// **10** (`DT-A`, `DT-B`). A frame with no surface text runs no text pass and one upload; the control
/// frame with text runs one pass and still one upload. Mutation: always run a (empty) pass.
@Test @MainActor func aFrameWithNoSurfaceTextRunsNoTextPassAndOneUpload() throws {
    let (without, platformWithout) = try surfaceWindow(label(), at: Point(x: px(4), y: px(3)), drawsText: false) { ctx in
        ctx.clear(red: 0, green: 0, blue: 1, alpha: 1)
    }
    let before = platformWithout.windowRenderer.renderer.uploadCalls
    without.drawFrameIfNeeded()
    let renderer = platformWithout.windowRenderer.renderer
    #expect(renderer.lastSurfaceTextPasses == 0, "no text, no pass")
    #expect(renderer.uploadCalls - before == 1, "one upload per frame")
    let (with, platformWith) = try surfaceWindow(label(), at: Point(x: px(4), y: px(3)))
    let beforeWith = platformWith.windowRenderer.renderer.uploadCalls
    with.drawFrameIfNeeded()
    #expect(platformWith.windowRenderer.renderer.lastSurfaceTextPasses == 1)
    #expect(platformWith.windowRenderer.renderer.uploadCalls - beforeWith == 1, "still one upload per frame")
}

/// **11** (`DT-A`, `MV-F`). The text pass adds no submission: the frame's one command buffer is committed
/// once (a second commit traps) and completes. Mutation: commit inside the pass helper.
@Test @MainActor func theTextPassAddsNoSubmission() throws {
    let (window, platform) = try surfaceWindow(label(), at: Point(x: px(4), y: px(3)))
    window.drawFrameIfNeeded()
    let buffer = try #require(platform.fakeSurface.lastCommandBuffer)
    buffer.waitUntilCompleted()
    #expect(buffer.status == .completed, "committed exactly once and ran: \(buffer.status.rawValue)")
    #expect(platform.windowRenderer.renderer.lastSurfaceTextPasses == 1)
}
