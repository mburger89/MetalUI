@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `Table` cell mode, the keys (`TCM-E`, record 394): one test per row of the spec's first table, the reveal on both axes and what a
// move costs. Counts are read after `runUntilIdle`; `Modifiers.primary`; the harness text system; each test names its mutation.

private let leftKey = "\u{f702}", rightKey = "\u{f703}", upKey = "\u{f700}", downKey = "\u{f701}"
private let homeKey = "\u{f729}", endKey = "\u{f72b}", pageUpKey = "\u{f72c}", pageDownKey = "\u{f72d}"
private let returnKey = "\r", tabKey = "\t", escapeKey = "\u{1b}"

/// A cell-mode table with cell (3, 2) active and the table focused (a click on it).
@MainActor private func focusedCellTable(rows: Int = 50, columns: Int = 6, frozen: Int = 0, model: CellModel, selection: TableSel? = nil,
                                         data: CountingRows? = nil, editable: Bool = true,
                                         editableCell: (@MainActor (TableCell<Int>) -> Bool)? = nil) async throws -> TestWindow {
    let w = try cellTable(rows: rows, columns: columns, frozen: frozen, model: model, selection: selection, data: data,
                          editable: editable, editableCell: editableCell)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    return w
}

/// **E1** ← and → move one column and stop at the edges, where they are consumed and write nothing. Mutation: the edge wraps.
@Test @MainActor func arrowsStopAtTheEdgesAndAreConsumed() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    w.typeKey(.leftArrow); w.typeKey(.leftArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 0))
    model.activeWrites = []
    #expect(rawCellKey(w, leftKey), "consumed at the left edge")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 0) && model.activeWrites.isEmpty, "stays: \(String(describing: model.active))")
    for _ in 0..<5 { w.typeKey(.rightArrow) }
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5))
    model.activeWrites = []
    #expect(rawCellKey(w, rightKey), "consumed at the right edge")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5) && model.activeWrites.isEmpty)
}

/// **E2** ↑ and ↓ move one row, keeping the column; with a row selection ⇧↓ extends it and the active cell follows the lead.
/// Mutation: ⇧ moves the active cell without extending the selection.
@Test @MainActor func upAndDownMoveOneRowAndShiftExtendsTheSelection() async throws {
    let model = CellModel(), sel = TableSel()
    let w = try await focusedCellTable(model: model, selection: sel)
    w.typeKey(.downArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 4, column: 2) && sel.multi == [4], "down: \(String(describing: model.active)) \(sel.multi)")
    w.typeKey(.downArrow, modifierFlags: .shift); w.typeKey(.downArrow, modifierFlags: .shift); try await w.runUntilIdle()
    #expect(sel.multi == [4, 5, 6], "extended \(sel.multi)")
    #expect(model.active == TableCell(row: 6, column: 2), "the active cell follows the lead")
    w.typeKey(.upArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 5, column: 2) && sel.multi == [5], "up: \(String(describing: model.active)) \(sel.multi)")
}

/// **E2b** Without a row selection ↑ ↓ still move the cell. Mutation: the move needs a selection binding.
@Test @MainActor func upAndDownMoveTheCellOfATableThatDoesNotSelect() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    w.typeKey(.downArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 4, column: 2))
    w.typeKey(.upArrow); w.typeKey(.upArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 2, column: 2))
}

/// **E3** Tab moves right and wraps to the next row's first column; ⇧Tab the other way; both are consumed at the very ends.
/// Mutation: Tab does not wrap.
@Test @MainActor func tabWrapsToTheNextRowsFirstColumn() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(rows: 4, model: model)
    w.typeKey(.tab); w.typeKey(.tab); w.typeKey(.tab); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5), "last column of the last row")
    model.activeWrites = []
    #expect(rawCellKey(w, tabKey), "consumed at the very end")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5) && model.activeWrites.isEmpty)
    w.click(at: rowPoint(1, column: 5)); try await w.runUntilIdle()
    w.typeKey(.tab); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 2, column: 0), "wraps: \(String(describing: model.active))")
    w.typeKey(.tab, modifierFlags: .shift); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 1, column: 5), "⇧Tab wraps back: \(String(describing: model.active))")
    w.click(at: rowPoint(0, column: 0)); try await w.runUntilIdle()
    model.activeWrites = []
    #expect(rawCellKey(w, tabKey, modifiers: .shift), "consumed at the very start")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 0, column: 0) && model.activeWrites.isEmpty)
}

/// **E4** Home and End are the first and last column of the row, as `primary`+← → are. Mutation: Home scrolls only (PR C's key).
@Test @MainActor func homeEndAndPrimaryArrowsJumpToTheEndsOfTheRow() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    w.typeKey(KeyEquivalent(Character(endKey))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5))
    w.typeKey(KeyEquivalent(Character(homeKey))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 0))
    w.typeKey(.rightArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 5))
    w.typeKey(.leftArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 0))
}

/// **E5** `primary`+↑ ↓ are the first and last row. Mutation: ↓ moves one row.
@Test @MainActor func primaryUpAndDownJumpToTheFirstAndLastRow() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    w.typeKey(.downArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 49, column: 2))
    w.typeKey(.upArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 0, column: 2))
}

/// **E6** Page Down and Page Up move the active cell by `rowsPerPage` (23 in an 800 x 600 table), and the page is revealed.
/// Mutation: the page keys scroll only (PR C's rule).
@Test @MainActor func pageKeysMoveTheActiveCellByAPage() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(rows: 200, model: model, selection: TableSel())   // a selecting table has row hitboxes
    w.typeKey(KeyEquivalent(Character(pageDownKey))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 26, column: 2), "down a page: \(String(describing: model.active))")
    let frame = try cellRowFrame(w, 26)
    #expect(frame.origin.y.value >= 28 && frame.origin.y.value + frame.size.height.value <= 600, "revealed: \(frame)")
    w.typeKey(KeyEquivalent(Character(pageUpKey))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 2), "back up: \(String(describing: model.active))")
}

/// **E7** ⇧Return moves one row up (a table that selects keeps its selection as it was). Mutation: ⇧Return moves down.
@Test @MainActor func shiftReturnMovesOneRowUp() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    w.typeKey(KeyEquivalent(Character(returnKey)), modifierFlags: .shift); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 2, column: 2), "up: \(String(describing: model.active))")
    #expect(model.editing == nil)
}

/// **E8** Escape is nothing: a table with a cell active declines it. Mutation: Escape clears the active cell.
@Test @MainActor func escapeFallsThrough() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    model.activeWrites = []
    #expect(!rawCellKey(w, escapeKey), "declined")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 2) && model.activeWrites.isEmpty)
}

/// **E9** With no active cell the first move starts at the first row, in column 0. Mutation: the move starts at the last row.
@Test @MainActor func aMoveWithNoActiveCellStartsAtTheFirstRow() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(model: model)
    model.active = nil; try await w.runUntilIdle()
    w.typeKey(.rightArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 0, column: 0), "from the top: \(String(describing: model.active))")
}

// MARK: - The reveal (`TCM-E`)

/// **E10** Every move reveals the new cell on both axes, clear of the pinned header and the frozen columns: with column 0 frozen
/// over 20 columns, End puts the last column fully right of the frozen one and inside the viewport; ↓ at the last visible row puts
/// the next row under the header. Mutation: the reveal rectangle starts at the cell's own x (a column lands under the frozen one).
@Test @MainActor func aCellRevealClearsHeaderAndFrozenColumns() async throws {
    let model = CellModel()
    let w = try await focusedCellTable(rows: 100, columns: 20, frozen: 1, model: model)
    /// The active cell's box in window space, read from its ring.
    @MainActor func box() throws -> (x: Float, y: Float) {
        try #require(ringOrigin(ringRects(w, width: 2)), "the active cell is realised and drawn: \(String(describing: model.active))")
    }
    w.typeKey(KeyEquivalent(Character(endKey))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 19))
    let last = try box()
    #expect(last.x >= 100 && last.x + 100 <= 800, "the last column is clear of the frozen one: \(last)")
    for _ in 0..<12 {
        w.typeKey(.leftArrow); try await w.runUntilIdle()
        let stepped = try box()
        #expect(stepped.x >= 100 && stepped.x + 100 <= 800, "column \(String(describing: model.active?.column)) is clear of the frozen one: \(stepped)")
    }
    w.typeKey(.downArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    let bottom = try box()
    #expect(bottom.y >= 28 && bottom.y + 24 <= 600, "the last row is revealed under the header: \(bottom)")
    w.typeKey(.upArrow, modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    let top = try box()
    #expect(top.y == 28, "row 0 sits right under the header: \(top)")
}

/// **K4** `primary`+↓ on a million rows reads the new window only: the key itself reads a handful of rows (the active row's
/// verification and the last row), the frames after it the window. Mutation: the move scans the data for the last row.
@Test @MainActor func primaryDownOnAMillionRowsReadsTheWindowOnly() async throws {
    let model = CellModel()
    let data = CountingRows(1_000_000)
    let w = try await focusedCellTable(rows: 0, model: model, data: data)
    data.resetCounts()
    _ = w.send(.keyDown(KeyEvent(charactersIgnoringModifiers: downKey, characters: downKey, modifiers: Modifiers.primary, timestamp: w.now)))
    #expect(data.subscriptReads <= 4, "the input read \(data.subscriptReads) rows")
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 999_999, column: 2))
    #expect(data.subscriptReads <= 30 * 2, "reads \(data.subscriptReads)")
    #expect(data.subscriptReads >= 28, "the window was read")
}
