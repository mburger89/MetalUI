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
