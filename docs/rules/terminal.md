# The terminal (`TRM-`)

Rulings: `docs/superpowers/2026-11-16-terminal-decisions.md`; frozen and draft signatures: `docs/superpowers/specs/2026-11-16-terminal-design.md`; record 334 (Phase 0). One or two sentences per rule; detail lives in the record of the PR that landed it.

**Module split** (`TRM-A`). `MetalUITerminal` (emulator, encoders, `PseudoTerminal`, `TerminalSnapshotSource`) is UI-free and imports nothing from MetalUI, AppKit, Metal or SDL; `TerminalView` lives in `MetalUITerminalUI`. No MetalUI product depends on either, and the parser is written in-house with no third-party code read or copied.

**Freeze** (`TRM-B`). Gaps 1, 3 and 4 are frozen by record 334 and change only by a new `TRM-` ruling Alloy accepts; gaps 2 (`TerminalView`, `TerminalPalette`) and 5 (`SurfaceRedrawTrigger`) are draft until the start of Phase 5.

**Replies** (`TRM-C`). A `TerminalEvent.reply` MUST be written to the pty by the owner; a host that drops it breaks vim and less. `TerminalPalette.boldIsBright` defaults to false and bold is the bold face only; the blink idle stop is a view flag.

**Key capture** (`TRM-D`). A capture layer hears a key before every other stage, `except` shortcuts skip it, and a key answered `.ignored` (including every key that encodes to nothing) goes through the unchanged pipeline from its first stage. Option-as-meta covers both Option keys and bypasses dead keys while on; nothing is captured while marked text composes.

**Platforms** (`TRM-E`). Windows 10 1809+ and Linux 5.3+ (pidfd); the Windows default shell is `pwsh` else `powershell`; on Windows `.interrupt` writes 0x03 and the other signals terminate the job object, and there is no foreground group.

**Cost.** A terminal output, blink or selection frame costs 0 builds and 0 element requests, and a hidden or idle terminal schedules nothing; every shared-view change pins the steady-frame request counts for apps that do not use it.

**Tests.** Pty and parser tests bound every wait and never sleep for timing; each guard is shown red against the wrong routing first (`docs/practices/verifying-tests-can-fail.md`).
