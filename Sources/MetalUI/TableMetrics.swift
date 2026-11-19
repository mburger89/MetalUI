// A table's measured constants (`TBL-V`), read from SwiftUI's `Table` by `docs/probes/swiftui-table.swift` (PR B, task B0): arm `G1` gave
// the row height 24, the header height 28 and the 6-point cell inset (a label at column x + 6); `W1` the default width 100 and `W4`
// the default minimum width 10. The divider hit area and the reorder threshold are MetalUI's own (no SwiftUI counterpart).

/// A table's constants, in points.
enum TableMetrics {
    /// The uniform row height (`tableRowHeight` overrides it).
    static let rowHeight = 24.0
    /// The pinned header's height.
    static let headerHeight = 28.0
    /// A column's width when it declares neither `ideal` nor a fixed width.
    static let defaultWidth = 100.0
    /// A column's minimum width when it declares none.
    static let defaultMinWidth = 10.0
    /// The inset between a cell's edge and its content on each side.
    static let cellInset = 6.0
    /// The column divider's hit-area width, centred on the column's trailing edge.
    static let dividerHitWidth = 6.0
    /// A header drag shorter than this is a sort click, not a reorder.
    static let reorderThreshold = 3.0
}
