import Testing
import Metal
import simd
import CoreText
import MetalUICore
import MetalUIShaderTypes
import MetalUIText
@testable import MetalUIRender

/// A white rect spanning x 10..<50, y 10..<50, carrying `mask` as its
/// `contentMask`.
///
/// **The expected values are built from the CLIP, not from the primitive.**
/// Reading the mask back off the `MUIRect` to decide what to assert would be
/// taxonomy shape 12 — the oracle being the code under test — which produced
/// four defects in M2. Every boundary asserted below is a literal.
private func clippedRect(mask: MUIBounds,
                         maskRadii: MUICorners = MUICorners(topLeft: 0, topRight: 0,
                                                            bottomRight: 0, bottomLeft: 0),
                         bounds: MUIBounds = MUIBounds(origin: MUIPoint(x: 10, y: 10),
                                                       size: MUISize(width: 40, height: 40)))
    -> MUIRect {
    MUIRect(bounds: bounds,
            contentMask: mask,
            maskCornerRadii: maskRadii,
            background: MUIHsla(h: 0, s: 0, l: 1, a: 1),   // white
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, _reserved: 0)
}

/// The clip box every rect test below cuts against: **x 14..<31, y 18..<39**.
///
/// Four distinct edge coordinates, none of them zero and no two of them equal,
/// all four strictly inside the rect's own 10..<50 box on both axes. That is
/// the whole point of the numbers: an origin of `(0, 0)` (which every
/// rasterized `contentMask` in this repo happens to have) makes
/// `mask.origin` unreadable, a full-surface height makes the entire vertical
/// axis unreadable, and two coincident edges make it impossible to say WHICH
/// edge a failure came from. Both mutations this fixture exists for —
/// `float2 lo = float2(0.0, 0.0)` and `return inside.x` in
/// `mask_coverage` — passed the whole suite against the previous
/// `(0, 0, 30, 64)` mask.
private let clipBox = MUIBounds(origin: MUIPoint(x: 14, y: 18),
                                size: MUISize(width: 17, height: 21))

@Test @MainActor func aRectIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // The rect spans 10..<50 on both axes. `clipBox` cuts it to x 14..<31,
    // y 18..<39 — inside the rect on all four sides.
    var scene = Scene()
    scene.insert(clippedRect(mask: clipBox))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)

    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Well inside the clip on both axes: painted.
    #expect(alphaAt(20, 25) > 200, "(20, 25) is inside both the rect and the clip")
    #expect(alphaAt(28, 35) > 200, "(28, 35) is inside both, near the far corner of the clip")
    // Outside the clip on exactly one axis at a time, inside the rect in all
    // four cases. Each names the term of `mask_coverage` it reads.
    #expect(alphaAt(11, 25) < 20,
            "x=11 is left of mask.origin.x=14 — reads `lo.x`, which a `float2 lo = float2(0, 0)` drops")
    #expect(alphaAt(20, 14) < 20,
            "y=14 is above mask.origin.y=18 — reads `lo.y`, which the same mutation drops")
    #expect(alphaAt(40, 25) < 20, "x=40 is right of the clip's far edge at 31 — reads `hi.x`")
    #expect(alphaAt(20, 45) < 20,
            "y=45 is below the clip's far edge at 39 — reads `hi.y`, the whole factor a `return inside.x` drops")
    // Outside the rect entirely: not painted, clip or no clip.
    #expect(alphaAt(5, 25) < 20)
}

/// The differential: the identical rect with a full-surface mask paints every
/// one of the four points the clipped version suppresses. Without this, the
/// test above passes on a shader that paints nothing outside `clipBox` for an
/// unrelated reason — or on one that paints nothing at all beyond a corner.
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

    #expect(alphaAt(11, 25) > 200, "unclipped, the point left of the clip must be painted")
    #expect(alphaAt(20, 14) > 200, "unclipped, the point above the clip must be painted")
    #expect(alphaAt(40, 25) > 200, "unclipped, the point right of the clip must be painted")
    #expect(alphaAt(20, 45) > 200, "unclipped, the point below the clip must be painted")
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

/// `MUIRect.contentMask` lives in the same **pre-projection** ScaledPixels
/// space as `MUIRect.bounds` — `rect_fragment` clips against
/// `RectVertexOut.pixelPosition`, not against the built-in `[[position]]`,
/// which is post-projection. `RectVertexOut`'s own doc comment states that,
/// and so does `aGlyphsContentMaskIsEvaluatedInPreProjectionSpace` below —
/// **in prose, about the rect path, while nothing checked it.** Mutating
/// `mask_coverage(in.pixelPosition, …)` to `mask_coverage(in.position.xy, …)`
/// reddened the whole suite nowhere until this test existed.
///
/// The geometry: a 32pt-wide rect at x 20..<52, clipped to its own left half
/// (mask far edge at x 36), shifted **16 device pixels left** on screen by a
/// translation in the projection matrix. Pre-projection, the surviving half is
/// x 20..<36, which lands on screen at x 4..<20. Post-projection — the mutant —
/// the mask is compared against screen x instead, so the whole shifted rect
/// (screen x 4..<36) is under 36 and nothing is clipped at all.
///
/// Sized to fail loudly rather than by a sliver: the mutant paints 16 device
/// pixels that must be blank, across the rect's full height.
@Test @MainActor func aRectsContentMaskIsEvaluatedInPreProjectionSpace() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // NDC spans [-1, 1] across `side` pixels, so a delta of `d` in NDC.x moves
    // the rendered geometry by `d / 2 * side` device pixels — the same
    // derivation `RendererTests.projectionMatrixMovesTheRenderedRect` uses,
    // negated here for a leftward shift.
    let shift = 16
    let deltaNDC = -2 * Float(shift) / Float(side)
    let projection = simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                             SIMD4<Float>(0, 1, 0, 0),
                                             SIMD4<Float>(0, 0, 1, 0),
                                             SIMD4<Float>(deltaNDC, 0, 0, 1)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 36, height: Float(side))),
                             bounds: MUIBounds(origin: MUIPoint(x: 20, y: 8),
                                               size: MUISize(width: 32, height: 32))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size, projection: projection)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Screen x 4..<20 — the surviving pre-projection half, after the shift.
    for x in 5..<19 {
        #expect(alphaAt(x, 20) > 200,
                "screen x=\(x) is the shifted image of pre-projection x=\(x + shift), inside the mask")
    }
    // Screen x 20..<36 — the clipped half, which the mutant paints.
    var spilled = 0
    for x in 21..<35 where alphaAt(x, 20) > 20 { spilled += 1 }
    #expect(spilled == 0,
            "\(spilled) device pixels painted right of the clip — the clip moved with the projection instead of staying in the rect's own pre-projection space")
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
                           mask: MUIBounds,
                           maskRadii: MUICorners = MUICorners(topLeft: 0, topRight: 0,
                                                              bottomRight: 0, bottomLeft: 0)
) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: x, y: y),
                               size: MUISize(width: Float(slot.width),
                                             height: Float(slot.height))),
             atlasBounds: MUIBounds(origin: MUIPoint(x: Float(slot.x), y: Float(slot.y)),
                                    size: MUISize(width: Float(slot.width),
                                                  height: Float(slot.height))),
             contentMask: mask,
             maskCornerRadii: maskRadii,
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
/// `bounds`, for both `MUIRect` and `MUIGlyph`. The rect half of that claim
/// used to be asserted here in prose and nowhere in code;
/// `aRectsContentMaskIsEvaluatedInPreProjectionSpace` above is now the test
/// for it, and this one covers the glyph pipeline only.
/// A glyph shifted left on screen by exactly half its own width,
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

// MARK: - Rounded clip corners

/// A rounded clip's CORNER differs from a square clip's — the whole reason
/// `maskCornerRadii` exists. `clipBox` (x 14..<31, y 18..<39, all four edges
/// non-zero and distinct — see its own doc comment) with a 6pt radius on every
/// corner excludes device pixel (14, 18) — `clipBox`'s own top-left corner
/// texel, pixel-centre (14.5, 18.5), 7.8pt from the rounding centre at
/// (22.5, 28.5) and outside a 6pt radius (SDF +1.78) — while the square clip
/// of the identical bounds includes it (SDF -0.5, well inside). A square clip
/// of the identical bounds paints it; the rounded one must cut it. That
/// differential, not either image alone, is the test — asserting only the
/// rounded render's low alpha would pass just as well on a mask that clips
/// everything.
@Test @MainActor func aRoundedClipCutsTheRectsCornerASquareClipWouldPaint() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    let radii = MUICorners(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)

    func alphaAt(_ pixels: [UInt8], _ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    var square = Scene()
    square.insert(clippedRect(mask: clipBox))
    square.finalize()
    let squarePixels = try renderer.renderOffscreen(square, size: size)

    var rounded = Scene()
    rounded.insert(clippedRect(mask: clipBox, maskRadii: radii))
    rounded.finalize()
    let roundedPixels = try renderer.renderOffscreen(rounded, size: size)

    #expect(alphaAt(squarePixels, 14, 18) > 200,
            "a square clip of clipBox's own bounds paints this corner pixel")
    #expect(alphaAt(roundedPixels, 14, 18) < 20,
            "a 6pt radius on the same bounds must cut it")

    // Sanity: deep inside the rounded region (near the mask's centre), both
    // still paint — the radius removes only the corners, not the box.
    #expect(alphaAt(roundedPixels, 22, 28) > 200)
    #expect(alphaAt(squarePixels, 22, 28) > 200)
}

/// The glyph half of the same differential — a glyph clipped square inside a
/// rounded container is the same defect one layer down `glyph_fragment`.
///
/// The corner pixel is found by scanning the rasterized 'M' for real ink
/// rather than assumed, matching this file's rule of building expectations
/// from the atlas, not from the primitive under test. The glyph is then
/// positioned so that inked pixel lands exactly on `clipBox`'s validated
/// corner differential — device pixel (14, 18), 6pt-radius-excluded,
/// square-clip-included — reusing the identical geometry
/// `aRoundedClipCutsTheRectsCornerASquareClipWouldPaint` proves above, so both
/// pipelines are checked against the same numbers.
@Test @MainActor func aRoundedClipCutsTheGlyphsCornerASquareClipWouldPaint() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlasForClipping(["M"])
    let slot = slots[0]
    renderer.upload(atlas)

    // The first inked texel scanning from the glyph's own top-left corner —
    // 'M's left stroke reaches the cap height, so this is expected to be
    // within a few rows/columns of (0, 0), and the search window traps
    // loudly rather than silently mis-positioning the glyph if it is not.
    var inkRow = -1, inkCol = -1
    search: for row in 0..<min(6, slot.height) {
        for column in 0..<min(6, slot.width) {
            if atlas.pixels[(slot.y + row) * atlas.width + slot.x + column] > 200 {
                inkRow = row
                inkCol = column
                break search
            }
        }
    }
    try #require(inkRow >= 0 && inkCol >= 0,
                "need ink within the glyph's own top-left 6x6 to build the corner differential")

    // Position the glyph so its inked pixel lands on device pixel (14, 18).
    let originX = 14 - inkCol
    let originY = 18 - inkRow
    try #require(originX >= 0 && originY >= 0)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    let radii = MUICorners(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
    func alphaAt(_ pixels: [UInt8], _ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    var square = Scene()
    square.insert(clippedSprite(slot, atX: Float(originX), y: Float(originY), mask: clipBox))
    square.finalize()
    let squarePixels = try renderer.renderOffscreen(square, size: size)

    var rounded = Scene()
    rounded.insert(clippedSprite(slot, atX: Float(originX), y: Float(originY),
                                 mask: clipBox, maskRadii: radii))
    rounded.finalize()
    let roundedPixels = try renderer.renderOffscreen(rounded, size: size)

    #expect(alphaAt(squarePixels, 14, 18) > 100,
            "a square clip of clipBox's own bounds paints this inked corner pixel")
    #expect(alphaAt(roundedPixels, 14, 18) < 20,
            "a 6pt radius on the same bounds must cut it")
}
