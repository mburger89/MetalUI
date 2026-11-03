import Testing
import Metal
import Foundation
import MetalUICore
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// 3D render effects, the renderer's side (ruling `PJ-A`): a transform record whose lane 4 `(g, h, i, det3)` has
// `det3 != 0` is projective. The vertex stage emits the homogeneous clip point, so the rasteriser interpolates the
// local position perspective-correctly; the fragment recomputes the scale `sqrt(|det3| / w^3)` and the screen point
// from it. Expected values are derived from the geometry in each comment, in pixels of a 100 x 100 target.

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3]))
}

private func mb(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}

private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

private let whole = mb(0, 0, 4096, 4096)

/// A projective record: `w = g x + h y + i`, `(x', y') = (a x + c y + tx, b x + d y + ty) / w`; `det3` is the 3 x 3 determinant.
func projectiveRecord(a: Float = 1, b: Float = 0, c: Float = 0, d: Float = 1, tx: Float = 0, ty: Float = 0,
                      g: Float, h: Float = 0, i: Float = 1, outer: MUIBounds = whole) -> MUITransform {
    let det3 = a * (d * i - ty * h) - c * (b * i - ty * g) + tx * (b * h - d * g)
    return MUITransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty, pixelScale: abs(det3).squareRoot(), _reserved: 0,
                        outerMask: outer, outerMaskRadii: corners(0), g: g, h: h, i: i, det3: det3)
}

private func rect(_ b: MUIBounds, color: MUIHsla = MUIHsla(h: 0, s: 1, l: 0.5, a: 1), mask: MUIBounds = mb(0, 0, 4096, 4096),
                  radius: Float = 0, shape: UInt32 = 0) -> MUIRect {
    MUIRect(bounds: b, contentMask: mask, maskCornerRadii: corners(0), background: color,
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: corners(radius),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: shape)
}

@MainActor
private func render(_ scene: Scene, size: Int = 100, atlas: GlyphAtlas? = nil) throws -> [UInt8] {
    var scene = scene
    scene.finalize()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    if let atlas { renderer.upload(atlas) }
    return try renderer.renderOffscreen(scene, size: Size(width: DevicePixels(Int32(size)), height: DevicePixels(Int32(size))))
}

/// `w = 1 + 0.003 x`: a rect at local x 20...120, y 40...120 lands on the trapezoid x' = x / w, y' = y / w. Its left edge is
/// x' = 18.87 (y' 37.7...113.2), its right edge x' = 88.24 (y' 29.4...88.2). The bounding box's lower right (85, 95) is
/// outside the trapezoid, (85, 40) inside. Mutation: emit `W = 1` in `projective_clip` (the quad is then the numerators').
@Test @MainActor func aProjectedRectCoversItsTrapezoidAndNotItsBounds() throws {
    var scene = Scene()
    scene.insert(rect(mb(20, 40, 100, 80)), transform: projectiveRecord(g: 0.003))
    let p = try render(scene)
    #expect(pixel(p, 85, 40, width: 100).a == 255, "inside the far edge")
    #expect(pixel(p, 85, 95, width: 100).a == 0, "inside the bounding box, outside the trapezoid")
    #expect(pixel(p, 50, 60, width: 100).a == 255)
    #expect(pixel(p, 10, 60, width: 100).a == 0, "left of the near edge")
}

/// The same trapezoid: its vertical edges are x' = 18.87 and 88.24 at every height, so the edge pixels hold a coverage the
/// analytic distance gives: pixel 18 about 0.13 (alpha 34) and pixel 88 about 0.24 (alpha 60, the edge at 88.24), within the
/// isotropic scale's error; a constant `pixelScale` (1) would make the far edge pixel 3. Mutation: `projective_scale` returns
/// `t.pixelScale`.
@Test @MainActor func aProjectedEdgeAntialiasesOverOneScreenPixelAtBothDepths() throws {
    var scene = Scene()
    scene.insert(rect(mb(20, 40, 100, 80)), transform: projectiveRecord(g: 0.003))
    let p = try render(scene)
    let near = pixel(p, 18, 60, width: 100).a, far = pixel(p, 88, 60, width: 100).a
    #expect(abs(near - 34) <= 14, "near edge pixel alpha \(near)")
    #expect(abs(far - 60) <= 20, "far edge pixel alpha \(far)")
    #expect(pixel(p, 17, 60, width: 100).a <= 4 && pixel(p, 19, 60, width: 100).a >= 250, "one pixel wide")
    #expect(pixel(p, 87, 60, width: 100).a >= 250 && pixel(p, 89, 60, width: 100).a <= 4, "one pixel wide at the far edge")
}

/// A 2 x 1 nearest image, red left and blue right, over local x 0...100, y 20...60 with `w = 1 + 0.01 x`: the texel boundary
/// is local x 50, screen 33.3 (perspective-correct); an affine interpolation would put it at the screen midpoint 25. Pixel 29 is
/// red, pixel 37 blue. Mutation: `[[center_no_perspective]]` on the UV varying.
@Test @MainActor func aProjectedImageSamplesPerspectiveCorrect() throws {
    var scene = Scene()
    let two = ImageTexture(width: 2, height: 1, straightRGBA: [255, 0, 0, 255, 0, 0, 255, 255])
    scene.insert(MUIImage(bounds: mb(0, 20, 100, 40), contentMask: whole, maskCornerRadii: corners(0), opacity: 1, texture: 0,
                          filter: ImageFilter.nearest.rawValue, order: 0),
                 texture: two, transform: projectiveRecord(g: 0.01))
    let p = try render(scene)
    let at29 = pixel(p, 29, 25, width: 100), at37 = pixel(p, 37, 25, width: 100)
    #expect(at29.r > 200 && at29.b < 50, "red at 29: \(at29)")
    #expect(at37.b > 200 && at37.r < 50, "blue at 37: \(at37)")
}

/// The outer mask is a screen rectangle, tested at the pixel's own screen point: `w = 1 + 0.01 x`, a rect over local
/// x 0...100 covers screen x 0...50, and an outer mask x >= 30 cuts it there. Pixel 27 is empty, 33 covered; the
/// interpolated `screenPosition` is not linear in screen space and would move the cut. Mutation: read `in.screenPosition` in
/// the projective fragment.
@Test @MainActor func theOuterMaskUnderAProjectionIsTestedAtTheScreenPoint() throws {
    var scene = Scene()
    scene.insert(rect(mb(0, 10, 100, 80)), transform: projectiveRecord(g: 0.01, outer: mb(30, 0, 70, 100)))
    let p = try render(scene)
    #expect(pixel(p, 26, 50, width: 100).a == 0, "left of the cut")
    #expect(pixel(p, 34, 50, width: 100).a == 255, "right of the cut")
    #expect(abs(pixel(p, 30, 50, width: 100).a - 128) <= 40 || pixel(p, 29, 50, width: 100).a < 255, "the cut is at x = 30")
}

/// A projective record that is the affine one written twice as large (every number doubled, `w = 2` everywhere) draws what the
/// affine record draws, within one level per channel: the fragment's `sqrt(|det3| / w^3)` is the affine `pixelScale`. Mutation:
/// `w * w` for `w * w * w` in `projective_scale` (a different exponent).
@Test @MainActor func aForcedProjectiveIdentityRowMatchesTheAffineBranch() throws {
    let atlas = GlyphAtlas(width: 32, height: 32)
    let font = FontKey(resolvedPostScriptName: "ProjectivePin", size: 10, variations: [],
                       matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    atlas.beginFrame()
    let slot = atlas.packed(for: GlyphKey(font: font, glyph: 1, size: 10, subpixelVariant: 0, scaleFactor: 1)) {
        GlyphImage(width: 7, height: 9, bytes: (0..<63).map { UInt8(($0 * 37 + 11) % 256) })
    }!.slot
    atlas.endFrame()
    func scene(projective: Bool) -> Scene {
        // A rotation by 30 degrees about (50, 50).
        let c: Float = 0.8660254, s: Float = 0.5
        let a = c, b = s, cc = -s, d = c
        let tx = 50 - c * 50 + s * 50, ty = 50 - s * 50 - c * 50
        let record: MUITransform = projective
            ? MUITransform(a: 2 * a, b: 2 * b, c: 2 * cc, d: 2 * d, tx: 2 * tx, ty: 2 * ty, pixelScale: 1, _reserved: 0,
                           outerMask: whole, outerMaskRadii: corners(0), g: 0, h: 0, i: 2,
                           det3: 8 * (a * d - b * cc))
            : MUITransform(a: a, b: b, c: cc, d: d, tx: tx, ty: ty, pixelScale: 1, _reserved: 0,
                           outerMask: whole, outerMaskRadii: corners(0))
        var scene = Scene()
        scene.insert(rect(mb(20.25, 30.5, 60, 30), radius: 8), transform: record)
        scene.insert(rect(mb(25.5, 55.25, 40, 25), color: MUIHsla(h: 0.6, s: 0.7, l: 0.5, a: 0.9), shape: 1), transform: record)
        let ramp = ImageTexture(width: 4, height: 3, straightRGBA: (0..<48).map { UInt8(($0 * 53) % 256) })
        scene.insert(MUIImage(bounds: mb(40.5, 20.25, 30, 20), contentMask: whole, maskCornerRadii: corners(0), opacity: 1,
                              texture: 0, filter: ImageFilter.linear.rawValue, order: 0), texture: ramp, transform: record)
        scene.insert(MUIGlyph(bounds: Bounds(origin: Point(x: ScaledPixels(30.5), y: ScaledPixels(40.25)),
                                             size: Size(width: ScaledPixels(7), height: ScaledPixels(9))),
                              slot: slot, contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                                              size: Size(width: ScaledPixels(4096), height: ScaledPixels(4096))),
                              maskCornerRadii: Corners(all: ScaledPixels(0)), color: Hsla(h: 0, s: 0, l: 0.1, a: 1), order: 0),
                     transform: record)
        return scene
    }
    let affine = try render(scene(projective: false), atlas: atlas), projective = try render(scene(projective: true), atlas: atlas)
    var worst = 0
    for i in 0..<affine.count { worst = max(worst, abs(Int(affine[i]) - Int(projective[i]))) }
    #expect(worst <= 1, "largest channel difference \(worst)")
    try #require(affine.contains { $0 != 0 }, "the scene draws something")
}
