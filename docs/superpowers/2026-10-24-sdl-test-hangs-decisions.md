# Hung SDL test helpers (item HG) — decisions

Rulings for item HG of the gpui-gap priority list (user request 2026-10-02; MetalCreator report 2026-10-24; **not a plan task**). Prefix `TL-`.
**Next unused: `TL-K`.** Spec: [`specs/2026-10-24-sdl-test-hangs-design.md`](specs/2026-10-24-sdl-test-hangs-design.md). Record: `../record/154-sdl-test-hangs.md`.
Branch `fix/sdl-test-hangs` from `935d0096`. Continues `GA-` (record 114), `GB-` (137), `SY-` (143), `DL-` (150). Divergence labels reserved 835-844: **none taken**.

Sources of truth. No SwiftUI or gpui claim exists (a test process's lifetime), so no SwiftUI probe is owed. Facts: this repository at `935d0096`,
SDL's `SDL_hints.h`, and three probes: `docs/probes/sdl-sigterm-handler.c`, `docs/probes/swift-testing-timelimit-blocked.swift`, and the real helper
measured in record 154 section 2. Backends/SDL is outside the census (`GA-L`); class M.

## TL-A — the cause: a blocked wait, a swallowed SIGTERM, an orphan

**Question.** What are the sleeping, SIGTERM-proof, parentless helpers?
**Evidence.** The helper ignores SIGTERM only when SDL video was initialised (C probe, separating arm; the real helper); a killed `swift test`
re-parents its helper to PID 1 (measured, also without SDL); the sleeping thread is in `semaphore_wait_trap` (sample). Unmutated code never blocks
(30 filtered + 3 whole-suite runs). The two sync-batch orphans ran the filtered suites that records 137 and 143's mutation runs execute, and those
mutations (a fence never signalled, a precondition removed) leave a main-actor wait with no partner.
**Ruling.** The cause is the combination, not a library bug (the link from the two orphans to mutation runs is an inference from the filter strings and the record's own mutation lists, not an observation; no orphan's stack was sampled before it was killed): a mutation (or a future defect) blocks a wait; the runner's kill reaches the parent only;
SDL's handler turns the helper's SIGTERM into an event nobody reads. The fix targets the last two links and the sleeping-forever property.
**Cost if wrong.** If a real library hang exists the deadline (`TL-D`) names its wait within 10 minutes the next time; nothing is hidden by the ruling.

## TL-B — test processes run with `SDL_NO_SIGNAL_HANDLERS=1`

**Ruling.** A test-only C constructor sets it before `main` (`setenv(..., 0)`: an explicit caller value wins). SDL reads hints from the environment, so
every `SDL_Init` in the helper and its exit-test children honours it; SIGTERM and SIGINT then act by default. Production is untouched: an app that wants
Ctrl-C to quit keeps SDL's handler. **Cost if wrong.** A test needing SDL's quit-on-signal conversion is not known; it would set the hint itself.

## TL-C — no `.timeLimit` on the blocking GPU suites

**Question.** The request asked for `.timeLimit(.minutes(1))`. Does it make a hang fail?
**Evidence.** Probe TL-1: a main-actor body blocked on a semaphore and an async body on a never-resumed continuation outlived the limit by minutes with
no issue and no summary. **Ruling.** Not added: a trait that cannot fire reads as protection that is not there. The process deadline (`TL-D`) is the
mechanism. **Cost if wrong.** A Swift Testing release that interrupts blocked bodies would make it free: re-run the probe on a toolchain bump (owner: the
next toolchain bump, record 154).

## TL-D — every `MetalUISDLTests` process has a deadline: `_exit(71)` naming the variable

**Ruling.** `METALUI_TEST_DEADLINE_SECONDS`, default 600 (the whole suite takes 10-16 s on macOS), `0` disables, junk is the default. On expiry the
process writes a message naming the variable and exits 71; on macOS first a best-effort `sample` file path is printed (`TL-H`). Applies to the exit-test
children too (same binary). A hang therefore fails the run instead of sleeping, and a workflow's 12-minute rule is never needed for this suite.
**Cost if wrong.** A legitimately long run (a 100k-row stress) would be cut: set the variable; Linux lavapipe's full run must stay far under 600 s (checked).

## TL-E — an orphaned helper exits: `_exit(70)` when `getppid()` changes

**Ruling.** A constructor-started thread polls every 500 ms (C thread, never a test sleep). Polling over `kqueue`/`prctl(PR_SET_PDEATHSIG)` because one
portable loop covers macOS and Linux and is unit-testable through callbacks (`TL3`, `TL4`). **Cost if wrong.** Up to 0.5 s of orphan life; a reparent to a
subreaper (not PID 1) also counts as a change, which is the intended meaning.

## TL-F — no production change: no deadline inside `waitBlocking`

**Question.** Should `SDLGPUFence.waitBlocking` and `Submitted.await` carry a bound? **Ruling.** No: `GB-F` says "no cancellation" on purpose (Metal's
`waitUntilCompleted` parity), a bound would be a behaviour change and a hook consulted by production code for a test's sake, and `TL-D` already bounds the
process. No library bug was found. **Cost if wrong.** A mutation's failure reads "deadline" rather than naming the verb; the `sample` file names it.

## TL-G — the 18-minute parallel whole-suite hang is carried

**Evidence.** Record 150's run is not reproducible: two parallel whole-suite runs took 10.8 s and 10.0 s. **Ruling.** Carried, not guessed at; the next
recurrence now ends at the deadline with a sampled stack. **Cost if wrong.** A window-test race stays latent; `--no-parallel` remains the rule.

## TL-H — a deadline run samples itself on macOS

**Ruling.** Best effort: `/usr/bin/sample <pid> 3 -file <path>` spawned with `posix_spawn`, waited at most 10 s, failure ignored; no other platform
(Linux has no equivalent in the image). **Cost if wrong.** An unwritable temp directory loses the sample, never the exit.

## TL-I — Windows is carried

**Ruling.** The target compiles to nothing under `_WIN32` (no `getppid`, no pthread by default). **Cost if wrong.** A Windows hung SDL test sleeps as before;
`Backends/SDL` tests are not run by Windows CI today (CLAUDE.md), owner: the first Windows SDL-test job.

## TL-J — the end-to-end orphan exit is a probe, not a pin

**Ruling.** TL3/TL4 pin the watcher's decision and TL1/TL2 pin the environment; whether the constructor is linked and wired is measured by
`docs/probes/sdl-orphan-exit.sh` (kill -9 the parent of a blocked helper, assert it is gone within 3 s) recorded in its header, since a test cannot
orphan its own runner. **Cost if wrong.** A regression of the wiring alone is caught by TL1 (the variable) but not the watcher thread's start.
