# 389: Table PR B, the API and rendering (`TBL-A`..`TBL-G`, `TBL-J`, `TBL-K`, `TBL-L`, `TBL-V`)

Class `A` (SwiftUI's `Table`) plus the MetalUI-only `tableRowHeight`, `tableFrozenColumns` and `tableRowIndex` (class `M`); divergences 1105 and 1110 used, 1106 and 1108 unused. Branch `feat/table-b`, base master `260d9614` (PR A, record 388, merged). Spec `docs/superpowers/specs/2026-11-18-table-design.md`, plan `docs/superpowers/plans/2026-11-18-table.md`, decisions `docs/superpowers/2026-11-18-table-decisions.md`, probe `docs/probes/swiftui-table.swift` (read in its header, raw output in `swiftui-table.recorded.txt`).

## Change

- **The probe** (task B0) ran on macOS 27.2.1 and decided the open arms: the default width 100 and minimum 10, the fill pass kept (no shrink: label 1106 unused), a cell inset of 6, a 28-point header, alternating rows, a table in a vertical `ScrollView` is the proposed width by 0, Home and End scroll only, SwiftUI type-selects (1109 used, record 390), headers do not reorder by default (record 391), a resize makes the last column give way (1111 used, record 391), a right-to-left environment mirrors SwiftUI's columns, and MetalUI's do too (the engine mirrors a custom layout's placements and the scroller's offsets are logical), so 1108 stays unused, and a header click's sort rule (record 390's literal). `TableMetrics.defaultMinWidth` is 10.
- **Types** (`TableColumnContent.swift`, `TableColumn.swift`): `TableColumnContent`, `TableRowContent`, `TableForEachContent`, `TableColumnBuilder` (a statement owns one structural slot, so a column keeps its key across an `if`), `TableColumnGroup`, `TableColumnForEach` (re-read every build, keyed by its element's id), `TableColumn` with every title spelling and the `Never`, `KeyPathComparator`, `value:` and `sortUsing:` forms, `.width`, `.alignment` and `TableColumnAlignment`. `ElementID.forColumn` names a cell by its column key.
- **The table** (`Table.swift`, `TableBody.swift`, `TableRows.swift`): `Table` is an element over a `ProposalScrollView([.horizontal, .vertical])` around an internal `TableBody`; the body reads `count` once and `data[i]` once per realised row (by position), resolves the columns, solves the widths, plans the window (`TableWindowPlanner`) and builds only the window's rows, cells and header; the header and the frozen cells are placed from the table's clamped offset. A cell is a `TableCellBox` (an element, never a `Box`), a row a `TableRowElement`, the header a `TableHeaderRow` of `TableHeaderCell`s with a `TableColumnDivider` each (drawn only; the drag is record 391). `tableColumnHeaders(_:)` is an environment value.
- **The demo** (`METALUI_TABLE_DEMO=1`): 1 000 000 x 200 synthetic rows, the "#" column frozen, three sortable columns, a `Set` selection, a context menu and `tableRowIndex`; its selection, sort and menu act when record 390 lands.

## Measured (macOS, debug build, the harness text system)

At the steady offsets (600, 12000) of an 800 x 600 table with 24-point rows and 100-point columns, every size gives the same frame: one build, 28 rows, 280 cells, 28 data reads, **621 element requests and 621 paints** (`B` = 2 and `P` = 2 for an empty table plus the window's 619). A vertical step (+24) and a horizontal step (+100) cost the same; an idle table draws no frame. `.equatable()` cell content replays translated on a scroll step: 270 hits and translations, 10 misses (the new row's cells). A settled table inside an `.equatable()` component replays whole (0 paints). 1 000 000 x 200: cold frame and settle 64 ms, 19 ms per scroll step, each step one build, 280 cells and 28 reads (`METALUI_RUN_1M_TABLE_TEST=1`).

## Tests

`TableColumnBuilderTests` (4), `TableCompileGuards` (1), `TableFoundationGuards` (1), `TableRenderTests` (17), `TableDataContractTests` (2), `TableFrameCostTests` (+10), `TableDemoTests` (1). Each test names its mutation in its doc comment; the round (every one restored, `git status` clean of source changes after):

| test | mutation | red |
|---|---|---|
| `foundationSortTypesAreAvailableOnEveryPlatform` | delete the `order = .reverse` write | itself |
| `theBuilderFlattensColumnsInDeclarationOrderWithStructuralKeys` | a slot gets a wrapper level (`slot + [i, 0]`) | itself, `aConditionalColumnKeepsItsSiblingsKeys`, `aForEachColumnIsKeyedByItsElementID` |
| `aConditionalColumnKeepsItsSiblingsKeys` | key a column by the count of columns produced so far | itself |
| `aForEachColumnIsKeyedByItsElementID, aDynamicColumnSetKeepsSurvivingCellsState` | key a `TableColumnForEach` column by its offset | both |
| `aNeverSortColumnLiftsIntoASortedTablesBuilder` | lift with `sortPrototype = AnyHashable(0)` | itself |
| `everyTableColumnSpellingCompiles` | delete the `Text` + `sortUsing:` initialiser | the target no longer compiles (`init(_:sortUsing:content:)` requires a `StringProtocol`) |
| `aTableLaysOutHeaderAndRowsAtTheProbesMetrics` | `TableMetrics.headerHeight` 0 | itself |
| `aScrolledTableRealisesOnlyTheWindowOnBothAxes` | every column realised (`f..<columns.count`) | itself |
| `theHeaderStaysAtTheTopAndScrollsAcross` | the header placed at content y 0 | itself |
| `anOverscrolledWheelKeepsTheHeaderPinnedInTheSameFrame` | the header placed from the scroller's raw offset | itself |
| `aFrozenColumnStaysAtTheLeadingEdge, aFrozenColumnTablesWindowCostsTheSameAsAPlainOne` | the frozen width ignored in the scrolling band | both |
| `aFrozenCellPaintsAboveTheScrolledCellUnderIt` | cells painted in reverse (frozen first) | itself |
| `aLongCellTextTruncatesWithAnEllipsis` | the `lineLimit` environment push dropped (first run: the test passed, a 24-point row's proposed height cuts the text to one line by itself; the test now uses a 40-point row) | itself |
| `aTrailingAlignedColumnRightAlignsItsCells` | the alignment ignored | itself |
| `aTableNarrowerThanItsViewportFillsTheRow` | the solver's fill pass skipped | itself |
| `tableColumnHeadersHiddenRemovesTheHeader` | the environment value ignored (first run did not compile: a bad edit) | itself |
| `aTableAtANilProposalAnswersTheProbesSize` | the frame layout answers the content's height at a nil proposal | itself |
| `aColdFirstFrameRealisesTheColdSliceThenTheWindow` | a cold slice of 64 rows (not every row: a million rows) | itself |
| `aCellsStateSurvivesAHorizontalExcursion` | `noteWindowedParent` skipped in the row | itself |
| `aScrolledTableMintsNoStateEntriesForItsCells` | each cell's content wrapped in a `Box` | itself |
| `aTableReadsEachRealisedRowOnceAndTheCountOncePerBuild, aScrollStepReadsOnlyTheNewWindow` | `data[i]` read twice per row | both |
| `aTablesSteadyFrameCostsItsWindow` | a second divider request per header cell | itself |
| `anIdleTableDrawsNothing` | `requestAnotherFrame()` unconditionally in the body's prepaint | itself (`notIdle`) |
| `aScrollStepCostsOneBuildAndTheSteadyRequests` | the header row requested twice | itself |
| `aHorizontalScrollStepCostsTheSame` | `columnOverscan = 2` | itself |
| `equatableCellsReplayTranslatedOnAScrollStep` | rows named by their position in the window | itself |
| `aSettledTableInsideAnEquatableComponentReplays` | `TableViewState.sameEntry` always false | itself |
| `aTablesWorkIsTheSameFor10kBy50AsFor1kBy20` | a header cell for every column (an eager header) | itself |
| `aCellTallerThanItsRowIsClippedToIt` | the overflow test always false (never clip) | itself |
| `aRightToLeftTableMirrorsItsColumnsAndWindowsThemOnTheScroll` | the row layout mirrors its cells a second time | itself |

Not mutated: `anEmptyTablesSteadyCostIsTheBase` (the base), `theTableDemoBuildsAndScrollsInOneBuildPerStep` (its pin is the build count, the same one `aScrollStepCostsOneBuildAndTheSteadyRequests` mutates) and `aTablesWorkIsTheSameFor1MBy200AsFor1kBy20` (opt-in; its equality is `aTablesWorkIsTheSameFor10kBy50AsFor1kBy20`'s).

## Deviations from the plan

- **A cell content is any `ElementGroup`, not an `Element`** (`@ElementBuilder`), wrapped in `LegacyContent` by the cell box: the plan's `.equatable()` cell (an `EquatableComponent`, an `ElementGroup`) could not otherwise be a column's content. Divergence 1110 names it.
- **A cell is clipped only when its content overflows it** (the plan clips every cell): a clip on the pass's stack is in the replay key and moved with every scroll step, so `equatableCellsReplayTranslatedOnAScrollStep` measured 0 translated; unclipped it is the plan's 270. `aCellTallerThanItsRowIsClippedToIt` pins the overflow clip. `TBL-K` amended.
- **The frozen-column cost is the steady window's** (10 columns: one frozen and nine scrolling, 280 cells, `B + 619`), not spec 4.4's `B + 678`, which counted the frozen column on top of the unshifted 5..<15 window; the planner (PR A) takes the frozen width out of the band, so spec 4.4's 678 is that arm's mutation (`aFrozenColumnTablesWindowCostsTheSameAsAPlainOne`). B4's `28 x 9 = 252` was frozen 2's arithmetic; frozen 1 is 28 x 10.
- **A table's element bounds are in content space**, so the pin tests subtract the scroll offset (`theHeaderStaysAtTheTopAndScrollsAcross`, `aFrozenColumnStaysAtTheLeadingEdge`) where the plan read window space.
- **`MetalUITestingTests` gains `MetalUIDemoContent`** (Package.swift) for the demo test; the demo's tree is built by `everyProductionTreeBuildsOnAOneMegabyteThread`.
- **The selection and sort bindings are accepted but not acted on**: the six initialisers are all here (task B4); the selection binding is held (`Table.selection`), the sort binding is dropped, and their input is record 390 (C1 to C4).
- The probe's `F1` arm could measure only an append (removal aborts SwiftUI); `K3`'s Page keys did not move under a synthetic event.
