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
