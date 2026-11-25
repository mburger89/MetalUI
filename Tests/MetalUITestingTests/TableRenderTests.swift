@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// `Table`'s rendering (`TBL-E`, `TBL-F`, `TBL-G`, `TBL-J`, `TBL-K`, `TBL-V`, record 389): geometry, the two-axis window, the pinned header
// and frozen columns, truncation, alignment, identity and state. Every count is read after `runUntilIdle` (off Darwin a dirty mark
// hops through a Task) and summed over `frameWork`; the harness text system; windows kept alive. Each test names its mutation.

/// A table of two static columns, named `slot([0])` and `slot([1])`, so a cell's frame is `frames(ofID:)`'s.
@MainActor private func staticTable(rows: Int = 50, hidden: Bool = false) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(rows)) {
            TableColumn("A") { r in Text("a\(r.id)") }.width(Pixels(100))
            TableColumn("B") { r in Text("b\(r.id)") }.width(Pixels(100))
        }
        .tableRowHeight(Pixels(24))
    }
}

/// The frames of every element named for the `.element` column key `column` of a `TableColumnForEach` (a keyed name, so
/// `frames(ofID:)` cannot find it), top to bottom.
@MainActor private func cells(_ w: TestWindow, column: Int) -> [Bounds<Pixels>] {
    let name = PathComponent.named(ElementID.forColumn(.element([0], AnyHashable(column)), keyed: true))
    return w.window.testingElementBounds.filter { $0.key.component == name }.map(\.value).sorted {
        ($0.origin.y.value, $0.origin.x.value) < ($1.origin.y.value, $1.origin.x.value)
    }
}

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// `bounds` (recorded in content space, before the scroller's translation) in window space at `offset`.
private func inWindow(_ bounds: Bounds<Pixels>, scrolledBy offset: (x: Double, y: Double) = steadyOffsets) -> Bounds<Pixels> {
    box(bounds.origin.x.value - Float(offset.x), bounds.origin.y.value - Float(offset.y), bounds.size.width.value, bounds.size.height.value)
}

@MainActor private func settle(_ w: TestWindow) async throws {
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
}

/// **G1** The header is 28 high, rows are 24, and the header cell and row 0's cell of a column are the column's width (probe
/// `swiftui-table.swift` arm `G1`: header 28, row 24; the AppKit chrome's margins are not modelled). Mutation: `TableMetrics.headerHeight`
/// 0, so there is no header and the first frame is row 0's.
@Test @MainActor func aTableLaysOutHeaderAndRowsAtTheProbesMetrics() async throws {
    let w = try staticTable()
    try await settle(w)
    let frames = try w.frames(ofID: "slot([0])")
    try #require(frames.count >= 2)
    #expect(frames[0] == box(0, 0, 100, 28), "header cell \(frames[0])")
    #expect(frames[1] == box(0, 28, 100, 24), "row 0 cell \(frames[1])")
    let second = try w.frames(ofID: "slot([1])")[0]
    #expect(second == box(100, 0, 100, 28))
}

/// A table scrolled to row 500 and column 5 realises only the window, on both axes (spec 4.4's fixture `F`). Mutation: disable the
/// column window (every column realised): 28 x 200 = 5600 cells and `r500c20` exists.
@Test @MainActor func aScrolledTableRealisesOnlyTheWindowOnBothAxes() async throws {
    let w = try namedTableFixture(rows: 1_000_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    w.window.setNeedsRedraw(); w.tick()
    let work = w.lastFrameWork
    #expect(work.tableRowsRealized == steadyRows, "rows \(work.tableRowsRealized)")
    #expect(work.tableCellsRealized == steadyRows * steadyColumns, "cells \(work.tableCellsRealized)")
    _ = try w.frame(ofID: "r500c6")
    #expect(throws: (any Error).self) { _ = try w.frame(ofID: "r500c20") }
}

/// The header stays at the top of the viewport while the rows scroll under it, and scrolls across with the columns: at the steady
/// offsets header column 6 is at window x 0 y 0 and row 500's column 6 cell at (0, 28). Mutation: place the header at content
/// y 0 (not the clamped offset): it scrolls away and no header is at y 0.
@Test @MainActor func theHeaderStaysAtTheTopAndScrollsAcross() async throws {
    let w = try namedTableFixture(rows: 1_000_000, columns: 200)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    w.window.setNeedsRedraw(); w.tick()
    let column6 = cells(w, column: 6)
    let header = try #require(column6.first { $0.size.height == 28 })
    #expect(inWindow(header) == box(0, 0, 100, 28), "header \(inWindow(header))")
    let row = try #require(column6.first { inWindow($0).origin.y == 28 })
    #expect(inWindow(row) == box(0, 28, 100, 24), "row 500's cell \(inWindow(row))")
}

/// A wheel past the top banks a negative raw offset until prepaint clamps it; the table clamps it itself, so in the very frame the
/// wheel lands the header is still at y 0. Mutation: place the header from the scroller's raw offset: it sits at y -500.
@Test @MainActor func anOverscrolledWheelKeepsTheHeaderPinnedInTheSameFrame() async throws {
    let w = try namedTableFixture(rows: 1_000_000, columns: 200)
    try await w.runUntilIdle()
    w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: 500)
    let header = try #require(cells(w, column: 0).first { $0.size.height == 28 })
    #expect(header.origin.y == 0, "header y \(header.origin.y)")
}

/// A frozen column stays at the leading edge: at the steady offsets column 0's header and cell are at x 0, and the row holds the
/// frozen cell and the window (columns 6..<15) = 10 cells. Mutation: ignore the frozen width in the band, so the window
/// starts at column 5 and a row holds 11.
@Test @MainActor func aFrozenColumnStaysAtTheLeadingEdge() async throws {
    let w = try namedTableFixture(rows: 1_000_000, columns: 200, frozen: 1)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    w.window.setNeedsRedraw(); w.tick()
    let column0 = cells(w, column: 0)
    let header = try #require(column0.first { $0.size.height == 28 })
    #expect(inWindow(header) == box(0, 0, 100, 28), "frozen header \(inWindow(header))")
    #expect(column0.contains { inWindow($0).origin.y == 28 }, "row 500's frozen cell")
    #expect(column0.allSatisfy { inWindow($0).origin.x == 0 }, "every frozen cell at x 0")
    #expect(w.lastFrameWork.tableCellsRealized == steadyRows * 10, "cells \(w.lastFrameWork.tableCellsRealized)")
}

/// A frozen cell paints above the scrolled cell under it: at the steady offsets scrolled column 6 sits under frozen column 0, and
/// in draw order the frozen cell's background comes after the scrolled cell's glyphs and before its own. Mutation: paint the frozen
/// cells first, so no glyph at that place is below the background.
@Test @MainActor func aFrozenCellPaintsAboveTheScrolledCellUnderIt() async throws {
    let w = try namedTableFixture(rows: 1_000_000, columns: 200, frozen: 1)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    w.window.setNeedsRedraw(); w.tick()
    let scene = w.scene
    func position(_ kind: PrimitiveKind, _ index: Int) -> Int? {
        scene.drawList.firstIndex { $0.kind == kind && index >= $0.start && index < $0.start + $0.count }
    }
    // Row 500 sits at window y 28...52: its frozen cell's opaque background is the rect at (0, 28, 100, 24).
    let background = try #require(scene.rects.indices.first {
        let b = scene.rects[$0].bounds
        return b.origin.x == 0 && b.origin.y == 28 && b.size.width == 100 && b.size.height == 24
    })
    let at = try #require(position(.rect, background))
    let inRow = scene.glyphs.indices.filter {
        let b = scene.glyphs[$0].bounds
        return b.origin.y >= 28 && b.origin.y < 52 && b.origin.x < 100
    }
    let below = inRow.filter { (position(.glyph, $0) ?? Int.max) < at }
    let above = inRow.filter { (position(.glyph, $0) ?? -1) > at }
    #expect(!below.isEmpty, "the scrolled cell's glyphs are under the frozen background (run \(at))")
    #expect(!above.isEmpty, "the frozen cell's own glyphs are above it")
}

/// **T1** A long cell text truncates: in a 60-wide column the row's text is one line cut with an ellipsis (six glyphs: five letters and
/// the ellipsis, all inside the cell), so the whole window holds the header's six glyphs and these six. Mutation: drop the `lineLimit`
/// environment push, so the 40-point row holds two lines and the window holds about sixteen glyphs.
@Test @MainActor func aLongCellTextTruncatesWithAnEllipsis() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        // A 40-point row has room for two lines, so only the environment's line limit makes this one line: a 24-point row's
        // proposed height would cut the text to one line by itself.
        Table(CountingRows(1)) {
            TableColumn("Narrow") { _ in Text("abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz") }.width(Pixels(60))
        }
        .tableRowHeight(Pixels(40))
    }
    try await settle(w)
    let row = w.allGlyphs.filter { $0.bounds.origin.y >= 28 }
    #expect(!row.isEmpty)
    #expect(w.allGlyphs.count <= 14, "the header's glyphs and one truncated line: \(w.allGlyphs.count) glyphs")
    #expect(row.allSatisfy { $0.bounds.origin.x >= 0 && $0.bounds.origin.x + $0.bounds.size.width <= 60 },
            "every glyph within the 60-point cell")
    #expect(row.count < 26, "the string was cut (\(row.count) glyphs of 55)")
}

/// A trailing-aligned column puts its text's right edge at the cell's right edge less the 6-point inset. Mutation: ignore the
/// alignment, so the text sits at the leading inset.
@Test @MainActor func aTrailingAlignedColumnRightAlignsItsCells() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(3)) {
            TableColumn("N") { _ in Text("12").id("n") }.width(Pixels(100)).alignment(.trailing)
        }
    }
    try await settle(w)
    let text = try #require(try w.frames(ofID: "n").first)
    #expect(text.origin.x + text.size.width == 94, "right edge \(text.origin.x + text.size.width)")
}

/// **W2** Three columns of default width in 800 fill the row: each grows to a third and the row's background rect (row 1 is
/// tinted) is 800 wide. Mutation: skip the solver's fill pass, so the columns stay 100.
@Test @MainActor func aTableNarrowerThanItsViewportFillsTheRow() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(4)) {
            TableColumn("A") { r in Text("a\(r.id)") }
            TableColumn("B") { r in Text("b\(r.id)") }
            TableColumn("C") { r in Text("c\(r.id)") }
        }
    }
    try await settle(w)
    let a = try w.frames(ofID: "slot([0])")
    let third = Float(800.0 / 3.0)
    #expect(abs(a[0].size.width.value - third) < 0.5, "header cell A \(a[0])")
    let c = try w.frames(ofID: "slot([2])")
    #expect(abs(c[0].origin.x.value - 2 * third) < 1)
    let tinted = w.scene.rects.filter { $0.bounds.origin.y == 52 && $0.bounds.size.height == 24 }
    #expect(tinted.contains { $0.bounds.origin.x == 0 && $0.bounds.size.width == 800 }, "row 1's background \(tinted.map(\.bounds))")
}

/// **G1** `tableColumnHeaders(.hidden)` removes the header (probe `G1`'s 28-point header is gone): row 0 is at y 0 and no 28-high cell exists. Mutation: ignore the environment
/// value, so the header returns.
@Test @MainActor func tableColumnHeadersHiddenRemovesTheHeader() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5)) { TableColumn("A") { r in Text("a\(r.id)") }.width(Pixels(100)) }
            .tableColumnHeaders(.hidden)
    }
    try await settle(w)
    let frames = try w.frames(ofID: "slot([0])")
    #expect(frames.first == box(0, 0, 100, 24), "row 0 \(frames.first as Any)")
    #expect(frames.allSatisfy { $0.size.height == 24 }, "no header cell")
}

/// **G3** A table in a vertical `ScrollView` answers its proposed width by 0 (probe `G3`: the proposal, else 0), so it never
/// realises more than the cold slice. Mutation: answer `header + N x rowHeight`, which realises every one of its 1000 rows.
@Test @MainActor func aTableAtANilProposalAnswersTheProbesSize() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        ProposalScrollView(.vertical) {
            Table(CountingRows(1000)) { TableColumn("A") { r in Text("a\(r.id)") }.width(Pixels(100)) }.id("table")
        }
    }
    try await w.runUntilIdle()
    let table = try w.frame(ofID: "table")
    #expect(table.size == Size(width: Pixels(800), height: Pixels(0)), "\(table)")
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(w.frameWork.allSatisfy { $0.tableRowsRealized <= 32 }, "rows \(w.frameWork.map(\.tableRowsRealized))")
    #expect(all.tableRowsRealized > 0)
}

/// The first frame realises the cold slice (32 rows by 16 columns), the next exactly the window (26 x 9 at offset 0), and
/// `runUntilIdle` settles. Mutation: a cold slice of every row, so the first frame builds 1 000 000 rows' worth.
@Test @MainActor func aColdFirstFrameRealisesTheColdSliceThenTheWindow() async throws {
    let w = try tableFixture(rows: 1_000_000, columns: 200)
    try await w.runUntilIdle()
    let history = w.frameWork
    let first = try #require(history.first)
    #expect(first.tableColdFrames == 1 && first.tableRowsRealized == 32 && first.tableCellsRealized == 32 * 16,
            "first frame: cold \(first.tableColdFrames), rows \(first.tableRowsRealized), cells \(first.tableCellsRealized)")
    w.window.setNeedsRedraw(); w.tick()
    #expect(w.lastFrameWork.tableCellsRealized == 26 * 9, "settled cells \(w.lastFrameWork.tableCellsRealized)")
    #expect(w.lastFrameWork.tableColdFrames == 0)
}

@MainActor private final class StateLog { var seen: [String: Int] = [:] }

private struct CountingCell: Component {
    let label: String
    let log: StateLog
    @State var taps = 0
    var content: some ElementGroup {
        _ = log.seen[label] = taps
        Text("\(label)").id("cell-\(label)").onClick { taps += 1 }
    }
}

@MainActor @Observable private final class ColumnModel { var names = ["a", "b", "c"] }

/// **F1** A column set that changes keeps the surviving columns' cells' `@State`: a counter in row 0's column "b" survives
/// `[a, b, c]` becoming `[b, c, d]`, where the column moves from display position 1 to 0. (The probe could only measure an append in
/// SwiftUI itself; removal aborts it.) Mutation: key a column by its display position, so "b" takes position 0's key and starts at 0.
@Test @MainActor func aDynamicColumnSetKeepsSurvivingCellsState() async throws {
    let log = StateLog(), model = ColumnModel()
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5)) {
            TableColumnForEach(model.names, id: \.self) { name in
                TableColumn(name) { r in CountingCell(label: "\(name)\(r.id)", log: log) }.width(Pixels(100))
            }
        }
    }
    try await w.runUntilIdle()
    let b0 = try #require(try w.frames(ofID: "cell-b0").first)
    for _ in 0..<2 { w.click(at: Point(x: b0.origin.x + 2, y: b0.origin.y + 2)) }
    try await w.runUntilIdle()
    #expect(log.seen["b0"] == 2, "b0 counted \(log.seen["b0"] as Any)")
    model.names = ["b", "c", "d"]
    try await w.runUntilIdle()
    #expect(log.seen["b0"] == 2, "b0 after the change \(log.seen["b0"] as Any)")
    #expect(log.seen["d0"] == 0)
}

/// A cell's `@State` survives a horizontal excursion: a counter in column 0 clicked twice is 2 again after scrolling the table to
/// x 600 and back. Mutation: skip `noteWindowedParent` in the row, so a cell that left its position reads as vanished and loses its state.
@Test @MainActor func aCellsStateSurvivesAHorizontalExcursion() async throws {
    let log = StateLog()
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5)) {
            TableColumnForEach(0..<200) { c in
                TableColumn("c\(c)") { r in CountingCell(label: "r\(r.id)c\(c)", log: log) }.width(Pixels(100))
            }
        }
    }
    try await w.runUntilIdle()
    let first = try #require(try w.frames(ofID: "cell-r0c0").first)
    for _ in 0..<2 { w.click(at: Point(x: first.origin.x + 2, y: first.origin.y + 2)) }
    try await w.runUntilIdle()
    #expect(log.seen["r0c0"] == 2)
    try await scrollTable(w, x: 600, y: 0)
    #expect(log.seen["r0c0"] == 2, "scrolled away, last built as \(log.seen["r0c0"] as Any)")
    try await scrollTable(w, x: -600, y: 0)
    #expect(log.seen["r0c0"] == 2, "back, \(log.seen["r0c0"] as Any)")
}

/// A scrolled table mints no state entries for its cells: the state table is the same size at the origin and at the steady offsets
/// (cells are not `Box`es, so no `$anim` slot is minted per cell). Mutation: wrap each cell's content in a `Box` (+1 slot per cell).
@Test @MainActor func aScrolledTableMintsNoStateEntriesForItsCells() async throws {
    let w = try tableFixture(rows: 1_000_000, columns: 200)
    try await w.runUntilIdle()
    let atOrigin = w.window.stateTable.count
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    #expect(w.window.stateTable.count == atOrigin, "origin \(atOrigin), scrolled \(w.window.stateTable.count)")
}

/// A cell taller than its row is clipped to it (divergence 1105; `TBL-K`): a 100-point swatch in a 24-point row paints inside the row's
/// band, and a swatch that fits is not clipped at all (so a caller's `.equatable()` content can replay translated). Mutation: never
/// clip (the overflow test always false), so the swatch's mask is the viewport's.
@Test @MainActor func aCellTallerThanItsRowIsClippedToIt() async throws {
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(3)) {
            TableColumn("A") { _ in Color.red.frame(width: Pixels(50), height: Pixels(100)) }.width(Pixels(100))
            TableColumn("B") { _ in Color.blue.frame(width: Pixels(50), height: Pixels(10)) }.width(Pixels(100))
        }
    }
    try await settle(w)
    let tall = w.scene.rects.filter { $0.bounds.size.width == 50 && $0.bounds.size.height == 100 }
    #expect(tall.count == 3, "swatches \(tall.count)")
    #expect(tall.allSatisfy { $0.contentMask.size.height <= 24 }, "masks \(tall.map(\.contentMask.size.height))")
    let short = w.scene.rects.filter { $0.bounds.size.width == 50 && $0.bounds.size.height == 10 }
    #expect(short.count == 3 && short.allSatisfy { $0.contentMask.size.height > 24 }, "a swatch that fits is not clipped")
}

/// **L1** A right-to-left table mirrors like SwiftUI's (probe `L1`: the first column is the rightmost): the layout engine mirrors a
/// custom layout's placements, so the columns, the scroller's origin and the window agree with no table code. Twenty columns of 100 in
/// 600: the first column is right of the second, the table opens at its leading (right) edge showing columns 0...5, and after scrolling
/// to the far end the viewport is still full (six columns across it, no blank band). Mutation: mirror the cells' placement a second time
/// in `TableRowLayout`, so the columns run left to right under a mirrored scroller.
@Test @MainActor func aRightToLeftTableMirrorsItsColumnsAndWindowsThemOnTheScroll() async throws {
    let w = try harnessWindow(size: sz(600, 300)) {
        Table(CountingRows(5)) {
            TableColumnForEach(0..<20) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)").id("r\(r.id)c\(c)") }.width(Pixels(100)) }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
    try await settle(w)
    func columnsOnScreen() -> Set<Int> {
        Set(w.allGlyphs.filter { $0.bounds.origin.y >= 28 && $0.bounds.origin.y < 52 && $0.bounds.origin.x >= 0 }
            .map { Int($0.bounds.origin.x) / 100 })
    }
    let first = try w.frame(ofID: "r0c0"), second = try w.frame(ofID: "r0c1")
    #expect(first.origin.x > second.origin.x, "c0 at \(first.origin.x), c1 at \(second.origin.x)")
    #expect(columnsOnScreen().isSuperset(of: [0, 1, 2, 3, 4, 5]), "at open: \(columnsOnScreen().sorted())")
    for _ in 0..<4 {
        w.scroll(at: Point(x: Pixels(300), y: Pixels(150)), byDeltaX: 900, deltaY: 0)
        try await w.runUntilIdle()
        w.window.setNeedsRedraw(); w.tick()
    }
    #expect(columnsOnScreen().isSuperset(of: [0, 1, 2, 3, 4, 5]), "at the far end: \(columnsOnScreen().sorted())")
    #expect(w.lastFrameWork.tableCellsRealized > 0)
}
