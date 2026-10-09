// Probe for ruling WS-A (record §86): does AccessKit's platform adapter accept
// an SDL window that is already visible?  One arm per process, because a
// Rust panic across the C ABI aborts the process.
//
//   probe V   create the window VISIBLE, then the adapter         (positive control:
//             what SDLPlatform did at cd84b0c; the measured CI panic)
//   probe H   create HIDDEN, adapter, SDL_ShowWindow             (the fix's order)
//   probe S   create HIDDEN, SDL_ShowWindow, then the adapter     (separating arm:
//             visibility at adapter time decides, not the creation flag)
//   probe N   create HIDDEN, adapter, never shown                 (hiddenWindows: true)
//
// Each arm prints `arm=<X> visible_at_adapter=<0|1> sdl_shown_at_adapter=<0|1>
// adapter=<yes|no> visible_after=<0|1> sdl_shown_after=<0|1>` (visible = the
// native predicate AccessKit checks on Windows, `IsWindowVisible`)
// and exits 0; an abort before that line is the panic.  Run: run.ps1 (Windows),
// run.sh (macOS).  Recorded output: README.md in this directory.
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <accesskit.h>
#ifdef _WIN32
#include <windows.h>
#endif

static struct accesskit_tree_update *activation(void *userdata) { (void)userdata; return NULL; }
static void action(struct accesskit_action_request *request, void *userdata) {
    (void)userdata; accesskit_action_request_free(request);
}

static int nativeVisible(SDL_Window *w) {
#ifdef _WIN32
    HWND hwnd = SDL_GetPointerProperty(SDL_GetWindowProperties(w), SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    return IsWindowVisible(hwnd) ? 1 : 0;
#else
    return (SDL_GetWindowFlags(w) & SDL_WINDOW_HIDDEN) ? 0 : 1;
#endif
}

static int sdlShown(SDL_Window *w) { return (SDL_GetWindowFlags(w) & SDL_WINDOW_HIDDEN) ? 0 : 1; }

static void *makeAdapter(SDL_Window *w) {
    SDL_PropertiesID p = SDL_GetWindowProperties(w);
#if defined(_WIN32)
    HWND hwnd = SDL_GetPointerProperty(p, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    return accesskit_windows_subclassing_adapter_new(hwnd, activation, NULL, action, NULL);
#elif defined(__APPLE__)
    void *nswindow = SDL_GetPointerProperty(p, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    return accesskit_macos_subclassing_adapter_for_window(nswindow, activation, NULL, action, NULL);
#else
    (void)p; return NULL;
#endif
}

int main(int argc, char **argv) {
    const char *arm = argc > 1 ? argv[1] : "V";
    if (!SDL_Init(SDL_INIT_VIDEO)) { printf("SDL_Init: %s\n", SDL_GetError()); return 2; }
    int hidden = strcmp(arm, "V") != 0;
    SDL_Window *w = SDL_CreateWindow("accesskit-window-show probe", 320, 200,
                                     SDL_WINDOW_RESIZABLE | (hidden ? SDL_WINDOW_HIDDEN : 0));
    if (!w) { printf("SDL_CreateWindow: %s\n", SDL_GetError()); return 2; }
    if (strcmp(arm, "S") == 0) SDL_ShowWindow(w);
    int before = nativeVisible(w);
    printf("arm=%s visible_at_adapter=%d sdl_shown_at_adapter=%d ", arm, before, sdlShown(w)); fflush(stdout);
    void *adapter = makeAdapter(w);
    if (strcmp(arm, "H") == 0) SDL_ShowWindow(w);
    printf("adapter=%s visible_after=%d sdl_shown_after=%d\n", adapter ? "yes" : "no", nativeVisible(w), sdlShown(w));
    fflush(stdout);
    SDL_DestroyWindow(w);
    SDL_Quit();
    return 0;
}
