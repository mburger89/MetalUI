import MetalUICore
import MetalUILayout
import Observation

// The content form's flatten cache (outline lane 8, ruling `OG-O`; Alloy's binding requirement, design section 9a item 1).
//
// A content `List`'s tree (`List { ForEach(roots) { NodeRow } }`, lane 2's flatten) evaluates every row body of every
// expanded folder, every frame. Lane 8 keeps what that walk produced (the units' sources and the calls it made on the
// state table) and reuses it while nothing it depends on has changed:
//
//  - **observed reads**: the walk runs inside an observation session of its own (the one a retained subtree's build
//    uses, `RetainedSession`), so an `@Observable` property it read - a node's name, its children, its `isExpanded` -
//    that changes marks the cache stale, and the window is dirtied;
//  - **bound state**: the `@State` entries the walk read are journalled with their versions (`RW-D`) and checked;
//  - **the list's own content value**: the top level of the content (the `ForEach` data's ids and what its closure makes of
//    each element, a component's own fields) is compared by value on every frame - `O(top-level elements)`, closures
//    called but no body run - so a value captured by the closure, or a changed data array, is never missed;
//  - **the ambient** (`BuildKey`: environment, scale, size, accessibility flags): equal, as a graft's is.
//
// A hit reapplies the journal (the same funnel a graft replays, `RK-F`: marks, produced and absent slots, names, windowed
// parents) and hands back the cached sources: no row body, no `ForEach` closure below the top level, no flatten. Only the
// window is then realised. A miss walks as before and records.
//
// **What the cache refuses** (the walk runs every frame, as in lane 2): a walk that read what observation cannot see -
// a component holding a class instance that is not `Observable`, an `@Environment` field, a `ForEach` over such
// instances - a top level that cannot be compared (a closure field, a `DisclosureGroup` written directly in the list), a
// walk that wrote state, made layout nodes or records, a pending ⌥ cascade. Correctness first: such a list is exactly
// as slow, and as right, as it was.

/// What one walk found out about itself, read by the code that records it.
@MainActor
final class OutlineWalk {
    /// The walk in progress, `nil` outside a cached flatten.
    private(set) static var current: OutlineWalk?
    /// The walk read something observation cannot see (`OG-O`).
    var unobserved: String?

    static func run<R>(_ body: () -> R) -> (R, OutlineWalk) {
        let walk = OutlineWalk()
        let outer = current
        current = walk
        defer { current = outer }
        return (body(), walk)
    }

    /// Notes that the walk met a component, so its fields can be checked.
    static func note<C>(component: C, bindsEnvironment: Bool) {
        guard let walk = current, walk.unobserved == nil else { return }
        if bindsEnvironment { walk.unobserved = "environment"; return }
        if !outlineFieldsAreObserved(component) { walk.unobserved = "unobservedClass" }
    }

    /// Notes that the walk iterates a `ForEach` over `element`s.
    static func note(elementType: Any.Type) {
        guard let walk = current, walk.unobserved == nil else { return }
        if elementType is AnyObject.Type, !(elementType is any Observable.Type) { walk.unobserved = "unobservedClass" }
    }
}

@MainActor private var outlineFieldsSafe: [ObjectIdentifier: Bool] = [:]

/// Whether every class instance a component's stored fields reach is `Observable` (the first instance of a type speaks for
/// the type). State and environment wrappers are skipped: state is versioned, an environment field refuses on its own.
@MainActor
func outlineFieldsAreObserved<C>(_ component: C) -> Bool {
    let key = ObjectIdentifier(C.self)
    if let known = outlineFieldsSafe[key] { return known }
    let result = outlineValueIsObserved(component, depth: 0)
    outlineFieldsSafe[key] = result
    return result
}

@MainActor
private func outlineValueIsObserved(_ value: Any, depth: Int) -> Bool {
    guard depth < 6 else { return false }
    let mirror = Mirror(reflecting: value)
    var seen = 0
    for child in mirror.children {
        let field = child.value
        if field is any BindableState || field is any BindableEnvironment { continue }
        if type(of: field) is AnyObject.Type {
            if !(field is any Observable) { return false }
            continue
        }
        switch Mirror(reflecting: field).displayStyle {
        case .struct?, .tuple?, .optional?, .enum?, .collection?, .set?, .dictionary?:
            if !outlineValueIsObserved(field, depth: depth + 1) { return false }
        default: break
        }
        seen += 1
        if mirror.displayStyle == .collection, seen >= 8 { break }
    }
    return true
}

// MARK: the top level's value

/// What the top level of a list's content is made of, by value: the elements a `ForEach` produced (its closure called, no
/// body run), the components and static members. Comparing two stamps decides whether the list's own content is the one the
/// cache was made for.
struct LazyStamp {
    var values: [Any] = []
    /// `false` when a member cannot be compared (a `DisclosureGroup` written directly, whose content is a closure).
    var comparable = true
    /// `ForEach` elements the stamp called the closure for.
    var checks = 0
}

@MainActor
protocol LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp)
}

@MainActor
func lazyStampMember<G: ElementGroup>(_ group: G, into stamp: inout LazyStamp) {
    if let stampable = group as? any LazyStampable {
        stampable.lazyStamp(into: &stamp)
    } else if lazyTreeCapableType(G.self), !(group is any Component) {
        stamp.comparable = false
    } else {
        stamp.values.append(group)
    }
}

extension ForEach: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) {
        stamp.values.append(data.count)
        for element in data {
            stamp.values.append(AnyHashable(element[keyPath: idKeyPath]))
            lazyStampMember(content(element), into: &stamp)
            stamp.checks += 1
        }
    }
}

extension Pair: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) {
        lazyStampMember(first, into: &stamp)
        lazyStampMember(second, into: &stamp)
    }
}

extension TupleGroup: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) {
        for member in repeat each members { lazyStampMember(member, into: &stamp) }
    }
}

extension OptionalGroup: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) {
        stamp.values.append(wrapped != nil)
        if let wrapped { lazyStampMember(wrapped, into: &stamp) }
    }
}

extension EitherGroup: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) {
        switch self {
        case .first(let group): stamp.values.append(0); lazyStampMember(group, into: &stamp)
        case .second(let group): stamp.values.append(1); lazyStampMember(group, into: &stamp)
        }
    }
}

extension LegacyContent: LazyStampable {
    func lazyStamp(into stamp: inout LazyStamp) { lazyStampMember(content, into: &stamp) }
}

/// `==` of two existentials: opens `a`, then casts `b` to its type (a mismatch is unequal, never a trap).
private func outlineOpenedEqual(_ a: any Equatable, _ b: Any) -> Bool {
    func open<A: Equatable>(_ a: A) -> Bool {
        guard let b = b as? A else { return false }
        return a == b
    }
    return open(a)
}

/// Whether two values are the same as far as a cache can tell: `Equatable` by `==`, a class by identity, a struct, tuple,
/// optional or collection field by field (a `State` or `Environment` wrapper skipped, a closure unequal to everything).
@MainActor
func lazySameValue(_ a: Any, _ b: Any, depth: Int = 0) -> Bool {
    guard type(of: a) == type(of: b) else { return false }
    if let equatable = a as? any Equatable { return outlineOpenedEqual(equatable, b) }
    if type(of: a) is AnyObject.Type { return (a as AnyObject) === (b as AnyObject) }
    guard depth < 8 else { return false }
    let left = Mirror(reflecting: a), right = Mirror(reflecting: b)
    switch left.displayStyle {
    case .struct?, .tuple?, .optional?, .enum?, .collection?, .set?, .dictionary?: break
    default: return false   // a function, a metatype: unknown
    }
    let lhs = Array(left.children), rhs = Array(right.children)
    guard lhs.count == rhs.count else { return false }
    if lhs.isEmpty { return left.displayStyle != .enum }
    for (x, y) in zip(lhs, rhs) {
        if x.value is any BindableState || x.value is any BindableEnvironment { continue }
        if !lazySameValue(x.value, y.value, depth: depth + 1) { return false }
    }
    return true
}

// MARK: the cache

/// What a content list's last walk left for a later frame, one per list (on `ContentMemoStore.Entry.outlineCache`).
@MainActor
final class OutlineFlattenCache {
    let key: BuildKey
    let stamp: [Any]
    let sources: [any LazyUnitSource]
    /// The calls the walk made on the state table and the stores, in order (`RK-F`), replayed on a hit.
    let events: [BuildJournal.Event]
    let nestedKeys: [ContentMemoStore.Key]
    let liveStates: [GlobalElementID]
    let animationIDs: [GlobalElementID]
    let stateReads: [(GlobalElementID, UInt64)]

    init(key: BuildKey, stamp: [Any], sources: [any LazyUnitSource], events: [BuildJournal.Event]) {
        self.key = key
        self.stamp = stamp
        self.sources = sources
        self.events = events
        var nested: [ContentMemoStore.Key] = []
        var live: [GlobalElementID] = []
        var animation: [GlobalElementID] = []
        var reads: [(GlobalElementID, UInt64)] = []
        for event in events {
            switch event {
            case .memoTouch(let key): nested.append(key)
            case .liveState(let id): live.append(id)
            case .stateRead(let id, let version): reads.append((id, version))
            case .animationTouch(let id): animation.append(id)
            default: break
            }
        }
        nestedKeys = nested
        liveStates = live
        animationIDs = animation
        stateReads = reads
    }

    /// Whether `events` hold a call a cache must not replay: a lifecycle or presentation note, a window preference.
    static func replayable(_ events: ArraySlice<BuildJournal.Event>) -> Bool {
        for event in events {
            switch event {
            case .lifecycleNote, .presentationNote, .windowPreference: return false
            default: continue
            }
        }
        return true
    }
}

extension Frame {
    /// Whether the entries the cached walk depends on are all still there and unchanged (`RK-F`'s test, `RW-D`).
    func outlineDependenciesHold(_ cache: OutlineFlattenCache) -> Bool {
        let memos = stateTable.contentMemos
        for key in cache.nestedKeys {
            guard let entry = memos.entry(for: key), !entry.stale, !entry.observedChange else { return false }
        }
        for id in cache.liveStates where !stateTable.hasEntry(id) { return false }
        for id in cache.animationIDs where !animationStore.hasEntry(id) { return false }
        for (id, version) in cache.stateReads where stateTable.entryVersion(id) != version { return false }
        return true
    }
}

/// `lazyFlattenRoot` behind the content list's cache (`OG-O`). Counts what it did on the frame's `LazyWork`.
@MainActor
func lazyFlattenRootCached<G: ProposalElementGroup>(_ group: G, parent: GlobalElementID,
                                                    pass: inout LayoutPass) -> [any LazyUnitSource]? {
    guard lazyTreeCapableType(G.self) else { return lazyFlatten(group) }
    let frame = pass.frame
    let store = frame.stateTable.contentMemos
    guard store.cachesOutlineContent else {
        frame.lazyWork.contentRebuilds += 1
        return lazyFlattenRoot(group, parent: parent, pass: &pass)
    }
    let entry = store.flattenEntry(for: parent)
    // A pending ⌥ cascade builds the groups as expanded and queues their writes: never cached, and what follows is new.
    if let context = OutlineCascade.context, !context.pending.isEmpty {
        entry.outlineCache = nil
        frame.lazyWork.contentRebuilds += 1
        return lazyFlattenRoot(group, parent: parent, pass: &pass)
    }
    let key = frame.graftBuildKey()
    var stamp = LazyStamp()
    lazyStampMember(group, into: &stamp)
    frame.lazyWork.contentChecks += stamp.checks
    if let cache = entry.outlineCache, stamp.comparable, !entry.observedChange, cache.key == key,
       lazySameStamp(cache.stamp, stamp.values), frame.outlineDependenciesHold(cache) {
        frame.reapply(cache.events)
        frame.lazyWork.contentHits += 1
        return cache.sources
    }
    entry.outlineCache = nil
    frame.lazyWork.contentRebuilds += 1
    let journal = store.journal
    let recorder = frame.openGraftWindow()
    let changes = entry.flags.changes
    let (sources, walk) = OutlineWalk.run {
        entry.buildSession.run(entry: entry, store: store) { lazyFlattenRoot(group, parent: parent, pass: &pass) }
    }
    journal.open.removeAll { $0 === recorder }
    defer { journal.clearIfIdle() }
    guard let sources else { return nil }
    let slice = journal.events[recorder.start...]
    guard stamp.comparable, walk.unobserved == nil, recorder.taint == nil,
          recorder.audit.movedChannel(to: frame.buildAudit()) == nil,
          frame.tree.nodeCount == recorder.lower, frame.lowering.order.count == recorder.orderStart,
          frame.animationStore.lifecycle.nextRegistrationOrder == recorder.lifecycleBase,
          OutlineFlattenCache.replayable(slice) else {
        return sources
    }
    entry.flags.clearObservedChange(ifChangesEqual: changes)
    entry.outlineCache = OutlineFlattenCache(key: key, stamp: stamp.values, sources: sources, events: Array(slice))
    return sources
}

@MainActor
private func lazySameStamp(_ a: [Any], _ b: [Any]) -> Bool {
    guard a.count == b.count else { return false }
    for index in a.indices where !lazySameValue(a[index], b[index]) { return false }
    return true
}
