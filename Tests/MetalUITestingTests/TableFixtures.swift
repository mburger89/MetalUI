@testable import MetalUI
import MetalUITesting

// Shared fixtures for the `Table` lanes (`TBL-`, record 388 onward). PR A holds the data side only: `Table` itself arrives in PR B,
// which extends this file with `tableFixture(rows:columns:frozen:)` and `scrollTable(_:x:y:)`.

/// One row of a table's data: a cheap handle, as Sift's `RowRef { ordinal, source }` is (`TBL-D`).
struct RowRef: Identifiable, Hashable {
    let id: Int
}

/// A `RandomAccessCollection` over `0..<n` that counts every `count` and `subscript` read. A class, so the counts are shared by
/// every copy a `Table` retains. `Index == Int`; every read is O(1), as the row-source contract requires (`TBL-D`).
final class CountingRows: RandomAccessCollection {
    let n: Int
    private(set) var subscriptReads = 0
    private(set) var countReads = 0

    init(_ n: Int) { self.n = n }

    var startIndex: Int { 0 }
    var endIndex: Int { countReads += 1; return n }
    var count: Int { countReads += 1; return n }
    subscript(position: Int) -> RowRef {
        subscriptReads += 1
        return RowRef(id: position)
    }

    func resetCounts() { subscriptReads = 0; countReads = 0 }
}

/// The steady-frame fixture's scroll offsets (spec 4.4): row 500 at the top, column 6 at the left of a 100-wide column run.
let steadyOffsets: (x: Double, y: Double) = (x: 600, y: 12000)
/// The rows an 800 x 600 table with a 28-point header and 24-point rows realises at `steadyOffsets`: `498..<526`.
let steadyRows = 28
/// The columns it realises: `5..<15`.
let steadyColumns = 10

// MARK: - The table fixtures (PR B)

/// An 800 x 600 harness window holding `Table(CountingRows(rows))` with `columns` columns of 100 points of `Text("r<id>c<column>")`,
/// rows 24 high and the first `frozen` columns frozen: the steady-frame fixture `F` of spec 4.4 (`TBL-M`).
@MainActor
func tableFixture(rows: Int, columns: Int, frozen: Int = 0, data: CountingRows? = nil) throws -> TestWindow {
    let source = data ?? CountingRows(rows)
    return try harnessWindow(size: sz(800, 600)) {
        Table(source) {
            TableColumnForEach(0..<columns) { c in
                TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100))
            }
        }
        .tableRowHeight(Pixels(24))
        .tableFrozenColumns(frozen)
    }
}

/// `tableFixture` with every cell's `Text` named `r<id>c<column>` (`.id`), so a test finds a cell's frame by name.
@MainActor
func namedTableFixture(rows: Int, columns: Int, frozen: Int = 0) throws -> TestWindow {
    let source = CountingRows(rows)
    return try harnessWindow(size: sz(800, 600)) {
        Table(source) {
            TableColumnForEach(0..<columns) { c in
                TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)").id("r\(r.id)c\(c)") }.width(Pixels(100))
            }
        }
        .tableRowHeight(Pixels(24))
        .tableFrozenColumns(frozen)
    }
}

/// Scrolls the table by exactly `(x, y)` through two phaseless wheel events at its centre (one vertical, then one horizontal: a
/// diagonal goes wholly to the dominant axis, `XS-F`), then settles. Deltas are the platform's, so a positive offset step is a
/// negative delta.
@MainActor
func scrollTable(_ w: TestWindow, x: Double, y: Double) async throws {
    let centre = Point(x: Pixels(400), y: Pixels(300))
    if y != 0 { w.scroll(at: centre, byDeltaX: 0, deltaY: Float(-y)) }
    if x != 0 { w.scroll(at: centre, byDeltaX: Float(-x), deltaY: 0) }
    try await w.runUntilIdle()
}
