# Terminal (Alloy gaps 1-5) - design and API freeze

Status: **Phase 0**. Gaps 1, 3 and 4 are FROZEN by this document; gaps 2 and 5 are DRAFT and freeze at the start of Phase 5 (`TRM-B`). Rulings: `docs/superpowers/2026-11-16-terminal-decisions.md` (prefix `TRM-`). Plan: `docs/superpowers/plans/2026-11-16-terminal.md`. Requester's design (read-only, Alloy repo): `2026-11-16-terminal-design.md` there; Alloy's answers of 2026-11-16 are binding and override where they differ. Amendments to Alloy's text are marked **[A]**; amendments made in Phase 0 are listed in `TRM-C`.

Normative words: MUST, MUST NOT, MAY. A frozen signature changes only by a new `TRM-` ruling that Alloy accepts; a draft signature changes freely until Phase 5 but MUST be re-sent to Alloy at the freeze.

## 1. Module shape (`TRM-A`)

| target / product | depends on | contains | platforms |
|---|---|---|---|
| `CPseudoTerminal` (C) | none | spawn, tty and ConPTY shims | macOS, Linux, Windows |
| `MetalUITerminal` | Foundation, Dispatch, `CPseudoTerminal` | parser, emulator, snapshot, encoders, `TerminalSnapshotSource`, `PseudoTerminal` | macOS, Linux, Windows |
| `MetalUITerminalUI` | `MetalUI`, `MetalUITerminal` | `TerminalView`, `TerminalPalette`, the `KeyPress` encoder overload, `package` hooks into MetalUI | wherever MetalUI builds |

- `MetalUITerminal` MUST NOT import `MetalUI` or any `MetalUI*` target. It MUST NOT import AppKit, Metal or SDL.
- `MetalUITerminal` joins the root package's non-Apple target list (`PC-A`) and so builds on Linux and Windows without SDL. No MetalUI product depends on either terminal target: an app that does not import them pays nothing.
- Both are library products. `CPseudoTerminal` is not a product.
- No iOS-family conformer exists or is planned (`PB-A`); the targets are macOS, Linux and Windows only.

## 2. Gap 1 - emulator, snapshot, events, modes, encoders (FROZEN)

All declarations are `public` in `MetalUITerminal`.

```swift
public struct TerminalSize: Hashable, Sendable {
    public var cols: Int
    public var rows: Int
    public init(cols: Int, rows: Int)            // clamps to at least 2 x 1
}
public struct TerminalPosition: Hashable, Comparable, Sendable {
    public var row: Int                          // absolute line number since start; stable across scrolling;
    public var col: Int                          // rows below TerminalEmulator.firstRow have been evicted
    public init(row: Int, col: Int)
}
public struct TerminalRange: Hashable, Sendable {
    public var lowerBound: TerminalPosition
    public var upperBound: TerminalPosition
    public init(lowerBound: TerminalPosition, upperBound: TerminalPosition)
}
public enum TerminalSelection: Hashable, Sendable { case linear(TerminalRange), block(TerminalRange) }

public final class TerminalEmulator {            // NOT Sendable: confined to one serial queue chosen by the caller
    public init(cols: Int, rows: Int, scrollback: Int = 10_000, payloadCap: Int = 4096)
    public var firstRow: Int { get }             // oldest retained absolute row
    public func feed(_ bytes: UnsafeRawBufferPointer)
    public func resize(cols: Int, rows: Int)     // reflows the primary screen; the alternate screen clips
    public func publishSnapshot() -> TerminalSnapshot   // carries the damage since the previous publish
    public var modes: TerminalModes { get }
    public func drainEvents() -> [TerminalEvent]        // [A] drained, not a property; empties the queue
    public var selection: TerminalSelection? { get set }
    public func selectedText() -> String?        // trailing blanks trimmed per row
    public func search(_ needle: String, from: TerminalPosition, backwards: Bool) -> TerminalRange?
    public func rowText(_ row: Int) -> String?   // nil for an evicted or not-yet-existing row
    public func scrollViewport(toOffset rows: Int)      // 0 = live bottom
}

public enum TerminalEvent: Sendable, Equatable {
    case title(String)                           // capped at 256 characters
    case workingDirectory(URL)                   // OSC 7
    case bell
    case hyperlink(id: UInt32, uri: String)      // OSC 8; the id keys TerminalSnapshot.links
    case reply([UInt8])                          // [A] bytes the emulator MUST have written to the child: DA1/DA2,
}                                                //     DSR/CPR, DECRQM, OSC 10/11 queries. The owner writes them to the pty.

public struct TerminalModes: Hashable, Sendable {
    public var applicationCursorKeys: Bool, applicationKeypad: Bool, bracketedPaste: Bool, focusEvents: Bool,
               alternateScreen: Bool, cursorVisible: Bool, autowrap: Bool, originMode: Bool
    public var mouseTracking: MouseTracking     // .off, .x10, .normal (1000), .buttonEvent (1002), .anyEvent (1003)
    public var mouseEncoding: MouseEncoding     // .legacy, .utf8 (1005), .sgr (1006)
    public var cursorStyle: TerminalCursorStyle // shape (.block, .bar, .underline) and blinking: Bool
    public init()                               // the power-on state
}
public enum MouseTracking: Hashable, Sendable { case off, x10, normal, buttonEvent, anyEvent }
public enum MouseEncoding: Hashable, Sendable { case legacy, utf8, sgr }
public struct TerminalCursorStyle: Hashable, Sendable {
    public enum Shape: Hashable, Sendable { case block, bar, underline }
    public var shape: Shape
    public var blinking: Bool
    public init(shape: Shape, blinking: Bool)
}
public struct TerminalCursor: Hashable, Sendable {
    public var row: Int, col: Int               // viewport coordinates
    public var visible: Bool, pendingWrap: Bool
}

public struct TerminalDamagedRow: Sendable { public let index: Int; public let row: TerminalRow }  // index = viewport row
public struct TerminalSnapshot: Sendable {
    public let version: UInt64                  // strictly increases on every publish that changes anything
    public let size: TerminalSize
    public let viewportOffset: Int
    public let damagedRows: [TerminalDamagedRow]// copy-on-write rows; an undamaged row is shared by identity with the previous snapshot
    public let isFullFrame: Bool                // after resize, reflow, alternate-screen switch and viewport scroll: every row is listed
    public let cursor: TerminalCursor
    public let modes: TerminalModes
    public let selection: TerminalSelection?
    public let links: [UInt32: String]
}
public struct TerminalRow: Sendable, Hashable {
    // compact: UTF-8 text plus run-length attribute spans; never one struct per cell
    public var text: String { get }
    public var columns: Int { get }
    public func cell(at column: Int) -> TerminalCell   // grapheme, width (1 or 2), attributes
    public var graphemes: [TerminalCell] { get }
}
public struct TerminalCell: Sendable, Hashable {       // grapheme, width, TerminalAttributes (fg/bg TerminalColor, bold, dim, italic,
    public let grapheme: Character                     // underline, strike, inverse, hidden, hyperlink id)
    public let width: Int
    public let attributes: TerminalAttributes
}
public enum TerminalColor: Hashable, Sendable { case `default`, indexed(UInt8), rgb(UInt8, UInt8, UInt8) }
public struct TerminalAttributes: Hashable, Sendable {
    public var foreground: TerminalColor, background: TerminalColor
    public var bold, dim, italic, underline, strikethrough, inverse, hidden: Bool
    public var hyperlink: UInt32?
}

// Encoders: pure, no emulator state. [A] one static namespace.
public enum TerminalEncoder {
    public static func encodeKey(_ key: TerminalKey, modes: TerminalModes, optionAsMeta: Bool) -> [UInt8]
    public static func encodeMouse(_ event: TerminalMouseEvent, at cell: TerminalPosition, modes: TerminalModes) -> [UInt8]
    public static func encodePaste(_ text: String, modes: TerminalModes) -> [UInt8]
    public static func encodeFocus(_ focused: Bool, modes: TerminalModes) -> [UInt8]
}
public struct TerminalKey: Sendable {                  // [A] in the core, in KeyEquivalent's spelling (private-use \u{F700}.. for arrows, F-keys)
    public var key: Character
    public var characters: String                      // the characters the key produced (empty for non-text keys)
    public var modifiers: TerminalModifiers
    public init(key: Character, characters: String, modifiers: TerminalModifiers)
}
public struct TerminalModifiers: OptionSet, Hashable, Sendable { /* .shift .control .option .command */ }
public struct TerminalMouseEvent: Sendable {
    public enum Kind: Sendable { case press, release, move, wheelUp, wheelDown }
    public enum Button: Sendable { case left, middle, right, none }
    public var kind: Kind, button: Button
    public var modifiers: TerminalModifiers
}
```

`MetalUITerminalUI` adds `TerminalEncoder.encodeKey(_ press: KeyPress, modes: TerminalModes, optionAsMeta: Bool) -> [UInt8]` (Alloy's spelling) as an overload that forwards to the core one.

```swift
// The queue/main hand-off. [A] New.
public final class TerminalSnapshotSource: @unchecked Sendable {
    public init(emulator: TerminalEmulator, queue: DispatchQueue)  // takes ownership of `emulator`; only `queue` touches it afterwards
    public func feed(_ bytes: UnsafeRawBufferPointer)              // on `queue`: feed, merge-publish, wake the bound view once
    public func resize(_ size: TerminalSize)                       // on `queue`; a newer resize replaces a pending one
    public var onReply: (@Sendable ([UInt8]) -> Void)?             // called on `queue`, in order, for every .reply event
    public var onEvents: (@MainActor ([TerminalEvent]) -> Void)?   // every other event, coalesced, at most once per frame
    public func perform(_ body: @escaping @Sendable (TerminalEmulator) -> Void)  // selection, search, rowText requests run on `queue`
}
```

### 2.1 Behaviour rules (frozen with the signatures)

1. **Parser.** Written in-house from the ECMA-48 and DEC state-machine descriptions; no third-party code read or copied (`TRM-A`). Chunk-split invariant: feeding any partition of a byte stream gives the same state. UTF-8 is decoded incrementally; an invalid sequence yields U+FFFD and never consumes the next valid byte. Random input MUST NOT trap and MUST keep the cursor inside the grid.
2. **Payloads.** OSC, DCS and APC payloads are capped at `payloadCap` (default 4096); an overlong payload is dropped to its terminator and the parser recovers. A title is capped at 256 characters. OSC 52 (clipboard) is off. No sequence can make the host open a file or run a command.
3. **Screen.** Cursor movement and erase, insert and delete (characters, lines), scroll regions (DECSTBM; DECSLRM optional), tab stops, DECSC/DECRC, alternate screen 47/1047/1049, DEC special graphics, wide (2-cell) and combining characters, pending wrap at the last column. SGR: 16 colours, 256, truecolor, both `;` and `:` forms.
4. **Replies.** DA1, DA2, DSR, CPR, DECRQM, and OSC 10/11 colour queries are answered by a `.reply` event whose bytes the owner MUST write to the child. A host that drops `.reply` breaks vim and less.
5. **Resize.** The primary screen reflows (cursor tracked; a wide character never splits at the edge); the alternate screen clips. A resize publishes a full-frame snapshot.
6. **Snapshots.** `publishSnapshot()` costs O(damaged rows). Undamaged rows are shared by identity. `TerminalSnapshotSource` merges the damage of every publish since the view last took one, so a flood of N feeds before one frame costs one merge and one draw.
7. **Selection and text.** `selection` is in absolute rows and survives scrolling; `selectedText()` trims trailing blanks per row and joins linear rows with `\n`; block selection joins by row. `search` covers scrollback and the screen.
8. **Scrollback.** A ring of compact rows, default 10 000. A full 10 000 x 120 ASCII scrollback MUST stay at or under 4 MB per pane.
9. **Encoders.**
   - Keys: Control combinations (Ctrl+@ and Ctrl+Space give NUL; Ctrl+\` also NUL; Ctrl+[ ESC; Ctrl+\\ ] ^ _ and Ctrl+? per the C0 table); Option as meta with `optionAsMeta` is an ESC prefix on the unmodified character; xterm modifier parameters (`1;<m>`) on arrows, Home, End, Insert, Delete, Page keys and F1-F20; application cursor and application keypad forms.
   - A key that encodes to nothing returns `[]` (this is what `TerminalView` declines on, `TRM-D`).
   - Mouse: x10, normal, button-event and any-event tracking in legacy, UTF-8 and SGR encodings; coordinates beyond the legacy limit are dropped, not wrapped.
   - Paste: strips every C0 control except tab, CR and LF, including every ESC (so `ESC[201~` cannot end a bracketed paste early); wraps in `ESC[200~ ... ESC[201~` only when `bracketedPaste`.
   - Focus: `ESC[I` or `ESC[O` only when `focusEvents`, else `[]`.

## 3. Gap 3 - key capture (FROZEN)

```swift
// Joins the keyboard layer exactly as onKeyPress does (KF-AD): on StyledElement, ElementGroup and ProposalElementGroup,
// with the return type onKeyPress has on each (`KeyboardModifier<Self>` on a proposal chain, `KeyPressed` on an ElementGroup).
public func keyCapture(except shortcuts: [KeyboardShortcut] = [], optionAsMeta: Bool = false) -> /* as onKeyPress */
```

[A] This replaces `.focusable(interactions: .captureAllKeys(except:))`: `FocusInteractions` is an `Int` `OptionSet` and cannot carry a payload. The capture state rides `KeyboardAttachment` as a new field; it is not a new `Handlers` member (pinned at 480).

**Order.** For a key event whose focus chain contains a capture layer (the layer is on the focused element or an ancestor):

1. Marked text composing: nothing is captured; the key goes to the input context as today.
2. A key that matches an `except` shortcut (`KeyboardShortcut.matches`, so `.primary` maps per platform) skips capture and continues at step 4.
3. Otherwise the capture layer's `onKeyPress` handlers (the same layer, outermost capture first, `KF-C`) get the key **before every other stage**: the Keymap, the `KF-X` command decline, field editing keys, `onKey`, clipboard, the context-menu key, `Button` shortcuts, commands, F10, Tab and `onInput`. On AppKit this includes the `performKeyEquivalent` path that precedes the main menu (`MN-J`, `MN-AI`).
4. A handler that answers `.handled` ends the event. `.ignored` hands the key to the unchanged pipeline from its first stage, so a key `TerminalView` encodes to nothing (every command-modified key) still reaches menus and commands.

`optionAsMeta: true` sends the platform a defaulted, no-op `PlatformWindow.setRawOptionKeys(_:)` hint while the capture layer is focused. AppKit then bypasses `inputContext` (dead keys and the character palette) for both Option keys; SDL treats both Alt keys as meta. IME and marked text are untouched otherwise (`TRM-D`). Not mapped on SDL today and added in Phase 4: Insert, F13-F20, the keypad; Ctrl+\` and Ctrl+Space MUST reach the encoder on X11, Wayland and Win32. Keys the OS reserves (Ctrl+Space input-source switching, Mission Control, Alt+Tab) are documented, not fixed.

## 4. Gap 4 - `PseudoTerminal` (FROZEN)

```swift
public final class PseudoTerminal: @unchecked Sendable {
    public enum Signal: Sendable { case hangup, interrupt, terminate, kill }       // [A]
    public enum ExitStatus: Sendable, Equatable { case exited(Int32), signaled(Int32) }
    public static func spawn(executable: String, argv: [String], env: [String: String], cwd: String,
                             size: TerminalSize) throws(PseudoTerminalError) -> PseudoTerminal
    public var processID: Int32 { get }
    public func onReadable(queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void)
    public func read(into buffer: UnsafeMutableRawBufferPointer) -> Int   // > 0 bytes read; 0 would block; -1 end of file
    public func write(_ bytes: [UInt8])                    // non-blocking; queued in order; never drops
    public func resize(cols: Int, rows: Int)
    public func signalGroup(_ signal: Signal)
    public var exitStatus: ExitStatus { get async }        // reaped exactly once
    public func foregroundProcessGroup() -> Int32?         // nil on Windows
    public func close()                                    // cancels readiness; idempotent; never signals after the reap
}
public enum PseudoTerminalError: Error, Sendable, Equatable {
    case openFailed(code: Int32), spawnFailed(code: Int32), unsupported(String)
}
```

### 4.1 Rules

- `spawn` takes an explicit executable and environment; it reads no defaults. The child gets exactly fds 0-2 (the slave) and a new session whose controlling tty is the pty. `env` is the whole environment. `cwd` is the working directory.
- Nothing installs a SIGCHLD handler. `signalGroup` signals the child's process group (POSIX) or follows the Windows mapping below, and is a no-op after the reap.
- `write` returns at once; a 1 MB write to a child that does not read MUST NOT block the caller. Bytes are never dropped and never reordered.
- `read` is called from the `onReadable` handler until it returns 0 (drain), on the caller's queue. After `close()` no handler runs.
- Linux: EIO on the master is end of file.

### 4.2 Mechanism per platform

| | macOS | Linux | Windows |
|---|---|---|---|
| open and spawn | `posix_openpt`/`grantpt`/`unlockpt`; `posix_spawn` with `POSIX_SPAWN_SETSID`, the slave opened by the child's first open of the tty, `CLOEXEC_DEFAULT` and `addinherit_np`; fallback (only if macOS refuses the controlling tty): a C `fork` using only async-signal-safe calls (`setsid`, `ioctl(TIOCSCTTY)`, `dup2`, `close_range`/`closefrom`, signal reset, `chdir`, `execve`) with argv and env built before the fork | the same, `posix_spawn` first | `CreatePseudoConsole` over **overlapped named pipes**; `STARTUPINFOEX` with `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`; no inherited handles; the child in a job object with kill-on-close; command line built with `CreateProcess` quoting |
| readiness | `DispatchSourceRead` | `DispatchSourceRead` | threadpool IO (`CreateThreadpoolIo`), hopping to the caller's queue |
| write | queue drained by a write source | same | overlapped write queue |
| resize | `TIOCSWINSZ` | `TIOCSWINSZ` | `ResizePseudoConsole` |
| reap | dispatch process source | `pidfd_open` plus a read source on the pidfd (kernel 5.3+; one shared reaper as fallback) | `RegisterWaitForSingleObject` |
| signals | `killpg` | `killpg` | `.interrupt` writes 0x03; `.hangup`, `.terminate`, `.kill` call `TerminateJobObject` |
| foreground group | `tcgetpgrp` | `tcgetpgrp` | `nil` |
| close | closes master, cancels sources | same | drains output so `ClosePseudoConsole` cannot deadlock; closes the job |

Platform floors and the Windows default shell: `TRM-E`. Windows output is re-rendered by conhost, so Windows tests assert on the emulated screen, not on raw bytes.

## 5. Gap 2 - `TerminalView` (DRAFT, freezes at Phase 5)

```swift
// MetalUITerminalUI. Not frozen.
public struct TerminalView: ElementGroup {
    public init(snapshotSource: TerminalSnapshotSource,
                theme: TerminalPalette,
                keyCaptureExceptions: [KeyboardShortcut] = [],
                optionAsMeta: Bool = false,
                cursorBlink: Bool = true,
                blinkStopsAfterIdle: Bool = true,          // the view stops blinking 30 s after the last input or output (TRM-C)
                boldIsBright: Bool = false,
                onInput: @escaping ([UInt8]) -> Void,
                onResize: @escaping (TerminalSize) -> Void,
                onLink: @escaping (TerminalLinkQuery) -> TerminalLinkTarget?)
}
public struct TerminalPalette: Sendable, Equatable {
    public var ansi: [Color]                               // exactly 16
    public var foreground, background, cursor, cursorText, selection: Color
    public var boldIsBright: Bool                          // default false; bold is the bold face only unless set
}
public struct TerminalLinkQuery: Sendable { /* cell: TerminalPosition, rowText: String, phase: .hover, .exit, .activate */ }
public struct TerminalLinkTarget: Sendable { /* columns: Range<Int>, payload: String */ }
```

Draft rules:
- The background is opaque (the palette's `background`); no glass or translucency in v1.
- Cell metrics come from the monospace `Font`; `onResize` fires only when the cell count changes, at most once per layout pass, clamped to 2 x 1.
- Box drawing U+2500-257F, blocks U+2580-259F, braille and Powerline U+E0A0-E0D4 are synthesised to cell size; a wide character takes 2 cells; colour emoji draw monochrome (R8 atlas); ligatures are off.
- Cursor in every style; blink at 2 Hz through a timed surface redraw; stops 30 s after the last input or output when `blinkStopsAfterIdle` (a view flag, not the host's job). An unfocused or hidden view schedules nothing.
- Selection (drag, double-click word, triple-click line, Option for block), underline, strike, dim, inverse, hidden.
- Wheel scrolls scrollback, or goes to the program on the alternate screen or while a mouse mode is on. Mouse reports through `encodeMouse`.
- Command-hover queries `onLink` only when the hovered cell changes and shows `.pointingHand`. `hitTest` is internal.
- Text input: a `package` text target at the cursor cell so IME marked text is drawn and the candidate window lands on wide-cell edges; paste goes through `encodePaste`, focus through `encodeFocus`.
- Accessibility v1: one text area exposing the visible rows' text; no live announcements.

## 6. Gap 5 - `SurfaceRedrawTrigger` (DRAFT, freezes at Phase 5)

```swift
// MetalUI. Not frozen.
public final class SurfaceRedrawTrigger: Sendable {
    public init()
    public func requestRedraw()
    public func requestRedraw(after: Duration)
}
// GPUSurface gains: init(redraw: ..., value: ..., trigger: SurfaceRedrawTrigger, draw: ...)
```

- Callable from any thread; coalesced; the earliest deadline wins. A trigger whose surface was not painted in the last frame is a no-op, so a hidden panel starts no timer.
- Today a surface redraw is a full window build (the value is read only in paint and `drawSurface` taints retention). The trigger instead drives a **surface-only frame**: the window re-encodes the last scene and runs only the invalidated surfaces' draws (0 builds, 0 element requests). A full frame replaces it whenever the scale changed, the glyph atlas `layoutGeneration` moved, or the window resized.
- Timed requests anchor on the frame clock (`TW-A`) so tests drive them with the simulated clock.
- A retained record stores the surface quad and its request and re-appends it on replay, so the `"surface"` taint goes.

## 7. Performance budgets

Counted (CI guards, steady frame, `TestWindow`/`lastFrameWork`):
- Output, blink and selection frames: 0 builds, 0 element requests, one surface draw per frame however many feeds arrived.
- Glyph instances at most damaged rows x columns plus solid rects. `onResize` only on a change in cell count.
- Idle (unfocused, hidden, or blink stopped): 0 timers, 0 frames, 0 wakeups.
- An editor key frame with a terminal visible has the same `elementRequests` as without it.

Timed (gated `METALUI_RUN_TERMINAL_BENCH=1`, release, Apple silicon; proposals for Alloy to confirm): plain ASCII parse at least 300 MB/s; SGR-heavy at least 80 MB/s; 0 allocations per `feed` in steady state except a new scrollback row; a surface-only frame at most 1 ms CPU for 200 x 60; a key's pty write inside the input dispatch.

## 8. Test strategy

- **Conformance corpus**, authored here, no third-party fixtures: `Tests/MetalUITerminalTests/Fixtures/*.vtfix` (escaped input, grid size, expected text plus attribute map, cursor, modes, events, replies). Batches modelled on the menus of vttest, re-authored. Properties: chunk-split invariance; random bytes never trap; reflow round trips. Recorded vim/less/htop transcripts MAY be added as labelled data.
- **Encoder tables**: one row per key and modifier; a test fails when one byte moves (`docs/practices/verifying-tests-can-fail.md`).
- **Pty** on all three OSes with bounded waits only (no sleep for timing), `--no-parallel`. POSIX (`/bin/sh -c`): `tty` names a pty, the child leads a session, only fds 0-2 are open, `stty size` follows a resize, `exit 7` gives `.exited(7)`, `kill -9 $$` gives `.signaled`, `signalGroup` kills a grandchild, `foregroundProcessGroup` changes under `sleep`, a 50 MB flood loses no byte, a 1 MB write does not block, no callback after `close()`. Windows (`cmd /c`, `powershell -NoProfile`): assert on the emulated screen; exit code, resize, job kill, close during output.
- **Renderer replay**: fixed snapshots through the grid sink (SGR palette sheet, box drawing, cursor styles, selection, a wide row), recorded on Metal and replayed on Vulkan (x86_64, aarch64) and D3D12.
- **Steady-frame cost** tests, each shown red first (`docs/practices/verifying-tests-can-fail.md`): output, blink (35 s simulated, at most 60 surface frames then 0), idle, hidden, typing, editor frame.

## 9. Risks

- **Windows ConPTY**: conhost re-encodes and reflows (double reflow); `ClosePseudoConsole` can block until output drains; no foreground group; Dispatch read sources are weak on Windows, hence threadpool IO. Check locally on the Windows ARM64 VM (`docs/rules/windows-vm.md`).
- **POSIX**: the macOS controlling tty under `posix_spawn` is a spike (Phase 2.1); Linux dispatch has no process source, hence pidfd.
- **CI**: containers need `/dev/ptmx` and `/dev/pts`; the root package runs on Linux x86_64 only, so `MetalUITerminalTests` also joins `Tests/PortableTests` for aarch64; Windows needs a release build (`WR-`); pty timing flakes are bounded by bounded waits.
- **Rendering**: atlas cap and reclaim during binary floods (a reclaim forces a full frame); R8 atlas means monochrome emoji; surface targets cap at 8192 px; a translucent background would break damaged-row-only redraw.
- **Keys**: the OS eats some Ctrl combinations; AppKit may route Ctrl+Tab to the key-view loop (a Phase 4 test).
