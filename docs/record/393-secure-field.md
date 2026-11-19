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

| mutation | red tests |
|---|---|
| `TextField.shownText` returns `text` (the real text drawn, published, measured) | `aSecureFieldDrawsOnlyBulletsAndNeverHandsTheTextToTheTextSystem`, `aSecureFieldPublishesItsRoleAndBulletsNeverItsText`, `theCaretMovesByGraphemeOverBullets` |
| `prepaint` publishes `value: text` | `aSecureFieldPublishesItsRoleAndBulletsNeverItsText` |
| the `TextInputTarget` is given `shownText` (the edit buffer is bullets) | `theBindingWritesTheRealText` |
| the `case "c" where secure, "x" where secure` arm removed (copy allowed) | `copyAndCutDoNothingInASecureField` |
| a `case "v" where secure` arm that does nothing (paste disabled) | `pasteInsertsIntoASecureField` |
| `mask` counts `text.utf16.count` | `theCaretMovesByGraphemeOverBullets` |
| the `.textComposition` claim removed from `Window` | `markedTextIsIgnoredInASecureField` |
| the word keys read the real characters | `wordMovementNeverRevealsWhereTheWordsAre` |
| `runDisappearancesForClose` skips `syncSecureTextInput()` (close keeps the hold) | `secureInputIsBalancedAcrossFocusBlurAndWindowClose` |
| `syncSecureTextInput` keeps a sent hold while anything is focused (removal never releases) | `removingTheFocusedSecureFieldReleasesSecureInput` |
| `syncSecureTextInput` drops its `wanted != sent` guard (a request per frame) | `aWindowWithoutASecureFieldKeepsItsFrameWorkAndSendsNothing` |
| `windowWillClose` skips `refreshSecureEventInput()` (AppKit) | `secureEventInputIsBalancedAcrossFocusKeyWindowAndClose` |
| the Cut/Copy `if` of `validateMenuItem` disabled | `aSecureFieldBypassesTheInputMethodAndDisablesCutAndCopy` |
| the role map answers no subrole | `aSecureTextFieldIsAXTextFieldWithTheSecureSubroleAndAMaskedValue` |
| the AppKit value answers the node's string | the same |
| `isPrintable` answers `true` | `aSecureFieldTypesPrintableCharactersAndKeepsTheRestAsKeys` |

Two instruments were found blind and fixed in the round: the first removal test mutated `syncSecureTextInput` with `guard focusedElement != nil`, which a removed field's stale focus does not trip (green), so its mutation became "keep a sent hold while anything is focused"; and `keyDown(with:)`'s secure branch cannot be told from the input context's own routing in a headless window (the context inserts the same text), so the branch's mutation stays green headlessly and is human check `SCF4`; the pure `secureTypedText` it calls is pinned by the last row. The SDL pin (`aSecureFieldIsAPasswordInputToAccessKitAndSDLHasNoSecureEntry`) has the mutation "map `.secureTextField` to `.textInput`".

## Verified

`swift build --build-system native --build-tests && swift test --build-system native --no-parallel`: 7072 tests in 79 suites, green (the run before the demo's two assertions were updated had exactly those two red; re-run after the last code change). `swift build -c release` green. SDL package (`Backends/SDL`, AccessKit 0.23 from the scratch fetch, SDL3 from Homebrew): the SDL pin passes and goes red under its mutation; `windowServerTrafficNeverStopsTheMainRunLoop` fails as on master and `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` could not write under the sandbox (unrelated). `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. Linux and Windows: CI.

## Carried

Bullet metrics against AppKit by pixels (1115); `NSSecureTextField`'s word keys and its input-source limits (`SCF-D`, 1117); SDL has no secure entry (1116).
