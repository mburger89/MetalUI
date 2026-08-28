import Testing
import Metal
import simd
import CoreText
import MetalUICore
import MetalUIShaderTypes
import MetalUIText
@testable import MetalUIRender

/// A rect clipped to the left half of its own box.
///
/// **The expected values are built from the CLIP, not from the primitive.**
/// Reading the mask back off the `MUIRect` to decide what to assert would be
/// taxonomy shape 12 — the oracle being the code under test — which produced
/// four defects in M2. The x boundary here is a literal.
private func clippedRect(mask: MUIBounds) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 10, y: 10),
                              size: MUISize(width: 40, height: 40)),
            contentMask: mask,
            background: MUIHsla(h: 0, s: 0, l: 1, a: 1),   // white
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, _reserved: 0)
}

@Test @MainActor func aRectIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // The rect spans x 10..<50. Clip it to x 10..<30.
    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)

    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Well inside the clip: painted.
    #expect(alphaAt(15, 25) > 200, "x=15 is inside both the rect and the clip")
    #expect(alphaAt(25, 25) > 200, "x=25 is inside both")
    // Well outside the clip but inside the rect: not painted.
    #expect(alphaAt(35, 25) < 20, "x=35 is inside the rect and outside the clip")
    #expect(alphaAt(45, 25) < 20, "x=45 is inside the rect and outside the clip")
    // Outside the rect entirely: not painted, clip or no clip.
    #expect(alphaAt(5, 25) < 20)
}

/// The differential: the identical rect with a full-surface mask paints all the
/// way across. Without this, the test above passes on a shader that paints
/// nothing beyond x=30 for an unrelated reason.
@Test @MainActor func theSameRectWithAFullMaskPaintsItsWholeWidth() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 64, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    #expect(alphaAt(35, 25) > 200, "unclipped, x=35 must be painted")
    #expect(alphaAt(45, 25) > 200, "unclipped, x=45 must be painted")
}

/// The clip edge is antialiased rather than a hard step. A half-pixel boundary
/// must produce a partially covered pixel, the same way the rect's own edge
/// does — a hard cutoff jags visibly on fractional boundaries.
@Test @MainActor func theClipEdgeIsAntialiasedLikeTheRectsOwnEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30.5, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    let edge = alphaAt(30, 25)
    #expect(edge > 20 && edge < 235,
            "the pixel straddling a 30.5 boundary must be partially covered, got \(edge)")
}

private func packedAtlasForClipping(_ characters: [Character]) throws -> (GlyphAtlas, [AtlasSlot]) {
    let font = FontResolver.resolve(family: nil, size: 24)
    let atlas = GlyphAtlas(width: 128, height: 128)
    atlas.beginFrame()
    defer { atlas.endFrame() }
    var slots: [AtlasSlot] = []
    for character in characters {
        var utf16 = Array(String(character).utf16)
        var glyphIDs = [CGGlyph](repeating: 0, count: utf16.count)
        try #require(CTFontGetGlyphsForCharacters(font.ctFont, &utf16, &glyphIDs, utf16.count))
        let key = GlyphKey(font: font.key, glyph: glyphIDs[0], size: 24,
                           subpixelVariant: 0, scaleFactor: 1)
        slots.append(try #require(atlas.slot(for: key) {
            GlyphRaster.rasterize(glyph: glyphIDs[0], font: font,
                                  subpixelVariant: 0, scaleFactor: 1)
        }))
    }
    return (atlas, slots)
}

private func clippedSprite(_ slot: AtlasSlot, atX x: Float, y: Float,
                           mask: MUIBounds) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: x, y: y),
                               size: MUISize(width: Float(slot.width),
                                             height: Float(slot.height))),
             atlasBounds: MUIBounds(origin: MUIPoint(x: Float(slot.x), y: Float(slot.y)),
                                    size: MUISize(width: Float(slot.width),
                                                  height: Float(slot.height))),
             contentMask: mask,
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: 0, _reserved: 0)
}

/// A glyph clipped to the left half of its box.
///
/// The expectation is built from the atlas bitmap and a literal boundary, not
/// from the sprite's own mask — shape 12 again, and the glyph path is where M2
/// actually got bitten by it.
@Test @MainActor func aGlyphIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlasForClipping(["M"])
    let slot = slots[0]
    renderer.upload(atlas)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    let originX = 8, originY = 8
    try #require(slot.width >= 6, "need a glyph wide enough to clip through the middle")
    let cut = Float(originX + slot.width / 2)

    var scene = Scene()
    scene.insert(clippedSprite(slot, atX: Float(originX), y: Float(originY),
                               mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                               size: MUISize(width: cut, height: Float(side)))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Every device pixel of the glyph, checked against the atlas AND the cut.
    var inkLeft = 0
    var spilledRight = 0
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let coverage = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            guard coverage > 200 else { continue }
            let x = originX + column, y = originY + row
            if Float(x) + 0.5 < cut - 0.5 {
                if alphaAt(x, y) > 100 { inkLeft += 1 }
            } else if Float(x) + 0.5 > cut + 0.5 {
                if alphaAt(x, y) > 20 { spilledRight += 1 }
            }
        }
    }
    #expect(inkLeft > 0, "the glyph must still paint left of the cut")
    #expect(spilledRight == 0, "\(spilledRight) glyph pixels painted right of the clip")
}

/// `contentMask` lives in the same pre-projection ScaledPixels space as
/// `bounds`, for both `MUIRect` and `MUIGlyph` (`rect_fragment` already clips
/// against `RectVertexOut.pixelPosition`, the pre-projection field, precisely
/// because the built-in `[[position]]` is post-projection — see that struct's
/// doc comment). A glyph shifted left on screen by exactly half its own width,
/// under a clip that keeps only its left half, must still show only its
/// (now-shifted) left half: the clip boundary is a property of the glyph and
/// its own mask, not of where the projection happens to put it on screen.
///
/// Sized to fail loudly rather than by a sliver: shifting left by exactly
/// `slot.width / 2` and clipping against `in.position.xy` (post-projection)
/// instead of `pixelPosition` moves the effective cut by that same half-width,
/// which is enough to let the ENTIRE glyph through unclipped — not merely move
/// the boundary by a pixel.
@Test @MainActor func aGlyphsContentMaskIsEvaluatedInPreProjectionSpace() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlasForClipping(["M"])
    let slot = slots[0]
    renderer.upload(atlas)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    let originX = 20, originY = 8
    try #require(slot.width >= 6, "need a glyph wide enough to clip through the middle")
    let halfWidth = slot.width / 2
    let cut = Float(originX + halfWidth)

    // Shift the glyph LEFT on screen by exactly `halfWidth` device pixels.
    // NDC spans [-1, 1] across `side` pixels, so a delta of `d` in NDC.x moves
    // the rendered geometry by `d / 2 * side` device pixels (same derivation
    // `RendererTests.projectionMatrixMovesTheRenderedRect` uses, negated here
    // for a leftward shift).
    let deltaNDC = -2 * Float(halfWidth) / Float(side)
    let projection = simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                             SIMD4<Float>(0, 1, 0, 0),
                                             SIMD4<Float>(0, 0, 1, 0),
                                             SIMD4<Float>(deltaNDC, 0, 0, 1)))

    var scene = Scene()
    scene.insert(clippedSprite(slot, atX: Float(originX), y: Float(originY),
                               mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                               size: MUISize(width: cut, height: Float(side)))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size, projection: projection)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Read back at the SHIFTED screen location — the glyph moved, its mask
    // (in the glyph's own pre-projection frame) did not.
    var inkLeft = 0
    var spilledRight = 0
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let coverage = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            guard coverage > 200 else { continue }
            let x = Float(originX + column)
            let screenX = originX + column - halfWidth
            let y = originY + row
            guard screenX >= 0, screenX < side else { continue }
            if x + 0.5 < cut - 0.5 {
                if alphaAt(screenX, y) > 100 { inkLeft += 1 }
            } else if x + 0.5 > cut + 0.5 {
                if alphaAt(screenX, y) > 20 { spilledRight += 1 }
            }
        }
    }
    #expect(inkLeft > 0, "the shifted glyph must still paint left of its own cut")
    #expect(spilledRight == 0,
            "\(spilledRight) glyph pixels painted right of the clip — the clip moved with the projection instead of staying in the glyph's own pre-projection space")
}
