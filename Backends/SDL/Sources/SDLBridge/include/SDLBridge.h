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
// Replaces the linear atlas sampler with a nearest one (diagnostic arm).
bool replay_use_nearest_filter(ReplayGPU *gpu);
// Synchronous diagnostic renderer. Copies caller bytes before returning.
// Buffers are opaque: Swift supplies the existing MetalUI shader ABI.
bool replay_render(ReplayGPU *gpu, uint32_t width, uint32_t height,
    const void *rects, uint32_t rect_bytes, const void *glyphs, uint32_t glyph_bytes,
    const ReplayRun *runs, uint32_t run_count,
    const uint8_t *atlas, uint32_t atlas_width, uint32_t atlas_height,
    const float *projection, uint8_t *bgra);
// Shows the most recently rendered texture in an SDL window for bounded seconds.
bool replay_show(ReplayGPU *gpu, uint32_t seconds);

// ---- The MetalUI window renderer (ruling RS-D) ----------------------------
// One SDL GPU device drawing MetalUI frames into a claimed SDL window's
// swapchain, or — with no window — into an offscreen target a caller can read
// back. Unlike replay_render it keeps its atlas texture between frames and
// does not wait for the GPU after submitting a window frame.
typedef struct MUIRenderer MUIRenderer;
MUIRenderer *mui_renderer_create(const char *shader_dir, const char *driver);
void mui_renderer_destroy(MUIRenderer *r);
const char *mui_renderer_driver(MUIRenderer *r);
// `window` is an SDL_Window *. Afterwards frames go to its swapchain.
bool mui_renderer_claim_window(MUIRenderer *r, void *window);
// The offscreen target's size, used while no window is claimed.
bool mui_renderer_set_offscreen_size(MUIRenderer *r, uint32_t width, uint32_t height);
// 1: a target was acquired, its pixel size written; 0: none this frame (retry);
// -1: an error (replay_error()).
int mui_renderer_begin(MUIRenderer *r, uint32_t *width, uint32_t *height);
// Draws into the target `begin` acquired and submits. The atlas is uploaded
// whole when `atlas_dirty` is set or its size changed.
bool mui_renderer_finish(MUIRenderer *r,
    const void *rects, uint32_t rect_bytes, const void *glyphs, uint32_t glyph_bytes,
    const ReplayRun *runs, uint32_t run_count,
    const uint8_t *atlas, uint32_t atlas_width, uint32_t atlas_height, bool atlas_dirty,
    const float *projection);
// The last offscreen frame as BGRA rows (waits for it).
bool mui_renderer_read_offscreen(MUIRenderer *r, uint8_t *bgra);
// The window's device pixels per point (SDL_GetWindowPixelDensity).
float mui_window_pixel_density(void *window);
