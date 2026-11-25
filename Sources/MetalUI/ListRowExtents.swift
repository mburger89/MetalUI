/// A variable-height `List`'s row heights: a measured height or nothing per
/// data index, with prefix offsets in `O(log n)` (ruling `VL-D`).
///
/// **Two Fenwick (binary indexed) trees over the indices** — the measured
/// heights (`sums`) and how many rows are measured (`counts`) — so
///
///     offset(of: i) = measuredSum(i) + (i − measuredCount(i)) × estimate
///
/// and a changed estimate costs nothing. `index(containing:)` descends both
/// trees in lockstep. Every query and `record` is `O(log n)`; `rebuild(ids:)`
/// and `forgetMeasurements(width:)` are `O(n)` and happen only on a data change
/// or a width change (`VL-E`).
///
/// **The estimate** (`VL-C`, divergence 147): the declared estimate when the
/// caller passed one; else the running mean of every row measured at the
/// current width; else 24. The declared estimate is taken as given — the
/// caller (`List`) clamps a non-positive or non-finite one to nil (spec §3.1).
///
/// **Where it lives.** A reference held in `ListOrigin.extents` at the list's
/// own `StateTable` entry, created in `prepaint` inside a vertical scroller,
/// mutated in `requestLayout` (a rebuild) and `prepaint` (records), never in
/// paint and never through `StateTable.write` — so it raises no `isDirty` and
/// cannot keep the display link awake (`VL-D`).
///
/// **Work counters** for the performance pins: `nodeVisits` counts every
/// Fenwick node a query or `record` touches (one per descent step in
/// `index(containing:)`, whether or not the step's node is in range — so a
/// descent is exactly `⌊log₂ count⌋ + 1` visits), and `rebuilds` counts
/// `rebuild(ids:)` calls. `rebuild` and `forgetMeasurements` touch every row
/// and count no visits: their cost is `rebuilds` (or a width change), named.
final class RowExtentIndex<ID: Hashable> {
    /// The fallback estimate when nothing is declared and nothing is measured:
    /// SwiftUI's own (probe `R2`, `VL-C`).
    static var fallbackEstimate: Double { 24 }

    /// The number of rows — `data.count` at the last rebuild.
    private(set) var count: Int
    var isEmpty: Bool { count < 1 }
    /// The caller's `estimatedRowHeight`, already clamped (nil: not declared).
    let declaredEstimate: Double?
    /// The width every recorded height was measured at, set by
    /// `forgetMeasurements(width:)`; nil until the first call.
    private(set) var width: Double?

    /// Per row: the measured height, or NaN when unmeasured.
    private var heights: [Double]
    /// Per row: the id recorded there (by `record` or `rebuild`), or nil.
    /// **Kept by `forgetMeasurements`** (`VL-O` item 2): an id is not
    /// width-dependent.
    private var ids: [ID?]
    /// Fenwick tree, 1-based (`sums[0]` unused): measured heights.
    private var sums: [Double]
    /// Fenwick tree, 1-based: measured counts.
    private var counts: [Int32]
    /// The sum and number of measured heights — the running mean's terms,
    /// kept beside the trees so reading the estimate visits no node.
    private var measuredTotal = 0.0
    private var measuredCount = 0

    /// Fenwick nodes touched so far — a work counter.
    private(set) var nodeVisits = 0
    /// `rebuild(ids:)` calls so far — a work counter.
    private(set) var rebuilds = 0

    // MARK: The attempt's journal (`RK-AJ`)

    /// What a rolled-back attempt restores. `nil` outside an attempt, so a mutation pays one nil check.
    ///
    /// The index is a class held in a state entry, so the entry's undo log restores the reference and nothing else
    /// (`AttemptRestorable`). `record` logs the old height and id of a row it changes and the old value of every Fenwick node
    /// it touches, and a rollback puts them back in reverse order, so every sum is the same bits, not the same up to
    /// rounding. `rebuild` and `forgetMeasurements` replace or clear every array: the first of them moves the arrays as they
    /// stand into `snapshot` (O(n) and transient, on a data or width change only), and the records logged before it are
    /// undone over the snapshot at the rollback. A quiet frame journals nothing.
    private struct Journal {
        struct Row { let index: Int; let height: Double; let id: ID? }
        struct Node { let k: Int; let sum: Double; let count: Int32 }
        struct Snapshot {
            let count: Int
            let heights: [Double]
            let ids: [ID?]
            let sums: [Double]
            let counts: [Int32]
        }
        var rows: [Row] = []
        var nodes: [Node] = []
        var snapshot: Snapshot?
        /// How many of `rows` and `nodes` were logged before the snapshot (they are undone over it).
        var rowsBeforeSnapshot = 0
        var nodesBeforeSnapshot = 0
        let count: Int
        let width: Double?
        let measuredTotal: Double
        let measuredCount: Int
    }
    private var journal: Journal?
    /// The number of entries the open attempt has journalled (a test observable).
    var journalledWrites: Int { journal.map { $0.rows.count + $0.nodes.count + ($0.snapshot == nil ? 0 : 1) } ?? 0 }

    init(count: Int, declaredEstimate: Double?) {
        let count = Swift.max(0, count)
        self.count = count
        self.declaredEstimate = declaredEstimate
        heights = Array(repeating: .nan, count: count)
        ids = Array(repeating: nil, count: count)
        sums = Array(repeating: 0, count: count + 1)
        counts = Array(repeating: 0, count: count + 1)
    }

    /// What an unmeasured row counts as (`VL-C`).
    var estimate: Double {
        if let declaredEstimate { return declaredEstimate }
        if measuredCount > 0 { return measuredTotal / Double(measuredCount) }
        return Self.fallbackEstimate
    }

    /// The sum of every row: measured, else the estimate.
    var totalExtent: Double { offset(of: count) }

    /// The sum of rows `0..<index` (measured, else the estimate); `index` is
    /// clamped into `0...count`.
    func offset(of index: Int) -> Double {
        var k = Swift.min(Swift.max(index, 0), count)
        let rows = k
        var sum = 0.0
        var measured = 0
        while k > 0 {
            nodeVisits += 1
            sum += sums[k]
            measured += Int(counts[k])
            k -= k & -k
        }
        return sum + Double(rows - measured) * estimate
    }

    /// Row `index`'s height: measured, else the estimate.
    func extent(at index: Int) -> Double {
        guard heights.indices.contains(index), !heights[index].isNaN else { return estimate }
        return heights[index]
    }

    /// The row whose span `[offset(of: i), offset(of: i + 1))` holds `y` — a
    /// `y` exactly on a boundary belongs to the row below it — clamped into
    /// `0..<count` (negative → 0, past the end → the last row; empty → 0).
    func index(containing y: Double) -> Int {
        guard !isEmpty, y > 0 else { return 0 }
        let estimate = self.estimate
        var step = 1
        while step <= count / 2 { step <<= 1 }
        var position = 0
        var sum = 0.0
        var measured = 0
        while step > 0 {
            nodeVisits += 1
            let next = position + step
            if next <= count {
                let nextSum = sum + sums[next]
                let nextMeasured = measured + Int(counts[next])
                // The end of row `next − 1`: rows `0..<next`.
                if nextSum + Double(next - nextMeasured) * estimate <= y {
                    position = next
                    sum = nextSum
                    measured = nextMeasured
                }
            }
            step >>= 1
        }
        return Swift.min(position, count - 1)
    }

    /// Whether row `index` has a height measured at the current width.
    func isMeasured(_ index: Int) -> Bool {
        heights.indices.contains(index) && !heights[index].isNaN
    }

    /// The id recorded at `index`, or nil.
    func id(at index: Int) -> ID? {
        ids.indices.contains(index) ? ids[index] : nil
    }

    /// Records row `index`'s measured height and id, replacing any earlier
    /// height (`VL-E` item 1). A non-finite height or an index out of range is
    /// ignored (stored extents stay finite).
    func record(_ height: Double, at index: Int, id: ID) {
        guard heights.indices.contains(index), height.isFinite else { return }
        let old = heights[index]
        if journal != nil, journal?.snapshot == nil, !(old == height && ids[index] == id) {
            journal?.rows.append(.init(index: index, height: old, id: ids[index]))
        }
        ids[index] = id
        let sumDelta: Double
        let countDelta: Int32
        if old.isNaN {
            sumDelta = height
            countDelta = 1
            measuredCount += 1
        } else {
            sumDelta = height - old
            countDelta = 0
        }
        measuredTotal += sumDelta
        heights[index] = height
        guard sumDelta != 0 || countDelta != 0 else { return }
        var k = index + 1
        let journalling = journal != nil && journal?.snapshot == nil
        while k <= count {
            nodeVisits += 1
            if journalling { journal?.nodes.append(.init(k: k, sum: sums[k], count: counts[k])) }
            sums[k] += sumDelta
            counts[k] += countDelta
            k += k & -k
        }
    }

    /// Forgets every height (`VL-E` item 2: the width changed) and stores the
    /// new `width`. **Keeps the ids** (`VL-O` item 2).
    func forgetMeasurements(width: Double) {
        takeSnapshot()
        self.width = width
        for i in heights.indices { heights[i] = .nan }
        for i in sums.indices { sums[i] = 0 }
        for i in counts.indices { counts[i] = 0 }
        measuredTotal = 0
        measuredCount = 0
    }

    /// Rebuilds the index for new data `ids` (`VL-E` item 3): every height
    /// whose id is still present moves to its new index, the rest are dropped
    /// (and leave the mean); every row records its new id. Returns the new
    /// index of each id (the first occurrence, should the data repeat one).
    @discardableResult
    func rebuild<C: Collection>(ids newIDs: C) -> [ID: Int] where C.Element == ID {
        takeSnapshot()
        rebuilds += 1
        var measuredByID: [ID: Double] = [:]
        measuredByID.reserveCapacity(measuredCount)
        for i in heights.indices where !heights[i].isNaN {
            if let id = ids[i], measuredByID[id] == nil { measuredByID[id] = heights[i] }
        }
        let newCount = newIDs.count
        var lookup: [ID: Int] = [:]
        lookup.reserveCapacity(newCount)
        var newHeights = Array(repeating: Double.nan, count: newCount)
        var newIdentities: [ID?] = []
        newIdentities.reserveCapacity(newCount)
        var newSums = Array(repeating: 0.0, count: newCount + 1)
        var newCounts = Array(repeating: Int32(0), count: newCount + 1)
        var total = 0.0
        var measured = 0
        for (index, id) in newIDs.enumerated() {
            newIdentities.append(id)
            guard lookup[id] == nil else { continue }
            lookup[id] = index
            if let height = measuredByID[id] {
                newHeights[index] = height
                newSums[index + 1] = height
                newCounts[index + 1] = 1
                total += height
                measured += 1
            }
        }
        // The linear Fenwick construction: each node adds itself to its parent.
        if newCount > 0 {
            for k in 1...newCount {
                let parent = k + (k & -k)
                if parent <= newCount {
                    newSums[parent] += newSums[k]
                    newCounts[parent] += newCounts[k]
                }
            }
        }
        count = newCount
        heights = newHeights
        ids = newIdentities
        sums = newSums
        counts = newCounts
        measuredTotal = total
        measuredCount = measured
        return lookup
    }

    /// Moves the arrays as they stand into the journal, once per attempt, before the first call that replaces or clears them.
    private func takeSnapshot() {
        guard journal != nil, journal?.snapshot == nil else { return }
        guard var held = journal else { return }
        journal = nil   // the copy below is the only holder, so the arrays are not copied twice
        held.rowsBeforeSnapshot = held.rows.count
        held.nodesBeforeSnapshot = held.nodes.count
        held.snapshot = .init(count: count, heights: heights, ids: ids, sums: sums, counts: counts)
        journal = held
    }
}

extension RowExtentIndex: AttemptRestorable {
    func beginAttempt() {
        journal = Journal(count: count, width: width, measuredTotal: measuredTotal, measuredCount: measuredCount)
    }

    func rollbackAttempt() {
        guard let held = journal else { return }
        var rowsEnd = held.rows.count, nodesEnd = held.nodes.count
        if let snapshot = held.snapshot {
            count = snapshot.count
            heights = snapshot.heights
            ids = snapshot.ids
            sums = snapshot.sums
            counts = snapshot.counts
            rowsEnd = held.rowsBeforeSnapshot
            nodesEnd = held.nodesBeforeSnapshot
        }
        for row in held.rows[..<rowsEnd].reversed() {
            heights[row.index] = row.height
            ids[row.index] = row.id
        }
        for node in held.nodes[..<nodesEnd].reversed() {
            sums[node.k] = node.sum
            counts[node.k] = node.count
        }
        width = held.width
        measuredTotal = held.measuredTotal
        measuredCount = held.measuredCount
        journal = nil
    }

    func endAttempt() { journal = nil }

    var attemptContents: String {
        "count \(count) width \(String(describing: width)) total \(measuredTotal) measured \(measuredCount) heights \(heights) ids \(ids) sums \(sums) counts \(counts)"
    }
}
