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

    /// The native run in progress, `nil` outside a native layout call.
    ///
    /// Held only so `setLayout` can read `measureDepth` (ruling SA-H clause 4:
    /// measurement never writes a rect). It is set and cleared by the two
    /// native entry points; **the cache is never reachable from here once the
    /// call returns**, so nothing survives a call (clause 1, ruling C-3's
    /// footing).
    private var activeNativeRun: NativeLayoutRun?

    /// The work the most recent `computeNativeLayout` or `measureNativeLayout`
    /// call did: leaf-closure and custom `sizeThatFits` calls, cache hits and
    /// cache misses (ruling SA-M). **Assigned, never accumulated**, when the
    /// call returns.
    ///
    /// **The counts live on the tree; the cache never does.** The record holds
    /// no `LayoutNodeID` and answers no layout question, so it is outside ruling
    /// C-3's objection to state outliving a run. It is here because only the
    /// tree is reachable after `Frame.render`. A test observable with no
    /// production reader, pinned by
    /// `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` and
    /// `nativeLayoutWorkIsPerCall`.
    private(set) var lastNativeLayoutWork = NativeLayoutWork()

    /// The stamp carried by every id this tree issues. Changed only by
    /// `reset(generation:)`, which is what makes the ids from before a reset
    /// detectably stale.
    public private(set) var generation: UInt64

    public init(generation: UInt64) { self.generation = generation }

    public var nodeCount: Int { styles.count }

    /// True while EITHER engine is laying this tree out: legacy `computeLayout`,
    /// or native `computeNativeLayout` / `measureNativeLayout` (ruling SA-I).
    ///
    /// Task 3 memoizes `measureNode` on the assumption that styles do not change
    /// during a run. Nothing enforced that before this flag, and a style written
    /// mid-layout would hand back a cached size computed for the *old* style —
    /// a wrong answer no fixture could catch, because the fixture and the golden
    /// would both be generated from the settled tree.
    ///
    /// **One flag for both engines, not one each.** They write the same
    /// `layouts` array through the same `setLayout`, and a legacy measurement
    /// memoizes against the same `styles`, so a second flag would let a native
    /// measure closure run legacy layout over this tree mid-run. While it is
    /// set, these trap: `setStyle`, every registration (`appendNode`, which
    /// `newNode`, `newLeaf` and every native registrar reach),
    /// `reset(generation:)`, and a re-entrant layout call of either engine
    /// (`beginLayout`'s message names `computeLayout` for history; it covers
    /// both).
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

    /// Registers a legacy (CSS) node.
    ///
    /// **A native child traps** (ruling SA-G): the CSS engine would lay it out
    /// as an empty flex box whose measure never runs, stored at a centred 0×0.
    /// There is no adapter in either direction; the root is the boundary
    /// (`Frame.computeRootLayout`). Native registrars do not come through here:
    /// they append their placeholder `Style.default` row through `appendNode`.
    public func newNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        for child in children {
            precondition(nativeNodes[slot(child)] == nil,
                         "legacy layout node given a native child — a proposal subtree cannot sit under a CSS container (SA-G)")
        }
        return appendNode(style: style, children: children)
    }

    /// The storage append every registration reaches: `newNode`, `newLeaf`
    /// (through `newNode`) and every native registrar.
    ///
    /// **It holds the registration check and not the native-child check.** A
    /// registration while either engine is laying the tree out grows the arrays
    /// the run is indexing (ruling SA-I), so it traps here, once, for every
    /// path. The native-child check lives in `newNode` alone, because native
    /// registrars append native children by design.
    private func appendNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        precondition(!isLayingOut, "layout node registered while layout is running (SA-I)")
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
        let id = appendNode(style: .default, children: [])
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
        let id = appendNode(style: .default, children: children)
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
        let id = appendNode(style: .default, children: [child, overlay])
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
    ///
    /// **Validation (ruling SA-J)**, per axis, each a trap naming the
    /// parameter:
    /// - a fixed dimension must be finite and non-negative (SwiftUI logs
    ///   "Invalid frame dimension", P3); zero is accepted;
    /// - a minimum must not be NaN or +∞ (P4, P4b); a negative one, −∞
    ///   included, is accepted and answers the child's size (P9);
    /// - a maximum must be non-negative (P4, P9); +∞ is accepted (P4c);
    /// - an ideal must be finite and non-negative. +∞ gets no SwiftUI
    ///   diagnostic, but answers ∞ at the unspecified proposal every stack child
    ///   receives (P4b), so it is rejected here, where the message can name it;
    /// - min ≤ ideal ≤ max where both are given ("Contradictory frame
    ///   constraints", P4, P4c);
    /// - a fixed dimension with a flexible one on the SAME axis traps. SwiftUI
    ///   has no spelling for it, and neither does MetalUI's element API, which
    ///   splits `frame` into SwiftUI's two overloads (SA-K item 6); this one
    ///   signature keeps the check as a backstop for kernel callers. A fixed
    ///   dimension on one axis and a flexible one on the other is accepted.
    public func newNativeFrame(child: LayoutNodeID, width: Double? = nil,
                               height: Double? = nil,
                               minWidth: Double? = nil, idealWidth: Double? = nil,
                               maxWidth: Double? = nil,
                               minHeight: Double? = nil, idealHeight: Double? = nil,
                               maxHeight: Double? = nil,
                               alignment: ProposalAlignment = .center) -> LayoutNodeID {
        _ = nativeNode(child)
        Self.validateFrameAxis("width", "Width", fixed: width, min: minWidth, ideal: idealWidth, max: maxWidth)
        Self.validateFrameAxis("height", "Height", fixed: height, min: minHeight, ideal: idealHeight, max: maxHeight)
        let id = appendNode(style: .default, children: [child])
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
    ///
    /// **Every inset must be finite** (ruling SA-J): SwiftUI answers inf×inf
    /// for +∞ (P2), traps placing the child for NaN, and places it at −∞ for
    /// −∞ (P2c). **A negative inset is accepted**, and the measured response is
    /// clamped at 0 per axis, as SwiftUI's is (P2, P2b; ruling SA-K item 3).
    public func newNativePadding(child: LayoutNodeID,
                                 insets: Edges<Double>) -> LayoutNodeID {
        _ = nativeNode(child)
        precondition(insets.top.isFinite && insets.right.isFinite
                        && insets.bottom.isFinite && insets.left.isFinite,
                     "padding insets must be finite (SA-J), got \(insets)")
        let id = appendNode(style: .default, children: [child])
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
        let id = appendNode(style: .default, children: [child])
        nativeNodes[id.index] = .fixedSize(horizontal: horizontal, vertical: vertical)
        return id
    }

    /// Registers an aspect-ratio proposal wrapper around exactly one child.
    ///
    /// The wrapper derives a ratio-constrained proposal from its parent, then
    /// reports and places that resolved rectangle. `.fit` inscribes the
    /// rectangle inside a concrete proposal; `.fill` circumscribes it. An
    /// unspecified parent axis is derived from its specified counterpart.
    ///
    /// **The ratio must be finite and non-zero** (ruling SA-J): SwiftUI answers
    /// nan for NaN and ±∞, and 0 answers 0×inf on a one-axis proposal (P8, P9).
    /// **A negative ratio is accepted**, as SwiftUI accepts it (P8, P8b; ruling
    /// SA-K item 2): −2 `.fit` at 100×80 answers 100×−50.
    public func newNativeAspectRatio(child: LayoutNodeID, ratio: Double,
                                     contentMode: AspectRatioContentMode = .fit) -> LayoutNodeID {
        _ = nativeNode(child)
        precondition(ratio.isFinite && ratio != 0,
                     "aspect ratio must be finite and non-zero (SA-J), got \(ratio)")
        let id = appendNode(style: .default, children: [child])
        nativeNodes[id.index] = .aspectRatio(ratio: ratio, contentMode: contentMode)
        return id
    }

    /// Registers a layout-priority wrapper around one proposal-layout child.
    ///
    /// Priority is consumed by a native linear stack when it divides a
    /// constrained main-axis proposal. Outside such a stack it is layout
    /// transparent, matching SwiftUI's modifier role.
    ///
    /// **NaN traps** (ruling SA-J): SwiftUI hangs on it (P7). **±∞ is
    /// accepted** and orders like any finite priority, +∞ first and −∞ last
    /// (P7, P7b; ruling SA-K item 1): the stack's `Set(...).sorted(by: >)`
    /// already sorts them correctly.
    public func newNativeLayoutPriority(child: LayoutNodeID, priority: Double) -> LayoutNodeID {
        _ = nativeNode(child)
        precondition(!priority.isNaN, "layout priority must not be NaN (SA-J)")
        let id = appendNode(style: .default, children: [child])
        nativeNodes[id.index] = .layoutPriority(priority)
        return id
    }

    /// Registers a native flexible spacer with an optional minimum length.
    ///
    /// A spacer reports its minimum when its main axis is unspecified. Native
    /// linear stacks recognise it through a layout-priority wrapper as well as
    /// directly, and divide any concrete offered surplus among them during
    /// placement.
    ///
    /// **A given minimum must be finite** (ruling SA-J): SwiftUI answers −inf
    /// for NaN and ±inf for ±∞ (P5, P9). A negative minimum is accepted:
    /// `Spacer(minLength: −30)` between two 20s answers 10 (P5).
    public func newNativeSpacer(minLength: Double? = nil) -> LayoutNodeID {
        if let minLength {
            precondition(minLength.isFinite, "spacer minLength must be finite (SA-J), got \(minLength)")
        }
        let id = appendNode(style: .default, children: [])
        nativeNodes[id.index] = .spacer(minLength: minLength ?? 0)
        return id
    }

    /// Registers a native linear stack with explicit inter-item spacing.
    ///
    /// A linear stack uses the supplied alignment only on its cross axis:
    /// horizontal stacks read its vertical component and vertical stacks read
    /// its horizontal component. The default is SwiftUI's centred stack
    /// alignment.
    ///
    /// **Spacing must be finite** (ruling SA-J): SwiftUI answers nan and ±inf
    /// (P1, P9). **Negative spacing is accepted, unclamped**: `{20; 20}` at −10
    /// answers 30, and at −100 answers −60, as SwiftUI does (P1).
    public func newNativeLinearStack(children: [LayoutNodeID], axis: ProposalStackAxis,
                                     spacing: Double = 0,
                                     alignment: ProposalAlignment = .center) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        precondition(spacing.isFinite, "linear stack spacing must be finite (SA-J), got \(spacing)")
        let id = appendNode(style: .default, children: children)
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
        let id = appendNode(style: .default, children: [child])
        nativeNodes[id.index] = .scrollViewport(axis: axis)
        return id
    }

    /// Registers a custom proposal-layout algorithm over native children.
    ///
    /// The one protocol-backed node kind; the eleven built-ins stay enum cases
    /// (ruling SA-B). Every child must already be native, as for every other
    /// native container.
    public func newNativeLayout(_ layout: some ProposalLayout,
                                children: [LayoutNodeID]) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        let id = appendNode(style: .default, children: children)
        nativeNodes[id.index] = .custom(layout)
        return id
    }

    /// Measures and places one all-native subtree into the existing rect store.
    ///
    /// `bounds` is root-absolute, matching the contract `Frame.bounds(of:)`
    /// already exposes to prepaint and paint.
    ///
    /// **The invalidation contract (ruling SA-H).** Measurements are cached for
    /// this call only, keyed by node and proposal, in a `NativeLayoutRun` that
    /// is created here and marked inactive on return. Nothing survives into
    /// another call, another frame or a `reset(generation:)`, so invalidation
    /// is by construction and there are no dirty flags. That deliberately
    /// diverges from SwiftUI, whose memo survives passes (probes F and G).
    /// Within the call each `(node, proposal)` body runs at most once.
    ///
    /// **Holds `isLayingOut` for its whole body** (ruling SA-I), so a measure
    /// closure or custom layout that restyles, registers into, resets or
    /// re-lays-out this tree traps, and so does a rect written from inside
    /// measurement. A rect written from a custom `placeSubviews` is NOT checked.
    ///
    /// **Validated at three checkpoints** (ruling SA-J): a NaN proposal traps
    /// at every measurement's entry, a NaN measurement at its exit, and a
    /// non-finite rect before it is stored, `bounds` included. A measurement
    /// may be infinite; a stored rect may not; nothing may be NaN. Recursion
    /// deeper than `NativeLayoutRun.maxDepth` native levels traps with the node
    /// named (ruling SA-L). The work done is left in `lastNativeLayoutWork`.
    @discardableResult
    public func computeNativeLayout(root: LayoutNodeID, proposal: ProposedSize,
                                    in bounds: LayoutRect) -> LayoutMeasurement {
        beginLayout()
        defer { endLayout() }
        let run = NativeLayoutRun(tree: self)
        activeNativeRun = run
        defer {
            run.isActive = false
            activeNativeRun = nil
            lastNativeLayoutWork = run.work
        }
        let result = measureNative(root, proposal: proposal, run: run)
        placeNative(root, in: bounds, proposal: proposal, run: run)
        roundNativeStoredRects(root)
        return result
    }

    /// Measures one all-native subtree and writes nothing: no rect, no measured
    /// width (ruling SA-H clause 4).
    ///
    /// The contract's "measurement never writes a rect" needs an entry point
    /// that does nothing else, and this is it. Same run lifetime, the same
    /// `isLayingOut` bracket, the same checkpoints 1 and 2 and depth guard as
    /// `computeNativeLayout`, and it too leaves its work in
    /// `lastNativeLayoutWork`.
    func measureNativeLayout(root: LayoutNodeID, proposal: ProposedSize) -> LayoutMeasurement {
        beginLayout()
        defer { endLayout() }
        let run = NativeLayoutRun(tree: self)
        activeNativeRun = run
        defer {
            run.isActive = false
            activeNativeRun = nil
            lastNativeLayoutWork = run.work
        }
        return measureNative(root, proposal: proposal, run: run)
    }

    /// Whether this node belongs to the native layout path.
    public func isNativeLayoutNode(_ id: LayoutNodeID) -> Bool {
        nativeNodes[slot(id)] != nil
    }

    public func style(_ id: LayoutNodeID) -> Style { styles[slot(id)] }

    /// Writes a legacy node's style.
    ///
    /// Traps while either engine is laying the tree out (ruling SA-I), and on a
    /// native node at any time (ruling SA-G): the proposal engine never reads
    /// `Style`, so the write would be silently inert. The reachable route is a
    /// legacy `width`/`height` on a proposal `Component` (`StyledComponent`'s
    /// amend); its `padding` wraps instead and meets `newNode`'s native-child
    /// check.
    public func setStyle(_ id: LayoutNodeID, _ s: Style) {
        precondition(!isLayingOut,
                     "setStyle called while computeLayout is running — measured sizes are memoized against the styles this would change")
        precondition(nativeNodes[slot(id)] == nil,
                     "setStyle on a native layout node — the proposal engine never reads Style (SA-G)")
        styles[slot(id)] = s
    }

    public func children(_ id: LayoutNodeID) -> [LayoutNodeID] { childLists[slot(id)] }
    public func measure(_ id: LayoutNodeID) -> MeasureFunction? { measures[slot(id)] }
    public func layout(_ id: LayoutNodeID) -> LayoutRect { layouts[slot(id)] }
    /// Stores a node's root-absolute rect.
    ///
    /// Traps while a native measurement body is running (ruling SA-H clause 4):
    /// measurement never writes a rect. Placement, including a custom layout's
    /// `placeSubviews`, is not checked, because the kernel's own placement
    /// writes through here.
    public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect) {
        precondition((activeNativeRun?.measureDepth ?? 0) == 0,
                     "setLayout called during native measurement — measurement never writes a rect (SA-H)")
        layouts[slot(id)] = r
    }

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
    ///
    /// **Traps while either engine is laying the tree out** (ruling SA-I): it
    /// would empty the arrays the run is indexing, and the run would then die
    /// on the next stale-id read with a message about neither.
    public func reset(generation: UInt64) {
        precondition(!isLayingOut, "reset(generation:) called while layout is running (SA-I)")
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

    /// One node's answer to one proposal, memoized in `run` (ruling SA-H).
    ///
    /// Internal rather than private so subview proxies (`ProposalLayout.swift`)
    /// measure through the same cache. `run.measureDepth` is raised around
    /// every body, built-in or custom, so a `PlacementSubview` used from inside
    /// any measurement traps (ruling SA-C), and so does `setLayout` (ruling
    /// SA-H clause 4).
    ///
    /// **Entered in the depth guard before anything else** (ruling SA-L), a
    /// cache hit included, and left on return. **Checkpoint 1** traps on a NaN
    /// proposal axis before the lookup, so the key never holds a NaN (SA-H
    /// clause 3). **Checkpoint 2** traps on a NaN size or baseline after the
    /// body, before the answer is cached; an infinite answer passes (ruling
    /// SA-J). Every lookup counts a hit or a miss, and every leaf closure or
    /// custom `sizeThatFits` counts a call (ruling SA-M).
    func measureNative(_ id: LayoutNodeID, proposal: ProposedSize,
                       run: NativeLayoutRun)
        -> LayoutMeasurement {
        run.enter(id)
        defer { run.leave() }
        precondition(!(proposal.width?.isNaN ?? false) && !(proposal.height?.isNaN ?? false),
                     "native layout received a NaN proposal \(proposal) at node \(id) (SA-J)")
        let key = NativeMeasurementKey(id: id, proposal: proposal)
        if let cached = run.cache[key] {
            run.work.cacheHits += 1
            return cached
        }
        run.work.cacheMisses += 1

        run.measureDepth += 1
        let result: LayoutMeasurement
        switch nativeNode(id) {
        case .leaf(let measure):
            run.work.measureCalls += 1
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
            // Clamped at 0 per axis, as SwiftUI's response is: −15 on 20 answers
            // 0, and leading −30 / trailing 5 on 20 answers 0×20 (P2, P2b;
            // ruling SA-K item 3). Unchanged for non-negative insets over a
            // non-negative child.
            result = LayoutMeasurement(
                size: SizeD(width: Swift.max(0, child.size.width + insets.left + insets.right),
                            height: Swift.max(0, child.size.height + insets.top + insets.bottom)),
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
        case .custom(let layout):
            run.work.measureCalls += 1
            result = layout.sizeThatFits(proposal: proposal,
                                         subviews: MeasurementSubviews(run: run, nodes: children(id)))
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
        run.measureDepth -= 1
        precondition(!result.size.width.isNaN && !result.size.height.isNaN
                        && !(result.firstBaseline?.isNaN ?? false)
                        && !(result.lastBaseline?.isNaN ?? false),
                     "native layout produced a NaN measurement \(result) at node \(id) (SA-J)")
        run.cache[key] = result
        return result
    }

    /// Stores `id` at `bounds` and places its subtree.
    ///
    /// **Entered in the depth guard** like `measureNative`, on the same counter,
    /// so the guard tracks the real stack across placement and the measurement
    /// it calls (ruling SA-L). **Checkpoint 3** traps on any non-finite field
    /// of `bounds` before it is stored: root bounds, a proxy's position and a
    /// child's infinite answer all arrive here (ruling SA-J). Negative widths
    /// and heights pass.
    private func placeNative(_ id: LayoutNodeID, in bounds: LayoutRect,
                             proposal: ProposedSize,
                             run: NativeLayoutRun) {
        run.enter(id)
        defer { run.leave() }
        precondition(bounds.x.isFinite && bounds.y.isFinite
                        && bounds.width.isFinite && bounds.height.isFinite,
                     "native layout would store a non-finite rect \(bounds) at node \(id) (SA-J)")
        setLayout(id, bounds)
        switch nativeNode(id) {
        case .leaf, .spacer:
            return
        case .custom(let layout):
            placeCustom(id, layout: layout, in: bounds, proposal: proposal, run: run)
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

    /// Places a `ProposalLayout` node's children (ruling SA-E).
    ///
    /// `placeSubviews` only records placements; each child's subtree is placed
    /// here, once, after it returns, in index order. A recorded child is stored
    /// at its answer to the record's proposal, offset from the record's
    /// position by the anchor's factors times that answer; an unrecorded child
    /// is measured at the parent's proposal and centred in `bounds` (probe I2).
    private func placeCustom(_ id: LayoutNodeID, layout: any ProposalLayout,
                             in bounds: LayoutRect, proposal: ProposedSize,
                             run: NativeLayoutRun) {
        let nodes = children(id)
        let records = NativePlacementRecords(count: nodes.count)
        let token = run.nextPlacementToken
        run.nextPlacementToken += 1
        let enclosing = run.activePlacement
        run.activePlacement = token
        layout.placeSubviews(in: bounds, proposal: proposal,
                             subviews: PlacementSubviews(run: run, nodes: nodes, token: token,
                                                         records: records))
        run.activePlacement = enclosing

        for (index, child) in nodes.enumerated() {
            if let record = records.records[index] {
                let size = measureNative(child, proposal: record.proposal, run: run).size
                placeNative(child,
                            in: LayoutRect(x: record.position.x - record.anchor.horizontalFactor * size.width,
                                           y: record.position.y - record.anchor.verticalFactor * size.height,
                                           width: size.width, height: size.height),
                            proposal: record.proposal, run: run)
            } else {
                let size = measureNative(child, proposal: proposal, run: run).size
                placeNative(child,
                            in: LayoutRect(x: bounds.x + (bounds.width - size.width) * 0.5,
                                           y: bounds.y + (bounds.height - size.height) * 0.5,
                                           width: size.width, height: size.height),
                            proposal: proposal, run: run)
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

    func isNativeSpacer(_ id: LayoutNodeID) -> Bool {
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

    /// One axis of `newNativeFrame`'s validation (ruling SA-J); `axis` and
    /// `Axis` spell the parameter names the messages carry.
    private static func validateFrameAxis(_ axis: String, _ Axis: String, fixed: Double?,
                                          min: Double?, ideal: Double?, max: Double?) {
        if let fixed {
            precondition(fixed >= 0 && fixed.isFinite,
                         "frame \(axis) must be finite and non-negative (SA-J), got \(fixed)")
            precondition(min == nil && ideal == nil && max == nil,
                         "frame \(axis) cannot be combined with min\(Axis), ideal\(Axis) or max\(Axis) (SA-J)")
        }
        if let min {
            precondition(!min.isNaN && min != .infinity,
                         "frame min\(Axis) must not be NaN or +infinity (SA-J), got \(min)")
        }
        if let max {
            precondition(max >= 0, "frame max\(Axis) must be non-negative (SA-J), got \(max)")
        }
        if let ideal {
            precondition(ideal >= 0 && ideal.isFinite,
                         "frame ideal\(Axis) must be finite and non-negative (SA-J), got \(ideal)")
        }
        if let min, let max {
            precondition(min <= max, "frame min\(Axis) must not exceed max\(Axis) (SA-J), got \(min) > \(max)")
        }
        if let min, let ideal {
            precondition(min <= ideal, "frame min\(Axis) must not exceed ideal\(Axis) (SA-J), got \(min) > \(ideal)")
        }
        if let ideal, let max {
            precondition(ideal <= max, "frame ideal\(Axis) must not exceed max\(Axis) (SA-J), got \(ideal) > \(max)")
        }
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
            // `width / ratio` is the height the width branch would give. `.fit`
            // takes that branch when it fits the proposed height, `.fill` when it
            // covers it. For a positive ratio and positive axes this is the old
            // `width / height <= ratio`; unlike it, it picks SwiftUI's branch for
            // a negative ratio and at zero or negative axes, 24 of 24 P8c arms
            // against 12 (ruling SA-K item 2).
            let usesWidth: Bool
            switch contentMode {
            case .fit: usesWidth = width / ratio <= height
            case .fill: usesWidth = width / ratio >= height
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

    /// The fraction of the free width placed before a child: 0 leading,
    /// 0.5 centred, 1 trailing. Public so an outside `ProposalLayout` that
    /// takes an alignment can compute a cross-axis offset (ruling SA-F).
    public var horizontalFactor: Double {
        switch self {
        case .topLeading, .leading, .bottomLeading: 0
        case .top, .center, .bottom: 0.5
        case .topTrailing, .trailing, .bottomTrailing: 1
        }
    }

    /// The fraction of the free height placed above a child: 0 top,
    /// 0.5 centred, 1 bottom.
    public var verticalFactor: Double {
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
    case custom(any ProposalLayout)
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
