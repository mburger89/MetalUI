import MetalUICore
import MetalUILayout

// A `Table`'s realised rows and cells (`TBL-J`, `TBL-K`, record 389). Both are internal `Element`s, not `Box`es, so none mints a
// `$anim` slot: a scrolled frame creates no state entries (`aScrolledTableMintsNoStateEntriesForItsCells`).

private let zeroPoint = Point(x: Pixels(0), y: Pixels(0))

// MARK: - A cell

/// One body cell (`TBL-K`): a column's content in a box of the column's width and the table's row height.
///
/// The content is proposed `(width - 2 x cellInset, rowHeight)` and aligned by the column's alignment. **A cell whose content is laid
/// out larger than the cell is clipped to it** in prepaint and paint, so it never reaches a neighbour (divergence 1105); a cell whose
/// content fits is not clipped at all. That is deliberate: a clip on the pass's stack is in the replay key's ambient and moves with
/// every scroll step, which would stop a caller's `.equatable()` cell content replaying translated (`FS-D`, `retainedTranslated`
/// 270 on a scroll step); content that fits cannot reach a neighbour, so the clip would only cost the replay. A frozen cell paints
/// the row's current background under its content (`paintsRowBackground`), so it is opaque over the scrolled cells it covers.
struct TableCellBox<Content: ElementGroup>: Element, ProposalElement {
    var content: LegacyContent<Content>
    var alignment: TableColumnAlignment
    /// The name of this cell in its row: the column's (`TBL-J`).
    var columnID: ElementID?
    var paintsRowBackground: Color?
    /// Cell mode's fill, ring and click (`TCM-D`, `TCM-I`); `nil` for every cell of a row table.
    var decor: TableCellDecor?

    var elementID: ElementID? { columnID }

    struct Layout {
        var node: LayoutNodeID
        var contentNodes: [LayoutNodeID]
        var content: LegacyContent<Content>.GroupLayout
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (nodes, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        let node = pass.requestNativeLayout(TableCellLayout(alignment: alignment, inset: TableMetrics.cellInset), children: nodes)
        return (node, Layout(node: node.layoutNodeID, contentNodes: nodes.map(\.layoutNodeID), content: contentLayout))
    }

    /// Whether any of the content's nodes reaches outside `bounds`: only then is the cell clipped.
    private static func overflows(_ bounds: Bounds<Pixels>, nodes: [LayoutNodeID], of boundsOf: (LayoutNodeID) -> Bounds<Pixels>) -> Bool {
        let right = bounds.origin.x.value + bounds.size.width.value, bottom = bounds.origin.y.value + bounds.size.height.value
        for node in nodes {
            let b = boundsOf(node)
            if b.origin.x.value < bounds.origin.x.value - 0.01 || b.origin.y.value < bounds.origin.y.value - 0.01
                || b.origin.x.value + b.size.width.value > right + 0.01 || b.origin.y.value + b.size.height.value > bottom + 0.01 {
                return true
            }
        }
        return false
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> LegacyContent<Content>.GroupPrepaint {
        // `TCM-D`: in cell mode a click lands on the cell, above its row's own hitbox.
        // Registered without a synthesized node: a clickable cell would publish as a button and fold its content's elements and
        // identifiers into one label; the click still lands, and the row it runs is the accessibility node that selects.
        if let handlers = decor?.handlers { pass.registerHandlers(handlers, at: bounds, id: id, synthesizesAccessibility: false) }
        guard Self.overflows(bounds, nodes: layout.contentNodes, of: { pass.bounds(of: $0) }) else {
            return content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        var result: LegacyContent<Content>.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: zeroPoint) {
            result = content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        return result
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout LegacyContent<Content>.GroupPrepaint, pass: inout PaintPass) {
        if let background = paintsRowBackground {
            pass.fill(bounds, color: pass.resolve(background), cornerRadii: Corners(all: Pixels(0)))
        }
        // `TCM-D` paint order inside a cell box: the row background above, then the caller's fill, the content, the ring.
        if let fill = decor?.fill {
            pass.fill(bounds, color: pass.resolve(fill), cornerRadii: Corners(all: Pixels(0)))
        }
        if Self.overflows(bounds, nodes: layout.contentNodes, of: { pass.bounds(of: $0) }) {
            pass.clipped(to: bounds, offsetBy: zeroPoint) {
                content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
            }
        } else {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
        if let ring = decor?.ring { Self.paintRing(ring, in: bounds, pass: &pass) }
    }

    /// The active ring (`TCM-D`): `width` points inside the box, as four fills.
    private static func paintRing(_ ring: TableCellRing, in bounds: Bounds<Pixels>, pass: inout PaintPass) {
        let color = pass.resolve(ring.color)
        let t = Pixels(Float(Swift.min(ring.width, Double(bounds.size.height.value) / 2, Double(bounds.size.width.value) / 2)))
        let x = bounds.origin.x, y = bounds.origin.y, w = bounds.size.width, h = bounds.size.height
        let square = Corners(all: Pixels(0))
        pass.fill(Bounds(origin: Point(x: x, y: y), size: Size(width: w, height: t)), color: color, cornerRadii: square)
        pass.fill(Bounds(origin: Point(x: x, y: y + h - t), size: Size(width: w, height: t)), color: color, cornerRadii: square)
        pass.fill(Bounds(origin: Point(x: x, y: y + t), size: Size(width: t, height: h - t - t)), color: color, cornerRadii: square)
        pass.fill(Bounds(origin: Point(x: x + w - t, y: y + t), size: Size(width: t, height: h - t - t)), color: color,
                  cornerRadii: square)
    }
}

/// Places a cell's content (`TBL-K`): proposed the cell's width less the insets and its height, aligned across the cell and
/// centred down it.
struct TableCellLayout: ProposalLayout {
    var alignment: TableColumnAlignment
    var inset: Double

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        let inner = ProposedSize(width: Swift.max(0, bounds.width - 2 * inset), height: bounds.height)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(inner).size
            let x: Double
            if alignment.isTrailing {
                x = bounds.x + bounds.width - inset - size.width
            } else if alignment.isCentered {
                x = bounds.x + (bounds.width - size.width) / 2
            } else {
                x = bounds.x + inset
            }
            subviews[index].place(at: Point(x: x, y: bounds.y + (bounds.height - size.height) / 2), anchor: .topLeading,
                                  proposal: inner)
        }
    }
}

/// A body cell with its content type removed: the row drives it through three methods, as `LazyUnitBox` drives a unit. A class,
/// so the layout and prepaint state a phase produces is still there for the next.
@MainActor
class AnyTableCell {
    /// Frozen cells paint this under their content (`TBL-K`).
    var rowBackground: Color? { get { nil } set {} }
    /// Cell mode's fill, ring and click (`TCM-D`); `nil` and ignored for a row table.
    var decor: TableCellDecor? { get { nil } set {} }
    func requestLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ProposalNodeID {
        fatalError("AnyTableCell is abstract")
    }
    func prepaint(pass: inout PrepaintPass) { fatalError("AnyTableCell is abstract") }
    func paint(pass: inout PaintPass) { fatalError("AnyTableCell is abstract") }
}

/// The one concrete `AnyTableCell`: a `TableCellBox` entered as a group member, so it counts as one element request and one
/// paint, takes its column's name under its row and re-binds its content's `@State` in every phase.
@MainActor
final class TableCellHolder<Content: ElementGroup>: AnyTableCell {
    var box: TableCellBox<Content>
    var layout: SingleElementLayout<TableCellBox<Content>>?
    var prepainted: LegacyContent<Content>.GroupPrepaint?

    init(_ box: TableCellBox<Content>) { self.box = box }

    override var rowBackground: Color? {
        get { box.paintsRowBackground }
        set { box.paintsRowBackground = newValue }
    }

    override var decor: TableCellDecor? {
        get { box.decor }
        set { box.decor = newValue }
    }

    override func requestLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                pass: inout LayoutPass) -> ProposalNodeID {
        let (nodes, built) = box.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        layout = built
        return nodes[0]
    }

    override func prepaint(pass: inout PrepaintPass) {
        guard var held = layout else { return }
        prepainted = box.prepaintGroup(layout: &held, pass: &pass)
        layout = held
    }

    override func paint(pass: inout PaintPass) {
        guard var held = layout else { return }
        var state = prepainted
        box.paintGroup(layout: &held, prepaint: &state, pass: &pass)
        layout = held
        prepainted = state
    }
}

// MARK: - A row

/// One realised row (`TBL-J`): its cells in paint order, scrolling cells first and frozen cells after, so a frozen cell is above
/// the cell it covers in paint, in prepaint's hitbox order and in the accessibility order the builder restores.
///
/// Named `ElementID.forRow(row.id)` by the body, as a `List` row is (`LH-A`), so its cells' identity is (row id x column key). It
/// calls `noteWindowedParent` for its cells (`ID-R`): without it a cell scrolled out of the window would read as vanished.
struct TableRowElement: Element, ProposalElement {
    var name: ElementID
    var cells: [AnyTableCell]
    var xs: [Double]
    var widths: [Double]
    var height: Double
    /// The row's own fill: alternating, or (PR C) selected. `nil` paints none.
    var background: Color?
    var handlers = Handlers()

    var elementID: ElementID? { name }

    struct Layout { var node: LayoutNodeID }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        pass.frame.stateTable.noteWindowedParent(id)   // `ID-R`, `TBL-J`
        var cursor = 0
        var nodes: [ProposalNodeID] = []
        nodes.reserveCapacity(cells.count)
        for cell in cells { nodes.append(cell.requestLayout(under: id, at: &cursor, pass: &pass)) }
        let node = pass.requestNativeLayout(TableRowLayout(xs: xs, widths: widths, height: height), children: nodes)
        return (node, Layout(node: node.layoutNodeID))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, pass: inout PrepaintPass) {
        pass.registerHandlers(handlers, at: bounds, id: id)
        for cell in cells { cell.prepaint(pass: &pass) }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Void,
                        pass: inout PaintPass) {
        if let background {
            pass.fill(bounds, color: pass.resolve(background), cornerRadii: Corners(all: Pixels(0)))
        }
        for cell in cells { cell.paint(pass: &pass) }
    }
}

/// Places a row's cells (`TBL-H`): subview `j` at `(xs[j], 0)`, proposed `(widths[j], height)`. Scrolling cells sit at their
/// column's offset and frozen cells at the table's clamped offset plus the frozen width before them (`TBL-E`).
struct TableRowLayout: ProposalLayout {
    var xs: [Double]
    var widths: [Double]
    var height: Double

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let natural = zip(xs, widths).map { $0 + $1 }.max() ?? 0
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? natural, height: proposal.height ?? height))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for index in subviews.indices where index < xs.count {
            subviews[index].place(at: Point(x: bounds.x + xs[index], y: bounds.y), anchor: .topLeading,
                                  proposal: ProposedSize(width: widths[index], height: height))
        }
    }
}
