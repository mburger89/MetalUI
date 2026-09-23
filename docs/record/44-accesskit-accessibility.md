# 44 — Accessibility off Apple through AccessKit, 2026-09-23

Branch `feat/accessibility`, from `feat/bidi` (PR #24, record §43). Spec:
`docs/superpowers/specs/2026-09-23-accesskit-accessibility-design.md`,
rulings `AX-A`…`AX-D` (next `AX-E`). Roadmap item 13. Supersedes `SP-B`.
The user chose AccessKit over hand-written AT-SPI/UIA bridges.

## What changed

- `Backends/SDL/scripts/fetch-accesskit.py` (`AX-A`): accesskit-c 0.23.0,
  SHA-256-checked, into the gitignored `.accesskit/` (or `$ACCESSKIT_DIR`),
  with `accesskit.pc`; cargo on hosts with no prebuilt library.
- `CAccessKit` system-library target; `MetalUISDL` depends on it, and on
  eleven Windows system libraries conditioned on Windows.
- `SDLBridge`: `mui_wake_for_accessibility` (a registered SDL user event,
  translated to `MUI_EVENT_ACCESSIBILITY`), `mui_window_native_handle`
  (`NSWindow`/`HWND` from SDL's window properties), `mui_window_position`.
- `MetalUISDL`: `AccessKitTree.swift` (`AccessKitSnapshot`, `AccessKitIDs`,
  the translation, `AX-B`) and `AccessKitAdapter.swift` (the three platform
  adapters, the C callbacks, the tree-update builder, `AX-C`). `SDLWindow`
  owns one adapter, publishes through it, parks and delivers requests.
- CI: the Linux image's build context is `Backends/SDL` (a `.dockerignore`
  admits only `scripts/`); it installs python3, curl and — on aarch64 —
  rustup and gcc, and bakes AccessKit into `/opt/accesskit`. The Windows job
  fetches it and passes `-I`/`-L`.

## Measured

- macOS (SDL 3 Cocoa): `Backends/SDL` 21 fixture tests + 14
  `MetalUISDLTests` (5 new) pass.
- Linux aarch64 (`swift:6.4-noble` + the new image, AccessKit built by
  cargo): builds; 21 + 13 pass (the NSAccessibility test is macOS-only).
- **AccessKit's macOS elements report MetalUI's label as
  `accessibilityTitle`, not `accessibilityLabel`** — found by the first run
  of the end-to-end test, which walked labels and found none; the test reads
  the title.
- The first Linux image build failed: cargo found no `cc` in the Swift
  image; gcc is installed on the aarch64 path.

## Mutations (`--filter AccessKit`, macOS)

| # | Mutant | Reddens |
|---|---|---|
| M1 | `focus` action not added for focusable nodes | `aMetalUITreeTranslatesToAccessKitsVocabulary` |
| M2 | button emitted with AccessKit's `label` role | `anNSAccessibilityClientReadsThePublishedTree` |
| M3 | label not set in the tree update | `anNSAccessibilityClientReadsThePublishedTree` |
| M4 | `pumpEvents` does not drain every window | **green** — the wake event's dispatch arm already delivers; the drain was redundant and is **deleted** |
| M4b | the `MUI_EVENT_ACCESSIBILITY` arm does `break` | `accessKitRequestsReachTheWindowInOrder`, `anNSAccessibilityClientReadsThePublishedTree` |
| M5 | installing the handler does not deliver parked requests | `accessKitRequestsReachTheWindowInOrder` |
| M6 | callbacks push no wake event | `accessKitRequestsReachTheWindowInOrder` |
| M7 | a forgotten id's number is handed out again | `accessKitIDsAreStableAndNeverReused` |
| M8 | bounds not scaled to physical pixels | `aMetalUITreeTranslatesToAccessKitsVocabulary` |

M4 is the "green mutant may be the correct spelling" case: two paths
delivered, one is gone, and M4b shows the survivor is pinned.

## Open

- **Human looks:** Orca on Linux and Narrator on Windows reading a
  `MetalUISDLDemo` window; VoiceOver on the SDL window on macOS (the test
  reads the tree, not speech).
- AT-SPI and UI Automation end to end are untested (`AX-D`); they share
  `treeUpdate` with the macOS path.
- Text-editing accessibility waits for item 14.
