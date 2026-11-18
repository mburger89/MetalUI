# 383 - the terminal keypad hint (`TRM-BM`)

Branch `feat/terminal-keypad-hint` on master `7b1a2253`. Class M, no divergence. Fixes the deferred limitation of `TRM-BC` item 2, `TRM-BJ` item 3 and `TRM-BK` item 6(c): a keypad digit under DECKPAM sent the digit on AppKit and SDL, because both deliver it as text.

**Mechanism.** `PlatformWindow.setRawKeypadKeys(_:)` (defaulted no-op, mirrors `setRawOptionKeys`, `TRM-X`). `KeyCapture` gains a `keypadAsKeys` closure, set through a `package` overload of `keyCapture`; `Window.syncRawKeypadKeys` asks the focus chain's capture layers on a focus change, a registry swap and after a surface-only frame, and sends only changes. `TerminalView` answers `model.modes.applicationKeypad` (the newest modes). AppKit: `keyDown` skips `inputContext` for keypad key codes (no marked text, no ⌘). SDL: `producesText(rawKeypadKeys:)` is false for keypad characters and the `TEXT_INPUT` that follows the key is dropped (`droppedKeypadText`, cleared by the next key-down). The encoder needed no change.

**Tests.** Root `TerminalKeypadHintTests` (hint follows DECKPAM and focus, end to end through the view, newest-modes frame, no terminal never sets it, cost), `TextInputPlatformTests.theKeypadHintMakesKeypadKeysKeysNotText` (AppKit `keyDown`), SDL package `SDLTerminalKeysTests` items 7 and 8. Mutations are in each test's header.

**Human check.** `TRM22`: keypad in vim, htop and mc with Num Lock on, AppKit and Linux.
