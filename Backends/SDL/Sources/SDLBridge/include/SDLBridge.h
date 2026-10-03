#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct ReplayGPU ReplayGPU;
// kind: 0 rect, 1 glyph, 2 image (ruling TE-AF). An image run samples one
// texture: the one its first record's `texture` field names.
typedef struct { uint32_t kind, start, count; } ReplayRun;
// A texture an image record samples: premultiplied RGBA8, row-major, borrowed.
typedef struct { const uint8_t *rgba; uint32_t width, height; } ReplayTexture;
ReplayGPU *replay_create(const char *msl);
// shader_dir contains six compiled stages; driver: metal, vulkan, direct3d12.
ReplayGPU *replay_create_portable(const char *shader_dir, const char *driver);
const char *replay_error(void);
const char *replay_driver(ReplayGPU *gpu);
void replay_destroy(ReplayGPU *gpu);
// Replaces the linear atlas sampler with a nearest one (diagnostic arm).
bool replay_use_nearest_filter(ReplayGPU *gpu);
// Synchronous diagnostic renderer. Copies caller bytes before returning.
// Buffers are opaque: Swift supplies the existing MetalUI shader ABI.
// `transforms` is the scene's MUITransform table (64 bytes a record, ruling
// GX-F); 0 bytes binds one zero record, which index 0 never reads.
bool replay_render(ReplayGPU *gpu, uint32_t width, uint32_t height,
    const void *rects, uint32_t rect_bytes, const void *glyphs, uint32_t glyph_bytes,
    const void *images, uint32_t image_bytes, const void *transforms, uint32_t transform_bytes,
    const ReplayTexture *textures, uint32_t texture_count,
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
// An image texture the renderer keeps until released (ruling TE-AF): created
// and uploaded at once (its own command buffer, submitted before the frame's),
// never written again. Returns an SDL_GPUTexture *, or NULL (replay_error()).
void *mui_renderer_create_texture(MUIRenderer *r, const uint8_t *rgba, uint32_t width, uint32_t height);
// SDL frees it once no submitted frame uses it.
void mui_renderer_release_texture(MUIRenderer *r, void *texture);
// Draws into the target `begin` acquired and submits. The atlas is uploaded
// whole when `atlas_dirty` is set or its size changed. `textures[i]` is the
// texture an image record's `texture` field `i` names (from create_texture).
// `transforms`: the scene's MUITransform table, as for replay_render.
bool mui_renderer_finish(MUIRenderer *r,
    const void *rects, uint32_t rect_bytes, const void *glyphs, uint32_t glyph_bytes,
    const void *images, uint32_t image_bytes, const void *transforms, uint32_t transform_bytes,
    void *const *textures, uint32_t texture_count,
    const ReplayRun *runs, uint32_t run_count,
    const uint8_t *atlas, uint32_t atlas_width, uint32_t atlas_height, bool atlas_dirty,
    const float *projection);
// The last offscreen frame as BGRA rows (waits for it).
bool mui_renderer_read_offscreen(MUIRenderer *r, uint8_t *bgra);
// How many times the renderer has released an offscreen frame's fence before
// the GPU signalled it — always 0 (SDL recycles a released fence while the
// submitted command buffer still points at it; record §61 §10).
uint32_t mui_renderer_unsignaled_fence_releases(MUIRenderer *r);
// How many command buffers this renderer has submitted, ever: every SDL_Submit…
// in the mui_renderer_* functions (finish, create_texture, read_offscreen) —
// so a test sees that an app surface adds no submission (MV-L item 4).
uint32_t mui_renderer_submission_count(MUIRenderer *r);
// ---- App-owned GPU surfaces (MetalView, ruling MV-H item 2) ---------------
// The renderer's SDL_GPUDevice *.
void *mui_renderer_device(MUIRenderer *r);
// The frame's SDL_GPUCommandBuffer * — valid between a successful begin and
// finish, NULL otherwise. App surface draws record into it; finish submits it.
void *mui_renderer_command_buffer(MUIRenderer *r);
// A surface's render target (SDL_GPUTexture *): B8G8R8A8_UNORM, colour target
// and sampler, w×h in 1…8192, contents undefined. No upload, so no submission
// and no fence. Release with mui_renderer_release_texture. NULL on failure.
void *mui_renderer_create_target(MUIRenderer *r, uint32_t width, uint32_t height);
// Records one render pass clearing `texture` to the premultiplied colour into
// `cmd` (an SDL_GPUCommandBuffer *), ended at once; submits nothing.
bool mui_gpu_clear_texture(void *cmd, void *texture, float red, float green, float blue, float alpha);
// Records one nearest-filtered blit of all of `source` (sw×sh, sampler usage)
// over the region (0, 0, dw, dh) of `destination` (colour-target usage),
// loading what is outside it, into `cmd`; submits nothing. A test's
// non-uniform surface fill (MV-Q): placed by the draw's pixelSize, so a
// target made at any other size composites a different pattern.
bool mui_gpu_blit_texture(void *cmd, void *source, uint32_t sw, uint32_t sh,
                          void *destination, uint32_t dw, uint32_t dh);
// The window's device pixels per point (SDL_GetWindowPixelDensity).
float mui_window_pixel_density(void *window);

// ---- The SDL platform (ruling SP-A) --------------------------------------
// Windows and events for MetalUIPlatform's `Platform`/`PlatformWindow`,
// flattened so Swift never touches SDL's event union.
enum {
    MUI_EVENT_NONE = 0, MUI_EVENT_QUIT, MUI_EVENT_CLOSE, MUI_EVENT_RESIZE,
    MUI_EVENT_MOUSE_DOWN, MUI_EVENT_MOUSE_UP, MUI_EVENT_MOUSE_MOVE, MUI_EVENT_WHEEL,
    MUI_EVENT_KEY_DOWN, MUI_EVENT_KEY_UP, MUI_EVENT_THEME, MUI_EVENT_EXPOSED,
    MUI_EVENT_ACCESSIBILITY, MUI_EVENT_MOUSE_DRAG, MUI_EVENT_TEXT_INPUT, MUI_EVENT_TEXT_EDITING,
    // Keyboard focus (ruling EV-AB). Appended, so no earlier kind renumbers.
    MUI_EVENT_FOCUS_GAINED, MUI_EVENT_FOCUS_LOST,
    // Drops from other applications (ruling DN-M). Appended after FOCUS_LOST,
    // so no earlier kind renumbers. `x`, `y` are window points where SDL gives
    // them (not on BEGIN); FILE's `text` is the path, TEXT's the text — both
    // owned by SDL until the next poll, so copy them at once.
    MUI_EVENT_DROP_BEGIN, MUI_EVENT_DROP_POSITION, MUI_EVENT_DROP_FILE, MUI_EVENT_DROP_TEXT,
    MUI_EVENT_DROP_COMPLETE,
    // The secondary (right) button (ruling MN-B item 3). Appended after
    // DROP_COMPLETE, so no earlier kind renumbers.
    MUI_EVENT_RIGHT_DOWN, MUI_EVENT_RIGHT_UP
};
enum { MUI_MOD_SHIFT = 1, MUI_MOD_CONTROL = 2, MUI_MOD_OPTION = 4, MUI_MOD_COMMAND = 8 };
typedef struct {
    uint32_t kind;
    uint32_t window_id;
    float x, y;            // pointer position in points, top-left origin
    float dx, dy;          // wheel, in lines (SDL's unit), direction applied
    uint32_t modifiers;    // MUI_MOD_*
    int32_t clicks;
    uint32_t keycode;      // SDL_Keycode
    bool repeat;
    double timestamp;      // seconds
    // TEXT_INPUT / TEXT_EDITING: UTF-8 owned by SDL, valid until the next
    // poll — copy it at once. EDITING's selection is `start`, `length` in
    // Unicode code points (SDL's unit).
    const char *text;
    int32_t start, length;
} MUIEvent;
bool mui_platform_init(void);
bool mui_poll_event(MUIEvent *event);
bool mui_wait_event(MUIEvent *event, int32_t timeout_ms);
// Pushes a synthetic SDL event built from `event` — for tests.
bool mui_push_event(const MUIEvent *event);
// Pushes an unflattened SDL_EVENT_WINDOW_* of type `sdl_type` for `window_id`,
// so a test reaches translate's arms for kinds mui_push_event cannot spell
// (the scale and pixel-size changes, ruling EV-AA). For tests.
bool mui_push_raw_window_event(uint32_t sdl_type, uint32_t window_id);
// SDL's event types for the two window events above, for tests.
extern const uint32_t mui_sdl_event_window_display_scale_changed;
extern const uint32_t mui_sdl_event_window_pixel_size_changed;
// Pushes an unflattened SDL_EVENT_DROP_* of type `sdl_type` (one of the
// mui_sdl_event_drop_* constants below) for `window_id` at (x, y), carrying a
// copy of `data` (NULL for BEGIN, POSITION and COMPLETE) — so a test reaches
// translate's drop arms through SDL's own queue (ruling DN-M, DN-U item 4).
// For tests.
bool mui_push_raw_drop_event(uint32_t sdl_type, uint32_t window_id, float x, float y, const char *data);
// SDL's event types for the five drop events, for tests. Exported from C so
// Swift never spells `SDL_EVENT_DROP_*.rawValue`, which is Int32 on Windows
// and UInt32 on Apple (DN-U item 4).
extern const uint32_t mui_sdl_event_drop_begin;
extern const uint32_t mui_sdl_event_drop_position;
extern const uint32_t mui_sdl_event_drop_file;
extern const uint32_t mui_sdl_event_drop_text;
extern const uint32_t mui_sdl_event_drop_complete;
// Pushes an unflattened SDL_EVENT_MOUSE_BUTTON_DOWN/UP (`sdl_type`, one of the
// mui_sdl_event_mouse_button_* constants below) for `button`, or an
// SDL_EVENT_MOUSE_MOTION with `state` (a mask of the mui_sdl_button_*mask
// constants), for `window_id` at (x, y) — so a test reaches translate's
// pointer arms through SDL's own queue (ruling MN-B item 3). For tests.
bool mui_push_raw_mouse_event(uint32_t sdl_type, uint32_t window_id, uint8_t button, uint32_t state,
                              float x, float y);
// SDL's pointer event types, buttons and masks, for tests. Exported from C so
// Swift never spells an SDL enum's `rawValue` (Int32 on Windows, MN-AD).
extern const uint32_t mui_sdl_event_mouse_button_down;
extern const uint32_t mui_sdl_event_mouse_button_up;
extern const uint32_t mui_sdl_event_mouse_motion;
extern const uint8_t mui_sdl_button_left;
extern const uint8_t mui_sdl_button_right;
extern const uint32_t mui_sdl_button_lmask;
extern const uint32_t mui_sdl_button_rmask;
// Whether SDL reports the window as having keyboard focus
// (SDL_WINDOW_INPUT_FOCUS) — read once, when a window opens (ruling EV-AB).
bool mui_window_has_input_focus(void *window);
void *mui_window_create(const char *title, int32_t width, int32_t height, bool hidden);
void mui_window_destroy(void *window);
uint32_t mui_window_id(void *window);
void mui_window_size(void *window, int32_t *width, int32_t *height);
bool mui_window_set_title(void *window, const char *title);
const char *mui_window_title(void *window);
bool mui_window_show(void *window);
// 0 light, 1 dark (SDL_GetSystemTheme; unknown reads as light).
int32_t mui_system_theme(void);
double mui_now(void);
// Wakes the event loop with MUI_EVENT_ACCESSIBILITY for `window_id` — safe
// from any thread; AccessKit's Linux adapter calls back on its own (AX-C).
bool mui_wake_for_accessibility(uint32_t window_id);
// The platform window under an SDL window: NSWindow on macOS, HWND on
// Windows, NULL elsewhere (AccessKit's subclassing adapters take it).
void *mui_window_native_handle(void *window);
// Text input (ruling TI-A): start with the caret rectangle (points) for the
// input method's candidate window, or stop.
bool mui_window_start_text_input(void *window, int32_t x, int32_t y, int32_t w, int32_t h);
bool mui_window_stop_text_input(void *window);
// The clipboard's UTF-8 text (free with mui_free), or NULL.
char *mui_clipboard_text(void);
bool mui_set_clipboard_text(const char *text);
void mui_free(void *memory);
// The window's position on screen in points (SDL_GetWindowPosition).
void mui_window_position(void *window, int32_t *x, int32_t *y);

// ---- The application icon (ruling AI-F) ------------------------------------
// SDL_PIXELFORMAT_RGBA32 (bytes R, G, B, A on every endianness), exported from
// C so Swift never spells a C enum's `rawValue` (Int32 on Windows, UInt32 on
// Apple).
extern const uint32_t MUI_PIXELFORMAT_RGBA32;
// An SDL_Surface * of `w` × `h` RGBA32 texels copied row by row through its
// pitch from `straight_rgba` (w × h × 4 bytes, STRAIGHT alpha), or NULL
// (replay_error()). Destroy with mui_surface_destroy.
void *mui_icon_surface_create(int32_t w, int32_t h, const uint8_t *straight_rgba);
// Adds `image` to `primary` as an alternate (SDL_AddSurfaceAlternateImage,
// which takes its own reference: the caller still destroys `image`).
bool mui_icon_surface_add_alternate(void *primary, void *image);
// SDL_SetWindowIcon. A NULL surface is refused (false) without calling SDL,
// and counted in mui_window_set_icon_null_calls.
bool mui_window_set_icon(void *window, void *surface);
// How many times mui_window_set_icon was handed NULL — always 0 (ruling AI-F
// item 5: NULL is never passed). For tests.
uint32_t mui_window_set_icon_null_calls(void);
void mui_surface_destroy(void *surface);
// Test readback.
uint32_t mui_surface_format(void *surface);
void mui_surface_size(void *surface, int32_t *w, int32_t *h);
// Copies the surface's texels, row by row through its pitch, into `out`
// (w × h × 4 bytes); false when `capacity` is short.
bool mui_surface_read_rgba(void *surface, uint8_t *out, int32_t capacity);
// SDL_GetSurfaceImages's count (the primary and its alternates), 0 on failure.
int32_t mui_surface_image_count(void *surface);
// The size of SDL_GetSurfaceImages's `index`th image; 0 × 0 out of range.
void mui_surface_image_size(void *surface, int32_t index, int32_t *w, int32_t *h);
