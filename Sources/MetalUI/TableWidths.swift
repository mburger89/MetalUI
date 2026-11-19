// Resolving a table's column widths (`TBL-G`): declared specs, the user's overrides and a fill rule. Pure arithmetic, run once per
// build over the columns' specs; no element is built.

/// What a column declares about its width.
struct TableColumnWidthSpec: Equatable {
    /// `width(x)`: the column is exactly `x`, ignores any override and is not resizable.
    var fixed: Double?
    var min: Double?
    var ideal: Double?
    var max: Double?
    /// Whether a user can resize the column.
    var isResizable: Bool { fixed == nil }
}

enum TableWidthSolver {
    /// The columns' widths in display order.
    ///
    /// 1. A fixed column is its `fixed`.
    /// 2. Otherwise the user override, else `ideal`, else `TableMetrics.defaultWidth`, clamped into
    ///    `[min ?? defaultMinWidth, max ?? ∞]`.
    /// 3. **Fill.** When the sum is below `viewport`, the surplus is split uniformly among the flexible columns (not fixed, not
    ///    overridden, below their max); a column that reaches its max drops out and the split repeats until the surplus or the
    ///    flexible columns run out (arm `W2`).
    /// 4. **No shrink.** A sum above `viewport` stays: the table scrolls across (arm `W3`).
    ///
    /// `overrides` is parallel to `specs`; a shorter array reads as nil past its end.
    static func resolve(_ specs: [TableColumnWidthSpec], overrides: [Double?], viewport: Double) -> [Double] {
        var widths = [Double]()
        widths.reserveCapacity(specs.count)
        var flexible = [Int]()
        for (i, spec) in specs.enumerated() {
            if let fixed = spec.fixed {
                widths.append(fixed)
                continue
            }
            let override = i < overrides.count ? overrides[i] : nil
            let wanted = override ?? spec.ideal ?? TableMetrics.defaultWidth
            let low = spec.min ?? TableMetrics.defaultMinWidth
            let clamped = Swift.min(Swift.max(wanted, low), spec.max ?? .infinity)
            widths.append(clamped)
            if override == nil { flexible.append(i) }
        }
        var surplus = viewport - widths.reduce(0, +)
        while surplus > 1e-9 {
            flexible.removeAll { widths[$0] >= (specs[$0].max ?? .infinity) }
            guard !flexible.isEmpty else { break }
            let share = surplus / Double(flexible.count)
            var given = 0.0
            for i in flexible {
                let add = Swift.min(share, (specs[i].max ?? .infinity) - widths[i])
                widths[i] += add
                given += add
            }
            surplus -= given
        }
        return widths
    }
}
