# 82 — Variable-height `List`

Branch `feat/variable-height-list` from `70ed000`. User request 2026-10-02,
item 7 of the gpui-gap priority list (not a plan task). Spec
`docs/superpowers/specs/2026-10-08-variable-height-list-design.md`; rulings
`docs/superpowers/2026-10-08-variable-height-list-decisions.md` (`VL-`).
Divergence labels reserved for this branch: 145–149.

## §1 Design session (2026-10-08)

- **Probe** `docs/probes/swiftui-variable-height-list.swift` (new), run in both
  SA-O forms, byte-identical 23 lines, screen unlocked. SwiftUI's `List` sizes
  a row from its content at the list's width plus 8 points of insets, floored
  at 24 (`V0`…`V3b`); estimates unrealised rows at the constant 24 (`R2`);
  lands `scrollTo` onto an unrealised row exactly (`T`); ignores an off-screen
  row's content change (`A1`/`A2`/`A4`); does not anchor an insertion above
  the top (`A3`, 24 points); a non-lazy `ScrollView` does not anchor (`A6s`,
  the separating arm); `List(_:rowContent:)` and both selection overloads
  compile (`S1`).
- **gpui** `crates/gpui/src/elements/list.rs` read from upstream (not run):
  `SumTree<ListItem>` of `Unmeasured`/`Measured`, `ListOffset { item_ix,
  offset_in_item }`, `splice`/`reset`, `overdraw` — `VL-G`'s anchoring idea.
- **Rulings** `VL-A`…`VL-M` (next unused `VL-N`); divergences 145, 146, 147
  proposed (rows land in lane 3); divergence 84 to be amended.
- **Baseline** at `70ed000`: native build clean; **2672 tests in 3 suites**
  passed, `FR-J no-argument frame: succeeded=true` (spec §0.1).

## §2 Critic pass (2026-10-08)

- **Probe re-taken** in both `SA-O` forms, screen unlocked: byte-identical
  between the forms and to the recorded 23 lines, exit 0. Two labels
  corrected in its header (output unchanged): `A2`'s row 98 was **not**
  realised (98:24 where a measured row reads 88), and `A6s` reads only the
  clip — `A3` is the arm that reads a row move. What SwiftUI does when a
  *realised* row above the viewport changes height is unprobed: no divergence
  is claimed for `VL-G` items 1–2 (`VL-N`).
- **Defects fixed** (rulings `VL-O`…`VL-R`, folded into the spec): the
  anchor row removed by a data change had no rule (`VL-O`, test 2.7b, two
  arms); `forgetMeasurements` keeps ids (`VL-O`); the carried `scrollTo`
  refinement could not learn its request's scope or anchor — lane 1 widens
  `Frame.unresolvedScrollRequests(enclosing:)`, `ListLeadReveal` gains only
  `refined` (`VL-P`, test 1.15); `ListRows.swift` and `VariableRowsLayout`
  move to lane 1 with three direct layout tests (`VL-Q`, 1.16–1.18); four
  mutations that could not redden or would truncate the run replaced, exact
  frame counts, divergence 147 pinned at the list level, index work pinned in
  the non-gated performance test, an animation pin (2.7c), lane 2 runs the
  demo-pixel comparison and the env-gated 100k tests (`VL-R`).
- **Rejected** (`VL-S`, and `VL-Q`'s last paragraph): off-screen
  invalidation on a datum change, an `A` inventory row, a splice API now,
  parallel lanes inside this worktree.
- Next unused id `VL-T`.

## §3 Lane 1 — index, `Frame` hooks, row layout (2026-10-08)

Commits `126bfb1` (red: tests 1.1–1.18, the `AreaLeaf` fixture, stubs) and
`a806444` (implementation); this section and `VL-T` in the docs commit after.

- **Landed.** `RowExtentIndex<ID>` (`Sources/MetalUI/ListRowExtents.swift`):
  two Fenwick trees (measured sums, measured counts), so `offset(of:)` =
  measured prefix + unmeasured rows × estimate and a changed estimate costs
  nothing; the estimate is declared, else the running mean, else 24 (`VL-C`);
  `rebuild(ids:)` keeps heights by id (linear Fenwick construction),
  `forgetMeasurements(width:)` keeps ids (`VL-O`); `nodeVisits`/`rebuilds`
  work counters. `Frame.noteScrollAnchorAdjustment(scroller:delta:)`, summed
  and added after the absolute resolutions in `applyScrollResolutions`, a zero
  or non-finite delta never recorded (`VL-G` item 2).
  `Frame.unresolvedScrollRequestsWithScope(enclosing:)` beside the unchanged
  two-member accessor (`VL-P`, `VL-T` item 1). `ScrollRequestQueue.carry(_:)`
  without `onEnqueue` (`VL-H`). `VariableRowsLayout` and
  `ListRows.arrangement` (default `.uniform`; nothing passes `.variable` yet,
  `VL-Q`). No public declaration; both inventory scripts print nothing.
- **Red-before** (stubs at `126bfb1`, filtered run of the 18 tests: "Test run
  with 18 tests in 0 suites failed … with 60 issues"), each test's first
  failing line:
  1.1 `RowExtentIndexTests.swift:19` `index.estimate == 24`;
  1.2 `:34` `index.estimate == 40`; 1.3 `:47` `index.estimate == 20`;
  1.4 `:79` `mismatches.isEmpty`; 1.5 `:96` `index.index(containing: y) == expected`;
  1.6 `:108` `index.offset(of: 3) == 78`; 1.7 `:123` `index.totalExtent == 90`;
  1.8 `:144` `index.count == 4`; 1.9 `:163` `index.estimate == 15`;
  1.10 `:185` `found == middle`;
  1.11 `ScrollAnchorAdjustmentTests.swift:157` `try storedOffset(window) == 130`;
  1.12 `:177` `try storedOffset(window) == 230`;
  1.14 `:208` `window.scrollRequests.pending.count == 1`;
  1.15 `:226` `seen.count == 1`;
  1.16 `VariableRowsLayoutTests.swift:62` `log.byName["r0"] == bounds(0, 110, 100, 10)`;
  1.17 `:84` `log.byName["a"] == expected[0]`;
  1.18 `:103` `log.byName["a"] == bounds(100, 130, 200, 20)`.
  **1.13 passes against the stub** by construction (a no-op hook writes
  nothing and asks for nothing — what 1.13 asserts); its instrument is
  mutation M1.13 below, which reddens it.
- **Suite** at `a806444`, native, unfiltered, `--no-parallel`: **"Test run
  with 2690 tests in 3 suites passed after 167.302 seconds"** (2672 + 18),
  `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:`
  SwiftPM's `--build-system native` deprecation notice;
  `swift build --build-tests` (default build system, lane-1 files touched and
  recompiled) 0 warnings. No guard added (175 unmoved).
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 70ed000 a806444`
  — controls as recorded (1048576 / 1031003 / 454895 / 0 / 1048576 / 0,
  distinct 544 / 216, prod modal 491221, distinct 529, indicator rects 0);
  **all fourteen images differing=0, scene identical**.
- **Mutations** (each on `a806444`, one file restored from a copy, full
  unfiltered native suite, 2690 tests every run, `git status --short` clean of
  sources after each; spellings in `VL-T` item 3) — every one reddens its
  named test:

  | # | Mutation | Reddened |
  |---|---|---|
  | M1.1 | fallback 24 → 28 | `anIndexWithNothingMeasuredEstimatesEveryRowAtTwentyFour`, `forgettingMeasurementsReturnsEveryRowToTheEstimate` |
  | M1.2 | mean before declared | `aDeclaredEstimateWinsOverTheRunningMean`, `aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes`, `aRebuildKeepsHeightsByIDAcrossAReorderAndAnInsertion`, `prefixOffsetsMatchANaiveSumAfterRecordsInAnyOrder`, `reRecordingARowReplacesItsHeight` |
  | M1.3 | mean → highest-index measured height | `theRunningMeanEstimatesUnmeasuredRows`, `aRebuildDropsHeightsOfIDsNoLongerPresent`, `forgettingMeasurementsReturnsEveryRowToTheEstimate` |
  | M1.4 | Fenwick update `k += k & -k` → `k += 1` | `prefixOffsetsMatchANaiveSumAfterRecordsInAnyOrder`, `aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes` |
  | M1.5 | descent `<=` → `<` | `indexContainingAnOffsetFindsTheRowWhoseSpanHoldsIt` |
  | M1.6 | drop the subtract-old step | `reRecordingARowReplacesItsHeight`, `prefixOffsetsMatchANaiveSumAfterRecordsInAnyOrder` |
  | M1.7a | forget clears sums, keeps counts | `forgettingMeasurementsReturnsEveryRowToTheEstimate` |
  | M1.7b | forget clears `ids` too | `forgettingMeasurementsReturnsEveryRowToTheEstimate` |
  | M1.8 | rebuild keyed by index | `aRebuildKeepsHeightsByIDAcrossAReorderAndAnInsertion`, `aRebuildDropsHeightsOfIDsNoLongerPresent` |
  | M1.9 | absent ids' heights kept in the mean | `aRebuildDropsHeightsOfIDsNoLongerPresent` |
  | M1.10 | linear prefix scan in `offset(of:)` | `aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes` |
  | M1.11a | adjustment not added | `anAnchorAdjustmentMovesTheStoredOffsetAfterPaintAndAsksForAFrame`, `anAnchorAdjustmentAddsToAScrollToResolutionInTheSameFrame` |
  | M1.11b | no `requestAnotherFrame` for an adjustment alone | `anAnchorAdjustmentMovesTheStoredOffsetAfterPaintAndAsksForAFrame` |
  | M1.12 | a resolution overrides the adjustment | `anAnchorAdjustmentAddsToAScrollToResolutionInTheSameFrame` |
  | M1.13 | zero delta recorded (and a frame requested) | `aZeroAdjustmentWritesNothingAndAsksForNoFrame` |
  | M1.14 | `carry` calls `onEnqueue` | `aCarriedScrollRequestDirtiesNothingAndResolvesNextFrame` |
  | M1.15 | accessor returns `anchor: nil` | `anUnresolvedRequestCarriesItsScopeAndAnchorToTheList` |
  | M1.16 | every row placed downward from slot 0 | `variableRowsPlaceTheAnchorAtItsOffsetAndTheRestAroundIt` |
  | M1.17 | rows placed with proposal `(nil, nil)` | `variableRowsAreMeasuredAtTheProposedWidth`, `variableRowsAtANilWidthTakeTheWidestRow`, `variableRowsPlaceTheAnchorAtItsOffsetAndTheRestAroundIt` |
  | M1.18 | heights measured at `(nil, nil)` | `variableRowsAreMeasuredAtTheProposedWidth`, `variableRowsAtANilWidthTakeTheWidestRow` |

  M1.11a's log had its summary line split by SwiftPM's stderr deprecation
  notice ("Test run with 2690 test⟨warning⟩s in 3 suites failed after 200.324
  seconds with 3 issues") — read by hand, not a truncation. No hang.
- **Ruling** `VL-T` (next unused `VL-U`). **Deferred to lane 2** as planned:
  `List` calling the index, the hook, the wide accessor and `.variable`; the
  env-gated 100k runs and the `nodeVisits` per-frame pins (`VL-R` items 7, 9).

## §4 Lane 2 — `List`'s variable branch (2026-10-08)

Commits `3bf8277` (red: tests 2.1–2.18 with 2.7b/2.7c, guard 2.19, 2.20/2.21,
stubs) and `14ac821` (implementation); this section and `VL-U` in the docs
commit after.

- **Landed** (`Sources/MetalUI/List.swift` only, spec §3.1/§3.3): the three
  `rowContent:` initialisers with doc comments, `estimatedRowHeight` clamped to
  "not declared" when non-positive or non-finite; `ListRowSizing`
  (`.uniform(Pixels)` / `.variable(estimate:)`) replaces the stored
  `rowHeight` (`swift package clean` before the first build); in
  `requestLayout` the index is `peek`ed from `ListOrigin.extents`, rebuilt by
  id on a count change or on a realised row whose recorded id differs, the
  anchor carried by id and placed at its old offset (`VL-G` item 3), `VL-O`'s
  removed-anchor fallback, `VL-F`'s window, `VariableRowsLayout` registered
  through `ListRows.arrangement`; in `prepaint` the index stored (only inside a
  vertical scroller), forgotten on a width change, each realised row's placed
  height recorded under its id, `D` noted through
  `Frame.noteScrollAnchorAdjustment`, `DD-F` staleness from the updated index
  and `offset + D`, and `VL-H`'s resolution with a refinement carried with its
  request's scope and anchor (`unresolvedScrollRequestsWithScope`). Ids,
  selection, keys, focus and AX run through the uniform construction; the
  uniform path's code is unchanged behind the `rowSizing` switch (`VL-I`).
  Paths spec §3.3 left open: `VL-U` item 4.
- **Red-before** (stubs at `3bf8277`, filtered native run of the 23: "Test run
  with 23 tests in 1 suite failed after 0.573 seconds with 39 issues"; 22 fail,
  the guard passes by construction, `VL-U` item 6), each test's first failing
  line:
  2.1 `VariableHeightListTests.swift:236` `log.bounds[1]?.origin.y == px(20)`;
  2.2 `:256` `log.bounds[0]?.size.height.value == expected`;
  2.3 `:281` `cold == 9440`;
  2.4 `:301` `log.built == Array(59...67)`;
  2.5a, 2.5b, 2.7, 2.7b, 2.7c, 2.8 `:214` `log.screenY[50] == 0` (the
  `rowFiftyOnTop` control: the stub never realises row 50 at 2460);
  2.6 `:370` `log.screenY[50] == -10`;
  2.9 `:516` `log.screenY[150] == 140`;
  2.10 `:535` `window.scrollRequests.pending.count == 1`;
  2.11 `:562` `log.screenY[163] == -10`;
  2.12 `:613` `target.bounds.size.height == px(30)`;
  2.13 `:690` `table.peek(longSlot, as: Int.self) == 3`;
  2.14 `:736` `lastFrame?.elementBounds[boxID]?.size.height == px(20)`;
  2.15 `:786` `rows == Array(0...6)`;
  2.16 `:806` `log.bounds[1]?.origin.y == px(20)`;
  2.17 `:830` `log.bounds[0]?.size.height == px(10)`;
  2.18 `:849` `listHeight == 4400`;
  2.20 `MeasurePerformanceTests.swift:612` `variableIndex(states)` (no index).
- **Corrected after the first green run** (`VL-U` item 1): rows 0…9 of the
  scrolled fixtures sum to 460, not 440 — 2.9's chain, 2.10's offset (4570)
  and 2.18's extent (4600) re-derived; 2.11's jump moved 5040 → 5070 (at 5040
  `D` was 0 and no frame was asked for, so the test saw no adjustment); 2.12's
  ⇧-click target (row 4 at y 100) lay outside the viewport — the sequence moved
  to rows 0/2/3. First implementation run of the 23 had read 9 issues in
  exactly those tests and in 2.20's then-unset work literal; nothing in
  `List.swift` changed for them.
- **2.20's work literal** from the cold column (a throwaway probe, deleted):
  `2n + 1` / `5n + 6` / `5n + 7` at n = 40, 160, 500, 2000 → **33 / 86 / 87**
  at r = 16, then read on the warm frames. Index visits derived from the code:
  17 / 21 (2.20), 31 / 47 (2.21); rebuilds 0.
- **Suite** at `14ac821`, native, unfiltered, `--no-parallel`, rebuilt after
  the last mutation: **"Test run with 2714 tests in 3 suites passed after
  181.602 seconds"** (the first green run, on the same code before a doc-only
  edit to `List`'s type comment, read the same count in 165.071 s) (2690 + 24: 21 in
  `VariableHeightListTests`, the guard, 2.20, and 2.21 counted while skipped),
  `FR-J no-argument frame: succeeded=true deprecations=2`, 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift build --build-tests` (default
  build system) 0 warnings. Guards 175 → 176 (2.19). Both inventory scripts
  print nothing (the census re-record is lane 3's).
- **The env-gated 100k pair** (`METALUI_RUN_100K_LIST_TEST=1`, filtered to
  both): "Test run with 2 tests in 1 suite passed after 55.104 seconds" — the
  uniform `aListsWorkIsTheSameFor100kRowsAsFor500` (cold 100k frame 47.4 s,
  printed, not asserted) and `aVariableListsWorkIsTheSameFor100kRowsAsFor500`
  (7.2 s for both counts' cold and warm frames): warm work 33 / 86 / 87 at 500
  and 100 000, 31 / 47 visits, no rebuild.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 70ed000 14ac821` —
  controls as recorded (1048576 / 1031003 / 454895 / 0 / 1048576 / 0, distinct
  544 / 216, prod modal 491221, distinct 529, indicator rects 0); **all
  fourteen images differing=0, scene identical**.
- **Mutations** (each on `14ac821`, one file restored from a copy, full
  unfiltered native suite of 2714, `git status --short` clean of sources after
  each; spellings in `VL-U` item 7; no hang) — every one reddens its named test:

  | # | Mutation | Reddened |
  |---|---|---|
  | MU | uniform spelling routed through the variable path | **`aListSizesItselfToCountTimesRowHeight`, `aListsWorkIsTheSameFor160RowsAsFor40`, `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent`** and 36 more: `aConditionalInAWindowedListRowIsNotResetByAnExcursion`, `aDisabledListShowsItsSelectionAndChangesNothing`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `aFractionalOffsetRoundsFirstDownAndLastUp`, `aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority`, `aGrownViewportIsFilledOnTheNextFrameWithoutInput`, `aListBelowAHeaderWindowsTheRowsOnScreen`, `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, `aListInAScrolledProposalScrollViewWindowsAtItsOffset`, `aListInAScrollerBelowTheWindowOriginWindowsTheRowsOnScreen`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aListWhoseOriginChangesIsReWindowedOnTheNextFrame`, `aListsFirstFrameAppearsEveryRowAndTheNextBuildDisappearsTheRowsOutsideItsWindow`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `aLoopInsideAWindowedListRowKeepsItsStateWhileTheRowIsOut`, `aLoweredListLaysOutEveryWindowedShape`, `aRowKeepsItsIdentityWhenItsPositionChanges`, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `aSelectedRowPaintsTheAccentBackground`, `aSurvivingForEachElementsListKeepsItsWindowedRowsState`, `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, `aWindowedListStillReportsItsFullContentHeight`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `anArrowPastTheWindowScrollsTheNewLeadIntoView`, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `distinctRowsGetDistinctIdentities`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `everyProductionRootsDeepestNativeLevelIsMeasured`, `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`, `scrollToComparesKeysByValue`, `scrollToReachesAnUnrealisedListRow`, `theListsSpacerIsANodeNotAnElement`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows`, `theVoiceOverScriptQuotesThePublishedTree` (406.5 s, 86 issues) |
  | M2.1 | rows pinned to the estimate | `aVariableListSizesEachRowToItsContent` and 20 more: every lane-2 test but 2.13 and the guard, 2.20 included |
  | M2.2 | `VariableRowsLayout` places rows at `(nil, nil)` | `aVariableRowIsMeasuredAtTheListsWidth` (rows read 40), `aVariableListInAHorizontalScrollerMeasuresEveryRowAtItsWidestWidth`, `aVariableListsWorkIsTheSameFor160RowsAsFor40`, `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement`, `variableRowsAreMeasuredAtTheProposedWidth`, `variableRowsAtANilWidthTakeTheWidestRow`, `variableRowsPlaceTheAnchorAtItsOffsetAndTheRestAroundIt` |
  | M2.3 | `trailingExtent` 0 | `aVariableListAnswersMeasuredPlusEstimatedExtent`, `aNonPositiveEstimateIsTreatedAsUndeclared`, `aRefinedRevealNeverRefinesAgain`, `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement`, `scrollToAnUnmeasuredRowLandsExactlyOnceMeasured` |
  | M2.4 | window by division at the estimate | `aVariableListWindowsByPrefixOffsets` and 12 more (2.5a, 2.5b, 2.6, 2.7, 2.7b, 2.7c, 2.8, 2.9, 2.10, 2.11, 2.15, 2.20) |
  | M2.5a | placed from `offset(of: first)` | `aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopInThatFrame`, `aSameCountDataChangeIsDetectedFromARealizedRow`, `aVariableListSettlesWithoutInput`, `aVariableListsWorkIsTheSameFor160RowsAsFor40`, `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement`, `anInsertionAboveTheViewportKeepsTheRowOnTop`, `anInsertionAboveTheViewportUnderWithAnimationKeepsTheRowOnTopEveryTick`, `removingTheRowOnTopPutsTheNextRowInItsPlace` |
  | M2.5b (= 2.7c's) | `noteScrollAnchorAdjustment` not called | `aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopOnTheNextFrame`, `anInsertionAboveTheViewportUnderWithAnimationKeepsTheRowOnTopEveryTick`, `aRefinedRevealNeverRefinesAgain`, `aSameCountDataChangeIsDetectedFromARealizedRow`, `aVariableListSettlesWithoutInput`, `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement`, `anInsertionAboveTheViewportKeepsTheRowOnTop`, `removingTheRowOnTopPutsTheNextRowInItsPlace`, `scrollToAnUnmeasuredRowLandsExactlyOnceMeasured` |
  | M2.6a | `forgetMeasurements` skipped | `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement`, `aVariableListAnswersMeasuredPlusEstimatedExtent` |
  | M2.6b | no anchor (placed from the first row, no `D`) | `aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement` and 9 more (2.5a, 2.5b, 2.7, 2.7b, 2.7c, 2.8, 2.10, 2.11, 2.20) |
  | M2.7 | anchor by index across a rebuild | `anInsertionAboveTheViewportKeepsTheRowOnTop`, `anInsertionAboveTheViewportUnderWithAnimationKeepsTheRowOnTopEveryTick`, `aSameCountDataChangeIsDetectedFromARealizedRow`, `removingTheRowOnTopPutsTheNextRowInItsPlace` |
  | M2.7b(a) | the id before preferred | `removingTheRowOnTopPutsTheNextRowInItsPlace` (arm 1 and arm 2) |
  | M2.7b(b) | `oldAnchorIndex` once the id is gone | `removingTheRowOnTopPutsTheNextRowInItsPlace` (**arm 2 only**, as `VL-O` predicted) |
  | M2.8 | realised-id check skipped | `aSameCountDataChangeIsDetectedFromARealizedRow`, `removingTheRowOnTopPutsTheNextRowInItsPlace` |
  | M2.9 | no refinement carried | `scrollToAnUnmeasuredRowLandsExactlyOnceMeasured`, `aRefinedRevealNeverRefinesAgain` |
  | M2.10 | `refined` guard dropped | `aRefinedRevealNeverRefinesAgain` |
  | M2.11 | a frame requested beside every adjustment | `aVariableListSettlesWithoutInput` and 10 more (2.4, 2.5a, 2.5b, 2.6, 2.7, 2.7b, 2.7c, 2.8, 2.9, 2.10) |
  | M2.12 | variable branch skips `rowClick` | `selectionAndShiftRangesAreUnchangedInAVariableList` |
  | M2.13 | variable branch drops the row's `.id` | `aVariableListRowsStateSurvivesABoundedExcursionButNotALongerOne` (both slots read nil), `aFocusedVariableRowKeepsFocusOutOfWindow`, `selectionAndShiftRangesAreUnchangedInAVariableList` |
  | M2.14 | variable branch drops the list's `isFocusable` | `aFocusedVariableRowKeepsFocusOutOfWindow`, `selectionAndShiftRangesAreUnchangedInAVariableList` |
  | M2.15 | variable branch drops `logicalIndex` | `aVariableListPublishesItsLogicalCountAndRealizedRowIndices` |
  | M2.16 | `withState` in `requestLayout` | `aVariableListOutsideAScrollerMintsNoStateEntry` |
  | M2.17 | `VariableRowsLayout` heights at `(nil, nil)` | `aVariableListInAHorizontalScrollerMeasuresEveryRowAtItsWidestWidth`, `aVariableRowIsMeasuredAtTheListsWidth`, `aVariableListsWorkIsTheSameFor160RowsAsFor40`, `variableRowsAreMeasuredAtTheProposedWidth`, `variableRowsAtANilWidthTakeTheWidestRow` |
  | M2.18 | clamp dropped | `aNonPositiveEstimateIsTreatedAsUndeclared` (the 0 and −5 arms) |
  | MG2.19 | `rowContent:` renamed `content:` | `theVariableListSpellingsCompileFromAPlainImport` |
  | M2.20a | a rebuild every bounded frame | `aVariableListsWorkIsTheSameFor160RowsAsFor40` (rebuilds, then visits 17 / 21) |
  | M2.20b | linear `offset(of:)`, with `METALUI_RUN_100K_LIST_TEST=1` | `aVariableListsWorkIsTheSameFor160RowsAsFor40`, `aVariableListsWorkIsTheSameFor100kRowsAsFor500`, `aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes` |

  M2.10's log held a byte sequence the driver could not decode as UTF-8; it was
  re-read with replacement (summary "2714 tests … failed … with 2 issues") and
  the driver resumed from M2.11.
- **Session note**: the session scratchpad is shared with the parallel
  branches' agents (its `mut/` held their logs); the first mutation run was
  stopped during MU, `List.swift` restored from `HEAD` (byte-identical to the
  driver's copy), and every run was retaken from a branch-private directory.
  A `mutate.py` already in the scratchpad root (lane 1's, by its `M1.*` logs)
  was overwritten by this lane's driver before the move.
- **Ruling** `VL-U` (next unused `VL-V`). **Deferred to lane 3** as planned:
  the demo, divergences 145–147 and 84's amendment, migration note, inventory
  row text and census, `Backends/SDL` and the Linux image.

## §5 Lane 2 review fixes (2026-10-08)

Commit `5f342c5` (tests only; `List.swift` unchanged — every finding was an
unpinned clause, not a defect). The reviewer's mutations V2, V8, V9, V11 and
V13 each read a green 2714 suite; four tests now pin them:

- **2.7d** `aMultiRowInsertionAboveTheViewportBuildsTheRowsOnScreenInThatFrame`
  (`VL-U` item 4(a), the window after a rebuild): 20 rows inserted above row 50
  on top at the estimate 50 — id 50 on screen at 0 and ids 50…53 built in the
  frame of the change, settled offset 3460.
- **2.11b** `aVariableListWhoseOriginChangesIsReWindowedOnTheNextFrame` and
  **2.11c** `aGrownViewportIsFilledByAVariableListOnTheNextFrameWithoutInput`:
  the variable twins of `aListWhoseOriginChangesIsReWindowedOnTheNextFrame` and
  `aGrownViewportIsFilledOnTheNextFrameWithoutInput` (`DD-F` item 3), every row
  measured so `D = 0` and only the staleness request can ask for the frame.
  2.11b arm 1: a 400pt in-content header removed at offset 2860 (next frame
  58…61, row 58 on top); arm 2: a 40pt header added at 2460 — only the fresh
  window's leading overscan row 47 is outside the built 48…56. 2.11c: 200 →
  560 viewport at 2460, the next frame builds 48…63.
- **2.7b arm 3**: the anchor and every id after it removed, ids 2000…2009
  appended — the last surviving id before it, id 49, on screen at 0 (`VL-O`
  item 1's backward search).
- **2.18's ∞ arm**: `estimatedRowHeight: .infinity` reads 4600 like nil.

Filtered native run of the 24 before the mutations: all passed (the tests
assert behaviour the code already had; their red is the mutations). Mutations
on `5f342c5`, `List.swift` restored from a copy after each, full unfiltered
native `--no-parallel` suite, `git status --short` clean after each (spellings
in `VL-U` item 7):

| # | Mutation | Reddened |
|---|---|---|
| V2 | `shift` dropped from the window's end | `aMultiRowInsertionAboveTheViewportBuildsTheRowsOnScreenInThatFrame` (`screenY[50] == 0`, `built ⊇ 50…53`; "2717 tests … failed … with 2 issues") |
| V11 | the variable staleness request dropped | `aVariableListWhoseOriginChangesIsReWindowedOnTheNextFrame` (both arms), `aGrownViewportIsFilledByAVariableListOnTheNextFrameWithoutInput` (9 issues) |
| V9 | the prepaint window's leading overscan dropped | `aVariableListWhoseOriginChangesIsReWindowedOnTheNextFrame` (arm 2 only; 3 issues) |
| V8 | no backward search (`var position = -1`) | `removingTheRowOnTopPutsTheNextRowInItsPlace` (arm 3, both frames; 2 issues) |
| V13 | `isFinite` dropped from `clampedEstimate` | `aNonPositiveEstimateIsTreatedAsUndeclared` — the ∞ arm **traps** (`LayoutTree.swift:856` "native layout produced a NaN measurement", `SA-J`), truncating the run with no summary line; counted as reddened because the unmutated suite finishes |

**Suite** on `5f342c5` after the last restore, native, unfiltered,
`--no-parallel`: **"Test run with 2717 tests in 3 suites passed after 159.708
seconds"** (2714 + 2.7d, 2.11b, 2.11c), `FR-J no-argument frame:
succeeded=true deprecations=2`, 0 `error:`, the only `warning:` SwiftPM's
deprecation notice; `swift build --build-tests` (default build system) 0
warnings. Guards unmoved (176). No source, image or `Backends/SDL` change, so
pixels and the Linux image are not re-taken.

## §6 Lane 3 — demo, documents, platforms (2026-10-08)

Commits `2e2656a` (red: 3.2 and the 3.1 arm, the demo stubbed without its
`ScrollView`) and `50b271a` (the demo and both entry points); this section,
`VL-V` and the documents in the docs commit after. Spec §5 lane 3 and `VL-K`,
amended by `VL-V`.

- **Landed.** `Sources/MetalUIDemoContent/VariableListDemo.swift`:
  `variableListDemoContent()` (public, doc comment, census row), a `Column`
  around the `VariableListDemo` `Component` (selection `@State` as a
  `Set<Int>`), a layout-transparent `ScrollViewReader` over
  `variableListDemoHeader(selected:jump:)` ("Jump to row 250" →
  `proxy.scrollTo(250, anchor: .top)`, "Selected: n") and
  `variableListDemoList(selection:)` — a greedy `ScrollView` holding
  `List(_:selection:rowContent:)` over 300 rows, `Text("Row i — …")` in three
  lengths with `.padding(6)`, no declared estimate. `METALUI_LIST_DEMO=1`
  opens it in `MetalUIDemo` (920 × 560) and in `MetalUISDLDemo`.
- **Red-before** (stub at `2e2656a`, filtered native run of 3.2: "Test run with
  1 test in 0 suites failed after 0.506 seconds with 3 issues"):
  `VariableListDemoTests.swift:52` `opening == 2` (1: an unbounded list settles
  in one frame); `:55` `atRest.count < variableListDemoItems.count` (300 of
  300 built); `:57` `try #require(window.lastScrollRegions.first)` (no
  scroller). The 3.1 arm passed against the stub (it builds whatever the demo
  is; its instrument is M3.1). The first spelling counted rows from the
  published tree and read 0 under the stub — AB-X publishes no rows from an
  unbounded window — so the count moved to element bounds before the red
  commit (`VL-V` item 3).
- **3.2's literals as derived and as read**: opening 2, after the 4000pt scroll
  1, stored offset exactly `before + 4000` (`VL-V` item 4).
- **Mutations** on `50b271a`, the file restored from a copy after each, full
  unfiltered native `--no-parallel` suite, `git status --short` clean of
  `Sources`/`Tests` after each:

| # | Mutation | Reddened |
|---|---|---|
| M3.2 | `ScrollView { … }` → `Box { … }` in `variableListDemoList(selection:)` | `theVariableListDemoSettlesHeadless` (`:52` `opening == 2`, `:55` the built-row count 300, `:57` no scroller; "2718 tests in 3 suites failed after 163.381 seconds with 3 issues") |
| M3.1 | `everyProductionTreeBuildsOnAOneMegabyteThread` at `64 * 1024` | `everyProductionTreeBuildsOnAOneMegabyteThread` (`.signal(SIGBUS)`; "2718 tests … failed after 162.755 seconds with 1 issue") |

  M3.1 is the spelling `VL-R` item 3 asked for, but the whole harness already
  fails at 256 KiB (the separating control), so it says nothing about the arm.
  **A separating measurement of the arm alone** (filtered, not a mutation
  claim): `buildEveryProductionTree()`'s body replaced by
  `buildTheVariableListDemo()` alone — `.signal(SIGBUS)` at 16 and 64 KiB,
  passes at 128, 256 and 512 KiB; replaced by `_ = 0` — passes at 16 and 64
  KiB. So the arm's own frames need between 64 and 128 KiB on macOS arm64
  debug, and the harness at 64 KiB sees them. (A first attempt that put
  `return` ahead of the existing body SIGBUSed at 256 KiB even "empty": a
  debug build reserves the frame for every temporary in the function at
  entry, whatever returns early — `buildTheServicesDemo()`'s note.)
- **Suite** at `50b271a` after the last restore, native, unfiltered,
  `--no-parallel`: **"Test run with 2718 tests in 3 suites passed after
  161.106 seconds"** (2717 + 3.2; the 3.1 arm is inside an existing test), `FR-J
  no-argument frame: succeeded=true deprecations=2`, 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift build --build-tests`
  (default build system) 0 warnings. No guard added (176, §4).
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 70ed000 HEAD` at
  `50b271a` — controls as recorded (light vs dark 1048576, default vs modal
  1031003, f0 vs f3 0, chrome legacy vs proposal 0, indicator rects 0), and
  **all fourteen images `differing=0`, scene identical**.
  `Tests/MetalUICrossPlatformTests/Expected.swift` unedited against `70ed000`
  (and the three `PortableTests` ones).
- **`Backends/SDL`** (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)` from `Backends/SDL`, macOS): **24 + 83** passed (as at
  `70ed000`, record §80 §5). **Linux image** (`docker build -t
  metalui-portable …`, then the `docker run … swift build --build-tests &&
  swift test --skip-build` of spec §7, volume
  `metalui-sdl-build-variable-height-list`): **24 + 80** passed (as record §80
  §5).
- **Imports**: `MetalUILayout` imports only `MetalUICore`, `MetalUIScene`
  only `MetalUIShaderTypes`; no diff under either against `70ed000`.
- **Documents**: `docs/divergences.md` rows 145, 146, 147 and 84 amended (the
  header's count and next label left for the merge: 108 live on this branch);
  `docs/migration.md` (the `List` row in Part 1, and the behaviour-change row
  for `VL-A`/`VL-I`: a content-sized list's `style.size.height` is `.auto`);
  `docs/api-overview.md` (`List` in the legacy layout and controls
  paragraphs); `docs/verification/human-checks.md` group VL (VL1–VL5,
  provisional letter); `closeout-inventory-map.tsv`'s `F list` row (145–147,
  `VL-A`, `VL-I`, content-sized rows); the census re-recorded **2536 → 2540**
  (the three `rowContent:` initialisers and `variableListDemoContent`); both
  inventory scripts print nothing.
- **Not taken**: the real-window capture and launching the demo (no lock
  probe run; nothing here needs a presented frame); the env-gated 100k pair
  (lane 3 changes no `List` code; lane 2's readings stand).

## §7 Record phase (2026-10-08)

`CLAUDE.md` (byte-identical `AGENTS.md`): the `VL-` prefix and its document
(next `VL-W`), one rule under **`List`** (content-sized rows, the index, the
anchor, the untouched fast path), `METALUI_LIST_DEMO=1` in the build block,
human-check groups "A–X and VL", and the counts sentence **2718 / 0 / 176**
(census 2540, `Backends/SDL` 24 + 83 / Linux image 24 + 80, record §6).
`docs/record/README.md` row 82; record §03 "2026-10-08: variable-height `List`
— looks owed" (VL1–VL5); record §04 "145–147 added, 84 amended; 108 live on the
branch". The published divergences header (105 live, next label 139) and
`CLAUDE.md`'s copy of it are left for the merge with `feat/input-apis` and
`feat/rich-text`.
