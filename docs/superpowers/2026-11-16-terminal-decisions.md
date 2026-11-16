# Terminal (Alloy gaps 1-5) - decisions (prefix `TRM-`)

Rulings for Alloy's integrated terminal, built as `docs/superpowers/specs/2026-11-16-terminal-design.md` lays out; plan `docs/superpowers/plans/2026-11-16-terminal.md`; record 334 (Phase 0). `TRM-` is distinct from `TM-` (`Text` view modifiers and dash patterns) and has no relation to any other prefix. "Alloy's answer" below means the binding answers sent on 2026-11-16 to the ten questions of the plan; where an answer and the plan differ, the answer wins. Divergence labels 1095-1104 are reserved for `TRM-`; every declaration in this work is class `M`, so none is expected to be used.

Next unused id: `TRM-P`. `TRM-F`..`TRM-J` are reserved by the parallel emulator and key-capture branches; `TRM-K`..`TRM-O` (the POSIX `PseudoTerminal`, record 336) are used.

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

Nothing installs a `SIGCHLD` handler. macOS reaps from a `DispatchSource` process source plus one `waitpid(WNOHANG)` right after it is armed (the child may have gone first); Linux reads a `pidfd_open` descriptor (kernel 5.3+, `TRM-E`) and, where that is missing, one shared 20 ms timer polls `waitpid(WNOHANG)` for every unreaped child (a `package` flag forces it for its test). The reap and the `exitStatus` result happen once, under the object's lock, and the same lock guards `signalGroup` (`killpg`, a no-op after the reap, so a reused pid is never signalled). `close()` does not stop reaping: the hangup from a closed master ends the child and it is still reaped, `exitStatus` still resolves, and an unclosed object is closed by `deinit`. On Windows the target compiles but `PseudoTerminal` and `PseudoTerminalError` are absent (`#if !os(Windows)`, and `CPseudoTerminal` is empty there); Phase 2.3 supplies them. `TerminalSize` is the one file the emulator branch shares (`Sources/MetalUITerminal/TerminalSize.swift`, spec shape).

