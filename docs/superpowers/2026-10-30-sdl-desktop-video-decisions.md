# SDL desktop video and dialogs - decisions

Rulings for the SDL desktop items XP-G33 and XP-G34. Prefix `VD-`. Written in parallel: VD-A..VD-E (XP-G33, the Linux image) and VD-F..VD-G (XP-G34, file dialog filter names).
Branch `feat/sdl-desktop-video` from master `cc8995d3`. **Nothing is published** (`BS-H`). **Next unused: `VD-H`** (VD-A..VD-E are XP-G33's).

## VD-F - `ContentType.localizedDescription`

**Ruling.** `ContentType` gains `public let localizedDescription: String?`, UTType's spelling (UniformTypeIdentifiers declares `localizedDescription: String?` as a get-only property; SwiftUI's `fileImporter` takes `[UTType]`), settable through an additive `init(_:conformingTo:filenameExtensions:localizedDescription:)` parameter defaulting to `nil` (UTType has no such initialiser: the registry supplies it, MetalUI has none). `PlatformFileType.localizedDescription: String?` joins its initialiser the same way, filled at the one mapping site (`ContentType.platformFileType`). Built-ins carry English text: `item` "Item", `data` "Data", `text` "Text", `plainText` "Plain text", `utf8PlainText` "Plain text (UTF-8)", `url` "URL", `fileURL` "File URL", `json` "JSON" (MetalUI declares no image types). **The description is no part of `==` or `hash(into:)`** (a custom `==` over identifier, conformance and extensions): UTType equates by identifier, and a label must not split a `Set`/dictionary key. Class stays D (the existing `content-type-extensions` row, amended with the field); divergence 129's text gains the filter name, no new label.
**Pin.** `aContentTypesDescriptionReachesTheSeamAndStaysOutOfEquality` (2.20).
**Cost if wrong.** A source-compatible additive field; the equality carve-out is the part to revisit.

## VD-G - the SDL filter name

**Ruling.** `SDLWindow.dialogFilters` names a filter `"<description> (*.a;*.b)"` when the type has a non-empty description and `"*.a;*.b"` when not, **never the identifier** (MetalCreator XP-G34: `com.metalcreator.mcgraph` showed raw on Linux). The pattern is unchanged (`a;b`). SDL3 passes the filter name to the platform dialog verbatim (the GTK portal/zenity and the Windows common dialog show it as given; SDL's own "All files" is the app's to add), so MetalUI builds the whole label. AppKit is unchanged (UTType). Types without extensions still filter nothing.
**Pin.** `sdlFilterNamesUseTheDescriptionAndNeverTheIdentifier` (1.13b, `Backends/SDL`); 1.13 updated to the bare-glob names.
**Cost if wrong.** A label string.

## VD-A - the image's SDL has the desktop drivers

**Ruling (XP-G33).** `Backends/SDL/linux/Dockerfile` builds SDL `release-3.4.16` with `-DSDL_X11=ON -DSDL_X11_SHARED=ON -DSDL_WAYLAND=ON -DSDL_WAYLAND_SHARED=ON -DSDL_WAYLAND_LIBDECOR=ON` and **no `SDL_UNIX_CONSOLE_BUILD`** (MetalCreator's tarball and AppImage bundle the image's `libSDL3.so.0`, which had only dummy/evdev/offscreen and failed on a desktop with "No available video device"). `SDL_*_SHARED=ON` is SDL's default and kept explicit: the client libraries are `dlopen`ed at run time, the bundled library hard-depends on none of them. Added packages: `libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev wayland-protocols libegl-dev libdecor-0-dev pkg-config`. **`libxtst-dev` is the one the brief's list lacked**: with `SDL_X11=ON` cmake stops with "Couldn't find dependency package for XTEST" (measured), which is the wanted behaviour, a missing dependency fails the configure instead of dropping a driver. Offscreen and dummy stay, audio stays off, `ENV SDL_VIDEO_DRIVER=offscreen` stays (CI unchanged).
**Cost if wrong.** An image that is a little larger; an app that must not set the variable.

## VD-B - the image proves the drivers

**Ruling.** `Backends/SDL/scripts/check-video-drivers.c` (in `scripts/` because `.dockerignore` admits only that directory) calls `SDL_GetNumVideoDrivers`/`SDL_GetVideoDriver` (no `SDL_Init`, no display) and exits 1 unless `x11`, `wayland`, `offscreen` and `dummy` are all listed; a Dockerfile `RUN` compiles and runs it right after the SDL install. A first attempt grepped `strings libSDL3.so.0` for the names and failed on a correct build (the names are not standalone strings), so the probe is the instrument. Measured output in the image: `SDL 3.4.16 video drivers (5): wayland x11 offscreen dummy evdev`.

## VD-C - headless without the variable (measured, `HeadlessLaunchCheck`, `SDLPlatform(options: .headless)`)

Binary built once in the new image, run against both the old image's `libSDL3` (`metalui-portable`, console build) and the new one:

| environment | old image | new image |
|---|---|---|
| `SDL_VIDEO_DRIVER` unset, no `DISPLAY`/`WAYLAND_DISPLAY` | `SDL_Init: No available video device` | `SDL_Init: No available video device` (plus `XDG_RUNTIME_DIR is invalid or not set` twice, SDL's Wayland probe) |
| unset, `DISPLAY=:99` (no server) | `No available video device` | `No available video device` |
| `SDL_VIDEO_DRIVER=x11`, no server | `SDL_Init: x11 not available` | `SDL_Init: x11 not available` |
| `SDL_VIDEO_DRIVER=offscreen` | `task ran=true iterations=1` | `task ran=true iterations=1` |
| Xvfb on `:99`, driver unset | n/a | `task ran=true iterations=1` (X11 driver auto-selected) |
| Xvfb on `:99`, `SDL_VIDEO_DRIVER=x11` | n/a | `task ran=true iterations=1` |

**Ruling.** Unset-env headless fails exactly as before, so **no code change**: `Options.headless` hides windows and renders offscreen but does not choose a video driver (the driver stays the environment's, `IC-J`), and headless CI must set `SDL_VIDEO_DRIVER=offscreen` (the image does). A desktop app with no display fails loudly rather than silently using offscreen; **SDLPlatform must never fall back to offscreen by itself for a desktop launch**. Noted, not built: with `options.rendersOffscreen && hidesWindows` and no display variable, `SDLPlatform` could set `SDL_HINT_VIDEO_DRIVER=offscreen` at normal priority before `SDL_Init` (an exported variable would still win, as `AP-A` does for the app id). Unrequested, so left.

## VD-D - CI equivalence

**Ruling.** The image was built with the CI invocation's context and file (`docker build -f Backends/SDL/linux/Dockerfile Backends/SDL`, the `docker/build-push-action` step of `sdl-gpu-linux.yml`, tag `metalui-portable` there) and `swift build` + `swift test --scratch-path /tmp/build` (the CI step's first two commands, `METALUI_REQUIRE_GPU=1`, lavapipe) run inside it with the checkout mounted at `/work`: `Test run with 335 tests in 19 suites passed` (this worktree, including XP-G34's uncommitted changes at that moment). Image: 6.94 GB before (`metalui-portable:latest`, content 1.65 GB), 7.03 GB after (content 1.67 GB): +0.09 GB disk, +0.02 GB compressed. Workflows: only `sdl-gpu-linux.yml` builds this Dockerfile; its buildx gha cache is keyed by `scope` (portable-arch) and layer content, so the changed `RUN` layers rebuild once and cache afterwards, no key edit needed; the new `COPY scripts/check-video-drivers.c` comes from the context `.dockerignore` already admits. **Not run locally** (need the macOS-recorded fixtures, absent from a worktree): `PortableReplay`, `DemoCapture`, the consumer-build step and Jotter. They do not touch the drivers; CI is their evidence.

## VD-E - docs

**Ruling.** `docs/getting-started.md` (what a Linux machine needs; "Shipping on Linux"), `docs/packaging.md` (new "Linux: SDL in the image" section) and `docs/testing.md` (headless needs `SDL_VIDEO_DRIVER=offscreen`) say: the image's SDL has X11, Wayland, offscreen and dummy; a consumer bundles `libSDL3.so.0` from the image; X11/Wayland/libdecor are `dlopen`ed from the user's system; headless runs set the variable. Unverified: a real Wayland compositor and a hardware X server.
