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

/// Signed distance from `p` to the ellipse with semi-axes `h`, centred at the
/// origin: negative inside, positive outside, in the same units as `p`
/// (ruling TE-AE). **Exact, not `f / |∇f|`**: the gradient estimate thins a
/// thick band away from the axes, which is the concentric-looking band probe
/// K8 separates from SwiftUI's by 518 px.
///
/// The trig-free fixed-iteration closest-point method (Chatfield's "simple
/// method", ruling TE-AQ item 6): three iterations over a unit direction `t`,
/// each moving the curve point to where the circle of curvature at the
/// current guess, centred at its evolute point `e`, meets the ray to `p`.
/// `sqrt` (via `length`), `*`, `+`, `/`, `clamp` only — no `acos`, `cbrt`,
/// `pow`, `sin` or `cos`, which Vulkan and Direct3D specify loosely, and
/// **the same statements and constants in `replay.hlsl`'s `ellipseSDF`**, so
/// the three backends agree at the ≤ 1 parity tolerance an edge pixel is
/// judged at. Equal axes (within 1e-4) take the circle branch: the evolute
/// collapses to the centre there and the iteration would divide by zero.
static float ellipse_sdf(float2 p, float2 h) {
    if (min(h.x, h.y) <= 0.0) { return 1.0e9; }
    if (abs(h.x - h.y) <= 1.0e-4) { return length(p) - h.x; }
    float2 q = abs(p);
    float2 t = float2(0.70710678, 0.70710678);
    float c = h.x * h.x - h.y * h.y;
    for (int i = 0; i < 3; i++) {
        float2 e = float2(c, -c) * t * t * t / h;
        float2 r = h * t - e;
        float2 v = q - e;
        float rl = length(r);
        float vl = max(length(v), 1.0e-6);
        t = clamp((v * (rl / vl) + e) / h, 0.0, 1.0);
        t = t / max(length(t), 1.0e-6);
    }
    float d = length(q - h * t);
    float2 n = q / h;
    return dot(n, n) < 1.0 ? -d : d;
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
// Transforms (ruling GX-F)
//
// A primitive whose transform index (`MUIRect.shape`/`MUIImage.filter` bits
// 8…31, `MUIGlyph.transform`) is 0 runs exactly the code it always ran —
// every branch below tests the index first. Index i > 0 reads
// `transforms[i − 1]`: the vertex stage grows the LOCAL quad by one screen
// pixel (`1 / pixelScale` local pixels) on every side, maps its corners by
// the affine, and hands the fragment the local position (`pixelPosition`,
// so the SDFs and the content mask run unchanged in local space) and the
// screen position (`screenPosition`, for the outer mask). The fragment
// multiplies every signed distance by `pixelScale` before the half-pixel
// threshold, so a rotated or scaled edge antialiases over one SCREEN pixel.
// `+ − × ÷ sqrt` only, as `replay.hlsl` does statement for statement.
// ---------------------------------------------------------------------------

static inline float2 transform_point(MUITransform t, float2 p) {
    return float2(t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty);
}

/// `mask_coverage` with distances scaled to screen pixels: the content mask
/// of a transformed primitive, which lives in its local space.
static inline float mask_coverage_scaled(float2 p, MUIBounds mask, MUICorners maskRadii, float s) {
    float2 halfSize = float2(mask.size.width, mask.size.height) * 0.5;
    float2 center   = float2(mask.origin.x, mask.origin.y) + halfSize;
    float2 rel      = p - center;
    float radius = pick_corner_radius(rel, maskRadii);
    return saturate(0.5 - rect_sdf(rel, halfSize, radius) * s);
}

/// The antialiased edge of a sprite's own quad (a transformed glyph or
/// image): coverage of `p` inside `bounds`, square corners, in screen pixels.
static inline float quad_edge(float2 p, MUIBounds bounds, float s) {
    float2 halfSize = float2(bounds.size.width, bounds.size.height) * 0.5;
    float2 center   = float2(bounds.origin.x, bounds.origin.y) + halfSize;
    return saturate(0.5 - rect_sdf(p - center, halfSize, 0.0) * s);
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
    /// Render-target position before the projection — differs from
    /// `pixelPosition` only under a transform (ruling GX-F), where it is
    /// where the outer mask is evaluated.
    float2 screenPosition;
    uint   rectID   [[flat]];
};

vertex RectVertexOut rect_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2  *unitVertices [[buffer(MUIRectBufferVertices)]],
    constant MUIRect *rects        [[buffer(MUIRectBufferRects)]],
    constant MUISize &viewport     [[buffer(MUIRectBufferViewport)]],
    constant float4x4 &projection  [[buffer(MUIRectBufferProjection)]],
    constant MUITransform *transforms [[buffer(MUIRectBufferTransforms)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIRect r = rects[instanceID];

    uint transformIndex = r.shape >> 8;
    float2 pos;
    float2 local;
    if (transformIndex == 0) {
        pos = float2(r.bounds.origin.x, r.bounds.origin.y)
            + unit * float2(r.bounds.size.width, r.bounds.size.height);
        local = pos;
    } else {
        MUITransform t = transforms[transformIndex - 1];
        float fringe = 1.0 / t.pixelScale;
        local = float2(r.bounds.origin.x, r.bounds.origin.y) - fringe
              + unit * (float2(r.bounds.size.width, r.bounds.size.height) + 2.0 * fringe);
        pos = transform_point(t, local);
    }

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
    out.pixelPosition = local;
    out.screenPosition = pos;
    out.rectID = instanceID;
    return out;
}

/// A rect's colour times its own edge coverage at `pixelPosition`, every
/// signed distance scaled by `s` before the half-pixel threshold. **`s` is
/// the literal 1.0 for an untransformed rect** (the call below), which the
/// compiler folds away (`x × 1.0 == x`), so index 0 is today's arithmetic —
/// pinned bit for bit by `anUntransformedSceneRendersBitIdenticallyToBefore`.
static float4 rect_shade(MUIRect r, float2 pixelPosition, float s) {
    float2 halfSize = float2(r.bounds.size.width, r.bounds.size.height) * 0.5;
    float2 center   = float2(r.bounds.origin.x, r.bounds.origin.y) + halfSize;
    float2 p        = pixelPosition - center;

    float outerAlpha;
    float innerAlpha;
    if ((r.shape & 0xFF) == MUIShapeEllipse) {
        // The ellipse inscribed in `bounds` (ruling TE-AE). Its border is
        // SwiftUI's `strokeBorder(w)` — `inset(by: w/2).stroke(w)`, probe
        // K8 — the band of half-width w/2 around the ellipse inset by w/2,
        // with one width, `borderWidths.top`; `cornerRadii` is ignored. The
        // band's outer edge is the coverage and its inner edge the selector,
        // exactly the roles `outerAlpha`/`innerAlpha` play for a rect. A band
        // at least as wide as the shorter diameter covers the whole ellipse
        // (K10's "a border wider than half fills"). Same half-pixel threshold.
        float w = r.borderWidths.top;
        float2 inset = halfSize - w * 0.5;
        if (w <= 0.0) {
            outerAlpha = saturate(0.5 - ellipse_sdf(p, halfSize) * s);
            innerAlpha = outerAlpha;
        } else if (min(inset.x, inset.y) <= 0.0) {
            outerAlpha = saturate(0.5 - ellipse_sdf(p, halfSize) * s);
            innerAlpha = 0.0;
        } else {
            float d = ellipse_sdf(p, inset);
            outerAlpha = saturate(0.5 - (d - w * 0.5) * s);
            innerAlpha = saturate(0.5 - (d + w * 0.5) * s);
        }
    } else {
        float radius = pick_corner_radius(p, r.cornerRadii);

        // Outer edge coverage. 0.5 is half a pixel: the antialiasing threshold.
        outerAlpha = saturate(0.5 - rect_sdf(p, halfSize, radius) * s);

        // Inner edge separates border from background.
        float2 border = float2(p.x < 0.0 ? r.borderWidths.left : r.borderWidths.right,
                               p.y < 0.0 ? r.borderWidths.top  : r.borderWidths.bottom);
        float innerRadius = max(radius - max(border.x, border.y), 0.0);
        innerAlpha = saturate(0.5 - rect_sdf(p, max(halfSize - border, 0.0), innerRadius) * s);
    }

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
    // The caller multiplies the clip last, so it composes with the
    // rounded-rect coverage above rather than replacing it. A primitive is
    // drawn where it intersects its mask.
    return float4(color.rgb * color.a, color.a) * outerAlpha;
}


fragment float4 rect_fragment(
    RectVertexOut in [[stage_in]],
    constant MUIRect *rects [[buffer(MUIRectBufferRects)]],
    constant MUITransform *fragmentTransforms [[buffer(MUIRectBufferTransforms)]]
) {
    MUIRect r = rects[in.rectID];
    uint transformIndex = r.shape >> 8;
    if (transformIndex == 0) {
        float clip = mask_coverage(in.pixelPosition, r.contentMask, r.maskCornerRadii);
        return rect_shade(r, in.pixelPosition, 1.0) * clip;
    }
    MUITransform t = fragmentTransforms[transformIndex - 1];
    float clip = mask_coverage_scaled(in.pixelPosition, r.contentMask, r.maskCornerRadii, t.pixelScale)
               * mask_coverage(in.screenPosition, t.outerMask, t.outerMaskRadii);
    return rect_shade(r, in.pixelPosition, t.pixelScale) * clip;
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
    /// See `RectVertexOut.screenPosition`.
    float2 screenPosition;
    uint   glyphID [[flat]];
};

vertex GlyphVertexOut glyph_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2   *unitVertices [[buffer(MUIGlyphBufferVertices)]],
    constant MUIGlyph *glyphs       [[buffer(MUIGlyphBufferGlyphs)]],
    constant MUISize  &viewport     [[buffer(MUIGlyphBufferViewport)]],
    constant float4x4 &projection   [[buffer(MUIGlyphBufferProjection)]],
    constant MUITransform *transforms [[buffer(MUIGlyphBufferTransforms)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIGlyph g = glyphs[instanceID];

    float2 pos;
    float2 local;
    float2 atlasPosition;
    if (g.transform == 0) {
        pos = float2(g.bounds.origin.x, g.bounds.origin.y)
            + unit * float2(g.bounds.size.width, g.bounds.size.height);
        local = pos;
        atlasPosition = float2(g.atlasBounds.origin.x, g.atlasBounds.origin.y)
                      + unit * float2(g.atlasBounds.size.width, g.atlasBounds.size.height);
    } else {
        // The fringe extrapolates the atlas position by the same fraction of
        // the quad; the fragment clamps it back inside the slot.
        MUITransform t = transforms[g.transform - 1];
        float fringe = 1.0 / t.pixelScale;
        float2 size = float2(g.bounds.size.width, g.bounds.size.height);
        float2 grown = unit * (size + 2.0 * fringe) - fringe;
        local = float2(g.bounds.origin.x, g.bounds.origin.y) + grown;
        pos = transform_point(t, local);
        float2 fraction = float2(size.x > 0.0 ? grown.x / size.x : 0.0, size.y > 0.0 ? grown.y / size.y : 0.0);
        atlasPosition = float2(g.atlasBounds.origin.x, g.atlasBounds.origin.y)
                      + fraction * float2(g.atlasBounds.size.width, g.atlasBounds.size.height);
    }

    // Pixel space (y down) to normalised device coordinates (y up). Identical
    // to `rect_vertex`'s mapping, and it must stay identical: a glyph and the
    // rect behind it are placed in one coordinate system by the paint pass.
    float2 ndc = pos / float2(viewport.width, viewport.height) * float2(2.0, -2.0)
               + float2(-1.0, 1.0);

    GlyphVertexOut out;
    // Same POST-NDC projection contract as `rect_vertex` — see the note there.
    out.position = projection * float4(ndc, 0.0, 1.0);
    out.pixelPosition = local;
    out.atlasPosition = atlasPosition;
    out.screenPosition = pos;
    out.glyphID = instanceID;
    return out;
}

fragment float4 glyph_fragment(
    GlyphVertexOut in [[stage_in]],
    constant MUIGlyph *glyphs   [[buffer(MUIGlyphBufferGlyphs)]],
    texture2d<float>   atlas    [[texture(MUIGlyphTextureAtlas)]],
    constant MUITransform *fragmentTransforms [[buffer(MUIGlyphBufferTransforms)]]
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

    MUIGlyph transformed = glyphs[in.glyphID];
    if (transformed.transform != 0) {
        // Under a transform (ruling GX-F) the sprite is resampled: bilinear
        // at the interpolated atlas position, CLAMPED half a texel inside the
        // slot so a neighbour's bitmap never bleeds in, times the quad's own
        // antialiased edge and both masks.
        MUITransform t = fragmentTransforms[transformed.transform - 1];
        float2 slotMin = float2(transformed.atlasBounds.origin.x, transformed.atlasBounds.origin.y);
        float2 slotMax = slotMin + float2(transformed.atlasBounds.size.width, transformed.atlasBounds.size.height);
        float2 inside = clamp(in.atlasPosition, slotMin + 0.5, slotMax - 0.5);
        float sampled = atlas.sample(atlas_sampler, inside).r
                      * quad_edge(in.pixelPosition, transformed.bounds, t.pixelScale);
        float4 tinted = hsla_to_srgba(transformed.color);
        float masks = mask_coverage_scaled(in.pixelPosition, transformed.contentMask,
                                           transformed.maskCornerRadii, t.pixelScale)
                    * mask_coverage(in.screenPosition, t.outerMask, t.outerMaskRadii);
        float transformedAlpha = tinted.a * sampled * masks;
        return float4(tinted.rgb * transformedAlpha, transformedAlpha);
    }

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
// Image pipeline (ruling TE-AF)
//
// The whole of one premultiplied RGBA8 texture stretched over `bounds`, times
// `opacity` and the mask. Linear filtering with clamped edges by default
// (probe I8: SwiftUI's default row is exactly bilinear with texel centres at
// the texel midpoints, and clamped outside them); `MUIImageFilterNearest`
// reads the texel under the pixel with `read`, so the SDL port binds no
// second sampler (`Texture2D.Load` there).
// ---------------------------------------------------------------------------

struct ImageVertexOut {
    float4 position [[position]];
    /// Unprojected position — see `RectVertexOut.pixelPosition`.
    float2 pixelPosition;
    /// 0…1 across the quad: normalised texture coordinates over the whole
    /// texture, so the texel centres fall where probe I8 put them.
    float2 uv;
    /// See `RectVertexOut.screenPosition`.
    float2 screenPosition;
    uint   imageID [[flat]];
};

vertex ImageVertexOut image_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2   *unitVertices [[buffer(MUIImageBufferVertices)]],
    constant MUIImage *images       [[buffer(MUIImageBufferImages)]],
    constant MUISize &viewport     [[buffer(MUIImageBufferViewport)]],
    constant float4x4 &projection   [[buffer(MUIImageBufferProjection)]],
    constant MUITransform *transforms [[buffer(MUIImageBufferTransforms)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIImage m = images[instanceID];

    uint transformIndex = m.filter >> 8;
    float2 pos;
    float2 local;
    float2 uv;
    if (transformIndex == 0) {
        pos = float2(m.bounds.origin.x, m.bounds.origin.y)
            + unit * float2(m.bounds.size.width, m.bounds.size.height);
        local = pos;
        uv = unit;
    } else {
        // The fringe extrapolates the UVs past 0…1; the fragment clamps them.
        MUITransform t = transforms[transformIndex - 1];
        float fringe = 1.0 / t.pixelScale;
        float2 size = float2(m.bounds.size.width, m.bounds.size.height);
        float2 grown = unit * (size + 2.0 * fringe) - fringe;
        local = float2(m.bounds.origin.x, m.bounds.origin.y) + grown;
        pos = transform_point(t, local);
        uv = float2(size.x > 0.0 ? grown.x / size.x : 0.0, size.y > 0.0 ? grown.y / size.y : 0.0);
    }
    // Identical to `rect_vertex`'s mapping, and it must stay identical.
    float2 ndc = pos / float2(viewport.width, viewport.height) * float2(2.0, -2.0)
               + float2(-1.0, 1.0);

    ImageVertexOut out;
    // Same POST-NDC projection contract as `rect_vertex` — see the note there.
    out.position = projection * float4(ndc, 0.0, 1.0);
    out.pixelPosition = local;
    out.uv = uv;
    out.screenPosition = pos;
    out.imageID = instanceID;
    return out;
}

fragment float4 image_fragment(
    ImageVertexOut in [[stage_in]],
    constant MUIImage *records [[buffer(MUIImageBufferImages)]],
    texture2d<float>   image   [[texture(MUIImageTextureImage)]],
    constant MUITransform *fragmentTransforms [[buffer(MUIImageBufferTransforms)]]
) {
    MUIImage m = records[in.imageID];
    uint transformIndex = m.filter >> 8;
    if (transformIndex != 0) {
        // Under a transform (ruling GX-F): the same filter at UVs clamped to
        // the texture, times the quad's antialiased edge and both masks.
        MUITransform t = fragmentTransforms[transformIndex - 1];
        float2 uv = clamp(in.uv, 0.0, 1.0);
        float4 sampled;
        if ((m.filter & 0xFF) == MUIImageFilterNearest) {
            uint2 size = uint2(image.get_width(), image.get_height());
            sampled = image.read(min(uint2(uv * float2(size)), size - 1));
        } else {
            constexpr sampler transformed_sampler(coord::normalized,
                                                  address::clamp_to_edge,
                                                  filter::linear);
            sampled = image.sample(transformed_sampler, uv);
        }
        float coverage = quad_edge(in.pixelPosition, m.bounds, t.pixelScale)
                       * mask_coverage_scaled(in.pixelPosition, m.contentMask, m.maskCornerRadii, t.pixelScale)
                       * mask_coverage(in.screenPosition, t.outerMask, t.outerMaskRadii);
        return sampled * (m.opacity * coverage);
    }
    float4 texel;
    if (m.filter == MUIImageFilterNearest) {
        uint2 size = uint2(image.get_width(), image.get_height());
        texel = image.read(min(uint2(in.uv * float2(size)), size - 1));
    } else {
        constexpr sampler image_sampler(coord::normalized,
                                        address::clamp_to_edge,
                                        filter::linear);
        texel = image.sample(image_sampler, in.uv);
    }
    // Premultiplied already (`ImageTexture`), so opacity and the clip scale
    // all four channels, to pair with a (one, oneMinusSourceAlpha) blend.
    float clip = mask_coverage(in.pixelPosition, m.contentMask, m.maskCornerRadii);
    return texel * (m.opacity * clip);
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


// Metal's view of `MUIImage` and of `MUIRect.shape`, read by
// `metalAndSwiftAgreeOnTheImageStructAndTheShapeField`. Its own kernel, so
// `abi_probe`'s 32-slot readers above are untouched.
kernel void image_abi_probe(
    device MUIUInt    *out [[buffer(MUIProbeBufferOut)]],
    constant MUIRect  &r   [[buffer(MUIProbeBufferRect)]],
    constant MUIImage &m   [[buffer(MUIProbeBufferImage)]]
) {
    out[0]  = (MUIUInt)sizeof(MUIImage);
    out[1]  = (MUIUInt)m.bounds.origin.x;
    out[2]  = (MUIUInt)m.bounds.size.height;
    out[3]  = (MUIUInt)m.contentMask.origin.x;
    out[4]  = (MUIUInt)m.contentMask.size.height;
    out[5]  = (MUIUInt)m.maskCornerRadii.topLeft;
    out[6]  = (MUIUInt)m.maskCornerRadii.bottomLeft;
    out[7]  = (MUIUInt)(m.opacity * 1000.0);
    out[8]  = m.texture;
    out[9]  = m.filter;
    out[10] = m.order;
    out[11] = (MUIUInt)sizeof(MUIRect);
    out[12] = r.order;
    out[13] = r.shape;
}


// Metal's view of `MUITransform` (ruling GX-F), read by
// `metalAndSwiftAgreeOnTheTransformStruct`: each float ×10, then `_reserved`.
kernel void transform_abi_probe(
    device MUIUInt         *out [[buffer(MUIProbeBufferOut)]],
    constant MUITransform  &t   [[buffer(MUIProbeBufferTransform)]]
) {
    out[0]  = (MUIUInt)sizeof(MUITransform);
    out[1]  = (MUIUInt)(t.a * 10.0);
    out[2]  = (MUIUInt)(t.b * 10.0);
    out[3]  = (MUIUInt)(t.c * 10.0);
    out[4]  = (MUIUInt)(t.d * 10.0);
    out[5]  = (MUIUInt)(t.tx * 10.0);
    out[6]  = (MUIUInt)(t.ty * 10.0);
    out[7]  = (MUIUInt)(t.pixelScale * 10.0);
    out[8]  = t._reserved;
    out[9]  = (MUIUInt)(t.outerMask.origin.x * 10.0);
    out[10] = (MUIUInt)(t.outerMask.origin.y * 10.0);
    out[11] = (MUIUInt)(t.outerMask.size.width * 10.0);
    out[12] = (MUIUInt)(t.outerMask.size.height * 10.0);
    out[13] = (MUIUInt)(t.outerMaskRadii.topLeft * 10.0);
    out[14] = (MUIUInt)(t.outerMaskRadii.topRight * 10.0);
    out[15] = (MUIUInt)(t.outerMaskRadii.bottomLeft * 10.0);
}
