import MetalUICore

// The table's two-axis window (`TBL-I`, `TBL-E`, `TBL-H`). Pure arithmetic over a `ScrollContext` pair (layout) or a
// `ScrollerFrame` pair (prepaint): no element, no state, no data read.

/// The table's own window constants; rows reuse `LazyWindow.overscan` and `LazyWindow.coldLines`.
enum TableWindow {
    /// Columns realised beyond the viewport on each side.
    static let columnOverscan = 1
    /// Columns a cold frame (the viewport not yet known) realises.
    static let coldColumns = 16
}

/// What a width change looks like to the staleness check (`TBL-I`): a different count, total or frozen width is a stale plan.
struct TableWidthsDigest: Equatable {
    var count: Int
    var totalWidth: Double
    var frozenWidth: Double
}

/// A window decision: the rows and columns to realise, and the clamped offsets the pins are placed from (`TBL-E`).
struct TableWindowPlan: Equatable {
    /// `.bounded` or `.cold`; never `.unbounded`, because the table owns its scroller.
    var mode: LazyPlanMode
    /// Rows to realise.
    var rows: Range<Int>
    /// Display positions of the scrolling columns to realise: the window, excluding the frozen ones.
    var columns: Range<Int>
    /// The frozen columns, `0..<f`: always realised.
    var frozen: Range<Int>
    /// The raw offsets clamped into the content: what the header and frozen cells are placed from.
    var offsetX: Double
    var offsetY: Double
    /// The viewport, one frame stale at layout and this frame's at prepaint.
    var viewportWidth: Double
    var viewportHeight: Double
    var digest: TableWidthsDigest
}

extension ScrollContext {
    /// A two-axis context: `axis` and the first two numbers are the primary (vertical) axis, `cross` the horizontal slot (`XS-H`).
    init(offset: Double, viewportExtent: Double, axis: ScrollAxis, cross: ScrollAxisContext?) {
        self.init(offset: offset, viewportExtent: viewportExtent, axis: axis)
        self.cross = cross
    }
}

enum TableWindowPlanner {
    /// The layout-time plan from the ambient contexts: the primary (vertical) one and `.along(.horizontal)` (`XS-H`). A nil
    /// context, or either viewport still 0, is cold.
    static func plan(rowCount: Int, rowHeight: Double, headerHeight: Double, columns: ColumnExtentIndex,
                     frozenCount: Int, context: ScrollContext?) -> TableWindowPlan {
        let vertical = context?.axis == .vertical ? context : nil
        let horizontal = context?.along(.horizontal)
        return make(rowCount: rowCount, rowHeight: rowHeight, headerHeight: headerHeight, columns: columns,
                    frozenCount: frozenCount,
                    vertical: vertical.map { ($0.offset, $0.viewportExtent) },
                    horizontal: horizontal.map { ($0.offset, $0.viewportExtent) })
    }

    /// The prepaint-time plan from the active scroller's frame: the resolved offsets and this frame's viewport.
    static func fresh(rowCount: Int, rowHeight: Double, headerHeight: Double, columns: ColumnExtentIndex,
                      frozenCount: Int, scroller: ScrollerFrame?) -> TableWindowPlan {
        let vertical = scroller?.axis == .vertical ? scroller : nil
        let horizontal = scroller?.along(.horizontal)
        return make(rowCount: rowCount, rowHeight: rowHeight, headerHeight: headerHeight, columns: columns,
                    frozenCount: frozenCount,
                    vertical: vertical.map { ($0.offset, $0.viewportExtent) },
                    horizontal: horizontal.map { ($0.offset, $0.viewportExtent) })
    }

    /// Whether `built` serves `fresh`: the fresh rows and columns lie inside the built ones, the widths digest and the frozen
    /// range are equal, and the clamped offsets (the pins) are equal. A cold plan was a guess made before the viewport was
    /// known (`LZ-E`), so it never contains a bounded one.
    static func contains(_ built: TableWindowPlan, _ fresh: TableWindowPlan) -> Bool {
        if built.mode == .cold && fresh.mode != .cold { return false }
        guard built.digest == fresh.digest, built.frozen == fresh.frozen,
              built.offsetX == fresh.offsetX, built.offsetY == fresh.offsetY else { return false }
        return within(fresh.rows, built.rows) && within(fresh.columns, built.columns)
    }

    private static func within(_ inner: Range<Int>, _ outer: Range<Int>) -> Bool {
        inner.isEmpty || (outer.lowerBound <= inner.lowerBound && inner.upperBound <= outer.upperBound)
    }

    private static func make(rowCount: Int, rowHeight: Double, headerHeight: Double, columns: ColumnExtentIndex,
                             frozenCount: Int, vertical: (offset: Double, viewport: Double)?,
                             horizontal: (offset: Double, viewport: Double)?) -> TableWindowPlan {
        let f = Swift.min(Swift.max(0, frozenCount), columns.count)
        let frozenWidth = columns.offset(of: f)
        let digest = TableWidthsDigest(count: columns.count, totalWidth: columns.totalWidth, frozenWidth: frozenWidth)
        guard let vertical, let horizontal, vertical.viewport > 0, horizontal.viewport > 0 else {
            return TableWindowPlan(mode: .cold, rows: 0..<Swift.min(LazyWindow.coldLines, rowCount),
                                   columns: f..<Swift.max(f, Swift.min(columns.count, TableWindow.coldColumns)),
                                   frozen: 0..<f, offsetX: 0, offsetY: 0,
                                   viewportWidth: horizontal?.viewport ?? 0, viewportHeight: vertical?.viewport ?? 0,
                                   digest: digest)
        }
        let contentHeight = headerHeight + rowHeight * Double(rowCount)
        // The table knows its content exactly, so it clamps the raw offsets itself: the pins never follow an overscroll.
        let offsetY = Swift.min(Swift.max(0, vertical.offset), Swift.max(0, contentHeight - vertical.viewport))
        let offsetX = Swift.min(Swift.max(0, horizontal.offset), Swift.max(0, columns.totalWidth - horizontal.viewport))
        let rows = rowHeight > 0 && rowCount > 0
            ? UniformWindow.lines(count: rowCount, extent: rowHeight, offset: offsetY,
                                  viewport: vertical.viewport - headerHeight, origin: 0, overscan: LazyWindow.overscan)
            : 0..<0
        // The scrolling columns window over the band after the frozen ones, intersected with `f..<C`.
        let band = columns.window(offset: offsetX + frozenWidth, viewport: horizontal.viewport - frozenWidth,
                                  overscan: TableWindow.columnOverscan)
        let first = Swift.max(f, band.lowerBound)
        return TableWindowPlan(mode: .bounded, rows: rows, columns: first..<Swift.max(first, band.upperBound),
                               frozen: 0..<f, offsetX: offsetX, offsetY: offsetY,
                               viewportWidth: horizontal.viewport, viewportHeight: vertical.viewport, digest: digest)
    }
}
