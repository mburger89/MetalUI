/* stb_image 2.30, compiled once (ruling PX-B; VENDORED.md). PNG and JPEG
   only; no stdio (MetalUI reads the bytes); no HDR or linear float paths; no
   failure strings; the scalar decode paths on every platform (STBI_NO_SIMD,
   ruling PX-O item 4: the parity table was measured on them); and no side
   longer than 16384, the largest texture side both renderers guarantee — a
   file claiming more is refused before any allocation. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_NO_FAILURE_STRINGS
#define STBI_NO_SIMD
#define STBI_MAX_DIMENSIONS 16384

#include "CStbImage.h"

/* No #pragma clang diagnostic: neither build system raises a warning here
   (measured, VENDORED.md). */
#include "stb_image.h"
