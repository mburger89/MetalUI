# 37 — SDL3 platform, 2026-09-23

Branch `feat/sdl-platform`, from `feat/render-seam` (PR #18, record §36).
Spec: `docs/superpowers/specs/2026-09-23-sdl-platform-design.md`, rulings
`SP-A`…`SP-C` (next `SP-D`). Roadmap item 8.

## What changed

- `SDLBridge`: `mui_platform_init`, `mui_poll_event`/`mui_wait_event`/
  `mui_push_event` over a flat `MUIEvent`, `mui_window_*`,
  `mui_system_theme`, `mui_now`.
- `MetalUISDL`: `SDLPlatform`, `SDLWindow`, `SDLKeys`.
- Root: `MetalUICore` is a library product (the SDL platform builds
  `Size<Pixels>` and `Point<Pixels>`).

## Measured (locally, macOS, SDL 3 Metal driver)

`Backends/SDL`: 21 fixture tests + 9 `MetalUISDLTests` (3 renderer, 6
platform) pass. Linux and Windows are measured by the SDL workflow.

## Mutations

| # | Mutant | Reddens |
|---|---|---|
| P1 | up arrow spelled as down | `sdlEventsArriveAsMetalUIInput`, `sdlKeysSpellWhatKeymapBinds` |
| P2 | shift does not uppercase `characters` | `sdlKeysSpellWhatKeymapBinds` |
| P3 | wheel lines not scaled | `aWheelLineIsTenPoints`, `sdlEventsArriveAsMetalUIInput` |
| P4 | paused links tick too | `theRunLoopTicksLinksAndEndsWhenTheLastWindowCloses` |
| P5 | close does not remove the window | `theRunLoop…` — **first a 900 s hang**: the test's tick cap never fires once every link stops; `run(maxIterations:)` now bounds it |
| P6 | mouse down reports no click count | `sdlEventsArriveAsMetalUIInput` |

## Open

- Real-hardware looks: wheel direction, option/control `characters`.
- Accessibility (`SP-B`, item 13), text input (item 14).
