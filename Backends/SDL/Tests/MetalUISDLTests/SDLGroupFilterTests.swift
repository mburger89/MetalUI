import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture

// R4-5 PR B (rulings `GF-E`, `GF-F`; record 219): a filtered offscreen group on the SDL renderer. The bridge runs the
// downsamples, the two Gaussians and (for a shadow) the tint pass over the group's target, and the quad samples the result;
// the window renderer and the replay path flatten the tree the same way (the filter words ride `ReplayGroup`). Analytic
// pixels as `GroupFilterRenderTests` (Metal); the Metal-to-SDL agreement is parity frame 17.

private let side = 200

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, hue: Float, lightness: Float = 0.5, order: MUIUInt) -> MUIRect {
    MUIRect(bounds: bounds(x, y, w, h), contentMask: bounds(-1000, -1000, 4000, 4000), maskCornerRadii: square,
            background: MUIHsla(h: hue, s: hue == 0 && lightness == 1 ? 0 : 1, l: lightness, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: square,
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: order, shape: 0)
}

private func quad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, order: MUIUInt) -> MUIImage {
    MUIImage(bounds: bounds(x, y, w, h), contentMask: bounds(x, y, w, h), maskCornerRadii: square, opacity: 1,
             texture: 0, filter: MUIUInt(MUIImageFilterNearest.rawValue), order: order)
}

/// A red 20 x 20 square at (40, 40), in a 64 x 64 box at (20, 20).
private func redSquare() -> Scene {
    var inner = Scene()
    inner.insert(rect(40, 40, 20, 20, hue: 0, order: 0))
    inner.finalize()
    return inner
}

private func frame(_ filter: Scene.GroupFilter, inner: Scene? = nil) -> Scene {
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, hue: 0, lightness: 1, order: 0))
    scene.insert(quad(20, 20, 64, 64, order: 1), group: inner ?? redSquare(), filter: filter)
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

@MainActor private func renderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: side, height: side)
}

/// **S1** (`GF-E`). A blurred group (sigma 2) is soft at the square's edge and keeps the square's mass, one filter group and
/// two passes, and the replay path draws the same bytes. Mutations in `filter_group`: the horizontal pass skipped (the
/// vertical edge stays sharp); the vertical one skipped (the horizontal edge).
@MainActor
@Test func aBlurredGroupMatchesMetal() throws {
    let r = try renderer()
    let scene = frame(Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero))
    let pixels = try draw(scene, on: r)
    #expect(near(rgb(pixels, 50, 50), [255, 0, 0], 2), "the centre is the square's red: \(rgb(pixels, 50, 50))")
    let rightEdge = rgb(pixels, 59, 50), bottomEdge = rgb(pixels, 50, 59)
    #expect(rightEdge[1] > 20 && rightEdge[1] < 235, "soft at the right edge (the horizontal pass): \(rightEdge)")
    #expect(bottomEdge[1] > 20 && bottomEdge[1] < 235, "soft at the bottom edge (the vertical pass): \(bottomEdge)")
    var mass = 0
    for y in 20..<84 { for x in 20..<84 { mass += 255 - rgb(pixels, x, y)[1] } }
    #expect(abs(mass - 255 * 400) < 255 * 400 / 50, "the blur keeps the square's mass: \(mass) of \(255 * 400)")
    #expect(r.lastFilteredGroups == 1 && r.lastFilterPasses == 2, "L + 2 passes: \(r.lastFilterPasses)")
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory, driver: SDLWindowRenderer.defaultDriver)
    let replayed = try replayer.render(scene, atlas: GlyphAtlas(width: 16, height: 16), width: side, height: side,
                                       projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    #expect(pixels == replayed, "the window renderer and the replay path draw one frame")
}

/// **S2** (`GF-E`). A shadow group draws the tint (premultiplied (0.5, 0, 0, 0.5)) times the alpha and not the square's
/// own colour: (255, 128, 128) inside, white outside, one tint pass. Mutations: the tint pass skipped (the square's
/// red stays); `filter_kind` dropped from `ReplayGroup` (no filter at all).
@MainActor
@Test func aShadowGroupIsTintedOnTheWindowRenderer() throws {
    let r = try renderer()
    let pixels = try draw(frame(Scene.GroupFilter(kind: .shadow, sigma: 0, tint: SIMD4<Float>(0, 0.5, 0.5, 0.5))), on: r)
    // Premultiplied (0, 0.5, 0.5, 0.5) over white: (127.5, 255, 255) -> (128, 255, 255) red-free cyan tint.
    #expect(near(rgb(pixels, 50, 50), [128, 255, 255], 2), "inside the square: \(rgb(pixels, 50, 50))")
    #expect(near(rgb(pixels, 70, 70), [255, 255, 255]), "outside: \(rgb(pixels, 70, 70))")
    #expect(r.lastFilterPasses == 1, "one tint pass: \(r.lastFilterPasses)")
}

/// **S3** (`GF-E`). A filter whose intermediate cannot be made degrades by name: a blur draws the unfiltered group (the
/// square stays sharp), a shadow nothing; both counted. Mutation: the two fallbacks swapped in `render_groups`.
@MainActor
@Test func aFailedFilterDegradesByName() throws {
    let r = try renderer()
    r.filterPoolFailsAllocation = true
    let blur = try draw(frame(Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero)), on: r)
    #expect(near(rgb(blur, 50, 50), [255, 0, 0]) && near(rgb(blur, 61, 50), [255, 255, 255]), "unfiltered: \(rgb(blur, 61, 50))")
    #expect(r.lastFilterAllocationFailures == 1, "counted: \(r.lastFilterAllocationFailures)")
    let shadow = try draw(frame(Scene.GroupFilter(kind: .shadow, sigma: 0, tint: SIMD4<Float>(0, 0, 0, 1))), on: r)
    #expect(near(rgb(shadow, 50, 50), [255, 255, 255]), "nothing: \(rgb(shadow, 50, 50))")
    #expect(r.lastFilterAllocationFailures == 1, "counted: \(r.lastFilterAllocationFailures)")
}

/// **S4** (`GF-C`). A surface only a group scene references keeps its handle and is drawn with the surface's own fill at
/// the right handle index (shifted past the frame's textures, root surfaces and group quads). Mutation: the surface base
/// not shifted in `SDLGroupSet` (the group samples another handle and draws white or the wrong texture).
@MainActor
@Test func aGroupsSurfaceHandleIsShifted() throws {
    let r = try renderer()
    let target = SurfaceTarget(id: SurfaceID(rawValue: 9), width: 20, height: 20)
    var inner = Scene()
    inner.insert(MUIImage(bounds: bounds(40, 40, 20, 20), contentMask: bounds(40, 40, 20, 20), maskCornerRadii: square, opacity: 1,
                          texture: 0, filter: MUIUInt(MUIImageFilterNearest.rawValue), order: 0), surface: target)
    inner.finalize()
    let scene = frame(Scene.GroupFilter(kind: .blur, sigma: 0, tint: .zero), inner: inner)
    try #require(scene.surfaces.isEmpty && scene.surfaceTargets.isEmpty && scene.groupScenes[0].surfaceTargets == [target], "set up: only the group references it")
    let request = SurfaceDrawRequest(target: target, scaleFactor: 1, time: 0, policy: .onDemand, value: nil) { ctx in
        ctx.clear(red: 0, green: 0, blue: 1, alpha: 1)
    }
    try #require(r.beginFrame() != nil)
    try #require(r.finishFrame(scene: scene, atlas: GlyphAtlas(width: 16, height: 16), surfaces: [request]))
    let pixels = try r.readPixels(width: side, height: side)
    #expect(near(rgb(pixels, 50, 50), [0, 0, 255]), "the surface's fill inside the group: \(rgb(pixels, 50, 50))")
    #expect(r.surfaceTargetsCreated == 1 && r.surfaceTargetsReleased == 0, "the target is kept")
}
