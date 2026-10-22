// SDL3 probe: clipboard change events and a lazy data callback (round 2 item 6, rulings CP-D, CP-F of
// docs/superpowers/2026-10-22-clipboard-extras-decisions.md). Does SDL post SDL_EVENT_CLIPBOARD_UPDATE
// for the app's OWN SDL_SetClipboardData/ClearClipboardData with no window, is the data callback run
// at set time or at read time, and does a multi-mime set carry more than one "item" (it cannot: one
// callback, one mime list).
//
// HOW TO RUN: cc docs/probes/sdl-clipboard-update.c -I<sdl3 include> -L<sdl3 lib> -lSDL3 -o /tmp/sdlup
//             SDL_VIDEO_DRIVER=dummy /tmp/sdlup        (and =offscreen)
//
// RECORDED OUTPUT: see the block at the end of the file.
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
static int calls = 0;
static const void *cb(void *ud, const char *mime, size_t *size) { calls++; *size = 3; return "abc"; }
static void cl(void *ud) {}
static int drain(void) { SDL_PumpEvents(); SDL_Event e; int n = 0; while (SDL_PollEvent(&e)) if (e.type == SDL_EVENT_CLIPBOARD_UPDATE) n++; return n; }
int main(void) {
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("init fail %s\n", SDL_GetError()); return 1; }
  printf("driver=%s\n", SDL_GetCurrentVideoDriver());
  drain();
  const char *mimes[] = {"application/x-a", "text/plain;charset=utf-8"};
  SDL_SetClipboardData(cb, cl, NULL, mimes, 2);
  printf("callback calls right after set=%d  (0 = lazy: called at read)\n", calls);
  printf("update events after own set=%d\n", drain());
  size_t n; void *p = SDL_GetClipboardData(mimes[0], &n); SDL_free(p);
  printf("callback calls after one read=%d\n", calls);
  SDL_SetClipboardText("x"); printf("update events after SetClipboardText=%d\n", drain());
  SDL_ClearClipboardData(); printf("update events after clear=%d\n", drain());
  SDL_Quit(); return 0; }
// RECORDED OUTPUT (2026-10-21, macOS arm64, SDL 3.4.x Homebrew, dummy and offscreen identical):
//   driver=dummy
//   callback calls right after set=0  (0 = lazy: called at read)
//   update events after own set=1
//   callback calls after one read=1
//   update events after SetClipboardText=1
//   update events after clear=1
// Reading: SDL's callback is lazy by nature (CB-H made it pure C, not eager); every set, text set
// and clear posts exactly one SDL_EVENT_CLIPBOARD_UPDATE, with no window, so a test needs no
// second process. One callback and one mime list per set: SDL has no multi-item clipboard.
