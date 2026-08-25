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
    MUIBounds contentMask;
    MUIHsla background;
    MUIHsla borderColor;
    MUICorners cornerRadii;
    MUIEdges borderWidths;
    MUIUInt order;
    MUIUInt _reserved;
} MUIRect;

typedef enum {
    MUIRectBufferVertices   = 0,
    MUIRectBufferRects      = 1,
    MUIRectBufferViewport   = 2,
    MUIRectBufferProjection = 3
} MUIRectBufferIndex;

typedef enum {
    MUIProbeBufferOut  = 0,
    MUIProbeBufferRect = 1
} MUIProbeBufferIndex;

#endif
