/// A handle to one node in one `LayoutTree`.
///
/// **The `generation` is what makes it a handle rather than a bare index**
/// (m1a ruling C-3). An index alone is silently valid in *any* tree: a
/// `LayoutNodeID` that outlives the tree that issued it addresses whatever node
/// happens to sit at the same index in the next one, with no error and no
/// diagnostic — a wrong rect, not a crash. Every `LayoutTree` accessor compares
/// this field against its own generation first, so a handle from another tree
/// traps at the point of use instead.
///
/// The check costs one `UInt64` comparison per access and is what lets
/// `MetalUI` allocate a fresh `LayoutTree` per frame while elements are free to
/// stash a node id anywhere — including the cross-frame state table, which is
/// the carrier that made C-3 reachable in the first place.
public struct LayoutNodeID: Hashable, Sendable {
    /// The generation of the tree that issued this id.
    public let generation: UInt64
    public let index: Int

    init(generation: UInt64, index: Int) {
        self.generation = generation
        self.index = index
    }
}

/// Structure-of-arrays node storage, reset per layout pass.
///
/// Parallel arrays rather than a class per node: the engine walks these in tight
/// loops, and `reset(generation:)` keeps capacity so a per-frame rebuild does not
/// re-allocate. Nothing here knows what a leaf actually contains — text, images
/// and app content all arrive as a `MeasureFunction` (spec §3.1).
///
/// ## Generations (ruling C-3)
///
/// A tree stamps every id it issues with its `generation`, and refuses any id
/// stamped with another. **The generation is supplied by the caller and has no
/// default**, because the only invariant that matters is one this type cannot
/// enforce alone: *two trees whose ids could ever meet must not share a
/// generation.* A default would hide that obligation at every call site.
///
/// In `Sources/`, `MetalUI.Frame` is the only constructor and draws from a
/// `@MainActor` monotonic counter, so no two live trees share a generation —
/// verify with `grep -rn "LayoutTree(" Sources/`. Tests that never exchange ids
/// between trees pass `0` and lose nothing by it.
public final class LayoutTree {
    private var styles: [Style] = []
    private var childLists: [[LayoutNodeID]] = []
    private var measures: [MeasureFunction?] = []
    private var layouts: [LayoutRect] = []
    private var measuredWidths: [Double] = []
    private var nativeNodes: [Int: NativeNode] = [:]

    /// The stamp carried by every id this tree issues. Changed only by
    /// `reset(generation:)`, which is what makes the ids from before a reset
    /// detectably stale.
    public private(set) var generation: UInt64

    public init(generation: UInt64) { self.generation = generation }

    public var nodeCount: Int { styles.count }

    /// True while `computeLayout` is running over this tree.
    ///
    /// Task 3 memoizes `measureNode` on the assumption that styles do not change
    /// during a run. Nothing enforced that before this flag, and a style written
    /// mid-layout would hand back a cached size computed for the *old* style —
    /// a wrong answer no fixture could catch, because the fixture and the golden
    /// would both be generated from the settled tree.
    ///
    /// The flag lives here rather than on `LayoutContext` because `setStyle` is a
    /// tree method and has no context in hand.
    private(set) var isLayingOut = false

    func beginLayout() {
        precondition(!isLayingOut, "computeLayout re-entered on the same tree")
        isLayingOut = true
    }

    func endLayout() { isLayingOut = false }

    /// Whether `id` was issued by this tree in its current generation.
    ///
    /// The same expression every accessor's precondition uses, exposed so the
    /// staleness rule can be asserted without provoking a trap.
    public func isCurrent(_ id: LayoutNodeID) -> Bool { id.generation == generation }

    public func newNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        for child in children { _ = slot(child) }
        styles.append(style)
        childLists.append(children)
        measures.append(nil)
        layouts.append(LayoutRect(x: 0, y: 0, width: 0, height: 0))
        measuredWidths.append(0)
        return LayoutNodeID(generation: generation, index: styles.count - 1)
    }

    public func newLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        let id = newNode(style: style, children: [])
        measures[id.index] = measure
        return id
    }

    /// Registers a native leaf for the SwiftUI-style layout migration.
    ///
    /// Native nodes reuse this tree's generation-stamped ids and resolved-rect
    /// storage. `Style.default` is temporary compatibility storage only: the
    /// native engine never reads it.
    public func newNativeLeaf(measure: @escaping NativeMeasureFunction) -> LayoutNodeID {
        let id = newNode(style: .default, children: [])
        nativeNodes[id.index] = .leaf(measure)
        return id
    }

    /// Registers the first native container: an unaligned overlay.
    ///
    /// Every child must already be native. This makes the migration boundary
    /// structural: a native subtree cannot accidentally delegate one child back
    /// into the CSS engine.
    public func newNativeOverlay(children: [LayoutNodeID]) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        let id = newNode(style: .default, children: children)
        nativeNodes[id.index] = .overlay
        return id
    }

    /// Registers a native fixed frame around exactly one native child.
    ///
    /// A fixed axis is proposed to the child and becomes the frame's measured
    /// size; an optional axis forwards the parent's proposal and adopts the
    /// child's response. An ideal axis is proposed only when its parent axis
    /// is unspecified, so it remains a child-measurement preference rather
    /// than a forced frame size. Placement centres the child inside the
    /// resulting frame, matching SwiftUI's default frame alignment.
    public func newNativeFrame(child: LayoutNodeID, width: Double? = nil,
                               height: Double? = nil,
                               minWidth: Double? = nil, idealWidth: Double? = nil,
                               maxWidth: Double? = nil,
                               minHeight: Double? = nil, idealHeight: Double? = nil,
                               maxHeight: Double? = nil,
                               alignment: NativeAlignment = .center) -> LayoutNodeID {
        _ = nativeNode(child)
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .frame(width: width, height: height,
                                       minWidth: minWidth, idealWidth: idealWidth,
                                       maxWidth: maxWidth,
                                       minHeight: minHeight, idealHeight: idealHeight,
                                       maxHeight: maxHeight,
                                       alignment: alignment)
        return id
    }

    /// Registers a native linear stack with explicit inter-item spacing.
    public func newNativeLinearStack(children: [LayoutNodeID], axis: NativeStackAxis,
                                     spacing: Double = 0) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        let id = newNode(style: .default, children: children)
        nativeNodes[id.index] = .linearStack(axis: axis, spacing: spacing)
        return id
    }

    /// Measures and places one all-native subtree into the existing rect store.
    ///
    /// `bounds` is root-absolute, matching the contract `Frame.bounds(of:)`
    /// already exposes to prepaint and paint. Measurements are cached only for
    /// this call, keyed by both node and proposal; a later frame receives a new
    /// tree and therefore a new cache.
    @discardableResult
    public func computeNativeLayout(root: LayoutNodeID, proposal: ProposedSize,
                                    in bounds: LayoutRect) -> LayoutMeasurement {
        var cache: [NativeMeasurementKey: LayoutMeasurement] = [:]
        let result = measureNative(root, proposal: proposal, cache: &cache)
        placeNative(root, in: bounds, proposal: proposal, cache: &cache)
        roundNativeStoredRects(root)
        return result
    }

    /// Whether this node belongs to the native layout path.
    public func isNativeLayoutNode(_ id: LayoutNodeID) -> Bool {
        nativeNodes[slot(id)] != nil
    }

    public func style(_ id: LayoutNodeID) -> Style { styles[slot(id)] }

    public func setStyle(_ id: LayoutNodeID, _ s: Style) {
        precondition(!isLayingOut,
                     "setStyle called while computeLayout is running — measured sizes are memoized against the styles this would change")
        styles[slot(id)] = s
    }

    public func children(_ id: LayoutNodeID) -> [LayoutNodeID] { childLists[slot(id)] }
    public func measure(_ id: LayoutNodeID) -> MeasureFunction? { measures[slot(id)] }
    public func layout(_ id: LayoutNodeID) -> LayoutRect { layouts[slot(id)] }
    public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect) { layouts[slot(id)] = r }

    /// The node's width **before `roundStoredRects` rounded it**, and the only
    /// number a phase after layout can use to ask the question layout asked.
    ///
    /// **This is the fix for what CLAUDE.md carried as divergence 8**, and the
    /// distinction it turns on is narrow enough to lose. `roundLayout` stores
    /// `round(x + w) - round(x)`, which keeps every boundary closed on its
    /// parent — that is the property the corpus depends on and it is not in
    /// question. But the number it stores lands *below* `w` about half the
    /// time, and a measured leaf that re-derives its own content from the
    /// stored width is then answering a **different** question from the one its
    /// measure function was given. Measured on `"Count N"` at 22pt: at the
    /// unrounded width every count typesets to one line, and at `floor` of it
    /// every count typesets to two.
    ///
    /// **Written for every node and read by exactly one**, `Text.paint`. It is
    /// not `private` to the text path because `roundStoredRects` is the only
    /// place the pre-rounding value still exists, and that is a tree-wide walk;
    /// a leaf-only store would have to be special-cased there for no gain.
    ///
    /// **Do not paint at this width's ORIGIN.** Only the width is recorded, and
    /// deliberately: a fractional origin is what `roundLayout` exists to
    /// eliminate, and reintroducing one would put glyphs on half-pixels. What
    /// this buys back is the sub-point the *width* lost, which is the whole
    /// defect.
    public func measuredWidth(_ id: LayoutNodeID) -> Double { measuredWidths[slot(id)] }

    func setMeasuredWidth(_ id: LayoutNodeID, _ w: Double) { measuredWidths[slot(id)] = w }

    /// Drop every node but keep the allocated capacity, under a **new**
    /// generation.
    ///
    /// **No production code calls this** — `grep -rn "\.reset(" Sources/` finds
    /// only the precondition's own message string. The element pipeline was
    /// expected to reset the tree each frame; `Frame` allocates a fresh
    /// `LayoutTree` per frame instead, which is spec §4.1's model and needs no
    /// reuse. The capacity-reuse path is therefore exercised by
    /// `LayoutTreeTests` alone. Those four guards are kept deliberately: they
    /// pin the contract for whoever does call it, and the contract is ruling
    /// C-3's, which is the one this repo has already been bitten by. Carried in
    /// CLAUDE.md's inert-API table.
    ///
    /// The parameter is not a convenience: reuse without it is exactly ruling
    /// C-3's hazard. Ids minted before the reset stay in whatever the caller
    /// kept them in, and after a reset the array they index has been refilled
    /// with unrelated nodes — smaller and the read traps, larger or equal and it
    /// silently returns a different node's rect. Requiring a strictly greater
    /// generation makes every such id detectably stale.
    public func reset(generation: UInt64) {
        precondition(generation > self.generation,
                     """
                     LayoutTree.reset(generation: \(generation)) does not advance past \
                     \(self.generation): ids minted before the reset would stay valid and \
                     silently address different nodes (ruling C-3)
                     """)
        self.generation = generation
        styles.removeAll(keepingCapacity: true)
        childLists.removeAll(keepingCapacity: true)
        measures.removeAll(keepingCapacity: true)
        layouts.removeAll(keepingCapacity: true)
        measuredWidths.removeAll(keepingCapacity: true)
        nativeNodes.removeAll(keepingCapacity: true)
    }

    /// The storage index for `id`, after checking it belongs to this tree.
    ///
    /// Every accessor above goes through here, so there is one place the rule
    /// lives and one place to mutate when testing that it fires.
    private func slot(_ id: LayoutNodeID) -> Int {
        precondition(isCurrent(id),
                     """
                     LayoutNodeID from generation \(id.generation) used against a LayoutTree \
                     at generation \(generation) — the id outlived the tree that issued it \
                     (ruling C-3)
                     """)
        return id.index
    }

    private func nativeNode(_ id: LayoutNodeID) -> NativeNode {
        let index = slot(id)
        guard let node = nativeNodes[index] else {
            preconditionFailure("native layout subtree contains a legacy node")
        }
        return node
    }

    private func measureNative(_ id: LayoutNodeID, proposal: ProposedSize,
                               cache: inout [NativeMeasurementKey: LayoutMeasurement])
        -> LayoutMeasurement {
        let key = NativeMeasurementKey(id: id, proposal: proposal)
        if let cached = cache[key] { return cached }

        let result: LayoutMeasurement
        switch nativeNode(id) {
        case .leaf(let measure):
            result = measure(proposal)
        case .overlay:
            result = children(id).reduce(LayoutMeasurement(size: .zero)) { current, child in
                let childMeasurement = measureNative(child, proposal: proposal, cache: &cache)
                return LayoutMeasurement(
                    size: SizeD(width: max(current.size.width, childMeasurement.size.width),
                                height: max(current.size.height, childMeasurement.size.height))
                )
            }
        case .frame(let width, let height, let minWidth, let idealWidth, let maxWidth, let minHeight, let idealHeight, let maxHeight, let alignment):
            let childProposal = ProposedSize(width: framedProposal(proposal.width, fixed: width, ideal: idealWidth, min: minWidth, max: maxWidth),
                                             height: framedProposal(proposal.height, fixed: height, ideal: idealHeight, min: minHeight, max: maxHeight))
            let child = measureNative(children(id)[0], proposal: childProposal, cache: &cache)
            let frameHeight = framedSize(child.size.height, fixed: height, min: minHeight, max: maxHeight)
            result = LayoutMeasurement(
                size: SizeD(width: framedSize(child.size.width, fixed: width, min: minWidth, max: maxWidth), height: frameHeight),
                firstBaseline: child.firstBaseline.map { $0 + (frameHeight - child.size.height) * alignment.verticalFactor },
                lastBaseline: child.lastBaseline.map { $0 + (frameHeight - child.size.height) * alignment.verticalFactor }
            )
        case .linearStack(let axis, let spacing):
            let childProposal = stackChildProposal(for: axis, parent: proposal)
            let childMeasurements = children(id).map {
                measureNative($0, proposal: childProposal, cache: &cache)
            }
            let gaps = Double(max(0, childMeasurements.count - 1)) * spacing
            switch axis {
            case .horizontal:
                result = LayoutMeasurement(
                    size: SizeD(width: childMeasurements.reduce(gaps) { $0 + $1.size.width },
                                height: childMeasurements.map(\.size.height).max() ?? 0)
                )
            case .vertical:
                result = LayoutMeasurement(
                    size: SizeD(width: childMeasurements.map(\.size.width).max() ?? 0,
                                height: childMeasurements.reduce(gaps) { $0 + $1.size.height })
                )
            }
        }
        cache[key] = result
        return result
    }

    private func placeNative(_ id: LayoutNodeID, in bounds: LayoutRect,
                             proposal: ProposedSize,
                             cache: inout [NativeMeasurementKey: LayoutMeasurement]) {
        setLayout(id, bounds)
        switch nativeNode(id) {
        case .leaf:
            return
        case .overlay:
            for child in children(id) {
                let measurement = measureNative(child, proposal: proposal, cache: &cache)
                placeNative(child,
                            in: LayoutRect(x: bounds.x, y: bounds.y,
                                           width: measurement.size.width, height: measurement.size.height),
                            proposal: proposal, cache: &cache)
            }
        case .frame(let width, let height, let minWidth, let idealWidth, let maxWidth, let minHeight, let idealHeight, let maxHeight, let alignment):
            let childProposal = ProposedSize(width: framedProposal(proposal.width, fixed: width, ideal: idealWidth, min: minWidth, max: maxWidth),
                                             height: framedProposal(proposal.height, fixed: height, ideal: idealHeight, min: minHeight, max: maxHeight))
            let child = children(id)[0]
            let measurement = measureNative(child, proposal: childProposal, cache: &cache)
            placeNative(child,
                        in: LayoutRect(x: bounds.x + (bounds.width - measurement.size.width) * alignment.horizontalFactor,
                                       y: bounds.y + (bounds.height - measurement.size.height) * alignment.verticalFactor,
                                       width: measurement.size.width, height: measurement.size.height),
                        proposal: childProposal, cache: &cache)
        case .linearStack(let axis, let spacing):
            let childProposal = stackChildProposal(for: axis, parent: proposal)
            var cursor = axis == .horizontal ? bounds.x : bounds.y
            for child in children(id) {
                let measurement = measureNative(child, proposal: childProposal, cache: &cache)
                let childBounds: LayoutRect
                switch axis {
                case .horizontal:
                    childBounds = LayoutRect(x: cursor,
                                             y: bounds.y + (bounds.height - measurement.size.height) / 2,
                                             width: measurement.size.width, height: measurement.size.height)
                    cursor += measurement.size.width + spacing
                case .vertical:
                    childBounds = LayoutRect(x: bounds.x + (bounds.width - measurement.size.width) / 2,
                                             y: cursor,
                                             width: measurement.size.width, height: measurement.size.height)
                    cursor += measurement.size.height + spacing
                }
                placeNative(child, in: childBounds, proposal: childProposal, cache: &cache)
            }
        }
    }

    private func stackChildProposal(for axis: NativeStackAxis, parent: ProposedSize) -> ProposedSize {
        switch axis {
        case .horizontal: ProposedSize(width: nil, height: parent.height)
        case .vertical: ProposedSize(width: parent.width, height: nil)
        }
    }

    private func framedProposal(_ parent: Double?, fixed: Double?, ideal: Double?, min: Double?, max: Double?) -> Double? {
        guard fixed == nil else { return fixed }
        guard let proposal = parent ?? ideal else { return nil }
        return Swift.max(min ?? -.infinity, Swift.min(proposal, max ?? .infinity))
    }

    private func framedSize(_ child: Double, fixed: Double?, min: Double?, max: Double?) -> Double {
        guard let fixed else {
            return Swift.max(min ?? 0, Swift.min(child, max ?? .infinity))
        }
        return fixed
    }

    /// Native layout shares the legacy engine's root-absolute rounding contract.
    /// Measurement stays fractional; only the stored rectangles seen by later
    /// phases are rounded from cumulative edges.
    private func roundNativeStoredRects(_ node: LayoutNodeID) {
        setMeasuredWidth(node, layout(node).width)
        setLayout(node, roundLayout([layout(node)])[0])
        for child in children(node) {
            roundNativeStoredRects(child)
        }
    }
}

public typealias NativeMeasureFunction = @Sendable (ProposedSize) -> LayoutMeasurement

public enum NativeStackAxis: Sendable, Hashable {
    case horizontal
    case vertical
}

/// A frame-local equivalent of SwiftUI's nine-point alignment vocabulary.
public enum NativeAlignment: Sendable, Hashable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    var horizontalFactor: Double {
        switch self {
        case .topLeading, .leading, .bottomLeading: 0
        case .top, .center, .bottom: 0.5
        case .topTrailing, .trailing, .bottomTrailing: 1
        }
    }

    var verticalFactor: Double {
        switch self {
        case .topLeading, .top, .topTrailing: 0
        case .leading, .center, .trailing: 0.5
        case .bottomLeading, .bottom, .bottomTrailing: 1
        }
    }
}

private enum NativeNode {
    case leaf(NativeMeasureFunction)
    case overlay
    case frame(width: Double?, height: Double?, minWidth: Double?, idealWidth: Double?,
               maxWidth: Double?, minHeight: Double?, idealHeight: Double?,
               maxHeight: Double?, alignment: NativeAlignment)
    case linearStack(axis: NativeStackAxis, spacing: Double)
}

private struct NativeMeasurementKey: Hashable {
    let id: LayoutNodeID
    let proposal: ProposedSize
}
