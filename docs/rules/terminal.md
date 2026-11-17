# The terminal (`TRM-`)

Rulings: `docs/superpowers/2026-11-16-terminal-decisions.md`; frozen and draft signatures: `docs/superpowers/specs/2026-11-16-terminal-design.md`; record 334 (Phase 0). One or two sentences per rule; detail lives in the record of the PR that landed it.

**Module split** (`TRM-A`). `MetalUITerminal` (emulator, encoders, `PseudoTerminal`, `TerminalSnapshotSource`) is UI-free and imports nothing from MetalUI, AppKit, Metal or SDL; `TerminalView` lives in `MetalUITerminalUI`. No MetalUI product depends on either, and the parser is written in-house with no third-party code read or copied.

**Freeze** (`TRM-B`). Gaps 1, 3 and 4 are frozen by record 334 and change only by a new `TRM-` ruling Alloy accepts; gaps 2 (`TerminalView`, `TerminalPalette`) and 5 (`SurfaceRedrawTrigger`) are draft until the start of Phase 5.

**Replies** (`TRM-C`). A `TerminalEvent.reply` MUST be written to the pty by the owner; a host that drops it breaks vim and less. `TerminalPalette.boldIsBright` defaults to false and bold is the bold face only; the blink idle stop is a view flag.

**Key capture** (`TRM-D`). A capture layer hears a key before every other stage, `except` shortcuts skip it, and a key answered `.ignored` (including every key that encodes to nothing) goes through the unchanged pipeline from its first stage. Option-as-meta covers both Option keys and bypasses dead keys while on; nothing is captured while marked text composes.

**Key capture, built** (`TRM-U`..`TRM-Y`, record 338). `keyCapture(except:optionAsMeta:)` marks the keyboard layer of the `onKeyPress` handlers it sits with (a marker handler on `KeyboardAttachment.capture`, not a `Handlers` member); `Window.dispatchKeyCapture` is the first key stage and offers the key once, outermost layer first; `except` and marked text skip it; `PlatformWindow.setRawOptionKeys(_:)` follows focus and bypasses `inputContext` for Option on AppKit (Alt on SDL).

**Platforms** (`TRM-E`). Windows 10 1809+ and Linux 5.3+ (pidfd); the Windows default shell is `pwsh` else `powershell`; on Windows `.interrupt` writes 0x03 and the other signals terminate the job object, and there is no foreground group.

**Storage** (`TRM-F`). A row is UTF-8 text plus run-length attribute spans, copy-on-write, never a struct or `Character` per cell; scrollback is a ring of compacted rows, and a 10 000 x 120 ASCII scrollback is proved under 4 MB by a counted byte census.

**Parser** (`TRM-G`). UTF-8 is decoded first (U+FFFD per maximal invalid subpart, the breaking byte decoded afresh), C1 controls are the scalars U+0080-U+009F, string payloads are capped in bytes and an overlong one is dropped to its terminator, and any split of a stream gives the same state.

**Phase 1.2 seam** (`TRM-H`). The emulator prints, wraps and moves the cursor and records mode flags; every other sequence is parsed and dropped until its phase, so no declared behaviour is a stub. Fixtures are `Tests/MetalUITerminalTests/Fixtures/*.vtfix` (`TRM-I`); the parser guards are chunk invariance, seeded fuzz, the census and the gated bench (`TRM-J`).

**POSIX pty** (`TRM-K`..`TRM-O`). `PseudoTerminal` starts its child with `posix_spawn` and `POSIX_SPAWN_SETSID` (the child's own first open of the slave gives it the controlling tty; the C `fork` path stays for glibc below 2.34 and tests run both), with exactly fds 0-2, every signal at default, and the size set before the child exists through a slave the parent holds open (Darwin forgets a size set on an unopened pty).

**Pty I/O** (`TRM-M`, `TRM-N`). `read` is >0, 0 would block or -1 end of file (a 0-byte read, EIO, or after `close`), latched so the level-triggered source stops firing; `write` queues on an internal queue, never blocks, never drops, never reorders.

**Pty lifetime** (`TRM-O`). No SIGCHLD handler: macOS process source, Linux pidfd (shared poll fallback); one reap under the lock that `signalGroup` takes, so a reaped pid is never signalled; `close()` stops callbacks, not reaping; Windows has no `PseudoTerminal` yet.

**Phase 1.3 screen** (`TRM-Z`..`TRM-AD`). The emulator executes cursor motion within margins and origin mode, erase with background colour, insert/delete, scroll regions, tab stops, DECSC/DECRC per screen, the alternate screen (47/1047/1049), DECSTR/RIS, DEC graphics, REP, SGR in `;` and `:` forms and the DA/DSR/CPR/DECRQM replies; DECSLRM is skipped. Rows reach scrollback only from a full-screen scroll on the primary screen; every reply is a `TerminalEvent.reply` from `drainEvents()` that the owner MUST write, and only `.reply` and `.bell` are emitted before OSC (1.4).

**Phase 1.4 OSC and snapshot source** (`TRM-AE`..`TRM-AH`, record 341). OSC 0/2 give `.title` (256 characters), OSC 7 a `.workingDirectory` for a `file` URL on a local host only, OSC 8 a link id in the pen (kept over SGR 0, reused by `id=` plus target, `TerminalSnapshot.links`), OSC 10/11 queries answer only when the owner set `queryColors`; OSC 52 and the rest are dropped. `TerminalSnapshotSource` publishes and merges on every feed, wakes the bound view once until `takeSnapshot()`, sends `.reply` to `onReply` on the queue and everything else to `onEvents` in one main-actor batch per hop.

**Cost.** A terminal output, blink or selection frame costs 0 builds and 0 element requests, and a hidden or idle terminal schedules nothing; every shared-view change pins the steady-frame request counts for apps that do not use it.

**Tests.** Pty and parser tests bound every wait and never sleep for timing; each guard is shown red against the wrong routing first (`docs/practices/verifying-tests-can-fail.md`).

**Surface-only redraw** (`TRM-P`..`TRM-T`, record 337; gap 5, draft until Phase 5). `SurfaceRedrawTrigger.requestRedraw()` redraws one `GPUSurface` in a frame with no build: `Window.drawFrameIfNeeded` re-encodes `lastScene` and hands the renderer only the pending surfaces' requests (`SurfaceDrawRequest.isForced`), and a full frame forces the same requests whenever the window is dirty, animating, on a timer or the scale, size or atlas `layoutGeneration` moved. A trigger whose surface the last frame did not paint is a no-op (unbound), `requestRedraw(after:)` keeps the earliest deadline per surface on the frame clock. A change to shared view paths pins an untriggered surface's steady-frame numbers (`SurfaceOnlyRedrawTests`).
