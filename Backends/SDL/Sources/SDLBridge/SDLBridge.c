#include "SDLBridge.h"
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct ReplayGPU {
    SDL_GPUDevice *device;
    SDL_GPUGraphicsPipeline *rect, *glyph;
    SDL_GPUSampler *sampler;
    SDL_GPUTexture *target;
    uint32_t width, height;
    const char *shader_dir;
    SDL_GPUShaderFormat format;
    bool portable;
};

const char *replay_error(void) { return SDL_GetError(); }
const char *replay_driver(ReplayGPU *g) { return SDL_GetGPUDeviceDriver(g->device); }

static SDL_GPUShader *shader(ReplayGPU *g, const char *source, const char *entry,
                            bool fragment, bool glyph) {
    void *loaded = NULL;
    size_t size = source ? strlen(source) : 0;
    if (g->portable) {
        const char *extension = g->format == SDL_GPU_SHADERFORMAT_MSL ? "msl" :
            g->format == SDL_GPU_SHADERFORMAT_SPIRV ? "spv" : "dxil";
        char path[4096];
        int length = snprintf(path, sizeof(path), "%s/%s.%s.%s", g->shader_dir,
            glyph ? "glyph" : "rect", fragment ? "fragment" : "vertex", extension);
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
        .num_storage_buffers = fragment ? 1 : 2,
        .num_uniform_buffers = fragment ? 0 : 2,
        .num_samplers = fragment && glyph ? 1 : 0
    };
    SDL_GPUShader *result = SDL_CreateGPUShader(g->device, &info);
    SDL_free(loaded);
    return result;
}

static SDL_GPUGraphicsPipeline *pipeline(ReplayGPU *g, const char *source, bool glyph) {
    SDL_GPUShader *v = shader(g, source, glyph ? "glyph_vertex" : "rect_vertex", false, glyph);
    if (!v) return NULL;
    SDL_GPUShader *f = shader(g, source, glyph ? "glyph_fragment" : "rect_fragment", true, glyph);
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
    g->rect = pipeline(g, source, false);
    if (!g->rect) goto fail;
    g->glyph = pipeline(g, source, true);
    if (!g->glyph) goto fail;
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
        SDL_DestroyGPUDevice(g->device);
    }
    free(g); SDL_QuitSubSystem(SDL_INIT_VIDEO);
}

static SDL_GPUTexture *texture(ReplayGPU *g, uint32_t w, uint32_t h, bool target) {
    SDL_GPUTextureCreateInfo info = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = target ? SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM : SDL_GPU_TEXTUREFORMAT_R8_UNORM,
        .usage = target ? SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER : SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = w, .height = h, .layer_count_or_depth = 1, .num_levels = 1
    };
    return SDL_CreateGPUTexture(g->device, &info);
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

bool replay_render(ReplayGPU *g, uint32_t w, uint32_t h,
    const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah,
    const float *projection, uint8_t *out) {
    // Diagnostic harness only: bounded fixtures, one completed frame at a time.
    if (!w || !h || w > 4096 || h > 4096 || !aw || !ah || aw > 4096 || ah > 4096)
        return SDL_SetError("invalid fixture dimensions");
    SDL_GPUBuffer *buffers[3] = {0};
    SDL_GPUTransferBuffer *uploads[4] = {0}, *download = NULL;
    SDL_GPUTexture *atlas_texture = NULL;
    SDL_GPUCommandBuffer *cmd = NULL;
    SDL_GPUFence *fence = NULL;
    bool ok = false;
    void *packed[2] = {0};
    if (g->target) { SDL_ReleaseGPUTexture(g->device, g->target); g->target = NULL; }
    g->target = texture(g, w, h, true);
    g->width = w; g->height = h;
    atlas_texture = texture(g, aw, ah, false);
    if (!g->target || !atlas_texture) goto cleanup;
    const float quad[] = {0,0, 1,0, 0,1, 1,1};
    const float aligned_quad[] = {0,0,0,0, 1,0,0,0, 0,1,0,0, 1,1,0,0};
    const void *data[] = {quad, rects, glyphs};
    uint32_t sizes[] = {sizeof(quad), rb, gb};
    if (g->portable) {
        // The existing CPU ABI is scalar-packed (120/88 bytes). SDL storage
        // uses 16-byte lanes, so round each record up, never reinterpret it.
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
    for (int i = 0; i < 3; i++) {
        if (!sizes[i]) continue;
        SDL_GPUBufferCreateInfo info = {
            .usage = SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ, .size = sizes[i]
        };
        buffers[i] = SDL_CreateGPUBuffer(g->device, &info);
        uploads[i] = transfer(g, sizes[i], false, data[i]);
        if (!buffers[i] || !uploads[i]) goto cleanup;
    }
    uploads[3] = transfer(g, aw * ah, false, atlas);
    // 256-byte pitch also works for a future D3D readback path.
    uint32_t pitch = (w * 4 + 255) & ~255u;
    download = transfer(g, pitch * h, true, NULL);
    if (!uploads[3] || !download) goto cleanup;
    cmd = SDL_AcquireGPUCommandBuffer(g->device);
    if (!cmd) goto cleanup;
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < 3; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[3] };
    SDL_GPUTextureRegion atlas_dst = { .texture = atlas_texture, .w = aw, .h = ah, .d = 1 };
    SDL_UploadToGPUTexture(copy, &atlas_src, &atlas_dst, false);
    SDL_EndGPUCopyPass(copy);
    struct { float width, height; uint32_t first_instance, padding; } viewport = {(float)w, (float)h, 0, 0};
    SDL_PushGPUVertexUniformData(cmd, 1, projection, sizeof(float) * 16);
    SDL_GPUColorTargetInfo target = {
        .texture = g->target, .load_op = SDL_GPU_LOADOP_CLEAR, .store_op = SDL_GPU_STOREOP_STORE
    };
    SDL_GPURenderPass *pass = SDL_BeginGPURenderPass(cmd, &target, 1, NULL);
    if (!pass) goto cleanup;
    for (uint32_t i = 0; i < count; i++) {
        bool glyph = runs[i].kind == 1;
        SDL_GPUBuffer *primitives = buffers[glyph ? 2 : 1];
        SDL_GPUBuffer *vertex_buffers[] = {buffers[0], primitives};
        SDL_BindGPUGraphicsPipeline(pass, glyph ? g->glyph : g->rect);
        SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 2);
        SDL_BindGPUFragmentStorageBuffers(pass, 0, &primitives, 1);
        if (glyph) {
            SDL_GPUTextureSamplerBinding binding = {atlas_texture, g->sampler};
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
    for (int i = 0; i < 3; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(g->device, buffers[i]);
    for (int i = 0; i < 4; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(g->device, uploads[i]);
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
};

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
    if (r->fence) SDL_ReleaseGPUFence(d, r->fence);
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

bool mui_renderer_finish(MUIRenderer *r,
    const void *rects, uint32_t rb, const void *glyphs, uint32_t gb,
    const ReplayRun *runs, uint32_t count,
    const uint8_t *atlas, uint32_t aw, uint32_t ah, bool atlas_dirty,
    const float *projection) {
    if (!r->cmd) return SDL_SetError("finish without a successful begin");
    SDL_GPUDevice *d = r->gpu->device;
    SDL_GPUCommandBuffer *cmd = r->cmd;
    r->cmd = NULL;
    SDL_GPUBuffer *buffers[3] = {0};
    SDL_GPUTransferBuffer *uploads[4] = {0};
    void *packed[2] = {0};
    bool ok = false;

    /* The CPU ABI is scalar-packed (120/88 bytes); SDL storage buffers use
       16-byte lanes, so each record is copied into a 128/96-byte slot. */
    const float aligned_quad[] = {0,0,0,0, 1,0,0,0, 0,1,0,0, 1,1,0,0};
    const void *data[] = {aligned_quad, rects, glyphs};
    uint32_t sizes[] = {sizeof(aligned_quad), rb, gb};
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
    for (int i = 0; i < 3; i++) {
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
        uploads[3] = transfer(r->gpu, aw * ah, false, atlas);
        if (!uploads[3]) goto cleanup;
    }
    SDL_GPUCopyPass *copy = SDL_BeginGPUCopyPass(cmd);
    if (!copy) goto cleanup;
    for (int i = 0; i < 3; i++) if (sizes[i]) {
        SDL_GPUTransferBufferLocation src = { .transfer_buffer = uploads[i] };
        SDL_GPUBufferRegion dst = { .buffer = buffers[i], .size = sizes[i] };
        SDL_UploadToGPUBuffer(copy, &src, &dst, false);
    }
    if (uploads[3]) {
        SDL_GPUTextureTransferInfo atlas_src = { .transfer_buffer = uploads[3] };
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
        bool glyph = runs[i].kind == 1;
        SDL_GPUBuffer *primitives = buffers[glyph ? 2 : 1];
        if (!primitives) continue;
        SDL_GPUBuffer *vertex_buffers[] = {buffers[0], primitives};
        SDL_BindGPUGraphicsPipeline(pass, glyph ? r->gpu->glyph : r->gpu->rect);
        SDL_BindGPUVertexStorageBuffers(pass, 0, vertex_buffers, 2);
        SDL_BindGPUFragmentStorageBuffers(pass, 0, &primitives, 1);
        if (glyph) {
            SDL_GPUTextureSamplerBinding binding = {r->atlas, r->gpu->sampler};
            SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        }
        viewport.first_instance = runs[i].start;
        SDL_PushGPUVertexUniformData(cmd, 0, &viewport, sizeof(viewport));
        SDL_DrawGPUPrimitives(pass, 4, runs[i].count, 0, 0);
    }
    SDL_EndGPURenderPass(pass);
    if (r->window) {
        ok = SDL_SubmitGPUCommandBuffer(cmd);
    } else {
        if (r->fence) { SDL_ReleaseGPUFence(d, r->fence); r->fence = NULL; }
        r->fence = SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
        ok = r->fence != NULL;
    }
    cmd = NULL;
cleanup:
    if (cmd) SDL_CancelGPUCommandBuffer(cmd);
    /* SDL releases these once the GPU no longer uses them. */
    for (int i = 0; i < 3; i++) if (buffers[i]) SDL_ReleaseGPUBuffer(d, buffers[i]);
    for (int i = 0; i < 4; i++) if (uploads[i]) SDL_ReleaseGPUTransferBuffer(d, uploads[i]);
    free(packed[0]); free(packed[1]);
    return ok;
}

bool mui_renderer_read_offscreen(MUIRenderer *r, uint8_t *out) {
    if (!r->offscreen) return SDL_SetError("no offscreen target");
    SDL_GPUDevice *d = r->gpu->device;
    if (r->fence) { SDL_WaitForGPUFences(d, true, &r->fence, 1); SDL_ReleaseGPUFence(d, r->fence); r->fence = NULL; }
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
