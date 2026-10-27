# 158. The SDL test-process guard on Windows, and record 150's parallel hang (item WG)

Item WG of the gpui-gap priority list (user request 2026-10-02; follow-up to HG, record 154, rulings `TL-A`..`TL-K`; **not a plan task**), on `fix/test-guard-windows` from `a2e5113b` (origin/master unmoved at the Record phase, so no renumbering). Rulings `WG-A`..`WG-L` in `docs/superpowers/2026-10-27-test-guard-windows-decisions.md`, spec `docs/superpowers/specs/2026-10-27-test-guard-windows-design.md`. Class M, test infrastructure and one product lock fix in `Backends/SDL`, outside the census. **No root change, no public declaration, no divergence label (875-884 untouched), no SwiftUI or gpui claim** (a test process's lifetime), no shader, no pixel.

## 1. What was wrong and what was built

**`TL-I` rested on a stale premise (`WG-A`).** Record 154 carried Windows because "Windows CI runs no `Backends/SDL` test". The `windows` job of `.github/workflows/sdl-gpu-linux.yml` runs `swift test` in `Backends/SDL` with `METALUI_REQUIRE_GPU=1` (PR #134's log showed a D3D12 debug-layer crash from a shader-compile test in `MetalUISDLTests.dll`), so a hung GPU wait there slept until the job timeout and an aborted run left its helper behind. `TL-I` is amended.

**The Windows half of `SDLTestProcessGuard` (lane 1).** The `#if !defined(_WIN32)` split in the `.c` and `.h` became `#if defined(_WIN32) ... #else ... #endif` around the platform code; the deadline parser stays shared. Swift seams keep the `muitg_*` names; `muitg_pid_t` is a typedef (`unsigned long` on Windows, `pid_t` elsewhere), and `muitg_parent_pid()` is new (`getppid()`, or a Toolhelp32 snapshot walk on Windows, `0` when unanswerable).

- **Orphan exit (`WG-B`, `WG-C`).** `muitg_watch_parent` opens the parent with `SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION` **in the calling thread before the watcher thread exists**, answers orphan when the open fails or when the parent's creation time is later than ours (the PID was reused before we looked: `muitg_process_started_before_us`), then loops `WaitForSingleObject(handle, poll)`: signalled is the orphan, timeout runs `onPoll`. Windows does not reparent, so a PID comparison would never change; the handle stays bound to the process. Never re-resolve a PID after start.
- **Exit (`WG-D`).** Codes 70 and 71 by `TerminateProcess` after a `WriteFile` to stderr, not `_exit` (which takes the loader lock a hung process may hold).
- **Deadline (`WG-E`).** A `Sleep` thread, message naming `METALUI_TEST_DEADLINE_SECONDS`, same parser (default 600, `0` disables). No minidump (`MiniDumpWriteDump` in-process is unreliable, no `procdump` on the runner); Windows has no `sample`, so the CI log line plus the last test name is the evidence.
- **Signals (`WG-F`).** SDL 3.2.x `SDL_quit.c` installs `SDL_HandleSIG` through the CRT `signal()` for SIGINT and SIGTERM unless the hint is set, on Windows too; the CRT raises SIGINT for Ctrl+C and never raises SIGTERM. The constructor sets `SDL_NO_SIGNAL_HANDLERS` on Windows (`_putenv_s`, an explicit value wins) so a local Ctrl+C ends a stuck run. **TL2 has no Windows twin** (`#if !os(Windows)`).
- **Constructor (`WG-G`).** `__attribute__((constructor))` under clang (lowered to `.CRT$XCU` on COFF), a `#pragma section(".CRT$XCU")` pointer under bare MSVC. TL8 proves it ran.

**Record 150's parallel hang, reproduced, diagnosed and fixed (lane 2, `WG-H`).** See section 4.

## 2. Tests (`Backends/SDL/Tests/MetalUISDLTests`)

`SDLTestProcessGuardTests.swift`: TL1, TL3-TL8 now run on every platform (TL3/TL4 take their PIDs from `muitg_parent_pid()` or a spawned child through one helper, `WG-K`); TL2 is POSIX-only; new **WG1** `theParentPidSeamAnswersTheParent` (all), **WG2** `anUnopenableProcessIsAnOrphanAtOnce` and **WG3** `aProcessStartedAfterUsIsNotOurParent` (Windows only). `SDLGPUDeviceInfoTests.swift`: **`aMainThreadMakeDuringAnOffThreadMakesHopDoesNotDeadlock`** (`WG-H`). At the Record phase the one `-Wasync` warning lane 1 left (`never.wait` in an async exit-test body) moved into a synchronous `holdUntilKilled()`; `Backends/SDL`'s `swift build --build-tests` then carries one warning, `AccessKitControlsParityTests.swift:83` ("no calls to throwing functions occur within `try`"), **not touched by this branch** (and the linker's macOS-version notice). Root: 0 new tests, 0 guards.

## 3. Probes

- `docs/probes/sdl-orphan-exit.ps1`: the Windows twin of `sdl-orphan-exit.sh`. **UNRUN** (header says so). Known defect, carried: `Find-Helper` looks only at direct children of the `swift` process, and on Windows `swift.exe` spawns `swift-test.exe`, which spawns the helper, so the first run will probably print "inconclusive: no helper found"; walk descendants (or start `swift-test.exe` directly) when it is first run (`WG-I`).
- `docs/probes/sdl-parallel-hang-repro.sh` (header holds the recorded numbers): `baseline` and `parallel <n> <secs>`.

## 4. The parallel hang

Baseline, one unfiltered `--no-parallel` run: wall 16 s (Swift Testing 14.4 s, 331 tests); deadline 16 x 3 = 48 s (`WG-L`, a fixed 90 s was rejected: it could fire on a slow suite). Before the fix, 8 parallel runs: 4 passed (11-12 s), **3 hung** (guard exit 71 at 48 s, `sample` read, all the same), 1 failed `sdlAFileDroppedOnTheAppIsAnOpenURL`. The main thread, running a main-actor GPU test, waited for `SDLGPUDevice.makeLock` inside `make`; the holder was a detached thread of `SDLGPUDeviceInfoTests` blocked in `DispatchQueue.main.sync` (`onMainThreadIfCocoa`), which needs the main thread: a **product lock-order inversion** (any app thread calling `make` while the main thread also does). **Fix:** `make` initialises video before `makeLock` and never holds the lock across the hop (macOS: the main queue serialises the init; elsewhere a `videoLock`); `makeLock` still serialises `SDL_CreateGPUDevice`. Seam `SDLGPUDevice.testingMakeEntered` (internal) orders the regression test's two calls. After: 12 parallel runs, 12 passed (12-14 s, load up to 110), and a `--no-parallel` run of 332 tests passed.

**`--no-parallel` stays the documented rule.** `sdlAFileDroppedOnTheAppIsAnOpenURL` (`SDLAppShellTests.swift:170`, `:176`) failed once in 8 parallel runs before the fix and in none of the 12 after (and none of 4 more at the verifier): **undiagnosed, carried**, a non-reproduction is not evidence of absence.

## 5. Mutations (each on a committed tree, restored)

| Mutation | Reddened |
|---|---|
| `setenv("SDL_NO_SIGNAL_HANDLERS")` removed from the POSIX constructor (guard suite filtered) | `theTestProcessRunsWithSDLsSignalHandlersOff` (TL1), `aSIGTERMKillsAProcessThatHasInitialisedSDLVideo` (TL2) |
| `muitg_parent_pid` returning 0; the watcher's `!=` inverted (lane 1's own runs) | no named test: the POSIX constructor has no `parent != 0` guard, so both kill the helper with exit 70 before any test runs (a crashed run, not a red test; the Windows constructor does guard `parent != 0`). Optional: add the guard on POSIX |
| video init moved back under `makeLock` in `SDLGPUDevice.make`, full `Backends/SDL` suite at deadline 90 s, `--no-parallel` | `aMainThreadMakeDuringAnOffThreadMakesHopDoesNotDeadlock` (hangs; guard exit 71 naming the variable) |

**Owed to CI or the VM, not run:** the Windows-only mutations (`WG2` failed-open branch returning "alive", `WG3` creation-time check removed, the `WaitForSingleObject` timeout path in TL4).

## 6. Verification

Backends/SDL on macOS with `METALUI_REQUIRE_GPU=1`: 31 + 332 tests (19 suites) passed `--no-parallel`; the 9 guard tests green; the only `error:` lines are the expected negative shader-compile tests. Root unmoved by construction (the diff against `a2e5113b` touches `Backends/SDL/**`, docs and a comment in `Backends/SDL/Package.swift`); the root count is in CLAUDE.md. The fourteen images and the Linux image were not re-taken (no `Sources/` change); CI runs the Linux image and the Windows job on push.

## 7. Hazards and deferrals

- **The Windows half has never been compiled or run.** The UTM VM (`192.168.64.2`) timed out on 2026-10-26 and `utmctl` is not on PATH (`WG-I`). A compile error or a false exit 70 (a launcher intermediary read as an orphan, `WG-J`) is possible on the first Windows CI run; one push cycle. Owner: the first CI log, human checks `WG1`-`WG3`.
- `WG-J` (an opt-out variable for the watcher) is built only if CI shows the false orphan.
- `sdlAFileDroppedOnTheAppIsAnOpenURL`: carried, owner: the next parallel-run flake.
- `sdl-orphan-exit.ps1` descendant walk: carried to its first run.
- A Windows SIGTERM twin (`WG-F`), a minidump (`WG-E`), a Job-object kill-on-close (the runner is not ours): refused.
