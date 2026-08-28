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
    MUIHsla background;
    MUIHsla borderColor;
    MUICorners cornerRadii;
    MUIEdges borderWidths;
    MUIUInt order;
    MUIUInt _reserved;
} MUIRect;

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
    MUIHsla   color;         // tint; the R8 atlas carries coverage only
    MUIUInt   order;
    MUIUInt   _reserved;
} MUIGlyph;

typedef enum {
    MUIRectBufferVertices   = 0,
    MUIRectBufferRects      = 1,
    MUIRectBufferViewport   = 2,
    MUIRectBufferProjection = 3
} MUIRectBufferIndex;

typedef enum {
    MUIGlyphBufferVertices   = 0,
    MUIGlyphBufferGlyphs     = 1,
    MUIGlyphBufferViewport   = 2,
    MUIGlyphBufferProjection = 3
} MUIGlyphBufferIndex;

typedef enum {
    MUIGlyphTextureAtlas = 0
} MUIGlyphTextureIndex;

typedef enum {
    MUIProbeBufferOut   = 0,
    MUIProbeBufferRect  = 1,
    MUIProbeBufferGlyph = 2
} MUIProbeBufferIndex;

#endif
