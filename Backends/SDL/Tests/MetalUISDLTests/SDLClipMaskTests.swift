import Foundation
import Testing
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture

// R4-5 PR C (rulings `CM-A`, `CM-D`; record 220): a masked offscreen group on the SDL renderer. The bridge draws the group's
// mask scene into a scratch target of the group's size under the group's projection, then one pass with the destination-in
// blend (`g->mask`, the `tint` stage at tint 1) multiplies the group's target by the scratch's alpha, before any filter. The
// window renderer and the replay path flatten the mask scene after the group's records like any record's. Analytic pixels as
// `GroupMaskTests` (Metal); the Metal-to-SDL agreement is parity frame 18.

private let side = 200

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, hue: Float, lightness: Float = 0.5, alpha: Float = 1,
                  order: MUIUInt, ellipse: Bool = false) -> MUIRect {
    MUIRect(bounds: bounds(x, y, w, h), contentMask: bounds(-1000, -1000, 4000, 4000), maskCornerRadii: square,
            background: MUIHsla(h: hue, s: hue == 0 && lightness == 1 ? 0 : 1, l: lightness, a: alpha),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: square,
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: order, shape: ellipse ? 1 : 0)
}

private func quad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, order: MUIUInt) -> MUIImage {
    MUIImage(bounds: bounds(x, y, w, h), contentMask: bounds(x, y, w, h), maskCornerRadii: square, opacity: 1,
             texture: 0, filter: MUIUInt(MUIImageFilterNearest.rawValue), order: order)
}

/// A red 80 x 80 square at (60, 50) and the ellipse inscribed in it as the mask, the group's box one pixel larger. The group
/// is not at the origin, so a mask drawn with another projection than the content's lands elsewhere.
private func maskedFrame(mask: Scene? = nil, filter: Scene.GroupFilter = .none) -> Scene {
    var content = Scene()
    content.insert(rect(60, 50, 80, 80, hue: 0, order: 0))
    content.finalize()
    var maskScene = Scene()
    maskScene.insert(rect(60, 50, 80, 80, hue: 0, lightness: 1, order: 0, ellipse: true))
    maskScene.finalize()
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, hue: 0, lightness: 1, order: 0))
    scene.insert(quad(59, 49, 82, 82, order: 1), group: content, filter: filter, mask: mask ?? maskScene)
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

/// **S1** (`CM-A`). A group masked by an ellipse keeps its centre, loses its corner to the background, and the frame ran one
/// group pass and one mask pass; the replay path (the fixture form) draws the same. Mutations in `make_pipeline`: the mask
/// pipeline's blend source-over (the corner stays red and the mask's white paints over the group); the mask pass skipped
/// in `render_groups` (the corner is red).
@MainActor
@Test func aMaskedGroupMatchesMetal() throws {
    let r = try renderer()
    let pixels = try draw(maskedFrame(), on: r)
    #expect(near(rgb(pixels, 100, 90), [255, 0, 0], 2), "the centre is red: \(rgb(pixels, 100, 90))")
    #expect(near(rgb(pixels, 62, 52), [255, 255, 255], 2), "the square's corner is masked away: \(rgb(pixels, 62, 52))")
    #expect(near(rgb(pixels, 20, 20), [255, 255, 255], 2), "outside: \(rgb(pixels, 20, 20))")
    #expect(r.lastGroupPasses == 1 && r.lastMaskPasses == 1 && r.lastMaskFailures == 0,
            "\(r.lastGroupPasses) \(r.lastMaskPasses) \(r.lastMaskFailures)")
    // The ellipse's edge is a coverage ramp, not a step: along y = 62 it crosses x = 71.4.
    let row = (68...75).map { rgb(pixels, $0, 62)[1] }
    #expect(row.contains { $0 > 20 && $0 < 235 }, "anti-aliased edge: \(row)")
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory, driver: SDLWindowRenderer.defaultDriver)
    let replayed = try replayer.render(maskedFrame(), atlas: GlyphAtlas(width: 16, height: 16), width: side, height: side,
                                       projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    #expect(pixels == replayed, "the window renderer and the replay path draw one frame")
}

/// **S1b** (`CM-A`). The mask multiplies **all four channels** by its alpha (the group's colour is premultiplied): a
/// half-transparent mask rect over the whole square leaves the square at half over white. Mutation: the destination factor
/// `one` (the mask does nothing and the square stays full red).
@MainActor
@Test func aHalfTransparentMaskHalvesTheGroup() throws {
    var half = Scene()
    half.insert(rect(60, 50, 80, 80, hue: 0, lightness: 1, alpha: 0.5, order: 0))
    half.finalize()
    let r = try renderer()
    let pixels = try draw(maskedFrame(mask: half), on: r)
    #expect(near(rgb(pixels, 100, 90), [255, 128, 128], 2), "half red over white: \(rgb(pixels, 100, 90))")
}

/// **S1c** (`CM-A`). The mask runs before the filter: a blurred group masked by the ellipse is blurred **after** the cut, so
/// the square's corner, outside the ellipse, stays clear except for the blur's own spill, and the frame ran one mask pass and
/// the filter's passes. Mutation: the mask pass after the filter (the corner is the unmasked blur's red).
@MainActor
@Test func aMaskIsAppliedBeforeTheGroupsFilter() throws {
    let r = try renderer()
    let pixels = try draw(maskedFrame(filter: Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero)), on: r)
    #expect(rgb(pixels, 62, 52)[1] > 200, "the corner is nearly clear: \(rgb(pixels, 62, 52))")
    #expect(near(rgb(pixels, 100, 90), [255, 0, 0], 4), "the centre keeps its red: \(rgb(pixels, 100, 90))")
    #expect(r.lastMaskPasses == 1 && r.lastFilteredGroups == 1, "\(r.lastMaskPasses) \(r.lastFilteredGroups)")
}

/// **S2** (`CM-A`). The flattened group set carries the mask: the mask's runs follow the group's own in the shared run array,
/// `mask_run_start`/`mask_run_count` name them, and the mask rect's transform index is shifted past the root's and the
/// group's like any record's. Mutation: `SDLGroupSet` drops the mask runs (the count reads 0).
@Test func aGroupsMaskRunsAreShifted() throws {
    func translation(_ tx: Float) -> MUITransform {
        MUITransform(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: 0, pixelScale: 1, _reserved: 0,
                     outerMask: bounds(0, 0, 400, 400), outerMaskRadii: square)
    }
    var content = Scene()
    content.insert(rect(60, 50, 20, 20, hue: 0, order: 0), transform: translation(5))
    content.finalize()
    var mask = Scene()
    mask.insert(rect(60, 50, 20, 20, hue: 0, lightness: 1, order: 0, ellipse: true), transform: translation(7))
    mask.finalize()
    var scene = Scene()
    scene.insert(rect(0, 0, 200, 200, hue: 0, lightness: 1, order: 0), transform: translation(1))
    scene.insert(quad(59, 49, 22, 22, order: 1), group: content, mask: mask)
    scene.finalize()
    let set = SDLGroupSet(scene, counts: (scene.rects.count, scene.glyphs.count, scene.images.count + scene.groups.count, scene.transforms.count),
                          mainRunCount: scene.drawList.count, groupTextureBase: 1, textureIndex: { _ in 0 })
    let group = try #require(set.groups.first)
    #expect(group.mask_run_count == 1 && group.mask_run_start == group.run_start + group.run_count,
            "the mask's runs follow the group's: \(group.run_start) \(group.run_count) \(group.mask_run_start) \(group.mask_run_count)")
    #expect(set.rects.count == 2, "the group's rect and the mask's")
    #expect(set.rects.map { $0.shape >> 8 } == [2, 3], "transform indices past the root's one and the group's: \(set.rects.map { $0.shape >> 8 })")
    #expect(set.transforms.count == 2)
    let maskRun = Int(group.mask_run_start) - scene.drawList.count
    try #require(set.runs.indices.contains(maskRun), "the mask's run is in the shared run array: \(set.runs.count) runs")
    #expect(set.runs[maskRun].start == UInt32(scene.rects.count + 1))
}

/// **S5** (`CM-A`). A mask whose scratch cannot be made (the hook; without portable shaders the same branch) draws the group
/// **unmasked, by name**: the corner shows the content's red (the bounding clip is the caller's), `lastMaskFailures` is 1 and
/// `lastMaskPasses` 0. Mutation: the degrade path draws nothing (the centre turns white).
@MainActor
@Test func aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName() throws {
    let r = try renderer()
    r.maskPoolFailsAllocation = true
    let pixels = try draw(maskedFrame(), on: r)
    #expect(near(rgb(pixels, 100, 90), [255, 0, 0], 2), "the centre is still red: \(rgb(pixels, 100, 90))")
    #expect(near(rgb(pixels, 62, 52), [255, 0, 0], 2), "the corner is unmasked: \(rgb(pixels, 62, 52))")
    #expect(r.lastMaskPasses == 0 && r.lastMaskFailures == 1, "\(r.lastMaskPasses) \(r.lastMaskFailures)")
    r.maskPoolFailsAllocation = false
    let again = try draw(maskedFrame(), on: r)
    #expect(near(rgb(again, 62, 52), [255, 255, 255], 2), "the next frame masks again: \(rgb(again, 62, 52))")
}
