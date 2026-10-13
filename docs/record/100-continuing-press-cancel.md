# 100 — Continuing press cancel (C26)

Branch `fix/continuing-press-cancel` from `930db4a`. **Not a plan task**: item C26 of the
gpui-gap priority list (user request 2026-10-02), reported by MetalCreator (developer-0a,
2026-10-12, gap VI-b, found planning C16's adoption; not blocking). Spec
`docs/superpowers/specs/2026-10-12-continuing-press-cancel-design.md`; rulings `GC-A`…`GC-G` in
`docs/superpowers/2026-10-12-continuing-press-cancel-decisions.md` (next unused `GC-H`); merged with master `3fce05f` (§96 text selection; no conflict, number 100 still free); probe
`docs/probes/swiftui-lost-release.swift` (arms `L0`…`L3`).

**Status: LANDED.** One lane. No public declaration, no inventory row, no divergence label
(305–314 untouched), no platform seam, no SDL change.

## §1 The bug and the fix

A primary press on the element the live arena belongs to was treated as a tap sequence's second
press (`continuing: true`), which failed every undecided non-tap leaf through `fail(_:)`. A drag
that had reported and whose release was lost (Mission Control, a native menu) was dropped with
neither `onEnded` nor `onCancelled`, and the new press started nothing.

- **`GC-B`** (`Gesture.swift`, `press(…continuing:)`, `.drag` arm): takes `cancelCallback(leaf)`
  before `fail(leaf)` and returns the cancels ahead of `resolve()`.
- **`GC-C`** (`Window.swift`, `dispatchGestures` `.mouseDown`): the continuing branch requires
  `!arena.isPressing`; a press that finds the arena still pressing is a lost release, so
  `abandon()` (cancels what reported) and a fresh arena form, as for a press elsewhere. SwiftUI
  agrees (probe `L1`/`L2`: cancel, then the second press starts a drag; `L3`: a bare move cancels
  nothing, so option (b) is not built).

## §2 Red first

Commit `1bdf951` (before the edits): 1.1 `["changed", "changed"]` against
`["changed", "changed", "cancelled", "changed", "end"]`; 1.4 `["changed", "changed"]` against
`["changed", "changed", "cancelled"]`.

## §3 Tests and mutations (`ContinuingPressCancelTests.swift`, 9 tests)

Suite after: **3481 tests in 3 suites** (3472 + 9), the `FR-J no-argument frame: succeeded=true`
line present, 0 `error:`; the only issues in the unmutated run are the five
`AppKitPresentationTests` sheet issues of a locked screen (`CI-AF`). Native build and
`swift build --build-tests`: 0 `warning:` beyond SwiftPM's deprecation notice.

| mutation | reddened (besides the baseline) |
|---|---|
| M1 revert `GC-C`'s `!arena.isPressing` | 1.1, 1.2, 1.3 |
| M2 `GC-B` back to `fail(leaf)` (no cancel) | 1.4, 1.3 (first shape of the test; see GC-G) |
| M3 `cancelCallback` ignores `activated` | 1.5, `aDragThatNeverBeganIsNotCancelled` |
| M4 continuing branch unreachable (`if false`) | 1.6, `aDoubleClickDeliversClickCountTwo`, `aTapSequenceReportsTheLastPressModifiers`, `aCountTwoTapEndsOnTheSecondReleaseByClickCount`, `aDoubleClickRunsOnlyTheDoubleWhicheverIsInner` (x3), `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren`, `aMiddleDragDuringAPendingPrimaryTapSequenceDisturbsNeither` |
| M5 `cancel()` does not fail the leaf (after 1.3 was re-shaped) | 1.3 |
| M6 drop `fail(leaf)` in `GC-B`'s arm | 1.4 (its trailing `cancel()`) |

Findings: the first M5 reddened nothing (1.3's arena half reached a leaf the continuing path had
already failed); 1.3 was re-shaped and M5 re-run (GC-G). **1.7 is not separated by M4**: after a
release the drag has ended and the arena is dead, so the click count is the fresh arena's either
way; it stays as an `IF-C` pin (GC-G). **1.10 dropped**: `cancelBehindEndedMembers` cannot owe a
cancel (GC-G). 1.8 is the lost-release shape of the existing
`aPrimaryArenaIsNotCancelledByAMoveWithoutAButton`. `IF-F`'s pins, `WD-C`'s arena arm and `IF-C`'s
pins stay green and unedited; no two-`mouseDown` fixture needed fixing.

**Audit (`GC-D`/`GC-F`)** pins by path: `abandon()` `aDroppedPrimaryDragReportsCancelledOnceAndNotEnded`
and 1.9; `cancel()` on stale arenas `aStaleButtonArenaReportsCancelledWhenTheSameButtonPressesAgain`,
`aStalePinchArenaReportsCancelledBeforeASameCentrePinchBegins`; close
`aWindowCloseCancelsLiveArenasBeforeOnDisappear`; draggable winning
`aDragStartedByADraggablesPreviewIsCancelled`; window-drag winning `WindowDragTests`'
`aHandleOverAGestureViewportDragsTheWindowAndCancelsTheViewport`; continuing press 1.1/1.4.

After the merge with master `3fce05f` (`swift package clean`, native build, unfiltered `--no-parallel`): **3513 tests in 3 suites passed** (3504 + 9), the `FR-J` line present, 0 `error:`, 0 recorded issues; no guard added (221 unmoved); census 3446 unmoved; the inventory checks print nothing.

## §4 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> 930db4a HEAD`: all fourteen images `differing=0`,
scenes identical; controls read their recorded non-zero values. `DemoFrameDeterminismTests`
`Expected.swift` unedited.

## §5 Owed

Human checks `GC1` (a real orbit interrupted by Mission Control or a native menu, then pressed
again: one `onCancelled`, the new orbit starts) and `GC2` (a real double-click still fires a
`count: 2` tap once); neither can be run by an agent. Added in the Record phase as
`docs/verification/human-checks.md` group `GC` (`GC1`, `GC2`) and record 03. Deferred: a bare
`.mouseMoved` cancel for the primary arena (rejected, `GC-C`); a SwiftUI double-click-beside-drag
measurement. CLAUDE.md's rule paragraph, the `GC-` prefix, the counts, `docs/api-overview.md`, `docs/migration.md` (one row) and the record index were written in the Record phase.
