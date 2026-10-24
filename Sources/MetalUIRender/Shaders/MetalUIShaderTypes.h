#ifndef METALUI_SHADER_TYPES_H
#define METALUI_SHADER_TYPES_H

// This file is compiled two ways:
//   1. by clang, via a symlink in MetalUIShaderTypes/include, so Swift imports these structs
//   2. by the Metal compiler at runtime, textually prepended to shaders.metal
// Guard anything that only one of them understands.

#ifndef __METAL_VERSION__
#include <stdint.h>
typedef uint32_t MUIUInt;
#else
typedef uint MUIUInt;
#endif

typedef struct { float x, y; } MUIPoint;
typedef struct { float width, height; } MUISize;
typedef struct { MUIPoint origin; MUISize size; } MUIBounds;
typedef struct { float h, s, l, a; } MUIHsla;
typedef struct { float topLeft, topRight, bottomRight, bottomLeft; } MUICorners;
typedef struct { float top, right, bottom, left; } MUIEdges;

// All geometry is in ScaledPixels (logical points x display scale), matching
// the fragment shader's [[position]], which is in render-target pixels.
typedef struct {
    MUIBounds bounds;
    // Axis-aligned clip, same space as `bounds`. `rect_fragment` multiplies
    // coverage by it, antialiased on the same half-pixel threshold as the
    // rect's own edge. The whole surface means "no clip" and is what
    // `Frame.fill` passes when no clip stack is active.
    MUIBounds contentMask;
    // Corner radii for `contentMask`, in the same space as `bounds` and
    // interpreted by `pick_corner_radius`/`rect_sdf` exactly as `cornerRadii`
    // below is for the rect's own edge. All-zero — the zero value every call
    // site written before this field existed gets by default — is a square
    // clip, identical to `contentMask` alone.
    MUICorners maskCornerRadii;
    MUIHsla background;
    MUIHsla borderColor;
    MUICorners cornerRadii;
    MUIEdges borderWidths;
    MUIUInt order;
    // Which outline `bounds` holds (`MUIShape`): 0, a rounded rectangle with
    // `cornerRadii` — the zero value every scene written before this field
    // existed carries, since it was `_reserved`, always 0 — or 1, the ellipse
    // inscribed in `bounds` (ruling TE-AE), which ignores `cornerRadii` and
    // reads one border width, `borderWidths.top`, as SwiftUI's inset-ellipse
    // band. The same word the field replaced, so the struct's size, the
    // replay packing (8 lanes) and every recorded scene's bytes are unchanged.
    MUIUInt shape;
} MUIRect;

typedef enum {
    MUIShapeRoundedRect = 0,
    MUIShapeEllipse     = 1
} MUIShape;

// A material's backdrop (ruling BB-A, BB-B): the blurred pixels already drawn
// beneath `bounds`, with `tint` composited over them, shape-masked, with an
// opacity -- ONE primitive, `c * o * (T + (1 - T.a) * B)` (premultiplied), so a
// fade reproduces SwiftUI's half-weight composite of the whole layer. 96 bytes:
// six `float4` lanes, so the SDL bridge uploads the records as they are.
//
// **256 bytes since Liquid Glass (ruling LG-B)**: the six lanes above did not
// move (offsets 0, 16, 32, 48, 64, 80, 84, 88, 92, pinned), and a glass tail of
// ten more lanes follows -- two look lanes (96...127) and four members of two
// lanes each (128...255). A material's tail is all zero and `glassFlags == 0`
// takes today's arithmetic byte for byte. The tail:
//   `glassFlags`  bit 0 glass, 1 lensRim, 2 dark (the scheme the record was
//                 resolved for; no arithmetic reads it), 3...5 member count
//                 (zero or one read the record itself, more than four are four),
//                 6...9 member k is an ellipse
//   `lensDepth`, `band`, `rimStrength`   device pixels, device pixels, alpha
//   `blendK`      the smooth-min blend radius, device pixels
//   `press`, `pressLift`   0...1 and the white lift's alpha at press 1
//   `member0...3` a member's bounds as fractions of `bounds` (origin and size)
//                 and its four corner radii as fractions of `bounds`' shorter
//                 side, so every site that translates or scales `bounds` moves
//                 the members with it. Read only when the count is two or more.
//
// `bounds`, `contentMask`, `maskCornerRadii`, `cornerRadii` and `shape` mean
// exactly what they mean on `MUIRect` (`shape`: `MUIShape` in bits 0...7, the
// transform index, 1 + an index into `Scene.transforms`, in bits 8...31, ruling
// GX-F). `tint` is straight alpha, like a rect's `background`. `sigma` is the
// blur's standard deviation in DEVICE pixels (`MUIBackdropSigmaPoints` x the
// display scale); `opacity` multiplies the whole result.
typedef struct {
    MUIBounds bounds;
    MUICorners radii;
} MUIGlassMember;

typedef struct {
    MUIBounds bounds;
    MUIBounds contentMask;
    MUICorners maskCornerRadii;
    MUICorners cornerRadii;
    MUIHsla tint;
    MUIUInt order;
    MUIUInt shape;
    float sigma;
    float opacity;
    MUIUInt glassFlags;
    float lensDepth;
    float band;
    float rimStrength;
    float blendK;
    float press;
    float pressLift;
    float glassReserved;
    MUIGlassMember member0;
    MUIGlassMember member1;
    MUIGlassMember member2;
    MUIGlassMember member3;
} MUIBackdrop;

// The blur's standard deviation in points, one constant for all six materials
// (ruling BB-D 1, probe swiftui-backdrop-blur.swift), and the most 2x
// downsample levels the pyramid uses before its Gaussian.
#define MUIBackdropSigmaPoints 52.0
#define MUIBackdropBlurMaxLevel 6

// An affine per instance (ruling GX-F): 64 bytes, four `float4` lanes, so the
// SDL bridge uploads the table as it is. A primitive names one by
// 1 + its index in `Scene.transforms`: `MUIRect.shape` bits 8…31,
// `MUIImage.filter` bits 8…31 (surfaces share the record), `MUIGlyph.transform`.
// Index 0 means identity and is never stored, so bits 0…7 of `shape`/`filter`
// keep their kind and every scene written before this struct existed keeps
// its bytes.
//
// The primitive's `bounds` and `contentMask` are then LOCAL (device pixels
// before the affine); `x' = a x + c y + tx`, `y' = b x + d y + ty` maps them
// to the render target. `pixelScale` is `sqrt|ad − bc|` — screen pixels per
// local pixel — which scales every signed distance before the half-pixel
// antialiasing threshold and sizes the vertex stage's one-pixel fringe.
// `outerMask` is the clip in force where the transform began, in SCREEN
// space, multiplied in at the fragment's screen position.
typedef struct {
    float a, b, c, d;
    float tx, ty;
    float pixelScale;
    MUIUInt _reserved;
    MUIBounds  outerMask;
    MUICorners outerMaskRadii;
} MUITransform;

// One glyph sprite: a 1:1 blit of an R8 coverage bitmap, tinted.
//
// `bounds` and `atlasBounds` are the SAME size in every case this renderer can
// currently produce — the atlas is rasterized at the device scale factor and
// `bounds` is in ScaledPixels, which is that same grid — so `glyph_fragment`
// samples texel centres exactly. They are two rectangles rather than an origin
// plus one size because the sprite path is where scaling would land if it ever
// does (a zoomed canvas, spec 7.5), and because a source and a destination that
// share a field cannot be told apart when one of them is wrong.
//
typedef struct {
    MUIBounds bounds;        // destination, ScaledPixels
    MUIBounds atlasBounds;   // source, atlas texels
    // Axis-aligned clip, same space as `bounds`, read by `glyph_fragment`. This
    // struct deliberately had no such field while `MUIRect`'s was inert; it
    // gained one in the same commit that made both live.
    MUIBounds contentMask;
    // Corner radii for `contentMask` — see `MUIRect.maskCornerRadii`. A glyph
    // has no corner radii of its own (a sprite is always a plain rect), so
    // this is the only `MUICorners` field on this struct.
    MUICorners maskCornerRadii;
    MUIHsla   color;         // tint; the R8 atlas carries coverage only
    MUIUInt   order;
    // 1 + an index into the scene's transform table (`MUITransform`, ruling
    // GX-F), or 0 for none — the word that was `_reserved`, always 0, so every
    // scene written before this field existed draws exactly as it did and the
    // struct's size and the replay packing (6 lanes) are unchanged (the
    // precedent is `MUIRect.shape`, TE-AQ item 7).
    MUIUInt   transform;
} MUIGlyph;

// One image: the whole of `Scene.textures[texture]` (premultiplied RGBA8, sRGB
// gamma space) stretched over `bounds` (ruling TE-AF). No source rectangle —
// an image always samples its whole texture, and a `.fill` image's overflow is
// cut by the mask, never by UVs. `filter` is `MUIImageFilter`. 64 bytes: four
// `float4` lanes, so the SDL bridge uploads the records as they are.
typedef struct {
    MUIBounds  bounds;          // destination, ScaledPixels
    MUIBounds  contentMask;     // see `MUIRect.contentMask`
    MUICorners maskCornerRadii; // see `MUIRect.maskCornerRadii`
    float      opacity;         // multiplies the premultiplied texel
    MUIUInt    texture;         // index into the scene's textures
    MUIUInt    filter;
    MUIUInt    order;
} MUIImage;

typedef enum {
    MUIImageFilterLinear  = 0,
    MUIImageFilterNearest = 1
} MUIImageFilter;

typedef enum {
    MUIRectBufferVertices   = 0,
    MUIRectBufferRects      = 1,
    MUIRectBufferViewport   = 2,
    MUIRectBufferProjection = 3,
    // The scene's `MUITransform` table, vertex and fragment (ruling GX-F).
    MUIRectBufferTransforms = 4
} MUIRectBufferIndex;

typedef enum {
    MUIGlyphBufferVertices   = 0,
    MUIGlyphBufferGlyphs     = 1,
    MUIGlyphBufferViewport   = 2,
    MUIGlyphBufferProjection = 3,
    // The scene's `MUITransform` table, vertex and fragment (ruling GX-F).
    MUIGlyphBufferTransforms = 4
} MUIGlyphBufferIndex;

typedef enum {
    MUIGlyphTextureAtlas = 0
} MUIGlyphTextureIndex;

typedef enum {
    MUIImageBufferVertices   = 0,
    MUIImageBufferImages     = 1,
    MUIImageBufferViewport   = 2,
    MUIImageBufferProjection = 3,
    // The scene's `MUITransform` table, vertex and fragment (ruling GX-F).
    MUIImageBufferTransforms = 4
} MUIImageBufferIndex;

typedef enum {
    MUIImageTextureImage = 0
} MUIImageTextureIndex;

typedef enum {
    MUIProbeBufferOut   = 0,
    MUIProbeBufferRect  = 1,
    MUIProbeBufferGlyph = 2,
    MUIProbeBufferImage = 3,
    MUIProbeBufferTransform = 4
} MUIProbeBufferIndex;

#endif
