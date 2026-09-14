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

    public var startIndex: Int { 0 }
    public var endIndex: Int { 0 }
    public subscript(position: Int) -> MeasurementSubview {
        MeasurementSubview(run: run, node: nodes[position])
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

    public var priority: Double { 0 }
    public var isSpacer: Bool { false }
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement {
        LayoutMeasurement(size: .zero)
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

    public var startIndex: Int { 0 }
    public var endIndex: Int { 0 }
    public subscript(position: Int) -> PlacementSubview {
        PlacementSubview(run: run, node: nodes[position], index: position,
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

    public var priority: Double { 0 }
    public var isSpacer: Bool { false }
    public func sizeThatFits(_ proposal: ProposedSize) -> LayoutMeasurement {
        LayoutMeasurement(size: .zero)
    }

    public func place(at position: Point<Double>,
                      anchor: ProposalAlignment = .topLeading,
                      proposal: ProposedSize) {}
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
