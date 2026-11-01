# 183 - the X11 window icon (`WI-A`..`WI-E`)

2026-11-01, branch `fix/x11-window-icon` from master `71e46462`; item XP-G36 (MetalCreator; the number is shared with record 182's
uniform slots, which landed first). Rulings: `docs/superpowers/2026-11-01-x11-window-icon-decisions.md`.

## 1. The report and what was measured

MetalCreator reported `_NET_WM_ICON` existing but empty for one 256x256 `app.icon` on Ubuntu 24.04 aarch64 / GNOME on Xorg (`xprop -len 16`).
In an arm64 container (`swift:6.4-noble` image, SDL 3.4.16 X11, Xvfb; `xvfb x11-utils` added in a derived image, then in the Dockerfile):

| Experiment | Result |
|---|---|
| C, SDL only, 32x32 RGBA32 surface, before / after `SDL_ShowWindow` | `nitems=1026 w=32 h=32`, both |
| C, SDL only, 256x256, before / after show | `nitems=65538 w=256 h=256`, both (xprop default, `-len 16`, `-len 300000`: empty) |
| C, sizes 245..250, 255, 256 | `XGetWindowProperty` full for all; xprop prints the bitmap to 245, nothing from 250 |
| `xprop -f _NET_WM_ICON 32c -len 400000` on 256 | `256, 256, 4294901760, ...` |
| `IconCheck 256` (MetalUI `App`, `SDLPlatform`) | `[256x256]` |
| `IconCheck 16,32,256`, before / after the window opened (no fix) | `[16x16]`, both |
| MetalCreator-0.1.0-linux-aarch64 tarball under Xvfb | `nitems=65538 w=256 h=256` |

So the one-256 case was never broken (xprop's formatter printed nothing; `WI-A`); the real defect was SDL ignoring alternates on X11 (`WI-B`).
SDL's `X11_SetWindowIcon` (release-3.4.16, `src/video/x11/SDL_x11window.c:1095`) writes `window->icon` alone.

## 2. The fix

`mui_x11_set_net_wm_icon` (`SDLBridge.c`), called by `mui_window_set_icon`: under the x11 driver and more than one image, write every image's
(w, h, ARGB) record through a dlopened libX11 under the request limit (`WI-B`, `WI-C`).

## 3. Pins and mutations

Tests (`Backends/SDL/Tests/MetalUISDLTests/SDLIconTests.swift`): W1 `theX11IconPropertyListsEveryImageAsWidthHeightArgb`, W2
`theX11IconPropertyDropsAnImageThatDoesNotFitTheRequest`, W3 `theX11PropertyIsWrittenOnlyOnX11ForMoreThanOneSize`; CI arm `IconCheck` + `check.sh`.
Each mutation applied to `SDLBridge.c`, `SDLIconTests` run in the Linux image under Xvfb with `SDL_VIDEO_DRIVER=x11`, restored after:

| Mutation | Reddened |
|---|---|
| MW1 ARGB written as RGBA | W1 (`property == ...`) |
| MW2 alternates skipped (`i < 1`) | W1 (`total == 2 + 4 + 2 + 9`) |
| MW3 request budget ignored | W2 (and the run aborted on an out-of-bounds write) |
| MW4 `count < 2` guard removed | W3 (two issues) |
| MW5 the `mui_window_set_icon` call removed (the fix reverted) | W3; and the CI arm reads `[16x16]` twice |

The driver check itself (`strcmp(driver, "x11")`) is redundant under SDL, whose offscreen driver has no Display property: not separately pinned.

## 4. Not verified

Wayland, and a real GNOME session's alt-tab and dock (human check `WI`). The macOS suite does not build `Backends/SDL`.

## 5. Counts

Root `swift package clean; swift build --build-system native --build-tests; swift test --build-system native --no-parallel`: **4787 tests in 12 suites
passed**, `FR-J no-argument frame: succeeded=true`. `Backends/SDL` in the arm64 Linux image (`METALUI_REQUIRE_GPU=1`, `swift test --scratch-path`): **31 + 342 passed**.
