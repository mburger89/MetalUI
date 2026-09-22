// Portable replay shaders. Compile four times with VERTEX_STAGE and GLYPH_STAGE.
// Storage is float4 lanes: rectangle stride 8 lanes (128 bytes), glyph 6 (96).
// Uniforms occupy 16 and 64 bytes. See SDLBridge.c for the packing boundary.
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
#else
StructuredBuffer<float4> primitives : register(t0, space2);
#endif
#endif

struct VertexOut {
    float4 position : SV_Position;
    float2 pixelPosition : TEXCOORD0;
#ifdef GLYPH_STAGE
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
#endif
    return result;
}
#else
float rectSDF(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
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
#else
    uint base = input.primitiveID * 8;
    float4 bounds = primitives[base];
    float2 halfSize = bounds.zw * 0.5;
    float2 p = input.pixelPosition - (bounds.xy + halfSize);
    float radius = cornerRadius(p, primitives[base + 5]);
    float outerAlpha = saturate(0.5 - rectSDF(p, halfSize, radius));
    float4 widths = primitives[base + 6]; // top, right, bottom, left
    float2 border = float2(p.x < 0 ? widths.w : widths.y, p.y < 0 ? widths.x : widths.z);
    float innerRadius = max(radius - max(border.x, border.y), 0.0);
    float innerAlpha = saturate(0.5 - rectSDF(p, max(halfSize - border, 0.0), innerRadius));
    float borderMix = outerAlpha > 0 ? saturate(innerAlpha / outerAlpha) : 0;
    float4 color = lerp(hslaToRGBA(primitives[base + 4]), hslaToRGBA(primitives[base + 3]), borderMix);
    float clip = maskCoverage(input.pixelPosition, primitives[base + 1], primitives[base + 2]);
    return float4(color.rgb * color.a, color.a) * outerAlpha * clip;
#endif
}
#endif
