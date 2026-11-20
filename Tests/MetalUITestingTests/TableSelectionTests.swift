@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// `Table` selection (`TBL-N`, record 390): clicks, ⇧ and primary-modifier selection, the position cache, a click under a
// multi-click tap (G39), accessibility selection and the selection across a sort. Every count is read after `runUntilIdle` and
// summed over `frameWork`; `Modifiers.primary` for toggles; the harness text system; windows kept alive. Each test names its mutation.

/// A selection the tests own: observed, so a write redraws, with every write kept.
@MainActor @Observable final class TableSel {
    var single: Int?
    var multi: Set<Int> = []
    @ObservationIgnored var singleWrites: [Int?] = []
    @ObservationIgnored var multiWrites: [Set<Int>] = []

    func singleBinding() -> Binding<Int?> { Binding(get: { self.single }, set: { self.single = $0; self.singleWrites.append($0) }) }
    func multiBinding() -> Binding<Set<Int>> { Binding(get: { self.multi }, set: { self.multi = $0; self.multiWrites.append($0) }) }
}

/// An 800 x 600 table of `rows` rows (24 high) and four 100-wide columns, selecting into `model.multi`; `data` counts the reads.
@MainActor func selectableTable(rows: Int = 50, model: TableSel, data: CountingRows? = nil, lookup: Bool = false,
                                single: Bool = false) throws -> TestWindow {
    let source = data ?? CountingRows(rows)
    return try harnessWindow(size: sz(800, 600)) {
        if single {
            lookupped(Table(source, selection: model.singleBinding()) { selectableColumns() }, lookup)
        } else {
            lookupped(Table(source, selection: model.multiBinding()) { selectableColumns() }, lookup)
        }
    }
}

@MainActor private func lookupped<R: TableRowContent, C: TableColumnContent>(_ table: Table<RowRef, R, C>, _ lookup: Bool) -> Table<RowRef, R, C> {
    let sized = table.tableRowHeight(Pixels(24))
    return lookup ? sized.tableRowIndex { $0 } : sized
}

@MainActor @TableColumnBuilder<RowRef, Never> func selectableColumns() -> TableColumnGroup<RowRef, Never> {
    TableColumn("A") { r in Text("a\(r.id)") }.width(Pixels(100))
    TableColumn("B") { r in Text("b\(r.id)") }.width(Pixels(100))
}

/// The centre of row `row`'s cell in column `column`, in window points, at scroll offset `offset` (header 28, rows 24).
func rowPoint(_ row: Int, column: Int = 0, offset: Double = 0) -> Point<Pixels> {
    Point(x: Pixels(Float(column * 100 + 50)), y: Pixels(Float(28 + Double(row) * 24 + 12 - offset)))
}

/// The positions of the highlighted rows: the 24-high full-width fills whose colour is not the alternating one (the majority).
@MainActor func highlightedRows(_ w: TestWindow, offset: Double = 0) -> [Int] {
    var fills: [(y: Float, key: [Float])] = []
    for rect in w.allRects where rect.bounds.size.height == 24 && rect.bounds.size.width >= 800 && rect.bounds.origin.y >= 28 {
        let color: [Float] = [rect.background.h, rect.background.s, rect.background.l, rect.background.a]
        fills.append((rect.bounds.origin.y, color))
    }
    var counts: [[Float]: Int] = [:]
    for fill in fills { counts[fill.key, default: 0] += 1 }
    guard let majority = counts.max(by: { $0.value < $1.value })?.key else { return [] }
    var rows: [Int] = []
    for fill in fills where fill.key != majority { rows.append(Int((Double(fill.y) - 28 + offset) / 24)) }
    return rows.sorted()
}

/// A click's press and release delivered with no frame after them, so a count read next is the input's alone.
@MainActor func rawClick(_ w: TestWindow, at point: Point<Pixels>, modifiers: Modifiers = [], count: Int = 1) {
    let event = MouseEvent(position: point, modifiers: modifiers, clickCount: count, timestamp: w.now)
    _ = w.send(.mouseMoved(event))
    _ = w.send(.mouseDown(event))
    _ = w.send(.mouseUp(event))
}

/// **K2** A click selects the row it lands on, writes the binding once and focuses the table. Mutation: drop
/// `ClickDispatch.focusRequest` in the row click (the focus assertion reddens) or the `onClick` (the write does).
@Test @MainActor func aClickSelectsTheRowAndFocusesTheTable() async throws {
    let model = TableSel()
    let w = try selectableTable(model: model, single: true)
    try await w.runUntilIdle()
    w.window.focus(nil)
    w.click(at: rowPoint(3))
    try await w.runUntilIdle()
    #expect(model.singleWrites == [3], "writes \(model.singleWrites)")
    let focused = try w.focusedElement
    #expect(focused != nil, "the table holds the focus")
    #expect(highlightedRows(w) == [3], "highlight \(highlightedRows(w))")
}

/// **N1** A primary-modifier click toggles and a ⇧-click selects the range from the anchor: 3, ⌘5, ⇧8 write
/// `[{3}, {3, 5}, {5, 6, 7, 8}]`. Mutation: anchor the range at the first clicked row, `{3...8}`.
@Test @MainActor func aPrimaryClickTogglesAndAShiftClickSelectsTheRange() async throws {
    let model = TableSel()
    let w = try selectableTable(model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3)); try await w.runUntilIdle()
    w.click(at: rowPoint(5), modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    w.click(at: rowPoint(8), modifierFlags: .shift); try await w.runUntilIdle()
    #expect(model.multiWrites == [[3], [3, 5], [5, 6, 7, 8]], "writes \(model.multiWrites)")
    #expect(highlightedRows(w) == [5, 6, 7, 8], "highlight \(highlightedRows(w))")
}

/// A key press and release delivered with no frame after them, so a count read next is the input's alone.
@MainActor func rawKey(_ w: TestWindow, _ key: KeyEquivalent, modifiers: Modifiers = []) -> Bool {
    let characters = String(key.character)
    let event = KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: w.now)
    let handled = w.send(.keyDown(event))
    _ = w.send(.keyUp(event))
    return handled
}

/// **N2** A ⇧-click across a million rows reads only the range: click row 999 000, scroll ten rows, ⇧-click row 999 010. The
/// selection holds 11 rows and the input reads 13 rows: the 11 of the range and one verification each of the clicked row and the
/// anchor (the plan counted 12; the cache verifies both ends). Mutation: drop the position cache (`index` always scans), which
/// reads about a million rows.
@Test @MainActor func aShiftClickAcrossAMillionRowsReadsOnlyTheRange() async throws {
    let model = TableSel()
    let data = CountingRows(1_000_000)
    let w = try selectableTable(model: model, data: data)
    try await w.runUntilIdle()
    try await scrollTable(w, x: 0, y: 999_000 * 24)
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    try #require(model.multi == [999_000], "the first click selected row 999 000: \(model.multi)")
    try await scrollTable(w, x: 0, y: 10 * 24)
    data.resetCounts()
    rawClick(w, at: rowPoint(0), modifiers: .shift)
    let reads = data.subscriptReads
    try await w.runUntilIdle()
    #expect(model.multi == Set(999_000...999_010), "selected \(model.multi.count)")
    #expect(reads == 13, "input reads \(reads)")
}

/// **N3** A key move with nothing selected reads one row. Click row 0, empty the selection from outside (the stored lead is no
/// longer selected), press ↓: row 0 is selected and the input reads at most two rows. Mutation: remove the `firstSelected` hook
/// (the controller then scans a million rows for a selected one).
@Test @MainActor func aKeyMoveWithNothingSelectedReadsOneRow() async throws {
    let model = TableSel()
    let data = CountingRows(1_000_000)
    let w = try selectableTable(model: model, data: data)
    try await w.runUntilIdle()
    w.click(at: rowPoint(5)); try await w.runUntilIdle()
    model.multi = []
    try await w.runUntilIdle()
    data.resetCounts()
    model.multiWrites = []
    let handled = rawKey(w, .downArrow)
    let reads = data.subscriptReads
    try await w.runUntilIdle()
    #expect(handled)
    #expect(model.multiWrites == [[0]], "writes \(model.multiWrites)")
    #expect(reads <= 2, "input reads \(reads)")
}

/// A cell whose content takes a double tap (G39): the selection click must still run under it.
@MainActor private func tapTable(model: TableSel, taps: TapCount) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(20), selection: model.multiBinding()) {
            TableColumn("A") { r in Text("a\(r.id)").frame(width: Pixels(80), height: Pixels(20)).onTapGesture(count: 2) { taps.value += 1 } }
                .width(Pixels(100))
        }
        .tableRowHeight(Pixels(24))
    }
}

@MainActor final class TapCount { var value = 0 }

/// **G39** A `Text.onTapGesture(count: 2)` in a cell does not swallow the selection click: a single click selects (`isSelectableRow`
/// on the row), and a double click selects once and fires the tap once. Mutation: do not mark the row `isSelectableRow`.
@Test @MainActor func aRowChildsDoubleTapDoesNotSwallowTheSelectionClick() async throws {
    let model = TableSel()
    let taps = TapCount()
    let w = try tapTable(model: model, taps: taps)
    try await w.runUntilIdle()
    w.click(at: Point(x: Pixels(30), y: Pixels(28 + 2 * 24 + 12)))
    w.advance(by: 1)
    try await w.runUntilIdle()
    #expect(model.multi == [2], "single click selected \(model.multi)")
    #expect(taps.value == 0, "a single click is no double tap")
    w.doubleClick(at: Point(x: Pixels(30), y: Pixels(28 + 4 * 24 + 12)))
    w.advance(by: 1)
    try await w.runUntilIdle()
    #expect(model.multi == [4], "double click selected \(model.multi)")
    #expect(taps.value == 1, "the double tap fired \(taps.value) times")
}

/// **N4** An accessibility selection names only realised rows: a realised row selects, a row the table did not realise refuses
/// the whole request, and the rows that select are exactly the ones the last build realised. Mutation: build `byRow` over every
/// row of the data (the unrealised rows then select).
@Test @MainActor func anAccessibilitySelectionNamesOnlyRealisedRows() async throws {
    let model = TableSel()
    let w = try selectableTable(rows: 1000, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3)); try await w.runUntilIdle()
    let body = try #require(w.window.focusedElement, "the clicked table holds the focus")
    let handler = try #require(w.window.lastFocusRegistry.actionHandler(for: body, type: ObjectIdentifier(AccessibilityRowSelection.self)),
                               "a selectable table registers the accessibility selection")
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    let realised = w.lastFrameWork.tableRowsRealized
    var selectable = 0
    for row in 0..<1000 {
        model.multi = []
        handler(AccessibilityRowSelection(rows: [GlobalElementID.child(of: body, at: 0, name: ElementID.forRow(row, keyed: false))]))
        if model.multi == [row] { selectable += 1 }
    }
    #expect(realised > 0 && selectable == realised, "realised \(realised), selectable \(selectable)")
    #expect(selectable < 40, "a window, not the data: \(selectable)")
}

/// A table over a model's rows, so a test can reorder them.
@MainActor @Observable final class SortedRows {
    var rows: [RowRef]
    init(_ n: Int) { rows = (0..<n).map { RowRef(id: $0) } }
}

/// **N5** The selection follows its id across a sort: select id 7 of 30, reverse the data, and the highlight is on id 7's new
/// position, and ↓ moves from there. Mutation: `ListRowSpace.index` trusts a cached position without verifying it (↓ then
/// moves from the stale position 7).
@Test @MainActor func theSelectionFollowsItsIDAcrossASort() async throws {
    let model = TableSel()
    let data = SortedRows(30)
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(data.rows, selection: model.multiBinding()) { selectableColumns() }.tableRowHeight(Pixels(24))
    }
    try await w.runUntilIdle()
    w.click(at: rowPoint(7)); try await w.runUntilIdle()
    #expect(model.multi == [7])
    data.rows.reverse()
    try await w.runUntilIdle()
    #expect(highlightedRows(w) == [22], "id 7 is at position 22 now: \(highlightedRows(w))")
    model.multiWrites = []
    w.typeKey(.downArrow); try await w.runUntilIdle()
    #expect(model.multiWrites == [[6]], "↓ from position 22 selects position 23, id 6: \(model.multiWrites)")
}
