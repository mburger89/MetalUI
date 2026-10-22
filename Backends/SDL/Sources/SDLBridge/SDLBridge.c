#if !defined(_GNU_SOURCE) && defined(__linux__)
#define _GNU_SOURCE 1
#endif
#include "SDLBridge.h"
/* Compiled only under the root package's `SDL` trait, which defines
   METALUI_SDL (ruling PX-H item 4); without it this file is the one
   declaration after the #endif, not an empty translation unit. */
#ifdef METALUI_SDL
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct ReplayGPU {
    SDL_GPUDevice *device;
    SDL_GPUGraphicsPipeline *rect, *glyph, *image;
    /* The backdrop blur's pipelines (ruling BB-D), made on the first frame that
       holds a backdrop (ensure_backdrop_pipelines): a renderer that never draws
       a material never loads their five shader stages. */
    SDL_GPUGraphicsPipeline *backdrop, *downsample, *gaussian;
    SDL_GPUSampler *sampler;
    SDL_GPUSampler *point;          /* nearest, clamped: the blur passes' texel fetch */
    SDL_GPUTexture *target;
    uint32_t width, height;
    char *shader_dir;               /* owned; the portable stages' directory */
    SDL_GPUShaderFormat format;
    bool portable;
};

const char *replay_error(void) { return SDL_GetError(); }
const char *replay_driver(ReplayGPU *g) { return SDL_GetGPUDeviceDriver(g->device); }

enum { KIND_RECT = 0, KIND_GLYPH = 1, KIND_IMAGE = 2, KIND_BACKDROP = 3 };
static const char *const kind_names[] = {"rect", "glyph", "image"};

/* An image record is 64 bytes, four float4 lanes (MUIImage): bounds,
   contentMask, maskCornerRadii, then opacity, texture, filter, order. */
enum { IMAGE_STRIDE = 64, IMAGE_TEXTURE_OFFSET = 52 };
/* A transform record is 64 bytes, four float4 lanes (MUITransform, ruling
   GX-F); an empty table binds one zero record, which index 0 never reads. */
enum { TRANSFORM_STRIDE = 64 };
static const uint8_t empty_transform[TRANSFORM_STRIDE] = {0};
/* Where each record keeps its transform index: rect `shape` (offset 116) and
   image `filter` (offset 56) bits 8…31, glyph `transform` (offset 84). */
enum { RECT_STRIDE = 120, GLYPH_STRIDE = 88, RECT_SHAPE_OFFSET = 116, GLYPH_TRANSFORM_OFFSET = 84,
       IMAGE_FILTER_OFFSET = 56 };
/* A backdrop record is 96 bytes, six float4 lanes (MUIBackdrop, ruling BB-B):
   bounds, contentMask, maskCornerRadii, cornerRadii, tint, then order, shape,
   sigma, opacity. Its `shape` keeps the transform index in bits 8…31. Uploaded
   as recorded (already whole lanes). */
enum { BACKDROP_STRIDE = 96, BACKDROP_SHAPE_OFFSET = 84, BACKDROP_SIGMA_OFFSET = 88, BACKDROP_MAX_LEVEL = 6 };

/* Every record a run draws names a transform the table holds (the shaders
   read record i − 1 for index i, ruling GX-F), checked once, as images_valid
   checks textures. A scene, or a recorded fixture, can never name one past
   the table; anything else is refused rather than read out of bounds. */
static bool transforms_valid(const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
                             const void *images, uint32_t ib, const void *backdrops, uint32_t bb, uint32_t tb,
                             const ReplayRun *runs, uint32_t count) {
    uint32_t table = tb / TRANSFORM_STRIDE;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *base; uint32_t stride, offset, shift, bytes;
        if (runs[i].kind == KIND_RECT) { base = rects; stride = RECT_STRIDE; offset = RECT_SHAPE_OFFSET; shift = 8; bytes = rb; }
        else if (runs[i].kind == KIND_GLYPH) { base = glyphs; stride = GLYPH_STRIDE; offset = GLYPH_TRANSFORM_OFFSET; shift = 0; bytes = gb; }
        else if (runs[i].kind == KIND_BACKDROP) { base = backdrops; stride = BACKDROP_STRIDE; offset = BACKDROP_SHAPE_OFFSET; shift = 8; bytes = bb; }
        else if (runs[i].kind == KIND_IMAGE) { base = images; stride = IMAGE_STRIDE; offset = IMAGE_FILTER_OFFSET; shift = 8; bytes = ib; }
        else return SDL_SetError("unknown run kind");
        if ((uint64_t)runs[i].start + runs[i].count > bytes / stride) return SDL_SetError("run past its records");
        for (uint32_t j = runs[i].start; j < runs[i].start + runs[i].count; j++) {
            uint32_t word;
            memcpy(&word, base + (size_t)j * stride + offset, sizeof(word));
            if ((word >> shift) > table) return SDL_SetError("a record names a missing transform");
        }
    }
    return true;
}
static uint32_t image_texture(const void *images, uint32_t index) {
    uint32_t texture;
    memcpy(&texture, (const uint8_t *)images + index * IMAGE_STRIDE + IMAGE_TEXTURE_OFFSET, sizeof(texture));
    return texture;
}

/* One compiled stage, `<name>.<vertex|fragment>.<msl|spv|dxil>` in the shader
   directory (portable), or `entry` in the MSL `source` (the adapted MetalUI
   source the Replay executable's native arm uses). */
static SDL_GPUShader *stage(ReplayGPU *g, const char *source, const char *entry, const char *name,
                            bool fragment, uint32_t samplers, uint32_t storage, uint32_t uniforms) {
    void *loaded = NULL;
    size_t size = source ? strlen(source) : 0;
    if (g->portable) {
        const char *extension = g->format == SDL_GPU_SHADERFORMAT_MSL ? "msl" :
            g->format == SDL_GPU_SHADERFORMAT_SPIRV ? "spv" : "dxil";
        char path[4096];
        int length = snprintf(path, sizeof(path), "%s/%s.%s.%s", g->shader_dir,
            name, fragment ? "fragment" : "vertex", extension);
        if (length < 0 || (size_t)length >= sizeof(path)) {
            SDL_SetError("shader path too long"); return NULL;
        }
        loaded = SDL_LoadFile(path, &size);
        if (!loaded) return NULL;
        source = loaded;
        entry = g->format == SDL_GPU_SHADERFORMAT_MSL ? "main0" : "main";
    }
    SDL_GPUShaderCreateInfo info = {
        .code = (const Uint8 *)source, .code_size = size,
        .entrypoint = entry, .format = g->format,
        .stage = fragment ? SDL_GPU_SHADERSTAGE_FRAGMENT : SDL_GPU_SHADERSTAGE_VERTEX,
        .num_storage_buffers = storage, .num_uniform_buffers = uniforms, .num_samplers = samplers
    };
    SDL_GPUShader *result = SDL_CreateGPUShader(g->device, &info);
    SDL_free(loaded);
    return result;
}

static SDL_GPUShader *shader(ReplayGPU *g, const char *source, const char *entry,
                            bool fragment, int kind) {
    /* Records, then the transform table (ruling GX-F); the vertex stage also
       reads the unit quad first. */
    return stage(g, source, entry, kind_names[kind], fragment, fragment && kind != KIND_RECT ? 1 : 0,
                 fragment ? 2 : 3, fragment ? 0 : 2);
}

/* A graphics pipeline over two stages into B8G8R8A8: premultiplied source-over
   when `blend` (the primitives), a plain write when not (the blur passes). */
static SDL_GPUGraphicsPipeline *make_pipeline(ReplayGPU *g, SDL_GPUShader *v, SDL_GPUShader *f, bool blend) {
    if (!v || !f) {
        if (v) SDL_ReleaseGPUShader(g->device, v);
        if (f) SDL_ReleaseGPUShader(g->device, f);
        return NULL;
    }
    SDL_GPUColorTargetDescription target = {
        .format = SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
        .blend_state = {
            .src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
            .enable_blend = blend
        }
    };
    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader = v, .fragment_shader = f,
        .primitive_type = SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
        .target_info = { .color_target_descriptions = &target, .num_color_targets = 1 }
    };
    SDL_GPUGraphicsPipeline *result = SDL_CreateGPUGraphicsPipeline(g->device, &info);
    SDL_ReleaseGPUShader(g->device, v);
    SDL_ReleaseGPUShader(g->device, f);
    return result;
}

static SDL_GPUGraphicsPipeline *pipeline(ReplayGPU *g, const char *source, int kind) {
    char vertex[32], fragment[32];
    SDL_snprintf(vertex, sizeof(vertex), "%s_vertex", kind_names[kind]);
    SDL_snprintf(fragment, sizeof(fragment), "%s_fragment", kind_names[kind]);
    SDL_GPUShader *v = shader(g, source, vertex, false, kind);
    if (!v) return NULL;
    SDL_GPUShader *f = shader(g, source, fragment, true, kind);
    if (!f) { SDL_ReleaseGPUShader(g->device, v); return NULL; }
    return make_pipeline(g, v, f, true);
}

/* The backdrop blur's three pipelines (ruling BB-D, replay.hlsl's BACKDROP_STAGE
   and PASS_STAGE): the material's quad (3 vertex storage buffers and 2 uniform
   buffers like a rect; fragment: the blurred texture, 2 storage buffers and the
   draw constants) and the downsample and Gaussian passes over the shared
   full-target triangle (one sampler and the pass constants). Portable shaders
   only; made once, on first use. */
static bool ensure_backdrop_pipelines(ReplayGPU *g) {
    if (g->backdrop && g->downsample && g->gaussian) return true;
    if (!g->portable || !g->shader_dir)
        return SDL_SetError("a backdrop needs the portable shaders (replay_create_portable)");
    SDL_GPUShader *quad_v = stage(g, NULL, NULL, "backdrop", false, 0, 3, 2);
    SDL_GPUShader *quad_f = quad_v ? stage(g, NULL, NULL, "backdrop", true, 1, 2, 1) : NULL;
    SDL_GPUGraphicsPipeline *backdrop = make_pipeline(g, quad_v, quad_f, true);
    if (!backdrop) return false;
    SDL_GPUGraphicsPipeline *passes[2] = {NULL, NULL};
    const char *names[2] = {"downsample", "gaussian"};
    for (int i = 0; i < 2; i++) {
        SDL_GPUShader *v = stage(g, NULL, NULL, "pass", false, 0, 0, 0);
        SDL_GPUShader *f = v ? stage(g, NULL, NULL, names[i], true, 1, 0, 1) : NULL;
        passes[i] = make_pipeline(g, v, f, false);
        if (!passes[i]) {
            char error[1024]; SDL_strlcpy(error, SDL_GetError(), sizeof(error));
            SDL_ReleaseGPUGraphicsPipeline(g->device, backdrop);
            if (passes[0]) SDL_ReleaseGPUGraphicsPipeline(g->device, passes[0]);
            SDL_SetError("%s", error);
            return false;
        }
    }
    g->backdrop = backdrop; g->downsample = passes[0]; g->gaussian = passes[1];
    return true;
}

/* Each device holds one reference on SDL's video subsystem, released by
   replay_destroy. **Not SDL_Init/SDL_Quit**: SDL_Quit tears down every
   subsystem whoever else is using it, and on Linux that unloads the Vulkan
   loader while another device's Mesa llvmpipe threads are still running —
   a crash two devices into a test run (ruling RS-D, measured in CI). */
static ReplayGPU *create(const char *source, const char *directory, const char *driver) {
    if (!SDL_InitSubSystem(SDL_INIT_VIDEO)) return NULL;
    ReplayGPU *g = calloc(1, sizeof(*g));
    if (!g) { SDL_SetError("allocation failed"); SDL_QuitSubSystem(SDL_INIT_VIDEO); return NULL; }
    g->portable = directory != NULL;
    if (directory) {
        g->shader_dir = SDL_strdup(directory); // kept: the backdrop pipelines load their stages on first use
        if (!g->shader_dir) { SDL_SetError("allocation failed"); goto fail; }
    }
    if (!strcmp(driver, "metal")) g->format = SDL_GPU_SHADERFORMAT_MSL;
    else if (!strcmp(driver, "vulkan")) g->format = SDL_GPU_SHADERFORMAT_SPIRV;
    else if (!strcmp(driver, "direct3d12")) g->format = SDL_GPU_SHADERFORMAT_DXIL;
    else { SDL_SetError("unsupported driver: %s", driver); goto fail; }
    g->device = SDL_CreateGPUDevice(g->format, true, driver);
    if (!g->device) goto fail;
    g->rect = pipeline(g, source, KIND_RECT);
    if (!g->rect) goto fail;
    g->glyph = pipeline(g, source, KIND_GLYPH);
    if (!g->glyph) goto fail;
    g->image = pipeline(g, source, KIND_IMAGE);
    if (!g->image) goto fail;
    SDL_GPUSamplerCreateInfo sampler = {
        .min_filter = SDL_GPU_FILTER_LINEAR, .mag_filter = SDL_GPU_FILTER_LINEAR,
        .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
    };
    g->sampler = SDL_CreateGPUSampler(g->device, &sampler);
    if (!g->sampler) goto fail;
    SDL_GPUSamplerCreateInfo point = {
        .min_filter = SDL_GPU_FILTER_NEAREST, .mag_filter = SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
    };
    g->point = SDL_CreateGPUSampler(g->device, &point);
    if (!g->point) goto fail;
    return g;
fail: {
    char error[1024]; SDL_strlcpy(error, SDL_GetError(), sizeof(error));
    replay_destroy(g); SDL_SetError("%s", error); return NULL;
} }

ReplayGPU *replay_create(const char *source) { return create(source, NULL, "metal"); }
ReplayGPU *replay_create_portable(const char *directory, const char *driver) {
    if (!directory || !driver) { SDL_SetError("shader directory and driver are required"); return NULL; }
    return create(NULL, directory, driver);
}

bool replay_use_nearest_filter(ReplayGPU *g) {
    // Diagnostic arm only: the production Metal renderer filters linearly.
    SDL_GPUSamplerCreateInfo info = {
        .min_filter = SDL_GPU_FILTER_NEAREST, .mag_filter = SDL_GPU_FILTER_NEAREST,
        .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
    };
    SDL_GPUSampler *sampler = SDL_CreateGPUSampler(g->device, &info);
    if (!sampler) return false;
    SDL_ReleaseGPUSampler(g->device, g->sampler);
    g->sampler = sampler;
    return true;
}

void replay_destroy(ReplayGPU *g) {
    if (!g) return;
    if (g->device) {
        SDL_WaitForGPUIdle(g->device);
        if (g->target) SDL_ReleaseGPUTexture(g->device, g->target);
        if (g->sampler) SDL_ReleaseGPUSampler(g->device, g->sampler);
        if (g->point) SDL_ReleaseGPUSampler(g->device, g->point);
        if (g->backdrop) SDL_ReleaseGPUGraphicsPipeline(g->device, g->backdrop);
        if (g->downsample) SDL_ReleaseGPUGraphicsPipeline(g->device, g->downsample);
        if (g->gaussian) SDL_ReleaseGPUGraphicsPipeline(g->device, g->gaussian);
        if (g->rect) SDL_ReleaseGPUGraphicsPipeline(g->device, g->rect);
        if (g->glyph) SDL_ReleaseGPUGraphicsPipeline(g->device, g->glyph);
        if (g->image) SDL_ReleaseGPUGraphicsPipeline(g->device, g->image);
        SDL_DestroyGPUDevice(g->device);
    }
    SDL_free(g->shader_dir);
    free(g); SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

static SDL_GPUTexture *texture_of(ReplayGPU *g, uint32_t w, uint32_t h, bool target, SDL_GPUTextureFormat sampled) {
    SDL_GPUTextureCreateInfo info = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = target ? SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM : sampled,
        .usage = target ? SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER : SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = w, .height = h, .layer_count_or_depth = 1, .num_levels = 1
    };
    return SDL_CreateGPUTexture(g->device, &info);
}
/* A target, or the R8 glyph atlas. */
static SDL_GPUTexture *texture(ReplayGPU *g, uint32_t w, uint32_t h, bool target) {
    return texture_of(g, w, h, target, SDL_GPU_TEXTUREFORMAT_R8_UNORM);
}

static SDL_GPUTransferBuffer *transfer(ReplayGPU *g, uint32_t size, bool download, const void *bytes) {
    SDL_GPUTransferBufferCreateInfo info = {
        .usage = download ? SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD : SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = size
    };
    SDL_GPUTransferBuffer *result = SDL_CreateGPUTransferBuffer(g->device, &info);
    if (result && bytes) {
        void *mapped = SDL_MapGPUTransferBuffer(g->device, result, false);
        if (!mapped) { SDL_ReleaseGPUTransferBuffer(g->device, result); return NULL; }
        memcpy(mapped, bytes, size);
        SDL_UnmapGPUTransferBuffer(g->device, result);
    }
    return result;
}

/* Records the bridge trusts, checked once: each image run's first record names
   a texture that exists (ReplayFixture validates recorded ones too). */
static bool images_valid(const void *images, uint32_t ib, uint32_t texture_count,
                         const ReplayRun *runs, uint32_t count) {
    if (ib % IMAGE_STRIDE) return SDL_SetError("unexpected MetalUI image ABI");
    for (uint32_t i = 0; i < count; i++) {
        if (runs[i].kind != KIND_IMAGE) continue;
        if ((uint64_t)runs[i].start + runs[i].count > ib / IMAGE_STRIDE) return SDL_SetError("image run past its records");
        if (image_texture(images, runs[i].start) >= texture_count) return SDL_SetError("image names a missing texture");
    }
    return true;
}

/* ---- The backdrop blur (rulings BB-A, BB-C, BB-D, BB-E, BB-R, BB-S) ------ */

uint32_t mui_backdrop_levels(float sigma) {
    uint32_t level = 0;
    float s = sigma;
    while (s > 4.0f && level < BACKDROP_MAX_LEVEL) { s *= 0.5f; level += 1; }
    return level;
}

/* One blur texture of the pool, or its size (BackdropFrameState in
   Sources/MetalUIRender/BackdropBlurPipeline.swift, restated). The pool is a
   free list by size: acquire hands out a free texture of the size or makes
   one; release marks it free; a size no frame acquired is dropped at the
   frame's end, and a frame with no backdrop drops everything. */
typedef struct { SDL_GPUTexture *texture; uint32_t width, height; bool free; } PoolSlot;
typedef struct { uint32_t width, height; } PoolSize;
typedef struct {
    SDL_GPUTexture *frame;
    uint32_t frame_width, frame_height;
    PoolSlot *slots; uint32_t slot_count, slot_capacity;
    PoolSize *used; uint32_t used_count, used_capacity;
    /* The last frame's work (ruling BB-S). */
    uint32_t splits, blurs, passes, copies, made;
    bool pool_fails, route_every_frame;
} BackdropState;

static void backdrop_begin_frame(BackdropState *b) {
    b->splits = b->blurs = b->passes = b->copies = b->made = 0;
    b->used_count = 0;
}

static void backdrop_release_all(ReplayGPU *g, BackdropState *b) {
    if (b->frame) SDL_ReleaseGPUTexture(g->device, b->frame);
    b->frame = NULL; b->frame_width = b->frame_height = 0;
    for (uint32_t i = 0; i < b->slot_count; i++) SDL_ReleaseGPUTexture(g->device, b->slots[i].texture);
    b->slot_count = 0;
}

static void backdrop_destroy(ReplayGPU *g, BackdropState *b) {
    backdrop_release_all(g, b);
    free(b->slots); free(b->used);
    memset(b, 0, sizeof(*b));
}

/* The frame target at w × h, replaced on a size change; NULL when it cannot be made. */
static SDL_GPUTexture *backdrop_frame_target(ReplayGPU *g, BackdropState *b, uint32_t w, uint32_t h) {
    if (b->frame && b->frame_width == w && b->frame_height == h) return b->frame;
    if (b->frame) SDL_ReleaseGPUTexture(g->device, b->frame);
    b->frame = NULL;
    SDL_GPUTexture *made = texture(g, w, h, true);
    if (!made) return NULL;
    b->made += 1;
    b->frame = made; b->frame_width = w; b->frame_height = h;
    return made;
}

/* A pool slot of w × h (its index), or -1 when none can be made (or the test hook fails it). */
static int backdrop_acquire(ReplayGPU *g, BackdropState *b, uint32_t w, uint32_t h) {
    if (b->pool_fails) return -1;
    if (b->used_count == b->used_capacity) {
        uint32_t capacity = b->used_capacity ? b->used_capacity * 2 : 16;
        PoolSize *grown = realloc(b->used, capacity * sizeof(*grown));
        if (!grown) return -1;
        b->used = grown; b->used_capacity = capacity;
    }
    b->used[b->used_count++] = (PoolSize){w, h};
    for (uint32_t i = 0; i < b->slot_count; i++)
        if (b->slots[i].free && b->slots[i].width == w && b->slots[i].height == h) { b->slots[i].free = false; return (int)i; }
    if (b->slot_count == b->slot_capacity) {
        uint32_t capacity = b->slot_capacity ? b->slot_capacity * 2 : 16;
        PoolSlot *grown = realloc(b->slots, capacity * sizeof(*grown));
        if (!grown) return -1;
        b->slots = grown; b->slot_capacity = capacity;
    }
    SDL_GPUTexture *made = texture(g, w, h, true);
    if (!made) return -1;
    b->made += 1;
    b->slots[b->slot_count] = (PoolSlot){made, w, h, false};
    return (int)b->slot_count++;
}

static void backdrop_release(BackdropState *b, int slot) {
    if (slot >= 0) b->slots[slot].free = true;
}

/* Drops the free textures of every size this frame did not acquire. */
static void backdrop_end_frame(ReplayGPU *g, BackdropState *b) {
    uint32_t kept = 0;
    for (uint32_t i = 0; i < b->slot_count; i++) {
        bool drop = false;
        if (b->slots[i].free) {
            drop = true;
            for (uint32_t u = 0; u < b->used_count; u++)
                if (b->used[u].width == b->slots[i].width && b->used[u].height == b->slots[i].height) { drop = false; break; }
        }
        if (drop) SDL_ReleaseGPUTexture(g->device, b->slots[i].texture);
        else b->slots[kept++] = b->slots[i];
    }
    b->slot_count = kept;
}

/* shaders' BackdropBlurPass / replay.hlsl's `Pass` cbuffer: the source rectangle
   in the source texture, the Gaussian's sigma at this level and its axis,
   padded to 32 bytes (the Metal struct's stride). */
typedef struct { int32_t src[4]; float sigma; int32_t horizontal; int32_t padding[2]; } PassConstants;

/* One blur pass: a full-target triangle writing `target` (no blend) from the
   texels of `source` inside (ox, oy, sw, sh). */
static bool blur_pass(ReplayGPU *g, BackdropState *b, SDL_GPUCommandBuffer *cmd, SDL_GPUGraphicsPipeline *pipeline,
                      SDL_GPUTexture *source, SDL_GPUTexture *target,
                      int32_t ox, int32_t oy, int32_t sw, int32_t sh, float sigma, bool horizontal) {
    SDL_GPUColorTargetInfo info = { .texture = target, .load_op = SDL_GPU_LOADOP_DONT_CARE, .store_op = SDL_GPU_STOREOP_STORE };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass(cmd, &info, 1, NULL);
    if (!pass) return false;
    PassConstants constants = { .src = {ox, oy, sw, sh}, .sigma = sigma, .horizontal = horizontal ? 1 : 0 };
    SDL_BindGPUGraphicsPipeline(pass, pipeline);
    SDL_GPUTextureSamplerBinding binding = { source, g->point };
    SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
    SDL_PushGPUFragmentUniformData(cmd, 0, &constants, sizeof(constants));
    SDL_DrawGPUPrimitives(pass, 3, 1, 0, 0);
    SDL_EndGPURenderPass(pass);
    b->passes += 1;
    return true;
}

/* A record's blurred region (Renderer.blur(record:…) in Metal): L downsamples
   then a horizontal and a vertical Gaussian at level L. `slot` is the blurred
   texture's pool slot, -1 with a zero `draw` when the region is empty or a
   texture cannot be made (the record then draws its flat tint, ruling BB-I).
   `draw` is (region origin x, y, uv scale x, y): the texel coordinate
   `(p + ½)/2^L − ½` of ruling BB-R, not `uv × size`. A false return is a
   failed pass (an SDL error), not a fallback. */
typedef struct { int slot; float draw[4]; } BlurResult;

static bool blur_record(ReplayGPU *g, BackdropState *b, SDL_GPUCommandBuffer *cmd, SDL_GPUTexture *frame,
                        uint32_t target_width, uint32_t target_height,
                        const ReplayRegion *region, float sigma, BlurResult *out) {
    out->slot = -1;
    memset(out->draw, 0, sizeof(out->draw));
    if (region->width <= 0 || region->height <= 0 || region->x < 0 || region->y < 0
        || (uint64_t)region->x + (uint64_t)region->width > target_width
        || (uint64_t)region->y + (uint64_t)region->height > target_height) return true;
    uint32_t levels = mui_backdrop_levels(sigma);
    int held[BACKDROP_MAX_LEVEL + 1];
    uint32_t held_count = 0;
#define GIVE_BACK() do { for (uint32_t k = 0; k < held_count; k++) backdrop_release(b, held[k]); } while (0)
    SDL_GPUTexture *source = frame;
    int32_t ox = region->x, oy = region->y, w = region->width, h = region->height;
    for (uint32_t level = 0; level < levels; level++) {
        int32_t nw = (w + 1) / 2, nh = (h + 1) / 2;
        int slot = backdrop_acquire(g, b, (uint32_t)nw, (uint32_t)nh);
        if (slot < 0) { GIVE_BACK(); return true; }
        held[held_count++] = slot;
        if (!blur_pass(g, b, cmd, g->downsample, source, b->slots[slot].texture, ox, oy, w, h, 0, false)) return false;
        source = b->slots[slot].texture; ox = oy = 0; w = nw; h = nh;
    }
    int scratch = backdrop_acquire(g, b, (uint32_t)w, (uint32_t)h);
    if (scratch < 0) { GIVE_BACK(); return true; }
    held[held_count++] = scratch;
    int result = backdrop_acquire(g, b, (uint32_t)w, (uint32_t)h);
    if (result < 0) { GIVE_BACK(); return true; }
    float level_sigma = sigma / (float)(1u << levels);
    if (!blur_pass(g, b, cmd, g->gaussian, source, b->slots[scratch].texture, ox, oy, w, h, level_sigma, true)) return false;
    if (!blur_pass(g, b, cmd, g->gaussian, b->slots[scratch].texture, b->slots[result].texture, 0, 0, w, h, level_sigma, false)) return false;
    GIVE_BACK();
#undef GIVE_BACK
    b->blurs += 1;
    float scale = (float)(1u << levels);
    out->slot = result;
    out->draw[0] = (float)region->x; out->draw[1] = (float)region->y;
    out->draw[2] = 1.0f / ((float)w * scale); out->draw[3] = 1.0f / ((float)h * scale);
    return true;
}

/* Where each primitive buffer sits in a frame's list. */
enum { BUF_QUAD = 0, BUF_RECT = 1, BUF_GLYPH = 2, BUF_IMAGE = 3, BUF_TRANSFORM = 4, BUF_BACKDROP = 5, BUF_COUNT = 6 };

/* The scalar-packed CPU ABI (120/88 bytes) widened to the SDL storage buffers'
   16-byte lanes (128/96); an image (64) and a backdrop (96) are whole lanes. The
   rect slots hold the scene's rects, then one FLAT-TINT rect per backdrop record
   — what a record draws when it cannot be blurred (ruling BB-I): the record's
   bounds, clip, radii, order and shape with its tint's alpha times its opacity,
   `c·o·T`, which the rect shader draws exactly. Returns false (with an error)
   when a size is not whole records; `*rect_records` is the scene's own count. */
static void flat_tint_rect(uint8_t *rect, const uint8_t *backdrop) {
    float tint[4], opacity;
    memcpy(rect, backdrop, 48);                       /* bounds, contentMask, maskCornerRadii */
    memcpy(tint, backdrop + 64, sizeof(tint));
    memcpy(&opacity, backdrop + 92, sizeof(opacity));
    tint[3] *= opacity;
    memcpy(rect + 48, tint, sizeof(tint));            /* background; borderColor and widths stay 0 */
    memcpy(rect + 80, backdrop + 48, 16);             /* cornerRadii */
    memcpy(rect + 112, backdrop + 80, 4);             /* order */
    memcpy(rect + 116, backdrop + 84, 4);             /* shape, the transform index with it */
}

static bool pack_records(const void *rects, uint32_t rb, const void *glyphs, uint32_t gb, const void *backdrops, uint32_t kb,
                         void *packed[2], const void *data[BUF_COUNT], uint32_t sizes[BUF_COUNT], uint32_t *rect_records) {
    const uint32_t old_stride[] = {RECT_STRIDE, GLYPH_STRIDE}, new_stride[] = {128, 96};
    if (rb % RECT_STRIDE || gb % GLYPH_STRIDE) return SDL_SetError("unexpected MetalUI primitive ABI");
    if (kb % BACKDROP_STRIDE) return SDL_SetError("unexpected MetalUI backdrop ABI");
    uint32_t records[2] = {rb / RECT_STRIDE, gb / GLYPH_STRIDE};
    uint32_t flats = kb / BACKDROP_STRIDE;
    *rect_records = records[0];
    const void *source[2] = {rects, glyphs};
    for (int i = 0; i < 2; i++) {
        uint32_t count = records[i] + (i == 0 ? flats : 0);
        if (!count) continue;
        packed[i] = calloc(count, new_stride[i]);
        if (!packed[i]) return SDL_SetError("packing allocation failed");
        for (uint32_t j = 0; j < records[i]; j++)
            memcpy((uint8_t *)packed[i] + (size_t)j * new_stride[i], (const uint8_t *)source[i] + (size_t)j * old_stride[i], old_stride[i]);
        if (i == 0)
            for (uint32_t j = 0; j < flats; j++)
                flat_tint_rect((uint8_t *)packed[0] + (size_t)(records[0] + j) * new_stride[0],
                               (const uint8_t *)backdrops + (size_t)j * BACKDROP_STRIDE);
        data[BUF_RECT + i] = packed[i]; sizes[BUF_RECT + i] = count * new_stride[i];
    }
    return true;
}

/* A frame's inputs, shared by the replay and window renderers' draw loops. */
typedef struct {
    ReplayGPU *g;
    SDL_GPUCommandBuffer *cmd;
    SDL_GPUBuffer *buffers[BUF_COUNT];
    SDL_GPUTexture *atlas;
    SDL_GPUTexture *const *image_textures;   /* by an image record's `texture` */
    const void *images;
    const void *backdrops;                   /* the CPU records (sigma) */
    const ReplayRegion *regions;
    uint32_t rect_records;                   /* the scene's; the flat rects follow */
    const ReplayRun *runs; uint32_t run_count;
    uint32_t width, height;
    const float *projection;
    struct { float width, height; uint32_t first_instance, padding; } viewport;
} FrameDraw;

/* One instanced draw of `count` records of a rect, glyph or image run (the
   binding every pipeline shares); a backdrop run that cannot be blurred is
   drawn as the rects its flat tint became. */
static void draw_primitives(FrameDraw *f, SDL_GPURenderPass *pass, uint32_t kind, uint32_t start, uint32_t count) {
    ReplayGPU *g = f->g;
    SDL_GPUBuffer *primitives = f->buffers[kind == KIND_GLYPH ? BUF_GLYPH : kind == KIND_IMAGE ? BUF_IMAGE : BUF_RECT];
    if (!primitives) return;
    SDL_GPUBuffer *vertex_buffers[] = {f->buffers[BUF_QUAD], primitives, f->buffers[BUF_TRANSFORM]};
    SDL_GPUBuffer *fragment_buffers[] = {primitives, f->buffers[BUF_TRANSFORM]};
    SDL_BindGPUGraphicsPipeline(pass, kind == KIND_GLYPH ? g->glyph : kind == KIND_IMAGE ? g->image : g->rect);
    SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 3);
    SDL_BindGPUFragmentStorageBuffers(pass, 0, fragment_buffers, 2);
    if (kind == KIND_GLYPH) {
        SDL_GPUTextureSamplerBinding binding = {f->atlas, g->sampler};
        SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
    } else if (kind == KIND_IMAGE) {
        SDL_GPUTextureSamplerBinding binding = {f->image_textures[image_texture(f->images, start)], g->sampler};
        SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
    }
    /* SDL explicitly warns built-in instance IDs differ across APIs when
       first_instance is nonzero. Supply the base through a uniform instead. */
    f->viewport.first_instance = start;
    SDL_PushGPUVertexUniformData(f->cmd, 0, &f->viewport, sizeof(f->viewport));
    SDL_DrawGPUPrimitives(pass, 4, count, 0, 0);
}

static void draw_run(FrameDraw *f, SDL_GPURenderPass *pass, const ReplayRun *run) {
    if (run->kind == KIND_BACKDROP) draw_primitives(f, pass, KIND_RECT, f->rect_records + run->start, run->count);
    else draw_primitives(f, pass, run->kind, run->start, run->count);
}

static SDL_GPURenderPass *begin_segment(FrameDraw *f, SDL_GPUTexture *texture, SDL_GPULoadOp load) {
    SDL_GPUColorTargetInfo info = { .texture = texture, .load_op = load, .store_op = SDL_GPU_STOREOP_STORE };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass(f->cmd, &info, 1, NULL);
    /* The projection is a vertex uniform of the command buffer; pushed again at
       each pass so no backend need carry it across the blur passes between. */
    if (pass) SDL_PushGPUVertexUniformData(f->cmd, 1, f->projection, sizeof(float) * 16);
    return pass;
}

static bool projection_is_identity(const float *m) {
    static const float identity[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
    return memcmp(m, identity, sizeof(identity)) == 0;
}

/* Draws the frame into `target` (ruling BB-C). **A frame with no backdrop run
   takes the single pass into the target, byte for byte**; one with backdrops
   renders into the frame target in segments — segment 0 clears transparent and
   draws up to the first backdrop run; at each backdrop run the segment ends,
   every record of the run is blurred from the frame as it stands, and a new
   segment (load) draws the run's quads and what follows — then blits the frame
   target to `target`, 1:1. Where the frame target or the pipelines cannot be
   made, or the projection is not the identity (the blit is texel for texel),
   each record draws its flat tint (ruling BB-I) in the single pass. `strict`
   (the diagnostic replay) reports missing pipelines instead. */
static bool encode_frame(FrameDraw *f, BackdropState *b, SDL_GPUTexture *target, bool strict) {
    ReplayGPU *g = f->g;
    bool has_backdrops = false;
    for (uint32_t i = 0; i < f->run_count; i++) if (f->runs[i].kind == KIND_BACKDROP) has_backdrops = true;
    backdrop_begin_frame(b);
    bool wants = has_backdrops || (b->route_every_frame && f->run_count > 0);
    SDL_GPUTexture *frame = NULL;
    if (wants && projection_is_identity(f->projection)) {
        bool ready = !has_backdrops || ensure_backdrop_pipelines(g);
        if (!ready && strict) return false;
        if (ready) frame = backdrop_frame_target(g, b, f->width, f->height);
    }
    if (!frame) {
        if (!wants) backdrop_release_all(g, b);
        SDL_GPURenderPass *pass = begin_segment(f, target, SDL_GPU_LOADOP_CLEAR);
        if (!pass) return false;
        for (uint32_t i = 0; i < f->run_count; i++) draw_run(f, pass, &f->runs[i]);
        SDL_EndGPURenderPass(pass);
        return true;
    }
    bool ok = false;
    BlurResult *results = NULL;
    SDL_GPURenderPass *pass = begin_segment(f, frame, SDL_GPU_LOADOP_CLEAR);
    if (!pass) goto done;
    for (uint32_t i = 0; i < f->run_count; i++) {
        const ReplayRun *run = &f->runs[i];
        if (run->kind != KIND_BACKDROP) { draw_run(f, pass, run); continue; }
        SDL_EndGPURenderPass(pass);
        pass = NULL;
        b->splits += 1;
        /* Every record of the run reads the frame as it stands at the split
           (a run holds no two overlapping records, ruling BB-E). */
        free(results);
        results = calloc(run->count, sizeof(*results));
        if (!results) { SDL_SetError("allocation failed"); goto done; }
        for (uint32_t k = 0; k < run->count; k++) {
            float sigma;
            memcpy(&sigma, (const uint8_t *)f->backdrops + (size_t)(run->start + k) * BACKDROP_STRIDE + BACKDROP_SIGMA_OFFSET, sizeof(sigma));
            if (!blur_record(g, b, f->cmd, frame, f->width, f->height, &f->regions[run->start + k], sigma, &results[k])) goto done;
        }
        pass = begin_segment(f, frame, SDL_GPU_LOADOP_LOAD);
        if (!pass) goto done;
        for (uint32_t k = 0; k < run->count; k++) {
            uint32_t record = run->start + k;
            if (results[k].slot < 0) { draw_primitives(f, pass, KIND_RECT, f->rect_records + record, 1); continue; }
            SDL_GPUBuffer *vertex_buffers[] = {f->buffers[BUF_QUAD], f->buffers[BUF_BACKDROP], f->buffers[BUF_TRANSFORM]};
            SDL_GPUBuffer *fragment_buffers[] = {f->buffers[BUF_BACKDROP], f->buffers[BUF_TRANSFORM]};
            SDL_BindGPUGraphicsPipeline(pass, g->backdrop);
            SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 3);
            SDL_BindGPUFragmentStorageBuffers(pass, 0, fragment_buffers, 2);
            SDL_GPUTextureSamplerBinding binding = {b->slots[results[k].slot].texture, g->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
            f->viewport.first_instance = record;
            SDL_PushGPUVertexUniformData(f->cmd, 0, &f->viewport, sizeof(f->viewport));
            SDL_PushGPUFragmentUniformData(f->cmd, 0, results[k].draw, sizeof(results[k].draw));
            SDL_DrawGPUPrimitives(pass, 4, 1, 0, 0);
            backdrop_release(b, results[k].slot);
        }
    }
    SDL_EndGPURenderPass(pass);
    pass = NULL;
    /* The copy: the frame target onto the target, texel for texel. */
    SDL_GPUBlitInfo blit = {
        .source = { .texture = frame, .w = f->width, .h = f->height },
        .destination = { .texture = target, .w = f->width, .h = f->height },
        .load_op = SDL_GPU_LOADOP_DONT_CARE, .filter = SDL_GPU_FILTER_NEAREST
    };
    SDL_BlitGPUTexture(f->cmd, &blit);
    b->copies = 1;
    backdrop_end_frame(g, b);
    ok = true;
done:
    if (pass) SDL_EndGPURenderPass(pass);
    free(results);
    return ok;
}

bool replay_render(ReplayGPU *g, uint32_t w, uint32_t h,
    const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
    const void *images, uint32_t ib, const void *transforms, uint32_t tb,
    const void *backdrops, uint32_t kb, const ReplayRegion *regions, uint32_t region_count,
    const ReplayTexture *textures, uint32_t texture_count,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah,
    const float *projection, uint8_t *out) {
    // Diagnostic harness only: bounded fixtures, one completed frame at a time.
    if (!w || !h || w > 4096 || h > 4096 || !aw || !ah || aw > 4096 || ah > 4096)
        return SDL_SetError("invalid fixture dimensions");
    if (!images_valid(images, ib, texture_count, runs, count)) return false;
    if (tb % TRANSFORM_STRIDE) return SDL_SetError("unexpected MetalUI transform ABI");
    if (kb % BACKDROP_STRIDE || region_count != kb / BACKDROP_STRIDE) return SDL_SetError("unexpected MetalUI backdrop ABI");
    if (!transforms_valid(rects, rb, glyphs, gb, images, ib, backdrops, kb, tb, runs, count)) return false;
    for (uint32_t t = 0; t < texture_count; t++)
        if (!textures[t].width || !textures[t].height || textures[t].width > 4096 || textures[t].height > 4096)
            return SDL_SetError("invalid image texture dimensions");
    SDL_GPUBuffer *buffers[BUF_COUNT] = {0};
    SDL_GPUTransferBuffer *uploads[BUF_COUNT + 1] = {0}, *download = NULL;
    SDL_GPUTexture *atlas_texture = NULL;
    SDL_GPUTexture **image_textures = NULL;
    SDL_GPUTransferBuffer **image_uploads = NULL;
    SDL_GPUCommandBuffer *cmd = NULL;
    SDL_GPUFence *fence = NULL;
    BackdropState backdrop = {0};
    bool ok = false;
    void *packed[2] = {0};
    if (texture_count) {
        image_textures = SDL_calloc(texture_count, sizeof(*image_textures));
        image_uploads = SDL_calloc(texture_count, sizeof(*image_uploads));
        if (!image_textures || !image_uploads) { SDL_SetError("allocation failed"); goto cleanup; }
    }
    if (g->target) { SDL_ReleaseGPUTexture(g->device, g->target); g->target = NULL; }
    g->target = texture(g, w, h, true);
    g->width = w; g->height = h;
    atlas_texture = texture(g, aw, ah, false);
    if (!g->target || !atlas_texture) goto cleanup;
    for (uint32_t t = 0; t < texture_count; t++) {
        image_textures[t] = texture_of(g, textures[t].width, textures[t].height, false, SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM);
        image_uploads[t] = transfer(g, textures[t].width * textures[t].height * 4, false, textures[t].rgba);
        if (!image_textures[t] || !image_uploads[t]) goto cleanup;
    }
    const float quad[] = {0,0, 1,0, 0,1, 1,1};
    const float aligned_quad[] = {0,0,0,0, 1,0,0,0, 0,1,0,0, 1,1,0,0};
    const void *data[BUF_COUNT] = {quad, rects, glyphs, images, tb ? transforms : empty_transform, backdrops};
    uint32_t sizes[BUF_COUNT] = {sizeof(quad), rb, gb, ib, tb ? tb : TRANSFORM_STRIDE, kb};
    uint32_t rect_records = 0;
    if (g->portable) {
        // The existing CPU ABI is scalar-packed (120/88 bytes). SDL storage
        // uses 16-byte lanes, so round each record up, never reinterpret it.
        // Images (64 bytes) and backdrops (96) are already whole lanes.
        data[BUF_QUAD] = aligned_quad; sizes[BUF_QUAD] = sizeof(aligned_quad);
        if (!pack_records(rects, rb, glyphs, gb, backdrops, kb, packed, data, sizes, &rect_records)) goto cleanup;
    }
    for (int i = 0; i < BUF_COUNT; i++) {
        if (!sizes[i]) continue;
        SDL_GPUBufferCreateInfo info = {
            .usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, .size = sizes[i]
        };
        buffers[i] = SDL_CreateGPUBuffer(g->device, &info);
        uploads[i] = transfer(g, sizes[i], false, data[i]);
        if (!buffers[i] || !uploads[i]) goto cleanup;
    }
    uploads[BUF_COUNT] = transfer(g, aw * ah, false, atlas);
    // 256-byte pitch also works for a future D3D readback path.
    uint32_t pitch = (w * 4 + 255) & ~255u;
    download = transfer(g, pitch * h, true, NULL);
    if (!uploads[BUF_COUNT] || !download) goto cleanup;
    cmd = SDL_AcquireGPUCommandBuffer(g->device);
    if (!cmd) goto cleanup;
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < BUF_COUNT; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[BUF_COUNT] };
    SDL_GPUTextureRegion atlas_dst = { .texture = atlas_texture, .w = aw, .h = ah, .d = 1 };
    SDL_UploadToGPUTexture(copy, &atlas_src, &atlas_dst, false);
    for (uint32_t t = 0; t < texture_count; t++) {
        SDL_GPUTextureTransferInfo image_src = { .transfer_buffer = image_uploads[t] };
        SDL_GPUTextureRegion image_dst = { .texture = image_textures[t], .w = textures[t].width, .h = textures[t].height, .d = 1 };
        SDL_UploadToGPUTexture(copy, &image_src, &image_dst, false);
    }
    SDL_EndGPUCopyPass(copy);
    FrameDraw frame = {
        .g = g, .cmd = cmd, .atlas = atlas_texture, .image_textures = image_textures, .images = images,
        .backdrops = backdrops, .regions = regions, .rect_records = rect_records,
        .runs = runs, .run_count = count, .width = w, .height = h, .projection = projection,
        .viewport = {(float)w, (float)h, 0, 0}
    };
    memcpy(frame.buffers, buffers, sizeof(buffers));
    if (!g->portable && kb) { SDL_SetError("a backdrop needs the portable shaders (replay_create_portable)"); goto cleanup; }
    if (!encode_frame(&frame, &backdrop, g->target, true)) goto cleanup;
    copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    SDL_GPUTextureRegion src = { .texture = g->target, .w = w, .h = h, .d = 1 };
    SDL_GPUTextureTransferInfo dst = { .transfer_buffer = download, .pixels_per_row = pitch / 4, .rows_per_layer = h };
    SDL_DownloadFromGPUTexture(copy, &src, &dst);
    SDL_EndGPUCopyPass(copy);
    fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    cmd = NULL;
    if (!fence || !SDL_WaitForGPUFences(g->device, true, &fence, 1)) goto cleanup;
    const uint8_t *mapped = SDL_MapGPUTransferBuffer(g->device, download, false);
    if (!mapped) goto cleanup;
    for (uint32_t y = 0; y < h; y++) memcpy(out + y * w * 4, mapped + y * pitch, w * 4);
    SDL_UnmapGPUTransferBuffer(g->device, download);
    ok = true;
cleanup:
    if (cmd) SDL_CancelGPUCommandBuffer(cmd);
    if (fence) SDL_ReleaseGPUFence(g->device, fence);
    for (int i = 0; i < BUF_COUNT; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(g->device, buffers[i]);
    for (int i = 0; i < BUF_COUNT + 1; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(g->device, uploads[i]);
    for (uint32_t t = 0; t < texture_count && image_textures; t++) {
        if (image_textures[t]) SDL_ReleaseGPUTexture(g->device, image_textures[t]);
        if (image_uploads && image_uploads[t]) SDL_ReleaseGPUTransferBuffer(g->device, image_uploads[t]);
    }
    SDL_free(image_textures); SDL_free(image_uploads);
    if (download) SDL_ReleaseGPUTransferBuffer(g->device, download);
    if (atlas_texture) SDL_ReleaseGPUTexture(g->device, atlas_texture);
    backdrop_destroy(g, &backdrop);
    free(packed[0]); free(packed[1]);
    return ok;
}

bool replay_show(ReplayGPU *g, uint32_t seconds) {
    SDL_Window *window = SDL_CreateWindow("MetalUI — SDL GPU scene replay", g->width, g->height, SDL_WINDOW_RESIZABLE);
    if (!window) return false;
    if (!SDL_ClaimWindowForGPUDevice(g->device, window)) { SDL_DestroyWindow(window); return false; }
    bool ok = true, quit = false;
    Uint64 end = SDL_GetTicks() + seconds * 1000;
    while (!quit && SDL_GetTicks() < end) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) quit = true;
        if (quit) break;
        SDL_GPUCommandBuffer *cmd = SDL_AcquireGPUCommandBuffer(g->device);
        if (!cmd) { ok = false; break; }
        SDL_GPUTexture *swap = NULL; uint32_t w, h;
        if (!SDL_WaitAndAcquireGPUSwapchainTexture(cmd, window, &swap, &w, &h)) {
            SDL_CancelGPUCommandBuffer(cmd); ok = false; break;
        }
        if (swap) {
            SDL_GPUBlitInfo info = {
                .source = {.texture = g->target, .w = g->width, .h = g->height},
                .destination = {.texture = swap, .w = w, .h = h},
                .load_op = SDL_GPU_LOADOP_DONT_CARE, .filter = SDL_GPU_FILTER_LINEAR
            };
            SDL_BlitGPUTexture(cmd, &info);
        }
        if (!SDL_SubmitGPUCommandBuffer(cmd)) { ok = false; break; }
        SDL_Delay(16);
    }
    SDL_WaitForGPUIdle(g->device);
    SDL_ReleaseWindowFromGPUDevice(g->device, window);
    SDL_DestroyWindow(window);
    return ok;
}

/* ---- The MetalUI window renderer (ruling RS-D) --------------------------- */

struct MUIRenderer {
    ReplayGPU *gpu;                 /* device, pipelines, sampler */
    SDL_Window *window;
    SDL_GPUCommandBuffer *cmd;      /* between begin and finish */
    SDL_GPUTexture *target;         /* the swapchain texture, or `offscreen` */
    uint32_t width, height;
    SDL_GPUTexture *offscreen;
    uint32_t offscreen_width, offscreen_height;
    SDL_GPUTexture *atlas;
    uint32_t atlas_width, atlas_height;
    SDL_GPUFence *fence;            /* the last offscreen frame */
    uint32_t unsignaled_fence_releases;
    uint64_t last_atlas_bytes;      /* the last frame's atlas bytes moved (RG-H) */
    uint32_t last_text_passes;      /* the last frame's surface text passes (DT-G) */
    uint32_t submissions;           /* every SDL_Submit… below (MV-L item 4) */
    BackdropState backdrop;         /* the frame target, the blur pool, the counters (BB-S) */
};

/* Releases the last offscreen frame's fence, counting a release made while
   the GPU had not yet signalled it. */
static void release_fence(MUIRenderer *r) {
    if (!r->fence) return;
    if (!SDL_QueryGPUFence(r->gpu->device, r->fence)) r->unsignaled_fence_releases += 1;
    SDL_ReleaseGPUFence(r->gpu->device, r->fence);
    r->fence = NULL;
}

uint32_t mui_renderer_unsignaled_fence_releases(MUIRenderer *r) { return r->unsignaled_fence_releases; }

uint32_t mui_renderer_submission_count(MUIRenderer *r) { return r->submissions; }

/* Waits for the last offscreen frame, then releases its fence. Never release
   it unwaited (record §61 §10): SDL returns a released fence to its pool at
   once, while the submitted command buffer still points at it, and the next
   submission re-arms that same fence (Direct3D 12 signals it back to 0 from
   the CPU). The older frame's queue signal then marks the fence done while
   the newer frame is still executing, and the next cleanup (any submit or
   wait) resets the newer frame's command allocator and destroys the buffers
   it released — mid-flight, the Direct3D 12 debug layer's break in
   D3D12_INTERNAL_DestroyBuffer. */
static void retire_fence(MUIRenderer *r) {
    if (!r->fence) return;
    SDL_WaitForGPUFences(r->gpu->device, true, &r->fence, 1);
    release_fence(r);
}

MUIRenderer *mui_renderer_create(const char *shader_dir, const char *driver) {
    ReplayGPU *gpu = replay_create_portable(shader_dir, driver);
    if (!gpu) return NULL;
    MUIRenderer *r = calloc(1, sizeof(*r));
    if (!r) { replay_destroy(gpu); SDL_SetError("allocation failed"); return NULL; }
    r->gpu = gpu;
    return r;
}

const char *mui_renderer_driver(MUIRenderer *r) { return replay_driver(r->gpu); }

void mui_renderer_destroy(MUIRenderer *r) {
    if (!r) return;
    SDL_GPUDevice *d = r->gpu->device;
    SDL_WaitForGPUIdle(d);
    if (r->cmd) SDL_CancelGPUCommandBuffer(r->cmd);
    release_fence(r); /* signalled: the device is idle */
    if (r->offscreen) SDL_ReleaseGPUTexture(d, r->offscreen);
    if (r->atlas) SDL_ReleaseGPUTexture(d, r->atlas);
    backdrop_destroy(r->gpu, &r->backdrop);
    if (r->window) SDL_ReleaseWindowFromGPUDevice(d, r->window);
    replay_destroy(r->gpu);
    free(r);
}

bool mui_renderer_claim_window(MUIRenderer *r, void *window) {
    if (!SDL_ClaimWindowForGPUDevice(r->gpu->device, (SDL_Window *)window)) return false;
    r->window = (SDL_Window *)window;
    return true;
}

bool mui_renderer_set_offscreen_size(MUIRenderer *r, uint32_t w, uint32_t h) {
    if (!w || !h || w > 8192 || h > 8192) return SDL_SetError("invalid offscreen size");
    if (r->offscreen && r->offscreen_width == w && r->offscreen_height == h) return true;
    if (r->offscreen) SDL_ReleaseGPUTexture(r->gpu->device, r->offscreen);
    r->offscreen = texture(r->gpu, w, h, true);
    r->offscreen_width = w; r->offscreen_height = h;
    return r->offscreen != NULL;
}

int mui_renderer_begin(MUIRenderer *r, uint32_t *w, uint32_t *h) {
    if (r->cmd) { SDL_CancelGPUCommandBuffer(r->cmd); r->cmd = NULL; }
    r->cmd = SDL_AcquireGPUCommandBuffer(r->gpu->device);
    if (!r->cmd) return -1;
    if (r->window) {
        SDL_GPUTexture *swap = NULL;
        if (!SDL_WaitAndAcquireGPUSwapchainTexture(r->cmd, r->window, &swap, &r->width, &r->height)) {
            SDL_CancelGPUCommandBuffer(r->cmd); r->cmd = NULL; return -1;
        }
        if (!swap) { SDL_CancelGPUCommandBuffer(r->cmd); r->cmd = NULL; return 0; }
        r->target = swap;
    } else {
        if (!r->offscreen) { SDL_CancelGPUCommandBuffer(r->cmd); r->cmd = NULL;
                             SDL_SetError("no window claimed and no offscreen size"); return -1; }
        r->target = r->offscreen;
        r->width = r->offscreen_width; r->height = r->offscreen_height;
    }
    *w = r->width; *h = r->height;
    return 1;
}

void *mui_renderer_create_texture(MUIRenderer *r, const uint8_t *rgba, uint32_t w, uint32_t h) {
    if (!w || !h || w > 8192 || h > 8192) { SDL_SetError("invalid image texture size"); return NULL; }
    SDL_GPUDevice *d = r->gpu->device;
    SDL_GPUTexture *result = texture_of(r->gpu, w, h, false, SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM);
    SDL_GPUTransferBuffer *upload = transfer(r->gpu, w * h * 4, false, rgba);
    SDL_GPUCommandBuffer *cmd = NULL;
    SDL_GPUCopyPass *copy = NULL;
    if (!result || !upload) goto fail;
    /* Its own command buffer, submitted now: SDL runs submissions in order, so
       it is uploaded before any frame submitted after this call samples it. */
    cmd = SDL_AcquireGPUCommandBuffer(d);
    if (!cmd) goto fail;
    copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto fail;
    SDL_GPUTextureTransferInfo src = { .transfer_buffer = upload };
    SDL_GPUTextureRegion dst = { .texture = result, .w = w, .h = h, .d = 1 };
    SDL_UploadToGPUTexture(copy, &src, &dst, false);
    SDL_EndGPUCopyPass(copy);
    r->submissions += 1;
    if (!SDL_SubmitGPUCommandBuffer(cmd)) { cmd = NULL; goto fail; }
    SDL_ReleaseGPUTransferBuffer(d, upload);
    return result;
fail:
    if (cmd) SDL_CancelGPUCommandBuffer(cmd);
    if (upload) SDL_ReleaseGPUTransferBuffer(d, upload);
    if (result) SDL_ReleaseGPUTexture(d, result);
    return NULL;
}

void mui_renderer_release_texture(MUIRenderer *r, void *texture) {
    if (texture) SDL_ReleaseGPUTexture(r->gpu->device, (SDL_GPUTexture *)texture);
}

/* ---- App-owned GPU surfaces (MetalView, ruling MV-H item 2) ---------------- */

void *mui_renderer_device(MUIRenderer *r) { return r->gpu->device; }

void *mui_renderer_command_buffer(MUIRenderer *r) { return r->cmd; }

/* A surface's render target: B8G8R8A8_UNORM (never sRGB, §7.8), colour target
   and sampler, uninitialised. Created only — no upload, so no command buffer,
   no submission and no fence (unlike mui_renderer_create_texture). */
void *mui_renderer_create_target(MUIRenderer *r, uint32_t w, uint32_t h) {
    if (!w || !h || w > 8192 || h > 8192) { SDL_SetError("invalid surface target size"); return NULL; }
    return texture(r->gpu, w, h, true);
}

/* One render pass over `texture`, LOADOP_CLEAR to the premultiplied colour,
   ended at once — recorded into `cmd`, never submitted here. */
bool mui_gpu_clear_texture(void *cmd, void *texture, float red, float green, float blue, float alpha) {
    if (!cmd || !texture) return SDL_SetError("clear without a command buffer or texture");
    SDL_GPUColorTargetInfo target = {
        .texture = (SDL_GPUTexture *)texture,
        .clear_color = { red, green, blue, alpha },
        .load_op = SDL_GPU_LOADOP_CLEAR, .store_op = SDL_GPU_STOREOP_STORE
    };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass((SDL_GPUCommandBuffer *)cmd, &target, 1, NULL);
    if (!pass) return false;
    SDL_EndGPURenderPass(pass);
    return true;
}

/* A nearest blit of the whole source over (0, 0, dw, dh) of the destination,
   recorded into `cmd`, never submitted here (MV-Q's test fill). */
bool mui_gpu_blit_texture(void *cmd, void *source, uint32_t sw, uint32_t sh,
                          void *destination, uint32_t dw, uint32_t dh) {
    if (!cmd || !source || !destination || !sw || !sh || !dw || !dh)
        return SDL_SetError("blit without a command buffer, a texture or a size");
    SDL_GPUBlitInfo info = {
        .source = { .texture = (SDL_GPUTexture *)source, .w = sw, .h = sh },
        .destination = { .texture = (SDL_GPUTexture *)destination, .w = dw, .h = dh },
        .load_op = SDL_GPU_LOADOP_LOAD,
        .filter = SDL_GPU_FILTER_NEAREST
    };
    SDL_BlitGPUTexture((SDL_GPUCommandBuffer *)cmd, &info);
    return true;
}

bool mui_renderer_finish(MUIRenderer *r,
    const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
    const void *images, uint32_t ib, const void *transforms, uint32_t tb,
    const void *backdrops, uint32_t kb, const ReplayRegion *regions, uint32_t region_count,
    void *const *textures, uint32_t texture_count,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah,
    const uint32_t *atlas_rects, uint32_t atlas_rect_count,
    const ReplaySurfaceText *texts, uint32_t text_count,
    const float *projection) {
    if (!r->cmd) return SDL_SetError("finish without a successful begin");
    r->last_text_passes = 0;
    SDL_GPUDevice *d = r->gpu->device;
    SDL_GPUCommandBuffer *cmd = r->cmd;
    r->cmd = NULL;
    SDL_GPUBuffer *buffers[BUF_COUNT] = {0};
    SDL_GPUTransferBuffer *uploads[BUF_COUNT + 1] = {0};
    void *packed[2] = {0};
    uint8_t *atlas_packed = NULL;
    uint32_t atlas_bytes = 0;
    bool ok = false;
    if (!images_valid(images, ib, texture_count, runs, count)) goto cleanup;
    if (tb % TRANSFORM_STRIDE) { SDL_SetError("unexpected MetalUI transform ABI"); goto cleanup; }
    if (kb % BACKDROP_STRIDE || region_count != kb / BACKDROP_STRIDE) { SDL_SetError("unexpected MetalUI backdrop ABI"); goto cleanup; }
    if (!transforms_valid(rects, rb, glyphs, gb, images, ib, backdrops, kb, tb, runs, count)) goto cleanup;
    /* A surface text range names glyph records the buffer holds, with transforms the table holds (DT-G):
       checked like a run, since it is drawn like one. */
    for (uint32_t i = 0; i < text_count; i++) {
        if (!texts[i].target || !texts[i].width || !texts[i].height) { SDL_SetError("surface text without a target"); goto cleanup; }
        ReplayRun run = { KIND_GLYPH, texts[i].start, texts[i].count };
        if (!transforms_valid(NULL, 0, glyphs, gb, NULL, 0, NULL, 0, tb, &run, 1)) goto cleanup;
    }

    /* The CPU ABI is scalar-packed (120/88 bytes); SDL storage buffers use
       16-byte lanes, so each record is copied into a 128/96-byte slot. An
       image (64 bytes) and a backdrop (96) are already whole lanes. */
    const float aligned_quad[] = {0,0,0,0, 1,0,0,0, 0,1,0,0, 1,1,0,0};
    const void *data[BUF_COUNT] = {aligned_quad, rects, glyphs, images, tb ? transforms : empty_transform, backdrops};
    uint32_t sizes[BUF_COUNT] = {sizeof(aligned_quad), rb, gb, ib, tb ? tb : TRANSFORM_STRIDE, kb};
    uint32_t rect_records = 0;
    if (!pack_records(rects, rb, glyphs, gb, backdrops, kb, packed, data, sizes, &rect_records)) goto cleanup;
    for (int i = 0; i < BUF_COUNT; i++) {
        if (!sizes[i]) continue;
        SDL_GPUBufferCreateInfo info = { .usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, .size = sizes[i] };
        buffers[i] = SDL_CreateGPUBuffer(d, &info);
        uploads[i] = transfer(r->gpu, sizes[i], false, data[i]);
        if (!buffers[i] || !uploads[i]) goto cleanup;
    }
    bool atlas_new = !r->atlas || r->atlas_width != aw || r->atlas_height != ah;
    if (atlas_new) {
        if (r->atlas) SDL_ReleaseGPUTexture(d, r->atlas);
        r->atlas = texture(r->gpu, aw, ah, false);
        r->atlas_width = aw; r->atlas_height = ah;
        if (!r->atlas) goto cleanup;
    }
    /* A new or resized atlas texture takes the whole atlas; otherwise only the dirty rects, packed
       tightly into one transfer buffer and copied one `SDL_UploadToGPUTexture` per rect (RG-H). */
    if (atlas_new) {
        atlas_bytes = aw * ah;
        uploads[BUF_COUNT] = transfer(r->gpu, atlas_bytes, false, atlas);
        if (!uploads[BUF_COUNT]) goto cleanup;
    } else if (atlas_rect_count) {
        uint64_t total = 0;
        for (uint32_t i = 0; i < atlas_rect_count; i++) {
            uint32_t rx = atlas_rects[4 * i], ry = atlas_rects[4 * i + 1];
            uint32_t rw = atlas_rects[4 * i + 2], rh = atlas_rects[4 * i + 3];
            if (rx > aw || rw > aw - rx || ry > ah || rh > ah - ry) {
                SDL_SetError("atlas dirty rect outside the atlas"); goto cleanup;
            }
            total += (uint64_t)rw * rh;
        }
        if (total) {
            atlas_packed = malloc(total);
            if (!atlas_packed) { SDL_SetError("out of memory"); goto cleanup; }
            uint8_t *out = atlas_packed;
            for (uint32_t i = 0; i < atlas_rect_count; i++) {
                uint32_t rx = atlas_rects[4 * i], ry = atlas_rects[4 * i + 1];
                uint32_t rw = atlas_rects[4 * i + 2], rh = atlas_rects[4 * i + 3];
                for (uint32_t row = 0; row < rh; row++) {
                    memcpy(out, atlas + (size_t)(ry + row) * aw + rx, rw);
                    out += rw;
                }
            }
            atlas_bytes = (uint32_t)total;
            uploads[BUF_COUNT] = transfer(r->gpu, atlas_bytes, false, atlas_packed);
            if (!uploads[BUF_COUNT]) goto cleanup;
        }
    }
    r->last_atlas_bytes = atlas_bytes;
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < BUF_COUNT; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    if (uploads[BUF_COUNT] && atlas_new) {
        SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[BUF_COUNT] };
        SDL_GPUTextureRegion atlas_dst = { .texture = r->atlas, .w = aw, .h = ah, .d = 1 };
        SDL_UploadToGPUTexture(copy, &atlas_src, &atlas_dst, false);
    } else if (uploads[BUF_COUNT]) {
        uint32_t offset = 0;
        for (uint32_t i = 0; i < atlas_rect_count; i++) {
            uint32_t rw = atlas_rects[4 * i + 2], rh = atlas_rects[4 * i + 3];
            if (!rw || !rh) continue;
            SDL_GPUTextureTransferInfo src = { .transfer_buffer = uploads[BUF_COUNT], .offset = offset,
                                               .pixels_per_row = rw, .rows_per_layer = rh };
            SDL_GPUTextureRegion dst = { .texture = r->atlas, .x = atlas_rects[4 * i], .y = atlas_rects[4 * i + 1],
                                         .w = rw, .h = rh, .d = 1 };
            SDL_UploadToGPUTexture(copy, &src, &dst, false);
            offset += rw * rh;
        }
    }
    SDL_EndGPUCopyPass(copy);

    FrameDraw frame = {
        .g = r->gpu, .cmd = cmd, .atlas = r->atlas, .image_textures = (SDL_GPUTexture *const *)textures,
        .images = images, .backdrops = backdrops, .regions = regions, .rect_records = rect_records,
        .runs = runs, .run_count = count, .width = r->width, .height = r->height, .projection = projection,
        .viewport = {(float)r->width, (float)r->height, 0, 0}
    };
    memcpy(frame.buffers, buffers, sizeof(buffers));
    /* The app's surface text (ruling DT-G): one load-op pass per surface over what the app drew, with the
       viewport the target's own size. After the atlas copy pass (its glyphs are uploaded) and before the
       scene's pass, which samples the target. No submission, no fence, no pipeline of its own. */
    for (uint32_t i = 0; i < text_count; i++) {
        if (!texts[i].count) continue;
        FrameDraw text = frame;
        text.width = texts[i].width; text.height = texts[i].height;
        text.viewport.width = (float)texts[i].width; text.viewport.height = (float)texts[i].height;
        SDL_GPURenderPass *pass = begin_segment(&text, (SDL_GPUTexture *)texts[i].target, SDL_GPU_LOADOP_LOAD);
        if (!pass) goto cleanup;
        draw_primitives(&text, pass, KIND_GLYPH, texts[i].start, texts[i].count);
        SDL_EndGPURenderPass(pass);
        r->last_text_passes += 1;
    }
    if (!encode_frame(&frame, &r->backdrop, r->target, false)) goto cleanup;
    r->submissions += 1;
    if (r->window) {
        ok = SDL_SubmitGPUCommandBuffer(cmd);
    } else {
        retire_fence(r);
        r->fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
        ok = r->fence != NULL;
    }
    cmd = NULL;
cleanup:
    if (cmd) SDL_CancelGPUCommandBuffer(cmd);
    /* SDL releases these once the GPU no longer uses them. */
    for (int i = 0; i < BUF_COUNT; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(d, buffers[i]);
    for (int i = 0; i < BUF_COUNT + 1; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(d, uploads[i]);
    free(packed[0]); free(packed[1]); free(atlas_packed);
    return ok;
}

void mui_renderer_backdrop_counters(MUIRenderer *r, uint32_t out[5]) {
    out[0] = r->backdrop.splits; out[1] = r->backdrop.blurs; out[2] = r->backdrop.passes;
    out[3] = r->backdrop.copies; out[4] = r->backdrop.made;
}

uint64_t mui_renderer_last_atlas_bytes(MUIRenderer *r) { return r->last_atlas_bytes; }

uint32_t mui_renderer_last_text_passes(MUIRenderer *r) { return r->last_text_passes; }

bool mui_renderer_has_frame_target(MUIRenderer *r) { return r->backdrop.frame != NULL; }

void mui_renderer_set_backdrop_hooks(MUIRenderer *r, bool pool_fails, bool route_every_frame) {
    r->backdrop.pool_fails = pool_fails;
    r->backdrop.route_every_frame = route_every_frame;
}

bool mui_renderer_read_offscreen(MUIRenderer *r, uint8_t *out) {
    if (!r->offscreen) return SDL_SetError("no offscreen target");
    SDL_GPUDevice *d = r->gpu->device;
    retire_fence(r);
    uint32_t w = r->offscreen_width, h = r->offscreen_height, pitch = (w * 4 + 255) & ~255u;
    SDL_GPUTransferBuffer *download = transfer(r->gpu, pitch * h, true, NULL);
    if (!download) return false;
    bool ok = false;
    SDL_GPUFence *fence = NULL;
    SDL_GPUCommandBuffer *cmd = SDL_AcquireGPUCommandBuffer(d);
    if (!cmd) goto done;
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) { SDL_CancelGPUCommandBuffer(cmd); goto done; }
    SDL_GPUTextureRegion src = { .texture = r->offscreen, .w = w, .h = h, .d = 1 };
    SDL_GPUTextureTransferInfo dst = { .transfer_buffer = download, .pixels_per_row = pitch / 4, .rows_per_layer = h };
    SDL_DownloadFromGPUTexture(copy, &src, &dst);
    SDL_EndGPUCopyPass(copy);
    r->submissions += 1;
    fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    if (!fence || !SDL_WaitForGPUFences(d, true, &fence, 1)) goto done;
    const uint8_t *mapped = SDL_MapGPUTransferBuffer(d, download, false);
    if (!mapped) goto done;
    for (uint32_t y = 0; y < h; y++) memcpy(out + y * w * 4, mapped + y * pitch, w * 4);
    SDL_UnmapGPUTransferBuffer(d, download);
    ok = true;
done:
    if (fence) SDL_ReleaseGPUFence(d, fence);
    SDL_ReleaseGPUTransferBuffer(d, download);
    return ok;
}

float mui_window_pixel_density(void *window) {
    return SDL_GetWindowPixelDensity((SDL_Window *)window);
}

/* ---- The SDL platform (ruling SP-A) ------------------------------------- */

static Uint32 accessibility_event_type = 0;
static Uint32 dialog_event_type = 0;
static SDL_Mutex *dialog_mutex = NULL;

/* Application id (ruling AP-E): process-global recorders written in the
   production path, `mui_cursor_*` style. Sequence numbers order the hint
   before SDL_Init for the last call; SDL is refcounted, so a read-back of the
   hint after init could not prove "before". */
static uint32_t app_id_sets = 0;
static char app_id_last[256] = {0};
static uint32_t app_id_seq = 0;
static uint32_t app_id_hint_seq = 0;
static uint32_t app_id_init_seq = 0;
static char app_id_seen_at_init[256] = {0};

bool mui_platform_init(const char *app_id) {
    app_id_hint_seq = 0;
    if (app_id != NULL && app_id[0] != '\0') {
        // SDL_HINT_APP_ID names the Wayland app_id / X11 WM_CLASS; "should be set
        // before SDL is initialized". Normal priority: the SDL_APP_ID environment
        // variable still overrides (AP-B).
        SDL_SetHint(SDL_HINT_APP_ID, app_id);
        app_id_hint_seq = ++app_id_seq;
        app_id_sets++;
        SDL_strlcpy(app_id_last, app_id, sizeof app_id_last);
    }
    // The application decides when it ends (ruling AS-B item 6): SDL's own
    // SDL_EVENT_QUIT after the last visible window's close request would end
    // a run whose close the app just vetoed. Every close request reaches
    // MetalUI, and only an approved one closes.
    SDL_SetHint(SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE, "0");
    app_id_init_seq = ++app_id_seq;
    {
        // SDL's own state immediately before SDL_Init (AP-E): what SDL will read.
        const char *seen = SDL_GetHint(SDL_HINT_APP_ID);
        SDL_strlcpy(app_id_seen_at_init, seen ? seen : "", sizeof app_id_seen_at_init);
    }
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) return false;
    // Drops from other applications (ruling DN-M) — enabled explicitly, so a
    // build of SDL that ships either kind disabled still delivers both.
    SDL_SetEventEnabled(SDL_EVENT_DROP_FILE, true);
    SDL_SetEventEnabled(SDL_EVENT_DROP_TEXT, true);
    if (accessibility_event_type == 0) accessibility_event_type = SDL_RegisterEvents(1);
    // File dialogs (ruling SV-G): their own wake event and the answer queue's
    // lock, created once per process.
    if (dialog_event_type == 0) dialog_event_type = SDL_RegisterEvents(1);
    if (!dialog_mutex) dialog_mutex = SDL_CreateMutex();
    return accessibility_event_type != 0 && dialog_event_type != 0 && dialog_mutex != NULL;
}

bool mui_wake_for_accessibility(uint32_t window_id) {
    SDL_Event e;
    SDL_zero(e);
    e.type = accessibility_event_type;
    e.user.windowID = window_id;
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

static uint32_t mods(SDL_Keymod m) {
    uint32_t r = 0;
    if (m & SDL_KMOD_SHIFT) r |= MUI_MOD_SHIFT;
    if (m & SDL_KMOD_CTRL) r |= MUI_MOD_CONTROL;
    if (m & SDL_KMOD_ALT) r |= MUI_MOD_OPTION;
    if (m & SDL_KMOD_GUI) r |= MUI_MOD_COMMAND;
    return r;
}

static bool translate(const SDL_Event *e, MUIEvent *out) {
    memset(out, 0, sizeof(*out));
    out->timestamp = (double)e->common.timestamp / 1e9;
    if (accessibility_event_type != 0 && e->type == accessibility_event_type) {
        out->kind = MUI_EVENT_ACCESSIBILITY; out->window_id = e->user.windowID; return true;
    }
    if (mui_instance_is_wake_event(e->type)) {   // SN-G: counted, then handed to Swift
        out->kind = MUI_EVENT_INSTANCE; return true;
    }
    if (dialog_event_type != 0 && e->type == dialog_event_type) {   // SV-G
        out->kind = MUI_EVENT_DIALOG; out->window_id = e->user.windowID; out->start = e->user.code; return true;
    }
    switch (e->type) {
    case SDL_EVENT_QUIT: out->kind = MUI_EVENT_QUIT; return true;
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        out->kind = MUI_EVENT_CLOSE; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_RESIZED: case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
    case SDL_EVENT_WINDOW_ENTER_FULLSCREEN: case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:   // CW-S: the chrome snapshot refreshes
    case SDL_EVENT_WINDOW_MAXIMIZED: case SDL_EVENT_WINDOW_RESTORED:
        out->kind = MUI_EVENT_RESIZE; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_EXPOSED:
        out->kind = MUI_EVENT_EXPOSED; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
        out->kind = MUI_EVENT_FOCUS_GAINED; out->window_id = e->window.windowID;
        out->modifiers = mods(SDL_GetModState());   // the modifiers held now (IF-I)
        return true;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        out->kind = MUI_EVENT_FOCUS_LOST; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_MOUSE_LEAVE:   // the pointer left the window (SV-N item 7)
        out->kind = MUI_EVENT_MOUSE_LEAVE; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_SYSTEM_THEME_CHANGED: out->kind = MUI_EVENT_THEME; return true;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: case SDL_EVENT_MOUSE_BUTTON_UP:
        // The primary button, the secondary one as its own kinds (ruling MN-B
        // item 3), every other button as OTHER_* with its SDL number (CI-E
        // item 4; Swift numbers it as AppKit does). A ctrl-click stays a
        // primary press (MN-AC item 1: off Apple it is List's toggle).
        if (e->button.button == SDL_BUTTON_LEFT)
            out->kind = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? MUI_EVENT_MOUSE_DOWN : MUI_EVENT_MOUSE_UP;
        else if (e->button.button == SDL_BUTTON_RIGHT)
            out->kind = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? MUI_EVENT_RIGHT_DOWN : MUI_EVENT_RIGHT_UP;
        else
            out->kind = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? MUI_EVENT_OTHER_DOWN : MUI_EVENT_OTHER_UP;
        out->window_id = e->button.windowID; out->x = e->button.x; out->y = e->button.y;
        out->clicks = e->button.clicks; out->modifiers = mods(SDL_GetModState());
        out->button = e->button.button;
        return true;
    case SDL_EVENT_MOUSE_MOTION:
        // The left button wins (a primary drag), then the right, then the
        // lowest held other button (CI-E item 4).
        if (e->motion.state & SDL_BUTTON_LMASK) out->kind = MUI_EVENT_MOUSE_DRAG;
        else if (e->motion.state & SDL_BUTTON_RMASK) out->kind = MUI_EVENT_RIGHT_DRAG;
        else if (e->motion.state & SDL_BUTTON_MMASK) { out->kind = MUI_EVENT_OTHER_DRAG; out->button = SDL_BUTTON_MIDDLE; }
        else if (e->motion.state & SDL_BUTTON_X1MASK) { out->kind = MUI_EVENT_OTHER_DRAG; out->button = SDL_BUTTON_X1; }
        else if (e->motion.state & SDL_BUTTON_X2MASK) { out->kind = MUI_EVENT_OTHER_DRAG; out->button = SDL_BUTTON_X2; }
        else out->kind = MUI_EVENT_MOUSE_MOVE;
        out->window_id = e->motion.windowID;
        out->x = e->motion.x; out->y = e->motion.y; out->modifiers = mods(SDL_GetModState());
        return true;
    case SDL_EVENT_TEXT_INPUT:
        out->kind = MUI_EVENT_TEXT_INPUT; out->window_id = e->text.windowID; out->text = e->text.text;
        return true;
    case SDL_EVENT_TEXT_EDITING:
        out->kind = MUI_EVENT_TEXT_EDITING; out->window_id = e->edit.windowID; out->text = e->edit.text;
        out->start = e->edit.start; out->length = e->edit.length;
        return true;
    case SDL_EVENT_MOUSE_WHEEL: {
        out->kind = MUI_EVENT_WHEEL; out->window_id = e->wheel.windowID;
        out->x = e->wheel.mouse_x; out->y = e->wheel.mouse_y;
        /* SDL reports FLIPPED for "natural" scrolling with the values
           already reversed; undo nothing, so the sign follows what the user
           asked the system for, as AppKit's scrollingDelta does. */
        out->dx = e->wheel.x; out->dy = e->wheel.y;
        out->modifiers = mods(SDL_GetModState());
        return true;
    }
    case SDL_EVENT_PINCH_BEGIN: case SDL_EVENT_PINCH_UPDATE: case SDL_EVENT_PINCH_END:
        // A trackpad pinch (ruling CI-K item 1): no position (Swift uses the
        // window's last pointer position), and window 0 from cocoa (Swift
        // routes it, CI-K item 2).
        out->kind = MUI_EVENT_PINCH; out->window_id = e->pinch.windowID; out->scale = e->pinch.scale;
        out->phase = e->type == SDL_EVENT_PINCH_BEGIN ? MUI_PINCH_BEGIN
                   : e->type == SDL_EVENT_PINCH_UPDATE ? MUI_PINCH_UPDATE : MUI_PINCH_END;
        out->modifiers = mods(SDL_GetModState());
        return true;
    case SDL_EVENT_CLIPBOARD_UPDATE:   // CP-G: no window; Swift tells every window's handler
        out->kind = MUI_EVENT_CLIPBOARD; return true;
    case SDL_EVENT_KEY_DOWN: case SDL_EVENT_KEY_UP:
        out->kind = e->type == SDL_EVENT_KEY_DOWN ? MUI_EVENT_KEY_DOWN : MUI_EVENT_KEY_UP;
        out->window_id = e->key.windowID; out->keycode = e->key.key;
        out->modifiers = mods(e->key.mod); out->repeat = e->key.repeat;
        return true;
    // Drops from other applications (ruling DN-M): the five kinds carry the
    // window, SDL's window-relative position (none on BEGIN) and, for FILE and
    // TEXT, SDL's string — valid until the next poll, so Swift copies it.
    case SDL_EVENT_DROP_BEGIN: case SDL_EVENT_DROP_POSITION: case SDL_EVENT_DROP_FILE:
    case SDL_EVENT_DROP_TEXT: case SDL_EVENT_DROP_COMPLETE:
        switch (e->type) {
        case SDL_EVENT_DROP_BEGIN: out->kind = MUI_EVENT_DROP_BEGIN; break;
        case SDL_EVENT_DROP_POSITION: out->kind = MUI_EVENT_DROP_POSITION; break;
        case SDL_EVENT_DROP_FILE: out->kind = MUI_EVENT_DROP_FILE; break;
        case SDL_EVENT_DROP_TEXT: out->kind = MUI_EVENT_DROP_TEXT; break;
        default: out->kind = MUI_EVENT_DROP_COMPLETE; break;
        }
        out->window_id = e->drop.windowID; out->x = e->drop.x; out->y = e->drop.y;
        out->text = e->drop.data;
        return true;
    default: return false;
    }
}

bool mui_poll_event(MUIEvent *out) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) if (translate(&e, out)) return true;
    return false;
}

bool mui_wait_event(MUIEvent *out, int32_t timeout_ms) {
    SDL_Event e;
    if (!SDL_WaitEventTimeout(&e, timeout_ms)) return false;
    if (translate(&e, out)) return true;
    return mui_poll_event(out);
}

bool mui_push_event(const MUIEvent *in) {
    SDL_Event e;
    SDL_zero(e);
    switch (in->kind) {
    case MUI_EVENT_QUIT: e.type = SDL_EVENT_QUIT; break;   // a termination request (AS-C item 8)
    case MUI_EVENT_MOUSE_DOWN: case MUI_EVENT_MOUSE_UP:
        e.type = in->kind == MUI_EVENT_MOUSE_DOWN ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
        e.button.windowID = in->window_id; e.button.button = SDL_BUTTON_LEFT;
        e.button.down = in->kind == MUI_EVENT_MOUSE_DOWN; e.button.clicks = (Uint8)in->clicks;
        e.button.x = in->x; e.button.y = in->y; break;
    case MUI_EVENT_RIGHT_DOWN: case MUI_EVENT_RIGHT_UP:
        e.type = in->kind == MUI_EVENT_RIGHT_DOWN ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
        e.button.windowID = in->window_id; e.button.button = SDL_BUTTON_RIGHT;
        e.button.down = in->kind == MUI_EVENT_RIGHT_DOWN; e.button.clicks = (Uint8)in->clicks;
        e.button.x = in->x; e.button.y = in->y; break;
    case MUI_EVENT_MOUSE_MOVE:
        e.type = SDL_EVENT_MOUSE_MOTION; e.motion.windowID = in->window_id;
        e.motion.x = in->x; e.motion.y = in->y; break;
    case MUI_EVENT_MOUSE_DRAG:
        e.type = SDL_EVENT_MOUSE_MOTION; e.motion.windowID = in->window_id; e.motion.state = SDL_BUTTON_LMASK;
        e.motion.x = in->x; e.motion.y = in->y; break;
    // Synthetic text for tests: SDL keeps the pointer, so the copy is leaked
    // on purpose (a test pushes a handful).
    case MUI_EVENT_TEXT_INPUT:
        e.type = SDL_EVENT_TEXT_INPUT; e.text.windowID = in->window_id;
        e.text.text = SDL_strdup(in->text ? in->text : ""); break;
    case MUI_EVENT_TEXT_EDITING:
        e.type = SDL_EVENT_TEXT_EDITING; e.edit.windowID = in->window_id;
        e.edit.text = SDL_strdup(in->text ? in->text : ""); e.edit.start = in->start; e.edit.length = in->length; break;
    case MUI_EVENT_WHEEL:
        e.type = SDL_EVENT_MOUSE_WHEEL; e.wheel.windowID = in->window_id;
        e.wheel.x = in->dx; e.wheel.y = in->dy; e.wheel.mouse_x = in->x; e.wheel.mouse_y = in->y; break;
    case MUI_EVENT_KEY_DOWN: case MUI_EVENT_KEY_UP:
        e.type = in->kind == MUI_EVENT_KEY_DOWN ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
        e.key.windowID = in->window_id; e.key.key = in->keycode; e.key.repeat = in->repeat;
        e.key.down = in->kind == MUI_EVENT_KEY_DOWN;
        e.key.mod = (in->modifiers & MUI_MOD_SHIFT ? SDL_KMOD_LSHIFT : 0)
                  | (in->modifiers & MUI_MOD_CONTROL ? SDL_KMOD_LCTRL : 0)
                  | (in->modifiers & MUI_MOD_OPTION ? SDL_KMOD_LALT : 0)
                  | (in->modifiers & MUI_MOD_COMMAND ? SDL_KMOD_LGUI : 0);
        break;
    case MUI_EVENT_CLOSE:
        e.type = SDL_EVENT_WINDOW_CLOSE_REQUESTED; e.window.windowID = in->window_id; break;
    case MUI_EVENT_RESIZE:
        e.type = SDL_EVENT_WINDOW_RESIZED; e.window.windowID = in->window_id; break;
    case MUI_EVENT_THEME: e.type = SDL_EVENT_SYSTEM_THEME_CHANGED; break;
    case MUI_EVENT_FOCUS_GAINED: case MUI_EVENT_FOCUS_LOST:
        e.type = in->kind == MUI_EVENT_FOCUS_GAINED ? SDL_EVENT_WINDOW_FOCUS_GAINED : SDL_EVENT_WINDOW_FOCUS_LOST;
        e.window.windowID = in->window_id;
        // A window event carries no modifiers: a test's held keys are SDL's
        // tracked state, set as a held key would (IF-I).
        SDL_SetModState((in->modifiers & MUI_MOD_SHIFT ? SDL_KMOD_LSHIFT : 0)
                      | (in->modifiers & MUI_MOD_CONTROL ? SDL_KMOD_LCTRL : 0)
                      | (in->modifiers & MUI_MOD_OPTION ? SDL_KMOD_LALT : 0)
                      | (in->modifiers & MUI_MOD_COMMAND ? SDL_KMOD_LGUI : 0));
        break;
    default: return SDL_SetError("unsupported synthetic event");
    }
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

const uint32_t mui_sdl_event_window_display_scale_changed = SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED;
const uint32_t mui_sdl_event_window_pixel_size_changed = SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED;

bool mui_push_raw_window_event(uint32_t sdl_type, uint32_t window_id) {
    if (sdl_type < SDL_EVENT_WINDOW_FIRST || sdl_type > SDL_EVENT_WINDOW_LAST)
        return SDL_SetError("not a window event");
    SDL_Event e;
    SDL_zero(e);
    e.type = sdl_type; e.window.windowID = window_id;
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

const uint32_t mui_sdl_event_window_mouse_leave = SDL_EVENT_WINDOW_MOUSE_LEAVE;

const uint32_t mui_sdl_event_drop_begin = SDL_EVENT_DROP_BEGIN;
const uint32_t mui_sdl_event_drop_position = SDL_EVENT_DROP_POSITION;
const uint32_t mui_sdl_event_drop_file = SDL_EVENT_DROP_FILE;
const uint32_t mui_sdl_event_drop_text = SDL_EVENT_DROP_TEXT;
const uint32_t mui_sdl_event_drop_complete = SDL_EVENT_DROP_COMPLETE;

bool mui_push_raw_drop_event(uint32_t sdl_type, uint32_t window_id, float x, float y, const char *data) {
    if (sdl_type < SDL_EVENT_DROP_FILE || sdl_type > SDL_EVENT_DROP_POSITION)
        return SDL_SetError("not a drop event");
    SDL_Event e;
    SDL_zero(e);
    e.type = sdl_type; e.drop.windowID = window_id; e.drop.x = x; e.drop.y = y;
    // As the synthetic text events above: SDL keeps the pointer, so the copy
    // is leaked on purpose (a test pushes a handful).
    e.drop.data = data ? SDL_strdup(data) : NULL;
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

const uint32_t mui_sdl_event_mouse_button_down = SDL_EVENT_MOUSE_BUTTON_DOWN;
const uint32_t mui_sdl_event_mouse_button_up = SDL_EVENT_MOUSE_BUTTON_UP;
const uint32_t mui_sdl_event_mouse_motion = SDL_EVENT_MOUSE_MOTION;
const uint8_t mui_sdl_button_left = SDL_BUTTON_LEFT;
const uint8_t mui_sdl_button_right = SDL_BUTTON_RIGHT;
const uint32_t mui_sdl_button_lmask = SDL_BUTTON_LMASK;
const uint32_t mui_sdl_button_rmask = SDL_BUTTON_RMASK;
const uint8_t mui_sdl_button_middle = SDL_BUTTON_MIDDLE;
const uint8_t mui_sdl_button_x1 = SDL_BUTTON_X1;
const uint8_t mui_sdl_button_x2 = SDL_BUTTON_X2;
const uint32_t mui_sdl_button_mmask = SDL_BUTTON_MMASK;
const uint32_t mui_sdl_button_x1mask = SDL_BUTTON_X1MASK;
const uint32_t mui_sdl_button_x2mask = SDL_BUTTON_X2MASK;

const uint32_t mui_sdl_event_pinch_begin = SDL_EVENT_PINCH_BEGIN;
const uint32_t mui_sdl_event_pinch_update = SDL_EVENT_PINCH_UPDATE;
const uint32_t mui_sdl_event_pinch_end = SDL_EVENT_PINCH_END;

bool mui_push_raw_pinch_event(uint32_t sdl_type, uint32_t window_id, float scale) {
    if (sdl_type != SDL_EVENT_PINCH_BEGIN && sdl_type != SDL_EVENT_PINCH_UPDATE && sdl_type != SDL_EVENT_PINCH_END)
        return SDL_SetError("not a pinch event");
    SDL_Event e;
    SDL_zero(e);
    e.type = sdl_type; e.pinch.windowID = window_id; e.pinch.scale = scale;
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

uint32_t mui_mouse_focus_window_id(void) {
    SDL_Window *w = SDL_GetMouseFocus();
    return w ? SDL_GetWindowID(w) : 0;
}

static SDL_Cursor *system_cursors[MUI_CURSOR_COUNT];

bool mui_set_system_cursor(int32_t cursor) {
    static const SDL_SystemCursor kinds[MUI_CURSOR_COUNT] = {
        SDL_SYSTEM_CURSOR_DEFAULT, SDL_SYSTEM_CURSOR_TEXT, SDL_SYSTEM_CURSOR_CROSSHAIR, SDL_SYSTEM_CURSOR_MOVE,
        SDL_SYSTEM_CURSOR_POINTER, SDL_SYSTEM_CURSOR_EW_RESIZE, SDL_SYSTEM_CURSOR_NS_RESIZE,
        SDL_SYSTEM_CURSOR_N_RESIZE, SDL_SYSTEM_CURSOR_S_RESIZE, SDL_SYSTEM_CURSOR_E_RESIZE,
        SDL_SYSTEM_CURSOR_W_RESIZE, SDL_SYSTEM_CURSOR_NE_RESIZE, SDL_SYSTEM_CURSOR_NW_RESIZE,
        SDL_SYSTEM_CURSOR_SE_RESIZE, SDL_SYSTEM_CURSOR_SW_RESIZE,
    };
    if (cursor < 0 || cursor >= MUI_CURSOR_COUNT) return SDL_SetError("unknown cursor");
    if (!system_cursors[cursor]) system_cursors[cursor] = SDL_CreateSystemCursor(kinds[cursor]);
    if (!system_cursors[cursor]) return false;
    return SDL_SetCursor(system_cursors[cursor]);
}

bool mui_push_raw_mouse_event(uint32_t sdl_type, uint32_t window_id, uint8_t button, uint32_t state,
                              float x, float y) {
    SDL_Event e;
    SDL_zero(e);
    e.type = sdl_type;
    if (sdl_type == SDL_EVENT_MOUSE_BUTTON_DOWN || sdl_type == SDL_EVENT_MOUSE_BUTTON_UP) {
        e.button.windowID = window_id; e.button.button = button; e.button.clicks = 1;
        e.button.down = sdl_type == SDL_EVENT_MOUSE_BUTTON_DOWN; e.button.x = x; e.button.y = y;
    } else if (sdl_type == SDL_EVENT_MOUSE_MOTION) {
        e.motion.windowID = window_id; e.motion.state = state; e.motion.x = x; e.motion.y = y;
    } else {
        return SDL_SetError("not a mouse event");
    }
    e.common.timestamp = SDL_GetTicksNS();
    return SDL_PushEvent(&e);
}

/* ---- File dialogs (ruling SV-G) ----------------------------------------- */

struct MUIDialogRequest {
    int32_t token;
    bool is_save, allow_many;
    char *default_location;
    SDL_DialogFileFilter *filters;
    int nfilters;
    uint32_t window_id;
};

struct MUIDialogResult {
    int32_t token;
    int32_t status;          // 1 chosen, 0 cancelled, -1 failed
    char **paths;
    int32_t count;
    char *error;
    struct MUIDialogResult *next;
};

static struct MUIDialogResult *dialog_head = NULL, *dialog_tail = NULL;

MUIDialogRequest *mui_dialog_request_new(int32_t token, bool is_save, bool allow_many,
                                         const char *default_location) {
    MUIDialogRequest *r = SDL_calloc(1, sizeof *r);
    if (!r) return NULL;
    r->token = token; r->is_save = is_save; r->allow_many = allow_many;
    r->default_location = default_location ? SDL_strdup(default_location) : NULL;
    return r;
}

bool mui_dialog_request_add_filter(MUIDialogRequest *r, const char *name, const char *pattern) {
    SDL_DialogFileFilter *grown = SDL_realloc(r->filters, sizeof *grown * (size_t)(r->nfilters + 1));
    if (!grown) return false;
    r->filters = grown;
    r->filters[r->nfilters].name = SDL_strdup(name);
    r->filters[r->nfilters].pattern = SDL_strdup(pattern);
    r->nfilters += 1;
    return true;
}

static void free_request(MUIDialogRequest *r) {
    for (int i = 0; i < r->nfilters; i++) {
        SDL_free((void *)r->filters[i].name);
        SDL_free((void *)r->filters[i].pattern);
    }
    SDL_free(r->filters);
    SDL_free(r->default_location);
    SDL_free(r);
}

/* SDL's dialog callback, on whatever thread SDL calls it from: copies the
   answer into the queue, wakes the main thread with MUI_EVENT_DIALOG and
   frees the request (its filters were needed until now). */
static void SDLCALL dialog_callback(void *userdata, const char *const *filelist, int filter) {
    (void)filter;
    MUIDialogRequest *request = userdata;
    struct MUIDialogResult *result = SDL_calloc(1, sizeof *result);
    if (result) {
        result->token = request->token;
        if (!filelist) {
            result->status = -1;
            result->error = SDL_strdup(SDL_GetError());
        } else if (!filelist[0]) {
            result->status = 0;
        } else {
            int32_t count = 0;
            while (filelist[count]) count++;
            result->paths = SDL_calloc((size_t)count, sizeof(char *));
            if (result->paths) {
                for (int32_t i = 0; i < count; i++) result->paths[i] = SDL_strdup(filelist[i]);
                result->count = count;
                result->status = 1;
            } else {
                result->status = -1;
                result->error = SDL_strdup("out of memory copying the chosen paths");
            }
        }
        SDL_LockMutex(dialog_mutex);
        if (dialog_tail) dialog_tail->next = result; else dialog_head = result;
        dialog_tail = result;
        SDL_UnlockMutex(dialog_mutex);
        SDL_Event e;
        SDL_zero(e);
        e.type = dialog_event_type;
        e.user.windowID = request->window_id;
        e.user.code = request->token;
        e.common.timestamp = SDL_GetTicksNS();
        SDL_PushEvent(&e);
    }
    free_request(request);
}

bool mui_dialog_request_show(MUIDialogRequest *r, void *window) {
    r->window_id = window ? SDL_GetWindowID((SDL_Window *)window) : 0;
    const SDL_DialogFileFilter *filters = r->nfilters > 0 ? r->filters : NULL;
    if (r->is_save)
        SDL_ShowSaveFileDialog(dialog_callback, r, (SDL_Window *)window, filters, r->nfilters, r->default_location);
    else
        SDL_ShowOpenFileDialog(dialog_callback, r, (SDL_Window *)window, filters, r->nfilters, r->default_location,
                               r->allow_many);
    return true;
}

MUIDialogResult *mui_take_dialog_result(int32_t token) {
    SDL_LockMutex(dialog_mutex);
    struct MUIDialogResult *previous = NULL, *node = dialog_head;
    while (node && node->token != token) { previous = node; node = node->next; }
    if (node) {
        if (previous) previous->next = node->next; else dialog_head = node->next;
        if (dialog_tail == node) dialog_tail = previous;
        node->next = NULL;
    }
    SDL_UnlockMutex(dialog_mutex);
    return node;
}

int32_t mui_dialog_result_status(const MUIDialogResult *r) { return r->status; }
int32_t mui_dialog_result_count(const MUIDialogResult *r) { return r->count; }
const char *mui_dialog_result_path(const MUIDialogResult *r, int32_t index) {
    return index >= 0 && index < r->count ? r->paths[index] : NULL;
}
const char *mui_dialog_result_error(const MUIDialogResult *r) { return r->error ? r->error : ""; }

void mui_dialog_result_free(MUIDialogResult *r) {
    if (!r) return;
    for (int32_t i = 0; i < r->count; i++) SDL_free(r->paths[i]);
    SDL_free(r->paths);
    SDL_free(r->error);
    SDL_free(r);
}

typedef struct {
    MUIDialogRequest *request;
    char **paths;        // NULL-terminated; NULL itself for a failure
} TestDialogAnswer;

static int SDLCALL test_dialog_thread(void *userdata) {
    TestDialogAnswer *answer = userdata;
    if (!answer->paths) SDL_SetError("test dialog failure");
    dialog_callback(answer->request, (const char *const *)answer->paths, -1);
    if (answer->paths) {
        for (char **p = answer->paths; *p; p++) SDL_free(*p);
        SDL_free(answer->paths);
    }
    SDL_free(answer);
    return 0;
}

bool mui_test_complete_dialog(uint32_t window_id, int32_t token, const char *joined_paths, int32_t count) {
    MUIDialogRequest *request = mui_dialog_request_new(token, false, false, NULL);
    TestDialogAnswer *answer = SDL_calloc(1, sizeof *answer);
    if (!request || !answer) return false;
    request->window_id = window_id;
    answer->request = request;
    if (count >= 0) {
        answer->paths = SDL_calloc((size_t)count + 1, sizeof(char *));
        const char *cursor = joined_paths ? joined_paths : "";
        for (int32_t i = 0; i < count; i++) {
            const char *end = SDL_strchr(cursor, '\n');
            size_t length = end ? (size_t)(end - cursor) : SDL_strlen(cursor);
            answer->paths[i] = SDL_malloc(length + 1);
            SDL_memcpy(answer->paths[i], cursor, length);
            answer->paths[i][length] = '\0';
            cursor = end ? end + 1 : cursor + length;
        }
    }
    SDL_Thread *thread = SDL_CreateThread(test_dialog_thread, "mui test dialog", answer);
    if (!thread) return false;
    SDL_DetachThread(thread);
    return true;
}

/* ---- Window size limits (ruling SV-M) ------------------------------------ */

// Independent of the order the limits change in (ruling `SV-AG` item 1): SDL
// refuses a minimum above the maximum still set and a maximum below the
// minimum still set, so the maximum is lifted first, the minimum set, then the
// new maximum. The caller sends a maximum no smaller than its minimum.
bool mui_window_set_size_limits(void *w, int32_t min_w, int32_t min_h, int32_t max_w, int32_t max_h) {
    SDL_Window *window = (SDL_Window *)w;
    bool lifted = SDL_SetWindowMaximumSize(window, 0, 0);
    bool ok = SDL_SetWindowMinimumSize(window, min_w, min_h);
    return SDL_SetWindowMaximumSize(window, max_w, max_h) && ok && lifted;
}

void mui_window_size_limits(void *w, int32_t *min_w, int32_t *min_h, int32_t *max_w, int32_t *max_h) {
    int a = 0, b = 0, c = 0, d = 0;
    SDL_GetWindowMinimumSize((SDL_Window *)w, &a, &b);
    SDL_GetWindowMaximumSize((SDL_Window *)w, &c, &d);
    *min_w = a; *min_h = b; *max_w = c; *max_h = d;
}

/* ---- Window chrome (item S1, rulings CW-B, CW-E, CW-G, CW-H, CW-O) -------- */

bool mui_window_set_bordered(void *w, bool bordered) {
    SDL_Window *window = (SDL_Window *)w;
    if (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) return false;   // CW-S: the platform defers
    if (!SDL_SetWindowBordered(window, bordered)) return false;
    // SDL answers true even where the driver has no SetWindowBordered (the offscreen one) and the
    // flag never moves: the answer is what happened, not what SDL said.
    return ((SDL_GetWindowFlags(window) & SDL_WINDOW_BORDERLESS) != 0) == !bordered;
}
bool mui_window_is_borderless(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_BORDERLESS) != 0;
}
bool mui_window_set_size(void *w, int32_t width, int32_t height) { return SDL_SetWindowSize((SDL_Window *)w, width, height); }
bool mui_window_minimize(void *w) { return SDL_MinimizeWindow((SDL_Window *)w); }
bool mui_window_maximize(void *w) { return SDL_MaximizeWindow((SDL_Window *)w); }
bool mui_window_restore(void *w) { return SDL_RestoreWindow((SDL_Window *)w); }
bool mui_window_is_maximized(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_MAXIMIZED) != 0;
}
bool mui_window_is_minimized(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_MINIMIZED) != 0;
}
bool mui_window_is_fullscreen(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_FULLSCREEN) != 0;
}

#define MUI_CHROME_BORDER 6.0f

void mui_chrome_snapshot_init(MUIChromeSnapshot *s, float width, float height, bool borderless,
                              bool zoomed_or_fullscreen, bool resizable_h, bool resizable_v) {
    memset(s, 0, sizeof(*s));
    s->width = width; s->height = height;
    s->borderless = borderless; s->zoomed_or_fullscreen = zoomed_or_fullscreen;
    s->resizable_h = resizable_h; s->resizable_v = resizable_v;
}

bool mui_chrome_snapshot_add_rect(MUIChromeSnapshot *s, float x, float y, float w, float h) {
    if (s->count >= MUI_CHROME_MAX_RECTS) return false;
    s->rects[s->count++] = (MUIChromeRect){ x, y, w, h };
    return true;
}

float mui_chrome_resize_border(void) { return MUI_CHROME_BORDER; }
int32_t mui_chrome_max_rects(void) { return MUI_CHROME_MAX_RECTS; }

/* The C twin of Swift's ChromeHitSnapshot.hit(at:): the order is corner, edge, drag rect, normal,
   every comparison half-open on the max side. */
int32_t mui_chrome_hit(const MUIChromeSnapshot *s, float x, float y) {
    if (!(x >= 0 && y >= 0 && x < s->width && y < s->height)) return MUI_CHROME_HIT_NORMAL;
    if (s->borderless && !s->zoomed_or_fullscreen) {
        float edge = MUI_CHROME_BORDER, corner = 2 * MUI_CHROME_BORDER;
        bool left = s->resizable_h && x < edge, right = s->resizable_h && x >= s->width - edge;
        bool top = s->resizable_v && y < edge, bottom = s->resizable_v && y >= s->height - edge;
        if (s->resizable_h && s->resizable_v) {
            bool near_left = x < corner, near_right = x >= s->width - corner;
            bool near_top = y < corner, near_bottom = y >= s->height - corner;
            if (near_top && near_left) return MUI_CHROME_HIT_TOP_LEFT;
            if (near_top && near_right) return MUI_CHROME_HIT_TOP_RIGHT;
            if (near_bottom && near_left) return MUI_CHROME_HIT_BOTTOM_LEFT;
            if (near_bottom && near_right) return MUI_CHROME_HIT_BOTTOM_RIGHT;
        }
        if (top) return MUI_CHROME_HIT_TOP;
        if (bottom) return MUI_CHROME_HIT_BOTTOM;
        if (left) return MUI_CHROME_HIT_LEFT;
        if (right) return MUI_CHROME_HIT_RIGHT;
    }
    for (int32_t i = 0; i < s->count; i++) {
        const MUIChromeRect *r = &s->rects[i];
        if (x >= r->x && y >= r->y && x < r->x + r->w && y < r->y + r->h) return MUI_CHROME_HIT_DRAGGABLE;
    }
    return MUI_CHROME_HIT_NORMAL;
}

/* One per window, in the window's properties so it is freed with the window. The lock guards
   `snapshot` and the counters; neither side takes another lock while holding it (CW-H). */
typedef struct {
    SDL_Mutex *mutex;
    MUIChromeSnapshot snapshot;
    bool installed;
    uint32_t publishes, copies, lock_pairs;
} ChromeState;

static const char *chrome_property = "metalui.chrome";

static void chrome_state_free(void *userdata, void *value) {
    (void)userdata;
    ChromeState *state = (ChromeState *)value;
    if (!state) return;
    SDL_DestroyMutex(state->mutex);
    free(state);
}

static ChromeState *chrome_state(SDL_Window *window, bool create) {
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    ChromeState *state = (ChromeState *)SDL_GetPointerProperty(props, chrome_property, NULL);
    if (state || !create) return state;
    state = (ChromeState *)calloc(1, sizeof(ChromeState));
    if (!state) return NULL;
    state->mutex = SDL_CreateMutex();
    if (!state->mutex) { free(state); return NULL; }
    if (!SDL_SetPointerPropertyWithCleanup(props, chrome_property, state, chrome_state_free, NULL)) {
        return NULL;   // SDL has already run the cleanup on failure
    }
    return state;
}

/* The only lock/unlock pair in the chrome path; the counter moves inside it (CW-O). */
static void chrome_lock(ChromeState *state) { SDL_LockMutex(state->mutex); state->lock_pairs++; }
static void chrome_unlock(ChromeState *state) { SDL_UnlockMutex(state->mutex); }

static int32_t chrome_locked_hit(ChromeState *state, float x, float y) {
    MUIChromeSnapshot copy;
    chrome_lock(state);
    memcpy(&copy, &state->snapshot, sizeof(copy));
    state->copies++;
    chrome_unlock(state);
    return mui_chrome_hit(&copy, x, y);
}

int32_t mui_window_chrome_hit(void *w, float x, float y) {
    ChromeState *state = chrome_state((SDL_Window *)w, false);
    return state ? chrome_locked_hit(state, x, y) : MUI_CHROME_HIT_NORMAL;
}

static SDL_HitTestResult chrome_hit_callback(SDL_Window *window, const SDL_Point *area, void *data) {
    (void)window;
    switch (chrome_locked_hit((ChromeState *)data, (float)area->x, (float)area->y)) {
    case MUI_CHROME_HIT_DRAGGABLE: return SDL_HITTEST_DRAGGABLE;
    case MUI_CHROME_HIT_TOP_LEFT: return SDL_HITTEST_RESIZE_TOPLEFT;
    case MUI_CHROME_HIT_TOP: return SDL_HITTEST_RESIZE_TOP;
    case MUI_CHROME_HIT_TOP_RIGHT: return SDL_HITTEST_RESIZE_TOPRIGHT;
    case MUI_CHROME_HIT_RIGHT: return SDL_HITTEST_RESIZE_RIGHT;
    case MUI_CHROME_HIT_BOTTOM_RIGHT: return SDL_HITTEST_RESIZE_BOTTOMRIGHT;
    case MUI_CHROME_HIT_BOTTOM: return SDL_HITTEST_RESIZE_BOTTOM;
    case MUI_CHROME_HIT_BOTTOM_LEFT: return SDL_HITTEST_RESIZE_BOTTOMLEFT;
    case MUI_CHROME_HIT_LEFT: return SDL_HITTEST_RESIZE_LEFT;
    default: return SDL_HITTEST_NORMAL;
    }
}

bool mui_window_set_hit_test(void *w, const MUIChromeSnapshot *snapshot) {
    SDL_Window *window = (SDL_Window *)w;
    if (!snapshot) {
        ChromeState *state = chrome_state(window, false);
        if (!state || !state->installed) return true;
        if (!SDL_SetWindowHitTest(window, NULL, NULL)) return false;
        state->installed = false;
        chrome_lock(state);   // a cleared window answers normal everywhere
        memset(&state->snapshot, 0, sizeof(state->snapshot));
        chrome_unlock(state);
        return true;
    }
    ChromeState *state = chrome_state(window, true);
    if (!state) return false;
    chrome_lock(state);
    memcpy(&state->snapshot, snapshot, sizeof(*snapshot));
    state->publishes++;
    chrome_unlock(state);
    if (!state->installed) {
        if (!SDL_SetWindowHitTest(window, chrome_hit_callback, state)) return false;
        state->installed = true;
    }
    return true;
}

bool mui_window_hit_test_installed(void *w) {
    ChromeState *state = chrome_state((SDL_Window *)w, false);
    return state && state->installed;
}

void mui_window_chrome_counters(void *w, uint32_t *publishes, uint32_t *copies, uint32_t *lock_pairs) {
    ChromeState *state = chrome_state((SDL_Window *)w, false);
    *publishes = state ? state->publishes : 0;
    *copies = state ? state->copies : 0;
    *lock_pairs = state ? state->lock_pairs : 0;
}

const char *mui_current_video_driver(void) {
    const char *driver = SDL_GetCurrentVideoDriver();
    return driver ? driver : "";
}

bool mui_window_has_input_focus(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_INPUT_FOCUS) != 0;
}

void *mui_window_create(const char *title, int32_t w, int32_t h, bool hidden) {
    SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (hidden) flags |= SDL_WINDOW_HIDDEN;
    return SDL_CreateWindow(title, w, h, flags);
}
void mui_window_destroy(void *w) {
    SDL_SetWindowHitTest((SDL_Window *)w, NULL, NULL);   // before the state it points at is freed (CW-H)
    SDL_DestroyWindow((SDL_Window *)w);
}
uint32_t mui_window_id(void *w) { return SDL_GetWindowID((SDL_Window *)w); }
void mui_window_size(void *w, int32_t *width, int32_t *height) { SDL_GetWindowSize((SDL_Window *)w, width, height); }
bool mui_window_set_title(void *w, const char *t) { return SDL_SetWindowTitle((SDL_Window *)w, t); }
const char *mui_window_title(void *w) { return SDL_GetWindowTitle((SDL_Window *)w); }
bool mui_window_show(void *w) { return SDL_ShowWindow((SDL_Window *)w); }
bool mui_window_hide(void *w) { return SDL_HideWindow((SDL_Window *)w); }
const char *mui_quit_on_last_window_close_hint(void) { return SDL_GetHint(SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE); }
bool mui_window_is_shown(void *w) {
    return (SDL_GetWindowFlags((SDL_Window *)w) & SDL_WINDOW_HIDDEN) == 0;
}
bool mui_window_id_is_open(uint32_t id) { return SDL_GetWindowFromID((SDL_WindowID)id) != NULL; }
bool mui_window_start_text_input(void *w, int32_t x, int32_t y, int32_t width, int32_t height) {
    SDL_Rect area = { x, y, width, height };
    if (!SDL_SetTextInputArea((SDL_Window *)w, &area, 0)) return false;
    return SDL_TextInputActive((SDL_Window *)w) || SDL_StartTextInput((SDL_Window *)w);
}
bool mui_window_stop_text_input(void *w) { return SDL_StopTextInput((SDL_Window *)w); }
char *mui_clipboard_text(void) {
    if (!SDL_HasClipboardText()) return NULL;
    return SDL_GetClipboardText();
}
bool mui_set_clipboard_text(const char *text) { return SDL_SetClipboardText(text); }
void mui_free(void *memory) { SDL_free(memory); }

/* ---- The typed clipboard (rulings CB-H, CB-I) ------------------------------
 * One malloc'd box holds every representation (mime, bytes), copied at set time.
 * SDL calls the data callback on whichever thread asks (the caller's for our own
 * data, the event-pumping thread for a remote request), so the callback is pure:
 * a lookup by mime returning a pointer into the box. No Swift closure, no actor
 * hop, no allocation. The cleanup callback frees the box exactly once. */
typedef struct {
    char *mime;
    const uint8_t *bytes;
    size_t size;
} MUIClipboardEntry;

typedef struct {
    size_t count;
    MUIClipboardEntry entries[];
} MUIClipboardBox;

static SDL_AtomicInt mui_clipboard_cleanups;
static SDL_AtomicInt mui_clipboard_live;

static const void *mui_clipboard_data(void *userdata, const char *mime, size_t *size) {
    const MUIClipboardBox *box = (const MUIClipboardBox *)userdata;
    *size = 0;
    if (!box || !mime) return NULL;
    for (size_t i = 0; i < box->count; i++) {
        if (strcmp(box->entries[i].mime, mime) == 0) {
            *size = box->entries[i].size;
            return box->entries[i].bytes;
        }
    }
    return NULL;
}

static void mui_clipboard_cleanup(void *userdata) {
    if (!userdata) return;
    SDL_AddAtomicInt(&mui_clipboard_cleanups, 1);
    SDL_AddAtomicInt(&mui_clipboard_live, -1);
    free(userdata);
}

bool mui_clipboard_set(const char *const *mimes, const uint8_t *const *bytes,
                       const size_t *sizes, size_t count) {
    if (count == 0) return false;
    size_t total = sizeof(MUIClipboardBox) + count * sizeof(MUIClipboardEntry);
    for (size_t i = 0; i < count; i++) total += strlen(mimes[i]) + 1 + sizes[i];
    MUIClipboardBox *box = (MUIClipboardBox *)malloc(total);
    if (!box) return false;
    box->count = count;
    uint8_t *cursor = (uint8_t *)box + sizeof(MUIClipboardBox) + count * sizeof(MUIClipboardEntry);
    const char **names = (const char **)malloc(count * sizeof(char *));
    if (!names) { free(box); return false; }
    for (size_t i = 0; i < count; i++) {
        size_t n = strlen(mimes[i]) + 1;
        memcpy(cursor, mimes[i], n);
        box->entries[i].mime = (char *)cursor;
        names[i] = (const char *)cursor;
        cursor += n;
        if (sizes[i] > 0) memcpy(cursor, bytes[i], sizes[i]);
        box->entries[i].bytes = cursor;
        box->entries[i].size = sizes[i];
        cursor += sizes[i];
    }
    SDL_AddAtomicInt(&mui_clipboard_live, 1);
    bool ok = SDL_SetClipboardData(mui_clipboard_data, mui_clipboard_cleanup, box, names, count);
    free(names); /* SDL copies the mime list */
    /* A failed set may or may not have stored the box (a late platform failure
     * leaves it stored): clearing makes SDL run the cleanup if it holds it, and
     * only SDL ever frees the box, so it is freed exactly once either way. */
    if (!ok) SDL_ClearClipboardData();
    return ok;
}

char **mui_clipboard_mime_types(size_t *count) {
    *count = 0;
    return SDL_GetClipboardMimeTypes(count);
}

void *mui_clipboard_get(const char *mime, size_t *size) {
    *size = 0;
    if (!SDL_HasClipboardData(mime)) return NULL;
    return SDL_GetClipboardData(mime, size);
}

bool mui_clipboard_has(const char *mime) { return SDL_HasClipboardData(mime); }
void mui_clipboard_clear(void) { SDL_ClearClipboardData(); }
int32_t mui_clipboard_cleanup_count(void) { return SDL_GetAtomicInt(&mui_clipboard_cleanups); }
int32_t mui_clipboard_live_count(void) { return SDL_GetAtomicInt(&mui_clipboard_live); }
/* Test hook (CB-H, test 4.2): calls the data callback of this process's own
 * clipboard through the pure path, on the calling thread, without SDL. Returns
 * the number of bytes the callback reports for `mime`. */
size_t mui_clipboard_callback_probe(const char *mime) {
    size_t n = 0;
    void *p = mui_clipboard_get(mime, &n);
    if (p) SDL_free(p);
    return n;
}
void mui_window_position(void *w, int32_t *x, int32_t *y) { SDL_GetWindowPosition((SDL_Window *)w, x, y); }
void *mui_window_native_handle(void *w) {
    SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window *)w);
#if defined(__APPLE__)
    return SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
#elif defined(_WIN32)
    return SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
#else
    (void)props;
    return NULL;
#endif
}
int32_t mui_system_theme(void) { return SDL_GetSystemTheme() == SDL_SYSTEM_THEME_DARK ? 1 : 0; }
double mui_now(void) { return (double)SDL_GetTicksNS() / 1e9; }

// ---- Image cursors (rulings IC-E, IC-O) ------------------------------------
//
// The recorders are written in the production path, so a test that cannot see
// the pointer reads what the bridge was asked for. A refused creation (the
// offscreen driver may refuse) still records its attempt.

static uint32_t cursor_attempts = 0, cursor_created = 0, cursor_destroyed = 0, cursor_sets = 0;
static int32_t cursor_last_w = 0, cursor_last_h = 0, cursor_last_hot_x = 0, cursor_last_hot_y = 0;
static int32_t cursor_last_alternates = 0;
static uint8_t *cursor_last_pixels = NULL;
static size_t cursor_last_pixel_bytes = 0;

void *mui_cursor_create(void *surface, int32_t hot_x, int32_t hot_y) {
    SDL_Surface *s = (SDL_Surface *)surface;
    if (!s) { SDL_SetError("cursor: NULL surface"); return NULL; }
    cursor_attempts++;
    cursor_last_w = s->w; cursor_last_h = s->h;
    cursor_last_hot_x = hot_x; cursor_last_hot_y = hot_y;
    int count = 0;
    SDL_Surface **images = SDL_GetSurfaceImages(s, &count);
    cursor_last_alternates = images && count > 0 ? count - 1 : 0;   // the list includes the surface itself
    if (images) SDL_free(images);
    size_t bytes = (size_t)s->w * (size_t)s->h * 4;
    uint8_t *copy = (uint8_t *)SDL_realloc(cursor_last_pixels, bytes);
    if (copy) {
        cursor_last_pixels = copy; cursor_last_pixel_bytes = bytes;
        for (int32_t y = 0; y < s->h; y++)
            memcpy(copy + (size_t)y * (size_t)s->w * 4,
                   (const uint8_t *)s->pixels + (size_t)y * (size_t)s->pitch, (size_t)s->w * 4);
    }
    SDL_Cursor *cursor = SDL_CreateColorCursor(s, hot_x, hot_y);
    if (cursor) cursor_created++;
    return cursor;
}

void mui_cursor_destroy(void *cursor) {
    if (!cursor) return;
    SDL_DestroyCursor((SDL_Cursor *)cursor);
    cursor_destroyed++;
}

bool mui_cursor_set(void *cursor) {
    if (!cursor) return false;
    cursor_sets++;
    return SDL_SetCursor((SDL_Cursor *)cursor);
}

uint32_t mui_cursor_attempt_count(void) { return cursor_attempts; }
uint32_t mui_cursor_created_count(void) { return cursor_created; }
uint32_t mui_cursor_destroyed_count(void) { return cursor_destroyed; }
uint32_t mui_cursor_live_count(void) { return cursor_created - cursor_destroyed; }
uint32_t mui_cursor_set_count(void) { return cursor_sets; }
int32_t mui_cursor_last_width(void) { return cursor_last_w; }
int32_t mui_cursor_last_height(void) { return cursor_last_h; }
int32_t mui_cursor_last_hot_x(void) { return cursor_last_hot_x; }
int32_t mui_cursor_last_hot_y(void) { return cursor_last_hot_y; }
int32_t mui_cursor_last_alternate_count(void) { return cursor_last_alternates; }

uint32_t mui_cursor_last_pixel(int32_t index) {
    if (index < 0 || (size_t)index * 4 + 4 > cursor_last_pixel_bytes) return 0;
    const uint8_t *p = cursor_last_pixels + (size_t)index * 4;
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

// ---- The application icon (ruling AI-F) ------------------------------------

const uint32_t MUI_PIXELFORMAT_RGBA32 = SDL_PIXELFORMAT_RGBA32;

void *mui_icon_surface_create(int32_t w, int32_t h, const uint8_t *straight_rgba) {
    if (w <= 0 || h <= 0 || !straight_rgba) { SDL_SetError("icon: bad size or no bytes"); return NULL; }
    SDL_Surface *s = SDL_CreateSurface(w, h, SDL_PIXELFORMAT_RGBA32);
    if (!s) return NULL;
    for (int32_t y = 0; y < h; y++)
        memcpy((uint8_t *)s->pixels + (size_t)y * (size_t)s->pitch,
               straight_rgba + (size_t)y * (size_t)w * 4, (size_t)w * 4);
    return s;
}

bool mui_icon_surface_add_alternate(void *primary, void *image) {
    return SDL_AddSurfaceAlternateImage((SDL_Surface *)primary, (SDL_Surface *)image);
}

static uint32_t window_set_icon_null_calls = 0;

bool mui_window_set_icon(void *window, void *surface) {
    if (!surface) { window_set_icon_null_calls++; return SDL_SetError("icon: NULL surface"); }
    return SDL_SetWindowIcon((SDL_Window *)window, (SDL_Surface *)surface);
}

uint32_t mui_window_set_icon_null_calls(void) { return window_set_icon_null_calls; }

void mui_surface_destroy(void *surface) { SDL_DestroySurface((SDL_Surface *)surface); }

uint32_t mui_surface_format(void *surface) { return (uint32_t)((SDL_Surface *)surface)->format; }

void mui_surface_size(void *surface, int32_t *w, int32_t *h) {
    *w = ((SDL_Surface *)surface)->w; *h = ((SDL_Surface *)surface)->h;
}

bool mui_surface_read_rgba(void *surface, uint8_t *out, int32_t capacity) {
    SDL_Surface *s = (SDL_Surface *)surface;
    if ((int64_t)capacity < (int64_t)s->w * s->h * 4) return SDL_SetError("icon: readback buffer short");
    for (int32_t y = 0; y < s->h; y++)
        memcpy(out + (size_t)y * (size_t)s->w * 4,
               (const uint8_t *)s->pixels + (size_t)y * (size_t)s->pitch, (size_t)s->w * 4);
    return true;
}

int32_t mui_surface_image_count(void *surface) {
    int count = 0;
    SDL_Surface **images = SDL_GetSurfaceImages((SDL_Surface *)surface, &count);
    if (!images) return 0;
    SDL_free(images);
    return count;
}

void mui_surface_image_size(void *surface, int32_t index, int32_t *w, int32_t *h) {
    *w = 0; *h = 0;
    int count = 0;
    SDL_Surface **images = SDL_GetSurfaceImages((SDL_Surface *)surface, &count);
    if (!images) return;
    if (index >= 0 && index < count) { *w = images[index]->w; *h = images[index]->h; }
    SDL_free(images);
}

uint32_t mui_app_id_set_count(void) { return app_id_sets; }
const char *mui_app_id_last(void) { return app_id_last; }
const char *mui_app_id_hint_seen_at_init(void) { return app_id_seen_at_init; }
bool mui_app_id_hint_precedes_init(void) {
    return app_id_hint_seq != 0 && app_id_hint_seq < app_id_init_seq;
}

#else
/* Built without the `SDL` trait: no SDL3 header, no SDL3 link. */
int mui_bridge_built_without_sdl = 1;
#endif
