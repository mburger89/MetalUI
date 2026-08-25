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
    float4 color = mix(borderColor, background, innerAlpha);

    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    return float4(color.rgb * color.a, color.a) * outerAlpha;
}

// ---------------------------------------------------------------------------
// ABI probe
//
// Reports Metal's view of the shared structs so a host test can compare it with
// Swift's. Catches MSL-vs-C layout divergence, which the Swift compiler cannot
// see. (C-vs-Swift divergence is impossible: Swift imports the same header.)
// ---------------------------------------------------------------------------

kernel void abi_probe(
    device MUIUInt   *out [[buffer(MUIProbeBufferOut)]],
    constant MUIRect &r   [[buffer(MUIProbeBufferRect)]]
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
}
