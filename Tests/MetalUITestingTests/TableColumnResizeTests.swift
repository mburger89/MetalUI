@testable import MetalUI
import Foundation
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// Column resize (`TBL-R`, record 391; probe arms `R2`, `R3`) and the absence of reorder (`TBL-S`, arm `R1`). The fixture is `F` with
// every column `.width(min: 50, ideal: 100, max: 300)`; a column's width is read as the distance between two neighbouring cells'
// text (each is inset 6). Every count is read after `runUntilIdle` and summed over `frameWork`. Each test names its mutation.

private let headerY = Pixels(14)
private func at(_ x: Double, _ y: Pixels = headerY) -> Point<Pixels> { Point(x: Pixels(Float(x)), y: y) }

@MainActor private func mouseEvent(_ w: TestWindow, _ p: Point<Pixels>) -> MouseEvent {
    MouseEvent(position: p, modifiers: [], clickCount: 1, buttonNumber: 0, timestamp: w.now)
}
extension TestWindow {
    /// A raw press, move-while-pressed and release: no frame is drawn until the test runs one.
    @MainActor fileprivate func press(at p: Point<Pixels>) { send(.mouseDown(mouseEvent(self, p))) }
    @MainActor fileprivate func dragMove(to p: Point<Pixels>) { send(.mouseDragged(mouseEvent(self, p))) }
    @MainActor fileprivate func release(at p: Point<Pixels>) { send(.mouseUp(mouseEvent(self, p))) }
}

@MainActor @Observable private final class ColumnIDs {
    var ids: [Int]
    var tick = 0
    init(_ ids: [Int]) { self.ids = ids }
}

@MainActor @TableColumnBuilder<RowRef, Never> private func limitedColumns(_ ids: [Int]) -> TableColumnGroup<RowRef, Never> {
    TableColumnForEach(ids, id: \.self) { c in
        TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)").id("r\(r.id)c\(c)") }.width(min: Pixels(50), ideal: Pixels(100), max: Pixels(300))
    }
}

@MainActor private func limitedTable(columns: Int = 200, model: ColumnIDs? = nil) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(1000)) { limitedColumns(model?.ids ?? Array(0..<columns)) }.tableRowHeight(Pixels(24))
    }
}

/// Column `c`'s width: the distance from its cell's text to the next column's.
@MainActor private func x(_ w: TestWindow, _ id: String) -> Double { (try? w.frame(ofID: id)).map { Double($0.origin.x.value) } ?? -1 }
@MainActor private func width(_ w: TestWindow, column c: Int) -> Double { x(w, "r0c\(c + 1)") - x(w, "r0c\(c)") }

/// The width of column 0 after a drag of `dx` on its divider (at its trailing edge, x 100).
@MainActor private func widthAfterDrag(_ dx: Double) async throws -> Double {
    let w = try limitedTable()
    try await w.runUntilIdle()
    w.drag(from: at(100), to: at(100 + dx))
    try await w.runUntilIdle()
    return width(w, column: 0)
}

/// **R2/R3** A drag on a divider resizes its column and the limits hold: +40 gives 140, +400 gives the maximum 300 and -200 the
/// minimum 50. Mutation: no clamp, in the handler (`Swift.min(Swift.max(wanted, low), high)` replaced by `wanted`) AND in the solver's
/// override (`TableWidthSolver`): 500 and -100 (a column of negative width). Either clamp alone is not enough to redden it, as each
/// holds the width by itself; the handler's is pinned by `aResizeDragPastALimitDrawsNothingMore`.
@Test @MainActor func draggingADividerResizesItsColumnWithinItsLimits() async throws {
    let plus40 = try await widthAfterDrag(40), plus400 = try await widthAfterDrag(400), minus200 = try await widthAfterDrag(-200)
    #expect(plus40 == 140 && plus400 == 300 && minus200 == 50, "+40 \(plus40), +400 \(plus400), -200 \(minus200)")
}

/// Resizing a column moves the columns after it and nothing before it, and the cells below follow the header. Mutation: the
/// drag starts from the resolved width plus 10 (`drag.start = width + 10`): the widths are off by 10.
@Test @MainActor func resizingAColumnMovesOnlyTheColumnsAfterIt() async throws {
    let w = try limitedTable()
    try await w.runUntilIdle()
    w.drag(from: at(200), to: at(250))   // column 1's divider
    try await w.runUntilIdle()
    #expect(width(w, column: 0) == 100 && width(w, column: 1) == 150 && width(w, column: 2) == 100)
    #expect(x(w, "r5c2") == 256, "a row's cells follow the header: \(x(w, "r5c2"))")
}

/// **R2 / divergence 1111** In a table whose columns fill the viewport (four columns of ideal 100, max 300, in 800 points: 200 each),
/// a +40 drag on column 1's divider gives it 240 and the OTHER flexible columns each give back a third of the 40 (186.67); SwiftUI
/// takes the 40 from the last column (probe `R2`). Mutation: an overridden column stays flexible in the solver (`flexible.append(i)`
/// for every column): it takes a share of the fill and ends under 240.
@Test @MainActor func aResizeInAFilledTableSharesTheChangeAmongTheOtherColumns() async throws {
    let w = try limitedTable(columns: 4)
    try await w.runUntilIdle()
    let before = (0..<3).map { width(w, column: $0) }
    #expect(before == [200, 200, 200], "filled: \(before)")
    w.drag(from: at(400), to: at(440)); try await w.runUntilIdle()
    let after = (0..<3).map { width(w, column: $0) }
    #expect(abs(after[0] - 560.0 / 3) < 1 && after[1] == 240 && abs(after[2] - 560.0 / 3) < 1,
            "the dragged column 240, the others 186.67 (layout rounds to whole points): \(after)")
}

@MainActor private func mixedTable() throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(100)) {
            TableColumn("fixed") { r in Text("r\(r.id)c0").id("r\(r.id)c0") }.width(Pixels(100))
            TableColumn("free") { r in Text("r\(r.id)c1").id("r\(r.id)c1") }.width(min: Pixels(50), ideal: Pixels(100), max: Pixels(300))
            TableColumn("wide") { r in Text("r\(r.id)c2").id("r\(r.id)c2") }.width(min: Pixels(50), ideal: Pixels(100), max: Pixels(300))
            TableColumn("more") { r in Text("r\(r.id)c3").id("r\(r.id)c3") }.width(Pixels(1000))
        }.tableRowHeight(Pixels(24))
    }
}

/// **R3** A fixed-width column has no divider: no resize pointer at its trailing edge and a drag there changes nothing, while the
/// next column's divider has both. Mutation: give a fixed column a divider (drop the `isResizable` test where the header cell is made).
@Test @MainActor func aFixedWidthColumnHasNoDivider() async throws {
    let w = try mixedTable()
    try await w.runUntilIdle()
    w.hover(at: at(100))
    #expect(w.pointerStyle != .columnResize, "a fixed column's edge shows \(String(describing: w.pointerStyle))")
    w.drag(from: at(100), to: at(160))
    try await w.runUntilIdle()
    #expect(x(w, "r0c1") == 106, "nothing moved: \(x(w, "r0c1"))")
    w.hover(at: at(200))
    #expect(w.pointerStyle == .columnResize, "the next column's edge shows \(String(describing: w.pointerStyle))")
}

/// The divider shows the column-resize pointer over its 6 points, both sides of the edge (the right half lies over the next
/// column's header, so it must register above it), and nowhere else. Mutation: no pointer attachment on the divider.
@Test @MainActor func theDividerShowsTheColumnResizePointer() async throws {
    let w = try limitedTable()
    try await w.runUntilIdle()
    for x in [97.5, 100, 102.5] {
        w.hover(at: at(x))
        #expect(w.pointerStyle == .columnResize, "x \(x): \(String(describing: w.pointerStyle))")
    }
    w.hover(at: at(60))
    #expect(w.pointerStyle != .columnResize, "mid-cell: \(String(describing: w.pointerStyle))")
    w.hover(at: at(100, Pixels(100)))
    #expect(w.pointerStyle != .columnResize, "the divider is the header's, not the rows': \(String(describing: w.pointerStyle))")
}

/// **FP-U** A resize step of +5 is one build with the steady requests and cells, resolving every column once. Mutation: the build
/// counts its columns twice (`columnsResolved += columns.count * 2`): 400 resolved.
@Test @MainActor func aResizeDragStepCostsOneBuildAndTheSteadyRequests() async throws {
    let w = try limitedTable()
    try await w.runUntilIdle()
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    let steady = w.lastFrameWork
    w.hover(at: at(100))
    try await w.runUntilIdle()
    w.press(at: at(100))
    try await w.runUntilIdle()
    w.resetFrameWork()
    w.dragMove(to: at(105))
    try await w.runUntilIdle()
    let step = w.frameWork.reduce(FrameWork(), +)
    w.release(at: at(105))
    #expect(step.builds == 1, "builds \(step.builds)")
    #expect(step.elementRequests == steady.elementRequests, "requests \(step.elementRequests) against \(steady.elementRequests)")
    #expect(step.tableColumnsResolved == 200, "columns resolved \(step.tableColumnsResolved)")
    #expect(step.tableCellsRealized == steady.tableCellsRealized, "cells \(step.tableCellsRealized)")
}

/// **FP-U** A drag event that moves nothing draws nothing: the moves between a press and a release at the same point build no frame
/// (the press and the release are the gesture's own, `FP-U` record 386). Mutation: write unconditionally (drop the `clamped !=
/// drag.last` guard): one build per move.
@Test @MainActor func aResizeDragThatDoesNotMoveDrawsNothing() async throws {
    let w = try limitedTable()
    try await w.runUntilIdle()
    w.hover(at: at(100)); try await w.runUntilIdle()
    w.press(at: at(100)); try await w.runUntilIdle()
    w.resetFrameWork()
    for _ in 0..<3 { w.dragMove(to: at(100)); try await w.runUntilIdle() }
    let moves = w.frameWork.reduce(FrameWork(), +)
    w.release(at: at(100)); try await w.runUntilIdle()
    #expect(moves.builds == 0, "builds \(moves.builds), requests \(moves.elementRequests)")
    #expect(width(w, column: 0) == 100)
}

/// A drag against a limit already reached draws nothing more, while the pointer stays on the divider. Mutation: the same guard dropped.
@Test @MainActor func aResizeDragPastALimitDrawsNothingMore() async throws {
    let w = try limitedTable()
    try await w.runUntilIdle()
    w.drag(from: at(100), to: at(300)); try await w.runUntilIdle()   // +200: the maximum, 300
    #expect(width(w, column: 0) == 300)
    w.hover(at: at(300)); try await w.runUntilIdle()
    w.press(at: at(300)); try await w.runUntilIdle()
    w.resetFrameWork()
    w.dragMove(to: at(301)); try await w.runUntilIdle()
    w.dragMove(to: at(302)); try await w.runUntilIdle()
    let past = w.frameWork.reduce(FrameWork(), +)
    w.release(at: at(302)); try await w.runUntilIdle()
    #expect(past.builds == 0, "builds past the limit \(past.builds)")
    #expect(width(w, column: 0) == 300)
}

/// A resized width survives the parent running again and a column joining the set: its key is the column's, not its position.
/// Mutation: key the widths by the column's display position (`columnState.widths[index]`).
@Test @MainActor func aResizedWidthSurvivesARebuildAndAColumnSetChange() async throws {
    let model = ColumnIDs(Array(0..<20))
    let w = try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            Text("tick \(model.tick)")
            Table(CountingRows(1000)) { limitedColumns(model.ids) }.tableRowHeight(Pixels(24))
        }
    }
    try await w.runUntilIdle()
    // The table sits one text line (about 14) below the window's top; drag column 1's divider at x 200.
    let top = try w.frame(ofID: "r0c0").origin.y.value
    let y = Pixels(top - 28 + 14)
    w.drag(from: at(200, y), to: at(250, y)); try await w.runUntilIdle()
    #expect(width(w, column: 1) == 150, "resized: \(width(w, column: 1))")
    model.tick += 1; try await w.runUntilIdle()
    #expect(width(w, column: 1) == 150, "after a parent re-run: \(width(w, column: 1))")
    model.ids = [99] + Array(0..<20); try await w.runUntilIdle()
    #expect(width(w, column: 1) == 150 && width(w, column: 2) == 100, "after a column joined in front: c1 \(width(w, column: 1)) c2 \(width(w, column: 2))")
}

private struct SortedRow: Identifiable { let id: Int }

@MainActor @Observable private final class SortLog {
    var order: [KeyPathComparator<SortedRow>] = []
    @ObservationIgnored var writes = 0
}

@MainActor private func sortedColumnsTable(_ log: SortLog) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        Table((0..<100).map(SortedRow.init), sortOrder: Binding(get: { log.order }, set: { log.order = $0; log.writes += 1 })) {
            TableColumnForEach(0..<12) { c in
                TableColumn("c\(c)", value: \SortedRow.id) { r in Text("r\(r.id)c\(c)").id("r\(r.id)c\(c)") }
                    .width(min: Pixels(50), ideal: Pixels(100), max: Pixels(300))
            }
        }.tableRowHeight(Pixels(24))
    }
}

/// The divider's far half lies over the next column's sortable header, and a drag from it resizes without sorting; a click on the
/// header's body still sorts. Mutation: register the divider inside its own cell's prepaint (before the next cell registers its click).
@Test @MainActor func aDragOnTheDividersFarHalfResizesAndDoesNotSort() async throws {
    let log = SortLog()
    let w = try sortedColumnsTable(log)
    try await w.runUntilIdle()
    w.drag(from: at(102.5), to: at(142.5))
    try await w.runUntilIdle()
    #expect(log.writes == 0, "sort writes \(log.writes)")
    #expect(x(w, "r0c1") == 146, "column 0 is 140 wide: \(x(w, "r0c1"))")
    w.click(at: at(190)); try await w.runUntilIdle()
    #expect(log.writes == 1, "a header click sorts: \(log.writes)")
}

/// **R1** Headers do not reorder by default: SwiftUI's `allowsColumnReordering` is false without a column customisation, and MetalUI
/// has no switch (`TBL-S`). A drag from one header's body across two others moves no column and sorts nothing. Mutation: the body
/// swaps its first two display columns (`ordered.swapAt(0, 1)`), what a reorder that did happen would leave.
@Test @MainActor func headersDoNotReorderByDefault() async throws {
    let log = SortLog()
    let w = try sortedColumnsTable(log)
    try await w.runUntilIdle()
    w.drag(from: at(50), to: at(250))
    try await w.runUntilIdle()
    #expect(log.writes == 0, "a header drag is not a click: \(log.writes)")
    let xs = (0..<3).map { x(w, "r0c\($0)") }
    #expect(xs == [6, 106, 206], "the columns kept their places: \(xs)")
}

// MARK: - Beside a redrawing sibling

@MainActor @Observable private final class Ticker { var n = 0 }

private struct ResizedTableHost: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Table(CountingRows(50)) { limitedColumns(Array(0..<12)) }.tableRowHeight(Pixels(24))
    }
    static func == (l: ResizedTableHost, r: ResizedTableHost) -> Bool { true }
}

/// **FP-U** An unfocused table whose user resized a column still replays when a sibling redraws: 0 rows and 0 cells realised, nothing
/// refused (a plain per-build write of `columnState` made the table `stateWrite`-ineligible). Mutation: write `columnState` plainly
/// in `Table.requestProposalLayout` (`$columnState.wrappedValue = columnState`).
@Test @MainActor func aResizedTableBesideARedrawingSiblingReplays() async throws {
    let ticker = Ticker()
    let w = try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            Text("tick \(ticker.n)")
            ResizedTableHost().equatable()
        }
    }
    try await w.runUntilIdle()
    let top = try w.frame(ofID: "r0c0").origin.y.value
    let y = Pixels(top - 28 + 14)
    w.drag(from: at(100, y), to: at(140, y)); try await w.runUntilIdle()
    #expect(width(w, column: 0) == 140, "resized \(width(w, column: 0))")
    // The drag's hover leaves the pointer over the header; move it away so no hover redraw counts.
    w.exitPointer(); try await w.runUntilIdle()
    for _ in 0..<2 { ticker.n += 1; try await w.runUntilIdle() }
    w.resetFrameWork()
    ticker.n += 1
    try await w.runUntilIdle()
    let f = w.frameWork.reduce(FrameWork(), +)
    #expect(f.builds >= 1, "the sibling drew")
    #expect(f.tableRowsRealized == 0 && f.tableCellsRealized == 0, "rows \(f.tableRowsRealized) cells \(f.tableCellsRealized), ineligible \(f.retainedIneligibleReasons)")
    #expect(f.retainedIneligibleReasons.isEmpty, "ineligible \(f.retainedIneligibleReasons)")
}

// MARK: - Cell mode

/// **TCM-C/F** Resizing a column while a cell edit is open keeps the editor over its cell, with its text, and ends no edit: the
/// edited cell is column 1, whose own divider (x 200) and an earlier column's (x 100) are dragged. Mutation: the editor's frame is
/// not refreshed once it has one (`if let found, ..., session.lastFrame == nil`): it stays at its old x when column 0 widens.
@Test @MainActor func resizingWhileAnEditIsOpenKeepsTheEditorOverItsCell() async throws {
    let model = CellModel()
    let source = CountingRows(50)
    let w = try harnessWindow(size: sz(800, 600)) {
        cellTableValue(data: source, columns: 12, model: model, resizable: true)
    }
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 1)); try await w.runUntilIdle()
    let body = try #require(w.window.focusedElement, "the table is focused")
    let editorID = GlobalElementID.child(of: body, at: 0, name: tableEditorName)
    w.typeKey(KeyEquivalent(Character("\r"))); try await w.runUntilIdle()
    w.typeText("zz"); try await w.runUntilIdle()
    func editorFrame() throws -> Bounds<Pixels> { try #require(w.window.lastHitboxes.last { $0.id == editorID }, "the editor is realised").bounds }
    let before = try editorFrame()
    #expect(w.window.lastFocusRegistry.textTarget(for: editorID)?.text.hasSuffix("zz") == true)

    w.drag(from: at(100), to: at(140)); try await w.runUntilIdle()   // column 0 widens by 40
    let moved = try editorFrame()
    #expect(moved.origin.x.value == before.origin.x.value + 40 && moved.size.width.value == before.size.width.value,
            "the editor followed its column: \(before) -> \(moved)")
    #expect(model.editing == TableCell(row: 3, column: 1) && model.commits.isEmpty, "the edit is still open: editing \(String(describing: model.editing)), commits \(model.commits)")
    #expect(w.window.focusedElement == editorID, "the editor kept the focus")
    #expect(w.window.lastFocusRegistry.textTarget(for: editorID)?.text.hasSuffix("zz") == true, "the text is kept")

    w.drag(from: at(240), to: at(300)); try await w.runUntilIdle()   // the edited column's own divider: 140 + 100 = 240
    let grown = try editorFrame()
    #expect(grown.origin.x == moved.origin.x && grown.size.width.value == moved.size.width.value + 40, "the editor widened with its column (a 100 column holds the 120 minimum, so +60 is +40): \(moved) -> \(grown)")
    #expect(model.editing != nil && model.commits.isEmpty, "still editing")
}
