import MetalUICore
import MetalUILayout

// A `Table`'s body inside its own scroller, and its pinned header (`TBL-E`, `TBL-I`, `TBL-J`, `TBL-K`, record 389).
//
// `TableBody` is what `Table`'s `ProposalScrollView([.horizontal, .vertical])` scrolls. It reads `data.count` once per build and
// `data[i]` once per realised row, resolves the columns (O(C), no element built), solves their widths, plans the two-axis window
// (`TableWindowPlanner`) and builds only the window's rows, cells and header. The header and the frozen cells are placed from the
// table's own CLAMPED offset, never the scroller's raw one (`TBL-E`): a wheel past either end never moves them for a frame.

private let zeroPoint = Point(x: Pixels(0), y: Pixels(0))

/// How a `Table` reads its data (`TBL-D`): the count once per build, an element by position once per realised row. Positions, not
/// indices, so nothing scans: a table over `CountingRows(1_000_000)` reads `count` once and `data[i]` for the window only.
struct TableSource<Value> {
    var count: @MainActor () -> Int
    var element: @MainActor (Int) -> Value

    @MainActor
    init<Data: RandomAccessCollection>(_ data: Data) where Data.Element == Value {
        count = { data.count }
        if Data.Index.self == Int.self, let start = data.startIndex as? Int {
            // `Collection.index(_:offsetBy:)` on a Strideable index range-checks against `endIndex`; reading by arithmetic keeps
            // a position read to the one subscript.
            element = { data[(start + $0) as! Data.Index] }
        } else {
            element = { data[data.index(data.startIndex, offsetBy: $0)] }
        }
    }
}

/// What the user changed about a table's columns (`TBL-L`): widths and order, keyed by column. Written only by the divider and
/// header drag handlers (PR D); read by every build.
struct TableColumnState: Equatable {
    var widths: [TableColumnKey: Double] = [:]
    var order: [TableColumnKey] = []
}

/// A table body's state at its own id (`TBL-L`), written through `withState(…, unchanged: sameEntry)` and never `write`, so a
/// settled table taints nothing and stays eligible inside an ancestor's retained subtree (`RW-I`).
struct TableViewState {
    var lastPlan: TableWindowPlan?

    static func sameEntry(_ a: TableViewState, _ b: TableViewState) -> Bool { a.lastPlan == b.lastPlan }
}

// MARK: - The body

struct TableBody<Value: Identifiable>: Element, ProposalElement {
    var source: TableSource<Value>
    var resolveColumns: @MainActor () -> [AnyTableColumn<Value>]
    var rowHeight: Double
    var frozenCount: Int
    var headerHeight: Double
    var columnState: TableColumnState

    struct Layout {
        var node: LayoutNodeID
        var plan: TableWindowPlan
        var index: ColumnExtentIndex
        var rowCount: Int
        var frozen: Int
        var values: EnvironmentValues
        var rows: [TableRowElement]
        var rowLayouts: [SingleElementLayout<TableRowElement>]
        var header: TableHeaderRow?
        var headerLayout: SingleElementLayout<TableHeaderRow>?
    }

    struct Prepaint {
        var rows: [Void?]
        var header: [TableHeaderCell.Prepaint?]?
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let frame = pass.frame
        // 1. `data.count`, once. 2. The columns: O(C), and no element is built.
        let rowCount = source.count()
        let columns = resolveColumns()
        frame.tableWork.columnsResolved += columns.count
        // 3. The display order: the frozen columns (the first declared), then the user's order, then new columns as declared.
        let frozen = Swift.min(Swift.max(0, frozenCount), columns.count)
        var ordered = Array(columns[0..<frozen])
        var rest = Array(columns[frozen...])
        if !columnState.order.isEmpty {
            var byKey: [TableColumnKey: AnyTableColumn<Value>] = [:]
            for column in rest { byKey[column.key] = column }
            var placed = Set<TableColumnKey>()
            for key in columnState.order {
                if let column = byKey[key], placed.insert(key).inserted { ordered.append(column) }
            }
            rest.removeAll { placed.contains($0.key) }
        }
        ordered.append(contentsOf: rest)
        // 4. The widths against last frame's viewport; 5. their prefix-sum index.
        let context = pass.scrollContext
        let viewportWidth = context?.along(.horizontal)?.viewportExtent ?? 0
        let widths = TableWidthSolver.resolve(ordered.map(\.width), overrides: ordered.map { columnState.widths[$0.key] },
                                              viewport: viewportWidth)
        let index = ColumnExtentIndex(widths: widths)
        // 6. The two-axis window. 7. The rows and cells are a window over the data (`ID-R`).
        let plan = TableWindowPlanner.plan(rowCount: rowCount, rowHeight: rowHeight, headerHeight: headerHeight, columns: index,
                                           frozenCount: frozen, context: context)
        frame.stateTable.noteWindowedParent(id)
        // 8. One environment push for every cell's `Text`: one line, tail truncation (`TBL-K`).
        let values = frame.scopedValues(applying: .transform { $0.lineLimit = 1; $0.truncationMode = .tail })
        let keyed = !(Value.ID.self is DescriptionInjectiveID.Type)
        var rows: [TableRowElement] = []
        var rowLayouts: [SingleElementLayout<TableRowElement>] = []
        var nodes: [ProposalNodeID] = []
        var header: TableHeaderRow?
        var headerLayout: SingleElementLayout<TableHeaderRow>?
        var cursor = 0
        frame.withEnvironment(values) {
            // 9. Each realised row reads `data[i]` once.
            for position in plan.rows {
                let value = source.element(position)
                frame.tableWork.dataReads += 1
                let alternate: Color? = position % 2 == 1 ? Color.surfaceSecondary : nil
                var cells: [AnyTableCell] = []
                var xs: [Double] = [], cellWidths: [Double] = []
                cells.reserveCapacity(plan.columns.count + frozen)
                for column in plan.columns {
                    let spec = ordered[column]
                    cells.append(spec.makeCell(value, spec.elementID))
                    xs.append(index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                for column in plan.frozen {
                    let spec = ordered[column]
                    let cell = spec.makeCell(value, spec.elementID)
                    cell.rowBackground = alternate ?? Color.background   // opaque over the scrolled cells (`TBL-K`)
                    cells.append(cell)
                    xs.append(plan.offsetX + index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                var row = TableRowElement(name: ElementID.forRow(value.id, keyed: keyed), cells: cells, xs: xs, widths: cellWidths,
                                          height: rowHeight, background: alternate)
                let (rowNodes, rowLayout) = row.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                rows.append(row)
                rowLayouts.append(rowLayout)
                nodes.append(contentsOf: rowNodes)
                frame.tableWork.cellsRealized += cells.count
            }
            // 10. The header, last: it prepaints and paints over the rows.
            if headerHeight > 0, !ordered.isEmpty {
                var cells: [TableHeaderCell] = []
                var xs: [Double] = [], cellWidths: [Double] = []
                for column in plan.columns {
                    let spec = ordered[column]
                    cells.append(TableHeaderCell(title: spec.title, name: spec.elementID, alignment: spec.alignment, paintsBackground: nil))
                    xs.append(index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                for column in plan.frozen {
                    let spec = ordered[column]
                    cells.append(TableHeaderCell(title: spec.title, name: spec.elementID, alignment: spec.alignment,
                                                 paintsBackground: Color.background))
                    xs.append(plan.offsetX + index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                var row = TableHeaderRow(cells: cells, xs: xs, widths: cellWidths, height: headerHeight)
                let (headerNodes, built) = row.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                header = row
                headerLayout = built
                nodes.append(contentsOf: headerNodes)
            }
        }
        // 11. The body's layout; 12. the counters.
        let node = pass.requestNativeLayout(
            TableBodyLayout(rowHeight: rowHeight, headerHeight: headerHeight, rowCount: rowCount, totalWidth: index.totalWidth,
                            viewportWidth: viewportWidth, firstRow: plan.rows.lowerBound, realisedRows: rows.count,
                            hasHeader: header != nil, offsetY: plan.offsetY),
            children: nodes)
        frame.tableWork.rowsRealized += rows.count
        if plan.mode == .cold { frame.tableWork.coldFrames += 1 }
        return (node, Layout(node: node.layoutNodeID, plan: plan, index: index, rowCount: rowCount, frozen: frozen, values: values,
                             rows: rows, rowLayouts: rowLayouts, header: header, headerLayout: headerLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Prepaint {
        let frame = pass.frame
        return frame.insideListRows {
            // `TBL-L`: the state is written through `withState(unchanged:)`, never `write`, so a settled table taints nothing.
            let plan = layout.plan
            pass.withState(id, initial: TableViewState(), unchanged: TableViewState.sameEntry) { $0.lastPlan = plan }
            // `TBL-I`: the plan this frame's resolved offsets and viewport give; not contained in the built one means one more
            // frame. A settled table asks for nothing.
            let fresh = TableWindowPlanner.fresh(rowCount: layout.rowCount, rowHeight: rowHeight, headerHeight: headerHeight,
                                                 columns: layout.index, frozenCount: layout.frozen,
                                                 scroller: frame.activeScrollerFrame)
            if !TableWindowPlanner.contains(plan, fresh) { frame.requestAnotherFrame() }
            @MainActor func run() -> Prepaint {
                frame.withEnvironment(layout.values) {
                    var result = Prepaint(rows: [], header: nil)
                    result.rows.reserveCapacity(layout.rows.count)
                    for i in layout.rows.indices {
                        result.rows.append(layout.rows[i].prepaintGroup(layout: &layout.rowLayouts[i], pass: &pass))
                    }
                    if var header = layout.header, var headerLayout = layout.headerLayout {
                        result.header = header.prepaintGroup(layout: &headerLayout, pass: &pass)
                        layout.header = header
                        layout.headerLayout = headerLayout
                    }
                    return result
                }
            }
            // `AB-X` rule 1: a cold frame publishes the table and no rows, and asks for a retry.
            if plan.mode == .cold, pass.collectsAccessibility {
                frame.requestAccessibilityRetry()
                return frame.withAccessibilitySuppressed(except: id) { run() }
            }
            return run()
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Prepaint,
                        pass: inout PaintPass) {
        let frame = pass.frame
        frame.withEnvironment(layout.values) {
            for i in layout.rows.indices {
                layout.rows[i].paintGroup(layout: &layout.rowLayouts[i], prepaint: &prepaint.rows[i], pass: &pass)
            }
            if var header = layout.header, var headerLayout = layout.headerLayout {
                header.paintGroup(layout: &headerLayout, prepaint: &prepaint.header, pass: &pass)
                layout.header = header
                layout.headerLayout = headerLayout
            }
        }
    }
}

/// The body's layout (`TBL-E`, `TBL-I`): it answers `(max(Σ widths, viewport width), header + count x rowHeight)` at any
/// proposal, places row `i` at `(0, header + i x rowHeight)` and the header at `(0, offset.y)`, the table's clamped offset.
///
/// **Not `Hashable`**, so it taints exactly its ancestors for the layout memo, as `LazyStackLayout` does (`LZ-F`): the realised
/// window is not a key.
struct TableBodyLayout: ProposalLayout {
    var rowHeight: Double
    var headerHeight: Double
    var rowCount: Int
    var totalWidth: Double
    var viewportWidth: Double
    /// The first realised row's position, and how many were realised.
    var firstRow: Int
    var realisedRows: Int
    var hasHeader: Bool
    /// The table's clamped vertical offset: the header's place in the content.
    var offsetY: Double

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: Swift.max(totalWidth, viewportWidth),
                                      height: headerHeight + rowHeight * Double(rowCount)))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for slot in 0..<Swift.min(realisedRows, subviews.count) {
            subviews[slot].place(at: Point(x: bounds.x, y: bounds.y + headerHeight + Double(firstRow + slot) * rowHeight),
                                 anchor: .topLeading, proposal: ProposedSize(width: bounds.width, height: rowHeight))
        }
        if hasHeader, subviews.count > realisedRows {
            subviews[realisedRows].place(at: Point(x: bounds.x, y: bounds.y + offsetY), anchor: .topLeading,
                                         proposal: ProposedSize(width: bounds.width, height: headerHeight))
        }
    }
}

/// A table's own frame (`TBL-E`): a table is greedy and self-scrolling, so it answers its proposal on each axis and 0 where it
/// has none (arm `G3`: a table in a vertical `ScrollView` is the proposed width by 0, and never realises every row).
struct TableFrameLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for index in subviews.indices {
            subviews[index].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading,
                                  proposal: ProposedSize(width: bounds.width, height: bounds.height))
        }
    }
}

// MARK: - The header

/// The pinned header row (`TBL-E`, `TBL-K`): an opaque band, its cells (scrolling first, frozen after), and a 1-point separator
/// under it. It registers an opaque background hitbox so a click never reaches a row under it.
struct TableHeaderRow: Element, ProposalElement {
    var cells: [TableHeaderCell]
    var xs: [Double]
    var widths: [Double]
    var height: Double

    var elementID: ElementID? { ElementID("$tableHeader") }

    struct Layout {
        var node: LayoutNodeID
        var cells: [SingleElementLayout<TableHeaderCell>]
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        pass.frame.stateTable.noteWindowedParent(id)   // `ID-R`: the cells are a window over the columns
        var cursor = 0
        var nodes: [ProposalNodeID] = []
        var layouts: [SingleElementLayout<TableHeaderCell>] = []
        for i in cells.indices {
            let (cellNodes, cellLayout) = cells[i].requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
            nodes.append(contentsOf: cellNodes)
            layouts.append(cellLayout)
        }
        let node = pass.requestNativeLayout(TableRowLayout(xs: xs, widths: widths, height: height), children: nodes)
        return (node, Layout(node: node.layoutNodeID, cells: layouts))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> [TableHeaderCell.Prepaint?] {
        pass.insertHitbox(bounds, id: id, opaque: true)
        var states: [TableHeaderCell.Prepaint?] = []
        for i in cells.indices { states.append(cells[i].prepaintGroup(layout: &layout.cells[i], pass: &pass)) }
        return states
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout [TableHeaderCell.Prepaint?],
                        pass: inout PaintPass) {
        pass.fill(bounds, color: pass.resolve(Color.background), cornerRadii: Corners(all: Pixels(0)))
        for i in cells.indices { cells[i].paintGroup(layout: &layout.cells[i], prepaint: &prepaint[i], pass: &pass) }
        let line = Bounds(origin: Point(x: bounds.origin.x, y: bounds.origin.y + bounds.size.height - Pixels(1)),
                          size: Size(width: bounds.size.width, height: Pixels(1)))
        pass.fill(line, color: pass.resolve(Color.separator), cornerRadii: Corners(all: Pixels(0)))
    }
}

/// One header cell: the title, and the divider at its trailing edge (`TBL-K`, `TBL-R`). Three element requests: the cell, the
/// label and the divider.
struct TableHeaderCell: Element, ProposalElement {
    var title: Text
    var name: ElementID
    var alignment: TableColumnAlignment
    /// A frozen header cell paints this under itself, so it is opaque over the scrolled cells it covers.
    var paintsBackground: Color?
    var label: LegacyContent<Text>?
    var divider = TableColumnDivider()

    var elementID: ElementID? { name }

    struct Layout {
        var node: LayoutNodeID
        var label: LegacyContent<Text>.GroupLayout
        var divider: SingleElementLayout<TableColumnDivider>
    }

    struct Prepaint {
        var label: LegacyContent<Text>.GroupPrepaint?
        var divider: Void?
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        var content = LegacyContent(title)
        let (labelNodes, labelLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        label = content
        let (dividerNodes, dividerLayout) = divider.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        let node = pass.requestNativeLayout(TableHeaderCellLayout(alignment: alignment, inset: TableMetrics.cellInset,
                                                                   dividerWidth: TableMetrics.dividerHitWidth),
                                            children: labelNodes + dividerNodes)
        return (node, Layout(node: node.layoutNodeID, label: labelLayout, divider: dividerLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Prepaint {
        var prepaint = Prepaint(label: nil, divider: nil)
        if var content = label {
            prepaint.label = content.prepaintGroup(layout: &layout.label, pass: &pass)
            label = content
        }
        prepaint.divider = divider.prepaintGroup(layout: &layout.divider, pass: &pass)
        return prepaint
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Prepaint,
                        pass: inout PaintPass) {
        if let paintsBackground {
            pass.fill(bounds, color: pass.resolve(paintsBackground), cornerRadii: Corners(all: Pixels(0)))
        }
        if var content = label, var held = prepaint.label {
            content.paintGroup(layout: &layout.label, prepaint: &held, pass: &pass)
            label = content
            prepaint.label = held
        }
        divider.paintGroup(layout: &layout.divider, prepaint: &prepaint.divider, pass: &pass)
    }
}

/// Places a header cell's label (aligned like the cells below it) and its divider (centred on the trailing edge).
struct TableHeaderCellLayout: ProposalLayout {
    var alignment: TableColumnAlignment
    var inset: Double
    var dividerWidth: Double

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        guard subviews.count == 2 else { return }
        let inner = ProposedSize(width: Swift.max(0, bounds.width - 2 * inset), height: bounds.height)
        let size = subviews[0].sizeThatFits(inner).size
        let x: Double
        if alignment.isTrailing {
            x = bounds.x + bounds.width - inset - size.width
        } else if alignment.isCentered {
            x = bounds.x + (bounds.width - size.width) / 2
        } else {
            x = bounds.x + inset
        }
        subviews[0].place(at: Point(x: x, y: bounds.y + (bounds.height - size.height) / 2), anchor: .topLeading, proposal: inner)
        subviews[1].place(at: Point(x: bounds.x + bounds.width - dividerWidth / 2, y: bounds.y), anchor: .topLeading,
                          proposal: ProposedSize(width: dividerWidth, height: bounds.height))
    }
}

/// The column divider (`TBL-R`): a 6-point hit area centred on the column's trailing edge, drawing a 1-point separator. PR B draws
/// it; PR D gives it the drag and the pointer.
struct TableColumnDivider: Element, ProposalElement {
    struct Layout { var node: LayoutNodeID }
    private struct LeafKey: Hashable {}

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let node = pass.requestNativeLeaf(key: LeafKey()) { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 6, height: proposal.height ?? 0))
        }
        return (node, Layout(node: node.layoutNodeID))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Void,
                        pass: inout PaintPass) {
        let line = Bounds(origin: Point(x: bounds.origin.x + (bounds.size.width - Pixels(1)) / 2, y: bounds.origin.y),
                          size: Size(width: Pixels(1), height: bounds.size.height))
        pass.fill(line, color: pass.resolve(Color.separator), cornerRadii: Corners(all: Pixels(0)))
    }
}
