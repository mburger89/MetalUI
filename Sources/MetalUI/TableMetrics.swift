// A table's measured constants (`TBL-V`). Provisional in PR A (the plan's values); the probe's arms `G1`, `G2`, `W1` and `W4`
// replace them in PR B's task B0.

/// A table's constants, in points.
enum TableMetrics {
    /// The uniform row height (`tableRowHeight` overrides it).
    static let rowHeight = 24.0
    /// The pinned header's height.
    static let headerHeight = 28.0
    /// A column's width when it declares neither `ideal` nor a fixed width.
    static let defaultWidth = 100.0
    /// A column's minimum width when it declares none.
    static let defaultMinWidth = 20.0
    /// The inset between a cell's edge and its content on each side.
    static let cellInset = 6.0
    /// The column divider's hit-area width, centred on the column's trailing edge.
    static let dividerHitWidth = 6.0
    /// A header drag shorter than this is a sort click, not a reorder.
    static let reorderThreshold = 3.0
}
