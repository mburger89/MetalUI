// Ruling VD-B: fails (exit 1) unless the installed libSDL3 was built with the desktop and
// the headless video drivers. Lists the drivers it finds; needs no display, no SDL_Init.
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    const char *required[] = {"x11", "wayland", "offscreen", "dummy"};
    int missing = 0;
    int n = SDL_GetNumVideoDrivers();
    printf("SDL %d.%d.%d video drivers (%d):", SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION, n);
    for (int i = 0; i < n; i++) printf(" %s", SDL_GetVideoDriver(i));
    printf("\n");
    for (unsigned r = 0; r < sizeof required / sizeof *required; r++) {
        int found = 0;
        for (int i = 0; i < n; i++) if (strcmp(SDL_GetVideoDriver(i), required[r]) == 0) found = 1;
        if (!found) { fprintf(stderr, "libSDL3 lacks the %s video driver\n", required[r]); missing = 1; }
    }
    return missing;
}
