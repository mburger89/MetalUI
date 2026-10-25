# Hung `MetalUISDLTests` helpers (item HG) — design

Item HG of the gpui-gap priority list (user request 2026-10-02) with MetalCreator's report of 2026-10-24; **not a plan task**. Rulings:
`../2026-10-24-sdl-test-hangs-decisions.md` (`TL-A`…`TL-J`). Record `§154` (Record phase). Base `935d0096`, branch `fix/sdl-test-hangs`.
`Backends/SDL` test infrastructure plus docs. Class M, no public declaration, no census row, no divergence (labels 835-844 untouched), no
SwiftUI claim (SwiftUI and gpui have no answer to a test process's lifetime: nothing to probe on either; the probes are of Swift Testing and SDL).
No root `Sources/` change: root stays **4445**, the fourteen images 0 px against `935d0096` by construction.

## What was reported

Three orphaned `Backends/SDL` test helpers (`swiftpm-testing-helper`, parent PID 1) slept 2-3 days at 0 % CPU, ignored SIGTERM and died only to
`kill -9`: two from `--filter "SDLGPUSyncBatchTests|SDLGPUReadbackAndFailureTests"` (worktree sync-batch), one from `--skip-build` (sdl-gpu-device-info).
Record 150 also holds an unexplained 18-minute hang of a parallel whole-suite run.

## What was measured (record 154 section 2, probes TL-1 and TL-2)

1. **Unmutated, nothing hangs.** 30 runs of the two filtered suites (`--no-parallel`, 2-4 s each), 2 parallel and 1 serial whole-suite runs
   (305 tests in 18 suites, 10-16 s) all passed with `METALUI_REQUIRE_GPU=1`.
2. **SIGTERM is swallowed by SDL.** Any process that ran `SDL_Init(SDL_INIT_VIDEO)` (every `SDLPlatform` and `SDLGPUDevice.make()`) has SDL's
   SIGINT/SIGTERM handlers installed, which post `SDL_EVENT_QUIT` and return. A test helper never pumps events, so the signal does nothing.
   C probe: survives SIGTERM by default, dies with `SDL_NO_SIGNAL_HANDLERS=1`. In the real helper (a temporary test holding a device then
   blocking on a semaphore): SIGTERM ignored, `kill -9` of `swift test` re-parents the helper to PID 1, it sleeps in `semaphore_wait_trap`, SIGTERM
   still ignored, `kill -9` of the PID ends it. This is the reported picture exactly.
3. **Killing `swift test` orphans the helper** (also without SDL: probe TL-1's separating arm). `swift test` and its helper are separate processes
   and nothing ties the helper's life to its parent's.
4. **What blocks forever** is a blocking verb whose partner never answers: `SDLGPUFence.waitBlocking()` (an `NSCondition` loop with no deadline, on
   the main actor from `downloadSynchronously`), `Submitted.await()` (a semaphore), `await fence.wait()` (a continuation), and the tests'
   `awaitStart()`. A healthy library never leaves them waiting; **a mutation does**: the pins of records 137 and 143 name mutations such as
   "the verb skips `startWaiting`" (fences never signal, the main actor sleeps in `waitBlocking`) and "the `preconditionNotOnOwnWorker` line removed
   (the child deadlocks on its own queue)". The two sync-batch orphans came from the filtered suites those mutation runs execute. A workflow that
   times out and kills `swift test` then leaves the sleeping helper, immune to SIGTERM.
5. **`.timeLimit(.minutes(1))` does not end such a test.** A main-actor body blocked on a semaphore and an async body awaiting a never-resumed
   continuation were both still alive minutes later with no issue and no summary line. A time limit is not the cure the request hoped for.
6. **No library bug was found** by inspection or by the loops: a fence signals in `finish()` after the waiter thread's wait, `SDLGPUWorker` drains its
   queue before exiting, and a device cannot deinit while a fence (which holds it) exists. The 18-minute parallel hang did not reproduce (carried, `TL-G`).

## Design

A test-only C target makes a hang **fail** and a dead parent **end the process**. No production code changes (`TL-F`).

### New target `SDLTestProcessGuard` (`Backends/SDL/Tests/SDLTestProcessGuard/`, C, test-only)

`include/SDLTestProcessGuard.h`, `SDLTestProcessGuard.c`, a dependency of `MetalUISDLTests` only (the one test target that initialises SDL),
`#if !defined(_WIN32)` inside (Windows carried, `TL-I`). One `__attribute__((constructor))` runs before `main`, in the helper and in every
exit-test child of the same binary:

1. `setenv("SDL_NO_SIGNAL_HANDLERS", "1", 0)` (overwrite 0: a caller's explicit value wins) so SIGTERM and SIGINT keep their default action (`TL-B`).
2. Starts the **parent watcher**: records `getppid()`, polls every 500 ms (a C thread, not a test sleep); when `getppid()` differs it writes
   `error: the process that started this test run is gone; exiting (TL-E)` to stderr and `_exit(70)` (`TL-E`).
3. Starts the **run deadline**: `METALUI_TEST_DEADLINE_SECONDS` (default 600; `0` disables; an unparsable or negative value is the default); on
   expiry, macOS runs `/usr/bin/sample <pid> 3 -file <tmp>/metalui-hang-<pid>.txt` (best effort, bounded by a 10 s wait, `TL-H`), writes
   `error: the test process ran past its deadline (METALUI_TEST_DEADLINE_SECONDS=600); a blocked wait? sample: <path> (TL-D)` and `_exit(71)`.

Testable seams (all `muitg_`-prefixed C functions, the constructor only calls them):
`int muitg_parse_deadline_seconds(const char *value)` (pure), `void muitg_watch_parent(pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void))`
(starts one detached thread; calls `onPoll` after each check and `onOrphan` once, then returns), `void muitg_start_deadline(int milliseconds, void (*onExpire)(void))`.
The constructor passes `_exit`-calling callbacks; a test passes recording callbacks.

### Tests (`Tests/MetalUISDLTests/SDLTestProcessGuardTests.swift`, `@Suite(.serialized)`, every wait bounded by a semaphore timeout, no sleep)

| Test | Red before | Mutation that must redden it |
| --- | --- | --- |
| `TL1 theTestProcessRunsWithSDLsSignalHandlersOff`: `getenv("SDL_NO_SIGNAL_HANDLERS") == "1"` | the variable is absent | constructor's `setenv` removed: TL1, TL2 |
| `TL2 aSIGTERMKillsAProcessThatHasInitialisedSDLVideo`: exit test, child calls `SDLGPUDevice.make()` (or `SDL_Init`) then `kill(getpid(), SIGTERM)` then waits 20 s on a semaphore; `processExitsWith: .signal(SIGTERM)` | the child survives, exits 0 after the wait | same |
| `TL3 aWatcherWhoseOriginalParentIsNotTheParentExits`: original = a pid that is not `getppid()`; `onOrphan` signals a semaphore, bounded 20 s | no `muitg_watch_parent` | the `!=` test inverted to `==`: TL3 times out (issue), TL4 sees a spurious orphan |
| `TL4 aWatcherWhoseParentIsUnchangedStaysQuiet`: original = `getppid()`; wait for 5 `onPoll` signals with a 1 ms poll, then assert `onOrphan` never ran | same | same |
| `TL5 aDeadlineExpiresOnceAfterItsMilliseconds`: 100 ms, `onExpire` counted, bounded wait, then 5 more polls of a second semaphore proving once | no `muitg_start_deadline` | the callback invoked in a loop (count 2) / never invoked |
| `TL6 theDeadlineEnvironmentParses`: nil, "", "abc", "-5" give 600; "0" gives 0; "30" gives 30; "999999999999" gives 600 | no parser | default changed to 60, or "0" mapped to default: TL6 |
| `TL7 theProcessStillRunsTheWholeSuiteUnderTheConstructor`: the whole suite's own passing, not a test | n/a | n/a |

TL7 is not a test; the unfiltered run is the gate. The end-to-end orphan exit is measured by the checker with `docs/probes/sdl-orphan-exit.sh`
(probe TL-3, written in the Implement phase: start a filtered run whose test blocks, `kill -9` the parent, assert the helper is gone within 3 s,
recorded in its header), and is **not a pin** (`TL-J`); with the watcher's decision pinned by TL3/TL4 the residue is the constructor's wiring,
which TL1 and the probe cover.

### Documentation

`docs/testing.md` (an "SDL tests" paragraph: SIGTERM works, the deadline variable, how a workflow kills a run: `kill <helper pid>`, never a name pattern),
`docs/verification/human-checks.md` group `TL` (TL1 Linux image: `docker run ... sleep` no; real check: kill a running `swift test` in the image and
see the helper end; TL2 macOS Ctrl-C of `swift test` while a GPU test blocks), record 154, CLAUDE.md one rule at the Record phase.

## Lanes

One lane, files: `Backends/SDL/Package.swift` (the target and the dependency), `Backends/SDL/Tests/SDLTestProcessGuard/**`,
`Backends/SDL/Tests/MetalUISDLTests/SDLTestProcessGuardTests.swift`, `docs/probes/sdl-orphan-exit.sh`. Verification (checker, not a lane): the
mutations above one at a time on a committed tree, `Backends/SDL` on macOS with `METALUI_REQUIRE_GPU=1 --no-parallel`, the Linux image
(`docker run ... bash -c 'swift build --build-tests ... && swift test --skip-build ...'`; the guard compiles and TL2 runs there), the root native
suite (4445, unmoved), `swift build --build-tests` 0 warnings.

## Scope, honestly

- **Built:** SIGTERM works in every SDL test process; an orphaned helper exits within about a second; any test process ends at a deadline with a
  named message and, on macOS, a `sample` of the blocked thread.
- **Refused, with evidence:** `.timeLimit` on the blocking suites (`TL-C`, probe TL-1: it does not fire on a blocked body, so it would read as a
  protection it is not); a deadline inside `SDLGPUFence.waitBlocking` (production code for a test's sake, `TL-F`).
- **Carried:** the 18-minute parallel whole-suite hang near `SDLImageCursorTests` (did not reproduce in 2 parallel runs, `TL-G`; owner: the next
  SDL-window change, re-open on a recurrence, whose deadline output will now name the wait); Windows (constructor compiled out, `TL-I`; owner: the
  first Windows SDL-test job); a production opt-out of SDL's signal handlers for apps (Ctrl-C quitting an app is the useful default, not asked).
