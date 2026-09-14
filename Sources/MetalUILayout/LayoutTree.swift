import MetalUICore

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
    public func newNativeLeaf(measure: @escaping ProposalMeasureFunction) -> LayoutNodeID {
        let id = newNode(style: .default, children: [])
        nativeNodes[id.index] = .leaf(measure)
        return id
    }

    /// Registers a native overlay, equivalent to a SwiftUI `ZStack`.
    ///
    /// Every child must already be native. This makes the migration boundary
    /// structural: a native subtree cannot accidentally delegate one child back
    /// into the CSS engine. Every child receives the same proposal, then is
    /// placed independently with the requested alignment.
    public func newNativeOverlay(children: [LayoutNodeID],
                                 alignment: ProposalAlignment = .center) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        let id = newNode(style: .default, children: children)
        nativeNodes[id.index] = .overlay(alignment: alignment)
        return id
    }

    /// Registers a SwiftUI-style overlay attachment around one primary child.
    ///
    /// Unlike a `ZStack`, the attachment is measured using the primary child's
    /// resolved size and never contributes to the wrapper's own measurement.
    public func newNativeOverlayAttachment(child: LayoutNodeID, overlay: LayoutNodeID,
                                           alignment: ProposalAlignment = .center) -> LayoutNodeID {
        _ = nativeNode(child)
        _ = nativeNode(overlay)
        let id = newNode(style: .default, children: [child, overlay])
        nativeNodes[id.index] = .overlayAttachment(alignment: alignment)
        return id
    }

    /// Registers a native fixed frame around exactly one native child.
    ///
    /// A fixed axis is proposed to the child and becomes the frame's measured
    /// size; an optional axis forwards the parent's proposal and adopts the
    /// child's response. When an ideal axis is used because its parent axis is
    /// unspecified, the clamped ideal also becomes the frame's response.
    /// Placement centres the child inside the resulting frame, matching
    /// SwiftUI's default frame alignment.
    public func newNativeFrame(child: LayoutNodeID, width: Double? = nil,
                               height: Double? = nil,
                               minWidth: Double? = nil, idealWidth: Double? = nil,
                               maxWidth: Double? = nil,
                               minHeight: Double? = nil, idealHeight: Double? = nil,
                               maxHeight: Double? = nil,
                               alignment: ProposalAlignment = .center) -> LayoutNodeID {
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

    /// Registers native outer padding around exactly one native child.
    ///
    /// Padding reduces each concrete proposal before measuring the child, then
    /// adds those insets back to the measured response and placement. An
    /// unspecified axis remains unspecified, so padding never invents a
    /// constraint that the parent did not offer.
    public func newNativePadding(child: LayoutNodeID,
                                 insets: Edges<Double>) -> LayoutNodeID {
        _ = nativeNode(child)
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .padding(insets: insets)
        return id
    }

    /// Registers native fixed-size behavior around exactly one native child.
    ///
    /// A fixed axis is deliberately left unspecified when measuring the child,
    /// preserving that axis's intrinsic response instead of accepting the
    /// parent's offered size. The wrapper reports that response unchanged.
    public func newNativeFixedSize(child: LayoutNodeID,
                                   horizontal: Bool = true,
                                   vertical: Bool = true) -> LayoutNodeID {
        _ = nativeNode(child)
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .fixedSize(horizontal: horizontal, vertical: vertical)
        return id
    }

    /// Registers an aspect-ratio proposal wrapper around exactly one child.
    ///
    /// The wrapper derives a ratio-constrained proposal from its parent, then
    /// reports and places that resolved rectangle. `.fit` inscribes the
    /// rectangle inside a concrete proposal; `.fill` circumscribes it. An
    /// unspecified parent axis is derived from its specified counterpart.
    public func newNativeAspectRatio(child: LayoutNodeID, ratio: Double,
                                     contentMode: AspectRatioContentMode = .fit) -> LayoutNodeID {
        _ = nativeNode(child)
        precondition(ratio.isFinite && ratio > 0,
                     "aspect ratio must be finite and greater than zero")
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .aspectRatio(ratio: ratio, contentMode: contentMode)
        return id
    }

    /// Registers a layout-priority wrapper around one proposal-layout child.
    ///
    /// Priority is consumed by a native linear stack when it divides a
    /// constrained main-axis proposal. Outside such a stack it is layout
    /// transparent, matching SwiftUI's modifier role.
    public func newNativeLayoutPriority(child: LayoutNodeID, priority: Double) -> LayoutNodeID {
        _ = nativeNode(child)
        precondition(priority.isFinite, "layout priority must be finite")
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .layoutPriority(priority)
        return id
    }

    /// Registers a native flexible spacer with an optional minimum length.
    ///
    /// A spacer reports its minimum when its main axis is unspecified. Native
    /// linear stacks recognise it through a layout-priority wrapper as well as
    /// directly, and divide any concrete offered surplus among them during
    /// placement.
    public func newNativeSpacer(minLength: Double? = nil) -> LayoutNodeID {
        let id = newNode(style: .default, children: [])
        nativeNodes[id.index] = .spacer(minLength: minLength ?? 0)
        return id
    }

    /// Registers a native linear stack with explicit inter-item spacing.
    ///
    /// A linear stack uses the supplied alignment only on its cross axis:
    /// horizontal stacks read its vertical component and vertical stacks read
    /// its horizontal component. The default is SwiftUI's centred stack
    /// alignment.
    public func newNativeLinearStack(children: [LayoutNodeID], axis: ProposalStackAxis,
                                     spacing: Double = 0,
                                     alignment: ProposalAlignment = .center) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        let id = newNode(style: .default, children: children)
        nativeNodes[id.index] = .linearStack(axis: axis, spacing: spacing,
                                             alignment: alignment)
        return id
    }

    /// Registers a proposal-layout scrolling viewport around one native child.
    ///
    /// The content receives an unspecified proposal along the scrolling axis,
    /// while the viewport adopts a concrete parent proposal when one exists.
    /// Geometry stays untransformed here; the owning element applies its stored
    /// scroll offset during prepaint and paint.
    public func newNativeScrollViewport(child: LayoutNodeID,
                                        axis: ProposalStackAxis) -> LayoutNodeID {
        _ = nativeNode(child)
        let id = newNode(style: .default, children: [child])
        nativeNodes[id.index] = .scrollViewport(axis: axis)
        return id
    }

    /// Measures and places one all-native subtree into the existing rect store.
    ///
    /// `bounds` is root-absolute, matching the contract `Frame.bounds(of:)`
    /// already exposes to prepaint and paint. Measurements are cached only for
    /// this call, keyed by both node and proposal, in a `NativeLayoutRun` that
    /// is created here and marked inactive on return; a later frame receives a
    /// new tree and therefore a new run.
    @discardableResult
    public func computeNativeLayout(root: LayoutNodeID, proposal: ProposedSize,
                                    in bounds: LayoutRect) -> LayoutMeasurement {
        let run = NativeLayoutRun(tree: self)
        defer { run.isActive = false }
        let result = measureNative(root, proposal: proposal, run: run)
        placeNative(root, in: bounds, proposal: proposal, run: run)
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
                               run: NativeLayoutRun)
        -> LayoutMeasurement {
        let key = NativeMeasurementKey(id: id, proposal: proposal)
        if let cached = run.cache[key] { return cached }

        let result: LayoutMeasurement
        switch nativeNode(id) {
        case .leaf(let measure):
            result = measure(proposal)
        case .spacer(let minLength):
            result = LayoutMeasurement(size: SizeD(
                width: spacerLength(for: proposal.width, minimum: minLength),
                height: spacerLength(for: proposal.height, minimum: minLength)
            ))
        case .overlay:
            result = children(id).reduce(LayoutMeasurement(size: .zero)) { current, child in
                let childMeasurement = measureNative(child, proposal: proposal, run: run)
                return LayoutMeasurement(
                    size: SizeD(width: max(current.size.width, childMeasurement.size.width),
                                height: max(current.size.height, childMeasurement.size.height))
                )
            }
        case .overlayAttachment:
            let child = measureNative(children(id)[0], proposal: proposal, run: run)
            _ = measureNative(children(id)[1],
                              proposal: ProposedSize(width: child.size.width, height: child.size.height),
                              run: run)
            result = child
        case .frame(let width, let height, let minWidth, let idealWidth, let maxWidth, let minHeight, let idealHeight, let maxHeight, let alignment):
            let childProposal = ProposedSize(width: framedProposal(proposal.width, fixed: width, ideal: idealWidth, min: minWidth, max: maxWidth),
                                             height: framedProposal(proposal.height, fixed: height, ideal: idealHeight, min: minHeight, max: maxHeight))
            let child = measureNative(children(id)[0], proposal: childProposal, run: run)
            let frameWidth = framedSize(child.size.width, proposal: proposal.width,
                                        fixed: width, ideal: idealWidth, min: minWidth, max: maxWidth)
            let frameHeight = framedSize(child.size.height, proposal: proposal.height,
                                         fixed: height, ideal: idealHeight, min: minHeight, max: maxHeight)
            result = LayoutMeasurement(
                size: SizeD(width: frameWidth, height: frameHeight),
                firstBaseline: child.firstBaseline.map { $0 + (frameHeight - child.size.height) * alignment.verticalFactor },
                lastBaseline: child.lastBaseline.map { $0 + (frameHeight - child.size.height) * alignment.verticalFactor }
            )
        case .padding(let insets):
            let childProposal = paddingProposal(proposal, insets: insets)
            let child = measureNative(children(id)[0], proposal: childProposal, run: run)
            result = LayoutMeasurement(
                size: SizeD(width: child.size.width + insets.left + insets.right,
                            height: child.size.height + insets.top + insets.bottom),
                firstBaseline: child.firstBaseline.map { $0 + insets.top },
                lastBaseline: child.lastBaseline.map { $0 + insets.top }
            )
        case .fixedSize(let horizontal, let vertical):
            result = measureNative(children(id)[0],
                                   proposal: fixedSizeProposal(proposal,
                                                               horizontal: horizontal,
                                                               vertical: vertical),
                                   run: run)
        case .aspectRatio(let ratio, let contentMode):
            let child = children(id)[0]
            let intrinsic = measureNative(child, proposal: proposal, run: run)
            let size = aspectRatioSize(proposal: proposal, intrinsic: intrinsic.size,
                                       ratio: ratio, contentMode: contentMode)
            let constrained = measureNative(child,
                                            proposal: ProposedSize(width: size.width, height: size.height),
                                            run: run)
            result = LayoutMeasurement(
                size: size,
                firstBaseline: constrained.firstBaseline,
                lastBaseline: constrained.lastBaseline
            )
        case .layoutPriority:
            result = measureNative(children(id)[0], proposal: proposal, run: run)
        case .scrollViewport(let axis):
            let content = measureNative(children(id)[0],
                                        proposal: scrollContentProposal(for: axis, parent: proposal),
                                        run: run)
            result = LayoutMeasurement(size: scrollViewportSize(proposal: proposal, content: content.size))
        case .linearStack(let axis, let spacing, _):
            let childProposal = stackChildProposal(for: axis, parent: proposal)
            let childMeasurements = children(id).map {
                measureNative($0, proposal: childProposal, run: run)
            }
            let gaps = Double(max(0, childMeasurements.count - 1)) * spacing
            let hasSpacer = children(id).contains(where: isNativeSpacer)
            switch axis {
            case .horizontal:
                let naturalWidth = childMeasurements.reduce(gaps) { $0 + $1.size.width }
                result = LayoutMeasurement(
                    size: SizeD(width: resolvedStackMainSize(naturalWidth, proposal: proposal.width,
                                                             hasSpacer: hasSpacer),
                                height: childMeasurements.map(\.size.height).max() ?? 0)
                )
            case .vertical:
                let naturalHeight = childMeasurements.reduce(gaps) { $0 + $1.size.height }
                result = LayoutMeasurement(
                    size: SizeD(width: childMeasurements.map(\.size.width).max() ?? 0,
                                height: resolvedStackMainSize(naturalHeight, proposal: proposal.height,
                                                              hasSpacer: hasSpacer))
                )
            }
        }
        run.cache[key] = result
        return result
    }

    private func placeNative(_ id: LayoutNodeID, in bounds: LayoutRect,
                             proposal: ProposedSize,
                             run: NativeLayoutRun) {
        setLayout(id, bounds)
        switch nativeNode(id) {
        case .leaf, .spacer:
            return
        case .overlay(let alignment):
            for child in children(id) {
                let measurement = measureNative(child, proposal: proposal, run: run)
                placeNative(child,
                            in: LayoutRect(x: bounds.x + (bounds.width - measurement.size.width) * alignment.horizontalFactor,
                                           y: bounds.y + (bounds.height - measurement.size.height) * alignment.verticalFactor,
                                           width: measurement.size.width, height: measurement.size.height),
                            proposal: proposal, run: run)
            }
        case .overlayAttachment(let alignment):
            let primary = children(id)[0]
            let overlay = children(id)[1]
            let primaryMeasurement = measureNative(primary, proposal: proposal, run: run)
            placeNative(primary, in: bounds, proposal: proposal, run: run)
            let overlayProposal = ProposedSize(width: primaryMeasurement.size.width,
                                               height: primaryMeasurement.size.height)
            let overlayMeasurement = measureNative(overlay, proposal: overlayProposal, run: run)
            placeNative(overlay,
                        in: LayoutRect(x: bounds.x + (bounds.width - overlayMeasurement.size.width) * alignment.horizontalFactor,
                                       y: bounds.y + (bounds.height - overlayMeasurement.size.height) * alignment.verticalFactor,
                                       width: overlayMeasurement.size.width, height: overlayMeasurement.size.height),
                        proposal: overlayProposal, run: run)
        case .frame(let width, let height, let minWidth, let idealWidth, let maxWidth, let minHeight, let idealHeight, let maxHeight, let alignment):
            let childProposal = ProposedSize(width: framedProposal(proposal.width, fixed: width, ideal: idealWidth, min: minWidth, max: maxWidth),
                                             height: framedProposal(proposal.height, fixed: height, ideal: idealHeight, min: minHeight, max: maxHeight))
            let child = children(id)[0]
            let measurement = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x + (bounds.width - measurement.size.width) * alignment.horizontalFactor,
                                       y: bounds.y + (bounds.height - measurement.size.height) * alignment.verticalFactor,
                                       width: measurement.size.width, height: measurement.size.height),
                        proposal: childProposal, run: run)
        case .padding(let insets):
            let childProposal = paddingProposal(proposal, insets: insets)
            let child = children(id)[0]
            _ = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x + insets.left,
                                       y: bounds.y + insets.top,
                                       width: Swift.max(0, bounds.width - insets.left - insets.right),
                                       height: Swift.max(0, bounds.height - insets.top - insets.bottom)),
                        proposal: childProposal, run: run)
        case .fixedSize(let horizontal, let vertical):
            let childProposal = fixedSizeProposal(proposal, horizontal: horizontal,
                                                  vertical: vertical)
            let child = children(id)[0]
            let measurement = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x, y: bounds.y,
                                       width: measurement.size.width, height: measurement.size.height),
                        proposal: childProposal, run: run)
        case .aspectRatio(let ratio, let contentMode):
            let child = children(id)[0]
            let intrinsic = measureNative(child, proposal: proposal, run: run)
            let size = aspectRatioSize(proposal: proposal, intrinsic: intrinsic.size,
                                       ratio: ratio, contentMode: contentMode)
            let childProposal = ProposedSize(width: size.width, height: size.height)
            _ = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x, y: bounds.y,
                                       width: size.width, height: size.height),
                        proposal: childProposal, run: run)
        case .layoutPriority:
            let child = children(id)[0]
            _ = measureNative(child, proposal: proposal, run: run)
            placeNative(child, in: bounds, proposal: proposal, run: run)
        case .scrollViewport(let axis):
            let child = children(id)[0]
            let childProposal = scrollContentProposal(for: axis, parent: proposal)
            let measurement = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x, y: bounds.y,
                                       width: measurement.size.width, height: measurement.size.height),
                        proposal: childProposal, run: run)
        case .linearStack(let axis, let spacing, let alignment):
            let childProposal = stackChildProposal(for: axis, parent: proposal)
            let childMeasurements = children(id).map {
                measureNative($0, proposal: childProposal, run: run)
            }
            let naturalMain = stackMainSize(childMeasurements, axis: axis, spacing: spacing)
            let spacerCount = children(id).filter(isNativeSpacer).count
            let availableMain = axis == .horizontal ? bounds.width : bounds.height
            let extraPerSpacer = spacerCount == 0 ? 0 : Swift.max(0, availableMain - naturalMain) / Double(spacerCount)
            let allocations = stackMainAllocations(children: children(id), measurements: childMeasurements,
                                                   axis: axis, available: availableMain,
                                                   spacing: spacing, hasSpacer: spacerCount > 0)
            var cursor = axis == .horizontal ? bounds.x : bounds.y
            for (index, (child, baseMeasurement)) in zip(children(id), childMeasurements).enumerated() {
                let placementProposal = spacerProposal(for: child, base: baseMeasurement,
                                                       parent: childProposal, axis: axis,
                                                       extra: extraPerSpacer)
                let constrainedProposal = stackPlacementProposal(placementProposal,
                                                                  axis: axis,
                                                                  allocatedMain: allocations[index])
                let measurement = measureNative(child, proposal: constrainedProposal, run: run)
                let childBounds: LayoutRect
                switch axis {
                case .horizontal:
                    childBounds = LayoutRect(x: cursor,
                                             y: bounds.y + (bounds.height - measurement.size.height) * alignment.verticalFactor,
                                             width: measurement.size.width, height: measurement.size.height)
                    cursor += measurement.size.width + spacing
                case .vertical:
                    childBounds = LayoutRect(x: bounds.x + (bounds.width - measurement.size.width) * alignment.horizontalFactor,
                                             y: cursor,
                                             width: measurement.size.width, height: measurement.size.height)
                    cursor += measurement.size.height + spacing
                }
                placeNative(child, in: childBounds, proposal: constrainedProposal, run: run)
            }
        }
    }

    private func stackChildProposal(for axis: ProposalStackAxis, parent: ProposedSize) -> ProposedSize {
        switch axis {
        case .horizontal: ProposedSize(width: nil, height: parent.height)
        case .vertical: ProposedSize(width: parent.width, height: nil)
        }
    }

    private func scrollContentProposal(for axis: ProposalStackAxis, parent: ProposedSize) -> ProposedSize {
        switch axis {
        case .horizontal: ProposedSize(width: nil, height: parent.height)
        case .vertical: ProposedSize(width: parent.width, height: nil)
        }
    }

    private func scrollViewportSize(proposal: ProposedSize, content: SizeD) -> SizeD {
        SizeD(width: resolvedViewportDimension(proposal.width, content: content.width),
              height: resolvedViewportDimension(proposal.height, content: content.height))
    }

    private func resolvedViewportDimension(_ proposal: Double?, content: Double) -> Double {
        guard let proposal, proposal.isFinite else { return content }
        return proposal
    }

    private func isNativeSpacer(_ id: LayoutNodeID) -> Bool {
        switch nativeNode(id) {
        case .spacer:
            return true
        case .layoutPriority:
            return isNativeSpacer(children(id)[0])
        default:
            return false
        }
    }

    private func spacerLength(for proposal: Double?, minimum: Double) -> Double {
        guard let proposal, proposal.isFinite else { return minimum }
        return Swift.max(minimum, proposal)
    }

    private func resolvedStackMainSize(_ natural: Double, proposal: Double?, hasSpacer: Bool) -> Double {
        guard let proposal, proposal.isFinite else { return natural }
        return hasSpacer ? Swift.max(natural, proposal) : Swift.min(natural, proposal)
    }

    private func stackMainSize(_ measurements: [LayoutMeasurement], axis: ProposalStackAxis,
                               spacing: Double) -> Double {
        let gaps = Double(Swift.max(0, measurements.count - 1)) * spacing
        switch axis {
        case .horizontal: return measurements.reduce(gaps) { $0 + $1.size.width }
        case .vertical: return measurements.reduce(gaps) { $0 + $1.size.height }
        }
    }

    private func spacerProposal(for child: LayoutNodeID, base: LayoutMeasurement,
                                parent: ProposedSize, axis: ProposalStackAxis,
                                extra: Double) -> ProposedSize {
        guard isNativeSpacer(child) else { return parent }
        switch axis {
        case .horizontal: return ProposedSize(width: base.size.width + extra, height: parent.height)
        case .vertical: return ProposedSize(width: parent.width, height: base.size.height + extra)
        }
    }

    private func stackPlacementProposal(_ proposal: ProposedSize, axis: ProposalStackAxis,
                                        allocatedMain: Double?) -> ProposedSize {
        guard let allocatedMain else { return proposal }
        switch axis {
        case .horizontal: return ProposedSize(width: allocatedMain, height: proposal.height)
        case .vertical: return ProposedSize(width: proposal.width, height: allocatedMain)
        }
    }

    private func stackMainAllocations(children: [LayoutNodeID], measurements: [LayoutMeasurement],
                                      axis: ProposalStackAxis, available: Double, spacing: Double,
                                      hasSpacer: Bool) -> [Double?] {
        let natural = stackMainSize(measurements, axis: axis, spacing: spacing)
        guard !hasSpacer, available < natural else { return Array(repeating: nil, count: children.count) }
        var allocations = Array<Double?>(repeating: nil, count: children.count)
        var remaining = Swift.max(0, available - Double(Swift.max(0, children.count - 1)) * spacing)
        let priorities = Set(children.map(nativeLayoutPriority)).sorted(by: >)
        for priority in priorities {
            let indices = children.indices.filter { nativeLayoutPriority(children[$0]) == priority }
            let ideal = indices.reduce(0) { partial, index in
                partial + stackMain(measurements[index], axis: axis)
            }
            if remaining >= ideal {
                for index in indices { allocations[index] = stackMain(measurements[index], axis: axis) }
                remaining -= ideal
            } else {
                let share = remaining / Double(indices.count)
                for index in indices { allocations[index] = share }
                remaining = 0
            }
        }
        return allocations
    }

    /// The priority a native stack (and a `ProposalLayout` subview proxy) reads
    /// for `id`: the value of a `layoutPriority` node that IS the child, looking
    /// through any depth of overlay attachments to their primary child, else 0.
    ///
    /// **The attachment look-through matches SwiftUI** (probe L2, ruling SA-D):
    /// `.overlay {}` does not lay its content out and leaves priority visible,
    /// while `frame`, `padding`, `aspectRatio` and `fixedSize` hide it, as they
    /// hide it in SwiftUI. MetalUI's paint-only proposal modifiers (`background`,
    /// `clip`, `border`, `opacity`, `allowsHitTesting`, `onTap`) register no node,
    /// so they need no case here. A single-child built-in stack does NOT pass
    /// its child's priority through, where SwiftUI's does (probe L3, SA-N item 8).
    /// Pinned by `aLinearStackReadsPriorityThroughAnOverlayAttachment`.
    func nativeLayoutPriority(_ id: LayoutNodeID) -> Double {
        switch nativeNode(id) {
        case .layoutPriority(let priority):
            return priority
        case .overlayAttachment:
            return nativeLayoutPriority(children(id)[0])
        default:
            return 0
        }
    }

    private func stackMain(_ measurement: LayoutMeasurement, axis: ProposalStackAxis) -> Double {
        switch axis {
        case .horizontal: measurement.size.width
        case .vertical: measurement.size.height
        }
    }

    private func framedProposal(_ parent: Double?, fixed: Double?, ideal: Double?, min: Double?, max: Double?) -> Double? {
        guard fixed == nil else { return fixed }
        guard let proposal = parent ?? ideal else { return nil }
        return Swift.max(min ?? -.infinity, Swift.min(proposal, max ?? .infinity))
    }

    private func framedSize(_ child: Double, proposal: Double?, fixed: Double?, ideal: Double?,
                            min: Double?, max: Double?) -> Double {
        guard let fixed else {
            if proposal == nil, let ideal {
                return Swift.max(min ?? 0, Swift.min(ideal, max ?? .infinity))
            }
            if max == .infinity, let proposal, proposal.isFinite {
                return Swift.max(min ?? 0, proposal)
            }
            return Swift.max(min ?? 0, Swift.min(child, max ?? .infinity))
        }
        return fixed
    }

    private func paddingProposal(_ parent: ProposedSize, insets: Edges<Double>) -> ProposedSize {
        ProposedSize(width: parent.width.map { Swift.max(0, $0 - insets.left - insets.right) },
                     height: parent.height.map { Swift.max(0, $0 - insets.top - insets.bottom) })
    }

    private func fixedSizeProposal(_ parent: ProposedSize, horizontal: Bool,
                                   vertical: Bool) -> ProposedSize {
        ProposedSize(width: horizontal ? nil : parent.width,
                     height: vertical ? nil : parent.height)
    }

    private func aspectRatioSize(proposal: ProposedSize, intrinsic: SizeD,
                                 ratio: Double,
                                 contentMode: AspectRatioContentMode) -> SizeD {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        switch (width, height) {
        case let (.some(width), .some(height)):
            let proposedRatio = width / height
            let usesWidth: Bool
            switch contentMode {
            case .fit: usesWidth = proposedRatio <= ratio
            case .fill: usesWidth = proposedRatio >= ratio
            }
            return usesWidth
                ? SizeD(width: width, height: width / ratio)
                : SizeD(width: height * ratio, height: height)
        case let (.some(width), .none):
            return SizeD(width: width, height: width / ratio)
        case let (.none, .some(height)):
            return SizeD(width: height * ratio, height: height)
        case (.none, .none):
            guard intrinsic.width > 0, intrinsic.height > 0 else { return .zero }
            let intrinsicRatio = intrinsic.width / intrinsic.height
            if intrinsicRatio <= ratio {
                return SizeD(width: intrinsic.width, height: intrinsic.width / ratio)
            }
            return SizeD(width: intrinsic.height * ratio, height: intrinsic.height)
        }
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

/// Measures a proposal-layout leaf's response.
public typealias ProposalMeasureFunction = @Sendable (ProposedSize) -> LayoutMeasurement

/// The main axis used by a proposal-layout stack.
public enum ProposalStackAxis: Sendable, Hashable {
    case horizontal
    case vertical
}

/// The two proposal strategies accepted by ``ElementGroup/aspectRatio(_:contentMode:)``.
public enum AspectRatioContentMode: Sendable, Hashable {
    /// Inscribe the requested ratio inside the proposed rectangle.
    case fit
    /// Circumscribe the proposed rectangle with the requested ratio.
    case fill
}

/// A frame-local equivalent of SwiftUI's nine-point alignment vocabulary.
public enum ProposalAlignment: Sendable, Hashable {
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
    case leaf(ProposalMeasureFunction)
    case overlay(alignment: ProposalAlignment)
    case overlayAttachment(alignment: ProposalAlignment)
    case frame(width: Double?, height: Double?, minWidth: Double?, idealWidth: Double?,
               maxWidth: Double?, minHeight: Double?, idealHeight: Double?,
               maxHeight: Double?, alignment: ProposalAlignment)
    case padding(insets: Edges<Double>)
    case fixedSize(horizontal: Bool, vertical: Bool)
    case aspectRatio(ratio: Double, contentMode: AspectRatioContentMode)
    case layoutPriority(Double)
    case spacer(minLength: Double)
    case scrollViewport(axis: ProposalStackAxis)
    case linearStack(axis: ProposalStackAxis, spacing: Double, alignment: ProposalAlignment)
}

/// Temporary source-compatible name for ``ProposalMeasureFunction``.
@available(*, deprecated, renamed: "ProposalMeasureFunction")
public typealias NativeMeasureFunction = ProposalMeasureFunction

/// Temporary source-compatible name for ``ProposalStackAxis``.
@available(*, deprecated, renamed: "ProposalStackAxis")
public typealias NativeStackAxis = ProposalStackAxis

/// Temporary source-compatible name for ``ProposalAlignment``.
@available(*, deprecated, renamed: "ProposalAlignment")
public typealias NativeAlignment = ProposalAlignment
