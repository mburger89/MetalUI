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
    SDL_GPUSampler *sampler;
    SDL_GPUTexture *target;
    uint32_t width, height;
    const char *shader_dir;
    SDL_GPUShaderFormat format;
    bool portable;
};

const char *replay_error(void) { return SDL_GetError(); }
const char *replay_driver(ReplayGPU *g) { return SDL_GetGPUDeviceDriver(g->device); }

enum { KIND_RECT = 0, KIND_GLYPH = 1, KIND_IMAGE = 2 };
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

/* Every record a run draws names a transform the table holds (the shaders
   read record i − 1 for index i, ruling GX-F), checked once, as images_valid
   checks textures. A scene, or a recorded fixture, can never name one past
   the table; anything else is refused rather than read out of bounds. */
static bool transforms_valid(const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
                             const void *images, uint32_t ib, uint32_t tb,
                             const ReplayRun *runs, uint32_t count) {
    uint32_t table = tb / TRANSFORM_STRIDE;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *base; uint32_t stride, offset, shift, bytes;
        if (runs[i].kind == KIND_RECT) { base = rects; stride = RECT_STRIDE; offset = RECT_SHAPE_OFFSET; shift = 8; bytes = rb; }
        else if (runs[i].kind == KIND_GLYPH) { base = glyphs; stride = GLYPH_STRIDE; offset = GLYPH_TRANSFORM_OFFSET; shift = 0; bytes = gb; }
        else { base = images; stride = IMAGE_STRIDE; offset = IMAGE_FILTER_OFFSET; shift = 8; bytes = ib; }
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

static SDL_GPUShader *shader(ReplayGPU *g, const char *source, const char *entry,
                            bool fragment, int kind) {
    void *loaded = NULL;
    size_t size = source ? strlen(source) : 0;
    if (g->portable) {
        const char *extension = g->format == SDL_GPU_SHADERFORMAT_MSL ? "msl" :
            g->format == SDL_GPU_SHADERFORMAT_SPIRV ? "spv" : "dxil";
        char path[4096];
        int length = snprintf(path, sizeof(path), "%s/%s.%s.%s", g->shader_dir,
            kind_names[kind], fragment ? "fragment" : "vertex", extension);
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
        /* Records, then the transform table (ruling GX-F); the vertex stage
           also reads the unit quad first. */
        .num_storage_buffers = fragment ? 2 : 3,
        .num_uniform_buffers = fragment ? 0 : 2,
        .num_samplers = fragment && kind != KIND_RECT ? 1 : 0
    };
    SDL_GPUShader *result = SDL_CreateGPUShader(g->device, &info);
    SDL_free(loaded);
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
    SDL_GPUColorTargetDescription target = {
        .format = SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
        .blend_state = {
            .src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
            .enable_blend = true
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
    g->shader_dir = directory; // borrowed only while this function builds pipelines
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
    g->shader_dir = NULL;
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
        if (g->rect) SDL_ReleaseGPUGraphicsPipeline(g->device, g->rect);
        if (g->glyph) SDL_ReleaseGPUGraphicsPipeline(g->device, g->glyph);
        if (g->image) SDL_ReleaseGPUGraphicsPipeline(g->device, g->image);
        SDL_DestroyGPUDevice(g->device);
    }
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

bool replay_render(ReplayGPU *g, uint32_t w, uint32_t h,
    const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
    const void *images, uint32_t ib, const void *transforms, uint32_t tb,
    const ReplayTexture *textures, uint32_t texture_count,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah,
    const float *projection, uint8_t *out) {
    // Diagnostic harness only: bounded fixtures, one completed frame at a time.
    if (!w || !h || w > 4096 || h > 4096 || !aw || !ah || aw > 4096 || ah > 4096)
        return SDL_SetError("invalid fixture dimensions");
    if (!images_valid(images, ib, texture_count, runs, count)) return false;
    if (tb % TRANSFORM_STRIDE) return SDL_SetError("unexpected MetalUI transform ABI");
    if (!transforms_valid(rects, rb, glyphs, gb, images, ib, tb, runs, count)) return false;
    for (uint32_t t = 0; t < texture_count; t++)
        if (!textures[t].width || !textures[t].height || textures[t].width > 4096 || textures[t].height > 4096)
            return SDL_SetError("invalid image texture dimensions");
    SDL_GPUBuffer *buffers[5] = {0};
    SDL_GPUTransferBuffer *uploads[6] = {0}, *download = NULL;
    SDL_GPUTexture *atlas_texture = NULL;
    SDL_GPUTexture **image_textures = NULL;
    SDL_GPUTransferBuffer **image_uploads = NULL;
    SDL_GPUCommandBuffer *cmd = NULL;
    SDL_GPUFence *fence = NULL;
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
    const void *data[] = {quad, rects, glyphs, images, tb ? transforms : empty_transform};
    uint32_t sizes[] = {sizeof(quad), rb, gb, ib, tb ? tb : TRANSFORM_STRIDE};
    if (g->portable) {
        // The existing CPU ABI is scalar-packed (120/88 bytes). SDL storage
        // uses 16-byte lanes, so round each record up, never reinterpret it.
        // Images (64 bytes) are already four whole lanes.
        const uint32_t old_stride[] = {120, 88}, new_stride[] = {128, 96};
        data[0] = aligned_quad; sizes[0] = sizeof(aligned_quad);
        for (int i = 0; i < 2; i++) {
            if (sizes[i + 1] % old_stride[i]) { SDL_SetError("unexpected MetalUI primitive ABI"); goto cleanup; }
            uint32_t records = sizes[i + 1] / old_stride[i];
            if (!records) continue;
            packed[i] = calloc(records, new_stride[i]);
            if (!packed[i]) { SDL_SetError("packing allocation failed"); goto cleanup; }
            for (uint32_t j = 0; j < records; j++)
                memcpy((uint8_t *)packed[i] + j * new_stride[i],
                       (const uint8_t *)data[i + 1] + j * old_stride[i], old_stride[i]);
            data[i + 1] = packed[i]; sizes[i + 1] = records * new_stride[i];
        }
    }
    for (int i = 0; i < 5; i++) {
        if (!sizes[i]) continue;
        SDL_GPUBufferCreateInfo info = {
            .usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, .size = sizes[i]
        };
        buffers[i] = SDL_CreateGPUBuffer(g->device, &info);
        uploads[i] = transfer(g, sizes[i], false, data[i]);
        if (!buffers[i] || !uploads[i]) goto cleanup;
    }
    uploads[5] = transfer(g, aw * ah, false, atlas);
    // 256-byte pitch also works for a future D3D readback path.
    uint32_t pitch = (w * 4 + 255) & ~255u;
    download = transfer(g, pitch * h, true, NULL);
    if (!uploads[5] || !download) goto cleanup;
    cmd = SDL_AcquireGPUCommandBuffer(g->device);
    if (!cmd) goto cleanup;
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < 5; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[5] };
    SDL_GPUTextureRegion atlas_dst = { .texture = atlas_texture, .w = aw, .h = ah, .d = 1 };
    SDL_UploadToGPUTexture(copy, &atlas_src, &atlas_dst, false);
    for (uint32_t t = 0; t < texture_count; t++) {
        SDL_GPUTextureTransferInfo image_src = { .transfer_buffer = image_uploads[t] };
        SDL_GPUTextureRegion image_dst = { .texture = image_textures[t], .w = textures[t].width, .h = textures[t].height, .d = 1 };
        SDL_UploadToGPUTexture(copy, &image_src, &image_dst, false);
    }
    SDL_EndGPUCopyPass(copy);
    struct { float width, height; uint32_t first_instance, padding; } viewport = {(float)w, (float)h, 0, 0};
    SDL_PushGPUVertexUniformData(cmd, 1, projection, sizeof(float) * 16);
    SDL_GPUColorTargetInfo target = {
        .texture = g->target, .load_op = SDL_GPU_LOADOP_CLEAR, .store_op = SDL_GPU_STOREOP_STORE
    };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass(cmd, &target, 1, NULL);
    if (!pass) goto cleanup;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t kind = runs[i].kind;
        SDL_GPUBuffer *primitives = buffers[kind == KIND_GLYPH ? 2 : kind == KIND_IMAGE ? 3 : 1];
        SDL_GPUBuffer *vertex_buffers[] = {buffers[0], primitives, buffers[4]};
        SDL_GPUBuffer *fragment_buffers[] = {primitives, buffers[4]};
        SDL_BindGPUGraphicsPipeline(pass, kind == KIND_GLYPH ? g->glyph : kind == KIND_IMAGE ? g->image : g->rect);
        SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 3);
        SDL_BindGPUFragmentStorageBuffers(pass, 0, fragment_buffers, 2);
        if (kind == KIND_GLYPH) {
            SDL_GPUTextureSamplerBinding binding = {atlas_texture, g->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        } else if (kind == KIND_IMAGE) {
            SDL_GPUTextureSamplerBinding binding = {image_textures[image_texture(images, runs[i].start)], g->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        }
        // SDL explicitly warns built-in instance IDs differ across APIs when
        // first_instance is nonzero. Supply the base through a uniform instead.
        viewport.first_instance = runs[i].start;
        SDL_PushGPUVertexUniformData(cmd, 0, &viewport, sizeof(viewport));
        SDL_DrawGPUPrimitives(pass, 4, runs[i].count, 0, 0);
    }
    SDL_EndGPURenderPass(pass);
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
    for (int i = 0; i < 5; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(g->device, buffers[i]);
    for (int i = 0; i < 6; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(g->device, uploads[i]);
    for (uint32_t t = 0; t < texture_count && image_textures; t++) {
        if (image_textures[t]) SDL_ReleaseGPUTexture(g->device, image_textures[t]);
        if (image_uploads && image_uploads[t]) SDL_ReleaseGPUTransferBuffer(g->device, image_uploads[t]);
    }
    SDL_free(image_textures); SDL_free(image_uploads);
    if (download) SDL_ReleaseGPUTransferBuffer(g->device, download);
    if (atlas_texture) SDL_ReleaseGPUTexture(g->device, atlas_texture);
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
    uint32_t submissions;           /* every SDL_Submit… below (MV-L item 4) */
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
    void *const *textures, uint32_t texture_count,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah, bool atlas_dirty,
    const float *projection) {
    if (!r->cmd) return SDL_SetError("finish without a successful begin");
    SDL_GPUDevice *d = r->gpu->device;
    SDL_GPUCommandBuffer *cmd = r->cmd;
    r->cmd = NULL;
    SDL_GPUBuffer *buffers[5] = {0};
    SDL_GPUTransferBuffer *uploads[6] = {0};
    void *packed[2] = {0};
    bool ok = false;
    if (!images_valid(images, ib, texture_count, runs, count)) goto cleanup;
    if (tb % TRANSFORM_STRIDE) { SDL_SetError("unexpected MetalUI transform ABI"); goto cleanup; }
    if (!transforms_valid(rects, rb, glyphs, gb, images, ib, tb, runs, count)) goto cleanup;

    /* The CPU ABI is scalar-packed (120/88 bytes); SDL storage buffers use
       16-byte lanes, so each record is copied into a 128/96-byte slot. An
       image (64 bytes) is already four whole lanes. */
    const float aligned_quad[] = {0,0,0,0, 1,0,0,0, 0,1,0,0, 1,1,0,0};
    const void *data[] = {aligned_quad, rects, glyphs, images, tb ? transforms : empty_transform};
    uint32_t sizes[] = {sizeof(aligned_quad), rb, gb, ib, tb ? tb : TRANSFORM_STRIDE};
    const uint32_t old_stride[] = {120, 88}, new_stride[] = {128, 96};
    for (int i = 0; i < 2; i++) {
        if (sizes[i + 1] % old_stride[i]) { SDL_SetError("unexpected MetalUI primitive ABI"); goto cleanup; }
        uint32_t records = sizes[i + 1] / old_stride[i];
        if (!records) continue;
        packed[i] = calloc(records, new_stride[i]);
        if (!packed[i]) { SDL_SetError("packing allocation failed"); goto cleanup; }
        for (uint32_t j = 0; j < records; j++)
            memcpy((uint8_t *)packed[i] + j * new_stride[i],
                   (const uint8_t *)data[i + 1] + j * old_stride[i], old_stride[i]);
        data[i + 1] = packed[i]; sizes[i + 1] = records * new_stride[i];
    }
    for (int i = 0; i < 5; i++) {
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
    if (atlas_new || atlas_dirty) {
        uploads[5] = transfer(r->gpu, aw * ah, false, atlas);
        if (!uploads[5]) goto cleanup;
    }
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < 5; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    if (uploads[5]) {
        SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[5] };
        SDL_GPUTextureRegion atlas_dst = { .texture = r->atlas, .w = aw, .h = ah, .d = 1 };
        SDL_UploadToGPUTexture(copy, &atlas_src, &atlas_dst, false);
    }
    SDL_EndGPUCopyPass(copy);

    struct { float width, height; uint32_t first_instance, padding; } viewport = {(float)r->width, (float)r->height, 0, 0};
    SDL_PushGPUVertexUniformData(cmd, 1, projection, sizeof(float) * 16);
    SDL_GPUColorTargetInfo target = {
        .texture = r->target, .load_op = SDL_GPU_LOADOP_CLEAR, .store_op = SDL_GPU_STOREOP_STORE
    };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass(cmd, &target, 1, NULL);
    if (!pass) goto cleanup;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t kind = runs[i].kind;
        SDL_GPUBuffer *primitives = buffers[kind == KIND_GLYPH ? 2 : kind == KIND_IMAGE ? 3 : 1];
        if (!primitives) continue;
        SDL_GPUBuffer *vertex_buffers[] = {buffers[0], primitives, buffers[4]};
        SDL_GPUBuffer *fragment_buffers[] = {primitives, buffers[4]};
        SDL_BindGPUGraphicsPipeline(pass, kind == KIND_GLYPH ? r->gpu->glyph : kind == KIND_IMAGE ? r->gpu->image : r->gpu->rect);
        SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 3);
        SDL_BindGPUFragmentStorageBuffers(pass, 0, fragment_buffers, 2);
        if (kind == KIND_GLYPH) {
            SDL_GPUTextureSamplerBinding binding = {r->atlas, r->gpu->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        } else if (kind == KIND_IMAGE) {
            SDL_GPUTextureSamplerBinding binding = {(SDL_GPUTexture *)textures[image_texture(images, runs[i].start)], r->gpu->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        }
        viewport.first_instance = runs[i].start;
        SDL_PushGPUVertexUniformData(cmd, 0, &viewport, sizeof(viewport));
        SDL_DrawGPUPrimitives(pass, 4, runs[i].count, 0, 0);
    }
    SDL_EndGPURenderPass(pass);
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
    for (int i = 0; i < 5; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(d, buffers[i]);
    for (int i = 0; i < 6; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(d, uploads[i]);
    free(packed[0]); free(packed[1]);
    return ok;
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

bool mui_platform_init(void) {
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
    if (dialog_event_type != 0 && e->type == dialog_event_type) {   // SV-G
        out->kind = MUI_EVENT_DIALOG; out->window_id = e->user.windowID; out->start = e->user.code; return true;
    }
    switch (e->type) {
    case SDL_EVENT_QUIT: out->kind = MUI_EVENT_QUIT; return true;
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        out->kind = MUI_EVENT_CLOSE; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_RESIZED: case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
        out->kind = MUI_EVENT_RESIZE; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_EXPOSED:
        out->kind = MUI_EVENT_EXPOSED; out->window_id = e->window.windowID; return true;
    case SDL_EVENT_WINDOW_FOCUS_GAINED:
        out->kind = MUI_EVENT_FOCUS_GAINED; out->window_id = e->window.windowID; return true;
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
        e.window.windowID = in->window_id; break;
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
void mui_window_destroy(void *w) { SDL_DestroyWindow((SDL_Window *)w); }
uint32_t mui_window_id(void *w) { return SDL_GetWindowID((SDL_Window *)w); }
void mui_window_size(void *w, int32_t *width, int32_t *height) { SDL_GetWindowSize((SDL_Window *)w, width, height); }
bool mui_window_set_title(void *w, const char *t) { return SDL_SetWindowTitle((SDL_Window *)w, t); }
const char *mui_window_title(void *w) { return SDL_GetWindowTitle((SDL_Window *)w); }
bool mui_window_show(void *w) { return SDL_ShowWindow((SDL_Window *)w); }
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

#else
/* Built without the `SDL` trait: no SDL3 header, no SDL3 link. */
int mui_bridge_built_without_sdl = 1;
#endif
