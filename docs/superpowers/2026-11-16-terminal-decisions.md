# Terminal (Alloy gaps 1-5) - decisions (prefix `TRM-`)

Rulings for Alloy's integrated terminal, built as `docs/superpowers/specs/2026-11-16-terminal-design.md` lays out; plan `docs/superpowers/plans/2026-11-16-terminal.md`; record 334 (Phase 0). `TRM-` is distinct from `TM-` (`Text` view modifiers and dash patterns) and has no relation to any other prefix. "Alloy's answer" below means the binding answers sent on 2026-11-16 to the ten questions of the plan; where an answer and the plan differ, the answer wins. Divergence labels 1095-1104 are reserved for `TRM-`; every declaration in this work is class `M`, so none is expected to be used.

Next unused id: `TRM-F`.

## TRM-A: module split

`MetalUITerminal` is UI-free (Foundation and Dispatch only; macOS, Linux, Windows) with a C shim `CPseudoTerminal`; `TerminalView` lives in a separate `MetalUITerminalUI` (depends on `MetalUI` and `MetalUITerminal`, uses `package` hooks). Both are library products; no MetalUI product depends on either, so an app that does not import them builds and costs the same as before. The parser is written in-house from the ECMA-48 and DEC state-machine descriptions, with no third-party code read or copied. `TerminalKey` is in the core; the `KeyPress` overload of `encodeKey` is in the UI module.

Why: a pty and an emulator are OS-level, not windowing, and Alloy needs a terminal core that links without MetalUI. Alloy's answer 1: module split OK, `TerminalKey` in core with a `KeyPress` overload in the UI module OK.

## TRM-B: the freeze table

| gap | surface | status | freezes |
|---|---|---|---|
| 1 | `MetalUITerminal`: emulator, snapshot, events, modes, encoders, `TerminalKey`, `TerminalSnapshotSource` | FROZEN | Phase 0 (record 334) |
| 3 | `keyCapture(except:optionAsMeta:)`, its order and fall-through | FROZEN | Phase 0 |
| 4 | `PseudoTerminal`, `Signal`, `ExitStatus`, `PseudoTerminalError` | FROZEN | Phase 0 |
| 2 | `TerminalView`, `TerminalPalette`, link query and target | DRAFT | start of Phase 5 |
| 5 | `SurfaceRedrawTrigger`, `GPUSurface(redraw:value:trigger:draw:)` | DRAFT | start of Phase 5 |

A frozen signature changes only by a new `TRM-` ruling Alloy accepts. A draft may change freely until Phase 5 and is re-sent to Alloy at the freeze. Phase 0 pins the types the plan left implicit (`TerminalSelection`, `TerminalCursor`, `TerminalCursorStyle`, `MouseTracking`, `MouseEncoding`, `TerminalMouseEvent`, `TerminalModifiers`, `TerminalDamagedRow`, `TerminalCell`, `TerminalAttributes`, `TerminalColor`, `PseudoTerminalError`) so Alloy can build fakes; their members beyond the plan's lists are MetalUI's choice and extend by `TRM-` rulings.

Why: Alloy's design freezes gaps 1, 3 and 4 before its task 5 (fakes and `PtySpawner`) and gaps 2 and 5 at its task 7.

## TRM-C: amendments to Alloy's text

1. `drainEvents()` (draining) and `TerminalSnapshotSource.onEvents` replace an `events` property: a property cannot say when it empties, and two readers would race.
2. New `TerminalEvent.reply([UInt8])` for DA, DSR/CPR, DECRQM and OSC 10/11 answers; the owner MUST write it to the pty (`TerminalSnapshotSource.onReply` does so on the pty's queue). Without it vim and less stall.
3. New `TerminalSnapshotSource` owns feed, merge-publish and the one view wake, the queue-to-main hand-off Alloy described.
4. `TerminalEncoder` is a static namespace (pure functions); `TerminalKey` uses `KeyEquivalent`'s spelling; Alloy's `KeyPress` spelling is an overload in `MetalUITerminalUI`.
5. `keyCapture(except:optionAsMeta:)` replaces `.focusable(interactions: .captureAllKeys(except:))`: `FocusInteractions` is an `Int` `OptionSet` and cannot carry a payload. The state rides `KeyboardAttachment`, not `Handlers`.
6. `PseudoTerminal.signalGroup` takes a `Signal` enum (`.hangup .interrupt .terminate .kill`), portable to Windows.
7. `TerminalPalette` and `TerminalView` carry `boldIsBright` (default false): bold is the bold face only unless set. The plan said "bold-as-bright" as a palette member; Alloy's answer 8 makes it an optional flag.
8. The blink stop-after-30-s is a `TerminalView` flag (`blinkStopsAfterIdle`, default on), not something the host drives through `requestRedraw`. Alloy's answer 10.
9. Option-as-meta covers both Option keys (not the left only) - `TRM-D`.
10. The opaque background comes from the palette's `background` (no glass in v1), accessibility v1 is the visible rows' text only, colour emoji draw monochrome and ligatures are off. Alloy's answers 5, 6, 8.

Why: each is a change Alloy accepted or answered (answers 2, 3, 5, 6, 8, 10).

## TRM-D: key capture - order, fall-through, option-as-meta, dead keys

1. A capture layer's `onKeyPress` handlers get a key before every other stage (Keymap, the `KF-X` command decline, field keys, `onKey`, clipboard, context-menu key, `Button` shortcuts, commands, F10, Tab, `onInput`), including AppKit's `performKeyEquivalent` pre-menu path.
2. A key matching an `except` shortcut (`KeyboardShortcut.matches`) skips capture. A key whose handler answers `.ignored` goes to the unchanged pipeline from its first stage. `TerminalView` answers `.ignored` for any key `encodeKey` encodes to nothing, so command-modified keys that are not in the allow-list still reach menus, as in Terminal.app.
3. Nothing is captured while marked text is composing.
4. With `optionAsMeta` both Option keys are meta: the platform is hinted (`setRawOptionKeys`, a defaulted no-op) to bypass the input context for them, so Option combinations skip dead keys and the character palette. IME and marked text are otherwise left alone.

Why: Alloy's answers 3 and 4 (2026-11-16): keys that encode to nothing fall through to menus; both Option keys; Option combinations bypass dead keys while on; IME untouched otherwise.

## TRM-E: platform floors, Windows shell, signals

- Windows 10 1809 or later (ConPTY). Linux kernel 5.3 or later (`pidfd_open`); a shared reaper is the fallback below that. macOS: the platform floor of the root package.
- `PseudoTerminal` takes an explicit executable. The default shell MetalUI's demo and tests use on Windows is `pwsh.exe` if found on `PATH`, else `powershell.exe`, else `%ComSpec%` (`cmd.exe`, a last resort MetalUI adds; both PowerShells are present on the supported floor so it is rarely reached). The resolver is `package`, not frozen API. On POSIX it is `$SHELL`, else `/bin/sh`.
- Windows has no process groups to signal and no foreground group: `.interrupt` writes 0x03 to the console input; `.hangup`, `.terminate` and `.kill` call `TerminateJobObject` on the job the child runs in (kill-on-close, so no orphans); `foregroundProcessGroup()` returns `nil`.

Why: Alloy's answers 7 and 9 (2026-11-16): `pwsh` if present else `powershell`; Win10 1809+ OK; signal mapping accepted; Linux 5.3+ OK.

## TRM-U: the capture stage - where it sits and what it offers (Phase 4.1, record 338)

1. `keyCapture(except:optionAsMeta:)` marks the keyboard layer it joins (the layer of the `onKeyPress` it is written beside, in either order). While the focus chain holds a marked layer, `Window.dispatchKeyCapture` runs as the first key stage, ahead of `dispatchAction` (the Keymap), and offers the key to that layer's `onKeyPress` handlers: outermost capture layer first, each layer's handlers last-written first (`KF-C`), under `StateDispatch.dispatching(to:)` the layer's element (`ID-F`).
2. Key-downs and key-ups are offered (a handler's `phases` still filters). Only the focus chain counts, not a hovered key region: capture is a focus feature.
3. A layer offered a key is not offered it again by `onKeyPress`'s own stage (`Window.keyCaptureOffered`, `dispatchKeyPress(_:along:in:skipping:)`): a handler answering `.ignored` is called once per key. A layer capture skipped (`except`, composing) is offered by `onKeyPress`'s stage as before, so the unchanged pipeline stays unchanged.

Why: spec §3 order; a double call would double a handler's side effects and break a terminal's encoder (a key written twice to the pty).

## TRM-V: what skips capture

1. A layer whose `except` holds a shortcut matching the event (`KeyboardShortcut.matches`: exact modifiers, key case-folded; `.primary` per platform) is skipped for that event, and only that layer: an outer layer without the exception still captures.
2. Nothing is captured while the focused text target composes marked text (a field's stored composition, a code view's session): the key belongs to the input method and goes through the pipeline as today (`isComposingMarkedText`).
3. A key event with no `charactersIgnoringModifiers` is not offered (as `onKeyPress`); a `textInput` commit is not a key and is not captured.

## TRM-W: the carrier - a marker handler, not a new `Handlers` member

`keyCapture` appends a marker `KeyPressHandler` (no phases, so it hears nothing; its `capture` field holds the exceptions and the Option flag) to the layer's handler list. `KeyboardAttachment` reads it into a stored `capture` field and `FocusRegistry` keeps one entry per capturing id (`keyCapture(for:)`, `keyCaptureCount`); `Handlers` gains nothing (its size is pinned). Because the marker rides `KeyPressRegistration` like any handler, `keyCapture` joins on every conformer family exactly as `onKeyPress` does: `StyledElement`/`KeyboardModifier`/a proposal chain (`Self`, `KF-AD`) and any `ElementGroup` (`KeyPressed`, `KF-AC`, `KF-AE`), at no element request.

Why: Alloy's answer 3 (state on `KeyboardAttachment`) and the steady-frame cost rule; the alternative (a `FocusInteractions` payload) cannot carry exceptions.

## TRM-X: the Option hint

`PlatformWindow.setRawOptionKeys(_:)` is a defaulted no-op requirement. `Window.syncRawOptionKeys` sends `true` when the focus chain holds a layer with `optionAsMeta` and `false` when it stops doing so, on each focus change and each frame's registry swap; it sends only changes (the last value is kept), so a steady frame sends nothing. AppKit (`MetalHostView.rawOptionKeys`): a key with Option held skips `inputContext` (dead keys, the character palette, Option-letter symbols) unless marked text is composing; ⌘ keys and every other key are routed as before. SDL: an Alt combination is a plain key (`producesText` false) and the `TEXT_INPUT` an Alt combination produces is dropped. IME and marked text are otherwise untouched.

## TRM-Y: AppKit routing and cost

1. The pre-menu path needs no new AppKit code: `performKeyEquivalent` already offers ⌘ and ⌃ keys to `Window.onInput`, whose first key stage is now capture, so a captured ⌘ or ⌃ key never reaches the main menu (`.handled` is the claim `performKeyEquivalent` returns) and an `.ignored` one does, as before. **⌃Tab** is such a ⌃ key: capture hears it before AppKit's key-view loop sees it; `.ignored` returns the window's answer and the loop proceeds. (Whether AppKit offers ⌃Tab to `performKeyEquivalent` on every macOS version is a human check, `TRM1`.)
2. Cost: an app not using `keyCapture` pays one dictionary-count comparison per key event and per frame (`keyCaptureCount > 0`); an app using it pays no element request, no layout node and no further retention miss (`KeyCaptureCostTests`, literal counts equal master's).

