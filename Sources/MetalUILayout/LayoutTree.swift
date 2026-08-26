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

    /// The stamp carried by every id this tree issues. Changed only by
    /// `reset(generation:)`, which is what makes the ids from before a reset
    /// detectably stale.
    public private(set) var generation: UInt64

    public init(generation: UInt64) { self.generation = generation }

    public var nodeCount: Int { styles.count }

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
        return LayoutNodeID(generation: generation, index: styles.count - 1)
    }

    public func newLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        let id = newNode(style: style, children: [])
        measures[id.index] = measure
        return id
    }

    public func style(_ id: LayoutNodeID) -> Style { styles[slot(id)] }
    public func setStyle(_ id: LayoutNodeID, _ s: Style) { styles[slot(id)] = s }
    public func children(_ id: LayoutNodeID) -> [LayoutNodeID] { childLists[slot(id)] }
    public func measure(_ id: LayoutNodeID) -> MeasureFunction? { measures[slot(id)] }
    public func layout(_ id: LayoutNodeID) -> LayoutRect { layouts[slot(id)] }
    public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect) { layouts[slot(id)] = r }

    /// Drop every node but keep the allocated capacity, under a **new**
    /// generation.
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
}
