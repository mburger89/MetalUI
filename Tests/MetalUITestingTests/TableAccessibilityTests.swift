import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// A `Table` in the published accessibility tree (`TBL-T`, record 392; spec section 7, cell-mode spec section 8). The tree a client
// reads: the table with its logical counts, a header row first, rows by position, cells by column with their own elements (so an
// `accessibilityIdentifier` on a cell's content stays findable in every mode), the active cell of a cell-mode table as the focused
// and selected cell, and the open editor as a text field inside that cell. Counts are read after `runUntilIdle` (off Darwin a dirty
// mark hops through a Task) and summed over `frameWork`; `Modifiers.primary`; the harness text system; each test names its mutation.

/// The table node of a published tree: the one `.table` with a column count.
@MainActor private func dataTable(_ w: TestWindow) throws -> (id: AccessibilityNodeID, node: AccessibilityNode) {
    let tree = try w.accessibilityTree
    let found = tree.nodes.first { $0.value.role == .table && $0.value.columnCount != nil }
    return try #require(found.map { (id: $0.key, node: $0.value) }, "no data table published: \(tree.nodes.values.map(\.role))")
}

/// A node's children as nodes.
@MainActor private func kids(_ id: AccessibilityNodeID, in w: TestWindow) throws -> [AccessibilityNode] {
    let tree = try w.accessibilityTree
    return (tree.nodes[id]?.children ?? []).compactMap { tree.nodes[$0] }
}

/// The data rows (the header row has no index) of the published table, in published order, with their ids.
@MainActor private func dataRows(_ w: TestWindow) throws -> [(id: AccessibilityNodeID, node: AccessibilityNode)] {
    let table = try dataTable(w)
    let tree = try w.accessibilityTree
    return table.node.children.compactMap { id in
        guard let node = tree.nodes[id], node.role == .row, node.rowIndex != nil else { return nil }
        return (id: id, node: node)
    }
}

/// **TA1** A million-row, 200-column table at the steady offsets publishes its LOGICAL counts, one header row, and only the
/// realised window: rows 498...525, and in the first row the cells of columns 5...14 in order. Mutation: publish `rowCount` as the
/// realised count (`layout.rows.count`) or give each cell its column minus one.
@Test @MainActor func aTablePublishesItsLogicalCountsAndTheRealisedWindow() async throws {
    let w = try tableFixture(rows: 1_000_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let table = try dataTable(w)
    #expect(table.node.rowCount == 1_000_000, "rows \(String(describing: table.node.rowCount))")
    #expect(table.node.columnCount == 200 && table.node.headerRowCount == 1, "columns \(String(describing: table.node.columnCount)) header \(String(describing: table.node.headerRowCount))")
    let rows = try dataRows(w)
    #expect(rows.count == steadyRows, "rows \(rows.count)")
    #expect(rows.map(\.node.rowIndex) == (498..<526).map { Optional($0) }, "indices \(rows.map(\.node.rowIndex))")
    let firstRow = try #require(rows.first)
    let cells = try kids(firstRow.id, in: w)
    #expect(cells.allSatisfy { $0.role == .cell }, "cell roles \(cells.map(\.role))")
    #expect(cells.map(\.columnIndex) == (5..<15).map { Optional($0) }, "columns \(cells.map(\.columnIndex))")
    #expect(cells.allSatisfy { $0.rowIndex == 498 }, "cells carry their row: \(cells.map(\.rowIndex))")
}

/// **TA2** A frozen column's cell paints and registers after the scrolled ones, and publishes FIRST in its row: with column 0 frozen
/// the row's cells are `[0, 6, ...]` ascending. Mutation: drop the builder's sort of a row's children by column.
@Test @MainActor func aFrozenCellIsPublishedFirstInItsRow() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200, frozen: 1)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let rowList = try dataRows(w)
    let first = try #require(rowList.first)
    let columns = try kids(first.id, in: w).compactMap(\.columnIndex)
    #expect(columns.first == 0, "the frozen column is first: \(columns)")
    #expect(columns == columns.sorted() && columns.count == 10, "ascending, ten cells: \(columns)")
}

/// **TA3** The header row is the table's FIRST child (it prepaints after every row), carries no row index, and its cells are
/// `.columnHeader`s with their column, their titles as labels, and the direction on the column the table sorts by. Mutation: leave
/// the header row where it prepainted (last), or publish `sortDirection` on every column.
@Test @MainActor func theHeaderRowIsTheTablesFirstChild() async throws {
    let model = SortModel()
    model.order = [KeyPathComparator(\SortRow.name)]
    let rows = (0..<20).map { SortRow(id: $0, name: "n\($0)", size: $0 % 5) }
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(rows, sortOrder: model.binding()) {
            TableColumn("Name", value: \SortRow.name).width(Pixels(100))
            TableColumn("Size", value: \SortRow.size) { r in Text("\(r.size)") }.width(Pixels(100))
            TableColumn("Plain") { r in Text("p\(r.id)") }.width(Pixels(100))
        }
        .tableRowHeight(Pixels(24))
    }
    try await w.runUntilIdle()
    let table = try dataTable(w)
    let tree = try w.accessibilityTree
    let headerID = try #require(table.node.children.first)
    let header = try #require(tree.nodes[headerID])
    #expect(header.role == .row && header.rowIndex == nil, "first child \(header.role) index \(String(describing: header.rowIndex))")
    let cells = header.children.compactMap { tree.nodes[$0] }
    #expect(cells.map(\.role) == [.columnHeader, .columnHeader, .columnHeader], "roles \(cells.map(\.role))")
    #expect(cells.map(\.columnIndex) == [0, 1, 2] && cells.map(\.label) == ["Name", "Size", "Plain"],
            "columns \(cells.map(\.columnIndex)) labels \(cells.map { $0.label ?? "-" })")
    #expect(cells.map(\.sortDirection) == [.ascending, nil, nil], "directions \(cells.map(\.sortDirection))")
    #expect(cells[0].actions.contains(.press) && cells[2].actions.isEmpty, "a sortable header presses, a plain one does not")
    #expect(header.children.count == 3 && table.node.children.count == 1 + 20, "children \(table.node.children.count)")
    model.order = [KeyPathComparator(\SortRow.name, order: .reverse)]
    try await w.runUntilIdle()
    let headerAfter = try #require(try dataTable(w).node.children.first)
    let direction = try kids(headerAfter, in: w).map(\.sortDirection)
    #expect(direction == [.descending, nil, nil], "after reversing \(direction)")
}

/// **TA4** A cold frame (no viewport yet) publishes the table and no rows; once idle the window's 28 rows are published. Mutation: no
/// suppression on a cold frame (its first frame publishes rows the plan never built for a viewport).
@Test @MainActor func aColdFramePublishesTheTableAndNoRows() async throws {
    let w = try tableFixture(rows: 10_000, columns: 20)
    let cold = try w.accessibilityTree
    let coldTable = cold.nodes.first { $0.value.role == .table && $0.value.columnCount != nil }
    #expect(coldTable != nil, "the table is published on frame 1")
    #expect(cold.nodes.values.filter { $0.role == .row && $0.rowIndex != nil }.isEmpty,
            "frame 1 publishes no rows: \(cold.nodes.values.filter { $0.role == .row }.count)")
    try await w.runUntilIdle()
    let after = try dataRows(w).count
    #expect(after > 0 && after <= steadyRows, "rows after idle \(after)")
}

private struct PlainRow: Identifiable { let id: Int }

/// **TA5** A `List` is published as before: no column count, no column index on its rows, no header. Mutation: give every `.table` a
/// column count.
@Test @MainActor func aListIsStillPublishedAsBefore() async throws {
    let w = try harnessWindow(size: sz(300, 300)) {
        ScrollView { List((0..<40).map(PlainRow.init), rowHeight: Pixels(28)) { r in Text("row \(r.id)") }
            .frame(width: Pixels(300), height: Pixels(300)) }
    }
    try await w.runUntilIdle()
    let tree = try w.accessibilityTree
    let tables = tree.nodes.values.filter { $0.role == .table }
    #expect(tables.count == 1 && tables[0].columnCount == nil && tables[0].headerRowCount == nil, "tables \(tables.count)")
    #expect(tree.nodes.values.allSatisfy { $0.columnIndex == nil && $0.sortDirection == nil && $0.role != .columnHeader })
    #expect(tree.nodes.values.contains { $0.role == .row && $0.rowIndex != nil })
}

// MARK: - Every cell keeps its element and identifier in every mode

@MainActor @TableColumnBuilder<RowRef, Never> private func identifiedColumns() -> TableColumnGroup<RowRef, Never> {
    TableColumn("A") { r in Text("a\(r.id)").accessibilityIdentifier("cell-a\(r.id)") }.width(Pixels(100))
    TableColumn("B") { r in Text("b\(r.id)").accessibilityIdentifier("cell-b\(r.id)") }.width(Pixels(100))
}

/// **TA6** In a plain, a selectable and a cell-mode table every body cell is its own `.cell` node holding its content element, whose
/// identifier a client finds; no node's label joins the cells' texts. Mutation: give a row `accessibilityElement(children:
/// .combine)` semantics, or fold a cell's content into the cell (a cell with no children).
@Test @MainActor func everyCellKeepsItsOwnElementAndIdentifierInEveryMode() async throws {
    let sel = TableSel(), model = CellModel()
    let plain = try harnessWindow(size: sz(800, 600)) { Table(CountingRows(5)) { identifiedColumns() }.tableRowHeight(Pixels(24)) }
    let selectable = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5), selection: sel.multiBinding()) { identifiedColumns() }.tableRowHeight(Pixels(24))
    }
    let cellMode = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5), selection: sel.multiBinding()) { identifiedColumns() }.tableRowHeight(Pixels(24))
            .tableActiveCell(model.activeBinding())
    }
    for (name, w) in [("plain", plain), ("selectable", selectable), ("cell mode", cellMode)] {
        try await w.runUntilIdle()
        let tree = try w.accessibilityTree
        let b = try w.element(identifier: "cell-b2")
        #expect(b.value == "b2", "\(name): cell-b2 reads \(String(describing: b.value))")
        let parent = tree.nodes.first { $0.value.children.contains(b.id) }?.value
        #expect(parent?.role == .cell && parent?.columnIndex == 1 && parent?.rowIndex == 2,
                "\(name): its cell is \(String(describing: parent?.role)) column \(String(describing: parent?.columnIndex)) row \(String(describing: parent?.rowIndex))")
        let joined = try w.elements(where: { ($0.label ?? "").contains("a2") && ($0.label ?? "").contains("b2") })
        #expect(joined.isEmpty, "\(name): a node joined its cells' texts: \(joined.map { $0.label ?? "" })")
        let rows = try dataRows(w)
        #expect(rows.count == 5 && rows.allSatisfy { $0.node.children.count == 2 }, "\(name): rows \(rows.count)")
    }
}

// MARK: - Cell mode (cell-mode spec section 8)

/// **TA7** The active cell of a cell-mode table is the focused element while the table has focus, and is selected; the table node
/// itself is not the focus. Mutation: publish the table body as the focus (no redirect to the active cell), or leave the active cell
/// unselected.
@Test @MainActor func theActiveCellIsTheFocusedAndSelectedCell() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 20, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    #expect(model.active == TableCell(row: 3, column: 2))
    let focused = try #require(try w.focusedElement, "something has focus")
    let tree = try w.accessibilityTree
    let node = try #require(tree.nodes[focused.id])
    #expect(node.role == .cell && node.rowIndex == 3 && node.columnIndex == 2, "focus is \(node.role) \(String(describing: node.rowIndex)),\(String(describing: node.columnIndex))")
    #expect(node.isSelected, "the active cell is selected")
    let selectedCells = tree.nodes.values.filter { $0.role == .cell && $0.isSelected }
    #expect(selectedCells.count == 1, "selected cells \(selectedCells.count)")
    // Moving the active cell moves the focus with it.
    w.typeKey(.rightArrow)
    try await w.runUntilIdle()
    let moved = try #require(try w.focusedElement)
    let movedColumn = try w.accessibilityTree.nodes[moved.id]?.columnIndex
    #expect(movedColumn == 3, "focus followed to column 3: \(String(describing: movedColumn))")
}

/// **TA8** A row table (no cell mode) keeps the table as the focused element. Mutation: redirect every table's focus to a cell.
@Test @MainActor func aRowTablesFocusStaysOnTheTable() async throws {
    let sel = TableSel()
    let w = try selectableTable(model: sel)
    try await w.runUntilIdle()
    w.window.focus(nil)
    w.click(at: rowPoint(3))
    try await w.runUntilIdle()
    let focused = try #require(try w.focusedElement)
    #expect(focused.role == .table, "focus is \(focused.role)")
}

/// **TA9** The open editor is a text field inside the cell it covers, and the focus. Mutation: leave the editor where it records (a
/// child of the table, not of the cell).
@Test @MainActor func theOpenEditorIsATextFieldChildOfItsCell() async throws {
    let model = CellModel()
    let w = try cellTable(rows: 20, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r"))
    try await w.runUntilIdle()
    #expect(model.editing == TableCell(row: 3, column: 2))
    let tree = try w.accessibilityTree
    let editors = tree.nodes.filter { $0.value.role == .textField }
    #expect(editors.count == 1, "text fields \(editors.count)")
    let editor = try #require(editors.first)
    let host = try #require(tree.nodes.first { $0.value.children.contains(editor.key) }?.value)
    #expect(host.role == .cell && host.rowIndex == 3 && host.columnIndex == 2,
            "the editor's parent is \(host.role) \(String(describing: host.rowIndex)),\(String(describing: host.columnIndex))")
    #expect(tree.focused == editor.key, "the editor holds the focus")
    // The cell keeps its own content element beside the editor.
    #expect(host.children.contains { tree.nodes[$0]?.value == "r3c2" || tree.nodes[$0]?.role == .staticText }, "the cell's content is kept")
}

// MARK: - Cost

/// **TA10** A table with no accessibility client records nothing and costs what it did: zero emissions, and the steady frame's
/// element requests, paints, cells and reads are the pinned literals and equal those of the same table with a client collecting.
/// Mutation: drop `Frame.recordAccessibility`'s `collectsAccessibility` gate (a table with no client then records every cell).
@Test @MainActor func aTableWithNoAccessibilityClientRecordsNothingAndCostsTheSame() async throws {
    func fixture(client: Bool) throws -> TestWindow {
        try harnessWindow(size: sz(800, 600), options: .init(accessibilityClientActive: client)) {
            Table(CountingRows(10_000)) {
                TableColumnForEach(0..<200) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
            }.tableRowHeight(Pixels(24))
        }
    }
    func steadyWork(_ w: TestWindow) async throws -> FrameWork {
        try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
        try await w.runUntilIdle()
        w.resetFrameWork()
        w.window.setNeedsRedraw(); w.tick()
        return w.lastFrameWork
    }
    let off = try fixture(client: false), on = try fixture(client: true)
    let quiet = try await steadyWork(off), loud = try await steadyWork(on)
    #expect(off.window.accessibility.lastEmissionCount == 0, "records with no client: \(off.window.accessibility.lastEmissionCount)")
    #expect(on.window.accessibility.lastEmissionCount > 280, "records with a client: \(on.window.accessibility.lastEmissionCount)")
    #expect(quiet.elementRequests == 621 && quiet.elementPaints == 621, "no client: requests \(quiet.elementRequests) paints \(quiet.elementPaints)")
    #expect(quiet.tableCellsRealized == 280 && quiet.tableDataReads == 28 && quiet.builds == 1,
            "no client: cells \(quiet.tableCellsRealized) reads \(quiet.tableDataReads) builds \(quiet.builds)")
    #expect(loud.elementRequests == quiet.elementRequests && loud.elementPaints == quiet.elementPaints
            && loud.tableCellsRealized == quiet.tableCellsRealized && loud.tableDataReads == quiet.tableDataReads
            && loud.builds == quiet.builds, "a collecting client moved the work: \(loud) against \(quiet)")
}
