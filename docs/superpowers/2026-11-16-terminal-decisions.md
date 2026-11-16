# Terminal (Alloy gaps 1-5) - decisions (prefix `TRM-`)

Rulings for Alloy's integrated terminal, built as `docs/superpowers/specs/2026-11-16-terminal-design.md` lays out; plan `docs/superpowers/plans/2026-11-16-terminal.md`; record 334 (Phase 0). `TRM-` is distinct from `TM-` (`Text` view modifiers and dash patterns) and has no relation to any other prefix. "Alloy's answer" below means the binding answers sent on 2026-11-16 to the ten questions of the plan; where an answer and the plan differ, the answer wins. Divergence labels 1095-1104 are reserved for `TRM-`; every declaration in this work is class `M`, so none is expected to be used.

Next unused id: `TRM-U`.

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

## TRM-F: storage layout and the shapes Phase 1.1 pins

1. A `TerminalRow` is a value type: `bytes` (the UTF-8 text of its cells, one grapheme cluster per cell, a wide character once), `runs` (run-length attribute spans covering exactly the stored columns, empty when every cell is default), the grid width, the stored column count and two flags (`isASCII`, so column and byte offset coincide; `wrapsToNext`, for reflow). No struct or `Character` per cell; `TerminalCell` and `cell(at:)` are produced on demand. Copying a row shares both arrays until one copy writes.
2. A row leaving the screen is compacted (trailing default blanks dropped, both arrays sized exactly) into a fixed-capacity ring (`ScrollbackRing`) that grows lazily to its capacity; evicting the oldest row is O(1). Absolute row `n` is the screen's first row plus its index, `firstRow` the oldest retained.
3. The census is counted, not sampled: the ring's array capacity times the row stride plus, per row, 32 header bytes plus capacity of each array rounded to 16. A 10 000 x 120 ASCII scrollback measures 1.85 MB, a row costing 32 bytes of struct and 160 of heap against 120 of text.
4. `TerminalRow.text` and `rowText` trim trailing spaces. `cell(at:)` answers the same cell for both columns of a wide character and a blank default cell outside the stored text. `graphemes` lists stored cells only (a wide cell once, no trailing blanks).
5. `TerminalModes()` is the power-on state: autowrap on, cursor visible, a steady block. The first `publishSnapshot()` is a full frame; the version bumps when damage, the cursor or the modes changed. The memberwise initialisers of `TerminalCursor`, `TerminalDamagedRow`, `TerminalSnapshot`, `TerminalCell` and `TerminalRow` are internal: the spec froze their members, not a constructor, and Alloy's fakes ask for one by a later ruling.

Why: Alloy flagged memory (10 000 rows of scrollback); the spec's budget is 4 MB per pane.

## TRM-G: the parser's reading of the byte stream

1. UTF-8 is decoded incrementally before the state machine; an invalid sequence yields U+FFFD for each maximal invalid subpart (the standard library's rule, which the tests use as the oracle) and the byte that broke it is decoded afresh. A sequence cut by the end of a feed waits for the next one.
2. C1 controls are the scalars U+0080-U+009F (two bytes in UTF-8); a lone byte 0x80-0x9F is invalid UTF-8 and prints U+FFFD, never a command.
3. A non-ASCII scalar inside an escape, CSI or DCS header cancels the sequence and prints; inside a string it is payload; inside an ignored CSI or DCS it is swallowed.
4. OSC, DCS and APC end at ESC (ST is ESC then `\`), U+009C, or, for OSC only, BEL, and are dispatched then. CAN, SUB and a C1 introducer drop a string in progress. SOS and PM are consumed without a dispatch. The payload counts bytes: exactly the cap is delivered, one more is dropped to the terminator and the parser recovers; nothing grows past the cap. C0 controls other than CAN, SUB and ESC are payload in a DCS and ignored in an OSC or APC.
5. CSI: C0 controls execute in place; ESC restarts; CAN and SUB abort (the final byte then prints). Parameters saturate at 65 535 and at most 32 are kept; `:` marks a sub-parameter (`isSub`); a private marker `<=>?` may only lead; more than 4 intermediates, a marker after digits or a digit after an intermediate suppress the dispatch.

Why: spec section 2.1 rules 1 and 2, written from the ECMA-48 and DEC state descriptions.

## TRM-H: what Phase 1.2 executes

The emulator prints text with autowrap and pending wrap (a wide character wraps whole, a combining mark joins the previous cell), runs BS, HT (fixed stops every 8 columns until 1.3), LF/VT/FF/IND (scrolling the whole screen into scrollback), CR, NEL, CUU, CUD, CUF, CUB, CNL, CPL, CHA/HPA, VPA, CUP/HVP, DECKPAM/DECKPNM and the mode flags `?1 ?7 ?9 ?25 ?1000 ?1002 ?1003 ?1004 ?1005 ?1006 ?2004`. Every cursor movement clears pending wrap. Everything else (SGR, erase, insert/delete, regions, RI, HTS, alternate screen, origin mode, OSC, DCS, APC, replies) is parsed and dropped until its phase; `modes.alternateScreen` and `originMode` therefore stay false. The pen is the default rendition until SGR lands.

Why: a seam that tests can assert on, with no stub that pretends to work.

## TRM-I: the `.vtfix` fixture format (version 1)

Line-oriented, `#` comments: `size`, `scrollback`, `input "<escaped>"` (`\e \r \n \t \\ \xHH \u{H}`), a `text` block and a `history` block of `|row|` lines (trailing blanks not compared), `cursor <row> <col> [pending]`, `modes name=value ...`. Later phases add attribute maps, events and replies as new keys; an unknown key fails the fixture. Every fixture runs whole, byte at a time and cut at every position.

## TRM-J: Phase 1 guards

Chunk-split invariance (every two-way cut, byte at a time, seeded partitions, over the parser event log and the whole emulator state), seeded fuzz (random bytes never trap, the cursor stays in the grid, ring and screen sizes hold), the counted census (4 MB) and the gated bench `METALUI_RUN_TERMINAL_BENCH=1` (release, plain ASCII, proposal 300 MB/s). The bench measures through the public API only, so it needs no `-enable-testing`.

Why: spec sections 7 and 8.

## TRM-P: the surface-only frame (Phase 3.1, gap 5 draft)

(Appended by `feat/surface-only-redraw`. Ids `TRM-P`..`TRM-T` are this branch's; `TRM-F`..`TRM-J` are record 335's; `TRM-K`..`TRM-O` stay reserved by parallel branches.)

1. `SurfaceRedrawTrigger.requestRedraw()` draws one `GPUSurface` in a **surface-only frame**: `Window.drawFrameIfNeeded` takes the branch only when the window is not dirty, not animating, has no gesture or tooltip timer, and a surface is pending. It re-encodes `lastScene` (kept since `HT-` and unchanged) with the same atlas and hands the renderer **only the pending surfaces' requests**, rebuilt from the last full frame's, at the display link's time. The renderers' table keeps every other referenced surface, undrawn (its existing keep rule), so they composite as they were. 0 builds, 0 element requests, no body, no `@State` or observation read, no accessibility or hover work (nothing it reads moved).
2. Any other reason for a frame (dirty, an animation, a timer) takes the full path, which **forces the pending surfaces' requests** instead (item 3), so a trigger is never lost to a frame that happened first and a surface draws once per request however many frames passed.
3. Forcing is `SurfaceDrawRequest.isForced` (`package`; the public initialiser is unchanged) read by `SurfaceTargetTable.update`: a forced request draws whatever its policy, `value:` and scale say. This is the only change the Metal and SDL renderers see, and they see it without a line of their own (both call the table).
4. A surface-only frame needs the last scene to stand. A full frame is taken instead when none was presented, or the scale, the content size, the platform's resize count or the glyph atlas's `layoutGeneration` moved since it, or the atlas wants a reclaim (`SurfaceRedrawState.canReuseScene`). A scale or size change also dirties the window, so the guard is a second line of defence for the atlas case, which dirties nothing.
5. After a full frame the window keeps its requests (without the force), rebinds the triggers of the surfaces it painted and unbinds those it did not (item `TRM-Q`.2), and drops deadlines of surfaces it did not paint. A surface-only frame whose drawable is not available leaves the surfaces pending and the display link awake; one whose pending surfaces all left the last frame pauses the link.
6. `HeadlessWindowRenderer` runs the requests through a `SurfaceTargetTable` every frame, as the GPU renderers do, and calls the `draw`s only while `runsSurfaceDraws` is on (default off, so the recorded-never-run contract of `HT-Q` stands); `TestWindow.runsSurfaceDraws` and `surfaceDrawCount` expose it, and `FrameWork.surfaceOnlyFrames` is 1 for a surface-only frame, 0 otherwise. `TestWindow`'s idle check counts a pending surface as work, so `runUntilIdle()` draws it.

Why: today a surface redraw is a full window build (the value is read in paint and `drawSurface` taints retention), which is the cost Alloy's terminal cannot pay per output chunk or blink. Rejected: a second `Scene` kept per surface (the scene is already the composite); skipping the build by making the surface's value an observation (it still builds, and reads in paint stay untracked, `MV-F`); drawing the surface from the trigger's thread (draws run on the main actor inside `finishFrame`, `MV-F`).

## TRM-Q: the trigger's contract

1. `SurfaceRedrawTrigger` is `@unchecked Sendable` (a lock around a bound wake closure and what was collected), not a plain `Sendable` as the draft spelled it: a final class with mutable state cannot be checked. Callable from any thread; on the main thread the window hears it synchronously, elsewhere through one `Task { @MainActor }` hop per drain.
2. **Coalescing** is per drain and per window: the trigger hops once until the window drains it, the window's pending set holds an id once, and a frame draws it once. 100 calls before a tick are one frame and one draw.
3. **A trigger whose surface was not painted by the last presented frame does nothing**: it is bound at the end of a full frame to the surfaces that frame painted (after the clip, size and opacity guards of `Frame.drawSurface`) and unbound the first frame that does not paint them, so requests of a hidden panel are dropped on the calling thread, with no hop, no frame and no timer. A trigger used before its surface's first presented frame is the same.
4. One trigger serves one surface in one window.

Why: spec §6 of the design ("a hidden panel starts no timer").

## TRM-R: timed requests

1. `requestRedraw(after:)` joins a per-window deadline set (`SurfaceRedrawState.deadlines`, one date per surface), the **earliest winning** whether the calls land in one hop or several. An immediate request does not cancel a later deadline, and a draw in between does not consume it.
2. The date is the **frame clock's** (`TW-A`) now plus the delay: the timeline store's date at the last display-link tick under the harness's simulated clock (`DX-A`), the wall clock in an app (the display link may have been paused for a long while, so the last tick would be stale). A test therefore drives the deadline with `advance(by:)`; nothing sleeps.
3. Due deadlines move into the pending set at the head of the display-link tick, before `drawFrameIfNeeded`. In an app (no simulated clock) one `Task` sleeps until the earliest deadline (the timeline's `taskScheduler`), moves the due ones into the pending set and wakes the display link; no second wake exists while there is no deadline.
4. A full frame drops the deadlines of surfaces it did not paint, so a deadline stops with its surface.

Why: spec §6 ("timed requests anchor on the frame clock"); the cursor blink is one deadline per half period, a surface-only frame each.

## TRM-S: the initialisers, and where gap 5 differs from the draft

The draft spelled one initialiser, `GPUSurface(redraw:value:trigger:draw:)`. This branch adds `GPUSurface(redraw:trigger:draw:)` beside it, with no `value:`, because a trigger-driven surface such as the terminal has nothing to compare and `value: 0` would be noise. `SurfaceRedrawTrigger` is `@unchecked Sendable` (`TRM-Q` item 1). Both stay draft until Phase 5 and Alloy's confirmation. Surface replay (`TRM-` Phase 3.3, removing the `"surface"` retention taint) is not here: a surface is still painted every full frame.

## TRM-T: cost

An app that never uses a trigger pays nothing. `GPUSurface`'s `paint` passes one more (nil) argument; `Frame.drawSurface` appends to `surfaceTriggers` only when there is one; `SurfaceRedrawState` holds empty collections; the display-link tick tests `deadlineCount > 0`; the drawFrameIfNeeded guard reads `pending.isEmpty`. Literals, on master ff73af7c and on this branch: see record 337 (test `aSurfaceWithoutATriggerCostsWhatItDidOnMaster`, `anAppWithNoSurfaceCostsWhatItDidOnMaster`). A frame owed by a trigger costs 0 builds and 0 element requests (`aTriggerDrawsItsSurfaceInAFrameWithNoBuild`).
