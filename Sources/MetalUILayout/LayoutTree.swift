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

    /// The axis of the linear stack that marked each spacer, by node index
    /// (ruling CN-C). A marked spacer answers 0 on that stack's CROSS axis.
    /// Written at registration by `newNativeLinearStack`'s walk
    /// (`markSpacers`), cleared by `reset(generation:)`, never written during
    /// layout. A stored property on a public class read across a module
    /// boundary: `swift package clean` after changing it (CN-R).
    private var spacerAxes: [Int: ProposalStackAxis] = [:]

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

    /// Registers a native frame around exactly one native child.
    ///
    /// **The rule, per axis** (rulings FR-A, FR-B, FR-L, FR-M), from 71 arms of
    /// two committed SwiftUI probes — `docs/probes/swiftui-frame-semantics.swift`
    /// and `docs/probes/swiftui-frame-negative-sizes.swift`, whose arm names the
    /// comments below cite:
    ///
    /// ```
    /// lo = max(0, min)   hi = max(0, max)      // DECLARED bounds only (H2, H4)
    ///
    /// childProposal = fixed ?? clamp(parentProposal ?? ideal,
    ///                                min == nil ? -inf : lo, hi)
    ///                 — nil when the proposal and the ideal are both nil
    ///
    /// response      = fixed ?? clamp(base, lo, hi)
    ///   base = parentProposal          a maximum, a concrete proposal, and a
    ///                                  DECLARED minimum (D control, D1, D2,
    ///                                  D13, C5, H11, H13)
    ///        = max(parentProposal, child)
    ///                                  a maximum, a concrete proposal, NO
    ///                                  minimum (D4, D5, D10, H2, H7, H8, H15,
    ///                                  H16)
    ///        = ideal                   no proposal on this axis (C1, C3, C4)
    ///        = the child's answer      otherwise (C control, D6-D9, D14, D15)
    /// ```
    ///
    /// So a frame with a maximum is **greedy**: it takes the space it is
    /// offered, clamped, rather than reporting what its child asked for. A
    /// minimum on its own is not greedy. A child bigger than the frame keeps its
    /// own size and overflows (A5, B9); a fixed frame never shrinks, because
    /// there is no shrinking in SwiftUI. Chained frames: the outer size wins and
    /// the inner keeps its own (E1, E2).
    ///
    /// **At an INFINITE proposal a frame with a maximum answers `inf`** (probe
    /// `D12`; ruling CN-F, which reverses `FR-B`'s old divergence of answering
    /// the child). A stack's flexibility probe asks every child at main ∞, so
    /// answering the child would report a greedy frame over a fixed child as
    /// rigid (`swiftui-stack-algorithms.swift` G4r, G4f). Built-in placement
    /// never proposes ∞ at a finite root; a caller that places such a frame at
    /// ∞ traps at checkpoint 3, where SwiftUI crashes in its own placement.
    ///
    /// Placement puts the child at `alignment` inside the bounds the frame was
    /// given — not inside its own measurement — defaulting to SwiftUI's centre.
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
    /// **The wrapper proposes a ratio-shaped size and answers its child's
    /// answer to it** (probes AR1–AR4, K4–K4j; ruling CN-G), placing the child
    /// at that answer. `.fit` inscribes the shape inside a two-axis proposal
    /// (`width / ratio <= height` takes the width), `.fill` circumscribes it;
    /// one concrete axis derives the other; nil×nil proposes nil×nil. **∞ is a
    /// concrete axis, not nil** (K4d–K4h): ∞×∞ proposes ∞×∞ and 500×∞ proposes
    /// 500×281.25 at 16:9. A fixed child keeps its own size (AR1: 168×95 at
    /// 500×300); only a child that takes the offer takes the ratio's shape
    /// (AR3).
    ///
    /// **The ratio must be finite and non-zero** (ruling SA-J): SwiftUI answers
    /// nan for NaN and ±∞, and 0 answers 0×inf on a one-axis proposal (P8, P9).
    /// **A negative ratio is accepted**, as SwiftUI accepts it (P8, P8b; ruling
    /// SA-K item 2): −2 `.fit` at 100×80 proposes 100×−50, which a child that
    /// takes the offer answers.
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
    /// **A nil minimum is `ProposalSpacing.platformDefault`, 8** (probe SP1,
    /// SP6, K1; ruling CN-C). A spacer answers its minimum on an unspecified
    /// axis and `max(minimum, proposal)` on a concrete one, ∞ at ∞ (contract
    /// probe E; ruling CN-F) — **except on the cross axis of the linear stack
    /// that marks it, where it answers 0** (SPB1, SPB2, SPB5, SP13). A stack
    /// marks the spacers it reaches through `layoutPriority`, `padding`,
    /// `frame`, `fixedSize`, `aspectRatio` and both children of an overlay
    /// attachment, when the stack registers (`markSpacers`); an unmarked
    /// spacer, alone or in a `ZStack`, is flexible on both axes (SPB3, SPB4,
    /// K2a). A linear stack gives it no other special case: its priority is
    /// −∞ unless a `layoutPriority` node wraps it (ruling CN-C), so it is
    /// served after every other child and takes what they leave (SP8, SP9,
    /// SP10, X6).
    ///
    /// **A given minimum must be finite** (ruling SA-J): SwiftUI answers −inf
    /// for NaN and ±inf for ±∞ (P5, P9). A negative minimum is accepted:
    /// `Spacer(minLength: −30)` between two 20s answers 10 (P5).
    public func newNativeSpacer(minLength: Double? = nil) -> LayoutNodeID {
        if let minLength {
            precondition(minLength.isFinite, "spacer minLength must be finite (SA-J), got \(minLength)")
        }
        let id = appendNode(style: .default, children: [])
        nativeNodes[id.index] = .spacer(minLength: minLength ?? ProposalSpacing.platformDefault)
        return id
    }

    /// Registers a native linear stack.
    ///
    /// A linear stack uses the supplied alignment only on its cross axis:
    /// horizontal stacks read its vertical component and vertical stacks read
    /// its horizontal component. The default is SwiftUI's centred stack
    /// alignment.
    ///
    /// **`spacing`** (ruling CN-H): a number is used verbatim for every gap,
    /// beside a spacer included (probe S control, SP4). **`nil` is SwiftUI's
    /// platform default**, decided per adjacent pair: 0 when the earlier
    /// child's trailing edge or the later child's leading edge is a
    /// zero-spacing edge (`zeroSpacingEdges`: a spacer's, seen through its
    /// wrappers and containers; SP2, SP3, K3a–K3q, V1–V8), else
    /// `ProposalSpacing.platformDefault` (S). The default stays 0 for kernel
    /// callers; `HStack`/`VStack` pass nil unless given a spacing.
    ///
    /// **A given spacing must be finite** (ruling SA-J): SwiftUI answers nan
    /// and ±inf (P1, P9). **Negative spacing is accepted, unclamped**: `{20;
    /// 20}` at −10 answers 30, and at −100 answers −60, as SwiftUI does (P1).
    ///
    /// **Marks its spacers** with `axis` (ruling CN-C; `markSpacers`), so each
    /// answers 0 on this stack's cross axis.
    public func newNativeLinearStack(children: [LayoutNodeID], axis: ProposalStackAxis,
                                     spacing: Double? = 0,
                                     alignment: ProposalAlignment = .center) -> LayoutNodeID {
        for child in children { _ = nativeNode(child) }
        if let spacing {
            precondition(spacing.isFinite, "linear stack spacing must be finite (SA-J), got \(spacing)")
        }
        let id = appendNode(style: .default, children: children)
        for child in children { markSpacers(child, axis: axis) }
        nativeNodes[id.index] = .linearStack(axis: axis, spacing: spacing,
                                             alignment: alignment)
        return id
    }

    /// Registers a proposal-layout scrolling viewport around one native child.
    ///
    /// The content receives an unspecified proposal along the scrolling axis,
    /// while the viewport adopts a concrete parent proposal when one exists —
    /// ∞ included, so it answers ∞ at ∞ (probe SC1; ruling CN-F).
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
        spacerAxes.removeAll(keepingCapacity: true)
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
            // CN-C: 0 on the cross axis of the stack that marked it.
            let mark = spacerAxes[id.index]
            result = LayoutMeasurement(size: SizeD(
                width: mark == .vertical ? 0 : spacerLength(for: proposal.width, minimum: minLength),
                height: mark == .horizontal ? 0 : spacerLength(for: proposal.height, minimum: minLength)
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
            // CN-G: the child's answer to the ratio-shaped proposal.
            result = measureNative(children(id)[0],
                                   proposal: aspectRatioProposal(proposal, ratio: ratio,
                                                                 contentMode: contentMode),
                                   run: run)
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
            result = LayoutMeasurement(size: solveLinearStack(id, axis: axis, spacing: spacing,
                                                              proposal: proposal, run: run).size)
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
            let childProposal = aspectRatioProposal(proposal, ratio: ratio, contentMode: contentMode)
            let measurement = measureNative(child, proposal: childProposal, run: run)
            placeNative(child,
                        in: LayoutRect(x: bounds.x, y: bounds.y,
                                       width: measurement.size.width, height: measurement.size.height),
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
            // CN-E: at a nil cross proposal the stack reports its first-pass
            // answers (measurement) but places after re-running the
            // distribution at its own measured cross size (probe Q1, X10,
            // X11, G17, G21).
            var solveProposal = proposal
            switch axis {
            case .horizontal where proposal.height == nil:
                solveProposal = ProposedSize(width: proposal.width,
                                             height: measureNative(id, proposal: proposal, run: run).size.height)
            case .vertical where proposal.width == nil:
                solveProposal = ProposedSize(width: measureNative(id, proposal: proposal, run: run).size.width,
                                             height: proposal.height)
            default:
                break
            }
            let solution = solveLinearStack(id, axis: axis, spacing: spacing, proposal: solveProposal, run: run)
            let gaps = stackGaps(id, axis: axis, spacing: spacing)
            var cursor = axis == .horizontal ? bounds.x : bounds.y
            for (index, child) in children(id).enumerated() {
                let answer = solution.answers[index].size
                let childBounds: LayoutRect
                switch axis {
                case .horizontal:
                    childBounds = LayoutRect(x: cursor,
                                             y: bounds.y + (bounds.height - answer.height) * alignment.verticalFactor,
                                             width: answer.width, height: answer.height)
                    cursor += answer.width + (index < gaps.count ? gaps[index] : 0)
                case .vertical:
                    childBounds = LayoutRect(x: bounds.x + (bounds.width - answer.width) * alignment.horizontalFactor,
                                             y: cursor,
                                             width: answer.width, height: answer.height)
                    cursor += answer.height + (index < gaps.count ? gaps[index] : 0)
                }
                placeNative(child, in: childBounds, proposal: solution.proposals[index], run: run)
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

    /// One viewport axis: the proposal when there is one — ∞ included (probe
    /// SC1 at ∞×∞; ruling CN-F) — else the content's answer.
    private func resolvedViewportDimension(_ proposal: Double?, content: Double) -> Double {
        guard let proposal else { return content }
        return proposal
    }

    /// Marks every spacer `id` reaches with `axis` (ruling CN-C), called by
    /// `newNativeLinearStack` for each child at registration. The walk goes
    /// through `layoutPriority`, `padding`, `frame`, `fixedSize`,
    /// `aspectRatio` (K2b, K2g/K2i, K2d, SP19, SP20) and BOTH children of an
    /// overlay attachment (X8's primary, K2e's overlay content), and stops at
    /// anything else: a `ZStack` (`overlay`, K2a), a nested linear stack
    /// (SP18b, whose own marks stand), a scroll viewport, a custom layout or a
    /// leaf. A spacer keeps the first mark it gets, which is its nearest
    /// stack's: an inner stack registers before the stack that contains it.
    private func markSpacers(_ id: LayoutNodeID, axis: ProposalStackAxis) {
        switch nativeNode(id) {
        case .spacer:
            if spacerAxes[id.index] == nil { spacerAxes[id.index] = axis }
        case .layoutPriority, .padding, .frame, .fixedSize, .aspectRatio, .overlayAttachment:
            for child in children(id) { markSpacers(child, axis: axis) }
        case .leaf, .overlay, .linearStack, .scrollViewport, .custom:
            return
        }
    }

    /// The gap after each of a linear stack's children but the last (ruling
    /// CN-H): `spacing` for every pair when one is given; otherwise, per pair,
    /// 0 when the earlier child's trailing edge or the later child's leading
    /// edge is a zero-spacing edge, else `ProposalSpacing.platformDefault`.
    private func stackGaps(_ id: LayoutNodeID, axis: ProposalStackAxis, spacing: Double?) -> [Double] {
        let nodes = children(id)
        guard nodes.count > 1 else { return [] }
        if let spacing { return Array(repeating: spacing, count: nodes.count - 1) }
        let edges = nodes.map { zeroSpacingEdges($0, axis: axis) }
        return (1..<nodes.count).map { index in
            edges[index - 1].trailing || edges[index].leading ? 0 : ProposalSpacing.platformDefault
        }
    }

    /// Which of `id`'s edges along `axis` take no default spacing (ruling
    /// CN-H as amended; probe K3 and V groups, every figure at nil×nil between
    /// two 20pt views):
    ///
    /// - a spacer: both, when the stack that marked it (`spacerAxes`, CN-C) is
    ///   along `axis` or no stack marked it (SP2, SP3, K3g, V3); neither when
    ///   a stack across `axis` did (K3h, V1d, V1h, V3h, V7h);
    /// - `layoutPriority`, `frame`, `fixedSize`, `aspectRatio`: the child's
    ///   (K3d, K3b, K3e, K3f, K3q);
    /// - an overlay attachment: its PRIMARY's (K3c); a spacer on the content
    ///   side is not seen (K3i);
    /// - `padding`: the child's, on an edge whose inset is exactly 0 (K3a,
    ///   K3o's cross-axis inset, K3q); a non-zero inset gives that edge the
    ///   default again (K3m, K3n, K3p, V6);
    /// - a linear stack along `axis`: its first child's leading edge and its
    ///   last child's trailing edge, whatever its own spacing (V1, V1b, V1c,
    ///   V1e, V1i, V1k);
    /// - a linear stack across `axis`, or a custom layout: an edge is zero if
    ///   it is zero on ANY child (V3b, V3e, V3f, V7, V7b, V7d, V7f, V7i);
    /// - a `ZStack` (`overlay`): an edge is zero only if it is zero on EVERY
    ///   child (K3g, K3l, V7g, V7j, V7k; K3j, K3k with a leaf child);
    /// - any of those three with no children: both (V1f, V1g, V3d, V4, V4b);
    /// - a leaf or a scroll viewport: neither (V8, whatever its content).
    ///
    /// Leading/trailing are left/right for a horizontal stack and top/bottom
    /// for a vertical one; no layout direction is read (divergence 25).
    private func zeroSpacingEdges(_ id: LayoutNodeID,
                                  axis: ProposalStackAxis) -> (leading: Bool, trailing: Bool) {
        switch nativeNode(id) {
        case .spacer:
            let zero = spacerAxes[id.index].map { $0 == axis } ?? true
            return (zero, zero)
        case .layoutPriority, .frame, .fixedSize, .aspectRatio, .overlayAttachment:
            return zeroSpacingEdges(children(id)[0], axis: axis)
        case .padding(let insets):
            let child = zeroSpacingEdges(children(id)[0], axis: axis)
            let (leading, trailing) = axis == .horizontal ? (insets.left, insets.right)
                                                          : (insets.top, insets.bottom)
            return (child.leading && leading == 0, child.trailing && trailing == 0)
        case .linearStack(let stackAxis, _, _) where stackAxis == axis:
            let nodes = children(id)
            guard let first = nodes.first, let last = nodes.last else { return (true, true) }
            return (zeroSpacingEdges(first, axis: axis).leading, zeroSpacingEdges(last, axis: axis).trailing)
        case .linearStack, .custom:
            let nodes = children(id)
            guard !nodes.isEmpty else { return (true, true) }
            let edges = nodes.map { zeroSpacingEdges($0, axis: axis) }
            return (edges.contains(where: \.leading), edges.contains(where: \.trailing))
        case .overlay:
            let edges = children(id).map { zeroSpacingEdges($0, axis: axis) }
            return (edges.allSatisfy(\.leading), edges.allSatisfy(\.trailing))
        case .leaf, .scrollViewport:
            return (false, false)
        }
    }

    /// Whether `id` is a spacer, directly or under any depth of `layoutPriority`
    /// nodes: the public proxies' `isSpacer`. **No built-in reads it** since
    /// ruling CN-B: a spacer takes surplus through its −∞ priority
    /// (`nativeLayoutPriority`), like any other child.
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

    /// A spacer's answer on one axis: its minimum at nil, else
    /// `max(minimum, proposal)` — ∞ at ∞, as SwiftUI's spacer answers
    /// (contract probe E; ruling CN-F, which drops the old `isFinite` gate).
    private func spacerLength(for proposal: Double?, minimum: Double) -> Double {
        guard let proposal else { return minimum }
        return Swift.max(minimum, proposal)
    }

    /// One linear stack's children's proposals and answers, and the size it
    /// answers, at `proposal` (ruling CN-B). The one function both
    /// `measureNative` and `placeNative` call, so what a stack reports and
    /// where it places cannot disagree at one proposal.
    ///
    /// - **Nil or infinite main proposal:** every child is offered that value
    ///   with the stack's cross proposal, and nothing is distributed (G7, G8).
    /// - **Finite main proposal:** the spacing comes off first (G12). Children
    ///   are grouped by `nativeLayoutPriority`, highest group first. A group is
    ///   offered what remains minus the minimum — the main-axis answer at main
    ///   0 — of every lower-priority child (G2, G14, X5). Inside a group,
    ///   children are served least flexible first, flexibility being the
    ///   answer at main ∞ minus the answer at main 0, ties in declaration order
    ///   (G1, G1r, X1, X3, X4); each is offered `max(0, remaining / children
    ///   left in the group)` (G13), and what remains shrinks by what it
    ///   ANSWERED.
    /// - **The answer** is the sum of the children's main answers plus the
    ///   spacing — overflow and shrink-wrap included (G9, G10, G13, X13) — and
    ///   the largest of their cross answers at those proposals (Q3).
    ///
    /// **Eager probing, a kernel choice** (CN-B): SwiftUI evaluates flexibility
    /// lazily; this probes every member of a group of two or more at main ∞
    /// and main 0, a group of one not at all, and a lower-priority child at
    /// main 0 only. Under the purity assumption (SA-H) the allocations equal
    /// SwiftUI's; the extra measurements are counted by
    /// `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork`.
    private func solveLinearStack(_ id: LayoutNodeID, axis: ProposalStackAxis, spacing: Double?,
                                  proposal: ProposedSize,
                                  run: NativeLayoutRun) -> (answers: [LayoutMeasurement],
                                                            proposals: [ProposedSize], size: SizeD) {
        let nodes = children(id)
        let cross = axis == .horizontal ? proposal.height : proposal.width
        let main = axis == .horizontal ? proposal.width : proposal.height
        func offer(_ length: Double?) -> ProposedSize {
            axis == .horizontal ? ProposedSize(width: length, height: cross)
                                : ProposedSize(width: cross, height: length)
        }
        func mainLength(_ measurement: LayoutMeasurement) -> Double {
            axis == .horizontal ? measurement.size.width : measurement.size.height
        }
        let gaps = stackGaps(id, axis: axis, spacing: spacing).reduce(0, +)
        var proposals = Array(repeating: offer(main), count: nodes.count)
        var answers: [LayoutMeasurement]

        if let main, main.isFinite, !nodes.isEmpty {
            answers = Array(repeating: LayoutMeasurement(size: .zero), count: nodes.count)
            let priorities = nodes.map(nativeLayoutPriority)
            var remaining = main - gaps
            for priority in Set(priorities).sorted(by: >) {
                let members = nodes.indices.filter { priorities[$0] == priority }
                let reserved = nodes.indices.filter { priorities[$0] < priority }.reduce(0.0) { total, index in
                    total + mainLength(measureNative(nodes[index], proposal: offer(0), run: run))
                }
                var order = members
                if members.count > 1 {
                    let flexibility = Dictionary(uniqueKeysWithValues: members.map { index in
                        (index, mainLength(measureNative(nodes[index], proposal: offer(.infinity), run: run))
                            - mainLength(measureNative(nodes[index], proposal: offer(0), run: run)))
                    })
                    order.sort { lhs, rhs in
                        let (l, r) = (flexibility[lhs]!, flexibility[rhs]!)
                        return l != r ? l < r : lhs < rhs
                    }
                }
                var groupRemaining = remaining - reserved
                for (served, index) in order.enumerated() {
                    proposals[index] = offer(Swift.max(0, groupRemaining / Double(order.count - served)))
                    answers[index] = measureNative(nodes[index], proposal: proposals[index], run: run)
                    groupRemaining -= mainLength(answers[index])
                    remaining -= mainLength(answers[index])
                }
            }
        } else {
            answers = nodes.indices.map { measureNative(nodes[$0], proposal: proposals[$0], run: run) }
        }

        let mainTotal = answers.reduce(gaps) { $0 + mainLength($1) }
        let crossMax = answers.map { axis == .horizontal ? $0.size.height : $0.size.width }.max() ?? 0
        let size = axis == .horizontal ? SizeD(width: mainTotal, height: crossMax)
                                       : SizeD(width: crossMax, height: mainTotal)
        return (answers, proposals, size)
    }

    /// The priority a native stack (and a `ProposalLayout` subview proxy) reads
    /// for `id` (rulings SA-D, CN-C, CN-D):
    ///
    /// - a spacer: **−∞** (SP8, X5; contract probe E, E2);
    /// - a `layoutPriority` node: its value, whatever it wraps (X6);
    /// - an overlay attachment: its primary's, at any depth (probe L2, X8);
    /// - a linear stack or overlay (`ZStack`) with **exactly one** child: that
    ///   child's (G11, K2a, L3); with any other count, 0 (G11c, L3);
    /// - anything else, a custom layout included: 0 (L3). `frame`, `padding`,
    ///   `aspectRatio` and `fixedSize` hide a priority, as in SwiftUI (L2).
    ///
    /// MetalUI's paint-only proposal modifiers (`background`, `clip`, `border`,
    /// `opacity`, `allowsHitTesting`, `onTap`) register no node, so they need
    /// no case here. Pinned by `aLinearStackReadsPriorityThroughAnOverlayAttachment`,
    /// `aSingleChildStackPassesItsChildsPriorityThrough` and
    /// `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity`.
    func nativeLayoutPriority(_ id: LayoutNodeID) -> Double {
        switch nativeNode(id) {
        case .spacer:
            return -.infinity
        case .layoutPriority(let priority):
            return priority
        case .overlayAttachment:
            return nativeLayoutPriority(children(id)[0])
        case .linearStack, .overlay:
            let nodes = children(id)
            return nodes.count == 1 ? nativeLayoutPriority(nodes[0]) : 0
        default:
            return 0
        }
    }

    /// One axis of the proposal a frame hands its child (rulings FR-A, FR-L).
    ///
    /// A **declared** bound is floored at 0 before use; an **absent** minimum
    /// forwards a negative proposal unchanged. Probe `H4` (`minWidth: −50`)
    /// proposes 0.0 to its child where `H2` (no minimum, the same −30 proposal)
    /// proposes −30.0, so the floor is on the declared bound and nowhere else.
    private func framedProposal(_ parent: Double?, fixed: Double?, ideal: Double?, min: Double?, max: Double?) -> Double? {
        guard fixed == nil else { return fixed }
        guard let proposal = parent ?? ideal else { return nil }
        let lo = min.map { Swift.max(0, $0) } ?? -.infinity
        let hi = max.map { Swift.max(0, $0) } ?? .infinity
        return Swift.max(lo, Swift.min(proposal, hi))
    }

    /// One axis of a frame's own answer (rulings FR-A, FR-B, FR-L, FR-M).
    ///
    /// Five things here are deliberate and must not be "simplified":
    ///
    /// - **`max != nil` is the greedy gate, not `max == .infinity`.** SwiftUI's
    ///   flexible frame grows at ANY maximum: probe `D4` answers 80 under a
    ///   *finite* 80pt cap at a 100pt proposal. Making it unconditional instead
    ///   — greedy whenever the proposal is concrete — breaks a minimum on its
    ///   own, which answers the child (`D7`: 40 at a 100pt proposal).
    /// - **`min == nil ? max(proposal, child) : proposal` tests the minimum's
    ///   PRESENCE, never its value** (`FR-M`). Probe `H8` (`maxWidth: 80`,
    ///   proposal 10, child 20) answers 20; `H14` (`minWidth: 0` added, the
    ///   same numbers) answers 10. Writing `(min ?? 0) == 0` reads 20 for both
    ///   and is wrong.
    /// - **An infinite proposal is greedy too** (ruling CN-F, reversing
    ///   `FR-B`): SwiftUI answers `inf` (`D12`), and a stack's flexibility
    ///   probe at main ∞ needs that answer to serve a greedy frame after its
    ///   rigid siblings (G4r, G4f). There is deliberately no `isFinite` gate;
    ///   a caller that PLACES the answer at ∞ traps at checkpoint 3.
    /// - **The declared bounds are floored at 0** (`FR-L`): SwiftUI never
    ///   answers a negative size. `hi`'s floor is unreachable through
    ///   `newNativeFrame` today, which rejects a negative maximum at
    ///   registration (`SA-J`, `aNegativeFrameMaximumTraps`); it is kept as a
    ///   backstop for kernel callers, exactly as `validateFrameAxis`'s
    ///   fixed-plus-flexible check is, and ruling `FR-R` records that no test
    ///   can currently see it.
    /// - **The ideal branch stays second.** It is unreachable from the first —
    ///   the greedy branch requires a non-nil proposal — so the order is
    ///   documentation rather than logic, but swapping the two is one of test
    ///   1.4's mutations.
    private func framedSize(_ child: Double, proposal: Double?, fixed: Double?, ideal: Double?,
                            min: Double?, max: Double?) -> Double {
        if let fixed { return fixed }
        let lo = Swift.max(0, min ?? 0)
        let hi = max.map { Swift.max(0, $0) } ?? .infinity
        let base: Double
        if max != nil, let proposal {
            base = min == nil ? Swift.max(proposal, child) : proposal
        } else if proposal == nil, let ideal {
            base = ideal                         // probes C1, C3, C4
        } else {
            base = child                         // probes C control, D6-D9, D14, D15
        }
        return Swift.max(lo, Swift.min(base, hi))
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

    /// The proposal `aspectRatio` hands its child (ruling CN-G). ∞ is a
    /// concrete axis here, never filtered to nil (K4d–K4h).
    private func aspectRatioProposal(_ proposal: ProposedSize, ratio: Double,
                                     contentMode: AspectRatioContentMode) -> ProposedSize {
        switch (proposal.width, proposal.height) {
        case let (.some(width), .some(height)):
            // `width / ratio` is the height the width branch would give. `.fit`
            // takes that branch when it fits the proposed height, `.fill` when it
            // covers it. For a positive ratio and positive axes this is the old
            // `width / height <= ratio`; unlike it, it picks SwiftUI's branch for
            // a negative ratio and at zero or negative axes, 24 of 24 P8c arms
            // against 12 (ruling SA-K item 2), and with ∞ in it (K4d, K4e, K4h).
            let usesWidth: Bool
            switch contentMode {
            case .fit: usesWidth = width / ratio <= height
            case .fill: usesWidth = width / ratio >= height
            }
            return usesWidth
                ? ProposedSize(width: width, height: width / ratio)
                : ProposedSize(width: height * ratio, height: height)
        case let (.some(width), .none):
            return ProposedSize(width: width, height: width / ratio)      // K4, K4c
        case let (.none, .some(height)):
            return ProposedSize(width: height * ratio, height: height)    // K4b
        case (.none, .none):
            return proposal                                               // AR2
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
    /// `spacing` nil is the platform default, decided per pair (CN-H).
    case linearStack(axis: ProposalStackAxis, spacing: Double?, alignment: ProposalAlignment)
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
