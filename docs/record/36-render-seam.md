# 36 — Render seam, 2026-09-23

Branch `feat/render-seam`, from `feat/text-seam` (PR #17, record §35).
Spec: `docs/superpowers/specs/2026-09-23-render-seam-design.md`, rulings
`RS-A`…`RS-D` (next `RS-E`). Roadmap item 7.

## What changed

- `MetalUIPlatform`: portable, a product; `WindowRenderer`;
  `PlatformWindow.renderer` replaces `surface`.
- `MetalUIRender`: `MetalWindowRenderer`; depends on `MetalUIPlatform`.
- New `MetalUIAppKit` (macOS): the AppKit platform, moved.
- `Window` draws through `platformWindow.renderer`; `App` hands its
  `Renderer` to `AppKitPlatform(renderer:)`.
- `Experiments/SDLGPU/Portable` → `Backends/SDL` (package `MetalUISDL`),
  with `mui_renderer_*` and `SDLWindowRenderer`; CI, Dockerfile, README and
  the Apple-half `Replay` repointed.

## Measured

- Root: **1686** unchanged (`PlatformTests` now reaches the AppKit layer
  surface through `AppKitWindow` and checks the window's renderer wraps it).
- Linux container: 486 + 22.
- `Backends/SDL`: 21 + 3 locally (SDL Metal); `PortableReplay` over freshly
  recorded fixtures PASS, frame 4 0 px.

## Found in CI

The first Linux run of `MetalUISDLTests` (llvmpipe) **crashed** — a worker
thread jumping to an unmapped address, two devices into the run. The
replay bridge paired each device with `SDL_Init`/`SDL_Quit`, and SDL3's
`SDL_Quit` tears down every subsystem whoever else holds it: destroying one
device unloaded the Vulkan loader under the next device's Mesa threads.
macOS (Metal) and Windows (D3D12) tolerated it. Each device now holds one
reference on the video subsystem (`SDL_InitSubSystem`/`SDL_QuitSubSystem`).

## Mutations

| # | Mutant | Reddens |
|---|---|---|
| R1 | Metal: atlas uploaded after encode | `aWindowUploadsTheAtlasBeforeEncodingSoTheFirstFrameOfTextIsNotBlank`, `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor` |
| R2 | `Window` does not stay dirty when there is no drawable | `skippedFrameKeepsDirtyStateAndRetriesSuccessfully` |
| R3 | SDL: atlas never re-uploaded after the first frame | `theAtlasPersistsAndUpdatesAcrossFrames` |
| R4 | SDL: dirty rect not cleared | `theAtlasPersistsAndUpdatesAcrossFrames` |
| R5 | SDL: glyph runs skipped | `aWindowRendererFrameIsTheReplayPathsFrame`, `theAtlasPersistsAndUpdatesAcrossFrames` |

## Counts

Root **1686** (no test added; one extended). `Backends/SDL`: 21 + 3.
