# SecureField: decisions (`SCF-`)

Sift's saved-connection passwords (its plan's gap G1). SwiftUI's `SecureField` on macOS is an `NSSecureTextField`
(probe `docs/probes/swiftui-secure-field.swift`, arm `A`). Class `D`: three divergences, labels 1115-1117 of the block
1115-1124 reserved by SCF. Record 393. Prefix `SCF-` (`SF-` is the system fonts').

Next unused ruling: `SCF-I`.

## SCF-A: a `TextField`'s editor with the text masked (ruled, built)

`SecureField` is a thin `Element` over a `TextField` whose internal `isSecure` is set. The editor, chrome, focus, binding,
undo and submit are the field's. The masking is **display only** and lives in one place, `TextField.shownText`: one bullet
`•` (U+2022) per grapheme of the text (`TextField.mask`). It is what `requestLayout` measures, what `geometry` lays out and
`paint` draws, and what `prepaint` publishes as the accessibility value; the caret offsets and the selection are the
bullets' (`caretOffsets` of the masked string, `count + 1` values), so they map 1:1 onto the graphemes of the real text. The
real text reaches the binding, `TextInputTarget.text` (the window's edit buffer) and the edit state's undo snapshots, and
nothing else: never the text system's shaping, measuring or caches, the scene's glyph runs or the accessibility tree
(`aSecureFieldDrawsOnlyBulletsAndNeverHandsTheTextToTheTextSystem`, `aSecureFieldPublishesItsRoleAndBulletsNeverItsText`).
The placeholder is drawn as a `TextField`'s. A vertical field is not offered.

## SCF-B: secure keyboard entry (ruled, built)

`PlatformWindow.setSecureTextInput(_:)`, **defaulted to a no-op**, sent by `Window` on change only
(`syncSecureTextInput`, called with `updateTextInputArea` after each frame): `true` while the focused element's text target
is secure, `false` when focus leaves, the field is removed (the frame clears the focus it did not produce) and **once more
when the window closes** (`runDisappearancesForClose`; a closed window sends nothing after). AppKit: `SecureEventInput`, a
counter over Carbon's `EnableSecureEventInput()` / `DisableSecureEventInput()` (the calls are injectable), one hold per
window held exactly while a secure field is focused, the window is key (`windowDidBecomeKey` and `windowDidResignKey`) and
open, released at `windowWillClose` and in the window's `isolated deinit`; a release with nothing held does nothing, so a
double blur or a close after a blur never disables another window's hold. Carbon is imported only by
`MetalUIAppKit/AppKitSecureInput.swift`; the core never sees it. SDL keeps the default: no equivalent (divergence 1116).
`HeadlessPlatformWindow.secureTextInputRequests` records the requests.

## SCF-C: the clipboard (ruled, built)

Copy and Cut do nothing: `TextEditing.key(secure:)` claims ⌘C and ⌘X (the key does not bubble to a menu or a shortcut) and
writes nothing and deletes nothing; on AppKit the host view's `validateMenuItem` answers `false` for the Edit menu's Cut and
Copy while the focus is secure (Paste stays on). Paste inserts, over a selection replaces it. Undo and redo work as in a
`TextField` (the history holds the real text, in the window's edit state). **MetalUI has no drag-out of a field's selected
text**, so there was nothing to disable.

## SCF-D: the word logic sees one word (ruled, built)

The word keys (⌥←/⌥→, ⌥⌫, ⌥⌦; ⌃ off a Mac), a double-click and a drag by words are computed over a string of the same
length with no word boundaries inside (`TextEditing.key`'s `wordCharacters`, `Window.editingText`): they go to the edge or
select all. Otherwise the caret's position after a word key would tell where the real text's words begin. (NSSecureTextField
is not measured here; this is a choice, unmeasured against AppKit.)

## SCF-E: no input method, no marked text (ruled, built)

`Window` claims a `.textComposition` for a secure target and keeps it out of the edit state; the field has no composition,
so the marked-text underline and the composed glyphs never draw. AppKit: the host view's `secureInput` flag sends a
printable key's characters as `.textInput` without the input context and any other key as a `.keyDown`, and drops a
`setMarkedText`. Committed text (`insertText`: the emoji palette, a pasted-in character) is typed. There is no autocorrect,
spell checking or text replacement in any MetalUI field. Divergence 1117 (dead keys and input methods).

## SCF-F: accessibility (ruled, built)

New roles `AXRole.secureTextField` and `AccessibilityRole.secureTextField` (not `.textField` plus a flag, so a client or
a harness query for `.textField` does not find a password field). AppKit: `AXTextField` with subrole `AXSecureTextField`;
SwiftUI's is the same (probe arm `A`). The value is **never the text**: the core publishes one bullet per grapheme, and the
AppKit bridge answers one U+F79A per character, which is what `NSSecureTextFieldCell` answers (probe arm `A`: 7 scalars of
`f79a` for "hunter2"). AccessKit: `ACCESSKIT_ROLE_PASSWORD_INPUT` (present in `accesskit.h` 0.23) with the bullets as the
value (divergence 1116).

## SCF-G: the API (ruled, built)

`SecureField(_ title: String, text: Binding<String>)`, `SecureField(_:text:prompt: Text?)` (`TextField`'s `VT-J` prompt
rules) and `SecureField(text:prompt:label: () -> Text)`, the label's string being the title. MetalUI has no
`LocalizedStringKey`, so the title is a `String` as `TextField`'s is; `TextField` has no `label:` builder either, so this one
takes a `Text`. Modifiers on the field: `.font(family:size:)`, `.foregroundColor`, `.textFieldStyle`, `.onSubmit`; the
generic ones (`.disabled`, `.frame`, `.focused`, `.background`) are the `StyledElement`'s. There is no `submitLabel` and no
`autocorrectionDisabled` in MetalUI to mirror.

## SCF-H: not offered (ruled, not built)

`SecureField(_:text:selection:)` (no `TextSelection` over bullets), `axis: .vertical`, a reveal-last-character delay (AppKit
has none), a show-password toggle (the app's `if` over two fields), a `SecureField` in an alert's actions (divergence 362
stands).

## Carried

- The bullet's metrics against AppKit's echo glyph, measured by pixels (divergence 1115).
- NSSecureTextField's word keys and double-click, measured (`SCF-D`).
- A secure-entry equivalent on Windows and Linux, if one exists that a toolkit can ask for (divergence 1116).
