# Window and application activation - decisions

Rulings for `Window.makeKeyAndOrderFront()`, `App.activate()` and the public `Color(hex:)`. Prefix `WA-`.
Branch `feat/mf-activate` from master `65e300a0`. **Nothing is published** (`BS-H`). **Next unused: `WA-D`.**
Why: MetalFlow shows macOS notifications; clicking one must bring the existing window forward. It is never called unprompted.

## WA-A - two defaultless requirements, two public verbs

**Ruling.** `PlatformWindow.orderFrontAndMakeKey()` and `Platform.activate()` are requirements with **no default**, so a conformer that forgets one fails to compile (CLAUDE.md, `PlatformWindow`'s defaultless requirements). `Window.makeKeyAndOrderFront()` (`@MainActor` with the rest of `Window`) calls the first; `App.activate()` calls the second. They are two verbs, not one: ordering a window front does not activate the application (AppKit's `makeKeyAndOrderFront` on an inactive app leaves the app behind), and activating the application brings no particular window. A notification click calls both.
- AppKit: `AppKitWindow` does `deminiaturize(nil)` when `isMiniaturized`, then `makeKeyAndOrderFront(nil)`; `AppKitPlatform.activate()` is `NSApplication.shared.activate(ignoringOtherApps: true)`, the call `run()` already makes (`AppKitPlatform.swift`): the deployment target predates `NSApp.activate()`, and `ignoringOtherApps` is what a user-initiated response needs.
- SDL: `SDLWindow.orderFrontAndMakeKey()` is `mui_window_raise` (`SDL_RestoreWindow` when minimised, then `SDL_RaiseWindow`; the existing single-instance raise, `SN-H`). SDL has no application-level activation, so `SDLPlatform.activate()` raises the focused window, else the lowest-id one, and does nothing with no window. A window manager may refuse to steal focus and flash the taskbar instead (a documented platform constraint, human check WA4).
- Headless (`HT-X` 1): `HeadlessPlatformWindow.orderFrontAndMakeKey()` counts the call (`orderFrontCalls`), clears `isMiniaturized`, and sets `isFrontmost` and `isKey`; `performWindowAction(.minimize)` now sets `isMiniaturized`, so the restore is observable. `HeadlessPlatform.activate()` counts (`activateCalls`).
- Every test fake and guard fixture conforming to the two protocols gained the member (`FakePlatformWindow`, `FakePlatform`, `PortableFakeWindow`, the four SDL test platforms, twelve guard files).
**Class.** M (MetalUI-only): SwiftUI has no equivalent call (`openWindow` makes windows). Inventory family `window-activation`.
**Pins.** `makeKeyAndOrderFrontReachesThePlatformWindow`, `makeKeyAndOrderFrontRestoresAMinimisedWindow`, `appActivateReachesThePlatform` (`WindowActivationTests`); `aConformerWithoutTheActivationRequirementsDoesNotCompile` (guard 1.3, `AppShellSeamCompileGuards`); `theActivationApiAndColorHexAreSpellableFromOutside` (`WindowActivationCompileGuards`). Migration rows in `docs/migration.md`.
**Cost if wrong.** A requirement a third-party conformer must add (an empty body is honest where it cannot).

## WA-B - `Color(hex:)` is public

**Ruling.** `Color.init(hex: UInt32)` (internal until now) is public: an opaque gamma-encoded sRGB colour from `0xRRGGBB`, bits above 24 ignored. For an alpha, `.opacity(_:)` on the result or `Color(Hsla.rgb(0x1E90FF, alpha: 0.5))`. SwiftUI has no such initialiser (it has `Color(.sRGB, red:green:blue:opacity:)`), so it is M, not a divergence from a SwiftUI spelling. Behaviour unchanged. Pin: the plain-import guard above (spelling), existing colour tests (value).

## WA-C - the check is a look

**Ruling.** Which window is frontmost and key is invisible to the suite; group `WA` in `docs/verification/human-checks.md` (WA1-WA4) is the check. The tests pin only that the verbs reach the platform.

## Mutations (run on this branch; each reverted)

Each applied to the committed source, the named tests run under `--build-system native`, then restored (`git checkout`).

| mutation | reddened |
|---|---|
| `Window.makeKeyAndOrderFront()` body emptied | `makeKeyAndOrderFrontReachesThePlatformWindow`, `makeKeyAndOrderFrontRestoresAMinimisedWindow` |
| `App.activate()` body emptied | `appActivateReachesThePlatform` |
| `HeadlessPlatformWindow.orderFrontAndMakeKey()` stops clearing `isMiniaturized` | `makeKeyAndOrderFrontRestoresAMinimisedWindow` only |
| `public` dropped from `Color.init(hex:)` | `theActivationApiAndColorHexAreSpellableFromOutside` (fixture error at `Color(hex:)`) |
| `extension Platform { public func activate() {} }` | `aConformerWithoutTheActivationRequirementsDoesNotCompile` (platform arm) |
| `extension PlatformWindow { public func orderFrontAndMakeKey() {} }` | the same guard (window arm) |

Not mutated: `public` dropped from `Window.makeKeyAndOrderFront()`/`App.activate()` (the same guard's fixture would redden); the AppKit and SDL bodies (no window server / window manager, see Carried).

## Carried

- `Window.makeKeyAndOrderFront()` does not change `controlActiveState` itself; the platform reports it back through `onControlActiveStateChange` as for a user click.
- No `Window.isKey`/`isMiniaturized` readers are public (nothing asked); the headless window exposes them.
- SDL cannot activate an application; `SDLPlatform.activate()` is the nearest honest answer. The SDL tests (offscreen) do not exercise `orderFrontAndMakeKey()` (no window manager); `orderFrontCalls` on `SDLWindow` is recorded for a later test.
- AppKit's two bodies are pinned by no test (`AI-K`'s reason: a headless run has no window server); human checks WA1-WA3 are their only check.
