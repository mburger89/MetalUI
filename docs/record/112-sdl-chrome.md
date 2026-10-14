# 112 — SDL custom window chrome (item S1)

Branch `feat/sdl-custom-chrome` from `fb9a7e42`. User request 2026-10-02 (gpui-gap list), MetalCreator SDL-port gap 3.
Spec `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`; rulings `docs/superpowers/2026-10-13-sdl-chrome-decisions.md`
(`CW-A`…`CW-T`); human checks group `CW`. Divergences 175 and 276 amended, 425 and 426 added (range 425–434).

## Lane 1 (root)

The seam (four defaultless `PlatformWindow` requirements, `PlatformWindowAction`), `ChromeHitSnapshot`/`ChromeHit`/
`ChromeHitMap.carve`, `Window.drawsWindowControls`/`minimize()`/`toggleZoom()`/`isZoomed`, the carved drag regions
(`ChromeRegions.swift`), the `$windowcontrols` strip, the headless `Options.sdlChrome`, the demo `METALUI_CHROME_DEMO=1`.
3758 tests, 236 guards; the fourteen images 0 px. Details: `CW-Q`, `CW-R`.

## Lane 2 (`Backends/SDL`)

- `SDLBridge.c`/`.h`: `mui_window_set_bordered` (reads the flag back), `mui_window_set_hit_test` over a per-window
  `SDL_Mutex`-guarded `MUIChromeSnapshot` (at most 64 rects, state in the window's SDL properties, cleared before
  destroy), `mui_chrome_hit` (the C twin of `ChromeHitSnapshot.hit(at:)`), `mui_window_chrome_hit` (the callback's own
  body), counters, minimise/maximise/restore and the flag reads; fullscreen, maximise and restore events reach the
  resize handler.
- `SDLPlatform.swift`: `setTitleBarStyle` (borderless, deferred while fullscreen), `titleBarInsets` (32 band; 138 right,
  70 left under macOS; zero in fullscreen), `setWindowDragRegions` (publishes with the edges, installs only when
  needed), `performWindowAction`, `hasNativeWindowControls` `false`, `isZoomed`, `performTitleBarPress(clickCount >= 2)`
  toggles zoom, `performWindowDrag()` still `false`.
- `SDLChromeTests.swift` (20 tests; 12 gated off the offscreen driver) and the re-pinned `SDLAppShellTests` answer.
- `Backends/SDL` on macOS 30 + 145 passed; in `swift:6.4-noble` 30 + 142 passed (12 skipped by the offscreen driver).
- Measured in the image: the offscreen driver cannot change a border or install a hit test (`CW-S`). Windows: UTM
  unreachable, CI covers it; a real drag, edge, double-click or snap is group `CW`.
- Mutations: 22, results in `CW-T`; three survivors named there (one fixed by a stronger pin, one Linux-only killer,
  one unobservable defensive line).
- `docs/guides/cross-platform.md` states only the measured facts.

## Carried

Linux double-click zoom (`CW-I`, check CW6); divergence 427 reserved; Windows UTM and CI runs; the Record phase
(CLAUDE.md rule, README rows, counts) belongs to the merge.
