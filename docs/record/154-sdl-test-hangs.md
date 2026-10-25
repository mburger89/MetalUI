# 154. Hung `MetalUISDLTests` helpers: SIGTERM, orphans and a run deadline (item HG)

Item HG of the gpui-gap priority list (user request 2026-10-02, MetalCreator's report of 2026-10-24; **not a plan task**), on `fix/sdl-test-hangs` from `935d0096` (origin/master unmoved at the Record phase, so no renumbering). Rulings `TL-A`..`TL-J` in `docs/superpowers/2026-10-24-sdl-test-hangs-decisions.md`; spec `docs/superpowers/specs/2026-10-24-sdl-test-hangs-design.md`. Class `M`, `Backends/SDL` test infrastructure and docs only: no production code, no public declaration, no census row, no divergence (835-844 untouched), no SwiftUI claim, no root `Sources/` or `Package.swift` change. Root stays **4445** and the fourteen images 0 px against `935d0096` **by construction, not re-measured**.

## 1. What was built

A test-only C target `SDLTestProcessGuard` (`Backends/SDL/Tests/SDLTestProcessGuard/`, a dependency of `MetalUISDLTests` only, compiled out under `_WIN32`, `TL-I`). One `__attribute__((constructor))` runs before `main`, in the helper and in every exit-test child of the same binary:

- `setenv("SDL_NO_SIGNAL_HANDLERS", "1", 0)` so SIGTERM and SIGINT keep their default action (`TL-B`; an explicit value wins).
- a parent watcher thread polling `getppid()` every 500 ms that `_exit(70)`s when it changes (`TL-E`).
- a run deadline, `METALUI_TEST_DEADLINE_SECONDS` (default 600, `0` disables, junk is the default) that on macOS first runs a best-effort `sample` of the process, then `_exit(71)` naming the variable (`TL-D`, `TL-H`).

Seams, all `muitg_`: `muitg_parse_deadline_seconds`, `muitg_watch_parent(original, pollMs, onOrphan, onPoll)`, `muitg_start_deadline(ms, onExpire)`. `docs/testing.md` gains "SDL test processes"; human checks group `TL`.

Why: the orphans of the report sleep because (a) SDL's handlers turn SIGTERM into an `SDL_EVENT_QUIT` nobody reads, (b) killing `swift test` re-parents its helper to PID 1, (c) a blocking verb with no partner (`waitBlocking`, `Submitted.await`, `awaitStart`) has no bound. The links (a) and (b) were measured; that the two sync-batch orphans came from mutation runs of records 137 and 143 is an **inference** from their filter strings, no orphan was sampled before it was killed (`TL-A`).

## 2. What was measured

- Unmutated, nothing hangs: 30 runs of the two filtered suites, two parallel and one serial whole-suite run, all passed (305 tests then).
- Probe `sdl-sigterm-handler.c`: a process that ran `SDL_Init(VIDEO)` survives SIGTERM; with `SDL_NO_SIGNAL_HANDLERS=1` it dies. In the real helper (a temporary test holding a device, then blocking on a semaphore) SIGTERM was ignored, `kill -9` of `swift test` re-parented it to PID 1, `sample` showed `semaphore_wait_trap`.
- Probe `swift-testing-timelimit-blocked.swift`: **`.timeLimit(.minutes(1))` does not end a blocked body** (main-actor semaphore wait alive at 4 min; async never-resumed continuation alive at 3m47s; no issue, no summary). Hence no `.timeLimit` on the GPU suites (`TL-C`); the request's first suggestion is refused with that evidence.
- Probe `sdl-orphan-exit.sh` (`TL-J`): `kill -9` of the parent of a held helper: with the guard `ok orphan exited after 0 s` (twice); separating arm, the guard's red-phase stub: `FAIL helper survived 3 s`.

## 3. Tests (`SDLTestProcessGuardTests`, `@Suite(.serialized)`, bounded semaphores, no sleeps)

`TL1 theTestProcessRunsWithSDLsSignalHandlersOff`; `TL2 aSIGTERMKillsAProcessThatHasInitialisedSDLVideo` (exit test, child initialises video, raises SIGTERM, `.signal(SIGTERM)`); `TL3 aWatcherWhoseOriginalParentIsNotTheParentExits`; `TL4 aWatcherWhoseParentIsUnchangedStaysQuiet`; `TL5 aDeadlineExpiresOnceAfterItsMilliseconds`; `TL6 theDeadlineEnvironmentParses`; `TL8 theConstructorArmedTheDeadlineBeforeMain` (reads `muitg_constructor_armed_deadline_milliseconds`, `TL-K`); `TL7 theProbeHoldBlocksTheHelper` (env-gated by `METALUI_TL_HOLD`, the probe's blocker, skipped otherwise). `Backends/SDL`: 304 -> 312 Swift Testing tests (18 suites), 31 XCTest.

## 4. Red runs and mutations

Red first: the pins ran over a stubbed guard target (`5e1a87c9`), then TL2 was corrected to require video init (`fd0c20f5`: red line is exit 0 instead of SIGTERM). Mutations ran on the committed tree, `Backends/SDL` unfiltered on macOS (`METALUI_REQUIRE_GPU=1 --no-parallel`, baseline **311 tests in 18 suites passed**).

| Mutation | Reddened |
|---|---|
| M1 constructor `setenv` removed | `theTestProcessRunsWithSDLsSignalHandlersOff`, `aSIGTERMKillsAProcessThatHasInitialisedSDLVideo` |
| M2 watcher's `getppid() != original` inverted | **no test by name**: the real constructor's watcher `_exit(70)`ed the run mid-way (`the process that started this test run is gone`), no summary line; TL3/TL4 never evaluated. Reddened by process death only |
| M3 deadline callback in a loop | `aDeadlineExpiresOnceAfterItsMilliseconds` |
| M3b deadline callback never invoked | `aDeadlineExpiresOnceAfterItsMilliseconds` |
| M4 parser default 600 -> 60 | `theDeadlineEnvironmentParses` |
| M5 parser maps `"0"` to the default | `theDeadlineEnvironmentParses` |
| MA (branch check, survived M1-M5) constructor's deadline arming removed | `theConstructorArmedTheDeadlineBeforeMain` (TL8; 1 issue, `SDLTestProcessGuardTests` filtered run, after the seam of `TL-K`) |
| MC (branch check) parser's trailing-junk test `*end != '\0'` dropped | `theDeadlineEnvironmentParses` (2 issues: the new `"30x"` and `"3 0"` arms; `"abc"` alone could not see it) |

M2 is the honest weak spot: TL3/TL4 were red only against the stub target. A `METALUI_TL_NO_WATCHER`-style switch or running them in an exit-test child would let M2 redden them by name (carried, below; left as is after the branch check).

## 5. Verification

Root native suite, 0 `error:`, `FR-J` line: see the counts bullet in `CLAUDE.md` (taken at the Record phase). `Backends/SDL` macOS 31 + 312 with `METALUI_REQUIRE_GPU=1`; Linux image 308 passing (re-taken after TL8). The root count and the fourteen images are unmoved by construction (`git diff --stat 935d0096 HEAD` touches only `Backends/SDL` test files, `Backends/SDL/Package.swift`, docs and probes).

## 6. Hazards

- A legitimately long run past 600 s is cut with exit 71: set `METALUI_TEST_DEADLINE_SECONDS` (a 100k stress run). Lavapipe's full run must stay far under it.
- The constructor is kept only if its object file is linked; TL3-TL6 call `muitg_` symbols, which forces it, and TL1 proves it ran.
- A reparent to a subreaper also counts as an orphan (intended).
- A test that needs SDL's quit-on-signal conversion must set the hint itself.

## 7. Deferrals, with owners

- **The 18-minute parallel whole-suite hang** of record 150 near `SDLImageCursorTests`: not reproduced (two parallel runs, 10.8 s and 10.0 s); carried (`TL-G`); owner: the next SDL-window change; the next recurrence ends at the deadline with a `sample`.
- **No deadline inside `waitBlocking`/`Submitted.await`** (`TL-F`, `GB-F` parity); re-open only on a library hang the deadline names.
- **`.timeLimit`** (`TL-C`): re-run the probe on a toolchain bump (owner: the next toolchain bump).
- **Windows** (`TL-I`): constructor compiled out; owner: the first Windows SDL-test job.
- **M2 by name** (section 4) and the Linux image re-take.
- A production opt-out of SDL's signal handlers for apps: not asked.

Human checks: group `TL` (`TL1`, `TL2`).
