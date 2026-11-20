@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// Shared fixtures for the cell-mode lanes (`TCM-`, record 394): an observed model the tests own, and the 800 x 600 table over it.

/// The cells' values, the active and editing cells, and every write and commit kept. Observed, so a write redraws.
@MainActor @Observable final class CellModel {
    var active: TableCell<Int>?
    var editing: TableCell<Int>?
    /// A value a test overrides; every other cell is `r<row>c<column>`.
    @ObservationIgnored var overrides: [TableCell<Int>: String] = [:]
    @ObservationIgnored var activeWrites: [TableCell<Int>?] = []
    @ObservationIgnored var editingWrites: [TableCell<Int>?] = []
    @ObservationIgnored var commits: [(cell: TableCell<Int>, text: String)] = []
    @ObservationIgnored var fillCalls = 0
    @ObservationIgnored var textCalls = 0
    @ObservationIgnored var tints: [TableCell<Int>: Color] = [:]
    /// Rows the table shows, so a test can remove one.
    var hidden: Set<Int> = []

    func value(_ cell: TableCell<Int>) -> String { overrides[cell] ?? "r\(cell.row)c\(cell.column)" }

    func activeBinding() -> Binding<TableCell<Int>?> {
        Binding(get: { self.active }, set: { self.active = $0; self.activeWrites.append($0) })
    }
    func editingBinding() -> Binding<TableCell<Int>?> {
        Binding(get: { self.editing }, set: { self.editing = $0; self.editingWrites.append($0) })
    }
}

/// The rows of a table a test reorders or trims, observed so a change redraws.
@MainActor @Observable final class RowsModel {
    var rows: [RowRef]
    init(_ count: Int) { rows = (0..<count).map { RowRef(id: $0) } }
}

/// The configured cell-mode table over `data` of `columns` 100-wide columns whose cells are named `r<id>c<column>` and show the
/// model's value. `selection` adds a row selection binding; `editable` the editor (whose initial text is `rawPrefix` and the value);
/// `tint` the cell background.
@MainActor func cellTableValue<Data: RandomAccessCollection>(
    data: Data, columns: Int = 6, frozen: Int = 0, model: CellModel, selection: TableSel? = nil, cellMode: Bool = true,
    editable: Bool = true, editableCell: (@MainActor (TableCell<Int>) -> Bool)? = nil, tint: Bool = false, lookup: Bool = false,
    rawPrefix: String = "") -> Table<RowRef, TableForEachContent<Data>, TableColumnGroup<RowRef, Never>> where Data.Element == RowRef {
    @TableColumnBuilder<RowRef, Never> var columnsBuilder: TableColumnGroup<RowRef, Never> {
        TableColumnForEach(0..<columns) { c in
            TableColumn("c\(c)") { r in
                Text(model.value(TableCell(row: r.id, column: c))).id("r\(r.id)c\(c)")
            }.width(Pixels(100))
        }
    }
    let table: Table<RowRef, TableForEachContent<Data>, TableColumnGroup<RowRef, Never>>
    if let selection {
        table = Table(data, selection: selection.multiBinding()) { columnsBuilder }
    } else {
        table = Table(data) { columnsBuilder }
    }
    var configured = table.tableRowHeight(Pixels(24)).tableFrozenColumns(frozen)
    if cellMode { configured = configured.tableActiveCell(model.activeBinding()) }
    if lookup { configured = configured.tableRowIndex { $0 } }
    if editable {
        configured = configured.tableCellEditing(model.editingBinding(), text: { cell in model.textCalls += 1; return rawPrefix + model.value(cell) },
                                                 isEditable: { cell in editableCell?(cell) ?? true },
                                                 onCommit: { cell, text in model.commits.append((cell, text)); model.overrides[cell] = text })
    }
    if tint {
        configured = configured.tableCellBackground { cell in model.fillCalls += 1; return model.tints[cell] }
    }
    return configured
}

/// An 800 x 600 harness window over `cellTableValue` of `data()` (read each frame, so an observed model reloads it).
@MainActor func cellTableOver<Data: RandomAccessCollection>(
    columns: Int = 6, frozen: Int = 0, model: CellModel, selection: TableSel? = nil, cellMode: Bool = true, editable: Bool = true,
    editableCell: (@MainActor (TableCell<Int>) -> Bool)? = nil, tint: Bool = false, lookup: Bool = false, rawPrefix: String = "",
    size: Size<Pixels> = sz(800, 600), data: @escaping @MainActor () -> Data) throws -> TestWindow where Data.Element == RowRef {
    try harnessWindow(size: size) {
        cellTableValue(data: data(), columns: columns, frozen: frozen, model: model, selection: selection, cellMode: cellMode,
                       editable: editable, editableCell: editableCell, tint: tint, lookup: lookup, rawPrefix: rawPrefix)
    }
}

/// `cellTableOver` a `CountingRows` of `rows` rows (or the `data` given, to count its reads).
@MainActor func cellTable(rows: Int = 50, columns: Int = 6, frozen: Int = 0, model: CellModel, selection: TableSel? = nil,
                          data: CountingRows? = nil, cellMode: Bool = true, editable: Bool = true, editableCell: (@MainActor (TableCell<Int>) -> Bool)? = nil,
                          tint: Bool = false, lookup: Bool = false, rawPrefix: String = "", size: Size<Pixels> = sz(800, 600)) throws -> TestWindow {
    let source = data ?? CountingRows(rows)
    return try cellTableOver(columns: columns, frozen: frozen, model: model, selection: selection, cellMode: cellMode,
                             editable: editable, editableCell: editableCell, tint: tint, lookup: lookup, rawPrefix: rawPrefix, size: size, data: { source })
}

/// A key delivered as a raw event with no frame after it, so a count read next is the input's alone. Answers whether it was handled.
@MainActor func rawCellKey(_ w: TestWindow, _ characters: String, modifiers: Modifiers = []) -> Bool {
    let event = KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: w.now)
    return w.send(.keyDown(event))
}

/// The four fills of an active ring `width` points wide inside the cell at (`row`, `column`) of an unscrolled 800 x 600 table.
@MainActor func ringRects(_ w: TestWindow, width: Float) -> [MUIRect] {
    w.allRects.filter { rect in
        let b = rect.bounds
        let horizontal = b.size.height == width && b.size.width == 100
        let vertical = b.size.width == width && b.size.height == 24 - 2 * width
        return horizontal || vertical
    }
}

/// The cell, as (row, column) of an unscrolled table, a ring group of four rects wraps: its top-left corner.
func ringOrigin(_ rects: [MUIRect]) -> (x: Float, y: Float)? {
    guard let minX = rects.map({ $0.bounds.origin.x }).min(), let minY = rects.map({ $0.bounds.origin.y }).min() else { return nil }
    return (minX, minY)
}

/// Row `row`'s frame in WINDOW space, from its own hitbox: `origin.x` is minus the horizontal offset, `origin.y` the row's top.
/// The body is found through the focus, so the table must hold it (a click on a cell gives it).
@MainActor func cellRowFrame(_ w: TestWindow, _ row: Int, body: GlobalElementID? = nil) throws -> Bounds<Pixels> {
    let owner = try #require(body ?? w.window.focusedElement, "the table holds the focus")
    let id = GlobalElementID.child(of: owner, at: 0, name: ElementID.forRow(row, keyed: false))
    return try #require(w.window.lastHitboxes.last { $0.id == id }, "row \(row) is realised").bounds
}
