import Foundation
import Testing
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture

// R4-5 PR A (rulings `GO-E`, `GO-F`; record 218): offscreen opacity groups on the SDL renderer. The group is rendered
// by the bridge into a pooled target with a post-NDC translation as the projection, then drawn back as an image quad;
// the window renderer and the replay path flatten the tree the same way. Analytic pixels as `GroupSceneTests` (Metal).

private let side = 200

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, hue: Float, lightness: Float = 0.5, order: MUIUInt) -> MUIRect {
    MUIRect(bounds: bounds(x, y, w, h), contentMask: bounds(0, 0, 400, 400), maskCornerRadii: square,
            background: MUIHsla(h: hue, s: hue == 0 && lightness == 1 ? 0 : 1, l: lightness, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: square,
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: order, shape: 0)
}

private func quad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, opacity: Float, order: MUIUInt) -> MUIImage {
    MUIImage(bounds: bounds(x, y, w, h), contentMask: bounds(x, y, w, h), maskCornerRadii: square, opacity: opacity,
             texture: 0, filter: MUIUInt(MUIImageFilterNearest.rawValue), order: order)
}

private func overlap() -> Scene {
    var inner = Scene()
    inner.insert(rect(90, 80, 60, 60, hue: 2.0 / 3.0, order: 0))
    inner.insert(rect(60, 50, 60, 60, hue: 0, order: 1))
    inner.finalize()
    return inner
}

private func groupFrame() -> Scene {
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, hue: 0, lightness: 1, order: 0))
    scene.insert(quad(59, 49, 92, 92, opacity: 0.5, order: 1), group: overlap())
    scene.finalize()
    return scene
}

private func rgb(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * side + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i])]
}
private func near(_ a: [Int], _ b: [Int], _ t: Int = 1) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) <= t } }

@MainActor private func draw(_ scene: Scene, on renderer: SDLWindowRenderer) throws -> [UInt8] {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: GlyphAtlas(width: 16, height: 16)))
    return try renderer.readPixels(width: side, height: side)
}

/// **GO-F.** The window renderer composites a group: the overlap reads the top colour over white, (255, 128, 128), one
/// group pass, and the replay path (the one `PortableReplay` holds to the Metal pixels) draws the same bytes.
/// Mutations in `render_groups`: the projection's x or y negated; a `LOAD` rather than `CLEAR` pass; the quad's texture
/// index not offset by the frame's handles.
@MainActor
@Test func aGroupCompositesItsOverlapOnTheWindowRenderer() throws {
    let renderer = try SDLWindowRenderer(offscreenWidth: side, height: side)
    let pixels = try draw(groupFrame(), on: renderer)
    #expect(near(rgb(pixels, 100, 90), [255, 128, 128]), "overlap: \(rgb(pixels, 100, 90))")
    #expect(near(rgb(pixels, 140, 130), [128, 128, 255]), "blue only: \(rgb(pixels, 140, 130))")
    #expect(near(rgb(pixels, 55, 90), [255, 255, 255]), "outside the box: \(rgb(pixels, 55, 90))")
    #expect(renderer.lastGroupPasses == 1, "passes: \(renderer.lastGroupPasses)")
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory, driver: SDLWindowRenderer.defaultDriver)
    let replayed = try replayer.render(groupFrame(), atlas: GlyphAtlas(width: 16, height: 16), width: side, height: side,
                                       projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    #expect(pixels == replayed, "the window renderer and the replay path draw one frame")
}

/// **GO-F.** A group inside a group takes two passes; a steady second frame makes no texture; a frame with no group
/// takes none. Mutation: the pool keyed by width only (two targets of one width and two heights alias).
@MainActor
@Test func nestedGroupsTakeTwoPassesAndASteadyFrameMakesNoTexture() throws {
    var middle = Scene()
    middle.insert(rect(100, 100, 30, 30, hue: 2.0 / 3.0, order: 0))
    middle.insert(quad(59, 49, 92, 92, opacity: 0.5, order: 1), group: overlap())
    middle.finalize()
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, hue: 0, lightness: 1, order: 0))
    scene.insert(quad(50, 40, 120, 120, opacity: 0.5, order: 1), group: middle)
    scene.finalize()
    let renderer = try SDLWindowRenderer(offscreenWidth: side, height: side)
    let first = try draw(scene, on: renderer)
    #expect(renderer.lastGroupPasses == 2, "passes: \(renderer.lastGroupPasses)")
    #expect(renderer.lastGroupTexturesMade == 2, "made: \(renderer.lastGroupTexturesMade)")
    #expect(near(rgb(first, 70, 60), [255, 191, 191], 2), "twice faded: \(rgb(first, 70, 60))")
    let second = try draw(scene, on: renderer)
    #expect(renderer.lastGroupTexturesMade == 0, "steady: \(renderer.lastGroupTexturesMade)")
    #expect(first == second)
    _ = try draw(Scene(), on: renderer)
    #expect(renderer.lastGroupPasses == 0)
}

/// **GO-F.** A group whose target cannot be made draws nothing, counted; the rest of the frame draws.
@MainActor
@Test func aGroupWithoutATargetDrawsNothingOnTheWindowRenderer() throws {
    let renderer = try SDLWindowRenderer(offscreenWidth: side, height: side)
    renderer.groupPoolFailsAllocation = true
    let pixels = try draw(groupFrame(), on: renderer)
    #expect(near(rgb(pixels, 100, 90), [255, 255, 255]), "the background only: \(rgb(pixels, 100, 90))")
    #expect(renderer.lastGroupAllocationFailures == 1 && renderer.lastGroupPasses == 0)
}
