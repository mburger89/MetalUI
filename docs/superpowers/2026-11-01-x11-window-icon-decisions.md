# X11 window icon - decisions

Rulings for the X11 window icon (item XP-G37, MetalCreator 2026-11-01, **not a plan task**). Record: `../record/183-x11-window-icon.md`.
Prefix **`WI-`**, lettered. **Next unused: `WI-F`.** (This line moves in the commit that appends a ruling; read the last `## WI-` heading.)

Branch `fix/x11-window-icon` from master `71e46462`. Class `M`: no public declaration, no divergence (975-984 untouched), nothing published.
The app-icon rulings (`AI-A`..`AI-N`, `2026-10-01-app-icon-decisions.md`) stand; `WI-B` adds to `AI-F` item 4.

## WI-A - the reported empty `_NET_WM_ICON` was xprop, not the property

**Report.** `app.icon = [one 256x256 bitmap]` on Ubuntu 24.04 aarch64, GNOME on Xorg: `xprop -id <win> -len 16 _NET_WM_ICON` printed
`_NET_WM_ICON(CARDINAL) =` and nothing else.

**Measured** (arm64 `swift:6.4-noble` image, SDL 3.4.16 with X11, Xvfb; a C program with no MetalUI, then MetalUI, then MetalCreator's own tarball):
`XGetWindowProperty` reads back `nitems=65538 remaining=0 w=256 h=256` for SDL's `SDL_SetWindowIcon` of one 256x256 `SDL_PIXELFORMAT_RGBA32`
surface (icon set before or after `SDL_ShowWindow`: the same), for the MetalUI program, and for MetalCreator's running app (`nitems=65538`).
xprop 1.2.6's pretty-printer for `_NET_WM_ICON` prints the bitmap for 32x32 and 64x64, `(not shown)` for 128-245, and **nothing at all from about 250
pixels up** (245 prints, 250 does not), whatever `-len` (`-len 300000` too); `-len 16` truncates any icon. `xprop -f _NET_WM_ICON 32c -len 400000`
prints `256, 256, 4294901760, ...`. The request-size theory (65538 CARDINALs, over the 256 KB core limit) is **refuted**: Xvfb reports a
16777212-byte maximum request and Xlib sends the property in one `XChangeProperty`; SDL's source (`X11_SetWindowIcon`) has no cap.

**Ruling.** No change to the one-image path. Any later check of the property reads raw values (`-f _NET_WM_ICON 32c`, or `XGetWindowProperty`),
never xprop's default. `.github/fixtures/x11-icon/check.sh` does.

## WI-B - every size is written to `_NET_WM_ICON` (the actual defect)

**Measured.** SDL 3.4.16's `X11_SetWindowIcon` converts and writes `window->icon` only; the alternates `SDL_AddSurfaceAlternateImage` added
are ignored on X11 (they are for Cocoa's and Wayland's scale pickers). A three-size `app.icon` ([16, 32, 256]) reached the property as `16x16`
alone, set before or after the window opened, so a window manager showing a 48 or 256 pixel icon scaled up a 16 pixel one.

**Ruling.** `mui_window_set_icon` calls `mui_x11_set_net_wm_icon` after `SDL_SetWindowIcon` succeeds. When SDL's video driver is `x11` and the surface
has more than one image it writes the list of (width, height, width x height ARGB32) records over `_NET_WM_ICON`, in `SDL_GetSurfaceImages`
order (the primary, the smallest, first - `AI-B`'s order). One image is left to SDL, which writes it whole. `mui_x11_icon_property` builds the
list as a pure function (`SDLIconTests` W1, W2).

## WI-C - through a dlopened libX11, inside the server's request limit

**Ruling.** The Display and Window come from SDL's window properties (`SDL_PROP_WINDOW_X11_DISPLAY_POINTER`, `..._WINDOW_NUMBER`); `XInternAtom`,
`XChangeProperty`, `XFlush`, `XExtendedMaxRequestSize` and `XMaxRequestSize` are found with `SDL_LoadObject("libX11.so.6")`/`SDL_LoadFunction`, as SDL
itself loads them. The bridge links no X library (`VD-A`: the image bundles none). A request longer than the server accepts is a BadLength the default
Xlib handler answers by exiting the process, so the list is built under `XExtendedMaxRequestSize - 6` longs and an image whose record would
pass it is left out whole (W2); a window whose limit leaves room for nothing keeps SDL's primary.

**Rejected**: linking libX11 (breaks `VD-A`); making the largest image the primary (the window manager then scales one image down, blurry
at 16 and 24); an `XSetErrorHandler` around the call (SDL's own handler is process-global state; staying under the limit needs none);
downscaling in Swift (the bitmaps are the author's).

## WI-D - X11 only; what is not claimed

**Ruling.** Cocoa (the Dock icon, `AI-I`), Windows (`WM_SETICON`) and Wayland are untouched: the driver check is the gate (`W3` pins that the
counter moves only under `SDL_VIDEO_DRIVER=x11`, and for more than one size). **Unverified**: Wayland (SDL's `xdg-toplevel-icon-v1` path
with alternates, no compositor here) and a real GNOME shell's alt-tab and dock (`docs/verification/human-checks.md`, group `WI`).

## WI-E - the CI arm: `IconCheck` under Xvfb

**Ruling.** The `linux` job of `sdl-gpu-linux.yml` runs `IconCheck` (`Backends/SDL/Sources/IconCheck`, a plain-import `App` on a real `SDLPlatform`
window) under Xvfb with `SDL_VIDEO_DRIVER=x11`: `256`, `16,32,256`, and `16,32,256` set after the window opened. After 60 loop passes it runs
`.github/fixtures/x11-icon/check.sh`, which reads `_NET_WM_ICON` raw (`WI-A`) and walks the records, failing unless the sizes are exactly the
expected list. The Dockerfile gains `xvfb x11-utils`. Red on arrival: without `WI-B` the second and third runs read `[16x16]`; the `256` arm is green
before and after (it documents `WI-A`).
