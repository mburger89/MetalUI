# SDL test-process guard on Windows (item WG) — decisions

Rulings for item WG (user request 2026-10-02; follow-up to HG, record 154, rulings `TL-A`..`TL-K`; **not a plan task**). Prefix `WG-`.
**Next unused: `WG-M`.** Spec: [`specs/2026-10-27-test-guard-windows-design.md`](specs/2026-10-27-test-guard-windows-design.md). Record: `../record/158-test-guard-windows.md`.
Branch `fix/test-guard-windows` from `a2e5113b`. Divergence labels reserved 875-884: **none taken**. Class M, `Backends/SDL` tests only.

Sources of truth. No SwiftUI or gpui claim exists (a test process's lifetime): no SwiftUI probe is owed. Facts: this repository, `.github/workflows/sdl-gpu-linux.yml`,
SDL 3.2.x `src/events/SDL_quit.c` (fetched from `release-3.2.x` on 2026-10-26) and `SDL_hints.h` of the installed SDL, Win32 documentation from knowledge
(not re-fetched), and the macOS guard of record 154. **Nothing here was compiled or run on Windows**: the UTM VM (`ssh metalui-win`, 192.168.64.2:22) timed out on 2026-10-26.

## WG-A — the premise of `TL-I` is stale; Windows CI runs the SDL tests

**Evidence.** The `windows` job ("Build and replay (Windows x64, D3D12)") runs `swift build @flags` then `swift test @flags` in `Backends/SDL` with
`METALUI_REQUIRE_GPU=1` (workflow lines ~238-250); PR #134's log showed a D3D12 debug-layer crash from a shader-compile test inside `MetalUISDLTests.dll`.
**Ruling.** `TL-I` is amended: the guard is built on Windows. **Cost if wrong.** None beyond the work: a Windows guard that no job exercises would still compile.

## WG-B — orphan: wait on the parent's process handle, opened at start

**Question.** `GetParentProcessId` polling (the POSIX `getppid` shape) or a handle wait?
**Ruling.** A handle wait. Windows does not reparent: `th32ParentProcessID` keeps naming a dead PID, so a PID comparison never changes and a reused PID would
mislead; a process handle stays bound to the process it opened. `muitg_watch_parent` opens `original` with `SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION`
**in the calling thread before the watcher thread exists**, answers orphan when the open fails or when the parent's creation time is later than the child's
(the PID was reused before we looked), then loops `WaitForSingleObject(handle, pollMilliseconds)`: signalled is the orphan, timeout runs `onPoll`, so TL3/TL4 keep
their meaning with one code path. The parent PID comes from `CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS)` (kernel32, no extra library; `NtQueryInformationProcess`
rejected as an undocumented-ish ntdll import with no gain). **Never re-resolve a PID after start.** **Cost if wrong.** A launcher that spawns the test process and exits
at once (an intermediary shim) would be read as an orphan: exit 70 in CI on the first run (`WG-J`). A child of the test runner that outlives a killed runner is
not killed by us otherwise (no Job object, `WG-D`'s sibling: we do not own the runner).

## WG-C — a creation-time seam, `muitg_process_started_before_us`

**Ruling.** The PID-reuse guard is one function so a test can pin it (`WG3`): `GetProcessTimes` creation time of the candidate `<=` ours. FILETIME compare as
`ULARGE_INTEGER`. **Cost if wrong.** A clock step could misorder; creation times are from the kernel's own clock at process creation, and a false "reused" only ends a test run.

## WG-D — exit by `TerminateProcess`, not `_exit`

**Ruling.** Codes stay 70 (orphan) and 71 (deadline), via `TerminateProcess(GetCurrentProcess(), code)` after a `WriteFile` to the stderr handle. `_exit` on Windows runs the
CRT's `ExitProcess` path, which delivers `DLL_PROCESS_DETACH` and takes the loader lock; a process that is hung because a thread holds a lock (the very case) can hang in the exit.
`TerminateProcess` has no such path. **Cost if wrong.** No flush of other buffers: the message is written with the handle API, and nothing else is wanted.

## WG-E — deadline: a `Sleep` thread; no minidump

**Ruling.** `CreateThread` and `Sleep(ms)` (the cap is 86400 s, within `DWORD`), message naming `METALUI_TEST_DEADLINE_SECONDS`, exit 71; the parser is the shared one.
**A dump is ruled out**: `MiniDumpWriteDump` from a thread of the dying process is documented as unreliable (it should run out of process), a child `procdump` is not on
the runner, and WER `LocalDumps` is machine configuration, not ours. Windows has no `sample`; the CI log's "ran past its deadline" line plus the last test name SwiftPM printed is
the evidence. **Cost if wrong.** A deadline names the variable, not the wait; the human check `WG3` reads the log. Revisit if CI shows a hang whose test is not identifiable.

## WG-F — `SDL_NO_SIGNAL_HANDLERS` on Windows, and no SIGTERM twin

**Evidence.** `SDL_quit.c` defines `HAVE_SIGNAL_SUPPORT` when `HAVE_SIGNAL_H` is configured (the CRT's `signal()`, on Windows too) and `SDL_InitQuit` installs `SDL_HandleSIG`
for SIGINT and SIGTERM unless `SDL_GetHintBoolean(SDL_HINT_NO_SIGNAL_HANDLERS)`; `SDL_hints.h` says "POSIX platforms" but the code is `signal()`-based, not `sigaction`-only
(the `#elif defined(HAVE_SIGNAL_H)` branch). The CRT raises SIGINT for Ctrl+C and Ctrl+Break in a console and **never raises SIGTERM** (nothing sends it; `TerminateProcess` is
uncatchable). **Ruling.** The constructor sets the variable on Windows too (`_putenv_s`, unless already set), so a local console Ctrl+C ends a stuck test run instead of becoming an
`SDL_EVENT_QUIT` nobody reads; it cannot matter to a CI kill. **TL2 has no Windows twin** (no signal to send; the premise of the pin is POSIX), and TL1 runs on Windows. **Cost if wrong.** If SDL's
Windows build lacks `HAVE_SIGNAL_H` the variable is inert and harmless. Unmeasured on Windows (`WG-I`).

## WG-G — the constructor: clang's attribute, MSVC's section as the fallback

**Ruling.** Swift on Windows compiles C targets with clang; LLVM lowers `__attribute__((constructor))` to a `.CRT$XCU` initializer on COFF, which the CRT runs before `main`. Under
`_MSC_VER` without `__clang__` (not a supported toolchain, kept for honesty) a `#pragma section(".CRT$XCU", read)` pointer is used. The object is kept by the linker because the Swift tests
reference `muitg_*` symbols (TL3-TL6) and TL8 proves the constructor ran. **Cost if wrong.** TL8 fails on Windows CI with `0 != 600000`: red, not silent.

## WG-H — record 150's parallel hang on macOS: re-attempt, then rule

**Ruling.** Lane 2 runs at least six parallel whole-suite `Backends/SDL` runs with `METALUI_TEST_DEADLINE_SECONDS=90` and reads any `sample` the guard produced. If one reproduces, the sample
names the wait and a fix or a ruling follows (an addendum here); if none does, the attempts are recorded and `TL-G` stands (carried, `--no-parallel` the documented rule, per CLAUDE.md). A
non-reproduction is not evidence of absence and is worded so.

## WG-I — Windows is verified by CI first; the local VM is unreachable

**Evidence.** `ssh -o ConnectTimeout=5 metalui-win` timed out connecting to 192.168.64.2:22; `utmctl` is not on PATH. **Ruling.** The design is not blocked: the Windows half is written to be
compiled by the `windows` job, the probe `sdl-orphan-exit.ps1` ships marked **unrun**, and human checks `WG1`-`WG3` stay open until a CI log and a VM run exist. If the VM is up in a later
phase, the implementer compiles and runs there first (ARM64, `-c core.symlinks=true` clone, an Interactive scheduled task if a window test needs one). **Cost if wrong.** A first-CI failure costs one push cycle.

## WG-J — no opt-out variable for the orphan watcher yet

**Ruling.** Not built. The POSIX watcher has never had one and `exit 70` is loud and named. Build `METALUI_TEST_PARENT_WATCH=0` (both platforms, one parse, one pin) only if a Windows CI run shows a launcher
intermediary tripping `WG-B`. **Cost if wrong.** One red CI run, fixed by the opt-out in one commit.

## WG-K — seam types, and lane order

**Ruling.** `muitg_pid_t` is a C typedef (`unsigned long` on Windows imports as `UInt32`, `pid_t` as `Int32`): Swift tests take every PID from `muitg_parent_pid()` or a spawned child's own PID converted at one helper, never `getppid()` or `Int32` literals outside `#if !os(Windows)`, so the file compiles on both. Lane 2 depends on lane 1's guard source and runs after its commit, on that tree. **Cost if wrong.** A Windows-only compile error, red on CI at once.

## WG-L — rejected: a fixed 90-second deadline for the parallel re-attempt

**Ruling.** Rejected as the design's first draft: the whole suite's healthy wall time is unmeasured and a deadline below it would fire on a slow, loaded Mac and be misread as the record-150 hang. The deadline is the measured unloaded unfiltered wall time x3, recorded with the load; a firing is read from its `sample`, not assumed. **Cost if wrong.** A false positive costs one misdiagnosis; the sample distinguishes a hang from slowness.
