// G33 (c), ruling II-A: one instance per distinct (parent, component) on the build path.
//
// `GlobalElementID.==` walks both chains unless they share an ancestor (`x === y` ends the walk). A frame mints every id afresh, so every
// lookup against an earlier frame's table (`StateTable`, the retained rows, the lazy units) used to walk the full depth. Interned ids make
// the same path in two frames the same object, so those lookups end at `l === r`. Interning is an optimisation only: `==` is unchanged,
// and an id made through the public `init` or `child(of:at:name:)` (never interned) still compares equal to its interned twin.

/// The process-wide table behind ``GlobalElementID/interned(component:parent:)``. Main actor only: every build site is, so no lock.
@MainActor
package final class IdentityInterner {
    package static let shared = IdentityInterner()

    package init() {}

    private struct Key: Hashable {
        /// A child holds its parent, so a parent's address cannot be reused while any child keyed on it is in the table.
        let parent: ObjectIdentifier?
        let component: PathComponent
        let hash: Int
        static func == (l: Key, r: Key) -> Bool { l.hash == r.hash && l.parent == r.parent && l.component == r.component }
        func hash(into hasher: inout Hasher) { hasher.combine(hash) }
    }
    private struct Slot {
        var id: GlobalElementID
        var lastUsed: UInt32
        /// Mint order: a child is always minted after its parent, so sweeping newest first lets a parent go in the same pass as its last child.
        let seq: Int
    }

    private var table: [Key: Slot] = [:]
    private var generation: UInt32 = 0
    private var nextSeq = 0
    private var sizeAtLastSweep = 0
    /// Slots untouched for more than this many builds, and referenced by nothing else, are dropped by a sweep.
    private let maxIdleGenerations: UInt32 = 2
    private let sweepEvery: UInt32 = 64
    private let minimumSweepSize = 1024

    /// How many ids the table holds.
    package var count: Int { table.count }

    /// The id for `component` under `parent`: the existing instance when the path was interned recently, else a new one.
    package func intern(component: PathComponent, parent: GlobalElementID?) -> GlobalElementID {
        let hash = GlobalElementID.pathHash(component: component, parent: parent)
        let key = Key(parent: parent.map(ObjectIdentifier.init), component: component, hash: hash)
        if let index = table.index(forKey: key) {
            table.values[index].lastUsed = generation
            return table.values[index].id
        }
        let id = GlobalElementID(component: component, parent: parent)
        table[key] = Slot(id: id, lastUsed: generation, seq: nextSeq)
        nextSeq &+= 1
        return id
    }

    /// Marks one frame build. Called by `Window` before each build.
    package func advance() {
        generation &+= 1
        if generation % sweepEvery == 0 || table.count > max(minimumSweepSize, 2 * sizeAtLastSweep) { sweep() }
    }

    /// Drops idle slots nothing else references. A referenced id stays (a `StateTable` key, a grafted row's id) so the dictionary key those
    /// hold and the instance handed out stay one object.
    package func sweep() {
        var stale: [(key: Key, seq: Int)] = []
        for (key, slot) in table where generation &- slot.lastUsed > maxIdleGenerations { stale.append((key, slot.seq)) }
        stale.sort { $0.seq > $1.seq }
        for (key, _) in stale {
            guard var slot = table.removeValue(forKey: key) else { continue }
            if !isKnownUniquelyReferenced(&slot.id) { table[key] = slot }
        }
        sizeAtLastSweep = table.count
    }
}

extension GlobalElementID {
    /// ``init(component:parent:)`` through the interner: the same path built twice yields one instance. For build-path sites on the main
    /// actor; the public initialiser stays non-interning (a separately built id is `==` but not `===`).
    @MainActor
    static func interned(component: PathComponent, parent: GlobalElementID?) -> GlobalElementID {
        IdentityInterner.shared.intern(component: component, parent: parent)
    }

    /// ``child(of:at:name:)`` through the interner.
    @MainActor
    static func internedChild(of parent: GlobalElementID?, at index: Int, name: ElementID?) -> GlobalElementID {
        interned(component: name.map(PathComponent.named) ?? .positional(index), parent: parent)
    }
}
