# 269. The latency trace writes in apps (G34 follow-up, `FP-J`)

Branch `fix/latency-trace-sink` (master `b7df7e6a`). Ruling `FP-J` in `docs/superpowers/2026-11-07-frame-timing-decisions.md`. Class `M`; no divergence.

Alloy ran `METALUI_LATENCY_TRACE=<path>` in a release build with a real window and about 200 keys: the file was created and stayed empty (no header) over three runs, while its own `FrameTiming` recorded `presented` times.

## Root cause

`Window.frameTiming` defaults to `FrameTiming.fromEnvironment()` (`Window.swift:461`), the only reader of the variable. Alloy assigns `FrameTiming(capacity: 8192)`; the env-built instance was dropped, having created the file (`enableTrace`) and nothing else, and the instance that recorded had `traceSink == nil`. The header was lazy (first presented input frame), so an empty file was the only trace of the dropped instance.

## Fix

- `FrameTiming.init` reads the variable (`FrameTiming.swift`), so any timing traces.
- New public `FrameTiming.enableTrace(destination:)` (inventory class `M`, covered by the `frame-timing` row).
- Header written on enable, once per destination per process; the file is opened once per path through Foundation's `FileHandle(forWritingAtPath:)` at its end (not POSIX `open`, whose Unix mode bits abort in the Windows CRT, which crashed the Windows test run) and the handle shared, each line one unbuffered write. The earlier per-instance `FileHandle` with `seekToEndOfFile` would also have let two windows overwrite each other.

## Ruled out

Text input (`insertText` -> `.textInput` -> kind `.text`) is traced; `noteTick` only fills the tick columns; the AppKit presented handler calls the same `notePresented` as the headless renderer; `FileHandle.write` was already unbuffered.

## Tests (`FrameTimingTests.swift`, fail before the fix)

`aTextInputFrameWritesATraceLineToTheFile`, `anAppBuiltFrameTimingTracesWhenTheEnvironmentIsSet`, `theTraceHeaderIsWrittenOnEnableAndLinesAreOnDiskAsProduced`: red on master (5 issues), green after.
