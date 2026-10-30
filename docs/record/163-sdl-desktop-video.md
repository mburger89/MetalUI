# 163. SDL desktop video drivers and dialog filter names (XP-G33, XP-G34)

Items `XP-G33` (MetalCreator gap: the image's `libSDL3.so.0` had only dummy/evdev/offscreen, so a bundled Linux app failed on a desktop with "No available video device") and `XP-G34` (MetalCreator gap: a Linux file dialog filter showed the raw type identifier), computed workflow task 2026-10-30, **not plan tasks**, on `feat/sdl-desktop-video` from master `cc8995d3`. Rulings `VD-A`..`VD-G` in `docs/superpowers/2026-10-30-sdl-desktop-video-decisions.md`, next `VD-H`. Commits `2b570983` (XP-G33), `1a6af601` (XP-G34), `760e9445` (verification fixes). Nothing pushed or published. Class `D` for the dialog filter (divergence 129 amended, no new label, next stays 206), `M` for the image.

## 1. What was built

- **Image drivers** (`VD-A`): `Backends/SDL/linux/Dockerfile` builds SDL `release-3.4.16` with X11, Wayland and libdecor ON (`*_SHARED=ON`, so the client libraries are `dlopen`ed and the bundled `libSDL3.so.0` hard-depends on none; `ldd` confirms) and no `SDL_UNIX_CONSOLE_BUILD`. Added the `-dev` packages; `libxtst-dev` was the one the brief lacked (cmake stops with "Couldn't find dependency package for XTEST", the wanted failure). `ENV SDL_VIDEO_DRIVER=offscreen` stays, so CI is unchanged.
- **Driver check** (`VD-B`): `Backends/SDL/scripts/check-video-drivers.c` lists drivers with `SDL_GetVideoDriver` (no `SDL_Init`) and exits 1 unless x11, wayland, offscreen and dummy are all present; a Dockerfile `RUN` runs it after the SDL install. A first attempt that grepped `strings libSDL3.so.0` failed on a correct build.
- **Headless without the variable** (`VD-C`): measured, no code change. `Options.headless` hides windows and renders offscreen but does not pick a video driver; headless CI sets `SDL_VIDEO_DRIVER=offscreen`. A desktop app must never fall back to offscreen by itself. Noted, not built: a hint set when headless options and no display variable.
- **Docs** (`VD-E`): `docs/getting-started.md`, `docs/packaging.md` (new "Linux: SDL in the image", with how to find `libSDL3.so.0` by `ldconfig -p`), `docs/testing.md`.
- **Dialog filter names** (`VD-F`, `VD-G`): `ContentType.localizedDescription: String?` (UTType's spelling; additive init parameter; built-ins carry English text; **excluded from `==` and `hash(into:)`**, the part to revisit), `PlatformFileType.localizedDescription` filled at `ContentType.platformFileType`. `SDLWindow.dialogFilters` names a filter `JSON (*.json)`, or bare `*.a;*.b` with no (or an empty) description, never the identifier. AppKit unchanged. Divergence 129 text and the `content-type-extensions` inventory row amended.

## 2. Measurements

| Environment (`HeadlessLaunchCheck`) | Old image | New image |
|---|---|---|
| driver unset, no `DISPLAY`/`WAYLAND_DISPLAY` | `No available video device` | same (plus `XDG_RUNTIME_DIR` notice twice) |
| unset, `DISPLAY=:99`, no server | `No available video device` | same |
| `SDL_VIDEO_DRIVER=x11`, no server | `x11 not available` | same |
| `SDL_VIDEO_DRIVER=offscreen` | task ran | task ran |
| Xvfb `:99`, driver unset / `=x11` | n/a | task ran (X11 auto-selected) |

New image driver line: `SDL 3.4.16 video drivers (5): wayland x11 offscreen dummy evdev`. Image 6.94 GB to 7.03 GB (content 1.65 to 1.67 GB). In-image `swift test --scratch-path /tmp/build` (`METALUI_REQUIRE_GPU=1`, llvmpipe/lavapipe): `Test run with 335 tests in 19 suites passed` (implementer and verifier). Not run locally: `PortableReplay`, `DemoCapture`, consumer build, Jotter (macOS-recorded fixtures absent from a worktree; CI covers them). Only `sdl-gpu-linux.yml` builds the Dockerfile; its gha cache rebuilds the changed layers once, no key edit.

## 3. Tests and counts

Root **4529 -> 4530** (+1, `aContentTypesDescriptionReachesTheSeamAndStaysOutOfEquality`, 2.20; existing expectations comparing `platformFileType` updated). `Backends/SDL` gains `sdlFilterNamesUseTheDescriptionAndNeverTheIdentifier` (1.13b), 1.13 updated. Guards unchanged (277, not re-tallied). `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 4. Mutations

| Mutant | Reddened |
|---|---|
| SDL filter name uses `type.identifier` | `sdlFilterNamesUseTheDescriptionAndNeverTheIdentifier`, `sdlFiltersCarryExtensionsAndATypeWithoutOneFiltersNothing` (re-run by verification, same) |
| described name drops the globs | `sdlFilterNamesUseTheDescriptionAndNeverTheIdentifier` |
| empty description not treated as none | `sdlFilterNamesUseTheDescriptionAndNeverTheIdentifier` |
| `platformFileType` drops the description | `aContentTypesDescriptionReachesTheSeamAndStaysOutOfEquality`, `aPlatformFileTypeCarriesIdentifierConformanceAndExtensions` |
| description added to `==` | `aContentTypesDescriptionReachesTheSeamAndStaysOutOfEquality` |
| Dockerfile `SDL_WAYLAND=OFF` | image build fails at the driver check ("libSDL3 lacks the wayland video driver"; verification) |
| "json has no description" | run failed, tests not captured (unrecorded) |

## 5. Verification

`swift package clean`, native build with tests, unfiltered `--no-parallel`, twice: `Test run with 4530 tests in 12 suites failed ... with 5 issues` (860.441 s and 891.513 s), `FR-J no-argument frame: succeeded=true deprecations=2`. The five are `appKitOpenDialogIsASheetWithTheDeclaredTypes`, `appKitSaveDialogCarriesTheNameTypesAndExportPrompt`, `appKitCancelledDialogArrivesAsQueuedInput`, `appKitDismissPresentationEndsTheSheetAndAnswersNothing`, `appKitSecondDialogWhileASheetIsUpAnswersFalse`, each failing on `turn { nsWindow.attachedSheet != nil }`. `ioreg` showed `CGSSessionScreenIsLocked = true` (a locked session is the plausible cause); `--filter AppKitPresentationTests` passes 9 of 9 on the same checkout; the branch's only change to that file is a fixture gaining a description. These are the five sheet tests that have failed on every locked-screen run since 2026-10-13 (records of S2, P1, S4+S8 and later), not this branch; the 4530 total matches the implementer's passing run. `CLAUDE.md` and `AGENTS.md` identical.

## 6. Carried

A real Wayland compositor and a hardware-GL X server are unmeasured (checks `VD1`, `VD2`); "the GTK portal and zenity show the name verbatim" (`VD-G`) is an assumption (`VD3`); the `ContentType` equality carve-out; the offscreen-hint idea of `VD-C`.
