# SDL3 platform — design

**Status: implemented** on `feat/sdl-platform` (record §37); roadmap item 8 of
`plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `SP-`
(`SP-A`…`SP-C`, next `SP-D`; rulings here).

## Rulings

### SP-A — `SDLPlatform` and `SDLWindow` in `Backends/SDL`

`MetalUISDL` gains `SDLPlatform: Platform` and `SDLWindow: PlatformWindow`,
each window drawing through its own `SDLWindowRenderer` (`RS-D`).

- **Events are flattened in C** (`mui_poll_event`, `mui_wait_event`): one
  `MUIEvent` struct per SDL event MetalUI reads — left button down/up with
  SDL's click count, motion, wheel, key down/up with modifiers and repeat,
  window resized / pixel size / display scale / exposed (all `onResize`),
  close requested, system theme changed, quit — so Swift never reads SDL's
  event union. `mui_push_event` builds the SDL event back from one, which is
  how the tests drive the real translation path.
- **Geometry:** `contentSize` is `SDL_GetWindowSize` (points; windows are
  created with `SDL_WINDOW_HIGH_PIXEL_DENSITY`), `scaleFactor`
  `SDL_GetWindowPixelDensity`; pointer positions are points, top-left
  origin, as `MetalUI` expects.
- **Appearance** is the system theme (`SDL_GetSystemTheme`); SDL has no
  per-window appearance. A theme change reaches every window.
- **Display link:** `run()` dispatches events and, while any window's link
  is running, ticks it every pass — the swapchain acquire inside the frame
  paces the loop to the display; with every link paused it sleeps in
  `SDL_WaitEvent` (250 ms timeout). Closing the last window, `SDL_EVENT_QUIT`
  or `stop()` ends it.

### SP-B — No accessibility, explicitly

`publishAccessibilityTree` publishes nothing and `onAccessibilityRequest` is
never called: AT-SPI (Linux) and UI Automation (Windows) are roadmap item
13, and `AB-R` forbids a default implementation, so the stub is written out
on `SDLWindow`. **A divergence**: a MetalUI app on SDL is invisible to
screen readers until item 13.

### SP-C — Keys and wheels in AppKit's vocabulary

`Keymap` spells bindings in the characters AppKit's `NSEvent` reports, so
`SDLKeys` maps SDL keycodes onto them: printable keycodes are their Unicode
scalar (letters lowercase; shift uppercases `characters`); backspace is
`\u{7f}` (AppKit's delete), forward delete `\u{f728}`, and arrows, home,
end, page up/down and F1–F12 the private-use function-key characters
`Keymap.namedKeys` reads. A wheel line is 10 points, AppKit's
`pointsPerScrollLine`, with SDL's direction (natural scrolling already
applied) taken as AppKit's `scrollingDelta` sign.

**Not handled** (and recorded as open): text input and IME — `characters`
is derived from the keycode, not from `SDL_EVENT_TEXT_INPUT` (roadmap item
14); right and middle buttons (MetalUI has no event for them); the wheel's
sign and the `characters` of option/control combinations are
unverified against real hardware — a human look, not a test.

## Tests

`SDLPlatformTests` (9 with the renderer's 3): the key table as literals
`Keymap.namedKeys` also spells; a hidden window's size, title, scale factor
and renderer; six synthetic events arriving as the right `InputEvent`s;
resize, theme and close reaching the window; the run loop ticking a running
link and not a paused one, and ending when the last window closes (under an
iteration budget, so a loop that never ends fails by count).
