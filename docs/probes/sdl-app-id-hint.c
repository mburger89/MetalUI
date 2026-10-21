// XP-G13 probe: what SDL does with SDL_HINT_APP_ID (AP-A, AP-C).
// Build/run (macOS, Homebrew SDL 3.4.18):
//   cc docs/probes/sdl-app-id-hint.c -I/opt/homebrew/include -L/opt/homebrew/lib -lSDL3 -o /tmp/appid && \
//     /tmp/appid; SDL_APP_ID=env.id /tmp/appid
// Arms: A1 SetHint before init reads back after init (positive control);
// A2 the SDL_APP_ID environment variable beats a normal-priority SDL_SetHint (separating arm: with env set the
// read-back is the env value, without it the code's); A3 the hint wins over SDL_SetAppMetadataProperty's identifier
// (SDL's metadata read answers the hint's value although the property was set afterwards).
// Recorded output (macOS, SDL 3.4.18, 2026-10-21), no env: A2 returned 1; A1 before/after init com.example.Probe;
// A3 com.example.Probe. With SDL_APP_ID=env.id: A2 returned 0; A1 before/after env.id; A3 env.id.
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    const char *env = getenv("SDL_APP_ID");
    printf("env SDL_APP_ID=%s\n", env ? env : "(unset)");
    bool set = SDL_SetHint(SDL_HINT_APP_ID, "com.example.Probe");
    printf("A2 SDL_SetHint returned %d\n", set);
    printf("A1 before init: %s\n", SDL_GetHint(SDL_HINT_APP_ID) ? SDL_GetHint(SDL_HINT_APP_ID) : "(null)");
    SDL_Init(SDL_INIT_EVENTS);
    printf("A1 after init: %s\n", SDL_GetHint(SDL_HINT_APP_ID) ? SDL_GetHint(SDL_HINT_APP_ID) : "(null)");
    SDL_SetAppMetadataProperty(SDL_PROP_APP_METADATA_IDENTIFIER_STRING, "com.example.Meta");
    printf("A3 metadata identifier: %s\n", SDL_GetAppMetadataProperty(SDL_PROP_APP_METADATA_IDENTIFIER_STRING));
    SDL_Quit();
    return 0;
}
