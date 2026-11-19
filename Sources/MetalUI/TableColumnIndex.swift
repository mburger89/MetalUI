// A table's columns as prefix offsets (`TBL-H`). Widths are declared, never measured or estimated, so there is no anchor
// correction and nothing like `RowExtentIndex`: a rebuild is O(C) once per build, a lookup O(1) or O(log C).

/// The prefix offsets of a table's columns in display order.
struct ColumnExtentIndex: Equatable {
    /// `offsets[i]` is the leading edge of column `i`; `offsets[count]` is the total width.
    private var offsets: [Double]

    /// Builds the index from the columns' widths in display order. O(C).
    init(widths: [Double]) {
        var offsets = [Double]()
        offsets.reserveCapacity(widths.count + 1)
        var running = 0.0
        offsets.append(running)
        for width in widths {
            running += width
            offsets.append(running)
        }
        self.offsets = offsets
    }

    /// The number of columns.
    var count: Int { offsets.count - 1 }

    /// The sum of every width.
    var totalWidth: Double { offsets[offsets.count - 1] }

    /// The leading edge of column `index`, clamped into `0...count` (`count` answers the total width). O(1).
    func offset(of index: Int) -> Double { offsets[Swift.min(Swift.max(0, index), count)] }

    /// The width of column `index`; 0 outside `0..<count`. O(1).
    func width(at index: Int) -> Double {
        guard index >= 0, index < count else { return 0 }
        return offsets[index + 1] - offsets[index]
    }

    /// The largest `i` with `offset(of: i) <= x`, clamped into `0...count - 1` (0 when empty). O(log C).
    func index(containing x: Double) -> Int {
        guard count > 0 else { return 0 }
        // The first position whose offset is greater than x, minus one.
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if offsets[mid] <= x { low = mid + 1 } else { high = mid }
        }
        return Swift.min(Swift.max(0, low - 1), count - 1)
    }

    /// The smallest `i` in `0...count` with `offset(of: i) >= x`. O(log C).
    func firstIndex(startingAtOrAfter x: Double) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if offsets[mid] >= x { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// The columns intersecting `[offset, offset + viewport)`, widened by `overscan` on each side. The top is clamped into
    /// `0...max(0, totalWidth − viewport)` as `UniformWindow` clamps it, so for equal widths this is
    /// `UniformWindow.lines` over the same count.
    func window(offset: Double, viewport: Double, overscan: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let top = Swift.min(Swift.max(0, offset), Swift.max(0, totalWidth - viewport))
        let first = Swift.max(0, index(containing: top) - overscan)
        let last = Swift.min(count, firstIndex(startingAtOrAfter: top + viewport) + overscan)
        return first..<Swift.max(first, last)
    }
}
