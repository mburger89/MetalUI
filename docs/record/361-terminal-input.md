# 361 - TerminalView input (`TRM-BC`; terminal Phase 5.4)

Numbered 361: 350 (ConPTY), 355, 359 and 360 are other open branches'; expect renumbering. `TRM-BB` is `perf/surface-replay`'s (open PR), this takes `TRM-BC`.

Branch `feat/terminal-view-input` from master `8790e4d9`. Wires the frozen `onInput`, `keyCaptureExceptions` and `optionAsMeta` of `TerminalView` (record 357); no signature changes. Class M, no divergence label.

**What landed.** Public: `TerminalEncoder.encodeKey(_ press: KeyPress, modes:optionAsMeta:)` (`MetalUITerminalUI`, the spec's overload), `KeyEvent.isKeypad` (`MetalUIPlatform`, default false; AppKit sets it from the key code). Package: `KeyPress.isKeypad`, `ExternalTextInput` and `KeyboardModifier.externalTextInput(_:)` (a text target whose text lives outside MetalUI), `KeyboardShortcut.matches(_ press:)`, `TerminalSnapshotSource.pendingModes`, `TerminalRow.overlaying(_:at:attributes:caretCharacter:)`. `Window` routes committed and marked text to an external target (never to `TextEditing`), declines the field editing keys, press and drag for it, refreshes the input method's area after a surface-only frame, and drops its marked text on focus loss.

**How.** One keyboard layer: `.focusable().focused(...).keyCapture(...).onKeyPress{}.pasteDestination(for: String.self){}.externalTextInput(...)`. See `TRM-BC`.

**Bindings.** Paste: ⌘V (and Edit > Paste) on Apple platforms, Ctrl+Shift+V on Linux and Windows. Option-as-meta: both Option keys. Everything else is the encoder's.

**Cost literals** (headless `TestWindow`, portable text system): a keystroke frame = 2 element requests (equal to a plain rebuilt frame of the view), then output: builds 0, elementRequests 0, surfaceOnlyFrames 1; an editor keystroke in a window with the view: 4 element requests, 1 build, equal to master `8790e4d9` (the view adds the same 2 as in 357).

**Tests.** `Tests/MetalUITerminalUITests/TerminalInputTests.swift` (13): the key matrix, option-as-meta, command keys fall through to a `CommandMenu`, exceptions, marked text drawn and only the commit sent, the input method's area, paste (plain, bracketed, ESC stripped, Edit > Paste enabled), focus events under mode 1004, the blink idle restart, both cost literals, the `KeyPress` overload, the overlay's cells and recorded glyphs. Each shown red against a named mutation (see the test comments).

**Findings.** The layer's own `onKeyPress` stage still offers a key capture skipped (`TRM-U` item 3), so the handler must refuse excepted keys and keys while composing itself. AppKit hands ordinary characters to a text target as text, not as key events, so on AppKit a keypad digit is text and `applicationKeypad` applies only to keypad keys that arrive as keys; SDL does not report the keypad flag yet.

**Not done.** SDL keypad flag; the pointer (5.5); accessibility (5.6); human checks `TRM7`-`TRM10`.
