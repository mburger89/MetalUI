# Record 247: onKeyPress during an IME composition (Alloy gap G14)

Branch `fix/onkeypress-during-ime`. Ruling `KF-AB` in `docs/superpowers/2026-10-08-key-focus-decisions.md` (next `KF-AC`).

## 1. What was asked and found

Alloy's quick-open list handles ↑, ↓ and Esc with `.onKeyPress` on a field; during CJK composition those keys belong to the input method. The first design, a `Window` gate on the focused field's composition, was dropped after the probe.

- **Probe** `docs/probes/swiftui-onkeypress-marked-text.swift`: marked text set on the SwiftUI field editor, ↓ and Esc posted; `onKeyPress` heard both, with and without marked text, and Esc did not cancel the composition. **No real IME was attached**, so this shows a declined key is delivered, nothing about what a real IME consumes.
- **macOS:** `MetalHostView.keyDown` hands a non-⌘ key to `inputContext.handleEvent` first, so consumed keys never arrive; declined ones are delivered as SwiftUI does. No change; pinned.
- **SDL:** keys and `TEXT_EDITING` arrive separately, so consumed keys reached `onKeyPress` and the Keymap. Fixed in the backend.
- Rejected: `KeyPress.isComposing` (every handler would have to remember it; SwiftUI has none).

## 2. Tests

- `Tests/MetalUITestingTests/OnKeyPressDuringCompositionTests.swift` (`aKeyThatReachesWindowDuringACompositionStillReachesOnKeyPress`).
- `Backends/SDL/Tests/MetalUISDLTests/SDLTextInputTests.swift` `keysAreNotForwardedWhileAnInputMethodComposes` (the pure `suppressesKey` arms plus pushed `TEXT_EDITING`/`TEXT_INPUT`/key events through a hidden window: suppressed while composing, ctrl-c forwarded, forwarded after a commit and after a cancel).

## 3. Mutations

| Mutation | Reddened |
| --- | --- |
| remove the `suppressesKey` line in `SDLWindow`'s key case | `keysAreNotForwardedWhileAnInputMethodComposes` |
| `dispatchKeyPress` returns false while the focused field composes | `aKeyThatReachesWindowDuringACompositionStillReachesOnKeyPress` |

## 4. Verification notes

The Backends/SDL run was done with AccessKit's trait and its six test files removed locally (the AccessKit release download returned 504 in this environment); the manifest and tests were restored before committing. Counts: see the PR.
