import MetalUICore
import MetalUILayout

// `LazyVStack` and `LazyHStack` (item L1, rulings `LZ-A`, `LZ-B`, `LZ-D`, `LZ-F`, `LZ-O`;
// spec 3.3; probe `docs/probes/swiftui-lazy-containers.swift` arms A1-A10, R1-R5, S1).

/// A lazy stack's realised units as a `ProposalLayout` (`LZ-F`): the SAME arithmetic for both
/// axes, over `axis`.
///
/// - **Cross size** (probe A1, A3, A5): the proposal when there is one (finite), else the FIRST
///   realised node's answer at `(nil, nil)` - not the widest, not the smallest (A3d: 50 of 50/100/30).
/// - **Main size** is content, never greedy (A1: 40 at a 200 proposal): `anchorOffset` + the realised
///   units from the anchor down (each node's extent plus `spacing`) + `trailingExtent`, less the
///   last spacing, floored at 0. A unit with no node adds nothing and no spacing (A9); a unit of
///   several nodes lays them out in sequence with `spacing` (A8).
/// - **Placement**: the anchor unit at `bounds.main + anchorOffset`, later units after it, earlier
///   ones before it, so a re-measured unit above the anchor moves only units above it (`VL-G`
///   item 1). Each node is proposed the cross extent on the cross axis and nothing on the main axis,
///   aligned across by `alignment`, and overflows centred when wider (A5).
///
/// **Not `Hashable`, so it taints exactly its ancestors for the layout memo** (`IV-`, `LZ-F`,
/// `LZ-R`): a key over its fields would have to hold the realised window and every measured
/// extent, so a hit could be a stale layout.
struct LazyStackLayout: ProposalLayout {
    var axis: ProposalStackAxis
    var alignment: ProposalAlignment
    var spacing: Double
    /// Nodes each realised unit registered, in order.
    var unitNodeCounts: [Int]
    /// The index, among the realised units, of the anchor unit.
    var anchorSlot: Int
    /// Where the anchor unit's leading edge sits from the layout's.
    var anchorOffset: Double
    /// The extent after the last realised unit (units not realised).
    var trailingExtent: Double

    private var vertical: Bool { axis == .vertical }

    private func nodeProposal(cross: Double) -> ProposedSize {
        vertical ? ProposedSize(width: cross, height: nil) : ProposedSize(width: nil, height: cross)
    }

    private func main(_ size: SizeD) -> Double { vertical ? size.height : size.width }
    private func across(_ size: SizeD) -> Double { vertical ? size.width : size.height }

    /// The first node of the anchor slot.
    private func anchorNode() -> Int {
        let slot = Swift.min(Swift.max(anchorSlot, 0), unitNodeCounts.count)
        return unitNodeCounts[0..<slot].reduce(0, +)
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let offered = vertical ? proposal.width : proposal.height
        let cross: Double
        if let offered, offered.isFinite {
            cross = offered
        } else if subviews.isEmpty {
            cross = 0
        } else {
            cross = across(subviews[0].sizeThatFits(.unspecified).size)
        }
        var below = 0.0
        for index in Swift.min(anchorNode(), subviews.count)..<subviews.count {
            below += main(subviews[index].sizeThatFits(nodeProposal(cross: cross)).size) + spacing
        }
        let extent = Swift.max(0, anchorOffset + below + trailingExtent - spacing)
        return LayoutMeasurement(size: vertical ? SizeD(width: cross, height: extent)
                                                : SizeD(width: extent, height: cross))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        let cross = vertical ? bounds.width : bounds.height
        let nodeProposal = nodeProposal(cross: cross)
        let answers = subviews.indices.map { subviews[$0].sizeThatFits(nodeProposal).size }
        let start = Swift.min(anchorNode(), subviews.count)
        let origin = vertical ? bounds.y : bounds.x
        func place(_ index: Int, along: Double) {
            let size = answers[index]
            let offset = (cross - across(size)) * (vertical ? alignment.horizontalFactor
                                                            : alignment.verticalFactor)
            let point = vertical ? Point(x: bounds.x + offset, y: along)
                                 : Point(x: along, y: bounds.y + offset)
            subviews[index].place(at: point, anchor: .topLeading, proposal: nodeProposal)
        }
        var along = origin + anchorOffset
        for index in start..<subviews.count {
            place(index, along: along)
            along += main(answers[index]) + spacing
        }
        along = origin + anchorOffset
        for index in stride(from: start - 1, through: 0, by: -1) {
            along -= main(answers[index]) + spacing
            place(index, along: along)
        }
    }
}

/// What a lazy stack's layout phase hands to prepaint and paint.
struct LazyStackState<Content: ProposalElementGroup> {
    var node: LayoutNodeID
    /// The units' table (empty for an eager container).
    var table: LazyUnitTable?
    /// Realised units, in unit order (empty for an eager container).
    var boxes: [LazyUnitBox] = []
    /// The eager container's content layout, `nil` when windowed.
    var eager: Content.GroupLayout?
    var plan: LazyLinePlan?
    var spacing: Double = 0
}

/// What prepaint hands to paint.
struct LazyStackPrepaint<Content: ProposalElementGroup> {
    var eager: Content.GroupPrepaint?
}

/// The one implementation behind `LazyVStack` and `LazyHStack`.
@MainActor
struct LazyStackEngine<Content: ProposalElementGroup> {
    var content: Content
    var spacing: Pixels?
    var axis: ProposalStackAxis
    var alignment: ProposalAlignment

    private var scrollAxis: ScrollAxis { axis == .vertical ? .vertical : .horizontal }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, LazyStackState<Content>) {
        let spacing = spacing.map { Double($0.value) } ?? ProposalSpacing.platformDefault
        let axis = self.axis
        guard let sources = lazyFlatten(content) else {
            // `LZ-B`, divergence 636: a member that is not a unit source makes the container eager.
            var cursor = 0
            let (children, contentLayout) = pass.frame.withStackAxis(axis) {
                content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
            }
            pass.frame.lazyWork.unbounded += 1
            pass.frame.lazyWork.unitsRealized += children.count
            pass.frame.lazyWork.linesRealized += children.count
            let layout = LazyStackLayout(axis: axis, alignment: alignment, spacing: spacing,
                                         unitNodeCounts: children.map { _ in 1 }, anchorSlot: 0,
                                         anchorOffset: 0, trailingExtent: 0)
            let node = pass.requestNativeLayout(layout, children: children)
            return (node, LazyStackState(node: node.layoutNodeID, table: nil, eager: contentLayout,
                                         spacing: spacing))
        }
        let table = LazyUnitTable(sources)
        let stored = pass.frame.stateTable.peek(id, as: LazyOrigin.self)
        let plan = LazyLinePlanner.plan(lineCount: table.count, key: table.key, stored: stored,
                                        origin: stored?.offset ?? 0, context: pass.scrollContext,
                                        axis: scrollAxis)
        table.begin(parent: id, pass: &pass)
        var boxes: [LazyUnitBox] = []
        boxes.reserveCapacity(plan.window.count)
        var seen = Set<AnyHashable>()
        var nodes: [ProposalNodeID] = []
        var counts: [Int] = []
        var anchorSlot = 0
        pass.frame.withStackAxis(axis) {
            for unit in plan.window {
                // `LZ-G`: duplicate ids dedupe within the realised window only, first wins.
                guard seen.insert(table.key(unit)).inserted else { continue }
                if unit < plan.anchorLine { anchorSlot += 1 }
                let box = table.realize(unit, parent: id, pass: &pass)
                boxes.append(box)
                nodes.append(contentsOf: box.nodes)
                counts.append(box.nodes.count)
            }
        }
        if plan.mode == .unbounded { pass.frame.lazyWork.unbounded += 1 }
        pass.frame.lazyWork.unitsRealized += boxes.count
        pass.frame.lazyWork.linesRealized += boxes.count
        let layout = LazyStackLayout(axis: axis, alignment: alignment, spacing: spacing, unitNodeCounts: counts,
                                     anchorSlot: anchorSlot, anchorOffset: plan.anchorOffset,
                                     trailingExtent: plan.trailing)
        let node = pass.requestNativeLayout(layout, children: nodes)
        return (node, LazyStackState(node: node.layoutNodeID, table: table, boxes: boxes, eager: nil,
                                     plan: plan, spacing: spacing))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LazyStackState<Content>,
                           pass: inout PrepaintPass) -> LazyStackPrepaint<Content> {
        guard let table = layout.table, let plan = layout.plan else {
            guard var eager = layout.eager else { return LazyStackPrepaint(eager: nil) }
            let prepaint = content.prepaintGroup(layout: &eager, pass: &pass)
            layout.eager = eager
            return LazyStackPrepaint(eager: prepaint)
        }
        let vertical = axis == .vertical
        let spacing = layout.spacing
        // Each realised unit's extent along the axis, as the index records it (`extent + spacing`
        // per node; a unit with no node records 0).
        let realised: [(line: Int, extent: Double)] = layout.boxes.map { box in
            var extent = 0.0
            for node in box.nodes {
                let size = pass.bounds(of: node.layoutNodeID).size
                extent += Double(vertical ? size.height.value : size.width.value) + spacing
            }
            return (box.unit, extent)
        }
        let outcome = LazyLinePlanner.prepaint(id, bounds: bounds, axis: scrollAxis, lineCount: table.count,
                                               made: plan.index, key: table.key, realised: realised,
                                               builtWindow: plan.window, builtCold: plan.mode == .cold,
                                               anchor: plan.anchor, pass: pass)
        if pass.frame.hasUnresolvedScrollRequests {
            let boxes = layout.boxes
            LazyLinePlanner.resolveScrollRequests(
                id, bounds: bounds, axis: scrollAxis, unitCount: table.count, line: { $0 },
                rawID: table.rawID, index: outcome.index, adjustment: outcome.adjustment,
                realisedBounds: { unit in
                    guard let box = boxes.first(where: { $0.unit == unit }), let node = box.nodes.first
                    else { return nil }
                    return pass.bounds(of: node.layoutNodeID)
                }, pass: pass)
        }
        for box in layout.boxes { box.prepaint(&pass) }
        return LazyStackPrepaint(eager: nil)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LazyStackState<Content>,
                        prepaint: inout LazyStackPrepaint<Content>, pass: inout PaintPass) {
        if layout.table == nil {
            guard var eager = layout.eager, var held = prepaint.eager else { return }
            content.paintGroup(layout: &eager, prepaint: &held, pass: &pass)
            layout.eager = eager
            prepaint.eager = held
            return
        }
        for box in layout.boxes { box.paint(&pass) }
    }
}

/// SwiftUI's `LazyVStack`: a vertical stack that realises its children only as a scroller along its
/// axis brings them near the viewport (item L1).
///
/// ```swift
/// ProposalScrollView {
///     LazyVStack {
///         ForEach(rows) { row in RowView(row) }
///     }
/// }
/// ```
///
/// **What is windowed.** Inside a `ProposalScrollView` (or `ScrollView`) scrolling vertically, only the
/// children within the viewport plus two on each side are built, laid out and prepainted each frame
/// (divergence 637: SwiftUI realises exactly the on-screen ones); a child's extent is measured the
/// first time it is realised and an unrealised child counts as the mean of the measured ones, with
/// the child on top of the viewport kept in place as extents are learned (`List(_:rowContent:)`'s
/// mechanism, the same `RowExtentIndex`). Outside a scroller, in a horizontal one, inside a
/// `Deferred` or when the content holds an `if`, `switch` or `for` member (divergence 636), every child is
/// realised, as `VStack` would.
///
/// **Size** (probe `swiftui-lazy-containers.swift`): the proposed width when there is one, else the
/// first child's, never the widest; the height is the content's, never greedy. Spacing defaults to 8.
///
/// **Identity and state.** A `ForEach` element is identified by its id as in any stack; a child
/// scrolled out keeps its `@State` while the state table is within `TB-AH`'s bound and is built
/// afresh after (keep durable values in data). A child that registers no view adds no extent and
/// no spacing. Accessibility exposes the realised children only. `pinnedViews:` and `Section` are
/// not offered.
public struct LazyVStack<Content: ProposalElementGroup>: Element {
    var engine: LazyStackEngine<Content>

    /// A vertical lazy stack of `content`, SwiftUI's `LazyVStack(alignment:spacing:pinnedViews:content:)`
    /// without `pinnedViews`.
    ///
    /// - Parameters:
    ///   - alignment: How children of different widths line up (default `.center`).
    ///   - spacing: The distance between children; `nil` is the platform default, 8.
    ///   - content: The children.
    public init(alignment: HorizontalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content) {
        engine = LazyStackEngine(content: content(), spacing: spacing, axis: .vertical,
                                 alignment: alignment.proposalAlignment)
    }

    /// What the layout phase hands to prepaint and paint.
    public struct Layout {
        var state: LazyStackState<Content>
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, state) = engine.requestLayout(id, pass: &pass)
        return (node, Layout(state: state))
    }

    /// What prepaint hands to paint.
    public struct Prepaint {
        var state: LazyStackPrepaint<Content>
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(state: engine.prepaint(id, bounds: bounds, layout: &layout.state, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(id, bounds: bounds, layout: &layout.state, prepaint: &prepaint.state, pass: &pass)
    }
}

extension LazyVStack: ProposalElement {}

/// SwiftUI's `LazyHStack`: `LazyVStack` along the horizontal axis (item L1).
///
/// Windowed against a scroller scrolling horizontally; the width is the content's, the height the
/// proposed one else the first child's. See ``LazyVStack`` for the realisation, identity and state
/// rules, which are the same.
public struct LazyHStack<Content: ProposalElementGroup>: Element {
    var engine: LazyStackEngine<Content>

    /// A horizontal lazy stack of `content`, SwiftUI's `LazyHStack(alignment:spacing:pinnedViews:content:)`
    /// without `pinnedViews`.
    ///
    /// - Parameters:
    ///   - alignment: How children of different heights line up (default `.center`).
    ///   - spacing: The distance between children; `nil` is the platform default, 8.
    ///   - content: The children.
    public init(alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ProposalContentBuilder content: () -> Content) {
        engine = LazyStackEngine(content: content(), spacing: spacing, axis: .horizontal,
                                 alignment: alignment.proposalAlignment)
    }

    /// What the layout phase hands to prepaint and paint.
    public struct Layout {
        var state: LazyStackState<Content>
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let (node, state) = engine.requestLayout(id, pass: &pass)
        return (node, Layout(state: state))
    }

    /// What prepaint hands to paint.
    public struct Prepaint {
        var state: LazyStackPrepaint<Content>
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        Prepaint(state: engine.prepaint(id, bounds: bounds, layout: &layout.state, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        engine.paint(id, bounds: bounds, layout: &layout.state, prepaint: &prepaint.state, pass: &pass)
    }
}

extension LazyHStack: ProposalElement {}
