# 394: Table PR F, cell mode (`TCM-A`..`TCM-K`)

Class `M` (MetalUI-only: SwiftUI's `Table` has no cell cursor, cell keys or inline editor), no divergence label. Branch `feat/table-f`, base master `e606f013` (PR C, record 390, merged). The spec and the decisions document are one file, `docs/superpowers/specs/2026-11-20-table-cell-mode-design.md` (rulings `TCM-A`..`TCM-K`, next `TCM-L`; its "As built" section lists the deviations). Requesters: Alloy (a CSV table editor) and Sift (edit mode and keyboard browsing of a result grid). Records 391 and 392 are reserved for Table PRs D and E and 393 is SecureField, so this is 394.

## Change

- **The API** (`TableCellMode.swift`, class `M`, inventory family `table-cell-mode`): `TableCell<RowID>` (a row id and a column's declared index), `Table.tableActiveCell(_:)` (turns cell mode on), `tableCellEditing(_:text:isEditable:onCommit:)` and `tableCellBackground(_:)`. The last two do nothing without the first. A table without `tableActiveCell` is PRs B to E: the same element requests, paints, rectangles and data reads (`aTableWithoutCellModeIsUnchanged`).
- **The active cell** (`TCM-D`): the caller's binding, written once per move and never for a move to the same cell. A cell click makes itself active, then runs the row's click (selection, ⇧ and `Modifiers.primary`, the menu's double click) or, for a table that does not select, focuses the table. In cell mode each realised cell registers its own click above its row's hitbox. The ring is four fills inside the cell box (2 points accent when the table or its editor is focused, 1 point `Color.secondary` when not), painted after the content; the fill is painted after the row's stripe or selection and before the content; a selected row is `Color.secondary` at 0.25, never the accent. The ring and the fill are keyed to (row id, declared column) because they are decided while the cell is built.
- **Keys** (`TCM-E`, `TableCellContext.keyHandler`): cell keys run before PR C's row keys and decline to them. ← → (consumed at the edges), ↑ ↓ (the table's row move when it selects, so ⇧ extends and the lead follows; else a position step), Tab and ⇧Tab (wrapping, consumed at the ends), Return (an edit, else PR C's Return), ⇧Return up, F2, Home, End, `primary` with the arrows, Page Up and Page Down (the active cell by a page), a printable key (an edit with the text replaced). Every move enqueues a `TableCellReveal` request the body resolves in prepaint: the row plus the header over the column's own band, widened by the frozen columns it must clear. A caller's `scrollTo(TableCell)` resolves in the same place (`TCM-J`), the row by `tableRowIndex` or one scan.
- **The editor** (`TCM-F`, `TCM-G`): one `TextField(axis: .vertical)` with `lineLimit(1...6)`, named `$tableEditor` under the table body, so its identity is the body's and cell recycling never reaches it; it is placed by position (x the column's offset, y the row's, width the larger of the column and 120) after the rows and before the header, and takes focus from inside the frame (`Frame.seatFocus`, new, internal), with its caret at the end of its text. Its keys are an `onKeyPress` on the field (Return, ⇧Return, Tab, ⇧Tab, Escape; ⌥Return stays the field's line break). The edit is a `TableEditSession` (a class in `TableViewState.edit`) whose `isOpen` flips before any callback, so it ends in exactly one `onCommit` or one cancel. The row is found by the session's position verified with one read per build, then `tableRowIndex`, then one scan; unresolved, the editor holds its last frame.
- **`editing` and the after-frame notes** (`TCM-H`): the body notes three lifecycle entries on its own id, so they run after the frame as inputs: an `onChange` of the `editing` binding (a caller's `nil` cancels, another cell cancels the old edit and begins a new one), an `onChange` of whether the editor holds focus (true to false commits) and, only while an edit is open, an `onDisappear` (the table leaving the hierarchy or its window closing commits). A click on another cell commits first, then moves; a click in the empty space commits through a viewport-sized region registered only while an edit is open.
- **State** (`TableViewState`): `edit`, `editRevision` and `refocus`. A begin and an end are real writes (`StateTable.write`), so they draw a frame; an end that the editor held focus for asks the next prepaint to give the table its focus back. Nothing else is written differently.
- **The demo** (`METALUI_TABLE_DEMO=1`): a "Cell mode" switch above the table, off by default (so the demo and `theTableDemoBuildsAndScrollsInOneBuildPerStep` are unchanged), swaps in an editable 2 000 x 8 sheet with the "#" column frozen and not editable, edited cells tinted, and a log line naming each commit.
- Docs: `docs/rules/input-focus.md`, `docs/rules/decision-prefixes.md` (`TCM-`, next `TCM-L`), `docs/api-overview.md`, the inventory map (family `table-cell-mode`, class M), `docs/verification/human-checks.md` (group TCM, not run), the spec's "As built".

## Measured (macOS, debug build, the harness text system)

- A key move writes the binding once and builds the window once (28 rows by 6 columns here, `builds x` the steady window, no more). A `primary`+↓ on 1 000 000 rows reads at most 4 rows during the input and the new window in the frames after it.
- An open edit costs one more data read per build (the position's verification) and a handful of element requests for the editor (pinned at most 8). A keystroke rebuilds the window and the editor and nothing else; an idle editor and an idle cell-mode table ask no frames and call no closure (`fill`, `text`, `isEditable`).
- `scrollTo(TableCell(row: 900_000, column: 150))` on 1 000 000 rows by 200 columns with `tableRowIndex` reads the window only and the cell lands in the viewport clear of the header and the frozen column.

## Tests

`TableCellModeTests` (20), `TableCellKeyboardTests` (12), `TableCellEditorTests` (25), `TableDemoTests` (+1). Every new test names its mutation in its doc comment. The round below (each restored after its run, source files byte-identical to the commit afterwards); "red" is the test itself failing, and a mutation commonly reddens neighbours too.

| test | mutation | red |
|---|---|---|
| `aClickSetsTheActiveCellAndSelectsItsRow` | the cell's click does not run the row click | itself |
| `aMoveWritesTheBindingOnceAndToTheSameCellNotAtAll` | `activate` writes unconditionally | itself |
| `aMoveRealisesOnlyTheVisibleWindowAndRebuildsNoRowTwice` | a build with an active cell counts its cells twice | itself |
| `aTableWithoutCellModeIsUnchanged` | the ring paints for every cell | itself |
| `anUnresolvableActiveCellDrawsNoRing` | the ring is drawn for the active column on every row | itself |
| `theRingIsAccentWhenFocusedAndSecondaryWhenNot` | the focus test dropped (always the 2-point accent ring) | itself |
| `aSelectedRowIsTheUnemphasisedFillInCellMode` | the accent selection fill in cell mode | itself |
| `aClickBelowTheLastRowLeavesTheActiveCell` | the empty space has a click that clears the active cell | itself |
| `modifiedClicksActOnTheRowSelectionAndMoveTheActiveCell` | a modified click skips the row click | itself |
| `anIdleCellModeTableAsksNoFrames` | the body asks another frame every prepaint in cell mode | itself (and most editor tests: `runUntilIdle` never settles) |
| `aCellBackgroundFillsTheWholeBox` | the fill rectangle is inset by 6 | itself |
| `theFillIsCalledOnlyForRealisedCellsAndNeverWhenIdle` | `fill` is called twice per cell | itself |
| `aTintStaysVisibleOnASelectedRow` | a selected row drops the tint | itself |
| `aNilFillPaintsNothing` | `nil` becomes a clear fill | itself |
| `theRingIsKeyedToTheCellAndNotTheWindowSlot` | the ring follows the first realised row | itself |
| `scrollToACellRevealsBothAxes` | the column is ignored | itself |
| `scrollToACellLeavesTheActiveCell` | the scroll makes its cell active | itself |
| `scrollToARowIDStillWorksInACellModeTable` | the row-id branch is disabled | itself |
| `aFrozenCellsRingIsAboveTheScrolledCells` | a row paints its cells in reverse | itself |
| `editingWithoutAnActiveCellBindingDoesNothing` | `isOn` is also true with a fill closure | itself |
| `arrowsStopAtTheEdgesAndAreConsumed` | the edge wraps | itself |
| `upAndDownMoveOneRowAndShiftExtendsTheSelection` | ⇧ does not extend | itself |
| `upAndDownMoveTheCellOfATableThatDoesNotSelect` | the position step is removed | itself (and four editor and key tests) |
| `tabWrapsToTheNextRowsFirstColumn` | Tab does not wrap | itself |
| `homeEndAndPrimaryArrowsJumpToTheEndsOfTheRow` | Home and End are declined | itself |
| `primaryUpAndDownJumpToTheFirstAndLastRow` | `primary`+↓ steps one row | itself |
| `pageKeysMoveTheActiveCellByAPage` | the page keys scroll only | itself |
| `shiftReturnMovesOneRowUp` | ⇧Return moves down | itself |
| `escapeFallsThrough` | Escape is taken as Tab | itself |
| `aMoveWithNoActiveCellStartsAtTheFirstRow` | the start is the last row | itself |
| `aCellRevealClearsHeaderAndFrozenColumns` | the reveal rectangle starts at the column's own x | itself |
| `primaryDownOnAMillionRowsReadsTheWindowOnly` | the active row is found by a scan | itself |
| `returnBeginsEditingWithTheCallersText` | the editor starts from the displayed content | itself |
| `typingACharacterReplacesTheText` | the typed character is ignored | itself |
| `returnCommitsOnceAndMovesDown` | an ended edit stays in the state, reads as open and `end` does not check | itself and eleven editor tests |
| `aSecondReturnBeforeTheNextFrameCommitsNothingMore` | both `isOpen` guards removed | itself |
| `shiftReturnAndTabCommitAndMove` | Tab commits and stays | itself |
| `tabAtTheLastColumnWrapsAfterTheCommit` | no wrap after an edit | itself |
| `escapeCancelsWithNoCallback` | Escape commits | itself |
| `aCallerNilCancels` | the cancel commits | itself |
| `aCallerCellBeginsAnEditAndRevealsIt` | the begin does not reveal | itself |
| `aClickElsewhereCommits` | the click does not commit first (focus leaving would, but after the move) | itself (the order `commit`, `active`) |
| `aClickInEmptySpaceCommits` | no empty-space click | itself |
| `focusLeavingTheTableCommitsButResigningKeyDoesNot` | focus leaving cancels | itself |
| `theEditorSurvivesScrollingItsCellOut` | the editor is unnamed (positional identity) | itself and five more |
| `aKeystrokeIntoAnOffscreenEditorRevealsIt` | typing does not reveal | itself |
| `optionReturnInsertsALineBreak` | ⌥Return commits | itself |
| `aCommitIsCalledEvenWhenTheTextIsUnchanged` | an unchanged text is not committed | itself and two more |
| `aCellThatIsNotEditableStartsNoEdit` | `isEditable` ignored for a typed key | itself |
| `typingRebuildsOnlyTheEditor` | a build with an open edit counts its cells twice (the first version of the test took its baseline with the edit open and stayed green; it now takes it from a table with none) | itself |
| `anIdleEditorCostsAnIdleTextField` | the body asks another frame while editing | itself (and most editor tests) |
| `aReloadThatDropsTheRowLeavesTheEditOpenAndCommitsOnce` | an unresolvable row cancels the edit | itself |
| `aSortUnderTheEditMovesTheEditorWithItsRow` | the position hint is trusted without verifying | itself |
| `theTableLeavingTheHierarchyCommitsOnce` and `theWindowClosingCommitsOnce` | the disappearance note removed | both |
| `anEndedEditNeverCommitsAgain` | an ended edit stays in the state and reads as open | itself and ten more |
| `returnOnACellThatIsNotEditableRunsThePrimaryAction` | cell mode swallows the keys it does not take | itself |
| `theTableDemosCellModeEditsASheet` | the sheet's `onCommit` does nothing | itself |

The existing PR C suites run unmodified and green. `everyStateWriteSiteIsClassified` moved `TableBody.swift` from (0, 1, 0, 0) to (2, 1, 1, 0) and is the only existing test edited.

## Deviations from the plan and the spec

- **The cost pins "zero cells realised" on a move or a keystroke cannot hold**: every frame the table draws rebuilds its window (`TBL-M`), so the pins are `builds x` the steady window in rows and cells, and the editor's element requests, which is what a move and a keystroke cost.
- **`fill` runs for every realised cell of every build**, not only the newly realised: a scroll step calls it `tableCellsRealized` times, idle it calls it 0 times.
- **A window resigning key has no event in `Window`**, so there is nothing to commit on; the test pins that a pointer leaving and a modifier change do not.
- **Cells register their own click in cell mode**, and a click in the empty space commits through a viewport-sized region registered only while an edit is open (the body is only as tall as its rows).
- **`tableCellEditing` and `tableCellBackground` without `tableActiveCell` do nothing** (the spec was silent). **A caller moving `editing` from one cell to another cancels the open edit** (silent).
- **Page Up and Page Down move the active cell and leave the row selection alone**; the plan's `TBL-O` amendment was silent on the selection.
- **The unemphasised selection fill** is `Color.secondary` at 0.25 (`List` has no unfocused fill to copy); the unfocused ring is `Color.secondary`.
- **A column reorder (PR D) is not built yet**, so the declared-to-display map is the identity in every test; it is built from the resolved columns' keys each build (O(columns), cell mode only) and `TableCellReveal` carries the display column. PR D's test should reorder and assert the ring and the reveal follow the declared index.
- The plan's names for PR C's types held (`TableViewState`, `TableLeadReveal`, the position cache, `composeTableKeys` is `TableSelectionContext.keyHandler`); the only plan name that does not exist is `TableViewState` holding the active cell (it is the caller's binding, read once per build).
- Divergences stay 226 live, next label 243 (none used).
