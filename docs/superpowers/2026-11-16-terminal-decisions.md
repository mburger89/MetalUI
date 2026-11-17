# Terminal (Alloy gaps 1-5) - decisions (prefix `TRM-`)

Rulings for Alloy's integrated terminal, built as `docs/superpowers/specs/2026-11-16-terminal-design.md` lays out; plan `docs/superpowers/plans/2026-11-16-terminal.md`; record 334 (Phase 0). `TRM-` is distinct from `TM-` (`Text` view modifiers and dash patterns) and has no relation to any other prefix. "Alloy's answer" below means the binding answers sent on 2026-11-16 to the ten questions of the plan; where an answer and the plan differ, the answer wins. Divergence labels 1095-1104 are reserved for `TRM-`; every declaration in this work is class `M`, so none is expected to be used.

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

## TRM-K: spawn mechanism (POSIX, Phase 2.1 spike)

`PseudoTerminal.spawn` opens the pty in C (`CPseudoTerminal`: `posix_openpt`, `grantpt`, `unlockpt`, `ptsname_r` or `TIOCPTYGNAME`) and starts the child with `posix_spawn` and `POSIX_SPAWN_SETSID` on both macOS and Linux. The slave is opened by the child itself as its first file action (`addopen` on fd 0, then `adddup2` onto 1 and 2): a session leader without a controlling terminal acquires the tty it opens, so no `TIOCSCTTY` is needed. **Spike result: macOS accepts this** (the child is its own session leader, `/dev/tty` opens, `tcgetpgrp` on the master answers the leader's group), so the macOS fork fallback is not needed there. The async-signal-safe `fork` path (`setsid`, `open`, `ioctl(TIOCSCTTY)`, `dup2`, `close_range` or a descriptor loop, `sigaction`, `chdir`, `execve`; argv, env and the descriptor limit built before the fork; an exec failure reported through a close-on-exec pipe) stays as the mechanism on a glibc older than 2.34 or musl, where `posix_spawn_file_actions_addclosefrom_np` is missing. A `package` `PseudoTerminal.Mechanism` (`.automatic`, `.posixSpawn`, `.fork`) lets the test suite run every behaviour under both. The parent holds the slave open across the spawn and sets `TIOCSWINSZ` on it: Darwin discards a size set on a pty nobody has opened (measured: `stty size` printed `0 0`), and this way the child's first `stty size` is right.

Why: spec 4.2 and plan 2.1 ("fork fallback only if macOS refuses the controlling tty").

## TRM-L: what the child inherits

Exactly fds 0-2 (the slave), nothing else: Darwin `POSIX_SPAWN_CLOEXEC_DEFAULT` with `addinherit_np` for 0-2; Linux `addclosefrom_np(3)`; the fork path `close_range` (else a loop to `_SC_OPEN_MAX`). Every signal is reset to its default and the mask is emptied (a host that ignores `SIGPIPE` does not pass that on). The master is close-on-exec and non-blocking. `env` is the whole environment and `argv` the whole argument vector; a missing executable or working directory is `spawnFailed(code: ENOENT)`.

Why: spec 4.1; the pinning tests probe fds 3-60 and the environment under both mechanisms.

## TRM-M: reading and end of file

`read(into:)` returns n > 0, 0 for `EAGAIN`, and -1 at end of file: a 0-byte read (macOS), `EIO` (Linux; spec 4.1) or any other error, and always after `close()`. It runs under the object's lock so a concurrent `close()` cannot close and reuse the descriptor mid-read. A `DispatchSourceRead` is level-triggered and fires forever at end of file, so the first `-1` latches end of file and the next event suspends the source instead of calling the handler again; `close()` and a replacing `onReadable` resume a suspended source before cancelling it so its cancel handler runs. The handler checks the closed flag under the lock, so none runs after `close()` returns on the handler's own queue and none starts after it from another.

## TRM-N: writing

`write(_:)` appends to a queue on an internal serial queue and returns; the queue is drained with non-blocking `write(2)` until `EAGAIN`, and a `DispatchSourceWrite` is resumed only while bytes are pending (a suspended or idle source costs nothing). Chunks keep their order, nothing is dropped and the queue has no cap (a child that never reads costs memory, not a stalled caller). `close()` discards what is still unsent. The master descriptor closes when its last source's cancel handler has run, because dispatch requires it.

## TRM-O: reaping, signals, lifetime, Windows

Nothing installs a `SIGCHLD` handler. macOS reaps from a `DispatchSource` process source plus one `waitpid(WNOHANG)` right after it is armed (the child may have gone first); Linux reads a `pidfd_open` descriptor (kernel 5.3+, `TRM-E`) and, where that is missing, one shared 20 ms timer polls `waitpid(WNOHANG)` for every unreaped child (a `package` flag forces it for its test). The reap and the `exitStatus` result happen once, under the object's lock, and the same lock guards `signalGroup` (`killpg`, a no-op after the reap, so a reused pid is never signalled). `close()` does not stop reaping: the hangup from a closed master ends the child and it is still reaped, `exitStatus` still resolves, and an unclosed object is closed by `deinit`. On Windows the target compiles but `PseudoTerminal` and `PseudoTerminalError` are absent (`#if !os(Windows)`, and `CPseudoTerminal` is empty there); Phase 2.3 supplies them. `TerminalSize` is declared once, in `Geometry.swift`.

## TRM-P: the surface-only frame (Phase 3.1, gap 5 draft)

(Appended by `feat/surface-only-redraw`. Ids `TRM-P`..`TRM-T` are this branch's; `TRM-F`..`TRM-J` are record 335's; `TRM-K`..`TRM-O` are record 336's.)

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

## TRM-Z: what Phase 1.3 executes, and the events

Phase 1.3 replaces `TRM-H`'s list of dropped sequences: the emulator now runs BEL (a `.bell` event), BS, HT, LF/VT/FF/IND, CR, NEL, RI, HTS (ESC H and C1 0x88), SO/SI; CUU CUD CUF CUB CNL CPL CHA HPA HPR VPA VPR CUP HVP; CHT CBT TBC; ED EL ECH (and DECSED/DECSEL, which are the same without protected cells); ICH DCH IL DL; SU SD; DECSTBM; REP; SGR; DECSC/DECRC (and CSI s/u, since DECSLRM is not implemented); DECALN; DECSTR; RIS; DA1, DA2, DSR 5 and 6 (and DECXCPR `?6n`), DECRQM (ANSI and DEC); DECSET/DECRST 1 6 7 9 12 25 47 1000 1002 1003 1004 1005 1006 1047 1048 1049 2004; SM/RM 4 (insert mode); DECSCUSR; DECKPAM/DECKPNM; G0-G3 designation. **Skipped on purpose:** DECSLRM and left/right margins (mode 69 answers "permanently reset"), DECCOLM, DECSCNM, protected areas, LNM and KAM, SS2/SS3 and 96-character sets, mouse-mode stacking (a mouse mode is one `MouseTracking` value, as the frozen enum says), OSC/DCS/APC (Phase 1.4).

`TerminalEvent` and `TerminalEmulator.drainEvents()` are declared whole, exactly as the frozen spec has them. This phase emits `.reply` and `.bell`; `.title`, `.workingDirectory` and `.hyperlink` are declared and are not emitted until OSC lands (1.4). The queue is bounded at 1 024 events between drains (a host that never drains loses the newest), and a `.bell` directly after a queued `.bell` is not queued again; replies never coalesce.

Why: the plan's 1.3 scope and the spec's rule that a reply must be written by the owner (`TRM-C`).

## TRM-AA: the screen model

1. The scroll region is rows `top...bottom`, 0-based; LF, IND and NEL at the bottom row scroll it up, RI at the top row scrolls it down, a cursor outside the region moves freely. CUU stops at the top margin when the cursor starts at or below it, CUD at the bottom margin when it starts at or above it. DECSTBM with top not above bottom is ignored; a valid one homes the cursor. IL and DL do nothing outside the region and move the cursor to column 0; SU and SD count is clamped to the region.
2. Rows leave to scrollback only when the region is the whole primary screen. A scroll inside a partial region, and every scroll on the alternate screen, drops the row. Reason: an absolute row number is "scrolled-off count plus screen index", and a partial region would renumber the rows below it. **Differs from xterm** (Alloy review, 2026-11-16, accepted for v1): xterm also saves the line leaving a region whose top margin is row 1 and whose bottom margin is above the last row (a pinned footer). Matching it would renumber the rows below the region on every scroll, breaking the stable `TerminalPosition.row` of a selection or anchor there; doing it without renumbering needs a per-row identity, left for later.
3. Erase and scroll use the pen's background and nothing else (background colour erase): an erased cell and a row brought in by a scroll carry `background = pen.background`. ED 3 empties scrollback. Erasing to the end of a row also ends its soft wrap. An erase that touches half a wide cell blanks the whole cell; ICH, DCH, ECH and IRM never leave half of one.
4. ICH, DCH, ECH, IL and DL clear the pending wrap (IL and DL also move to column 0); ED and EL leave it, so `abcd ESC[K` on a 4-column row erases the last cell and the cursor stays pending.
5. Plain-ASCII rows without attribute spans edit in place (insert, delete, truncate); every other case rebuilds the row from one slot per column and merges equal spans, so wide cells and attributes are handled in one place. Storage stays the `TRM-F` layout: no struct or `Character` per stored cell.

Why: vttest's scrolling-region and insert/delete screens, and xterm's behaviour where the frozen model leaves a choice.

## TRM-AB: save/restore, the alternate screen and resets

1. DECSC saves position, pending wrap, pen, origin mode, the four charsets and the shift state; each screen has its own slot, so 1049 (which saves on the primary slot) does not clobber a DECSC made inside the alternate screen. DECRC with nothing saved goes home with defaults.
2. 47 swaps to the alternate screen keeping its last contents; 1047 does the same and clears it when left; 1049 saves the cursor, clears the alternate screen on entry and restores the cursor on exit; 1048 is save/restore alone. Entering when already there, or leaving when not there, does nothing. The cursor position carries across 47 and 1047. A switch publishes a full frame, and `rowText` for screen rows answers the screen that shows.
3. DECSTR resets cursor visibility, cursor style, origin mode, autowrap (to on), application cursor keys and keypad, insert mode, the region, the pen, the charsets and the saved cursors; it leaves the screen, the cursor position, the alternate screen, tab stops and the mouse, paste and focus modes. RIS is the power-on state with a blank screen on the primary screen; scrollback is kept (history survives a `reset`).
4. DECOM set or reset homes the cursor. The cursor-position report is region-relative in origin mode. DECRQM answers 1 set, 2 reset, 4 permanently reset (mode 69, ANSI 20) and 0 for anything else.

Why: xterm's documented behaviour; the choices on DECSTR autowrap and RIS scrollback are MetalUI's (an app that soft-resets expects wrapping, and a user who runs `reset` expects history to stay).

## TRM-AC: graphics sets, REP and insert mode

G0-G3 hold `ascii` (final `B`, and any set not known), `decGraphics` (`0`) or `uk` (`A`); SO selects G1 and SI G0. Only printable ASCII is translated (UTF-8 above it is never a 7-bit set), and while the set in GL is not ASCII, or insert mode is on, printable bytes take a per-scalar path so the plain-ASCII fast path costs nothing. DEC graphics maps 0x5F-0x7E; 0x5F shows a blank. REP repeats the last printed scalar (after translation, wide ones included, nothing when none), at most 65 535 times. IRM (SM/RM 4) inserts blanks before each printed cell.

Why: vttest's character-set screens and the spec's list; keeping the fast path unconditional keeps the bench honest.

## TRM-AD: SGR and the replies

1. `TerminalAttributes` gains `underlineStyle` (`TerminalUnderlineStyle`: none, single, double, curly, dotted, dashed), `underlineColor` and `blink`; `underline` stays and reads `underlineStyle != .none` (writing sets single or none), so frozen readers compile unchanged.
2. SGR handles 0-9, 21-29, 30-37, 38, 39, 40-47, 48, 49, 58, 59, 90-97 and 100-107, with `;` and `:` forms (`38;5;n`, `38;2;r;g;b`, `38:5:n`, `38:2:r:g:b`, `38:2::r:g:b`, `38:2:cs:r:g:b`; `4:0`-`4:5`). 5 and 6 both set blink. A malformed or out-of-range extended colour changes nothing and ends the sequence there; what came before applies.
3. DECSCUSR 1-6 are blinking and steady block, underline and bar; 0 is a blinking block like 1 (xterm ctlseqs and VT520; Alloy's review). The power-on style stays the steady block (`TRM-F`) and DECSTR returns to it; only an explicit `CSI 0 SP q` blinks.
4. DA1 answers `CSI ? 62 ; 22 c` (VT220 class, ANSI colour), DA2 `CSI > 1 ; 0 ; 0 c`; DSR 5 answers `CSI 0 n`, DSR 6 `CSI r ; c R`, `CSI ? 6 n` `CSI ? r ; c ; 1 R`. A request with any other parameter is not answered.

Why: spec section 2.1 rule 3 (SGR in all forms) and the replies the spec requires the owner to write.

## TRM-AE: OSC 0/2/8 and the link table (Phase 1.4, record 341)

1. An OSC is `number ; text`; a payload with no `;` after the number, or no number, is dropped, as is every number not listed here (OSC 1, 4, 52 and the rest: spec section 2.1 rule 2 keeps the clipboard off). OSC 0 and 2 emit `.title(text)` with the text cut to 256 characters (not bytes; a `;` inside a title is kept); an empty title is a title.
2. OSC 8 is `params ; uri` (the uri is everything after the second `;`). A non-empty uri registers a link and puts its id in the pen (`TerminalAttributes.hyperlink`), so every cell printed until the link ends carries it; an empty uri ends it. A link is registered, and `.hyperlink(id:uri:)` raised, once per new id. Ids count from 1.
3. With `id=` among the colon-separated params, a link with the same id and the same target keeps its numeric id, so separated runs are one link; the same id with another target is a new link. Without `id=` every opening is a new link.
4. SGR 0 (and a bare `CSI m`) keeps the link; only OSC 8, DECSTR, RIS, or DECRC of a pen saved without one ends it. `TerminalSnapshot.links` is the whole table, and a publish whose only change is a new link bumps the version.

Why: spec sections 2 and 2.1; hyperlink survival over SGR 0 is what `ls --hyperlink` and `delta` rely on.

## TRM-AF: OSC 7, OSC 10/11 and what is not answered

1. OSC 7 accepts a `file` URL whose host is empty, `localhost` or this machine's host name (full or first label, case-folded) and whose path is absolute; the path is percent-decoded into `.workingDirectory(URL(fileURLWithPath:))`. Any other scheme or host, a relative path or no path is dropped, so a remote machine's `cwd` cannot point the host at a local directory.
2. The emulator has no theme colours of its own (the palette lives in `MetalUITerminalUI`). `package var queryColors` is where the owner puts the default foreground and background; with it set, `OSC 10 ; ?` and `OSC 11 ; ?` answer `.reply(ESC ] n ; rgb:rrrr/gggg/bbbb ESC \)`, the 8-bit value doubled to 16 bits. With it nil (the initial state) a query is not answered, which a program treats as an unthemed terminal; a wrong answer would make vim pick the wrong background. The reply always ends in ST (xterm mirrors the query's terminator; the parser does not carry it). Setting a colour (`OSC 10 ; spec`) is ignored.

Why: spec section 2.1 rule 4 (queries are `.reply` events) and rule 2 (no sequence opens a file).

## TRM-AG: `TerminalSnapshotSource`

1. The frozen signatures are as the spec has them. `feed` runs on `queue` (at once when already there, else a copy of the bytes is queued), feeds the emulator, publishes and merges the snapshot into one pending value: rows listed later override earlier ones, a full frame or a size change makes the result a full frame, the latest version, cursor, modes, selection and links win. `resize` keeps the newest pending size and applies it once on `queue`; `perform` runs its body on `queue` and publishes after it.
2. After each publish the source drains the emulator's events: every `.reply` goes to `onReply`, on `queue`, in order, at once; everything else queues (1 024 at most) for `onEvents`, delivered on the main actor in one batch per hop (a hop is scheduled only when none is outstanding, so a burst is one call). Events raised while `onEvents` is nil wait for the next hop after it is set.
3. The bound view attaches through `package var onWake` (called on `queue` when a snapshot is waiting and none was before; the view binds it to its `SurfaceRedrawTrigger`) and `package func takeSnapshot()` (the merged snapshot, then re-arms the wake). A flood of N feeds is N publishes and one wake, and the take is one merge result. `package var statistics` and `package var eventHop` exist for the counted tests. Nothing in `MetalUITerminalUI` exists yet; no public API is added beyond the frozen one.
4. `resize` applies through `package var resizeHandler`, which `TRM-AM` (Phase 1.5) defaults to `TerminalEmulator.resize(cols:rows:)`; a test supplies a recording handler.

Why: spec section 2 (the queue/main hand-off) and rule 6 (a flood costs one merge and one draw), and the Phase 5 hook in draft gap 2.

## TRM-AH: bounds

Titles 256 characters; OSC strings by `payloadCap` (an overlong one is dropped whole, with no event and no link); distinct links 65 536 per emulator (a link past it is not attached to cells and raises no event); queued events 1 024 in the emulator and 1 024 in the source. A flood of links, titles or directories therefore cannot grow memory without bound.


## TRM-AI: the encoder surface (amended 2026-11-16: keypad and horizontal wheel)

1. `TerminalEncoder` is the four frozen statics; `TerminalKey`, `TerminalModifiers` (`.shift .control .option .command`) and `TerminalMouseEvent` (with `init(kind:button:modifiers:)`, button and modifiers defaulted) live in `MetalUITerminal` and import no UI module. `TerminalKey.key` is `KeyEquivalent`'s spelling: U+F700-F703 up, down, left, right; U+F704-F717 F1-F20; U+F727 Insert; U+F728 forward delete; U+F729 Home; U+F72B End; U+F72C and U+F72D the page keys; U+007F Backspace.
2. **Amendment 2026-11-16 (Alloy approved, binding), both additive.** `TerminalKey.isKeypad` (default false; the init parameter is defaulted, so existing calls compile) marks a numeric-keypad key, spelled in `key` as `0`-`9`, `*`, `+`, `,`, `-`, `.`, `/`, `=` or CR for Enter. With `applicationKeypad` (DECKPAM) such a key sends `ESC O` plus a final: `0`-`9` are `p q r s t u v w x y`, `*` `j`, `+` `k`, `,` `l`, `-` `m`, `.` `n`, `/` `o`, Enter `M`, `=` `X`; a Shift, Option or Control key inserts the xterm parameter (`1 + shift + 2 alt + 4 ctrl`) before the final (Control+Enter `ESC O 5 M`). With DECKPNM (or `isKeypad` false) the key is an ordinary key and sends its character (Enter is CR). Command still encodes to `[]`. NumLock state is not modelled (the spec does not cover it). `TerminalMouseEvent.Kind` gains `wheelLeft` and `wheelRight`, buttons 66 and 67 in legacy, UTF-8 and SGR, with wheel up and down's rules (not in x10, no release, modifier bits added).
3. `encodeMouse`'s cell is the viewport cell, row and column from 0 (the caller subtracts the first visible row from a `TerminalPosition`); a negative row or column reports nothing.
4. A private-use code in U+F700-U+F8FF with no row in the table (F21 and up, Begin, Clear) encodes to nothing.

Why: spec section 2.1 rule 9 and `TRM-C` item 4.

## TRM-AJ: Command, Option and option-as-meta

1. A key with `.command` encodes to `[]` for every key and mode, so `TerminalView` declines it and menus see it (`TRM-D` item 2).
2. On arrows, Home, End, the page keys, Insert, forward delete and F1-F20, Option is the xterm Alt parameter (`m = 1 + shift + 2 alt + 4 ctrl`, so Option alone is 3) whether or not `optionAsMeta` is on. Option never sets xterm's meta bit (8).
3. On every other key, `optionAsMeta` makes Option an ESC prefix on the unmodified character: the ASCII `key` (an ASCII lower-case letter is upper-cased when Shift is held; other keys stay as `key`, so Option+Shift+1 is `ESC 1`), or `ESC` plus `characters` when `key` is not ASCII. Option with Control gives `ESC` plus the control byte; Option with Tab, Return, Escape and Backspace is `ESC` plus that key's bytes (Shift+Tab: `ESC ESC [ Z`). Without `optionAsMeta`, Option leaves `characters` (the composed text) alone.

Why: `TRM-D` item 4 (both Option keys are meta; dead keys are bypassed by the platform hint, not by the encoder) and the spec's "ESC prefix on the unmodified character".

## TRM-AK: key tables

1. Control with an ASCII letter (either case) is the letter's C0 byte; Control with `@`, Space, `` ` `` or `2` is NUL; `[` or `3` ESC; `\` or `4` FS; `]` or `5` GS; `^` or `6` RS; `_`, `-`, `/` or `7` US; `?`, `8` and Shift+`/` DEL. Control with any other key sends its `characters` unchanged. Shift never changes a Control byte.
2. Backspace is DEL, Control+Backspace BS (0x08), Shift changes neither. Tab is HT, Shift+Tab `CSI Z`, Control+Tab HT. Return and keypad-style LF are CR in every modifier combination. Escape is ESC.
3. Unmodified arrows, Home, End and F1-F4 are `CSI x` (Home `H`, End `F`) and, when `applicationCursorKeys`, `SS3 x`; F1-F4 are `SS3 P Q R S` in both modes; a key with Shift, Option or Control uses `CSI 1 ; m x` in both modes. Insert, forward delete, Page Up and Page Down are `CSI 2/3/5/6 ~` or `CSI n ; m ~`. F5-F20 are `CSI 15 17 18 19 20 21 23 24 25 26 28 29 31 32 33 34 ~`, with `; m` when modified.

Why: xterm's ctlseqs "PC-Style Function Keys" and "Control Bytes" tables, written out here, not copied from any implementation.

## TRM-AL: mouse, paste and focus bytes

1. Reporting by mode: x10 reports left, middle and right presses and nothing else, without modifier bits; normal (1000) adds releases and the wheel; button-event (1002) adds motion with a button held; any-event (1003) adds motion with none. A press or release with `.none` is never reported.
2. The code is the button (left 0, middle 1, right 2), plus 32 for motion (motion with no button is 3 + 32), 64 up and 65 down for the wheel (presses only, no release), plus Shift 4, Option 8, Control 16; Command adds nothing. Coordinates are 1-based.
3. Legacy is `ESC [ M` and three bytes of 32 + value; a column or row above 223 drops the whole report, never wraps. A release in legacy and UTF-8 is button 3 plus the modifier bits. UTF-8 (1005) writes each value 32 + n as one or two UTF-8 bytes and drops a report above 2015. SGR (1006) is `ESC [ < code ; col ; row M`, a release the button's own code and `m`, with no coordinate limit.
4. Paste drops every byte below 0x20 except tab, LF and CR (the ESC of an embedded `ESC[201~` goes, leaving `[201~` as text), changes nothing else (no LF to CR conversion), and wraps in `ESC[200~ ... ESC[201~` only with `bracketedPaste`. Focus is `ESC[I` or `ESC[O` only with `focusEvents`.

Why: spec section 2.1 rule 9 and xterm's mouse tracking description.

## TRM-AM: `resize(cols:rows:)` and absolute rows (Phase 1.5, record 345)

1. `resize(cols:rows:)` is the frozen signature; the size clamps to 2 x 1 (`TRM-B`). The same size after clamping is a no-op (no damage, no version). Any other size sets the next publish to a full frame, resets the scroll region to the whole screen (xterm does too), keeps origin mode, clears the pending wrap (except where the reflow keeps one, `TRM-AN`), and raises no event: the pty's own window size is the owner's call (`PseudoTerminal.resize`).
2. **Absolute rows after a resize.** The oldest retained row keeps its absolute number; `firstRow` moves only by the rows the scrollback capacity evicts during the resize; every later row is renumbered consecutively, and the screen's first row is `firstRow` plus the retained scrollback count. A resize that changes only the height therefore keeps every row's number and text (rows move between the screen and scrollback, the numbers do not). A resize that changes the width renumbers, because the row count above the screen changes; it increments `TerminalEmulator.reflowGeneration`, which the next snapshot carries (`TerminalSnapshot.reflowGeneration`) with `isFullFrame == true`.
3. **What Phase 1.6's selection must do** (stated here so it cannot diverge): a `TerminalPosition` is valid only for the reflow generation it was taken in. A selection that sees a snapshot of a later generation is cleared (the text under a range cannot be named across a rewrap without per-row identity, which the model does not have, `TRM-AA` 2); height-only resizes keep it. Phase 1.6 may refine this; it may not reuse a position across generations.
4. Tab stops keep their columns; columns past the old width get the default stops (every 8th). A DECSC slot on the primary screen follows its character through the reflow like the cursor, and clamps to the grid when it fell into scrolled-off or blank rows; the alternate screen's slot clamps. The scroll region is reset (rule 1), so a program that wants one sets it again on SIGWINCH.

Why: xterm resets margins on resize and clamps saved cursors; renumbering is forced by reflow, so the rule keeps the one number that cannot move (the oldest retained row) and gives the host one integer to compare.

## TRM-AN: rewrap

1. **The unit is a logical line**: a run of rows joined by the soft-wrap flag (`wrapsToNext`), across the scrollback and screen boundary. Only the primary screen and its scrollback rewrap; hard lines (no flag) never join, and a line that already fits is untouched.
2. A line is cut into rows of the new width cell by cell. **A wide character never splits**: when it does not fit in the last column the row ends one column short (flagged soft-wrapped) and the character starts the next row. That empty column is not text: joining rows does not carry it, so widening and narrowing back restores the line.
3. **Blanks.** Trailing blanks in the default rendition at the end of a line are not carried; a coloured blank (background erase, a status bar) is content and is. A soft-wrapped row keeps its own trailing blanks (they are text of the longer line), so `ScrollbackRing` rows that wrap are not trimmed by `compact()`. When joining, a wrapped row stored shorter than the old width is padded with blanks to that width, except for the one-column gap rule above.
4. **The cursor stays on its character** (the cell it addressed, a wide cell included). A cursor past the end of the text keeps its column: the line is lengthened by blanks that exist only to hold it (they are not stored in the rows), so a cursor at the start of a full row gets its own row, flagged as the same line. A pending wrap survives only when the line still ends exactly at the right edge (the cursor on the last cell of a full row); otherwise it is cleared and the cursor sits on the next column.
5. Attributes and hyperlink ids ride with their cells. Text, attribute spans, `isASCII` and the used width of each new row are rebuilt from the joined line; a row that fits is moved without copying its storage.
6. Round trip: narrowing to any width and widening back (with enough scrollback not to evict) gives the original logical lines, text and attributes, when the original had no trailing default blanks stored; the property test checks it.

Why: the spec asks for reflow with cursor tracking and no split wide character; the soft-wrap flag is the only join signal terminals keep, as xterm-family and Terminal.app do.

## TRM-AO: rows, the screen's top and the hidden primary

1. After the rewrap the content is the rows up to the last one holding text, attributes, a wrap flag or the cursor; blank rows below it are not content. The screen shows `rows` rows starting at `top`, where `top` starts as the new index of the old screen's first row, then:
   - **growing**: `top` moves up by the added rows, so rows come back from scrollback and the cursor moves down with them (as xterm and Terminal.app do); with less scrollback than rows added, the rest is blank at the bottom;
   - **shrinking**: blank rows below the content go first; if content still does not fit, the top rows go to scrollback, but never so far that the cursor leaves the screen (rows below that are dropped from the bottom);
   - the cursor row is always on the screen afterwards.
2. Rows leaving the screen are compacted like a scroll (`TRM-F`); scrollback keeps the newest rows that fit its capacity, so a narrowing that multiplies the rows evicts the oldest and `firstRow` advances (`TRM-AM` 2).
3. **While the alternate screen shows**, the primary (hidden) screen reflows the same way, following the DECSC slot saved on entry (1049/1048) as its cursor; with no slot it is anchored by its content alone. 47 and 1047 saved nothing, so the primary comes back with the cursor clamped.
4. **The alternate screen clips**: columns past the new width are cut (a wide cell cut in half is blanked), rows past the new height are dropped from the bottom, new rows are blank; nothing wraps, no row keeps a wrap flag; the cursor clamps and its pending wrap clears. The alternate buffer that is not showing is clipped the same way so both buffers always match the grid.

Why: xterm and Terminal.app pull from and push to scrollback with the window; a full-screen program repaints the alternate screen on SIGWINCH, so clipping loses nothing it will not redraw.

## TRM-AP: cost

A resize that changes only the height does not rewrap: it moves rows. A width change visits every retained row once (one pass to find lines, one to rebuild the ones that change; a row that fits is relabelled, not copied). Measured in release on the macOS arm64 dev machine: reflow of 10 068 retained rows (120 columns, mixed soft and hard lines, some coloured and wide) takes 1 ms best and 3 ms worst over 80, 120, 200 and 120 columns, against a proposed bound of 50 ms (the gated bench `reflowOfTenThousandScrollbackRows`, `METALUI_RUN_TERMINAL_BENCH=1`). Reflow runs on the emulator's queue and `TerminalSnapshotSource.resize` coalesces a drag into one call, so nothing here is on the main thread.

## TRM-AU: the grid sink records rects as glyph instances over a solid atlas slot (Phase 5.1, record 347)

1. `SurfaceTextSink` (`package`, `MetalUIScene`) is also the grid sink: besides `append(_:)` for glyph sprites it records `fillRect(_:color:clip:)`, a solid rectangle in device pixels of the surface's own target, in call order with the glyphs, in the surface's one batch. `fillRect` returns `false` and records nothing when the atlas has no room for the solid slot. No public API (`TerminalView` is 5.3).
2. **A rect is one `MUIGlyph`** whose source is the reserved solid slot: `GlyphKey` with the font `MetalUI.GridSink.Solid`, packed through the frame's atlas on first use like any glyph (`SurfaceTextSink.solidKey`, `solidSlot`), a 4 x 4 square of coverage 255. The renderers' existing glyph pipelines, the existing `ReplaySurfaceText` pass and the existing atlas upload (`DT-B`) draw it: no C, shader, blob, pipeline or fixture change (`TE-AD`).
3. **The sampled square is the slot's inner 2 x 2** (`solidInset` 1): `glyph_fragment` samples with `filter::linear`, and a quad stretched over a rect larger than its source reads `atlasPosition` anywhere in the source rectangle, so a source that is the whole slot reads the neighbouring texels at the quad's right and bottom edges (the atlas packs slots flush, so they are other glyphs' or empty). With a one-texel margin the filter's footprint (the sampled square grown by one texel) is inside the slot at every pixel of any rect size, edge pixels included. Measured on Metal (arm64) with `solidInset` 0, the whole slot as the source: the last columns and rows of a rect read short of coverage (a 17 x 9 red rect's pixel at x 19 reads 217 of 255, a 1-wide blue column's bottom pixel 170, a white 8 x 8 cell's bottom row 191), and the SDL tests go red the same way; with 1 every pixel of 1 x 1, 1 x 12 and 17 x 9 rects, and of adjacent 8 x 8 cells, is the exact colour at scale factors 1 and 2. **So the quad path (`ReplaySurfaceQuads`) is not built**: the bleed was real but is removed by the margin alone.
4. Colours are `MUIHsla` (`Scene` is platform-free); primaries, black, white and greys read back byte-exact, other colours within the GPU's one-step rounding.
5. The mask defaults to the rect itself; an explicit `clip` is for the cursor, a selection or a row clipped to the view's bounds.

## TRM-AV: a retained target and damaged rows

1. A surface's target persists between frames: the renderer's `SurfaceTargetTable` keeps the texture for as long as the scene references the surface at the same device-pixel size and clears it to transparent only when it is new (a first frame or a resize; `isNewTarget`, `MV-E`). Neither renderer clears a surface it redraws: the app's draw runs first and then the grid's pass, load op `.load` (Metal `Renderer.encodeSurfaceText`; SDL `mui_renderer_finish`, `LOADOP_LOAD`).
2. So a view redraws only the damaged rows by recording, for each such row, an **opaque** background rect over the row's whole cell span and then the row's glyphs, cursor and decorations in call order; everything else keeps the previous frame's pixels exactly. A translucent background would composite over the old row, so a row redraw must use an opaque background (the default background is drawn as one too). A new or resized target must be redrawn in full (`isNewTarget`).
3. The sink does not choose rows; it records what it is given. The one-pass-per-surface order (`DT-A`) is the paint order within the frame.

## TRM-AW: cost

A `GPUSurface` using the grid sink builds no element: the sink is renderer-side and records into the frame's sink, so a surface that records rects and glyphs costs the element requests of a surface that records glyphs (`aGridSurfaceCostsTheElementRequestsOfATextSurface`, per-frame literals equal). A frame with no sink use runs no pass (`DT-A`).

Next unused: `TRM-AX` (`TRM-AQ`..`TRM-AT` belong to the open resize/view work in PR #350).

