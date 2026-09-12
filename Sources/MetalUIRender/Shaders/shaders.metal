// MetalUIShaderTypes.h is textually prepended by ShaderLibrary before compilation.
// Do NOT add an #include for it: MTLCompileOptions has no include search path.

#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Signed distance to a rounded box centred at the origin.
/// Negative inside, positive outside, in the same units as `p`.
static float rect_sdf(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

/// Radius of the corner nearest to `centerToPoint`.
static float pick_corner_radius(float2 centerToPoint, MUICorners radii) {
    if (centerToPoint.x < 0.0) {
        return centerToPoint.y < 0.0 ? radii.topLeft : radii.bottomLeft;
    }
    return centerToPoint.y < 0.0 ? radii.topRight : radii.bottomRight;
}

/// HSLA to gamma-encoded sRGB. No linearization: the compositor works in this
/// space directly (spec 7.8).
static float4 hsla_to_srgba(MUIHsla hsla) {
    float h = hsla.h * 6.0;
    float c = (1.0 - fabs(2.0 * hsla.l - 1.0)) * hsla.s;
    float x = c * (1.0 - fabs(fmod(h, 2.0) - 1.0));
    float m = hsla.l - c / 2.0;

    float3 rgb;
    if      (h < 1.0) rgb = float3(c, x, 0.0);
    else if (h < 2.0) rgb = float3(x, c, 0.0);
    else if (h < 3.0) rgb = float3(0.0, c, x);
    else if (h < 4.0) rgb = float3(0.0, x, c);
    else if (h < 5.0) rgb = float3(x, 0.0, c);
    else              rgb = float3(c, 0.0, x);

    return float4(rgb + m, hsla.a);
}

// Antialiased coverage of `p` inside an axis-aligned, optionally rounded mask,
// in the same pixel space as `[[position]]`.
//
// Reuses `rect_sdf`/`pick_corner_radius` — the same machinery `rect_fragment`
// already uses for its own `outerAlpha` — rather than a second rounded-rect
// implementation, and on the same half-pixel threshold, so a clip edge and a
// rect edge antialias identically. `maskRadii` all zero degenerates to a plain
// axis-aligned box, which is every call site written before this parameter
// existed.
//
// **Not `discard_fragment()`.** There is no depth buffer, so discarding buys
// nothing, and on some GPUs it disables early-Z for the whole shader. Returning
// coverage keeps this composable with the SDF coverage the callers already
// compute.
static inline float mask_coverage(float2 p, MUIBounds mask, MUICorners maskRadii) {
    float2 halfSize = float2(mask.size.width, mask.size.height) * 0.5;
    float2 center   = float2(mask.origin.x, mask.origin.y) + halfSize;
    float2 rel      = p - center;
    float radius = pick_corner_radius(rel, maskRadii);
    // 0.5 is half a pixel: the same antialiasing threshold `rect_sdf` uses.
    return saturate(0.5 - rect_sdf(rel, halfSize, radius));
}

// ---------------------------------------------------------------------------
// Rect pipeline
// ---------------------------------------------------------------------------

struct RectVertexOut {
    float4 position [[position]];
    /// Unprojected position, in the same ScaledPixels space as `MUIRect.bounds`.
    /// The fragment shader must evaluate its SDF here, not in `position.xy`:
    /// under a non-identity projection those spaces differ, and using
    /// `position.xy` would clip each rect to its unprojected footprint.
    float2 pixelPosition;
    uint   rectID   [[flat]];
};

vertex RectVertexOut rect_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2  *unitVertices [[buffer(MUIRectBufferVertices)]],
    constant MUIRect *rects        [[buffer(MUIRectBufferRects)]],
    constant MUISize &viewport     [[buffer(MUIRectBufferViewport)]],
    constant float4x4 &projection  [[buffer(MUIRectBufferProjection)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIRect r = rects[instanceID];

    float2 pos = float2(r.bounds.origin.x, r.bounds.origin.y)
               + unit * float2(r.bounds.size.width, r.bounds.size.height);

    // Pixel space (y down) to normalised device coordinates (y up).
    float2 ndc = pos / float2(viewport.width, viewport.height) * float2(2.0, -2.0)
               + float2(-1.0, 1.0);

    RectVertexOut out;
    // CONTRACT: `projection` is a POST-NDC transform, not a camera matrix. It is
    // applied AFTER the hardcoded pixel->NDC divide above, and the vertex always
    // emits z = 0, w = 1. So a CompositorServices backend cannot hand over a
    // plain per-eye P*V: it must pre-compose the inverse of the viewport mapping
    // this shader owns, and encode any depth it needs into the matrix itself.
    // That is expressible for a planar UI, so the spec 3.2 seam holds — but "a
    // matrix the renderer does not interpret" understates what the caller owes.
    out.position = projection * float4(ndc, 0.0, 1.0);
    out.pixelPosition = pos;
    out.rectID = instanceID;
    return out;
}

fragment float4 rect_fragment(
    RectVertexOut in [[stage_in]],
    constant MUIRect *rects [[buffer(MUIRectBufferRects)]]
) {
    MUIRect r = rects[in.rectID];

    float2 halfSize = float2(r.bounds.size.width, r.bounds.size.height) * 0.5;
    float2 center   = float2(r.bounds.origin.x, r.bounds.origin.y) + halfSize;
    float2 p        = in.pixelPosition - center;

    float radius = pick_corner_radius(p, r.cornerRadii);

    // Outer edge coverage. 0.5 is half a pixel: the antialiasing threshold.
    float outerAlpha = saturate(0.5 - rect_sdf(p, halfSize, radius));

    // Inner edge separates border from background.
    float2 border = float2(p.x < 0.0 ? r.borderWidths.left : r.borderWidths.right,
                           p.y < 0.0 ? r.borderWidths.top  : r.borderWidths.bottom);
    float innerRadius = max(radius - max(border.x, border.y), 0.0);
    float innerAlpha = saturate(0.5 - rect_sdf(p, max(halfSize - border, 0.0), innerRadius));

    float4 background  = hsla_to_srgba(r.background);
    float4 borderColor = hsla_to_srgba(r.borderColor);

    // **`innerAlpha` selects between border and background; it must NOT carry
    // edge coverage, because `outerAlpha` already does, below.** With zero
    // border widths `innerAlpha` is bit-identical to `outerAlpha`, so mixing by
    // it directly premultiplied the fragment a second time: the emitted RGB
    // decayed as `c^3` against an alpha of `c^2`, which loses *colour* rather
    // than merely opacity and left a desaturated fringe on every rounded
    // corner and every fractionally-positioned edge. Measured on a 100x100
    // rect at radius 30: pixel (8,8) came out alpha 2 / red 0 where 24 / 24 is
    // correct. Normalising by `outerAlpha` makes this a pure selector — 0 in
    // the outer antialiasing band where `innerAlpha` is 0 (border colour,
    // weighted once below), and exactly `innerAlpha` at the inner transition
    // where `outerAlpha` is 1, so the non-zero-border case is unchanged.
    // Pinned by `aZeroWidthBordersColorChangesNoPixel`, whose two arms are
    // measured to disagree without this line.
    float borderMix = outerAlpha > 0.0 ? saturate(innerAlpha / outerAlpha) : 0.0;
    float4 color = mix(borderColor, background, borderMix);

    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    // Clip last, so it composes with the rounded-rect coverage above rather
    // than replacing it. A primitive is drawn where it intersects its mask.
    float clip = mask_coverage(in.pixelPosition, r.contentMask, r.maskCornerRadii);
    return float4(color.rgb * color.a, color.a) * outerAlpha * clip;
}

// ---------------------------------------------------------------------------
// Glyph pipeline
//
// `monochromeSprite` (spec 7.1): an R8 coverage bitmap from the glyph atlas,
// multiplied by a tint. The atlas carries no colour at all, which is what makes
// one bitmap serve every colour the same run is ever drawn in.
// ---------------------------------------------------------------------------

struct GlyphVertexOut {
    float4 position [[position]];
    /// Unprojected position, in the same ScaledPixels space as `MUIGlyph.bounds`
    /// (and `contentMask`). The fragment shader must clip here, not in
    /// `position.xy`: under a non-identity projection those spaces differ, and
    /// using `position.xy` would clip each glyph to its unprojected footprint.
    /// Same reasoning as `RectVertexOut.pixelPosition` — see the note there.
    float2 pixelPosition;
    /// Source position in ATLAS TEXELS, not normalised — the sampler below is
    /// declared `coord::pixel`. Interpolating this rather than recomputing it
    /// per fragment is what makes the blit exact: at a fragment centre it is
    /// `atlasBounds.origin + k + 0.5`, which is texel `k`'s centre.
    float2 atlasPosition;
    uint   glyphID [[flat]];
};

vertex GlyphVertexOut glyph_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2   *unitVertices [[buffer(MUIGlyphBufferVertices)]],
    constant MUIGlyph *glyphs       [[buffer(MUIGlyphBufferGlyphs)]],
    constant MUISize  &viewport     [[buffer(MUIGlyphBufferViewport)]],
    constant float4x4 &projection   [[buffer(MUIGlyphBufferProjection)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIGlyph g = glyphs[instanceID];

    float2 pos = float2(g.bounds.origin.x, g.bounds.origin.y)
               + unit * float2(g.bounds.size.width, g.bounds.size.height);

    // Pixel space (y down) to normalised device coordinates (y up). Identical
    // to `rect_vertex`'s mapping, and it must stay identical: a glyph and the
    // rect behind it are placed in one coordinate system by the paint pass.
    float2 ndc = pos / float2(viewport.width, viewport.height) * float2(2.0, -2.0)
               + float2(-1.0, 1.0);

    GlyphVertexOut out;
    // Same POST-NDC projection contract as `rect_vertex` — see the note there.
    out.position = projection * float4(ndc, 0.0, 1.0);
    out.pixelPosition = pos;
    out.atlasPosition = float2(g.atlasBounds.origin.x, g.atlasBounds.origin.y)
                      + unit * float2(g.atlasBounds.size.width, g.atlasBounds.size.height);
    out.glyphID = instanceID;
    return out;
}

fragment float4 glyph_fragment(
    GlyphVertexOut in [[stage_in]],
    constant MUIGlyph *glyphs   [[buffer(MUIGlyphBufferGlyphs)]],
    texture2d<float>   atlas    [[texture(MUIGlyphTextureAtlas)]]
) {
    // `coord::pixel` so the sampler takes atlas texels directly: the alternative
    // is dividing by the atlas dimensions, which means carrying them across the
    // ABI and resolving the same quantity twice. `clamp_to_edge` so a coordinate
    // exactly on the atlas's far edge — which a slot flush against it produces —
    // reads the last texel rather than 0.
    //
    // `filter::linear` matches gpui's `monochrome_sprite_fragment`. **It is
    // exact at the 1:1 scale this renderer emits, and that is measured rather
    // than argued**: swapping it for `filter::nearest` leaves all 429 tests
    // green, including a per-pixel comparison of two rendered sprites against
    // the CPU atlas bytes. So the two filters are indistinguishable today and
    // the choice is unpinned on purpose — no input this renderer can build
    // distinguishes them, and a test manufacturing one would be testing the
    // test. It becomes load-bearing the moment a sprite is drawn at a scale
    // other than 1:1 (a zoomed canvas, spec 7.5), which is why linear is the
    // one written.
    //
    // The exactness is the interpolated coordinate landing on texel centres:
    // at destination pixel k the fragment centre carries
    // `atlasBounds.origin + k + 0.5`. Shifting `atlasPosition` by a single
    // texel (`origin.x + 1.0` in `glyph_vertex`) reddens
    // `aGlyphSpriteBlitsExactlyTheAtlasPixelsItPointsAt`,
    // `glyphsAreTintedByTheirColorAndScaledByCoverage`,
    // `aGlyphPackedAfterTheFirstUploadStillReachesTheGPU`,
    // `anAtlasWithNoDirtyRectStillUploadsInFullToANewTexture`,
    // `aRectAndAGlyphBothDrawInOneScene` and
    // `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor` — so the
    // alignment is guarded rather than assumed. **Named rather than counted
    // (ruling SI-H)**: this comment said "four tests" when it was written in
    // Task 7, two tests sensitive to the same line landed after it, and a count
    // is stale the moment one does. Re-measured `--no-parallel` on 2026-08-28,
    // 9 issues across those six, suite 444.
    constexpr sampler atlas_sampler(coord::pixel,
                                    address::clamp_to_edge,
                                    filter::linear);

    // R8: coverage in .r, and .gba are the format's defaults (0, 0, 1), so
    // reading anything but .r here would silently paint a constant.
    float coverage = atlas.sample(atlas_sampler, in.atlasPosition).r;

    MUIGlyph g = glyphs[in.glyphID];
    float4 tint = hsla_to_srgba(g.color);
    // Spec 7.8: coverage is a blend weight applied to alpha, used unmodified
    // and with no linearization anywhere. gpui's `color.a *= sample.a`.
    // Same clip as `rect_fragment`, same helper, evaluated in the same
    // pre-projection space via `pixelPosition` (not the built-in
    // `in.position.xy`, which is post-projection — see `GlyphVertexOut`'s doc
    // comment). That is what makes a glyph and a rect under one clip stack cut
    // on exactly the same boundary under ANY projection, not only the identity
    // one every existing test used before this was fixed.
    float clip = mask_coverage(in.pixelPosition, g.contentMask, g.maskCornerRadii);
    float alpha = tint.a * coverage * clip;
    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    return float4(tint.rgb * alpha, alpha);
}

// ---------------------------------------------------------------------------
// ABI probe
//
// Reports Metal's view of the shared structs so a host test can compare it with
// Swift's. Catches MSL-vs-C layout divergence, which the Swift compiler cannot
// see. (C-vs-Swift divergence is impossible: Swift imports the same header.)
// ---------------------------------------------------------------------------

kernel void abi_probe(
    device MUIUInt    *out [[buffer(MUIProbeBufferOut)]],
    constant MUIRect  &r   [[buffer(MUIProbeBufferRect)]],
    constant MUIGlyph &g   [[buffer(MUIProbeBufferGlyph)]]
) {
    out[0]  = (MUIUInt)sizeof(MUIRect);
    out[1]  = (MUIUInt)sizeof(MUIBounds);
    out[2]  = (MUIUInt)sizeof(MUIHsla);
    out[3]  = (MUIUInt)sizeof(MUICorners);
    out[4]  = (MUIUInt)sizeof(MUIEdges);
    // Field round-trip catches offset drift that sizes alone would miss.
    out[5]  = (MUIUInt)r.bounds.origin.x;
    out[6]  = (MUIUInt)r.bounds.size.height;
    out[7]  = (MUIUInt)r.contentMask.size.width;
    out[8]  = (MUIUInt)(r.background.h * 1000.0);
    out[9]  = (MUIUInt)(r.borderColor.a * 1000.0);
    out[10] = (MUIUInt)r.cornerRadii.bottomLeft;
    out[11] = (MUIUInt)r.borderWidths.left;
    out[12] = r.order;

    // MUIGlyph. Every field is read back, and `bounds` and `atlasBounds` are the
    // pair that most needs it: they are the same type, adjacent, and a shader
    // that swapped them would still compile and would sample the destination
    // rectangle out of the atlas.
    out[13] = (MUIUInt)sizeof(MUIGlyph);
    out[14] = (MUIUInt)g.bounds.origin.x;
    out[15] = (MUIUInt)g.bounds.origin.y;
    out[16] = (MUIUInt)g.bounds.size.width;
    out[17] = (MUIUInt)g.bounds.size.height;
    out[18] = (MUIUInt)g.atlasBounds.origin.x;
    out[19] = (MUIUInt)g.atlasBounds.origin.y;
    out[20] = (MUIUInt)g.atlasBounds.size.width;
    out[21] = (MUIUInt)g.atlasBounds.size.height;
    out[22] = (MUIUInt)(g.color.h * 1000.0);
    out[23] = (MUIUInt)(g.color.s * 1000.0);
    out[24] = (MUIUInt)(g.color.l * 1000.0);
    out[25] = (MUIUInt)(g.color.a * 1000.0);
    out[26] = (MUIUInt)g.contentMask.origin.x;
    out[27] = (MUIUInt)g.contentMask.size.width;
    out[28] = g.order;

    // `maskCornerRadii` on both structs — two corners each (not one), so a
    // transposition with the existing `cornerRadii` field (same type,
    // adjacent on `MUIRect`) shows up as a wrong number rather than a
    // coincidental match.
    out[29] = (MUIUInt)r.maskCornerRadii.topLeft;
    out[30] = (MUIUInt)r.maskCornerRadii.bottomRight;
    out[31] = (MUIUInt)g.maskCornerRadii.topLeft;
}
