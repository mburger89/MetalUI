/* Probe TL-2 (item HG, record 154): SDL converts SIGTERM into an event; a process that initialises video and
 * never pumps events therefore ignores SIGTERM. Build and run:
 *   cc docs/probes/sdl-sigterm-handler.c -I/opt/homebrew/include -L/opt/homebrew/lib -lSDL3 -Wl,-rpath,/opt/homebrew/lib -o /tmp/p
 *   SDL_VIDEO_DRIVER=dummy /tmp/p & P=$!; sleep 1; kill -TERM $P; sleep 2; kill -0 $P   # alive: survived
 *   SDL_NO_SIGNAL_HANDLERS=1 SDL_VIDEO_DRIVER=dummy /tmp/p & ...                         # separating arm
 * Recorded 2026-10-24 (SDL 3.x from Homebrew, macOS 27): default env: SURVIVED SIGTERM (killed only by kill -9);
 * SDL_NO_SIGNAL_HANDLERS=1: died on SIGTERM. SDL_hints.h documents the hint (default "0": SIGINT and SIGTERM
 * become SDL_EVENT_QUIT). The same survival was measured in the real MetalUISDL test helper (record 154 section 2).
 */
#include <SDL3/SDL.h>
#include <unistd.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (!SDL_Init(SDL_INIT_VIDEO)) { printf("init failed %s\n", SDL_GetError()); return 2; }
    printf("ready\n"); fflush(stdout);
    for (int i = 0; i < 300; i++) usleep(100000);   // 30 s, never pumps events
    printf("survived\n"); return 0;
}
