# Test hygiene - decisions

Rulings for round-3 item R3-3. Record: `../record/176-test-hygiene.md`. Branch `fix/test-hygiene` from `7d3d1b80`. Reserved divergence labels 905-914: none taken.

Prefix **`TK-`**, lettered. **Next unused: `TK-E`.** (Moves in the commit that appends a ruling.)

**Carried.** `EO-H`, `HT-Y`, `HT-Z`, `RU-B`, `AS-G`. No SwiftUI probe, no gpui comparison: no observable behaviour moves; tests only.

## TK-A - The AppKit sheet tests skip, with a stated reason, when the session cannot show a sheet

**Question.** Why does an unfiltered `swift test --build-system native --no-parallel` not finish on a locked Mac, and what guard stops it?
**Ruling.** Measured at `7d3d1b80` with the screen locked (`CGSSessionScreenIsLocked = 1`, on console): unfiltered, `appKitOpenDialog…`, `appKitSaveDialog…`, `appKitCancelledDialog…`, `appKitDismissPresentation…` and `appKitSecondDialogWhileASheetIsUpAnswersFalse` each spend 61 s inside `presentFileDialog` (`NSOpenPanel.init` waiting on the remote view service), then fail "no sheet attached": 4644 tests, 5 issues, 664 s. The same nine tests pass alone while locked (about 1 s each). A bisection by test-name ranges (1-899, 900-1668, 1669-1768 of the run's order, each plus the panel test) passed; 1-1768 together failed, so the trigger is accumulated process state, not one test, a window count (200 key windows did not reproduce it), idle time (330 s did not), file descriptors (136), or any single module (Platform, Text, Render, Testing, Scaffold, Core, SystemFonts, ShaderRuntime each passed with the panel test). It was not found. The guard is therefore the one condition the failure was seen under: `AppKitPresentationTests` reads `CGSessionCopyCurrentDictionary` (no AppKit object, so it runs before anything that can block) and the seven sheet tests carry `.enabled(if: canShowSheets, "…")` (session on the console, screen not locked); the two window-only tests need only the console session. macOS CI runs a logged-in console session, unlocked, so both flags read true and the tests run there.
**Evidence.** `docs/record/176-test-hygiene.md` section 1. Unverified: an unlocked run on this Mac (the Mac stayed locked), and CI itself (not runnable locally).
**Cost if wrong.** A locked Mac skips tests that would have passed when run alone; an unlocked Mac that still hits the accumulated-state hang is not protected.

## TK-B - The guard is a trait, evaluated once per process, never inside the test body

**Ruling.** `.enabled(if:)` is evaluated before the body, so a skipped test never reaches `NSOpenPanel.init`. A test that needs a panel adds the trait; the body is not the place to detect the session.
**Cost if wrong.** A new panel test without the trait hangs a locked run again.

## TK-C - `aTaskCompletesUnderRunUntilIdle` waits with `runUntil`, not a count of `runUntilIdle()` calls

**Question.** Is the EO-H flake still live after `HT-Y`/`HT-Z`?
**Ruling.** Yes. Reproduced in the `metalui-portable` image (aarch64, Swift 6.4.1) with 12 busy processes on 12 CPUs: the test as it stood (a loop of up to 64 `runUntilIdle()` calls) failed 4 of 40 runs, each `loader.value → 0`. The task body had not run at all: 64 rounds of four yields are microseconds, and under load the executor had not yet handed the task its turn, so the count was a bet on scheduling. `HT-Y`/`HT-Z` changed what counts as idle, not that. The test now calls `runUntil { loader.value == 42 && drawn() == [50] }`, which ticks, reads the condition and yields until it holds and fails only after its real-time bound (10 s, a slow machine waits longer); it then settles with `runUntilIdle()`. Same load, 40 of 40 passed. `runUntil(timeout:_:)` is the right tool for any wait on work the harness cannot see being finished by its own turns.
**Cost if wrong.** The 10 s bound is a wall-clock read; a machine slower than that fails.

## TK-D - SDL's Cocoa driver reports the process's launch arguments as window-0 drops; `sdlAFileDroppedOnTheAppIsAnOpenURL` records only its own URLs

**Question.** Why did `sdlAFileDroppedOnTheAppIsAnOpenURL` fail once in 8 runs?
**Ruling.** Not a parallel-run race. The failing run's `opened` read `[["file:///SDLAppShell"], ["file:///…/MetalUISDLTests"], [our batch]]`: the `--filter SDLAppShell` argument and the test binary path, delivered by AppKit's `openFile:` through SDL as window-0 `DROP_FILE` + `DROP_COMPLETE`. They surface on whichever pump first runs the Cocoa loop, park (no handler yet) and are flushed when the test assigns `onOpenURLs`, so whether this test sees them depends on scheduling (1 in 7 and 1 in 6 with a `--filter`, 0 in 30 after the change). The platform's behaviour is right (a launch document is an open, `AS-G`); the test now records only the URLs it pushed and ignores other batches. Mutation: a stray window-0 batch pushed before the handler passes with the filter and fails without it (the same two expectations that failed).
**Cost if wrong.** A real regression that adds an extra batch of our own URLs is still seen; one that emits only foreign URLs is not, and no test claims it.
