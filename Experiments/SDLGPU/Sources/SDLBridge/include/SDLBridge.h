#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct ReplayGPU ReplayGPU;
typedef struct { uint32_t kind, start, count; } ReplayRun;
ReplayGPU *replay_create(const char *msl);
// shader_dir contains four compiled stages; driver: metal, vulkan, direct3d12.
ReplayGPU *replay_create_portable(const char *shader_dir, const char *driver);
const char *replay_error(void);
const char *replay_driver(ReplayGPU *gpu);
void replay_destroy(ReplayGPU *gpu);
// Synchronous diagnostic renderer. Copies caller bytes before returning.
// Buffers are opaque: Swift supplies the existing MetalUI shader ABI.
bool replay_render(ReplayGPU *gpu, uint32_t width, uint32_t height,
    const void *rects, uint32_t rect_bytes, const void *glyphs, uint32_t glyph_bytes,
    const ReplayRun *runs, uint32_t run_count,
    const uint8_t *atlas, uint32_t atlas_width, uint32_t atlas_height,
    const float *projection, uint8_t *bgra);
// Shows the most recently rendered texture in an SDL window for bounded seconds.
bool replay_show(ReplayGPU *gpu, uint32_t seconds);
