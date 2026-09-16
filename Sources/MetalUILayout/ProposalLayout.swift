import MetalUICore

/// A proposal-layout algorithm: measure subviews at proposals, then place them.
///
/// MetalUI's value counterpart to SwiftUI's `Layout`, not a source-compatible
/// copy (ruling SA-A). Register one with `LayoutTree.newNativeLayout(_:children:)`
/// or, from an element, `LayoutPass.requestNativeLayout(_:children:)`; the
/// `MetalUI` module adds `ProposalLayoutContainer` and `callAsFunction` so a
/// conformer can be written `MyLayout() { A(); B() }`.
///
/// **No cache requirement.** The kernel memoizes every `(node, proposal)` pair
/// for the duration of one layout call, so `sizeThatFits` runs once per
/// distinct proposal and so does every subview measurement it asks for.
///
/// **Sendable** because the engine calls a layout from whatever thread it runs
/// on, the same bar `ProposalMeasureFunction` meets.
///
/// **A layout's answer must be a function of its value, its proposal and its
/// subviews' answers.** The kernel memoizes on that assumption and does not
/// detect a layout that breaks it.
public protocol ProposalLayout: Sendable {
    /// The subviews handed in can measure and cannot place (ruling SA-C):
    /// `MeasurementSubview` has no `place`.
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement

    /// `bounds` is root-absolute. A subview this never places is centred in
    /// `bounds` at its answer to `proposal`; a subview placed more than once
    /// keeps its last placement. Every subview's own subtree is placed ONCE,
    /// after this returns, in index order (ruling SA-E; SwiftUI's order is the
    /// reverse, and nothing may rely on either).
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews)
}

/// The subviews a `ProposalLayout.sizeThatFits` call may measure.
public struct MeasurementSubviews: RandomAccessCollection {
    let run: NativeLayoutRun
    let nodes: [LayoutNodeID]

    init(run: NativeLayoutRun, nodes: [LayoutNodeID]) {
        self.run = run
        self.nodes = nodes
    }

    public var startIndex: Int { run.requireActive(); return nodes.startIndex }
    public var endIndex: Int { run.requireActive(); return nodes.endIndex }
    public subscript(position: Int) -> MeasurementSubview {
        run.requireActive()
        return MeasurementSubview(run: run, node: nodes[position])
    }
}

/// One subview, as `sizeThatFits` sees it: priority, spacer-ness and a cached
/// measurement, and nothing that writes a rect (ruling SA-C, SA-D).
public struct MeasurementSubview {
    let run: NativeLayoutRun
    let node: LayoutNodeID

    init(run: NativeLayoutRun, node: LayoutNodeID) {
        self.run = run
        self.node = node
    }

    /// The built-in stack's own priority rule (rulings SA-D, CN-C, CN-D): a
    /// spacer reads −∞ (SwiftUI's proxy reads the same, contract probe E); a
    /// `layoutPriority` node its value; an overlay attachment its primary's,
    /// at any depth (L2); a built-in linear stack or `ZStack` with exactly one
    /// child that child's (L3); anything else 0 — a `frame`, `padding`,
    /// `aspectRatio` or `fixedSize` over a priority, a container of two or
    /// more, and a custom layout of any count (L, L2, L3).
    public var priority: Double {
        run.requireActive()
        return run.tree.nativeLayoutPriority(node)
    }

    /// True for a spacer node, directly or under any depth of `layoutPriority`
    /// nodes, and never through `frame`, padding, an overlay attachment or any
    /// other wrapper (ruling SA-D). SwiftUI exposes no such test (probes E,
    /// E2), and since ruling CN-B no built-in stack reads it: a spacer's
    /// behaviour in a stack follows from its −∞ `priority`, and its zero on a
    /// built-in stack's cross axis from a mark the stack sets at registration
    /// (ruling CN-C), which a custom layout cannot set. A custom layout that
    /// wants the built-in's cross size can leave `isSpacer` subviews out of
    /// it, as `ReferenceLinearStack` does; the mark's walk reaches further
    /// (through padding, frames, `fixedSize`, `aspectRatio` and overlays).
    public var isSpacer: Bool {
        run.requireActive()
        return run.tree.isNativeSpacer(node)
    }

    /// This subview's answer to `proposal`, through the run's cache: its
    /// measurement body runs once per distinct proposal per layout call
    /// (ruling SA-H clause 2).
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement {
        run.requireActive()
        return run.tree.measureNative(node, proposal: proposal, run: run)
    }
}

/// The subviews a `ProposalLayout.placeSubviews` call may measure and place.
public struct PlacementSubviews: RandomAccessCollection {
    let run: NativeLayoutRun
    let nodes: [LayoutNodeID]
    let token: UInt64
    let records: NativePlacementRecords

    init(run: NativeLayoutRun, nodes: [LayoutNodeID], token: UInt64,
         records: NativePlacementRecords) {
        self.run = run
        self.nodes = nodes
        self.token = token
        self.records = records
    }

    public var startIndex: Int { run.requireActive(); return nodes.startIndex }
    public var endIndex: Int { run.requireActive(); return nodes.endIndex }
    public subscript(position: Int) -> PlacementSubview {
        run.requireActive()
        return PlacementSubview(run: run, node: nodes[position], index: position,
                                token: token, records: records)
    }
}

/// One subview, as `placeSubviews` sees it.
public struct PlacementSubview {
    let run: NativeLayoutRun
    let node: LayoutNodeID
    let index: Int
    let token: UInt64
    let records: NativePlacementRecords

    init(run: NativeLayoutRun, node: LayoutNodeID, index: Int, token: UInt64,
         records: NativePlacementRecords) {
        self.run = run
        self.node = node
        self.index = index
        self.token = token
        self.records = records
    }

    /// The same rule as `MeasurementSubview.priority`.
    public var priority: Double {
        run.requireActive()
        return run.tree.nativeLayoutPriority(node)
    }

    /// The same rule as `MeasurementSubview.isSpacer`.
    public var isSpacer: Bool {
        run.requireActive()
        return run.tree.isNativeSpacer(node)
    }

    /// The same cached measurement as `MeasurementSubview.sizeThatFits(_:)`.
    /// Asking here places nothing.
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement {
        run.requireActive()
        return run.tree.measureNative(node, proposal: proposal, run: run)
    }

    /// Records a placement. After `placeSubviews` returns, the subview is
    /// stored at its answer to `proposal`, offset from `position` by
    /// `anchor`'s factors times that size (probes K, K2), and its subtree is
    /// placed once. A later call for the same subview replaces the record
    /// (probe J). Nothing is measured or placed by this call itself.
    ///
    /// **Why deferred** (ruling SA-E): an eager `place` would run a
    /// twice-placed subtree's own `placeSubviews` twice, which SwiftUI never
    /// does (probe J), and doubles the work per level of a chain of layouts
    /// that each re-place a child.
    ///
    /// Traps when used outside its own `placeSubviews` call or while any
    /// measurement body runs (ruling SA-C's dynamic backstop behind the static
    /// one, `MeasurementSubview` having no `place`).
    public func place(at position: Point<Double>,
                      anchor: ProposalAlignment = .topLeading,
                      proposal: ProposedSize) {
        run.requireActive()
        precondition(token == run.activePlacement,
                     "a PlacementSubview was used outside its placeSubviews call")
        precondition(run.measureDepth == 0,
                     "a PlacementSubview was used during measurement")
        records.records[index] = NativePlacementRecord(position: position, anchor: anchor,
                                                       proposal: proposal)
    }
}

/// One recorded `place` call.
struct NativePlacementRecord {
    var position: Point<Double>
    var anchor: ProposalAlignment
    var proposal: ProposedSize
}

/// The placement records of one `placeSubviews` call, shared by every proxy
/// that call hands out.
final class NativePlacementRecords {
    var records: [NativePlacementRecord?]
    init(count: Int) { records = Array(repeating: nil, count: count) }
}
