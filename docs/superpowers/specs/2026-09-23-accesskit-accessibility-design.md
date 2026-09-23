# Accessibility off Apple through AccessKit — design

**Status: implemented** on `feat/accessibility` (record §44); roadmap item 13
of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `AX-`
(`AX-A`…`AX-D`, next `AX-E`; rulings here). Supersedes `SP-B`.

## Problem

`SDLWindow.publishAccessibilityTree` published nothing (`SP-B`): a MetalUI
app on Linux or Windows was invisible to Orca and Narrator. MetalUI already
builds a platform-neutral `AccessibilityTree` every frame once a client is
present (`AB-`), and already answers `AccessibilityRequest`s (`.activate`,
`.press`, `.focus`, `.increment`, `.decrement`). What was missing is a bridge
from that tree to AT-SPI (Linux) and UI Automation (Windows).

## Rulings

### AX-A — AccessKit's C bindings, fetched, not vendored

The bridge is [AccessKit](https://github.com/AccessKit/accesskit) (Rust,
Apache-2.0/MIT; the C bindings `accesskit-c` 0.23.0, BSD-3-Clause for the
Chromium-derived parts). One tree update format drives AT-SPI, UI Automation
and NSAccessibility — the three platform adapters are AccessKit's, not ours.

- **Fetched by a script**, `Backends/SDL/scripts/fetch-accesskit.py`: the
  release zip (65 MB, SHA-256 pinned in the script), unpacked into the
  gitignored `Backends/SDL/.accesskit/` (or `$ACCESSKIT_DIR`), the host's
  prebuilt static library copied to `.accesskit/lib`, and `accesskit.pc`
  written for pkg-config (Linux, macOS; frameworks and `-lm` in its `Libs`).
  On Windows it prints the `-Xcc -I` / `-Xswiftc -L` flags instead. The
  release ships libraries for macOS arm64/x86_64, Linux x86_64 and Windows
  x64; **Linux aarch64 has none**, so the script builds the Rust sources in
  the same archive with `cargo build --release --locked`.
- **Not vendored**, unlike FreeType, HarfBuzz and SheenBidi: it is Rust, and
  the root package must build with SwiftPM alone. It is a dependency of the
  **`Backends/SDL` package only** — the root package never sees it.
- `CAccessKit` is a `systemLibrary` target (`pkgConfig: "accesskit"`); the
  Windows system libraries the Rust library needs (`bcrypt`, `ntdll`,
  `propsys`, `runtimeobject`, `uiautomationcore`, `userenv`, `ws2_32`,
  `ole32`, `oleaut32`, `user32`, `advapi32`) are `linkedLibrary` settings on
  `MetalUISDL`, conditioned on Windows.
- **CI**: the Linux image (`Backends/SDL/linux/Dockerfile`, build context now
  `Backends/SDL`) bakes it into `/opt/accesskit` — installing rustup and gcc
  on aarch64 only — and sets `PKG_CONFIG_PATH`; the Windows job runs the
  script and passes its paths. Building `Backends/SDL` locally now needs
  `python3 scripts/fetch-accesskit.py` once and
  `PKG_CONFIG_PATH=$PWD/.accesskit` on every `swift build`/`swift test`.

### AX-B — The translation is a pure value

`AccessKitSnapshot.translate(_:title:scale:ids:)` turns an
`AccessibilityTree` into AccessKit's vocabulary with no C in sight:

- A **window node** (id 0, role `window`, labelled with the window title) is
  the root; MetalUI's roots are its children.
- **Ids** come from `AccessKitIDs`: a MetalUI node keeps its number for as
  long as it exists; a node that leaves the tree is forgotten and **its number
  is never reused** (a screen reader may still hold it).
- **Roles:** `group` → `genericContainer`, `button` → `button`, `staticText`
  → `label`, `image` → `image`, `table` → `table`, `row` → `row`.
- **Actions:** `press` → `click`, `increment`/`decrement` as themselves, and
  `focus` on every `isFocusable` node. `isEnabled == false` → disabled,
  `isSelected` → selected; label and value carried verbatim.
- **Bounds** are MetalUI's frame (points, window content origin) times the
  window's pixel density — AccessKit's coordinates are physical pixels.
- **Focus** is the focused node's number, or the window's when nothing is
  focused.
- Nodes are listed depth first, parents before children.

### AX-C — One adapter per SDL window, requests on the main thread

`AccessKitAdapter` owns the platform adapter for one `SDLWindow`:
`accesskit_unix_adapter_new` on Linux (AT-SPI needs no window handle; the
window's screen rectangle is pushed with `set_root_window_bounds` on every
resize), `accesskit_macos_subclassing_adapter_for_window` over SDL's
`NSWindow` on macOS (with SDL's `SDL3Window` class given AccessKit's focus
forwarder once per process), and `accesskit_windows_subclassing_adapter_new`
over the `HWND` on Windows. SDL hands out the native handle through window
properties (`mui_window_native_handle`).

- **Publishing** stores the snapshot and, if it changed, calls
  `update_if_active` with a factory that builds a full tree update from it;
  queued events (macOS, Windows) are raised at once. An inactive adapter
  costs one comparison.
- **AccessKit calls back** — on Linux from its own thread — for activation
  (a screen reader appeared: answer the current snapshot, queue `.activate`)
  and actions (queue the action and its node number, free the request). The
  snapshot and queue sit behind a lock; the callbacks do nothing else.
- **Delivery is on the main thread**: each callback pushes an SDL user event
  (`mui_wake_for_accessibility`, safe from any thread), which the run loop
  dispatches as `MUI_EVENT_ACCESSIBILITY`; the window drains the queue,
  maps numbers back to `AccessibilityRequest`s (an unknown number is
  dropped), and calls `onAccessibilityRequest`. Requests that arrive before
  `Window` installs its handler are **parked** and delivered when it does, as
  the AppKit bridge parks `.activate` (`AB-B`).
- The adapter is released before the SDL window is destroyed, like the
  renderer.

### AX-D — What is tested, and what is a human look

- The translation, field by field, and the id rule — pure tests on every
  platform.
- The request path — a real hidden SDL window, the callbacks driven the way
  AccessKit drives them (`simulateAccessKitRequest`), the wake read back out
  of SDL's queue — on every platform.
- **macOS end to end**: an NSAccessibility client (dynamic lookup of the
  informal `accessibilityChildren`/`accessibilityRole`/`accessibilityTitle`/
  `accessibilityValue`, as a client's selectors would) walks the SDL
  window's content view; asking activates AccessKit, MetalUI hears
  `.activate`, and the whole published tree comes back with MetalUI's roles,
  labels (AppKit's title) and values.
- **Not tested: AT-SPI and UI Automation end to end.** That needs a session
  D-Bus with the AT-SPI registry (Linux) or a UIA client (Windows); both
  adapters share `treeUpdate` with the macOS one, so what is unpinned is the
  platform half AccessKit owns. Orca and Narrator reading a MetalUI SDL window
  are **human looks**, owed.

## Not in scope

Text-editing accessibility (caret, selection ranges, `TextField`'s role)
arrives with item 14's text input. `rowCount`/`rowIndex` are not carried
(AccessKit derives table structure from children). Live regions,
descriptions and keyboard shortcuts have no MetalUI source yet.
