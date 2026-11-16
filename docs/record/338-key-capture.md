# 338 - Key capture (terminal Phase 4.1; `TRM-U`..`TRM-Y`, class M)

Branch `feat/key-capture` from master `ff73af7c`. Alloy gap 3, frozen by record 334 (`TRM-D`). Class M: no divergence label (SwiftUI has no key capture). Phase 4.2 (SDL key coverage for Insert, F13-F20, the keypad, Ctrl+backtick and Ctrl+Space) is not in this record.

**API.** `keyCapture(except: [KeyboardShortcut] = [], optionAsMeta: Bool = false)` on `StyledElement`, `KeyboardModifier`, any proposal chain or `LifecycleScope` over one (`Self`, one `keyboard` layer, `KF-AD`) and any `ElementGroup` (`KeyPressed`, `KF-AC`/`KF-AE`). `PlatformWindow.setRawOptionKeys(_:)`, a defaulted no-op; `HeadlessPlatformWindow.rawOptionKeyRequests` and the test fake record it.

**Where it sits.** `Window.dispatchKeyCapture` is the first key stage in `onInput`, ahead of `dispatchAction` (the Keymap), so ahead of the `KF-X` decline, field keys, `onKey`, the clipboard, the context-menu key, `Button` and `CommandMenu` shortcuts, commands, F10, Tab and `onInput`. On AppKit `performKeyEquivalent` already hands ⌘ and ⌃ keys (⌃Tab among them) to `onInput` before the main menu, so capture precedes the menu with no AppKit change on that path. The capture layer's own `onKeyPress` handlers are offered the key once: `onKeyPress`'s stage skips layers capture already offered (`keyCaptureOffered`).

**Carrier.** A marker `KeyPressHandler` (empty phases, a `capture` payload) rides the layer's handler list; `KeyboardAttachment.capture` reads it and `FocusRegistry` keeps `keyCapture(for:)`. `Handlers` is untouched (size pinned). Every conformer that carries an `onKeyPress` handler carries the marker, so the three families of `KF-AC`/`KF-AD`/`KF-AE` needed no per-conformer code beyond the spelling.

**Option.** `Window.syncRawOptionKeys` (focus change and frame registry swap, changes only) sends `setRawOptionKeys`. AppKit skips `inputContext` for an Option key while the hint is on and no marked text composes; SDL treats Alt combinations as keys and drops the `TEXT_INPUT` they produce.

**Tests.** `Tests/MetalUITests/KeyCaptureTests.swift`: the ordering matrix over the keymap, the command table, field editing keys, `onKey`, clipboard copy and paste, a `Button` shortcut, a `CommandMenu` shortcut, F10 and Tab, each run handled and ignored; the `KF-X` decline contrast; ⌃Tab; `except` (and the platform's modifier, `ControlKeys.selectionToggleModifier()`); marked text; capture off the focus chain; nested layers; the Option hint; every conformer family. `KeyCaptureCostTests.swift`: steady keystroke frame literals. Mutations are listed on each test and were run (see the PR body).

**Not run by an agent** (human group `TRM`): ⌃Tab on a real AppKit window (whether the key-view loop sees it first), Option dead keys with `optionAsMeta`, an IME with capture on.
