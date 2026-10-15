// SDL3 probe: the clipboard-data API with no window (item S3, rulings CB-H, CB-I of
// docs/superpowers/2026-10-14-clipboard-types-decisions.md). Does SetClipboardData ->
// HasClipboardData / GetClipboardData / GetClipboardText / GetClipboardMimeTypes round-trip
// inside one process on a headless video driver, when is the callback called, what do an
// absent type, a replace and a clear do.
//
// HOW TO RUN:  cc docs/probes/sdl-clipboard-data.c -I<sdl3 include> -L<sdl3 lib> -lSDL3 -o /tmp/sdlcb
//              SDL_VIDEO_DRIVER=dummy /tmp/sdlcb      (and =offscreen; the Linux image: CB-N)
//
// RECORDED OUTPUT (2026-10-14, macOS arm64, SDL 3.4.18, SDL_VIDEO_DRIVER=dummy; offscreen
// printed the same first lines):
//   driver=dummy
//   set=1 has_custom=1 has_text=1 hastext2=1
//   cb mime=application/x-com.acme.graph          <- called by GetClipboardData, on the caller's thread
//   get custom n=7 payload
//   cb mime=text/plain;charset=utf-8              <- GetClipboardText asks for exactly this mime
//   text=[payload]
//   types=2  (both mimes, in the order given)
//   absent=0x0 n=0 has=0                          <- an absent type is NULL, size 0
//   cleans after replace=1 has_custom=0           <- SetClipboardText ran the old cleanup once
//   after clear has_text=0
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
static int calls = 0, cleans = 0;
static const void *cb(void *ud, const char *mime, size_t *size) { calls++; printf("cb mime=%s\n", mime); const char *d = ud; *size = strlen(d); return d; }
static void cl(void *ud) { cleans++; }
int main(void) {
  if (!SDL_Init(SDL_INIT_VIDEO)) { printf("init fail %s\n", SDL_GetError()); return 1; }
  printf("driver=%s\n", SDL_GetCurrentVideoDriver());
  const char *mimes[] = {"application/x-com.acme.graph", "text/plain;charset=utf-8"};
  bool ok = SDL_SetClipboardData(cb, cl, (void *)"payload", mimes, 2);
  printf("set=%d has_custom=%d has_text=%d hastext2=%d\n", ok, SDL_HasClipboardData(mimes[0]), SDL_HasClipboardData(mimes[1]), SDL_HasClipboardText());
  size_t n = 0; void *p = SDL_GetClipboardData(mimes[0], &n); printf("get custom n=%zu %.*s\n", n, (int)n, (char*)p); SDL_free(p);
  char *t = SDL_GetClipboardText(); printf("text=[%s]\n", t); SDL_free(t);
  size_t cnt = 0; char **types = SDL_GetClipboardMimeTypes(&cnt); printf("types=%zu\n", cnt); for (size_t i=0;i<cnt;i++) printf(" %s\n", types[i]); SDL_free(types);
  p = SDL_GetClipboardData("application/x-absent", &n); printf("absent=%p n=%zu has=%d\n", p, n, SDL_HasClipboardData("application/x-absent"));
  SDL_SetClipboardText("replaced"); printf("cleans after replace=%d has_custom=%d\n", cleans, SDL_HasClipboardData(mimes[0]));
  SDL_ClearClipboardData(); printf("after clear has_text=%d\n", SDL_HasClipboardText());
  SDL_Quit(); return 0; }
