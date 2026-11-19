# 393: SecureField (`SCF-A`..`SCF-H`)

Class `D`, three divergences (1115-1117). Branch `feat/secure-field`, base master `260d9614`. Sift's saved-connection passwords (its plan's gap G1). Decisions `docs/superpowers/2026-11-19-secure-field-decisions.md`, probe `docs/probes/swiftui-secure-field.swift`. Records 389-392 are the Table line's.

## Change

- `SecureField` (`SecureField.swift`): a thin `Element` over a `TextField` with its internal `isSecure` set; the editor, chrome, focus, binding, undo and submit are the field's (`SCF-A`, `SCF-G`).
- Masking is display-only, in `TextField.shownText`: one `•` per grapheme, measured, laid out (the caret offsets are the bullets', 1:1 with the graphemes), drawn and published (`SCF-A`). The text system never sees the text.
- `TextInputTarget` gains `secure` in its one hooks box (`Handlers` keeps its pinned size). `TextEditing.key(secure:)` claims copy and cut without effect and sees one word (`SCF-C`, `SCF-D`); `Window` keeps `.textComposition` out of the state, uses masked text for double-click and drag-by-word (`SCF-D`, `SCF-E`).
- `PlatformWindow.setSecureTextInput(_:)` (defaulted no-op) is sent on change by `Window.syncSecureTextInput` and once on close. AppKit: `SecureEventInput`, a counter over Carbon's `EnableSecureEventInput`/`DisableSecureEventInput`, one hold per window while a secure field is focused in a key window, released on blur, resign key, close and deinit; the host view bypasses the input context, drops marked text and answers `false` to Cut and Copy (`SCF-B`, `SCF-E`).
- `AXRole.secureTextField` and `AccessibilityRole.secureTextField`: AppKit `AXTextField` with subrole `AXSecureTextField` and U+F79A per character, AccessKit `PASSWORD_INPUT` (`SCF-F`).
- The demo (`METALUI_TEXT_INPUT_DEMO=1`) has a Password field.

## Measured (probe `swiftui-secure-field.swift`, macOS 27.0)

A SwiftUI `SecureField` holding "hunter2" is an `AppKitSecureTextField` over `NSSecureTextFieldCell`: `AXRole` `AXTextField`, `AXSubrole` `AXSecureTextField`, `AXValue` seven U+F79A scalars (never the text). A `TextField` is `AXTextField` with no subrole and the text as its value.

## Tests

`SecureFieldTests` (portable, 11), three `TextInputPlatformTests`/`AppKitAccessibilityTests` tests (AppKit) and one SDL test. Each names its mutation; the round, every one restored (a `git diff` of the sources empty after), with the red tests:

MUTATIONS

## Verified

FULLRUN

## Carried

Bullet metrics against AppKit by pixels (1115); `NSSecureTextField`'s word keys and its input-source limits (`SCF-D`, 1117); SDL has no secure entry (1116).
