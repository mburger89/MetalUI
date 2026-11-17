# 356: shifted shortcuts match one way; the ⇧Tab fix; ⇧⌘P confirmed on SDL (`KF-AL`)

Branch `fix/shortcut-shift-probe` from master a34fd90d. Class M (A for ⇧Tab if SwiftUI fires, unconfirmed), no divergence. Alloy palette #3 and its binding answer 3. PR2 of the shortcut design (PR1, `KF-AG`, is record 355).

## What changed
- `KeyEvent.unshiftedKey` (public, default ""); AppKit fills it with Shift held through `UnshiftedKey` (`UCKeyTranslate`, per-layout cache); SDL sets it from its keycode.
- `KeyboardShortcut.matches`: "\u{19}" is "\t"; the base key with `.shift` also matches.

## Findings
- ⇧P / Ctrl+Shift+P fires on SDL as expected, with and without a focused `TextField`; extra Alt or no Shift does not fire. The unfocused arm cannot observe the event through `onKey` (the raw bubble follows focus), so it checks `SDLKeys.characters` instead.
- Probe P3 (SwiftUI on ⇧Tab) is not observable by an agent: no key window, no real key event. Human check KF-AL1.

## Tests and mutations
`ShortcutShiftTests` (5): drop the "\u{19}" reading, ignore `unshiftedKey`, drop the `.shift` requirement on the base key, drop the event's `.lowercased()` each redden. `AppKitUnshiftedKeyTests` (1): modifier state 0 to 2 reddens. `SDLShiftShortcutTests` (3 functions, 4 cases): `SDLKeys.characters` stops upper-casing reddens.
