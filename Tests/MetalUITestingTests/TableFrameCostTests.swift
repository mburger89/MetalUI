@testable import MetalUI
import Foundation
import MetalUITesting
import Testing

// What a window with no table costs (`TBL-M`, record 388; spec section 6). PR A adds `Frame.tableWork` and five public `FrameWork`
// fields, every one of them 0 in a window with no table, and two literals measured on master `91a9904e` BEFORE any change that
// stays unchanged afterwards. The table's own cost pins arrive with `Table` itself (PR B). Every count is read after
// `runUntilIdle` (off Darwin a dirty mark hops through a Task) and summed over `frameWork`, never `lastFrameWork`. The harness
// text system; windows kept alive.

@MainActor private final class DxLog { var lastBuiltDx: Float = -1; var builds = 0 }

/// `PointerDragFrameCostTests`' `WriterChip` (R5's fixture), restated here because that one is private.
private struct WriterChip: Component {
    let log: DxLog
    @State var dx: Float = 0
    var content: some ElementGroup {
        let _: Void = { log.lastBuiltDx = dx; log.builds += 1 }()
        VStack(spacing: 0) {
            Rectangle().frame(width: Pixels(200), height: Pixels(200))
                .gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { v in dx = Float(v.translation.width.value) })
            Rectangle().frame(width: Pixels(20 + dx), height: Pixels(10))
        }
    }
}

private struct PlainRow: Identifiable { let id: Int }

/// **T1** A window holding no table reports no table work, in any of the five fields, summed over every frame it took to
/// settle. Mutation: initialise `TableWork.coldFrames` to 1 (every build then counts a cold table frame).
@Test @MainActor func aWindowWithoutATableReportsNoTableWork() async throws {
    let w = try harnessWindow { Text("a") }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(all.builds > 0)
    #expect(all.tableRowsRealized == 0, "rows \(all.tableRowsRealized)")
    #expect(all.tableCellsRealized == 0, "cells \(all.tableCellsRealized)")
    #expect(all.tableColumnsResolved == 0, "columns \(all.tableColumnsResolved)")
    #expect(all.tableDataReads == 0, "reads \(all.tableDataReads)")
    #expect(all.tableColdFrames == 0, "cold \(all.tableColdFrames)")
}

/// **T2** A window with no table keeps its steady element requests: R5's `WriterChip` fixture costs 6 and a `List` of 40 rows at
/// `rowHeight` 28 in a 300-point `ScrollView` costs the literal below, both measured on master `91a9904e` before this PR touched
/// anything (`List.window` now forwards to `UniformWindow.lines`, unchanged). Mutation: `List.overscan = 3`, which moves the
/// `List` literal (more rows realised).
@Test @MainActor func aWindowWithoutATableKeepsItsSteadyRequests() async throws {
    let log = DxLog()
    let chip = try harnessWindow { Column { WriterChip(log: log) } }
    try await chip.runUntilIdle()
    chip.window.setNeedsRedraw(); chip.tick()
    let steady = chip.lastFrameWork.elementRequests
    print("TBL-M R5 literal: steady elementRequests \(steady)")
    #expect(steady == 6, "steady \(steady)")

    let list = try harnessWindow(size: sz(300, 300)) {
        ScrollView { List((0..<40).map(PlainRow.init), rowHeight: Pixels(28)) { r in Text("row \(r.id)") } }
            .frame(width: Pixels(300), height: Pixels(300))
    }
    try await list.runUntilIdle()
    list.window.setNeedsRedraw(); list.tick()
    let listSteady = list.lastFrameWork.elementRequests
    print("TBL-M List literal: steady elementRequests \(listSteady)")
    #expect(listSteady == 28, "list steady \(listSteady)")
}

// MARK: - The table's own cost (PR B, `TBL-M`; spec 4.4)

private struct EqCell: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text) }
}

/// A host whose table sits behind an `.equatable()` boundary: it never changes, so the whole table is replayable.
private struct TableHost: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Table(CountingRows(1_000_000)) {
            TableColumnForEach(0..<200) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
        }
        .tableRowHeight(Pixels(24))
        .frame(width: Pixels(800), height: Pixels(600))
    }
    static func == (l: TableHost, r: TableHost) -> Bool { true }
}

@MainActor private func steady(_ w: TestWindow) async throws -> FrameWork {
    try await w.runUntilIdle()
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    return w.lastFrameWork
}

@MainActor private func work(of step: () -> Void, in w: TestWindow) async throws -> FrameWork {
    w.resetFrameWork()
    step()
    try await w.runUntilIdle()
    return w.frameWork.reduce(FrameWork(), +)
}

/// **B6-0** An empty table (no rows, no columns) is the base `B`, `P`: the table, its scroller and its body. Measured once and pinned;
/// every other pin states itself against it (`B + 619` is the window's own cost).
private let emptyTableRequests = 2
private let emptyTablePaints = 2
/// A steady window's own cost at fixture `F` (spec 4.4): the header row 1, its 10 cells at 3 each, and 28 rows at 1 + 2 x 10.
private let windowRequests = 1 + 3 * 10 + 28 * (1 + 2 * 10)

@Test @MainActor func anEmptyTablesSteadyCostIsTheBase() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table([] as [RowRef]) { TableColumnForEach(0..<0) { (c: Int) in TableColumn("c\(c)") { (_: RowRef) in Text("x") } } }
    }
    let f = try await steady(w)
    print("TBL-M B: steady elementRequests \(f.elementRequests), elementPaints \(f.elementPaints)")
    #expect(f.elementRequests == emptyTableRequests, "B \(f.elementRequests)")
    #expect(f.elementPaints == emptyTablePaints, "P \(f.elementPaints)")
    #expect(f.builds == 1 && f.tableRowsRealized == 0 && f.tableCellsRealized == 0)
}

/// **B6-1** A steady frame at the steady offsets of a 10 000-row by 200-column table: one build, `B + 619` requests, `P + 619` paints
/// (pinned as the literal 621), 28 rows, 280 cells, 28 data reads. Mutation: a second divider per header cell (the divider built as
/// a wrapper with a second element), +10 requests and paints.
@Test @MainActor func aTablesSteadyFrameCostsItsWindow() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let f = try await steady(w)
    #expect(f.builds == 1)
    #expect(f.elementRequests == emptyTableRequests + windowRequests, "requests \(f.elementRequests)")
    #expect(f.elementPaints == 621, "paints \(f.elementPaints)")
    #expect(f.tableRowsRealized == 28 && f.tableCellsRealized == 280 && f.tableDataReads == 28,
            "rows \(f.tableRowsRealized) cells \(f.tableCellsRealized) reads \(f.tableDataReads)")
    #expect(f.tableColumnsResolved == 200, "columns resolved \(f.tableColumnsResolved)")
}

/// A settled table draws nothing: no frame, no build, and `runUntilIdle` returns. Mutation: `requestAnotherFrame()` unconditionally
/// in the body's prepaint, so the display link never sleeps and `runUntilIdle` throws `notIdle`.
@Test @MainActor func anIdleTableDrawsNothing() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    try await w.runUntilIdle()
    let drawn = w.framesDrawn
    w.resetFrameWork()
    try await w.runUntilIdle()
    #expect(w.framesDrawn == drawn, "frames drawn \(w.framesDrawn - drawn)")
    #expect(w.frameWork.reduce(0) { $0 + $1.builds } == 0)
}

/// One vertical wheel step (+24) is one build with the steady requests and cells. Mutation: build the header twice (the header
/// row requested again after the rows), +31 requests.
@Test @MainActor func aScrollStepCostsOneBuildAndTheSteadyRequests() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let step = try await work(of: { w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -24) }, in: w)
    #expect(step.builds == 1, "builds \(step.builds)")
    #expect(step.elementRequests == emptyTableRequests + windowRequests, "requests \(step.elementRequests)")
    #expect(step.tableCellsRealized == 280 && step.tableDataReads == 28)
}

/// One horizontal step (+100, a whole column) costs the same. Mutation: `TableWindow.columnOverscan = 2`: 12 columns, 336 cells.
@Test @MainActor func aHorizontalScrollStepCostsTheSame() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let step = try await work(of: { w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: -100, deltaY: 0) }, in: w)
    #expect(step.builds == 1, "builds \(step.builds)")
    #expect(step.elementRequests == emptyTableRequests + windowRequests, "requests \(step.elementRequests)")
    #expect(step.tableCellsRealized == 280, "cells \(step.tableCellsRealized)")
}

/// A frozen column joins the window: spec 4.4's row for it reads `B + 678`, which counted the frozen column on top of the unshifted
/// window (11 columns); the planner takes the frozen width out of the scrolling band (`TBL-H`, PR A's `frozenColumnsAreOutsideTheWindow
/// AndAlwaysPlanned`), so 1 frozen + 9 scrolling = 10 columns and the cost is the steady window's. Mutation: ignore the frozen
/// width in the band (11 columns, 308 cells).
@Test @MainActor func aFrozenColumnTablesWindowCostsTheSameAsAPlainOne() async throws {
    let w = try tableFixture(rows: 10_000, columns: 200, frozen: 1)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let f = try await steady(w)
    #expect(f.tableCellsRealized == 280, "cells \(f.tableCellsRealized)")
    #expect(f.elementRequests == emptyTableRequests + windowRequests, "requests \(f.elementRequests)")
}

/// **B6-6** A caller's `.equatable()` cell content replays translated on a scroll step: 27 surviving rows x 10 cells = 270 hits and
/// translations, the 10 cells of the new row miss, and the paints are the steady frame's less the 270 replayed cell paints. Mutation:
/// name the rows by their position in the window (`row<k>`) instead of their id: a row's cells change identity every step and nothing replays.
@Test @MainActor func equatableCellsReplayTranslatedOnAScrollStep() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(10_000)) {
            TableColumnForEach(0..<200) { c in TableColumn("c\(c)") { r in EqCell(text: "r\(r.id)c\(c)").equatable() }.width(Pixels(100)) }
        }.tableRowHeight(Pixels(24))
    }
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    let step = try await work(of: { w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -24) }, in: w)
    #expect(step.retainedTranslated == 270, "translated \(step.retainedTranslated), refused \(step.retainedTranslationRefusedReasons)")
    #expect(step.retainedHits == 270 && step.retainedMisses == 10, "hits \(step.retainedHits) misses \(step.retainedMisses)")
    #expect(step.elementPaints == 621 - 270, "paints \(step.elementPaints)")
}

/// **B6-7** A settled table inside an `.equatable()` parent replays: the second steady frame is a retained hit and the table's paints are
/// skipped. Mutation: `TableViewState.sameEntry` always false, so the body's state write taints every ancestor and nothing replays.
@Test @MainActor func aSettledTableInsideAnEquatableComponentReplays() async throws {
    let w = try harnessWindow(size: sz(800, 600)) { VStack(spacing: Pixels(0)) { TableHost().equatable() } }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    w.window.setNeedsRedraw(); w.tick()
    let f = w.lastFrameWork
    #expect(f.retainedHits >= 1, "hits \(f.retainedHits), ineligible \(f.retainedIneligibleReasons)")
    #expect(f.elementPaints == 0 && f.retainedSkippedPaints >= 500, "skipped paints \(f.retainedSkippedPaints), painted \(f.elementPaints)")
}

/// **B6-8** The work is the same at every size: 1 000 x 20 and 10 000 x 50 at the steady offsets give the same requests, paints, cells
/// and reads. Mutation: build the header cell of every column (an eager header), which moves requests with the column count.
@Test @MainActor func aTablesWorkIsTheSameFor10kBy50AsFor1kBy20() async throws {
    var seen: [(requests: Int, paints: Int, cells: Int, reads: Int)] = []
    for (rows, columns) in [(1_000, 20), (10_000, 50)] {
        let w = try tableFixture(rows: rows, columns: columns)
        try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
        let f = try await steady(w)
        seen.append((f.elementRequests, f.elementPaints, f.tableCellsRealized, f.tableDataReads))
    }
    #expect(seen[0] == seen[1], "1k x 20 \(seen[0]) against 10k x 50 \(seen[1])")
    #expect(seen[0].cells == 280 && seen[0].reads == 28)
}

/// **B6-9 (opt-in)** `METALUI_RUN_1M_TABLE_TEST=1 swift test --filter aTablesWorkIsTheSameFor1MBy200AsFor1kBy20`: 1 000 000 x 200 costs what
/// 1 000 x 20 does at the same offsets, and a 200-step sweep costs one build, 280 cells and 28 reads every step (the wall time per
/// step and the cold frame's are printed).
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_1M_TABLE_TEST"] == "1")) @MainActor
func aTablesWorkIsTheSameFor1MBy200AsFor1kBy20() async throws {
    let small = try tableFixture(rows: 1_000, columns: 20)
    try await scrollTable(small, x: steadyOffsets.x, y: steadyOffsets.y)
    let a = try await steady(small)
    let started = Date()
    let big = try tableFixture(rows: 1_000_000, columns: 200)
    try await big.runUntilIdle()
    print("TBL 1M x 200 cold frame and settle: \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    try await scrollTable(big, x: steadyOffsets.x, y: steadyOffsets.y)
    let b = try await steady(big)
    #expect(a.elementRequests == b.elementRequests && a.elementPaints == b.elementPaints
            && a.tableCellsRealized == b.tableCellsRealized && a.tableDataReads == b.tableDataReads,
            "1k x 20 (\(a.elementRequests), \(a.elementPaints), \(a.tableCellsRealized)) against 1M x 200 (\(b.elementRequests), \(b.elementPaints), \(b.tableCellsRealized))")
    let sweepStart = Date()
    for step in 0..<200 {
        let f = try await work(of: { big.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -24) }, in: big)
        #expect(f.builds == 1 && f.tableCellsRealized == 280 && f.tableDataReads == 28,
                "step \(step): builds \(f.builds), cells \(f.tableCellsRealized), reads \(f.tableDataReads)")
    }
    print("TBL 1M x 200 sweep: \(Int(Date().timeIntervalSince(sweepStart) * 1000 / 200)) ms per step")
}

// MARK: - The cost of input (PR C, `TBL-N`, `TBL-O`, `TBL-Q`; record 390)

/// A selectable (and, with `sorted`, sortable) table of 1 000 000 rows by 200 columns at the steady offsets, its first click done so
/// the table holds the focus.
@MainActor private func inputFixture(sorted: SortModel? = nil, model: TableSel = TableSel(), data: CountingRows) async throws -> TestWindow {
    let w: TestWindow
    if let sorted {
        w = try harnessWindow(size: sz(800, 600)) {
            Table(data, sortOrder: sorted.rowBinding()) {
                TableColumnForEach(0..<200) { c in
                    TableColumn("c\(c)", value: \RowRef.id) { r in Text("r\(r.id)c\(c)") }.width(Pixels(100))
                }
            }
            .tableRowHeight(Pixels(24))
        }
    } else {
        w = try harnessWindow(size: sz(800, 600)) {
            Table(data, selection: model.multiBinding()) {
                TableColumnForEach(0..<200) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
            }
            .tableRowHeight(Pixels(24))
        }
    }
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    return w
}

extension SortModel {
    @MainActor func rowBinding() -> Binding<[KeyPathComparator<RowRef>]> {
        Binding(get: { self.rowOrder }, set: { self.rowOrder = $0; self.rowWrites += 1 })
    }
}

/// **C-1** A selection change realises only the visible window: a click at the steady offsets is builds x 28 rows, 280 cells and 28
/// reads, plus the input's own reads, and the steady frame afterwards (a selected row) costs the unselected steady window's
/// requests. Mutation: scan the first 5000 rows for the highlight whenever the table selects.
@Test @MainActor func aSelectionChangeRealisesOnlyTheVisibleWindow() async throws {
    let data = CountingRows(1_000_000)
    let model = TableSel()
    let w = try await inputFixture(model: model, data: data)
    try await w.runUntilIdle()
    data.resetCounts()
    let f = try await work(of: { w.click(at: Point(x: Pixels(50), y: Pixels(28 + 12 + 5 * 24))) }, in: w)
    #expect(model.multi == [505], "selected \(model.multi)")
    #expect(f.tableRowsRealized == 28 * f.builds && f.tableCellsRealized == 280 * f.builds, "rows \(f.tableRowsRealized) cells \(f.tableCellsRealized) builds \(f.builds)")
    #expect(data.subscriptReads <= 28 * f.builds + 4, "reads \(data.subscriptReads) in \(f.builds) builds")
    let steadyAfter = try await steady(w)
    #expect(steadyAfter.elementRequests == emptyTableRequests + windowRequests, "requests \(steadyAfter.elementRequests)")
}

/// **C-2** A key move realises only the visible window: ↓ from row 505 at the steady offsets, then at most the same figures.
/// Mutation: as C-1.
@Test @MainActor func aKeyMoveRealisesOnlyTheVisibleWindow() async throws {
    let data = CountingRows(1_000_000)
    let model = TableSel()
    let w = try await inputFixture(model: model, data: data)
    w.click(at: Point(x: Pixels(50), y: Pixels(28 + 12 + 5 * 24)))
    try await w.runUntilIdle()
    data.resetCounts()
    let f = try await work(of: { w.typeKey(.downArrow) }, in: w)
    #expect(model.multi == [506], "selected \(model.multi)")
    #expect(f.tableRowsRealized == 28 * f.builds && f.tableCellsRealized == 280 * f.builds, "rows \(f.tableRowsRealized) cells \(f.tableCellsRealized)")
    #expect(data.subscriptReads <= 28 * f.builds + 4, "reads \(data.subscriptReads) in \(f.builds) builds")
}

/// **C-3** A sort click realises only the visible window and reads no row for itself. Mutation: as C-1 (in the layout, for a
/// table with a sort).
@Test @MainActor func aSortRealisesOnlyTheVisibleWindow() async throws {
    let data = CountingRows(1_000_000)
    let sorted = SortModel()
    let w = try await inputFixture(sorted: sorted, data: data)
    try await w.runUntilIdle()
    data.resetCounts()
    let f = try await work(of: { w.click(at: Point(x: Pixels(50), y: Pixels(14))) }, in: w)
    #expect(sorted.rowWrites == 1, "writes \(sorted.rowWrites)")
    #expect(f.tableRowsRealized == 28 * f.builds && f.tableCellsRealized == 280 * f.builds, "rows \(f.tableRowsRealized) cells \(f.tableCellsRealized)")
    #expect(data.subscriptReads == 28 * f.builds, "reads \(data.subscriptReads) in \(f.builds) builds")
}

/// **C-4** An idle selected table asks for no frame: after a click and a key, nothing is drawn while idle. Mutation:
/// `requestAnotherFrame()` in the body's prepaint whenever it is focusable (the display link never sleeps).
@Test @MainActor func anIdleSelectedTableAsksNoFrames() async throws {
    let data = CountingRows(1_000_000)
    let model = TableSel()
    let w = try await inputFixture(model: model, data: data)
    w.click(at: Point(x: Pixels(50), y: Pixels(28 + 12 + 5 * 24)))
    w.typeKey(.downArrow)
    try await w.runUntilIdle()
    let drawn = w.framesDrawn
    w.resetFrameWork()
    try await w.runUntilIdle()
    #expect(w.framesDrawn == drawn, "frames drawn while idle: \(w.framesDrawn - drawn)")
    #expect(w.frameWork.reduce(0) { $0 + $1.builds } == 0)
}

// MARK: - A sorted header costs nothing extra (record 392, "Fixes after merge")

/// **T-SORT** A sorted table's scroll steps cost what the same table unsorted costs, with no accessibility client attached: the
/// sort chevron is one more element in the header (the unsorted header has none), so the sorted figure is the unsorted one + 1
/// and not + 2. PR E's `.accessibilityHidden(true)` on the chevron wrapped it in a third, `AccessibilityModifier` element on every
/// build, whether or not a client collected (`TBL-T`: accessibility-only work costs nothing without a client). Alloy's guard of 285
/// became 286. Mutation: restore `Image(systemName: "chevron.down").accessibilityHidden(true)` in `TableHeaderCell`.
@Test @MainActor func aSortedHeaderCostsOnlyItsChevronWhileNoClientCollects() async throws {
    @MainActor func perStep(sorted: Bool) async throws -> [Int] {
        let model = SortModel()
        if sorted { model.order = [KeyPathComparator(\SortRow.name)] }
        let rows = (0..<10_000).map { SortRow(id: $0, name: "n\($0)", size: $0 % 5) }
        let w = try harnessWindow(size: sz(800, 600)) {
            Table(rows, sortOrder: model.binding()) {
                TableColumn("Name", value: \SortRow.name).width(Pixels(100))
                TableColumn("Size", value: \SortRow.size) { r in Text("\(r.size)") }.width(Pixels(100))
                TableColumn("Plain") { r in Text("p\(r.id)") }.width(Pixels(100))
            }
            .tableRowHeight(Pixels(24))
        }
        try await scrollTable(w, x: 0, y: 12000)
        var costs: [Int] = []
        for _ in 0..<4 {
            let step = try await work(of: { w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -24) }, in: w)
            costs.append(step.elementRequests)
        }
        return costs
    }
    let plain = try await perStep(sorted: false)
    let sorted = try await perStep(sorted: true)
    print("TBL-T sorted scroll: unsorted \(plain), sorted \(sorted)")
    #expect(sorted == plain.map { $0 + 2 }, "unsorted \(plain), sorted \(sorted)")
}
