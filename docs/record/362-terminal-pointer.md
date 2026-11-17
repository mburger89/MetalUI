# 362 - TerminalView pointer (`TRM-BD`; terminal Phase 5.5)

Numbered 362: 350, 355, 359, 360 and 361 are other branches' (open PRs); expect renumbering. `TRM-BD` follows `TRM-BC` (#364) and `TRM-BB` (#362's perf branch).

Branch `feat/terminal-view-pointer`, on `feat/terminal-view-input` (#364). Wires the frozen `onLink` and the pointer; no signature changes. Class M, no divergence (Edit > Copy enablement follows divergence 455).

**What landed.** `Sources/MetalUITerminalUI/TerminalViewModel+Pointer.swift` (hit test, wheel, reports, selection, autoscroll, copy, links); the pointer input as fields of the keyboard layer (`KeyboardModifier.pointerInput`, `package`: hover, one composed `simultaneousGesture` of three buttons, the wheel, and a `PointerAttachment.styleProvider` for the pointer style), plus `onModifierKeysChanged` and `copyable`; `TerminalView` is `Equatable`; a link underline parameter on `TerminalRowPainter.draw`; `package` `TerminalEmulator.scrollViewport(byRows:)` and `viewportTopRow`. No public declaration, so no inventory row.

**Rules chosen** (see `TRM-BD`): alternate-screen wheel = arrow keys (Terminal.app, VTE, Alacritty; xterm's 1007 defaults off); ⌥ = block selection; ⇧ at the press bypasses reporting, wheel included; link modifier = the primary modifier (Ctrl off Apple); `.exit` on every cell left; OSC 8 is the fallback, activated through `openURL`.

**Cost literals** (headless, portable text system): a rebuilt frame of the view 2 element requests, an editor keystroke beside it 4 (both as on master); hover and ⌘ hover over a link row draw the same frames and builds as a twin without a terminal (25 and 25 for 25 moves) and entering a link costs no build; a selection drag event is 1 build, 2 requests, and a surface redraw of the selected row only; output after it 0 builds, 0 requests. A surface-only drag frame is not reachable: `Window` dirties after every handled pointer event (`FP-T`, #363, spares only unclaimed moves). First draft used four wrappers (6 requests); folded into the keyboard layer on review.

**Retention.** `TerminalView` is `Equatable` (inputs only; closures excluded as `TabStrip`'s are); `.equatable()` replays nothing today because a `GPUSurface` subtree is ineligible (0 retained hits).

**Tests.** `TerminalPointerTests.swift` and `TerminalPointerSelectionTests.swift`; each names its mutation. Run: all 17 mutations (and, after the fold, re-adding a wrapper, an always-equal `==` and a static pointer style) (round, precise rows tripled, no wheel shift bypass, no alternate branch, no press shift test, modifiers dropped, no block, no autoscroll, query every move, no pointer style, no exit, no OSC 8, hover redraw, no copy text, far-end extend, word/line swapped, no activate) turned the suite red; restored from copies.

**Not done.** Dragging after a double or triple click does not extend by words or lines; middle-click paste; mode 1007 and 1015 in the emulator; a surface-only drag frame; accessibility (5.6); human checks `TRM11`-`TRM14`.
