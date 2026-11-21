# 392: Table PR E, accessibility on AppKit and AccessKit (`TBL-T`, `TBL-AB`)

Class `M` (the platform tree's additions; SwiftUI's own table is an `AXOutline`), **divergence 1107**, amends divergence 32. Branch `feat/table-e`, base master `a714225e` (PRs A, B, C, D and F merged). Decisions `docs/superpowers/2026-11-18-table-decisions.md` (`TBL-T` built, `TBL-AB` is new, next `TBL-AC`); spec `docs/superpowers/specs/2026-11-18-table-design.md` section 7 and `specs/2026-11-20-table-cell-mode-design.md` section 8; plan `docs/superpowers/plans/2026-11-18-table.md`, "PR E" (E1 to E5).

## Change

- **The platform tree** (`MetalUIPlatform/AccessibilityTree.swift`, public). `AccessibilityRole.columnHeader`, `public enum AccessibilitySortDirection { ascending, descending }` and four optional `AccessibilityNode` fields, `columnCount`, `columnIndex`, `headerRowCount`, `sortDirection` (initialiser parameters defaulted to `nil`). They are stored properties of an `Equatable` struct, so `hasSameStructure` compares them. A `.table` with a non-nil `columnCount` is a data table. Migration entry in `docs/migration.md`; four class `M` inventory rules and one family (`table-accessibility`) in the map; every declaration has a doc comment (both closeout probes print nothing).
- **The builder side is not on `AXNode`** (deviation 1). `AXEmission` gains an optional `AXTableInfo` (`.table`, `.headerRow`, `.cell`, `.columnHeader`) that `Frame.recordAccessibility(…table:)` writes, so `AXNode` (121) and `Handlers` (480) keep their pinned sizes and nothing changes for a table with no client. `AccessibilityTreeBuilder` maps it: the table node's `columnCount` and `headerRowCount`, a cell's `rowIndex` and `columnIndex`, a header cell's `.columnHeader` role, column and direction, the header row as a `.row` with no index (never `isSelectable`), the active cell `isSelected`, and the ordering and focus rules below.
- **`TableBody` and friends** record only `if collectsAccessibility`: the table node at the body's id over the VIEWPORT (the body's own bounds are the whole content), after the body's handlers; `logicalIndex` on EVERY realised row (it was only a clickable row's); each body cell as its own `.cell` node recorded BEFORE its content (so the content's elements and identifiers are its children; the cell-mode click is still registered with `synthesizesAccessibility: false`); the header row and each header cell (the click registers without synthesizing a button, the cell is a `.columnHeader` that folds its title like a button folds its label, and the sort chevron is `accessibilityHidden` so the label is the title alone).
- **Order.** Records come in prepaint order: frozen cells after the scrolled ones, the header after every row. The builder puts the header row first among a table's children and sorts a row's (and the header's) cells by column. Columns are DISPLAY positions.
- **Cell mode** (spec section 8). The active cell is `isSelected`, and a focus on the table body is published as the focus of its active cell (`activeCells`, built as the nodes are emitted); an open edit's editor prepaints inside `withAccessibilityAdopter(<the cell>)`, so the text field is that cell's child (a `TableEditAnchor` the cell fills in when it prepaints; the editor prepaints after the rows). Neither needs a node that is not already published: with the editing cell scrolled out of the window the editor falls back to being a child of the table.
- **AppKit** (`AppKitAccessibility.swift`). A node with a `columnCount` is `AXTable` (a `List` stays `AXOutline`), its rows `AXRow`/`AXTableRow` (the header row is not among `AXRows`, `AXSelectedRows` or `AXIndex`), `AXRowCount` and `AXColumnCount` its logical counts, `AXHeader` the header row's `AXGroup` (only when `headerRowCount` is above 0), `AXColumnHeaderUIElements` the header's cells in column order; a `.cell` answers `AXRowIndexRange` and `AXColumnIndexRange`; `.columnHeader` is `AXButton` with subrole `AXSortButton` and `AXSortDirection`. No `AXColumn` elements (divergence 1107).
- **AccessKit** (`AccessKitTree.swift`, `AccessKitAdapter.swift`). `COLUMN_HEADER`; `column_count`, `column_index` and `sort_direction` set when present; `row_count` and every data row's and cell's `row_index` shifted by the table's `headerRowCount` (the header row is `row_index` 0), made in the translation, so the neutral tree's counts stay AppKit's.
- **Docs.** The decisions doc (`TBL-T` built, `TBL-AB`), divergence 1107 and the amendment to 32 in `docs/divergences.md` (235 live), `docs/rules/divergence-labels.md`, `decision-prefixes.md`, `input-focus.md`, `docs/api-overview.md`, `docs/migration.md`, the inventory map, `docs/verification/human-checks.md` (the TBL group PR D created is extended: TBL1 to TBL3, TBL5 and TBL6 added around its TBL4) and `docs/verification/voiceover-script.md` (section 5, no machine-checked markers).

## Ruling: `AXTable`, not SwiftUI's `AXOutline` (`TBL-AB`, divergence 1107)

Probe `A1` found SwiftUI's table is an `AXOutline` of `AXRow`/`AXOutlineRow`s with `AXRowCount` and `AXColumnCount` nil, `AXColumn` elements and an `AXHeader` view of `AXSortButton`s. The spec (7.4), the plan (E3) and human check TBL1 (VoiceOver announces "table, N rows, M columns") all want `AXTable` and counts, which an outline does not announce, so MetalUI keeps `AXTable` and records the difference as divergence 1107 together with the missing `AXColumn` elements. The `columnCount` field is the whole difference between a `Table` and a `List`, which stays an outline. **This is the one place the build chose against the probe; a human VoiceOver run (TBL1) can overturn it, and the change is one `case .table:` arm and the subrole.**

## Deviations from the plan

1. **The table fields are on `AXEmission`, not `AXNode`** (above): the plan's internal `AXNode` fields and `AXRoleHint` cases (`.dataTable`, `.tableRow`, `.tableCell`, `.columnHeader`) were not added; a table's fields are written only by the table, only while a client collects, and the size pins (`AXNode` 121, `Handlers` 480) did not move.
2. **No `AXRoleHint` and no `TableRows.swift` hint for the table node**: it is a direct `recordAccessibility` at the body's id (focus, the selection action and the press registry are already the body's), over the viewport.
3. **`aDataTableIsAnAXTableWithTableRows` reads a 1 000 000-row by 200-column table UNSCROLLED**, not at the steady offsets, so the cell's column range is `(0, 1)` and the header count the realised columns, not `(5, 1)` and 10. The steady-offset reads (498...525 and columns 5...14) are in the core tree test, `aTablePublishesItsLogicalCountsAndTheRealisedWindow`.
4. **Every realised row now publishes**, a plain table's included (the plan limited `logicalIndex` to a clickable row, record 394), because the row is the cells' parent and carries `AXIndex`.
5. **The sort chevron is hidden from a client** (its label "Go Down" would otherwise join the header's label); the types of the header's indicator gain `AccessibilityModifier<Image>`.
6. **The cell-mode focus is a published focus on the cell, not a focusable cell**: a client's `.focus` request on a cell is refused (the body is the focusable element), as a `List` row's content is.
7. **`headerRowCount` decides whether AppKit offers `AXHeader`**, so the field has an AppKit arm (the parity test `everyAccessibilityNodeFieldHasAnAppKitArm` names every field; its count went from 20 to 24 in both backends).

## Tests

New: `TableAccessibilityTests` (10, core tree), `TableAppKitAccessibilityTests` (4), `AccessibilityTableFieldsTests` (1, `MetalUIPlatformTests`) and the SDL package's `AccessKitTableTests` (5). `TableRowAccessibilityTests` pass unchanged. The two parity tests gained four arms each. Each new test was run red against the mutation below and restored (sources byte-identical afterwards, checked with `git diff`).

| mutation | red |
|---|---|
| M1 the table node's `logicalCount` is the realised row count | `aTablePublishesItsLogicalCountsAndTheRealisedWindow` |
| M2 a cell's column minus one | `aTablePublishesItsLogicalCountsAndTheRealisedWindow` |
| M3 the builder does not order a table's children | `aFrozenCellIsPublishedFirstInItsRow`, `theHeaderRowIsTheTablesFirstChild` |
| M4 every header cell reads ascending | `theHeaderRowIsTheTablesFirstChild` |
| M5 no suppression on a cold frame (`if false`) | `aColdFramePublishesTheTableAndNoRows` |
| M6 every `.table` gets a column count | `aListIsStillPublishedAsBefore` |
| M7 a `.cell` folds its content as a button does | `everyCellKeepsItsOwnElementAndIdentifierInEveryMode` |
| M8 no focus redirect to the active cell | `theActiveCellIsTheFocusedAndSelectedCell` |
| M9 the active cell not selected | `theActiveCellIsTheFocusedAndSelectedCell` |
| M10 every cell is recorded as the table's active cell | `theActiveCellIsTheFocusedAndSelectedCell`, `aRowTablesFocusStaysOnTheTable` (see the note below) |
| M11 the editor not adopted by its cell | `theOpenEditorIsATextFieldChildOfItsCell` |
| M12 `Frame.recordAccessibility` without its `collectsAccessibility` gate | `aTableWithNoAccessibilityClientRecordsNothingAndCostsTheSame` |
| M13 `AccessibilityNode.columnIndex` not stored by the initialiser | `theTableFieldsTakePartInStructure` |
| M14 a data table left an `AXOutline` | `aDataTableIsAnAXTableWithTableRows` |
| M15 the header row counted in `AXRows` | `aDataTableIsAnAXTableWithTableRows` |
| M16 a cell's column range is its row | `aDataTableIsAnAXTableWithTableRows` |
| M17 every `.table` is an `AXTable` | `aListIsStillAnAXOutline` |
| M18 the table body is the published focus | `aCellModesActiveCellIsAXFocusedAndAXSelected` |
| M19 the editor not adopted by its cell | `theOpenEditorIsAnAXTextFieldInsideItsCell` |
| M20 AccessKit: no header shift | `aTableMapsToAccessKitTableWithHeaderRowCounted` |
| M21 AccessKit: always add one to `row_count` | `aTableWithNoHeaderRowCountsOnlyItsData` |
| M22 AccessKit: every table's rows shifted | `aListsRowIndicesAreNotShifted` |
| M23 AccessKit: the cell's `selected` dropped | `theActiveCellIsAccessKitsFocusAndSelected` |
| M24 AccessKit: a cell's children dropped | `theOpenEditorIsATextInputInsideItsCell` |

Not every test of the five `TBL-T` plan rows has a mutation of its own here: `aTableWithNoHeaderRowCountsOnlyItsData`, `aListsRowIndicesAreNotShifted` and `aTableMapsToAccessKitTableWithHeaderRowCounted` are the three AccessKit pins and each has the one above.

## Measured (macOS, debug build, the harness text system)

- A table with no accessibility client: 0 emissions and the steady frame of record 389 unchanged (621 requests, 621 paints, 280 cells, 28 data reads, 1 build); the same table with a client collecting costs the same on every one of those (records are not element requests). The existing `TableFrameCostTests` and the sibling-redraw replay tests in `TableRetainedTests` run with the harness's client ON by default and still pass, so a collecting client does not move retained replay either.
- At the steady offsets of a 1 000 000 x 200 table a client reads 28 rows, each with 10 cells, and a header row of 10 cells: about 310 nodes.

## Counts

Root, `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`: **7235 tests in 79 suites, green** (7220 at record 391, plus 15: `TableAccessibilityTests` 10, `TableAppKitAccessibilityTests` 4, `AccessibilityTableFieldsTests` 1). `swift build -c release` green. `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

SDL package (`cd Backends/SDL && swift test` with the flags `python3 scripts/fetch-accesskit.py --print-flags` prints, as the Linux job's image has by default; the `AccessKit` trait is on in that package's manifest): 441 tests (401 in 20 suites and 40 in the replay run). The five new `AccessKitTableTests` and every `AccessKit*` test pass. Two failures, neither this record's: `windowServerTrafficNeverStopsTheMainRunLoop` (fails on master, and ends the run early when it is not skipped), and `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens`, which could not write into the Xcode toolchain's `pm` directory in the sandbox this record was made in (`NSCocoaErrorDomain` 513). Off Darwin the new tests use `runUntilIdle()`, sum `frameWork` and need no modifier; CI results are in the pull request.
