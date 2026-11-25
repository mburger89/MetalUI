@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `Table` cell mode, the active cell (`TCM-D`, record 394): clicks, the ring, the row highlight, what a move costs and what a table
// without cell mode keeps. Counts are read after `runUntilIdle` and summed over `frameWork`; `Modifiers.primary`; the harness text
// system; windows kept alive. Each test names its mutation in its doc comment.

/// **D1** A click on a cell sets the active cell and selects its row: the binding is `(3, 2)` and the row selection `[3]`.
/// Mutation: the cell's click does not run the row click (the selection stays empty).
@Test @MainActor func aClickSetsTheActiveCellAndSelectsItsRow() async throws {
    let model = CellModel(), sel = TableSel()
    let w = try cellTable(model: model, selection: sel)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 2), "active \(String(describing: model.active))")
    #expect(sel.multi == [3], "selected \(sel.multi)")
    #expect(w.window.focusedElement != nil, "the table is focused")
}

/// **D2** A move writes the binding once, and a move to the same cell writes nothing: → once, then Home at column 0 is a move to
/// the cell it is on. Mutation: the move writes unconditionally.
@Test @MainActor func aMoveWritesTheBindingOnceAndToTheSameCellNotAtAll() async throws {
    let model = CellModel()
    let w = try cellTable(model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 0)); try await w.runUntilIdle()
    model.activeWrites = []
    w.typeKey(.rightArrow); try await w.runUntilIdle()
    #expect(model.activeWrites == [TableCell(row: 3, column: 1)], "writes \(model.activeWrites)")
    model.activeWrites = []
    w.typeKey(KeyEquivalent("\u{f729}")); try await w.runUntilIdle()   // Home: column 0
    #expect(model.activeWrites == [TableCell(row: 3, column: 0)])
    model.activeWrites = []
    w.typeKey(KeyEquivalent("\u{f729}")); try await w.runUntilIdle()   // Home again: the same cell
    #expect(model.activeWrites.isEmpty, "writes \(model.activeWrites)")
}

// MARK: - Cost (`TCM-K`)

@MainActor private func work(of step: () -> Void, in w: TestWindow) async throws -> FrameWork {
    w.resetFrameWork()
    step()
    try await w.runUntilIdle()
    return w.frameWork.reduce(FrameWork(), +)
}

/// What one rebuilt frame of `w` realises: the steady window, read from a forced redraw.
@MainActor private func oneFrame(_ w: TestWindow) async throws -> FrameWork {
    try await w.runUntilIdle()
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    return w.lastFrameWork
}

/// **K2** A move rebuilds the window the way every frame does and nothing more. The plan pinned "zero cells realised", which no
/// frame of any table can meet (the body realises its window each build, `TBL-M`); the pin that holds is builds x the steady
/// window, and one binding write. → realises exactly `builds x (28 rows, their cells)`. Mutation: a build with an active cell
/// realises its rows twice.
@Test @MainActor func aMoveRealisesOnlyTheVisibleWindowAndRebuildsNoRowTwice() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 5000, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 1)); try await w.runUntilIdle()
    let steady = try await oneFrame(w)
    #expect(steady.tableRowsRealized > 0 && steady.tableCellsRealized == steady.tableRowsRealized * 6, "steady \(steady.tableRowsRealized)")
    model.activeWrites = []
    let moved = try await work(of: { w.typeKey(.rightArrow) }, in: w)
    #expect(model.activeWrites.count == 1)
    #expect(moved.tableRowsRealized == moved.builds * steady.tableRowsRealized, "rows \(moved.tableRowsRealized) over \(moved.builds) builds")
    #expect(moved.tableCellsRealized == moved.builds * steady.tableCellsRealized, "cells \(moved.tableCellsRealized)")
}

/// **K1** A table without `tableActiveCell` is the row table: the same element requests, paints and rectangles as a cell-mode
/// table with no active cell, and `tableCellEditing` and `tableCellBackground` do nothing to it. A visible active cell adds only
/// its ring's four rectangles and no element. Mutation: the ring paints for every cell (the rectangle counts move).
@Test @MainActor func aTableWithoutCellModeIsUnchanged() async throws {
    let model = CellModel()
    let row = try cellTable(model: model, cellMode: false, tint: true)
    let cell = try cellTable(model: model)
    let rowFrame = try await oneFrame(row), cellFrame = try await oneFrame(cell)
    #expect(rowFrame.elementRequests == cellFrame.elementRequests, "requests \(rowFrame.elementRequests) \(cellFrame.elementRequests)")
    #expect(rowFrame.elementPaints == cellFrame.elementPaints)
    #expect(rowFrame.tableCellsRealized == cellFrame.tableCellsRealized && rowFrame.tableDataReads == cellFrame.tableDataReads)
    #expect(row.allRects.count == cell.allRects.count, "rects \(row.allRects.count) \(cell.allRects.count)")
    #expect(model.fillCalls == 0, "the fill of a row table never runs")
    cell.click(at: rowPoint(2, column: 2)); try await cell.runUntilIdle()
    let withRing = try await oneFrame(cell)
    #expect(withRing.elementRequests == cellFrame.elementRequests, "the ring is not an element")
    #expect(cell.allRects.count == row.allRects.count + 4, "a ring is four rectangles: \(cell.allRects.count)")
}

/// **D5** A cell whose row no longer resolves draws no ring, and the next key move starts from the first row, in the column it
/// had. Mutation: the ring is drawn for the active cell's column on every row.
@Test @MainActor func anUnresolvableActiveCellDrawsNoRing() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 50, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 1)); try await w.runUntilIdle()
    #expect(!ringRects(w, width: 2).isEmpty, "the ring is there")
    model.active = TableCell(row: 9999, column: 1); try await w.runUntilIdle()
    #expect(ringRects(w, width: 2).isEmpty && ringRects(w, width: 1).isEmpty, "no ring for a row that is not there")
    model.activeWrites = []
    w.typeKey(.downArrow); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 0, column: 1), "starts from the first row: \(String(describing: model.active))")
    #expect(!ringRects(w, width: 2).isEmpty)
}

/// The accent the harness theme paints a selected row of a row table with.
@MainActor private func accentFill() async throws -> [Float] {
    let sel = TableSel()
    let w = try selectableTable(model: sel)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2)); try await w.runUntilIdle()
    let rect = try #require(w.allRects.first { $0.bounds.size.height == 24 && $0.bounds.size.width >= 800
        && $0.bounds.origin.y == 28 + 2 * 24 })
    return [rect.background.h, rect.background.s, rect.background.l, rect.background.a]
}

/// **D3** A focused table's ring is 2 points in the accent colour; unfocused it is 1 point in another (the secondary label colour).
/// Mutation: the ring is always 2 points in the accent.
@Test @MainActor func theRingIsAccentWhenFocusedAndSecondaryWhenNot() async throws {
    let accent = try await accentFill()
    let model = CellModel()
    let w = try cellTable(model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    let focused = ringRects(w, width: 2)
    #expect(focused.count == 4, "four fills: \(focused.count)")
    let focusedOrigin = try #require(ringOrigin(focused))
    #expect(focusedOrigin == (200, 28 + 3 * 24), "inside the cell box: \(String(describing: ringOrigin(focused)))")
    let color = focused.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    #expect(color.allSatisfy { $0 == accent }, "accent \(accent), ring \(color)")
    w.window.focus(nil); try await w.runUntilIdle()
    #expect(ringRects(w, width: 2).isEmpty, "no 2-point ring while unfocused")
    let dim = ringRects(w, width: 1)
    #expect(dim.count == 4, "a 1-point ring: \(dim.count)")
    #expect(dim.allSatisfy { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] != accent }, "not the accent")
}

/// **D6** In cell mode a selected row is the unemphasised fill, never the accent, so a tint stays readable. Mutation: the accent
/// selection fill in cell mode.
@Test @MainActor func aSelectedRowIsTheUnemphasisedFillInCellMode() async throws {
    let accent = try await accentFill()
    let model = CellModel(), sel = TableSel()
    let w = try cellTable(model: model, selection: sel)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2, column: 1)); try await w.runUntilIdle()
    let rows = highlightedRows(w)
    #expect(rows == [2], "the selected row is highlighted: \(rows)")
    let fill = try #require(w.allRects.first { $0.bounds.size.height == 24 && $0.bounds.size.width >= 800 && $0.bounds.origin.y == 28 + 2 * 24 })
    #expect([fill.background.h, fill.background.s, fill.background.l, fill.background.a] != accent, "not the accent")
}

/// **D7** A click in the empty space below the last row leaves the active cell where it was. Mutation: the click clears it.
@Test @MainActor func aClickBelowTheLastRowLeavesTheActiveCell() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 5, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(1, column: 3)); try await w.runUntilIdle()
    model.activeWrites = []
    w.click(at: Point(x: Pixels(150), y: Pixels(500))); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 1, column: 3) && model.activeWrites.isEmpty, "active \(String(describing: model.active))")
}

/// **D8** ⇧-click extends the row selection and primary-click toggles it, each as TBL-N says, and the active cell moves to the
/// clicked cell. Mutation: the cell's click skips the row click for a modified click.
@Test @MainActor func modifiedClicksActOnTheRowSelectionAndMoveTheActiveCell() async throws {
    let model = CellModel(), sel = TableSel()
    let w = try cellTable(model: model, selection: sel)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2, column: 1)); try await w.runUntilIdle()
    w.click(at: rowPoint(5, column: 3), modifierFlags: .shift); try await w.runUntilIdle()
    #expect(sel.multi == [2, 3, 4, 5], "range \(sel.multi)")
    #expect(model.active == TableCell(row: 5, column: 3))
    w.click(at: rowPoint(8, column: 0), modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    #expect(sel.multi == [2, 3, 4, 5, 8], "toggled \(sel.multi)")
    #expect(model.active == TableCell(row: 8, column: 0))
}

/// **K3** An idle cell-mode table asks no frames, with a tint, an active cell and a selection. Mutation: the body asks another
/// frame every build in cell mode.
@Test @MainActor func anIdleCellModeTableAsksNoFrames() async throws {
    let model = CellModel(), sel = TableSel()
    let w = try cellTable(model: model, selection: sel, tint: true)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2, column: 1)); try await w.runUntilIdle()
    w.resetFrameWork()
    model.fillCalls = 0
    try await w.runUntilIdle()
    #expect(w.frameWork.reduce(FrameWork(), +).builds == 0, "frames while idle: \(w.frameWork.count)")
    #expect(model.fillCalls == 0, "the fill ran \(model.fillCalls) times while idle")
}

// MARK: - The cell background (`TCM-I`)

/// **I1** The fill covers the whole cell box, not the content inset: a tint for cell (3, 2) is a rectangle at the box's origin and
/// size, 100 x 24. Mutation: the rectangle is inset by the cell's 6 points.
@Test @MainActor func aCellBackgroundFillsTheWholeBox() async throws {
    let model = CellModel()
    let tint = Color.red
    model.tints[TableCell(row: 3, column: 2)] = tint
    let w = try cellTable(model: model, tint: true)
    try await w.runUntilIdle()
    let hits = w.allRects.filter { $0.bounds.origin.x == 200 && $0.bounds.origin.y == 28 + 3 * 24 && $0.bounds.size.width == 100
        && $0.bounds.size.height == 24 }
    #expect(hits.count == 1, "one box-sized fill: \(hits.count)")
    #expect(!w.allRects.contains { $0.bounds.size.width == 88 }, "no inset rectangle")
}

/// **I2** `fill` runs once per realised cell per build and never in paint or while idle: after a scroll step it was called exactly
/// `tableCellsRealized` times (the plan said "only the newly realised", but the window is rebuilt whole, `TBL-M`), and idle it
/// is called zero times. Mutation: the fill is called twice per cell.
@Test @MainActor func theFillIsCalledOnlyForRealisedCellsAndNeverWhenIdle() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 5000, model: model, tint: true)
    try await w.runUntilIdle()
    model.fillCalls = 0
    try await w.runUntilIdle()
    #expect(model.fillCalls == 0, "idle calls \(model.fillCalls)")
    model.fillCalls = 0
    let scrolled = try await work(of: { w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -240) }, in: w)
    #expect(scrolled.tableCellsRealized > 0)
    #expect(model.fillCalls == scrolled.tableCellsRealized, "calls \(model.fillCalls), cells \(scrolled.tableCellsRealized)")
}

/// **I3** A tint on a selected row is drawn: cell (2, 1)'s fill is a rectangle in the scene above the row's selection fill, so it is
/// the colour on the screen. Mutation: the selected row paints the accent over the tint.
@Test @MainActor func aTintStaysVisibleOnASelectedRow() async throws {
    let model = CellModel(), sel = TableSel()
    model.tints[TableCell(row: 2, column: 1)] = Color.red
    let w = try cellTable(model: model, selection: sel, tint: true)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2, column: 3)); try await w.runUntilIdle()
    let rects = w.allRects
    let rowFill = try #require(rects.firstIndex { $0.bounds.size.height == 24 && $0.bounds.size.width >= 800 && $0.bounds.origin.y == 28 + 2 * 24 })
    let tint = try #require(rects.firstIndex { $0.bounds.origin.x == 100 && $0.bounds.origin.y == 28 + 2 * 24 && $0.bounds.size.width == 100 })
    #expect(tint > rowFill, "the tint (\(tint)) is painted after the selected row's fill (\(rowFill))")
}

/// **I4** A `nil` fill paints nothing: the cell-mode table with a tint closure that answers `nil` has the rectangles of the one with
/// no closure. Mutation: `nil` becomes a clear fill.
@Test @MainActor func aNilFillPaintsNothing() async throws {
    let model = CellModel()
    let plain = try cellTable(model: model), tinted = try cellTable(model: model, tint: true)
    try await plain.runUntilIdle(); try await tinted.runUntilIdle()
    #expect(plain.allRects.count == tinted.allRects.count, "rects \(plain.allRects.count) \(tinted.allRects.count)")
}

// MARK: - Recycling (review focus 4)

/// **R4** The ring is keyed to (row id, column), never to a window slot: click cell (3, 2), scroll 5 000 rows away and back, and
/// the ring is on the same cell; while away there is none. Mutation: the ring follows the first realised row.
@Test @MainActor func theRingIsKeyedToTheCellAndNotTheWindowSlot() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 10_000, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    try await scrollTable(w, x: 0, y: 24 * 5000)
    #expect(ringRects(w, width: 2).isEmpty, "the cell is not realised, so no ring is drawn")
    try await scrollTable(w, x: 0, y: -24 * 5000)
    let backOrigin = try #require(ringOrigin(ringRects(w, width: 2)))
    #expect(backOrigin == (200, 28 + 3 * 24), "the ring is back on the cell")
}

// MARK: - Scroll to a cell (`TCM-J`)

@MainActor private final class CellProxyHolder { var proxy: ScrollViewProxy? }

/// A cell-mode table under a `ScrollViewReader`: `rows` rows by `columns` columns, with `tableRowIndex` when `lookup`.
@MainActor private func readerCellTable(rows: Int, columns: Int, lookup: Bool, model: CellModel, data: CountingRows,
                                        selection: TableSel = TableSel(), holder: CellProxyHolder) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
                let _ = holder.proxy = proxy
                cellTableValue(data: data, columns: columns, model: model, selection: selection, lookup: lookup)
            }
        }
    }
}

/// **J1** `scrollTo(TableCell)` on 1 000 000 rows by 200 columns reveals the cell on both axes and reads the window only: the
/// cell (900 000, 150) is on screen, clear of the header, and the data reads stay at the new window's. Mutation: the column is
/// ignored (the cell's row is shown but column 150 is not realised).
@Test @MainActor func scrollToACellRevealsBothAxes() async throws {
    let model = CellModel(), data = CountingRows(1_000_000), holder = CellProxyHolder()
    let w = try readerCellTable(rows: 1_000_000, columns: 200, lookup: true, model: model, data: data, holder: holder)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    data.resetCounts()
    holder.proxy?.scrollTo(TableCell(row: 900_000, column: 150))
    try await w.runUntilIdle()
    #expect(data.subscriptReads <= 30 * 2, "reads \(data.subscriptReads)")
    let frame = try w.frame(ofID: "r900000c150")
    #expect(frame.size.width.value > 0, "the cell is realised")
    let row = try cellRowFrame(w, 900_000, body: w.window.focusedElement)
    #expect(row.origin.y.value >= 28 && row.origin.y.value + row.size.height.value <= 600, "the row is on screen: \(row)")
    // Column 150 sits at content x 15 000; the viewport is 800 wide, so the reveal moved right by at least 14 200.
    #expect(frame.origin.x.value >= 14_200 && frame.origin.x.value + 100 <= 15_800, "the column is in the viewport band: \(frame)")
}

/// **J2** `scrollTo(TableCell)` leaves the active cell where it was. Mutation: the scroll makes its cell active.
@Test @MainActor func scrollToACellLeavesTheActiveCell() async throws {
    let model = CellModel(), data = CountingRows(10_000), holder = CellProxyHolder()
    let w = try readerCellTable(rows: 10_000, columns: 30, lookup: true, model: model, data: data, holder: holder)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2, column: 1)); try await w.runUntilIdle()
    model.activeWrites = []
    holder.proxy?.scrollTo(TableCell(row: 5_000, column: 20))
    try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 2, column: 1) && model.activeWrites.isEmpty, "active \(String(describing: model.active))")
}

/// **J3** A plain row id keeps PR C's behaviour in a cell-mode table: `scrollTo(rowID)` reveals the row and no cell. Mutation: the
/// row id branch is shadowed by the cell branch.
@Test @MainActor func scrollToARowIDStillWorksInACellModeTable() async throws {
    let model = CellModel(), data = CountingRows(10_000), holder = CellProxyHolder()
    let w = try readerCellTable(rows: 10_000, columns: 6, lookup: true, model: model, data: data, holder: holder)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    holder.proxy?.scrollTo(7_000)
    try await w.runUntilIdle()
    let row = try cellRowFrame(w, 7_000, body: w.window.focusedElement)
    #expect(row.origin.y.value >= 28 && row.origin.y.value + row.size.height.value <= 600, "row 7000 is on screen: \(row)")
}

// MARK: - Frozen columns

/// **D4** A frozen cell's ring is above the scrolled cells: with column 0 frozen and column 1 tinted under it after a scroll, the
/// ring of the frozen active cell is drawn after the tint. Mutation: the ring paints before the cell's content and fill.
@Test @MainActor func aFrozenCellsRingIsAboveTheScrolledCells() async throws {
    let model = CellModel()
    for column in 1..<10 { model.tints[TableCell(row: 3, column: column)] = Color.red }
    let w = try cellTable(columns: 10, frozen: 1, model: model, tint: true)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 0)); try await w.runUntilIdle()
    try await scrollTable(w, x: 150, y: 0)
    let rects = w.allRects
    let ring = try #require(rects.lastIndex { $0.bounds.size.height == 2 && $0.bounds.size.width == 100 && $0.bounds.origin.x == 0 })
    let under = try #require(rects.lastIndex { $0.bounds.origin.x < 100 && $0.bounds.origin.x > -100 && $0.bounds.size.width == 100
        && $0.bounds.size.height == 24 && $0.bounds.origin.y == 28 + 3 * 24 && $0.bounds.origin.x != 0 })
    #expect(ring > under, "the frozen ring (\(ring)) is painted after the scrolled tint under it (\(under))")
}

/// **A1** `tableCellEditing` and `tableCellBackground` have no effect without `tableActiveCell` (`TCM-A`): Return starts no edit and
/// the fill never runs. Mutation: the editor starts in a table with no active-cell binding.
@Test @MainActor func editingWithoutAnActiveCellBindingDoesNothing() async throws {
    let model = CellModel()
    let w = try cellTable(model: model, cellMode: false, tint: true)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    #expect(model.editing == nil && model.editingWrites.isEmpty && model.fillCalls == 0 && model.activeWrites.isEmpty)
}
