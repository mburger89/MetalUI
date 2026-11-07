import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
import MetalUIScene
@testable import MetalUI

// R4-5 PR B (`GF-C`, `GF-E`; divergence 167). The Metal half of a surface inside a filtered group: the window renderer
// keeps and resolves the target of a surface that only a group scene references, and the blur reads it. A real `Window` over
// `FakePlatformWindow` with a real `MetalWindowRenderer` (the `MetalViewTests` harness).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int, side: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// **R6** (`GF-C`). A blurred `GPUSurface` is blurred on Metal: the window's target table keeps the surface's target alive
/// (released count 0 over three frames, one target created: the surface is referenced only by the group scene), its centre is
/// still the app's red and its edge is soft. Mutations: `references:` reading the root scene only (the target is released
/// and recreated every frame); the target lookup returning nil (nothing drawn).
@Test @MainActor func aSurfaceInsideAGroupKeepsItsTarget() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 64, startsDisplayLink: false) {
        GPUSurface(draw: { ctx in ctx.clear(red: 1, green: 0, blue: 0, alpha: 1) }).frame(width: px(20), height: px(20))
            .blur(radius: px(2))
    }
    window.drawFrameIfNeeded()
    for _ in 0..<2 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    let scene = window.lastScene
    try #require(scene.surfaces.isEmpty && scene.groups.count == 1, "set up: the surface lives in a blur group")
    let table = platform.windowRenderer.surfaceTable
    #expect(table.createdCount == 1 && table.releasedCount == 0, "one target, kept: \(table.createdCount) created, \(table.releasedCount) released")
    let quad = scene.groups[0]
    let pixels = platform.fakeSurface.readPixels()
    let cx = Int(quad.bounds.origin.x + quad.bounds.size.width / 2), cy = Int(quad.bounds.origin.y + quad.bounds.size.height / 2)
    let centre = rgba(pixels, cx, cy, side: 64)
    #expect(centre[0] > 240 && centre[3] > 240, "the app's red at the centre: \(centre)")
    let edge = rgba(pixels, cx - 10, cy, side: 64)
    #expect(edge[3] > 40 && edge[3] < 215, "a soft edge: \(edge)")
}
