// Portable replay shaders. Compile six times: VERTEX_STAGE or not, times
// no kind define (rects), GLYPH_STAGE or IMAGE_STAGE; and, since the backdrop
// blur (rulings BB-A, BB-D, BB-J), five more: BACKDROP_STAGE in both stages
// (a material's blurred quad, shaders.metal's `backdrop_vertex` and
// `backdrop_fragment`), and PASS_STAGE (a full-target triangle; with
// DOWNSAMPLE_STAGE or GAUSSIAN_STAGE its fragment is one blur pass,
// shaders.metal's `backdrop_pass_vertex`, `backdrop_downsample_fragment`,
// `backdrop_gaussian_fragment`, statement for statement, TE-AD).
// Storage is float4 lanes: rectangle stride 8 lanes (128 bytes), glyph 6 (96),
// image 4 (64, uploaded as recorded), transform 4 (64, `MUITransform`, ruling
// GX-F). Uniforms occupy 16 and 64 bytes. See SDLBridge.c for the packing
// boundary. A backdrop record (MUIBackdrop, 96 bytes) is 6 lanes, uploaded as
// recorded. A primitive's transform index (rect lane 7 .y and image lane 3 .z
// bits 8…31, glyph lane 5 .y) is 0 for today's code; i > 0 reads transform
// record i − 1 — shaders.metal's transformed branches, statement for statement.
#ifdef PASS_STAGE
// ---------------------------------------------------------------------------
// The blur passes (ruling BB-D, BB-S). `PassConstants` is shaders.metal's
// `BackdropBlurPass`: the source rectangle (origin x, y, size w, h) in the
// source texture, the Gaussian's sigma at this level and its axis. Texels are
// FETCHED, never filtered: a point sampler at the texel centre returns the
// texel exactly (the Metal shader `read`s; a sampler is bound so the stage's
// resource is the combined image sampler SDL's SPIR-V convention expects).
// ---------------------------------------------------------------------------
struct PassVertexOut {
    float4 position : SV_Position;
};
#ifdef VERTEX_STAGE
PassVertexOut main(uint vertexID : SV_VertexID) {
    float2 p = float2(float((vertexID << 1) & 2), float(vertexID & 2));
    PassVertexOut result;
    result.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return result;
}
#else
Texture2D<float4> source : register(t0, space2);
SamplerState sourceSampler : register(s0, space2);
cbuffer Pass : register(b0, space3) { int4 passSource; float passSigma; int passHorizontal; };
float4 fetch(int2 texel) {
    uint width, height;
    source.GetDimensions(width, height);
    return source.SampleLevel(sourceSampler, (float2(texel) + 0.5) / float2(width, height), 0);
}
float4 main(PassVertexOut input) : SV_Target0 {
    int2 p = int2(input.position.xy);
    int2 origin = passSource.xy;
    int2 last = passSource.zw - 1;
#ifdef DOWNSAMPLE_STAGE
    int2 lo = min(2 * p, last);
    int2 hi = min(2 * p + 1, last);
    float4 a = fetch(origin + int2(lo.x, lo.y)) + fetch(origin + int2(hi.x, lo.y));
    float4 b = fetch(origin + int2(lo.x, hi.y)) + fetch(origin + int2(hi.x, hi.y));
    return (a + b) * 0.25;
#else
    float sigma = passSigma;
    int radius = sigma > 0.0 ? int(ceil(3.0 * sigma)) : 0;
    int2 axis = passHorizontal != 0 ? int2(1, 0) : int2(0, 1);
    float twoSigmaSquared = 2.0 * sigma * sigma;
    float total = 1.0;
    float4 sum = fetch(origin + min(p, last));
    for (int i = 1; i <= radius; i++) {
        float w = exp(-float(i * i) / twoSigmaSquared);
        total += 2.0 * w;
        int2 l = clamp(p - axis * i, int2(0, 0), last);
        int2 r = clamp(p + axis * i, int2(0, 0), last);
        sum += w * (fetch(origin + l) + fetch(origin + r));
    }
    return sum / total;
#endif
}
#endif
#else
#if defined(GLYPH_STAGE) || defined(IMAGE_STAGE)
#define SPRITE_STAGE
#endif
#ifdef VERTEX_STAGE
cbuffer Viewport : register(b0, space1) { float2 viewport; uint firstInstance; uint viewportPadding; };
cbuffer Projection : register(b1, space1) { column_major float4x4 projection; };
StructuredBuffer<float4> units : register(t0, space0);
StructuredBuffer<float4> primitives : register(t1, space0);
StructuredBuffer<float4> transforms : register(t2, space0);
#else
#ifdef GLYPH_STAGE
Texture2D<float> atlas : register(t0, space2);
SamplerState atlasSampler : register(s0, space2);
StructuredBuffer<float4> primitives : register(t1, space2);
StructuredBuffer<float4> transforms : register(t2, space2);
#elif defined(IMAGE_STAGE)
Texture2D<float4> image : register(t0, space2);
SamplerState imageSampler : register(s0, space2);
StructuredBuffer<float4> primitives : register(t1, space2);
StructuredBuffer<float4> transforms : register(t2, space2);
#elif defined(BACKDROP_STAGE)
// The blurred level-L texture; `drawConstants` is (region origin x, y, uv scale
// x, y), shaders.metal's `draw` (BB-R).
Texture2D<float4> blurred : register(t0, space2);
SamplerState blurredSampler : register(s0, space2);
StructuredBuffer<float4> primitives : register(t1, space2);
StructuredBuffer<float4> transforms : register(t2, space2);
cbuffer Draw : register(b0, space3) { float4 drawConstants; };
#else
StructuredBuffer<float4> primitives : register(t0, space2);
StructuredBuffer<float4> transforms : register(t1, space2);
#endif
#endif

struct VertexOut {
    float4 position : SV_Position;
    // Local under a transform (the SDFs and content mask read it), the
    // render-target position otherwise.
    float2 pixelPosition : TEXCOORD0;
    // The render-target position before the projection: the outer mask's.
    float2 screenPosition : TEXCOORD3;
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
#elif defined(BACKDROP_STAGE)
    uint base = id * 6;
#else
    uint base = id * 8;
#endif
    float2 unit = units[vertexID].xy;
    float4 bounds = primitives[base];
#ifdef GLYPH_STAGE
    uint transformIndex = asuint(primitives[base + 5].y);
#elif defined(IMAGE_STAGE)
    uint transformIndex = asuint(primitives[base + 3].z) >> 8;
#elif defined(BACKDROP_STAGE)
    uint transformIndex = asuint(primitives[base + 5].y) >> 8;
#else
    uint transformIndex = asuint(primitives[base + 7].y) >> 8;
#endif
    float2 pos;
    float2 local;
#ifdef SPRITE_STAGE
    float2 atlasPosition;
#endif
    if (transformIndex == 0) {
        pos = bounds.xy + unit * bounds.zw;
        local = pos;
#ifdef GLYPH_STAGE
        float4 source = primitives[base + 1];
        atlasPosition = source.xy + unit * source.zw;
#elif defined(IMAGE_STAGE)
        atlasPosition = unit;
#endif
    } else {
        uint record = (transformIndex - 1) * 4;
        float4 lin = transforms[record];
        float4 translation = transforms[record + 1];
        float fringe = 1.0 / translation.z;
#ifdef SPRITE_STAGE
        float2 grown = unit * (bounds.zw + 2.0 * fringe) - fringe;
        local = bounds.xy + grown;
        float2 fraction = float2(bounds.z > 0.0 ? grown.x / bounds.z : 0.0, bounds.w > 0.0 ? grown.y / bounds.w : 0.0);
#ifdef GLYPH_STAGE
        float4 source = primitives[base + 1];
        atlasPosition = source.xy + fraction * source.zw;
#else
        atlasPosition = fraction;
#endif
#else
        local = bounds.xy - fringe + unit * (bounds.zw + 2.0 * fringe);
#endif
        pos = float2(lin.x * local.x + lin.z * local.y + translation.x,
                     lin.y * local.x + lin.w * local.y + translation.y);
    }
    float2 ndc = pos / viewport * float2(2, -2) + float2(-1, 1);
    VertexOut result;
    result.position = mul(projection, float4(ndc, 0, 1));
    result.pixelPosition = local;
    result.screenPosition = pos;
    result.primitiveID = id;
#ifdef SPRITE_STAGE
    result.atlasPosition = atlasPosition;
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
// shaders.metal's `mask_coverage_scaled` (ruling GX-F): a transformed
// primitive's local content mask, its distance in screen pixels.
float maskCoverageScaled(float2 p, float4 bounds, float4 radii, float s) {
    float2 halfSize = bounds.zw * 0.5;
    float2 rel = p - bounds.xy - halfSize;
    return saturate(0.5 - rectSDF(rel, halfSize, cornerRadius(rel, radii)) * s);
}
// shaders.metal's `quad_edge`: a transformed sprite's own antialiased edge.
float quadEdge(float2 p, float4 bounds, float s) {
    float2 halfSize = bounds.zw * 0.5;
    return saturate(0.5 - rectSDF(p - (bounds.xy + halfSize), halfSize, 0.0) * s);
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
#ifndef GLYPH_STAGE
#ifndef IMAGE_STAGE
// shaders.metal's `rect_shade`: colour times edge coverage, every distance
// scaled by `s` — the literal 1.0 for an untransformed rect, folded away.
float4 rectShade(uint base, float2 pixelPosition, float s) {
    float4 bounds = primitives[base];
    float2 halfSize = bounds.zw * 0.5;
    float2 p = pixelPosition - (bounds.xy + halfSize);
    float4 widths = primitives[base + 6]; // top, right, bottom, left
    float outerAlpha;
    float innerAlpha;
    // Lane 7: (order, shape, padding, padding) — shape's low byte 1 is the
    // ellipse (TE-AE); bits 8…31 the transform (GX-F).
    if ((asuint(primitives[base + 7].y) & 0xFF) == 1) {
        float w = widths.x;
        float2 inset = halfSize - w * 0.5;
        if (w <= 0.0) {
            outerAlpha = saturate(0.5 - ellipseSDF(p, halfSize) * s);
            innerAlpha = outerAlpha;
        } else if (min(inset.x, inset.y) <= 0.0) {
            outerAlpha = saturate(0.5 - ellipseSDF(p, halfSize) * s);
            innerAlpha = 0.0;
        } else {
            float d = ellipseSDF(p, inset);
            outerAlpha = saturate(0.5 - (d - w * 0.5) * s);
            innerAlpha = saturate(0.5 - (d + w * 0.5) * s);
        }
    } else {
        float radius = cornerRadius(p, primitives[base + 5]);
        outerAlpha = saturate(0.5 - rectSDF(p, halfSize, radius) * s);
        float2 border = float2(p.x < 0 ? widths.w : widths.y, p.y < 0 ? widths.x : widths.z);
        float innerRadius = max(radius - max(border.x, border.y), 0.0);
        innerAlpha = saturate(0.5 - rectSDF(p, max(halfSize - border, 0.0), innerRadius) * s);
    }
    float borderMix = outerAlpha > 0 ? saturate(innerAlpha / outerAlpha) : 0;
    float4 color = lerp(hslaToRGBA(primitives[base + 4]), hslaToRGBA(primitives[base + 3]), borderMix);
    return float4(color.rgb * color.a, color.a) * outerAlpha;
}
#endif
#endif
#ifdef BACKDROP_STAGE
// shaders.metal's `backdrop_coverage`: the rect shader's outer coverage of a
// white borderless rect of the record's bounds and shape (the record's lanes:
// bounds 0, mask 1, mask radii 2, corner radii 3, tint 4, (order, shape, sigma,
// opacity) 5), every distance scaled by `s`.
float backdropCoverage(uint base, float2 pixelPosition, float s) {
    float4 bounds = primitives[base];
    float2 halfSize = bounds.zw * 0.5;
    float2 p = pixelPosition - (bounds.xy + halfSize);
    if ((asuint(primitives[base + 5].y) & 0xFF) == 1) {
        return saturate(0.5 - ellipseSDF(p, halfSize) * s);
    }
    float radius = cornerRadius(p, primitives[base + 3]);
    return saturate(0.5 - rectSDF(p, halfSize, radius) * s);
}
#endif
float4 main(VertexOut input) : SV_Target0 {
#ifdef BACKDROP_STAGE
    // `c * o * (T + (1 - T.a) * B)`, premultiplied (shaders.metal's `backdrop_fragment`).
    uint base = input.primitiveID * 6;
    uint transformIndex = asuint(primitives[base + 5].y) >> 8;
    float s = 1.0;
    float clip;
    if (transformIndex == 0) {
        clip = maskCoverage(input.pixelPosition, primitives[base + 1], primitives[base + 2]);
    } else {
        uint record = (transformIndex - 1) * 4;
        s = transforms[record + 1].z;
        clip = maskCoverageScaled(input.pixelPosition, primitives[base + 1], primitives[base + 2], s)
             * maskCoverage(input.screenPosition, transforms[record + 2], transforms[record + 3]);
    }
    float c = backdropCoverage(base, input.pixelPosition, s) * clip;
    float4 tc = hslaToRGBA(primitives[base + 4]);
    float4 tint = float4(tc.rgb * tc.a, tc.a);
    float opacity = primitives[base + 5].w;
    float2 uv = (input.screenPosition - drawConstants.xy) * drawConstants.zw;
    float4 behind = blurred.SampleLevel(blurredSampler, uv, 0);
    return c * opacity * (tint + (1.0 - tint.a) * behind);
#elif defined(GLYPH_STAGE)
    uint base = input.primitiveID * 6;
    uint width, height;
    atlas.GetDimensions(width, height);
    uint transformIndex = asuint(primitives[base + 5].y);
    if (transformIndex != 0) {
        uint record = (transformIndex - 1) * 4;
        float4 translation = transforms[record + 1];
        float s = translation.z;
        float4 slot = primitives[base + 1];
        float2 inside = clamp(input.atlasPosition, slot.xy + 0.5, slot.xy + slot.zw - 0.5);
        float sampled = atlas.Sample(atlasSampler, inside / float2(width, height))
                      * quadEdge(input.pixelPosition, primitives[base], s);
        float4 tinted = hslaToRGBA(primitives[base + 4]);
        float masks = maskCoverageScaled(input.pixelPosition, primitives[base + 2], primitives[base + 3], s)
                    * maskCoverage(input.screenPosition, transforms[record + 2], transforms[record + 3]);
        float transformedAlpha = tinted.a * sampled * masks;
        return float4(tinted.rgb * transformedAlpha, transformedAlpha);
    }
    float coverage = atlas.Sample(atlasSampler, input.atlasPosition / float2(width, height));
    float4 tint = hslaToRGBA(primitives[base + 4]);
    float clip = maskCoverage(input.pixelPosition, primitives[base + 2], primitives[base + 3]);
    float alpha = tint.a * coverage * clip;
    return float4(tint.rgb * alpha, alpha);
#elif defined(IMAGE_STAGE)
    // Lanes: bounds, contentMask, maskCornerRadii, (opacity, texture, filter, order).
    uint base = input.primitiveID * 4;
    float4 fields = primitives[base + 3];
    uint transformIndex = asuint(fields.z) >> 8;
    if (transformIndex != 0) {
        uint record = (transformIndex - 1) * 4;
        float s = transforms[record + 1].z;
        float2 uv = clamp(input.atlasPosition, 0.0, 1.0);
        float4 sampled;
        if ((asuint(fields.z) & 0xFF) == 1) {
            uint width, height;
            image.GetDimensions(width, height);
            uint2 size = uint2(width, height);
            sampled = image.Load(int3(min(uint2(uv * float2(size)), size - 1), 0));
        } else {
            sampled = image.Sample(imageSampler, uv);
        }
        float coverage = quadEdge(input.pixelPosition, primitives[base], s)
                       * maskCoverageScaled(input.pixelPosition, primitives[base + 1], primitives[base + 2], s)
                       * maskCoverage(input.screenPosition, transforms[record + 2], transforms[record + 3]);
        return sampled * (fields.x * coverage);
    }
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
    uint transformIndex = asuint(primitives[base + 7].y) >> 8;
    if (transformIndex == 0) {
        float clip = maskCoverage(input.pixelPosition, primitives[base + 1], primitives[base + 2]);
        return rectShade(base, input.pixelPosition, 1.0) * clip;
    }
    uint record = (transformIndex - 1) * 4;
    float s = transforms[record + 1].z;
    float clip = maskCoverageScaled(input.pixelPosition, primitives[base + 1], primitives[base + 2], s)
               * maskCoverage(input.screenPosition, transforms[record + 2], transforms[record + 3]);
    return rectShade(base, input.pixelPosition, s) * clip;
#endif
}
#endif
#endif
