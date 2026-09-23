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

// ---- The SDL platform (ruling SP-A) --------------------------------------
// Windows and events for MetalUIPlatform's `Platform`/`PlatformWindow`,
// flattened so Swift never touches SDL's event union.
enum {
    MUI_EVENT_NONE = 0, MUI_EVENT_QUIT, MUI_EVENT_CLOSE, MUI_EVENT_RESIZE,
    MUI_EVENT_MOUSE_DOWN, MUI_EVENT_MOUSE_UP, MUI_EVENT_MOUSE_MOVE, MUI_EVENT_WHEEL,
    MUI_EVENT_KEY_DOWN, MUI_EVENT_KEY_UP, MUI_EVENT_THEME, MUI_EVENT_EXPOSED,
    MUI_EVENT_ACCESSIBILITY, MUI_EVENT_MOUSE_DRAG, MUI_EVENT_TEXT_INPUT, MUI_EVENT_TEXT_EDITING
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
