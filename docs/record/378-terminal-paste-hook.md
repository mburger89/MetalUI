# 378 - The terminal paste hook (`TRM-BG`)

Branch `feat/terminal-paste-hook` from master `f66a6913`. Class M, no divergence (labels untouched). Alloy's request: `.pasteDestination` takes the paste before the host can show its multi-line confirmation.

**API.** `TerminalView(…, onLink:, onPaste: (@MainActor (String, TerminalModes) -> Bool)? = nil)`. Called in `TerminalViewModel.paste(_:)` after the empty guard and before the default: `true` is handled (nothing sent), `false` the default, nil today's. The text is the raw clipboard text (the host sends `TerminalEncoder.encodePaste(text, modes:)` itself).

**Routes.** The paste destination's action (⌘V and Edit ▸ Paste on Apple) and Ctrl+Shift+V (elsewhere) both call `paste`; there is no middle-click or drop paste to route.

**Modes.** The model's `modes` (`source.pendingModes`, else the last snapshot): the newest the source has, read under the source's lock, as every key press reads it. A mode set by output still on the emulator's queue unpublished is not seen. No emulator-queue read.

**Cost.** A closure, not compared by the field's `==`; read only on a paste. Measured: steady frame 2 element requests with and without a hook; an editor keystroke beside the view 2 requests and 1 build with and without.

**Tests** (`TerminalPasteHookTests`): the paste key, the destination's handler (and Edit ▸ Paste delivery on Apple), current modes (including a mode set in the same burst, undrawn), true sends nothing, false equals the hook-less bytes, nil is today's, cost. Mutations are in the file's header.
