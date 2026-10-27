# SDL test-process guard on Windows (item WG) — design

Follow-up to item HG (record 154, rulings `TL-A`..`TL-K`). Rulings: [`../2026-10-27-test-guard-windows-decisions.md`](../2026-10-27-test-guard-windows-decisions.md) (prefix `WG-`).
Status: **built and recorded in `docs/record/158-test-guard-windows.md`** (Windows half unrun, `WG-I`).
Branch `fix/test-guard-windows` from `a2e5113b`. Class M, test-only, `Backends/SDL`, outside the census. **No root change, no public declaration, no divergence label (875-884 untouched), no SwiftUI or gpui claim** (a test process's lifetime).

## Why

`TL-I` carried Windows on the premise that Windows CI runs no `Backends/SDL` test. That is stale (`WG-A`): the `windows` job of `.github/workflows/sdl-gpu-linux.yml` runs `swift test @flags` in `Backends/SDL`, so a hung GPU wait in `MetalUISDLTests.dll` there sleeps until the runner's job timeout, and an aborted run leaves the helper behind. Record 150's 18-minute parallel macOS hang is re-attempted with the macOS guard's `sample` (`WG-H`).

## Design

One C target, `SDLTestProcessGuard`, now has a Windows half (the `#if !defined(_WIN32)` split becomes `#if defined(_WIN32) ... #else ... #endif` in both files; the portable parser stays outside both). Swift seams stay the `muitg_*` names.

- **Types and seams (header).** `muitg_pid_t` (`unsigned long` on Windows, `pid_t` elsewhere); new `muitg_pid_t muitg_parent_pid(void)` (`getppid()`, or the Toolhelp walk on Windows, `0` when unanswerable); `muitg_watch_parent(muitg_pid_t original, int pollMilliseconds, onOrphan, onPoll)` and `muitg_start_deadline`, `muitg_parse_deadline_seconds`, `muitg_constructor_armed_deadline_milliseconds` unchanged in meaning. New Windows-only `int muitg_process_started_before_us(muitg_pid_t pid)` (creation-time comparison, `WG-C`).
- **Orphan exit (`WG-B`).** `muitg_watch_parent` on Windows opens `original` with `SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION` **synchronously in the caller** (before the thread starts, so a PID reused later cannot be resolved), refuses (orphan at once) when the open fails or the parent's creation time is later than ours, then a detached thread loops `WaitForSingleObject(handle, pollMilliseconds)`: signalled calls `onOrphan` and returns; timeout calls `onPoll`. The constructor passes `muitg_parent_pid()` and 500 ms; `muitg_orphaned` writes the TL-E message with `WriteFile` and `TerminateProcess(GetCurrentProcess(), 70)` (`WG-D`).
- **Deadline (`WG-E`).** `CreateThread` + `Sleep(ms)` then `onExpire`; the expiry writes the TL-D message naming `METALUI_TEST_DEADLINE_SECONDS` and `TerminateProcess(..., 71)`. Same parser, default 600, `0` disables. No minidump (`WG-E`).
- **Signals (`WG-F`).** The constructor sets `SDL_NO_SIGNAL_HANDLERS=1` (unless set) with `_putenv_s`; on Windows this only stops SDL's CRT `signal(SIGINT)` handler (Ctrl+C in a console), SIGTERM never arrives.
- **Constructor (`WG-G`).** `__attribute__((constructor))` under clang (what Swift on Windows uses; LLVM lowers it to `.CRT$XCU`), a `#pragma section(".CRT$XCU")` initializer under `_MSC_VER` without clang.
- **Package.swift**: unchanged except the comment (`compiled out on Windows`); no `linkerSettings` (Toolhelp and process APIs are `kernel32`).

## Tests (`Backends/SDL/Tests/MetalUISDLTests/SDLTestProcessGuardTests.swift`; the suite's `#if !os(Windows)` is removed, per-test gating below)

Red-before is the same for every pin: the Windows half absent (today's header declares nothing under `_WIN32`; the target does not compile there), so nothing is "red on arrival" off Windows; the mutation column is what proves each.

| Test | Platforms | Pins | Mutation that must redden it |
|---|---|---|---|
| TL1 `theTestProcessRunsWithSDLsSignalHandlersOff` | all | constructor ran, hint set | `_putenv_s`/`setenv` removed: TL1 (TL2 too on POSIX) |
| TL2 `aSIGTERMKillsAProcessThatHasInitialisedSDLVideo` | macOS, Linux | unchanged | as TL1; **no Windows twin** (`WG-F`: `.disabled` by `#if !os(Windows)` on that one function) |
| TL3 `aWatcherWhoseOriginalParentIsNotTheParentExits` | all; Windows spawns a short child with Foundation `Process`, waits for exit, watches that PID (the object stays signalled while `Process` holds its handle) | orphan decision | signalled/`!=` test inverted: TL3 times out, TL4 sees a spurious orphan |
| TL4 `aWatcherWhoseParentIsUnchangedStaysQuiet` | all | five polls, no orphan | as TL3; on Windows also: `WaitForSingleObject` timeout path dropped (no `onPoll`) |
| TL5 `aDeadlineExpiresOnceAfterItsMilliseconds` | all | once | callback in a loop or never |
| TL6 `theDeadlineEnvironmentParses` | all | parser | default changed, `"0"` mapped to default |
| TL8 `theConstructorArmedTheDeadlineBeforeMain` | all | constructor wiring (the one test that proves `.CRT$XCU` ran) | `muitg_arm_deadline` call removed |
| TL7 `theProbeHoldBlocksTheHelper` | all, env-gated | the probe's hold | n/a |
| **WG1** `theParentPidSeamAnswersTheParent` | all | POSIX: equals `getppid()`; Windows: non-zero, not `GetCurrentProcessId`, and a process that exists (`muitg_process_started_before_us` true) | Windows answer `0` or own PID; POSIX stub |
| **WG2** `anUnopenableProcessIsAnOrphanAtOnce` | Windows | open failure is an orphan synchronously decided (PID `0xFFFFFFF0`) | the failed-open branch returning "alive" (TL3 would not see it: it opens fine) |
| **WG3** `aProcessStartedAfterUsIsNotOurParent` | Windows | PID-reuse guard: a child spawned after us, kept alive by `Process`, is refused by `muitg_process_started_before_us` and `muitg_watch_parent` on it calls `onOrphan` | creation-time comparison removed or inverted |

WG1 is a new test, WG2/WG3 Windows-only; counts: macOS/Linux `MetalUISDLTests` +1 (WG1), Windows +3. No root test, no guard (a plain-import guard is not needed: no public declaration). Unproved by a pin, named: handle opened at start rather than lazily in the thread (PID reuse after start cannot be simulated; `WG-B` states the rule and the code puts open and thread creation in one function, as `TL-K`'s arm and record).

Probes: `docs/probes/sdl-orphan-exit.ps1` (the Windows twin of `sdl-orphan-exit.sh`: start `swift test --skip-build --filter theProbeHoldBlocksTheHelper` with `METALUI_TL_HOLD=1`, find the helper child, `Stop-Process -Force` the runner, assert the helper gone in 3 s; header says **unrun** until a Windows run is recorded) and `docs/probes/sdl-parallel-hang-repro.sh` (lane 2, below).

## Lanes (two, disjoint files)

1. **Lane 1, the guard.** `Backends/SDL/Tests/SDLTestProcessGuard/**`, `Backends/SDL/Tests/MetalUISDLTests/SDLTestProcessGuardTests.swift`, `Backends/SDL/Package.swift` (comment only), `docs/probes/sdl-orphan-exit.ps1`. Build and run on macOS (`swift test $(...) --no-parallel`, `METALUI_REQUIRE_GPU=1`), the Linux image (POSIX half must be byte-unmoved in behaviour: TL1-TL8 green), cross-compile check of the Windows half where possible (`clang --target=aarch64-pc-windows-msvc -fsyntax-only` with the Windows SDK headers is not available on this Mac, so syntax only through mingw-style stubs is *not* claimed; CI and the UTM VM are the compilers, `WG-I`). Mutations of the table, one at a time, on a committed tree, macOS/Linux ones run, Windows ones listed as owed to CI.
2. **Lane 2, record 150's hang.** `docs/probes/sdl-parallel-hang-repro.sh` and its recorded output only (no source): at least six parallel whole-suite `Backends/SDL` runs on macOS with `METALUI_REQUIRE_GPU=1` and a deadline of the measured unloaded whole-suite wall time x3 (first take one unfiltered run to measure it; a fixed 90 s would fire on a healthy slow suite and be read as a hang, `WG-L`), a deadline `sample` read if one fires. Lane 2 runs after lane 1's commit, on that tree (`WG-K`). Reproduced: diagnose (a ruling `WG-H` addendum, a fix only in `Backends/SDL`). Not reproduced: the attempts (count, wall times, load on the Mac) go in the record and `TL-G` stays carried; `--no-parallel` stays the rule.

Verification beyond lanes (checker): root native suite unmoved at 4481 in 3 suites with the `FR-J` line, `swift build --build-tests` 0 warnings, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (no public declaration), fourteen images 0 px against `a2e5113b` (no `Sources/` change), Linux image for `Backends/SDL`.

## Documentation (Record phase, not now)

Record `158-test-guard-windows.md`; `docs/testing.md` "SDL tests" paragraph gains the Windows sentence; `docs/verification/human-checks.md` group `WG`: **WG1** first green Windows CI run shows TL1, TL3-TL8, WG1-WG3 passed in `MetalUISDLTests` and no exit 70 (a false orphan); **WG2** run `sdl-orphan-exit.ps1` in the UTM VM and record its output; **WG3** a hung test under the deadline shows exit 71 and the message in the CI log (mutation: a `waitBlocking` with no partner under `METALUI_TEST_DEADLINE_SECONDS=30`). CLAUDE.md gets one rule line in the Record phase.

## Scope, honestly

- **Built:** the Windows orphan exit, deadline and constructor; the Windows tests; the Windows probe (unrun); the macOS parallel-hang re-attempt.
- **Refused, with reasons:** a Windows SIGTERM twin (no such signal, `WG-F`); a minidump on deadline (`WG-E`); a Job-object kill-on-close for the helper (the runner is `swift test`, not ours; `WG-B` cost).
- **Carried, owner:** compiling and running the Windows half locally (the UTM VM at `192.168.64.2` timed out on ssh and `utmctl` is not on PATH; owner: the next session with the VM up, else the first CI run, `WG-I`); a false-orphan opt-out variable (build only if CI shows a launcher intermediary, `WG-J`).
