// Portable replay shaders. Compile six times: VERTEX_STAGE or not, times
// no kind define (rects), GLYPH_STAGE or IMAGE_STAGE.
// Storage is float4 lanes: rectangle stride 8 lanes (128 bytes), glyph 6 (96),
// image 4 (64, uploaded as recorded). Uniforms occupy 16 and 64 bytes. See
// SDLBridge.c for the packing boundary.
#if defined(GLYPH_STAGE) || defined(IMAGE_STAGE)
#define SPRITE_STAGE
#endif
#ifdef VERTEX_STAGE
cbuffer Viewport : register(b0, space1) { float2 viewport; uint firstInstance; uint viewportPadding; };
cbuffer Projection : register(b1, space1) { column_major float4x4 projection; };
StructuredBuffer<float4> units : register(t0, space0);
StructuredBuffer<float4> primitives : register(t1, space0);
#else
#ifdef GLYPH_STAGE
Texture2D<float> atlas : register(t0, space2);
SamplerState atlasSampler : register(s0, space2);
StructuredBuffer<float4> primitives : register(t1, space2);
#elif defined(IMAGE_STAGE)
Texture2D<float4> image : register(t0, space2);
SamplerState imageSampler : register(s0, space2);
StructuredBuffer<float4> primitives : register(t1, space2);
#else
StructuredBuffer<float4> primitives : register(t0, space2);
#endif
#endif

struct VertexOut {
    float4 position : SV_Position;
    float2 pixelPosition : TEXCOORD0;
#ifdef SPRITE_STAGE
    // Glyph: atlas texels. Image: 0...1 across the quad (normalised UVs).
    float2 atlasPosition : TEXCOORD1;
    nointerpolation uint primitiveID : TEXCOORD2;
#else
    nointerpolation uint primitiveID : TEXCOORD1;
#endif
};

#ifdef VERTEX_STAGE
VertexOut main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    uint id = instanceID + firstInstance;
#ifdef GLYPH_STAGE
    uint base = id * 6;
#elif defined(IMAGE_STAGE)
    uint base = id * 4;
#else
    uint base = id * 8;
#endif
    float2 unit = units[vertexID].xy;
    float4 bounds = primitives[base];
    float2 pos = bounds.xy + unit * bounds.zw;
    float2 ndc = pos / viewport * float2(2, -2) + float2(-1, 1);
    VertexOut result;
    result.position = mul(projection, float4(ndc, 0, 1));
    result.pixelPosition = pos;
    result.primitiveID = id;
#ifdef GLYPH_STAGE
    float4 source = primitives[base + 1];
    result.atlasPosition = source.xy + unit * source.zw;
#elif defined(IMAGE_STAGE)
    result.atlasPosition = unit;
#endif
    return result;
}
#else
float rectSDF(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}
// shaders.metal's `ellipse_sdf`, statement for statement and constant for
// constant (ruling TE-AQ item 6): the trig-free three-iteration closest-point
// method, so Metal, Vulkan and Direct3D agree at the parity tolerance.
float ellipseSDF(float2 p, float2 h) {
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
float cornerRadius(float2 p, float4 corners) {
    return p.x < 0 ? (p.y < 0 ? corners.x : corners.w) : (p.y < 0 ? corners.y : corners.z);
}
float maskCoverage(float2 p, float4 bounds, float4 radii) {
    float2 halfSize = bounds.zw * 0.5;
    float2 rel = p - bounds.xy - halfSize;
    return saturate(0.5 - rectSDF(rel, halfSize, cornerRadius(rel, radii)));
}
float4 hslaToRGBA(float4 hsla) {
    float h = hsla.x * 6.0;
    float c = (1.0 - abs(2.0 * hsla.z - 1.0)) * hsla.y;
    float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
    float m = hsla.z - c / 2.0;
    float3 rgb;
    if (h < 1) rgb = float3(c, x, 0);
    else if (h < 2) rgb = float3(x, c, 0);
    else if (h < 3) rgb = float3(0, c, x);
    else if (h < 4) rgb = float3(0, x, c);
    else if (h < 5) rgb = float3(x, 0, c);
    else rgb = float3(c, 0, x);
    return float4(rgb + m, hsla.w);
}
float4 main(VertexOut input) : SV_Target0 {
#ifdef GLYPH_STAGE
    uint base = input.primitiveID * 6;
    uint width, height;
    atlas.GetDimensions(width, height);
    float coverage = atlas.Sample(atlasSampler, input.atlasPosition / float2(width, height));
    float4 tint = hslaToRGBA(primitives[base + 4]);
    float clip = maskCoverage(input.pixelPosition, primitives[base + 2], primitives[base + 3]);
    float alpha = tint.a * coverage * clip;
    return float4(tint.rgb * alpha, alpha);
#elif defined(IMAGE_STAGE)
    // Lanes: bounds, contentMask, maskCornerRadii, (opacity, texture, filter, order).
    uint base = input.primitiveID * 4;
    float4 fields = primitives[base + 3];
    float4 texel;
    if (asuint(fields.z) == 1) {
        // Nearest: the texel under the pixel, read, not sampled (no second sampler).
        uint width, height;
        image.GetDimensions(width, height);
        uint2 size = uint2(width, height);
        texel = image.Load(int3(min(uint2(input.atlasPosition * float2(size)), size - 1), 0));
    } else {
        texel = image.Sample(imageSampler, input.atlasPosition);
    }
    float clip = maskCoverage(input.pixelPosition, primitives[base + 1], primitives[base + 2]);
    return texel * (fields.x * clip);
#else
    uint base = input.primitiveID * 8;
    float4 bounds = primitives[base];
    float2 halfSize = bounds.zw * 0.5;
    float2 p = input.pixelPosition - (bounds.xy + halfSize);
    float4 widths = primitives[base + 6]; // top, right, bottom, left
    float outerAlpha;
    float innerAlpha;
    // Lane 7: (order, shape, padding, padding) — shape 1 is the ellipse (TE-AE).
    if (asuint(primitives[base + 7].y) == 1) {
        float w = widths.x;
        float2 inset = halfSize - w * 0.5;
        if (w <= 0.0) {
            outerAlpha = saturate(0.5 - ellipseSDF(p, halfSize));
            innerAlpha = outerAlpha;
        } else if (min(inset.x, inset.y) <= 0.0) {
            outerAlpha = saturate(0.5 - ellipseSDF(p, halfSize));
            innerAlpha = 0.0;
        } else {
            float d = ellipseSDF(p, inset);
            outerAlpha = saturate(0.5 - (d - w * 0.5));
            innerAlpha = saturate(0.5 - (d + w * 0.5));
        }
    } else {
        float radius = cornerRadius(p, primitives[base + 5]);
        outerAlpha = saturate(0.5 - rectSDF(p, halfSize, radius));
        float2 border = float2(p.x < 0 ? widths.w : widths.y, p.y < 0 ? widths.x : widths.z);
        float innerRadius = max(radius - max(border.x, border.y), 0.0);
        innerAlpha = saturate(0.5 - rectSDF(p, max(halfSize - border, 0.0), innerRadius));
    }
    float borderMix = outerAlpha > 0 ? saturate(innerAlpha / outerAlpha) : 0;
    float4 color = lerp(hslaToRGBA(primitives[base + 4]), hslaToRGBA(primitives[base + 3]), borderMix);
    float clip = maskCoverage(input.pixelPosition, primitives[base + 1], primitives[base + 2]);
    return float4(color.rgb * color.a, color.a) * outerAlpha * clip;
#endif
}
#endif
