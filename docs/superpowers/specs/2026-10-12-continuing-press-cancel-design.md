# Continuing press cancel — design spec

Item C26. Rulings: [`../2026-10-12-continuing-press-cancel-decisions.md`](../2026-10-12-continuing-press-cancel-decisions.md)
(`GC-A`…`GC-E`). Evidence: `docs/probes/swiftui-lost-release.swift` (header).
Baseline `930db4a`: **3472 tests in 3 suites**, the `FR-J no-argument frame:
succeeded=` line, 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
`swift build --build-tests` 0 warnings; pixels 0 px in the fourteen offscreen
images (`docs/probes/demo-pixels/compare.sh <scratch> 930db4a HEAD`);
`DemoFrameDeterminismTests` `Expected.swift` unedited.

## 0. The report, reproduced, and what the probe says

`Window.dispatchGestures` treats a primary press on the element the live arena
belongs to as the second press of a tap sequence (`continuing: true`), which fails
every undecided non-tap leaf through `fail(_:)`. A drag that had reported and
whose release was lost is dropped with neither `onEnded` nor `onCancelled`.
Reproduced headless (`FakePlatformWindow`, a 300x300 window, one `half()` box,
`DragGesture(minimumDistance: 0)` with the three callbacks): down, drag, down,
up reads `["changed", "changed"]` (**measured on `930db4a`**: no `cancelled`, no `end`, and the second press starts nothing at all) where the contract is
`["changed", "changed", "cancelled", "changed", "end"]`. The throwaway repro was not committed (a red test breaks the suite); test 1.1 below is it.

SwiftUI (probe, macOS 27.0.1): the second press cancels the first drag (no
`end`) and starts a new one (`L1`, `L2`); a bare `mouseMoved` cancels nothing
(`L3`). Not measured: a double-click beside a drag (the arm was a broken
instrument and was removed); MetalUI's own contract rules that case (§3, 1.7).

## 1. API

None. No public declaration, no inventory row, no divergence, no platform seam.

## 2. Implementation (one lane)

1. `Sources/MetalUI/Gesture.swift`, `press(at:clickCount:continuing:modifiers:)`,
   `.drag` arm: `if continuing { if let c = cancelCallback(leaf) { cancels.append(c) }; fail(leaf); continue }`;
   return `cancels + resolve()`. (`GC-B`)
2. `Sources/MetalUI/Window.swift`, `dispatchGestures` `.mouseDown`: the continuing
   branch requires `!arena.isPressing` (comment cites `GC-C`); otherwise the
   existing `arena.abandon()` and fresh-arena path runs. (`GC-C`)
3. Doc comments of `press(continuing:)` and `abandon()` updated.

Files: the two sources, `Tests/MetalUITests/ContinuingPressCancelTests.swift`
(new; copies `GestureFollowupTests`' private helpers, they are `private`), the
probe, the decisions doc and record. Nothing else.

## 3. Tests (all new, in `ContinuingPressCancelTests.swift`; each red before unless stated)

Mutation column: restore the quoted code, run the **unfiltered** suite, name the
reddened tests. `W` = through a `Window`, `A` = `GestureArena` directly.

| id | name | what | red-before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 W | `aPrimaryPressOnTheSameElementAfterALostReleaseCancelsTheReportedDrag` | down, drag, down, up: `changed, changed, cancelled, changed, end` | yes (no `cancelled`, `end` for the first press) | revert `GC-C` condition |
| 1.2 W | `aLostReleaseDragWithAMinimumDistanceStartsAgainOnTheNextPress` | `minimumDistance: 10`; moved past it, lost release, press, move past, up: one `cancelled`, then a full second drag | yes | revert `GC-C` |
| 1.3 W | `aLostReleaseCancelsOnceAndALaterReleaseDoesNotCancelAgain` | after 1.1, a further press elsewhere: no second `cancelled` | passes (regression pin) | make `cancel` not fail the leaf |
| 1.4 A | `aContinuingPressCancelsAReportedDragThroughTheCancelPath` | arena: `press`, `move`, `press(continuing: true)` with no release: callbacks = `[changed, changed, cancelled]`, no end | yes | `GC-B` back to `fail(leaf)` |
| 1.5 A | `aContinuingPressDoesNotCancelADragThatNeverReported` | `minimumDistance: 10`, no move: no `cancelled` | passes | `cancelCallback` ignoring `activated` |
| 1.6 W | `aRealDoubleClickStillCompletesATapCountTwoAndFiresNothingSpurious` | `SpatialTapGesture(count: 2)` plus a sibling `DragGesture(minimumDistance: 5)` with all callbacks: down/up (count 1), down/up (count 2): tap fires once with the second press's value, no `cancelled`, no drag callback | passes | `GC-C` using "same element" only (regress: treat every press as lost) |
| 1.7 W | `aDragWithClickCountTwoStillReportsTheSecondPress` | `IF-C`'s existing situation re-driven: release then press: not a lost release, `clickCount` 2 | passes | as 1.6 |
| 1.8 W | `aMouseMovedWhileTheLostPrimaryArenaIsPressingDoesNotCancelIt` | down, drag, `mouseMoved`: no `cancelled` (option (b) is not built) | passes | add a `.mouseMoved` cancel |
| 1.9 W | `aLostReleaseOnAnotherElementStillCancelsOnceAndBeforeTheNewCallbacks` | `IF-F` 1.5 re-pinned beside `GC-C` | passes | existing |
| 1.10 A | `aReportedLeafBehindAnEndedMemberIsNotLeftUncancelled` | try to build the `cancelBehindEndedMembers` case (`GC-D`) | if it cannot be built, drop and say so in the record | n/a |

`IF-F`'s pins (1.5-1.7 of `GestureFollowupTests`) and `WD-C`'s arena arm stay
unedited and green. If an existing test sends two `mouseDown`s with no `mouseUp`
as a double-click, `GC-C` reddens it: fix the fixture (insert the `mouseUp`)
only if the real platforms send one (AppKit and SDL always do), name the test in
the record, and take the fallback of `GC-C` if the suite objects broadly.

## 4. Demo expectation

None; no demo section. Pixels 0 px (the change is in input dispatch only).

## 5. Human checks (group `GC`, provisional)

`GC1` (real window): in the canvas demo or MetalCreator's viewport, start an orbit,
open Mission Control or a native menu mid-drag, return and press again on the same
element: the first drag reports `onCancelled` once (never `onEnded`) and the new
press orbits at once. `GC2`: a real double-click on a tap-count-2 element still
fires once. Not runnable by an agent.

## 6. Scope: deferred

- Lost-release detection on a bare `.mouseMoved` for the primary arena (option b):
  rejected, `GC-C`. Owner: none.
- A double-click beside a drag measured in SwiftUI: the probe's arm was broken;
  re-attempt belongs to a session that can post real events (as `IF-D`/`IF-G`).
  Owner: none.

## 7. Lanes

One. Order: write 1.1, 1.4 red (the first commit), then the two edits, then the
remaining tests, mutations, full suites (`swift build --build-system native
--build-tests`, unfiltered `--no-parallel`), pixel compare, docs.
