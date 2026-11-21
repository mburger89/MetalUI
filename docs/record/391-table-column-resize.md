# 391: Table PR D, column resize; reorder not built (`TBL-R`, `TBL-S`, `TBL-AA`)

Class `A` (SwiftUI's `Table`), **divergence 1111** (where a resize's width comes from when the columns fill the viewport), no public API. Branch `feat/table-d`, base master `44d3d685` (PRs A, B, C and F merged). Decisions `docs/superpowers/2026-11-18-table-decisions.md` (`TBL-R` and `TBL-S` flip, `TBL-AA` is new, next `TBL-AB`); plan `docs/superpowers/plans/2026-11-18-table.md`, "PR D" (D1 built, D2 not built, D3 here).

## Change

- **Resize** (`TableColumnDrag.swift`, `TableBody.swift`). A resizable column's divider (a non-fixed `.width`) takes the `.columnResize` pointer and a `DragGesture(minimumDistance: 0)` over its 6 points. `TableResizeDrag` takes the column's resolved width in the build that made its handler as the start, and writes `columnState.widths[key] = clamp(start + translation)` to the table's `@State` binding only when that differs from the last value written. The start, the key and the last value are a `TableResizeDragBox` the state holds by reference (its `==` ignores it), so keeping them writes nothing; `onEnded` and `onCancelled` clear it. A fixed-width column's divider draws its line and has no handler. No `withState` site was added (`everyStateWriteSiteIsClassified` is unchanged): the write is a `@State` binding write, from input only.
- **The divider registers after the header's cells** (`TBL-AA`). Its far half lies over the next header cell, whose click sorts; registration order is hit rank, so `TableHeaderRow.prepaint` registers every divider after all its cells (`TableColumnDivider.registerResize`), and skips a scrolled column's divider that lies under the frozen header cells. A press on either half resizes and sorts nothing.
- **Reorder is not built, by the plan's "Branch for R1".** `TBL-S` records probe `R1` (`allowsColumnReordering` is false without a column customisation), so no gesture is attached, `headersDoNotReorderByDefault` replaces the five reorder tests, and there is no MetalUI switch in v1. `TableColumnState.order` and the display-order code stay (read every build, written by nothing) for a later customisation PR. **So the plan's two cell-mode tests for reorder (the active cell and editor following the declared column, ← → and Tab in display order under a reorder) are not written: no order can be produced.** What is built carries over: `TCM-C`'s declared-to-display map is built from `columnState.order` and unchanged, and a resize while an edit is open is tested.
- **Divergence 1111** (probe `R2`): SwiftUI takes a +40 drag from the LAST column when the columns fill the viewport (206, 206, 100, 205 became 206, 246, 100, 165). MetalUI's rule is `TBL-G`'s fill: the dragged column stops being flexible and the other flexible columns share the surplus, each giving back a part (`aResizeInAFilledTableSharesTheChangeAmongTheOtherColumns`: four columns of 200 give 240, 187, 186, 187 on a +40 drag). When the columns are wider than the viewport there is no surplus and nothing gives way, as in SwiftUI. Divergences: 234 live (233 before; CLAUDE.md and `docs/divergences.md`'s header agree); next label 243 unchanged (1111 is from the TBL reservation).
- Docs: the decisions doc, `docs/divergences.md`, `docs/rules/divergence-labels.md`, `decision-prefixes.md`, `input-focus.md`, `docs/api-overview.md`, the inventory map's `table-columns` family text (no new public declaration, so no new row; both closeout probes print nothing), `docs/verification/human-checks.md` (group TBL, row TBL4; the group is created here, the other TBL rows arrive with their records).

## Deviations from the plan

1. **Reorder (D2) is not built** (above); `TableReorderDrag`, `TableReorder.target` and the five reorder tests are not written.
2. **`TableResizeDrag` carries the width, the spec and the binding** rather than the plan's `{ key, startWidth }`: the start is chosen when the first drag event arrives (a closure built each frame cannot hold it), so the held reference is `TableResizeDragBox`, inside `TableColumnState`.
3. **The divider's hit area registers from the header row, not from the cell** (`TBL-AA`): the plan did not foresee the next header's click covering the divider's far half.
4. **`aResizedWidthSurvivesARebuildAndAColumnSetChange`** adds a column in FRONT (a keyed `TableColumnForEach`), since an appended one would pass under a position key too.
5. The cell-mode fixture `cellTableValue` gained `resizable:` (default false: its columns stay fixed 100).
6. **Both the handler and the solver clamp a width.** Either alone holds the visible width; the handler's is what stops a limit-bound drag writing a new value per event, and the solver's is a guard for an override that did not come from the handler.

## Measured (macOS, debug build, the harness text system)

- A resize step of +5 on `F` (1000 rows by 200 columns): 1 build, the steady element requests, 200 columns resolved, the steady cell count.
- A press, three moves in place and a release: 0 builds for the moves; moves past a limit with the pointer still on the divider: 0 builds.
- An unfocused table with a resized column beside a redrawing sibling, behind an `.equatable()` boundary: 0 rows and 0 cells realised, no ineligible reason.

## Tests

`TableColumnResizeTests` (13). Each names its mutation; each was run red against the committed code and restored (sources byte-identical afterwards). "Red" lists the tests that failed under it.

| mutation | red |
|---|---|
| M1 no clamp in the handler | `aResizeDragPastALimitDrawsNothingMore` only (the solver still clamps the shown width) |
| M1c no clamp in the handler or the solver | `draggingADividerResizesItsColumnWithinItsLimits`, `aResizeDragPastALimitDrawsNothingMore` |
| M2 the start width + 10 | seven tests, among them `draggingADividerResizesItsColumnWithinItsLimits`, `resizingAColumnMovesOnlyTheColumnsAfterIt` |
| M3 a fixed column gets a divider | `aFixedWidthColumnHasNoDivider` |
| M4 no pointer attachment | `theDividerShowsTheColumnResizePointer`, `aFixedWidthColumnHasNoDivider` |
| M5 `columnsResolved` counted twice per build | `aResizeDragStepCostsOneBuildAndTheSteadyRequests` |
| M6 write unconditionally (the `clamped != drag.last` guard dropped) | `aResizeDragThatDoesNotMoveDrawsNothing`, `aResizeDragPastALimitDrawsNothingMore` |
| M8 widths keyed by display position | `aResizedWidthSurvivesARebuildAndAColumnSetChange` |
| M9 the divider registered inside its cell, not after them | `aDragOnTheDividersFarHalfResizesAndDoesNotSort`, `theDividerShowsTheColumnResizePointer` and eight more |
| M10 the first two display columns swapped (what a reorder would leave) | `headersDoNotReorderByDefault` and nine more |
| M11 a plain `$columnState.wrappedValue = columnState` in `Table.requestProposalLayout` | `aResizedTableBesideARedrawingSiblingReplays` and eleven more |
| M12 the editor's frame not refreshed once it has one | `resizingWhileAnEditIsOpenKeepsTheEditorOverItsCell` |
| M13 an overridden column stays flexible in the solver | `aResizeInAFilledTableSharesTheChangeAmongTheOtherColumns` |

A first mutation for the cost test, `requestAnotherFrame()` in the header's prepaint, crashed the run (`fatalError`: the window never went idle) and was replaced by M5. Two plan assertions changed: `aResizeDragThatDoesNotMoveDrawsNothing` counts the moves between the press and the release (the press and the release are the gesture's own frames, record 386), and the past-limit case holds the pointer on the divider (leaving it is a hover frame).

## Counts

Root run, `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`: **7220 tests in 79 suites, green** (7207 at record 394, plus this record's 13). `swift build -c release` green. `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. The SDL package was not re-run (`windowServerTrafficNeverStopsTheMainRunLoop` fails on master). Off Darwin the tests use `runUntilIdle()`, sum `frameWork` and `Modifiers.primary` where a modifier is needed; CI results are in the pull request.
