import MetalUICore
import MetalUILayout

// `OutlineGroup` in a lazy stack and its `OutlineIndex` (outline lane 3, rulings `OG-B`, `OG-D`, `OG-K`; extends lane
// 2's tree flattening, `LazyTree.swift`).
//
// Lane 2 reads a tree by evaluating the body of every element of every expanded folder each frame. An `OutlineGroup`
// reads its tree from DATA, so it can do better: the visible rows are flattened ONCE into an index (depth-first, one
// entry per row), and a frame only checks that the index still describes the data, in `O(expanded groups + window)`.
//
// **The index is rebuilt** when an expansion changed (`generation`: a row's toggle bumps it) or a validation failed;
// it is **validated** each frame by reading the root count, each expanded group's `children.count` (and its element's
// id), and each row of last frame's window (id, and whether it is still a group). A scroll frame therefore rebuilds
// nothing and reads the `children` key path `expanded groups + window` times. A change outside last frame's window
// that the checks cannot see is noticed when its row is realised (`stale`), one frame later.
//
// **Identity is the eager outline's** (`OutlineScopes` computes the ids `OutlineNode`'s structure gives, so the same
// tree moved between a `VStack` and a `LazyVStack`, or written as the recursive `DisclosureGroup` form, finds the
// same `@State`): per element a `ForEach` scope, a component level, an `if`/`else` branch, and for a group the
// disclosure's own component, its stack and its content slot. Expansion is each group's own `@State` slot
// (`DisclosureGroupBody.local`), read by `peek` without building the group.

/// The ids of an outline row's levels, the structure of `OutlineNode` (`Component`, `if`/`else`, `DisclosureGroup`).
/// Each function is one level of `OutlineGroupBody`/`OutlineNode`/`DisclosureGroupBody`; a test pins them against the
/// ids the eager outline mints.
enum OutlineScopes {
    /// The element's `ForEach` scope under the level (`FI-A`, `FI-B`): the level's one `ForEach` is its member 0.
    static func element<ID: Hashable>(in level: GlobalElementID, at index: Int, key: ID, needsKey: Bool) -> GlobalElementID {
        let slot = GlobalElementID(component: .positional(0), parent: level)
        return GlobalElementID.child(
            of: slot, at: index,
            name: ElementID(name: String(describing: key), key: needsKey ? IdentityKey(AnyHashable(key)) : nil))
    }

    /// The `OutlineNode` component's level.
    static func node(of element: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: element, at: 0, name: nil)
    }

    /// The `if` branch of a group, and the `else` branch of a leaf.
    static func groupBranch(of node: GlobalElementID) -> GlobalElementID { GlobalElementID(component: .positional(0), parent: node) }
    static func leafBranch(of node: GlobalElementID) -> GlobalElementID { GlobalElementID(component: .positional(1), parent: node) }

    /// The disclosure's component id (its `@State` slot hangs under it).
    static func group(of node: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: groupBranch(of: node), at: 0, name: nil)
    }

    /// The disclosure's own stack, whose member 0 is the label row.
    static func stack(of group: GlobalElementID) -> GlobalElementID { GlobalElementID.child(of: group, at: 0, name: nil) }

    /// The level the disclosure's content is realised under: the stack's `if` slot, member 1.
    static func children(of group: GlobalElementID) -> GlobalElementID {
        GlobalElementID(component: .positional(1), parent: stack(of: group))
    }
}

/// One level of `OutlineIndex.rebuild`'s walk: a level's collection, how far the walk is through it, and where it hangs.
struct OutlineCursor<Data: RandomAccessCollection> {
    var level: OutlineRoots<Data>
    var next = 0
    var parentSlot: Int
    var scope: GlobalElementID
    var depth: Int
}

/// One row of the flattened outline.
struct OutlineEntry<ID: Hashable> {
    let key: ID
    let indexInParent: Int
    /// The slot, in `OutlineIndex.groups`, of the expanded group this row is a child of; `-1` for a root.
    let parentSlot: Int
    let depth: Int
    let isGroup: Bool
    let isExpanded: Bool
}

/// An expanded group: its row, how many children it had, and the ids of its levels.
struct OutlineExpandedGroup {
    let entry: Int
    let childCount: Int
    /// The disclosure's component id; its expansion slot is `DisclosureSlot.slot(of:)`.
    let groupID: GlobalElementID
    /// Where its children's `ForEach` hangs.
    let childLevel: GlobalElementID
}

/// The flattened rows of an `OutlineGroup` in a lazy stack and everything a frame needs to keep them (`OG-K`). A class,
/// held in the outline's own `@State` slot: it is the group's per-frame cache, not state anything observes.
@MainActor
final class OutlineIndex<Data: RandomAccessCollection, ID: Hashable> {
    typealias Level = OutlineRoots<Data>

    private(set) var entries: [OutlineEntry<ID>] = []
    private(set) var groups: [OutlineExpandedGroup] = []
    /// The roots and each expanded group's children as the last validation or rebuild read them.
    private var liveRoots: Level?
    private var live: [Level] = []
    private var rootCount = 0
    private var built = false
    private var builtGeneration = 0
    /// Bumped by a row's toggle: the index no longer matches the expansions.
    var expansionGeneration = 0
    /// Set when realising a row found the data or its expansion differing from the index (`OG-K`): rebuilt next frame.
    var stale = false
    /// The rows realised since the last `prepare`, and the ones before that (validated on the next one).
    private var realisedLow = Int.max
    private var realisedHigh = -1
    private var lastWindow: Range<Int>?
    /// The rows this frame's checks or rebuild already read from the data, so realising them reads nothing more.
    private var fresh: Range<Int> = 0..<0
    /// Expanded groups below a collapsed or unvisited ancestor, kept alive each frame so their expansion survives
    /// the ancestor's collapse (`P-E5`) past the state table's bounded retention (`TB-AH`).
    private var hidden: Set<GlobalElementID> = []

    let needsKey = !(ID.self is DescriptionInjectiveID.Type)   // `FI-B`

    /// An empty index (nothing built yet); `nonisolated` so a `@State` initial value can make one.
    nonisolated init() {}

    var count: Int { entries.count }

    func collection(forParentSlot slot: Int) -> Level? { slot < 0 ? liveRoots : live[slot] }

    /// Whether row `unit` was checked against the data by this frame's `prepare` (a validation of the last window, or a
    /// rebuild of everything), so realising it need not read the data again.
    func isFresh(_ unit: Int) -> Bool { fresh.contains(unit) }

    func noteRealised(_ unit: Int) {
        realisedLow = Swift.min(realisedLow, unit)
        realisedHigh = Swift.max(realisedHigh, unit)
    }

    /// Validates the index against the data and rebuilds it when it no longer matches (`OG-K`), once per frame,
    /// before the rows are planned. Counts into `frame.lazyWork`.
    func prepare(roots: Level, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>,
                 scope: GlobalElementID, frame: Frame) {
        if realisedHigh >= realisedLow { lastWindow = realisedLow..<(realisedHigh + 1) }
        realisedLow = Int.max
        realisedHigh = -1
        var reads = 0
        var checks = 0
        if validate(roots: roots, id: id, children: children, reads: &reads, checks: &checks) {
            fresh = lastWindow ?? 0..<0
        } else {
            rebuild(roots: roots, id: id, children: children, scope: scope, frame: frame, reads: &reads)
            fresh = 0..<entries.count
        }
        frame.lazyWork.childrenReads += reads
        frame.lazyWork.indexValidations += checks
        // Every expanded group's expansion stays live, however far its row is from the window.
        for group in groups { frame.stateTable.mark(DisclosureSlot.slot(of: group.groupID)) }
        for group in hidden { frame.stateTable.mark(DisclosureSlot.slot(of: group)) }
    }

    /// The checks of one frame: the root count, each expanded group (its element's id and `children.count`) and each
    /// row of the last window (its id, and whether it is still a group).
    private func validate(roots: Level, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>,
                          reads: inout Int, checks: inout Int) -> Bool {
        guard built, builtGeneration == expansionGeneration, !stale else { return false }
        checks += 1
        guard roots.count == rootCount else { return false }
        var fresh: [Level] = []
        fresh.reserveCapacity(groups.count)
        for group in groups {
            checks += 1
            let entry = entries[group.entry]
            let parent = entry.parentSlot < 0 ? roots : fresh[entry.parentSlot]
            guard entry.indexInParent < parent.count else { return false }
            let element = parent[entry.indexInParent]
            guard element[keyPath: id] == entry.key else { return false }
            reads += 1
            guard let kids = element[keyPath: children], kids.count == group.childCount else { return false }
            fresh.append(Level(collection: kids))
        }
        if let window = lastWindow {
            for position in window where position < entries.count {
                checks += 1
                let entry = entries[position]
                let parent = entry.parentSlot < 0 ? roots : fresh[entry.parentSlot]
                guard entry.indexInParent < parent.count else { return false }
                let element = parent[entry.indexInParent]
                guard element[keyPath: id] == entry.key else { return false }
                reads += 1
                guard (element[keyPath: children] != nil) == entry.isGroup else { return false }
            }
        }
        liveRoots = roots
        live = fresh
        return true
    }

    /// One depth-first walk of the visible rows: every element of the roots and of each expanded group, a group's
    /// children only while its expansion slot says it is open. Iterative (a deep tree must not deepen the stack).
    private func rebuild(roots: Level, id idPath: KeyPath<Data.Element, ID>, children childrenPath: KeyPath<Data.Element, Data?>,
                         scope: GlobalElementID, frame: Frame, reads: inout Int) {
        frame.lazyWork.indexRebuilds += 1
        let needsKey = self.needsKey
        let table = frame.stateTable
        var entries: [OutlineEntry<ID>] = []
        entries.reserveCapacity(self.entries.count)
        var groups: [OutlineExpandedGroup] = []
        var live: [Level] = []
        var seen = Set<GlobalElementID>()       // every group's disclosure id this walk visited
        var open = Set<GlobalElementID>()       // those that were expanded
        var stack = [OutlineCursor<Data>(level: roots, parentSlot: -1, scope: scope, depth: 0)]
        while let top = stack.last {
            if top.next == top.level.count {
                stack.removeLast()
                continue
            }
            let position = top.next
            stack[stack.count - 1].next += 1
            let element = top.level[position]
            let key = element[keyPath: idPath]
            reads += 1
            guard let kids = element[keyPath: childrenPath] else {
                entries.append(OutlineEntry(key: key, indexInParent: position, parentSlot: top.parentSlot,
                                            depth: top.depth, isGroup: false, isExpanded: false))
                continue
            }
            let elementScope = OutlineScopes.element(in: top.scope, at: position, key: key, needsKey: needsKey)
            let groupID = OutlineScopes.group(of: OutlineScopes.node(of: elementScope))
            seen.insert(groupID)
            let expanded = table.peek(DisclosureSlot.slot(of: groupID), as: Bool.self) ?? false
            entries.append(OutlineEntry(key: key, indexInParent: position, parentSlot: top.parentSlot,
                                        depth: top.depth, isGroup: true, isExpanded: expanded))
            guard expanded else { continue }
            open.insert(groupID)
            let slot = groups.count
            let childLevel = OutlineScopes.children(of: groupID)
            groups.append(OutlineExpandedGroup(entry: entries.count - 1, childCount: kids.count, groupID: groupID,
                                               childLevel: childLevel))
            live.append(Level(collection: kids))
            stack.append(OutlineCursor<Data>(level: live[slot], parentSlot: slot, scope: childLevel, depth: top.depth + 1))
        }
        // `OG-D`: an element the data dropped loses its expansion; one under a collapsed ancestor keeps it.
        var removed: [GlobalElementID] = []
        for old in self.entries where old.isGroup {
            let level = old.parentSlot < 0 ? scope : self.groups[old.parentSlot].childLevel
            let elementScope = OutlineScopes.element(in: level, at: old.indexInParent, key: old.key, needsKey: needsKey)
            let groupID = OutlineScopes.group(of: OutlineScopes.node(of: elementScope))
            if seen.contains(groupID) { continue }
            if old.parentSlot >= 0, !open.contains(self.groups[old.parentSlot].groupID) { continue }
            table.noteRemovedSubtree(elementScope)
            removed.append(elementScope)
        }
        var candidates = hidden
        for group in self.groups { candidates.insert(group.groupID) }
        hidden = candidates.filter { candidate in
            !seen.contains(candidate) && !removed.contains { candidate.isOrDescends(from: $0) }
                && table.peek(DisclosureSlot.slot(of: candidate), as: Bool.self) == true
        }
        self.entries = entries
        self.groups = groups
        self.live = live
        liveRoots = roots
        rootCount = roots.count
        built = true
        builtGeneration = expansionGeneration
        stale = false
        lastWindow = nil
    }
}

// MARK: lazy flattening

extension OutlineGroup: LazyTreeType
    where Parent: ElementGroup, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    static var lazyTreeCapable: Bool { true }
}

extension OutlineGroup: LazyTreeFlattenable
    where Parent: ElementGroup, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    /// The group as one source of rows: its own component level is entered as the eager path enters it, the index
    /// validated or rebuilt, and the rows realised from the index by `OutlineGroupSource` (`OG-K`).
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        var cursor = sources.count
        let body = makeBody()
        let id = body.enterComponent(under: parent, at: &cursor, pass: &pass)
        let index = body.index
        index.prepare(roots: roots, id: spec.id, children: spec.children, scope: id, frame: pass.frame)
        sources.append(OutlineGroupSource(index: index, scope: id, spec: spec))
        return true
    }
}

/// An outline's rows, one unit each, realised from the index under the identity the eager outline gives them.
@MainActor
struct OutlineGroupSource<Data: RandomAccessCollection, ID: Hashable, Leaf: ElementGroup>: LazyUnitSource {
    let index: OutlineIndex<Data, ID>
    let scope: GlobalElementID
    let spec: OutlineSpec<Data, ID, Leaf>

    var lazyUnitCount: Int { index.count }
    func lazyUnitID(_ unit: Int) -> AnyHashable { AnyHashable(index.entries[unit].key) }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {}

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let entry = index.entries[unit]
        index.noteRealised(unit)
        let empty = LazyUnitBox(unit: globalIndex, key: AnyHashable(LazyUnitKey(segment: segment, id: AnyHashable(entry.key))),
                                nodes: [], prepaint: { _ in }, paint: { _ in })
        guard let level = index.collection(forParentSlot: entry.parentSlot), entry.indexInParent < level.count else {
            index.stale = true
            pass.frame.requestAnotherFrame()
            return empty
        }
        let element = level[entry.indexInParent]
        if !index.isFresh(unit) {
            // `OG-K`: a row entering the window was not checked: if the data changed there, rows keep the old
            // identity this frame and the next one rebuilds.
            pass.frame.lazyWork.childrenReads += 1
            if element[keyPath: spec.id] != entry.key || (element[keyPath: spec.children] != nil) != entry.isGroup {
                index.stale = true
                pass.frame.requestAnotherFrame()
            }
        }
        let parentLevel = entry.parentSlot < 0 ? scope : index.groups[entry.parentSlot].childLevel
        let elementScope = OutlineScopes.element(in: parentLevel, at: entry.indexInParent, key: entry.key,
                                                 needsKey: index.needsKey)
        if pass.frame.notesScrollKeys { pass.frame.noteScrollKey(elementScope, AnyHashable(entry.key)) }   // `DD-K`
        pass.frame.forEachIdentityWork.elements += 1   // `FI-B`, per realised row
        if index.needsKey { pass.frame.forEachIdentityWork.keyed += 1 }
        let node = OutlineScopes.node(of: elementScope)
        let groupBranch = OutlineScopes.groupBranch(of: node), leafBranch = OutlineScopes.leafBranch(of: node)
        if entry.isGroup {
            pass.frame.stateTable.noteProduced(groupBranch)
            pass.frame.stateTable.noteAbsent(leafBranch)
            let index = self.index
            var body = DisclosureGroupBody<Leaf, OutlineSubgroupChildren>(
                expansion: nil, label: spec.content(element), makeContent: { OutlineSubgroupChildren() })
            body.keepsHiddenState = true
            body.onToggle = { index.expansionGeneration &+= 1 }
            var cursor = 0
            let group = body.enterComponent(under: groupBranch, at: &cursor, pass: &pass)
            if body.isExpanded != entry.isExpanded {
                index.stale = true
                pass.frame.requestAnotherFrame()
            }
            let source: any LazyUnitSource = ListRowChrome.isActive
                ? LazyLegacyStaticSource(group: body.listHeader, marksHeader: true) : LazyLegacyStaticSource(group: body.header)
            let box = source.realizeLazyUnit(0, globalIndex: globalIndex, segment: 0, parent: OutlineScopes.stack(of: group),
                                             cursorBase: 0, pass: &pass)
            box.depth += entry.depth
            return box
        }
        pass.frame.stateTable.noteProduced(leafBranch)
        pass.frame.stateTable.noteAbsent(groupBranch)
        let box = outlineRowSource(spec.content(element))
            .realizeLazyUnit(0, globalIndex: globalIndex, segment: 0, parent: leafBranch, cursorBase: 0, pass: &pass)
        box.depth += entry.depth
        return box
    }
}

/// A leaf's content as one static unit: the typed entry for an element or a proposal component, the untyped one
/// otherwise (`lazyFlattenPlain`'s choice, but one unit however many members the content has).
@MainActor
private func outlineRowSource<G: ElementGroup>(_ group: G) -> any LazyUnitSource {
    if group is any ProposalElement || group is any Component, let proposal = group as? any ProposalElementGroup {
        return typedRowSource(proposal)
    }
    return LazyLegacyStaticSource(group: group)
}

@MainActor
private func typedRowSource<P: ProposalElementGroup>(_ group: P) -> any LazyUnitSource { LazyStaticSource(group: group) }
