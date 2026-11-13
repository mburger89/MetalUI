# 272. Keyed decoration owners and real-row gutter markers (Alloy gap G35 PR D, `CV-AO`, `CV-AP`)

Branch `feat/codeview-decoration-owners` (master `b7df7e6a`). Decisions `CV-AO` and `CV-AP` in `docs/superpowers/2026-11-07-code-view-decisions.md` (next unused `CV-AT`; `CV-AJ`..`CV-AN` belong to PRs A and C in parallel). Class `M`; no divergence added or retired (220 live, next label 241). Alloy's answers 3 and 4 (reserved lane so text never shifts, markers clickable with row and owner, a diff's removed lines before a diagnostic at one gap, highest priority wins, no blending) are binding and are what the rulings implement.

## 1. API

`CodeDecorationOwner(_:priority:)` and `.default`; `setLineDecorations(_:asOf:owner:)`, `setVirtualRows(_:asOf:owner:)` (both default to `.default`, so every existing call compiles and behaves as before), `removeDecorations(of:)`; `CodeLineDecoration.gutterMarker` (a defaulted initialiser parameter before `tag`); `CodeGutterHit.owner` (output only, `nil` for the default owner) and `CodeGutterHit.Source.gutterMarker`; `CodeView.gutterMarkerLane(_:)`.

Deviations from the plan, and why: owners are keyed by **name** (the plan's `Hashable` struct would make the same name with another priority a second owner, and a re-set with a new priority could not change the rank); the lane is **two space advances** wide, a font constant; `CodeGutterHit.owner` is `nil` for the default owner, which the existing equality assertions (`CodeGutterHit(lines:tag:source:displayRow:)`) require; the lane is a strip at the gutter's left, the numbers and bar keep their places; the lane flag lives on `CodeDecorations` (`markersEverSet`, sticky), not on the view, so two views of one decorations object reserve it together and stay aligned.

## 2. Structure

- Lines: `lineTrees` (one `RunTree` per owner id, the default first) and `lines`, which is the one owner's tree itself while there is one, else the merge (`rebuildLines()`). The payload carries `owner`, `marker`, `markerTag`, `markerOwner`; owner ids index an append-only table so a payload stores two bytes. A sorted, disjoint set builds with `RunTree(tiling:)` (a Cartesian tree by one pass with a stack); anything else keeps the old one-`set`-each path, so overlapping decorations overwrite in the order given exactly as before.
- Virtual rows: `VirtualGroup` gains `owner` and `priority`; `CodeRowMap.build` is now the same stack construction (O(groups)); `allGroups()` lists groups with their gap positions. A set while no other owner has ever given rows builds in place; otherwise it builds on a scratch map, replays the deltas since `asOf`, merges with the other owners' groups read off the live map (two-pointer on (gap, priority, owner id)), and builds the live map once.
- Paint and hit-testing: the plan computes the lane in `makePlan` (never in measure), rows carry the marker layout (cached through `CodeLineCache.marker`, the gutter bucket), `gutterHit(at:)` answers the lane (or the number column with the lane off) with `.gutterMarker`.

## 3. Measured (debug, counters never clocks)

See the test list; the numbers are in section 4.

## 4. Tests

`Tests/MetalUITestingTests/CodeViewOwnersTests.swift`: `twoOwnersMergeByPriorityPerField`, `settingOneOwnerKeepsTheOthersShiftedRows`, `virtualGroupsOfTwoOwnersAtOneGapOrderByPriority`, `anEditCostsLogarithmicWorkPerOwner`, `setCostIsLinearInGroupsAndZeroPerFrame`, `aRealRowMarkerReplacesTheNumberOrSitsInTheLane`, `removeDecorationsClearsOnlyThatOwner`, `aMarkerClickReportsRowAndOwner`, `mergedLineDecorationsMatchAnArrayModelUnderRandomSetsAndEdits`; `Tests/MetalUITests/CodeRowMapTests.swift`: `theGroupsOfSeveralOwnersListInOrderWithTheirPositionsUnderRandomSplices`. Each was proven to fail under the mutation named in its doc comment (section 5).
