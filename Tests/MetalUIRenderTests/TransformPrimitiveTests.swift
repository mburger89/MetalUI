import Testing
import Metal
import Foundation
import MetalUICore
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// Lane 1 of paths, shadows and transforms (ruling GX-F): rects, ellipses,
// glyphs and images carry an affine per instance, read from the scene's
// `MUITransform` table through an index in a word each primitive already has
// (`MUIRect.shape`/`MUIImage.filter` bits 8…31, `MUIGlyph.transform`). Index
// 0 runs today's code. Expected values are derived before each run from the
// geometry in the comment above the test.

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3]))
}

private func mb(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}

private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

/// A transform record: `x' = a x + c y + tx`, `y' = b x + d y + ty`, its
/// `pixelScale` `sqrt|ad − bc|`, its outer mask the whole 200×200 target
/// unless given.
func transformRecord(a: Float, b: Float, c: Float, d: Float, tx: Float, ty: Float,
                     outer: MUIBounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4096, height: 4096)),
                     outerRadius: Float = 0) -> MUITransform {
    let det = a * d - b * c
    return MUITransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty, pixelScale: abs(det).squareRoot(), _reserved: 0,
                        outerMask: outer,
                        outerMaskRadii: MUICorners(topLeft: outerRadius, topRight: outerRadius,
                                                   bottomRight: outerRadius, bottomLeft: outerRadius))
}

/// A quarter turn clockwise (y-down) about (cx, cy): local (x, y) →
/// (cx + cy − y, cy − cx + x). Exact: no trigonometry.
private func quarterTurn(about cx: Float, _ cy: Float, outer: MUIBounds? = nil) -> MUITransform {
    outer.map { transformRecord(a: 0, b: 1, c: -1, d: 0, tx: cx + cy, ty: cy - cx, outer: $0) }
        ?? transformRecord(a: 0, b: 1, c: -1, d: 0, tx: cx + cy, ty: cy - cx)
}

/// A rotation by `degrees` (positive clockwise, y-down) about (cx, cy).
private func rotation(_ degrees: Double, about cx: Float, _ cy: Float) -> MUITransform {
    let r = degrees * Double.pi / 180
    let c = Float(cos(r)), s = Float(sin(r))
    return transformRecord(a: c, b: s, c: -s, d: c, tx: cx - c * cx + s * cy, ty: cy - s * cx - c * cy)
}

private func solidRect(_ b: MUIBounds, mask: MUIBounds = mb(0, 0, 200, 200), maskRadius: Float = 0,
                       shape: UInt32 = 0, border: Float = 0) -> MUIRect {
    MUIRect(bounds: b, contentMask: mask, maskCornerRadii: corners(maskRadius),
            background: MUIHsla(h: 0, s: 0, l: 0, a: 1), borderColor: MUIHsla(h: 0, s: 1, l: 0.5, a: 1),
            cornerRadii: corners(0), borderWidths: MUIEdges(top: border, right: border, bottom: border, left: border),
            order: 0, shape: shape)
}

@MainActor
private func render(_ scene: Scene, width: Int = 200, height: Int = 200, atlas: GlyphAtlas? = nil) throws -> [UInt8] {
    var scene = scene
    scene.finalize()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    if let atlas { renderer.upload(atlas) }
    return try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(width)), height: DevicePixels(Int32(height))))
}

/// 1.1 — a 160×20 rect centred in 200×200 (local x 20…180, y 90…110), under
/// a quarter turn about the centre, covers x 90…110, y 20…180: (100, 40) is
/// inside the drawn bar and (40, 100) — inside its untransformed bounds — is
/// not. The identity arm reads the opposite; the two arms must disagree.
@Test @MainActor func aRotatedRectCoversItsRotatedOutlineAndNotItsBounds() throws {
    var turned = Scene()
    turned.insert(solidRect(mb(20, 90, 160, 20)), transform: quarterTurn(about: 100, 100))
    var plain = Scene()
    plain.insert(solidRect(mb(20, 90, 160, 20)))
    let t = try render(turned), p = try render(plain)
    #expect(pixel(t, 100, 40, width: 200).a == 255, "the rotated bar covers (100, 40)")
    #expect(pixel(t, 40, 100, width: 200).a == 0, "the rotated bar leaves its old bounds")
    #expect(pixel(p, 100, 40, width: 200).a == 0)
    #expect(pixel(p, 40, 100, width: 200).a == 255)
    try #require(t != p, "the arms must disagree")
}

/// FNV-1a over a buffer.
func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in bytes { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
    return h
}

/// A fixed untransformed scene: a bordered rounded rect, an ellipse band, a
/// glyph run from a synthetic ramp atlas, a linear and a nearest image and a
/// rounded mask — fractional positions so edges antialias.
@MainActor
func untransformedPinScene() -> (Scene, GlyphAtlas) {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let font = FontKey(resolvedPostScriptName: "TransformPin", size: 10, variations: [],
                       matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    var scene = Scene()
    scene.insert(MUIRect(bounds: mb(10.25, 12.5, 90, 60), contentMask: mb(0, 0, 200, 200), maskCornerRadii: corners(0),
                         background: MUIHsla(h: 0.6, s: 0.5, l: 0.5, a: 1), borderColor: MUIHsla(h: 0.1, s: 0.9, l: 0.5, a: 1),
                         cornerRadii: corners(14), borderWidths: MUIEdges(top: 3, right: 3, bottom: 3, left: 3),
                         order: 0, shape: 0))
    scene.insert(MUIRect(bounds: mb(110.5, 10.25, 80, 50), contentMask: mb(0, 0, 200, 200), maskCornerRadii: corners(0),
                         background: MUIHsla(h: 0.3, s: 0.6, l: 0.5, a: 1), borderColor: MUIHsla(h: 0.9, s: 0.8, l: 0.4, a: 1),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 9, right: 9, bottom: 9, left: 9),
                         order: 0, shape: 1))
    atlas.beginFrame()
    for g in 0..<5 {
        let key = GlyphKey(font: font, glyph: UInt16(g), size: 10, subpixelVariant: 0, scaleFactor: 1)
        let packed = atlas.packed(for: key) {
            GlyphImage(width: 7, height: 9, bytes: (0..<63).map { UInt8(($0 * 37 + g * 11) % 256) })
        }!
        scene.insert(MUIGlyph(bounds: Bounds(origin: Point(x: ScaledPixels(Float(20 + g * 9)), y: ScaledPixels(90)),
                                             size: Size(width: ScaledPixels(7), height: ScaledPixels(9))),
                              slot: packed.slot, contentMask: Bounds(origin: Point(x: ScaledPixels(15), y: ScaledPixels(85)),
                                                                     size: Size(width: ScaledPixels(50), height: ScaledPixels(20))),
                              maskCornerRadii: Corners(all: ScaledPixels(5)),
                              color: Hsla(h: 0.0, s: 0.0, l: 0.1, a: 1), order: 0))
    }
    atlas.endFrame()
    let ramp = ImageTexture(width: 4, height: 3, straightRGBA: (0..<48).map { UInt8(($0 * 53) % 256) })
    scene.insert(MUIImage(bounds: mb(100.25, 80.5, 60, 40), contentMask: mb(0, 0, 200, 200), maskCornerRadii: corners(0),
                          opacity: 1, texture: 0, filter: 0, order: 0), texture: ramp)
    scene.insert(MUIImage(bounds: mb(30.25, 130.5, 50, 40), contentMask: mb(35, 135, 60, 30), maskCornerRadii: corners(9),
                          opacity: 0.75, texture: 0, filter: 1, order: 0), texture: ramp)
    scene.insert(MUIRect(bounds: mb(120.25, 140.25, 60, 40), contentMask: mb(125, 145, 40, 40), maskCornerRadii: corners(12),
                         background: MUIHsla(h: 0.8, s: 0.7, l: 0.6, a: 0.8), borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 1),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    return (scene, atlas)
}

/// 1.2 — the pin: every untransformed primitive renders bit-identically to
/// the renderer before transforms existed. The literal was recorded on the
/// unmodified renderer (this lane's red commit, `dc96395`'s shaders).
@Test @MainActor func anUntransformedSceneRendersBitIdenticallyToBefore() throws {
    let (scene, atlas) = untransformedPinScene()
    let pixels = try render(scene, atlas: atlas)
    #expect(fnv1a(pixels) == untransformedPinHash, "hash \(String(fnv1a(pixels), radix: 16))")
}
/// Recorded on `dc96395`'s renderer, before any shader change.
let untransformedPinHash: UInt64 = 0xc1c0_b5e3_50b2_17a8

/// 1.3 — a 100×40 rect rotated 30° about the target's centre: some pixel
/// whose centre lies outside the rotated rect by less than half a pixel has
/// partial coverage. Without the vertex stage's fringe the quad ends at the
/// rect's edge and every such pixel reads 0.
@Test @MainActor func aTransformedEdgeIsAntialiasedAcrossTheFringe() throws {
    var scene = Scene()
    scene.insert(solidRect(mb(50, 80, 100, 40)), transform: rotation(30, about: 100, 100))
    let pixels = try render(scene)
    let r = 30.0 * Double.pi / 180, c = cos(r), s = sin(r)
    var fringe = 0, partialInFringe = 0
    for y in 0..<200 {
        for x in 0..<200 {
            // Back to local: the inverse rotation about (100, 100).
            let dx = Double(x) + 0.5 - 100, dy = Double(y) + 0.5 - 100
            let lx = c * dx + s * dy + 100, ly = -s * dx + c * dy + 100
            let ox = max(50 - lx, lx - 150), oy = max(80 - ly, ly - 120)
            let outside = (max(ox, 0) * max(ox, 0) + max(oy, 0) * max(oy, 0)).squareRoot()
            guard ox > 0 || oy > 0, outside < 0.5 else { continue }
            fringe += 1
            let a = pixel(pixels, x, y, width: 200).a
            if a > 0 && a < 255 { partialInFringe += 1 }
        }
    }
    try #require(fringe > 50)
    #expect(partialInFringe > fringe / 2, "\(partialInFringe) of \(fringe) fringe pixels partial")
}

/// 1.4 — under a uniform scale of 2 about the origin, local (10.125,
/// 10.125, 30, 30) lands on screen x, y 20.25…80.25: each edge lies a
/// quarter pixel from a pixel centre, so with distances in screen pixels
/// (band ±0.5) exactly one column and one row are partial at each edge (20
/// and 80). With `pixelScale` ignored the band is ±1 screen pixel and the
/// neighbour outside each edge (19, 79) reads partial too. **An edge through
/// a pixel centre cannot discriminate**: both bands then end exactly on the
/// neighbours' centres — the first arm (20.5) let M1d stay green (`GX-S`
/// item 1). (`scale(2, 0.5)`, the spec's arm, has `|det| = 1` and cannot see
/// `pixelScale` at all; the 2:1 arm below only bounds the band.)
@Test @MainActor func aScaledRectAntialiasesInScreenPixels() throws {
    var scene = Scene()
    scene.insert(solidRect(mb(10.125, 10.125, 30, 30)), transform: transformRecord(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0))
    let pixels = try render(scene)
    let row = (0..<200).map { pixel(pixels, $0, 50, width: 200).a }
    let column = (0..<200).map { pixel(pixels, 50, $0, width: 200).a }
    let partialColumns = row.indices.filter { row[$0] > 0 && row[$0] < 255 }
    let partialRows = column.indices.filter { column[$0] > 0 && column[$0] < 255 }
    #expect(partialColumns == [20, 80], "partial columns \(partialColumns)")
    #expect(partialRows == [20, 80], "partial rows \(partialRows)")

    // 2:1 (|det| 2, pixelScale √2): the isotropic band is at most two pixels.
    var wide = Scene()
    wide.insert(solidRect(mb(10.25, 20.25, 30, 30)), transform: transformRecord(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    let w = try render(wide)
    let wideRow = (0..<200).map { pixel(w, $0, 35, width: 200).a }
    #expect(wideRow.filter { $0 > 0 && $0 < 255 }.count <= 4)
}

/// 1.5 — the bar of 1.1 with a LOCAL content mask over its left half (local
/// x 20…100 → screen y 20…100) and a SCREEN outer mask cutting the top
/// quarter (y < 50): (100, 30) is cut by the outer mask, (100, 70) is drawn,
/// (100, 130) is cut by the content mask, (100, 170) too. Read at the screen
/// position, the content mask (x 20…100, y 90…110) would clear (100, 70).
@Test @MainActor func theOuterMaskIsScreenSpaceAndTheContentMaskLocal() throws {
    var scene = Scene()
    scene.insert(solidRect(mb(20, 90, 160, 20), mask: mb(20, 90, 80, 20)),
                 transform: quarterTurn(about: 100, 100, outer: mb(0, 50, 200, 150)))
    let pixels = try render(scene)
    #expect(pixel(pixels, 100, 30, width: 200).a == 0, "outer mask")
    #expect(pixel(pixels, 100, 70, width: 200).a == 255, "drawn")
    #expect(pixel(pixels, 100, 130, width: 200).a == 0, "content mask")
    #expect(pixel(pixels, 100, 170, width: 200).a == 0, "content mask")
}

/// 1.6 — a glyph slot of coverage 0 packed hard against a neighbour whose
/// left column is 255, drawn ×4 and turned a quarter: bilinear sampling near
/// the slot's right edge blends the neighbour's column unless the atlas
/// position is clamped to the slot, so every drawn pixel must read 0.
@Test @MainActor func aRotatedGlyphSamplesItsSlotOnly() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let font = FontKey(resolvedPostScriptName: "SlotClamp", size: 10, variations: [],
                       matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    atlas.beginFrame()
    let empty = atlas.packed(for: GlyphKey(font: font, glyph: 1, size: 10, subpixelVariant: 0, scaleFactor: 1)) {
        GlyphImage(width: 6, height: 6, bytes: [UInt8](repeating: 0, count: 36))
    }!
    let neighbour = atlas.packed(for: GlyphKey(font: font, glyph: 2, size: 10, subpixelVariant: 0, scaleFactor: 1)) {
        GlyphImage(width: 6, height: 6, bytes: (0..<36).map { $0 % 6 == 0 ? 255 : 0 })
    }!
    atlas.endFrame()
    try #require(neighbour.slot.x == empty.slot.x + 6 && neighbour.slot.y == empty.slot.y, "slots abut")
    var scene = Scene()
    // Local 6×6 at (47, 47); ×4 about (50, 50) then a quarter turn.
    let t = transformRecord(a: 0, b: 4, c: -4, d: 0, tx: 50 + 4 * 50, ty: 50 - 4 * 50)
    scene.insert(MUIGlyph(bounds: Bounds(origin: Point(x: ScaledPixels(47), y: ScaledPixels(47)),
                                         size: Size(width: ScaledPixels(6), height: ScaledPixels(6))),
                          slot: empty.slot, contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                                                size: Size(width: ScaledPixels(200), height: ScaledPixels(200))),
                          color: Hsla(h: 0, s: 0, l: 0, a: 1), order: 0), transform: t)
    let pixels = try render(scene, width: 100, height: 100, atlas: atlas)
    let lit = (0..<100).flatMap { y in (0..<100).map { x in pixel(pixels, x, y, width: 100).a } }.filter { $0 > 0 }.count
    #expect(lit == 0, "\(lit) pixels read the neighbour slot")
}

/// 1.7 — a red/blue 2×1 texture over local (0, 45.5, 100, 10), turned a
/// quarter about (50, 50) (screen x = 100 − y, y = x): red on top, blue
/// below; nearest switches exactly between rows 49 and 50; the edges at
/// screen x 44.5 and 54.5 cut columns 44 and 54 in half.
@Test @MainActor func aRotatedImageKeepsItsFilterAndAntialiasesItsEdges() throws {
    let redBlue = ImageTexture(width: 2, height: 1, straightRGBA: [255, 0, 0, 255, 0, 0, 255, 255])
    for nearest in [false, true] {
        var scene = Scene()
        scene.insert(MUIImage(bounds: mb(0, 45.5, 100, 10), contentMask: mb(0, 0, 200, 200), maskCornerRadii: corners(0),
                              opacity: 1, texture: 0, filter: nearest ? 1 : 0, order: 0),
                     texture: redBlue, transform: quarterTurn(about: 50, 50))
        let pixels = try render(scene, width: 100, height: 100)
        let top = pixel(pixels, 50, 5, width: 100), bottom = pixel(pixels, 50, 95, width: 100)
        #expect(top.r > 200 && top.b < 40 && top.a == 255, "top \(top)")
        #expect(bottom.b > 200 && bottom.r < 40 && bottom.a == 255, "bottom \(bottom)")
        if nearest {
            #expect(pixel(pixels, 50, 49, width: 100) == (255, 0, 0, 255))
            #expect(pixel(pixels, 50, 50, width: 100) == (0, 0, 255, 255))
        }
        for x in [44, 54] {
            let a = pixel(pixels, x, 20, width: 100).a
            #expect(a > 100 && a < 155, "edge column \(x) alpha \(a)")
        }
        #expect(pixel(pixels, 43, 20, width: 100).a == 0 && pixel(pixels, 55, 20, width: 100).a == 0)
    }
}

/// 1.8 — `filter` 1 with a transform index above its low byte still reads
/// the texel under each pixel: the 2-texel image over 100 px switches between
/// 49 and 50 with no blend (an exact identity record at index 3).
@Test @MainActor func theFilterWordCarriesTheTransformAboveItsLowByte() throws {
    let redBlue = ImageTexture(width: 2, height: 1, straightRGBA: [255, 0, 0, 255, 0, 0, 255, 255])
    var scene = Scene()
    scene.insert(solidRect(mb(0, 150, 1, 1)), transform: transformRecord(a: 1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
    scene.insert(solidRect(mb(0, 160, 1, 1)), transform: transformRecord(a: 1, b: 0, c: 0, d: 1, tx: 2, ty: 0))
    scene.insert(MUIImage(bounds: mb(0, 0, 100, 10), contentMask: mb(0, 0, 200, 200), maskCornerRadii: corners(0),
                          opacity: 1, texture: 0, filter: 1, order: 0),
                 texture: redBlue, transform: transformRecord(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    try #require(scene.images[0].filter == 1 | 3 << 8, "index 3 above the filter")
    let pixels = try render(scene)
    #expect(pixel(pixels, 49, 5, width: 200) == (255, 0, 0, 255))
    #expect(pixel(pixels, 50, 5, width: 200) == (0, 0, 255, 255))
}

/// 1.9 — `shape = 1 | 2 << 8` is still the ellipse: the bounds' corner pixel
/// is clear and the centre covered (an identity record at index 2).
@Test @MainActor func aShapeWordAboveItsLowByteKeepsItsShape() throws {
    var scene = Scene()
    scene.insert(solidRect(mb(0, 190, 1, 1)), transform: transformRecord(a: 1, b: 0, c: 0, d: 1, tx: 3, ty: 0))
    scene.insert(solidRect(mb(20, 20, 160, 100), shape: 1), transform: transformRecord(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    try #require(scene.rects[1].shape == 1 | 2 << 8)
    let pixels = try render(scene)
    #expect(pixel(pixels, 22, 22, width: 200).a == 0, "outside the ellipse")
    #expect(pixel(pixels, 100, 70, width: 200).a == 255, "inside")
}
