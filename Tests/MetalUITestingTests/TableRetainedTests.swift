@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// A table beside a redrawing sibling (`TBL-L`, record 394 "Fixes from Alloy"): a selectable or cell-mode table whose own inputs did not
// change replays retained, as a plain table does. Alloy measured about 250 element requests per frame for a selectable table next to
// a sibling editor, `stateWrite` the retained-ineligible reason. Each test sits the table behind an `.equatable()` boundary and
// bumps an `@Observable` counter that only a sibling `Text` reads, so each frame the sibling rebuilds and the table is a replay
// candidate. Counts, never time; the harness text system; windows kept alive.

@MainActor @Observable private final class Ticker { var n = 0 }

private enum RetainedKind { case plain, single, multi, cell }

private struct RetainedTableHost: Component, @MainActor Equatable {
    let kind: RetainedKind
    let sel: TableSel
    let cell: CellModel
    var content: some ElementGroup {
        switch kind {
        case .plain:
            Table(CountingRows(50)) { selectableColumns() }.tableRowHeight(Pixels(24))
        case .single:
            Table(CountingRows(50), selection: sel.singleBinding()) { selectableColumns() }.tableRowHeight(Pixels(24))
        case .multi:
            Table(CountingRows(50), selection: sel.multiBinding()) { selectableColumns() }.tableRowHeight(Pixels(24))
        case .cell:
            cellTableValue(data: CountingRows(50), columns: 4, model: cell, editable: false)
        }
    }
    static func == (l: RetainedTableHost, r: RetainedTableHost) -> Bool { true }
}

@MainActor private func siblingWindow(_ kind: RetainedKind, ticker: Ticker, sel: TableSel, cell: CellModel) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            Text("tick \(ticker.n)")
            RetainedTableHost(kind: kind, sel: sel, cell: cell).equatable()
        }
    }
}

/// The frame a sibling's change draws, after the table settled.
@MainActor private func siblingFrame(_ w: TestWindow, _ ticker: Ticker) async throws -> FrameWork {
    for _ in 0..<2 { ticker.n += 1; try await w.runUntilIdle() }
    w.resetFrameWork()
    ticker.n += 1
    try await w.runUntilIdle()
    return w.frameWork.reduce(FrameWork(), +)
}

private struct SiblingCost { let requests: Int; let rows: Int; let cells: Int; let reasons: [String: Int] }

@MainActor private func siblingCost(_ kind: RetainedKind, setUp: (TestWindow, TableSel, CellModel) async throws -> Void = { _, _, _ in }) async throws -> SiblingCost {
    let ticker = Ticker(), sel = TableSel(), cell = CellModel()
    let w = try siblingWindow(kind, ticker: ticker, sel: sel, cell: cell)
    try await w.runUntilIdle()
    try await setUp(w, sel, cell)
    let f = try await siblingFrame(w, ticker)
    #expect(f.builds >= 1, "the sibling drew")
    return SiblingCost(requests: f.elementRequests, rows: f.tableRowsRealized, cells: f.tableCellsRealized, reasons: f.retainedIneligibleReasons)
}

/// **F-1** A plain table beside a redrawing sibling realises nothing: the baseline the selectable cases are held to. Mutation: none (the
/// baseline); it is the figure the next tests compare against.
@Test @MainActor func aPlainTableBesideARedrawingSiblingReplays() async throws {
    let c = try await siblingCost(.plain)
    #expect(c.rows == 0 && c.cells == 0, "rows \(c.rows) cells \(c.cells), ineligible \(c.reasons)")
    #expect(c.reasons.isEmpty, "ineligible \(c.reasons)")
}

/// **F-2** A single-selection table replays as the plain one does: 0 rows, 0 cells, the same requests and no `stateWrite`. Mutation:
/// write the body's `TableViewState` with `write` in the body's prepaint (a write that does not compare).
@Test @MainActor func aSingleSelectionTableBesideARedrawingSiblingReplays() async throws {
    let base = try await siblingCost(.plain)
    let c = try await siblingCost(.single)
    #expect(c.rows == 0 && c.cells == 0, "rows \(c.rows) cells \(c.cells), ineligible \(c.reasons)")
    #expect(c.reasons["stateWrite"] == nil, "ineligible \(c.reasons)")
    #expect(c.requests == base.requests, "requests \(c.requests) against the plain table's \(base.requests)")
}

/// **F-3** The same for multi-selection, with a selection held.
@Test @MainActor func aMultiSelectionTableBesideARedrawingSiblingReplays() async throws {
    let base = try await siblingCost(.plain)
    let c = try await siblingCost(.multi) { _, sel, _ in sel.multi = [3, 4] }
    #expect(c.rows == 0 && c.cells == 0, "rows \(c.rows) cells \(c.cells), ineligible \(c.reasons)")
    #expect(c.reasons["stateWrite"] == nil, "ineligible \(c.reasons)")
    #expect(c.requests == base.requests, "requests \(c.requests) against the plain table's \(base.requests)")
}

/// **F-4** A focused selection table (a click gave it the focus, with a lead) asks no frame when idle, and beside a sibling it is
/// never refused (`stateWrite` was the old reason). A focused element under an occurrence is a counted miss by design (`SB-X`, as a
/// focused field is), so the table is rebuilt; the retained figure for the unfocused table is F-2/F-3's.
@Test @MainActor func aFocusedSelectionTableBesideARedrawingSiblingIsNeverRefused() async throws {
    var idleFrames = -1
    let c = try await siblingCost(.multi) { w, sel, _ in
        w.click(at: rowPoint(2))
        try await w.runUntilIdle()
        #expect(!sel.multi.isEmpty, "the click selected \(sel.multi)")
        let drawn = w.framesDrawn
        try await w.runUntilIdle()
        idleFrames = w.framesDrawn - drawn
    }
    #expect(idleFrames == 0, "idle frames \(idleFrames)")
    #expect(c.reasons.isEmpty, "ineligible \(c.reasons)")
}

/// **F-5** A cell-mode table with an active cell and no edit open, not focused, replays beside a sibling as the plain table does.
@Test @MainActor func aCellModeTableBesideARedrawingSiblingReplays() async throws {
    let base = try await siblingCost(.plain)
    let c = try await siblingCost(.cell) { _, _, cell in cell.active = TableCell(row: 2, column: 1) }
    #expect(c.rows == 0 && c.cells == 0, "rows \(c.rows) cells \(c.cells), ineligible \(c.reasons)")
    #expect(c.reasons.isEmpty, "ineligible \(c.reasons)")
    #expect(c.requests == base.requests, "requests \(c.requests) against the plain table's \(base.requests)")
}

/// **F-6** A focused cell-mode table (a click activated a cell) asks no frame when idle and is never refused beside a sibling.
@Test @MainActor func aFocusedCellModeTableBesideARedrawingSiblingIsNeverRefused() async throws {
    var idleFrames = -1
    let c = try await siblingCost(.cell) { w, _, cell in
        w.click(at: rowPoint(2, column: 1))
        try await w.runUntilIdle()
        #expect(cell.active != nil, "the click activated \(String(describing: cell.active))")
        let drawn = w.framesDrawn
        try await w.runUntilIdle()
        idleFrames = w.framesDrawn - drawn
    }
    #expect(idleFrames == 0, "idle frames \(idleFrames)")
    #expect(c.reasons.isEmpty, "ineligible \(c.reasons)")
}
