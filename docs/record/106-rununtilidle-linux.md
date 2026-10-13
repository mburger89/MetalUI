# 106 — `runUntilIdle()` after a click on Linux

Branch `fix/rununtilidle-linux` from `848ee029`. **Not a plan task**: item C29 of the gpui-gap
priority list (user request 2026-10-02), found by item 10b (record 103 §7, `DG-P`). Merged with master `b17aee19` (§103, no conflict; no other 106 on master). Spec
`docs/superpowers/specs/2026-10-13-rununtilidle-linux-design.md`; rulings `RU-A`, `RU-B` in the new
decisions doc `docs/superpowers/2026-10-13-rununtilidle-linux-decisions.md` (next unused `RU-C`).
**No public API, no divergence (labels 365–374 unused), no probe (no SwiftUI claim).** One source
edit: `Sources/MetalUI/Window.swift`.

## §1 Reproduction (red first)

`Tests/MetalUITestingTests/RunUntilIdleAfterClickTests.swift` test 3.1 (a `Button`, `click`, then
`try await runUntilIdle()`) in `metalui-portable` (`swift:6.4-noble`, arm64, volume
`metalui-sdl-build-rununtilidle-linux`), commit `11b561d9`:
`✘ Test runUntilIdleReturnsAfterAButtonClick() recorded an issue at RunUntilIdleAfterClickTests.swift:10:2: Caught error: the window was still drawing after 64 rounds`.

## §2 Isolation

A throwaway probe (not kept) printed per round, after the click: `Thread.isMainThread` **false**
(Swift Testing's async test runs the main actor on a pool thread), `observationDirtyings` 1, 2, 3, 4,
5, 6, `needsRedraw` true each round, `hasActiveAnimations` **false** throughout. So not the pressed
wash, not a hover/tooltip timer (no animation or timer is live), and not a main-queue drain: the
cause is the observation path. `Window.markDirtyFromObservation` branches on `Thread.isMainThread`;
the flush's own `onChange` (the sentinel write the previous frame armed) therefore hopped, and the
hop ran after `isFlushing` was cleared (`RU-A`). The first frame has no armed session to trip, which
is why a window never clicked was idle.

## §3 Fix

`Window.flushingThread` (`FlushingThread`, lock-guarded `Thread?`), set around the sentinel write;
`markDirtyFromObservation` returns first thing on that thread. Probe after: `observationDirtyings`
0, `needsRedraw` false, `runUntilIdle()` returns. Test 3.2 pins that a real `@Observable` write after
a click is still drawn, then idle.

## §4 Mutations (Linux image, `--filter RunUntilIdleAfterClick`, restored from a copy, `git status`
clean after each)

| Mutation | Reddened |
|---|---|
| delete `if flushingThread.isCurrent { return }` | `runUntilIdleReturnsAfterAButtonClick` (`notIdle`), `anObservableWriteAfterAClickIsStillDrawnAndThenIdle` (`notIdle`) |
| delete `flushingThread.set(nil)` in the `defer` | `anObservableWriteAfterAClickIsStillDrawnAndThenIdle` (`[70]` expectation: the write was dropped) |

| same mutation, macOS (`--filter` observation/redraw/new tests, not the full suite) | `anObservableWriteAfterAClickIsStillDrawnAndThenIdle`, `aCommandsObservableWriteOutsideInputRedrawsTheBar` (`MenuBarStripTests`) |

`flushingThread.set(Thread.current)` deleted is the first row's effect. **On macOS the first
mutation reddens nothing** (the main-thread branch is still guarded by `isFlushing`): the fix is
value-identical there, by construction, and the existing `ObservationTests` (the `observationDirtyings`
pins) stay green.

## §5 Counts

macOS, `swift package` native build, `swift test --build-system native --no-parallel`: **3584 tests in
3 suites** (3582 + 2) on the branch alone; **3626 tests in 3 suites** (master's 3624 + 2) after the merge with `b17aee19`, 229 guards unmoved, the five `AppKitPresentationTests` sheet issues of `CI-AF` on a locked screen and
nothing else, 0 `error:`, `FR-J no-argument frame: succeeded=true`; `swift build --build-tests` 0
`warning:`. Linux image: `MetalUITestingTests` + observation tests 127 passed with the two new tests green; the
unfiltered image run of the root package was started but only its last 60 lines were kept, and they
show no failure (not a counted result).

## §6 The guides (`DG-P`)

Run in the image with this fix: the `docs/guides` tree (`9f8b6c35`) with its `Window.swift`
replaced by this branch's and its one workaround (`GuideMirrorsLane1` line 416, `setNeedsRedraw()` then
`tick()`) replaced by `try await window.runUntilIdle()`: **167 `MetalUITestingTests` passed**, all guide
mirrors and the `docs/testing.md` recipe tests among them. So the workaround **can go**, and
`docs/testing.md`'s and the state guide's "(the observation hop is asynchronous off macOS)" caveat is
no longer needed for a click; the hop is still asynchronous for an off-main-thread write. The guides'
text is left to item 10c.

## §7 Demo pixels

`docs/probes/demo-pixels/compare.sh <scratch> 848ee029 HEAD`: 14 of 14 images **scene identical,
0 differing pixels** (`HEAD` `11a160f6`), the controls at their recorded values.
