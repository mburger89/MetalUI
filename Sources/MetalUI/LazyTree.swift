import MetalUICore
import MetalUILayout

// Lazy flattening through a tree (outline lane 2, rulings `OG-B`, `OG-C`; extends `LZ-B`).
//
// A lazy stack's content normally reads as units whose count is known without evaluating anything: a
// `ForEach` element is one unit, a static member one, and an `if` makes the container eager (`LZ-B`). A
// hierarchical list needs more: a row is a `Component` whose body is `if folder { DisclosureGroup { rows } label: {…} }
// else { leaf }`, so a row is **one unit (a leaf), or a label unit followed by the units of the expanded content,
// recursively**. This file reads such content, and ONLY such content: `lazyTreeCapable(_:)` is decided from the
// content's TYPE (does it hold a `DisclosureGroup`, directly or through a `Component`, an `if`/`else`, a `ForEach`
// or a `Pair`?), so every container that holds no disclosure keeps `LZ-B`'s rules exactly (a plain `if` is still
// eager, a plain `Component` row is still one unit, an unbounded 100k list evaluates no more bodies than before).
//
// **Identity equals the eager `VStack`'s** (`OG-B`): the flattening walks the same ids the eager path numbers -
// a `Component` enters its own level with `enterComponent` (its `@State` is bound, its index consumed), an `if`
// reserves its one slot, an `if`/`else` both of its slots, a `ForEach` element hangs under its id-named scope - and
// each nested level realises its units under that level's id with its own cursor, so the same tree moved between a
// `VStack` and a `LazyVStack` finds the same `@State`. The flattening does the walk for EVERY element each frame
// (a body is evaluated per row of an expanded folder, never for the children of a collapsed one): light evaluation,
// no layout; only the window is realised.

// MARK: capability

/// A type that can hold a disclosure, so its lazy reading may yield other than exactly one unit.
@MainActor
protocol LazyTreeType {
    static var lazyTreeCapable: Bool { get }
}

@MainActor private var lazyTreeCapableCache: [ObjectIdentifier: Bool] = [:]

/// Whether `type` can contribute a tree to a lazy container (`OG-C`): a `DisclosureGroup`, or a `Component`,
/// `if`, `if`/`else`, `Pair`, `ForEach` or adopted legacy member holding one. Decided from the type alone.
@MainActor
func lazyTreeCapableType(_ type: Any.Type) -> Bool {
    let key = ObjectIdentifier(type)
    if let known = lazyTreeCapableCache[key] { return known }
    let result: Bool
    if let tree = type as? any LazyTreeType.Type {
        result = tree.lazyTreeCapable
    } else if let component = type as? any Component.Type {
        result = componentIsTreeCapable(component)
    } else {
        result = false
    }
    lazyTreeCapableCache[key] = result
    return result
}

@MainActor
private func componentIsTreeCapable<C: Component>(_ type: C.Type) -> Bool {
    // An `Animatable` component interpolates in its own entry (`VA-I`), which the flattening does not run.
    if C.self is any Animatable.Type { return false }
    return lazyTreeCapableType(C.Content.self)
}

extension DisclosureGroup: LazyTreeType {
    static var lazyTreeCapable: Bool { true }
}

extension Pair: LazyTreeType {
    static var lazyTreeCapable: Bool { lazyTreeCapableType(First.self) || lazyTreeCapableType(Second.self) }
}

extension OptionalGroup: LazyTreeType {
    static var lazyTreeCapable: Bool { lazyTreeCapableType(Wrapped.self) }
}

extension EitherGroup: LazyTreeType {
    static var lazyTreeCapable: Bool { lazyTreeCapableType(First.self) || lazyTreeCapableType(Second.self) }
}

extension LegacyContent: LazyTreeType {
    static var lazyTreeCapable: Bool { lazyTreeCapableType(Content.self) }
}

extension ForEach: LazyTreeType {
    static var lazyTreeCapable: Bool { lazyTreeCapableType(Content.self) }
}

// MARK: flattening

/// A tree-capable group that lists its own units under `parent`, with its index among the units of the level
/// being built (`sources.count`) as its cursor.
@MainActor
protocol LazyTreeFlattenable {
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool
}

/// The sources of a lazy container's content, `nil` when a member makes the container eager. A container whose
/// content cannot hold a disclosure reads exactly as before (`LZ-B`).
@MainActor
func lazyFlattenRoot<G: ProposalElementGroup>(_ group: G, parent: GlobalElementID,
                                              pass: inout LayoutPass) -> [any LazyUnitSource]? {
    guard lazyTreeCapableType(G.self) else { return lazyFlatten(group) }
    var sources: [any LazyUnitSource] = []
    return lazyFlattenTree(group, into: &sources, parent: parent, pass: &pass) ? sources : nil
}

/// Appends `group`'s sources at the level whose units are realised under `parent`. Every source consumes exactly
/// one cursor index of that level, so a source's cursor is its position in `sources`.
@MainActor
func lazyFlattenTree<G: ElementGroup>(_ group: G, into sources: inout [any LazyUnitSource],
                                      parent: GlobalElementID, pass: inout LayoutPass) -> Bool {
    guard lazyTreeCapableType(G.self) else { return lazyFlattenPlain(group, into: &sources) }
    if let tree = group as? any LazyTreeFlattenable {
        return tree.lazyTreeFlatten(into: &sources, parent: parent, pass: &pass)
    }
    if let component = group as? any Component {
        return lazyFlattenComponent(component, into: &sources, parent: parent, pass: &pass)
    }
    return lazyFlattenPlain(group, into: &sources)
}

/// A member with no tree in it: read exactly as a lazy container reads it today.
@MainActor
private func lazyFlattenPlain<G: ElementGroup>(_ group: G, into sources: inout [any LazyUnitSource]) -> Bool {
    if let proposal = group as? any ProposalElementGroup {
        return lazyFlattenMember(proposal, into: &sources)
    }
    return lazyFlattenMember(LegacyContent(group), into: &sources)
}

/// A `Component` holding a tree: its own level is entered as the eager path enters it (identity, `@State`, its one
/// index), `content` is materialised once, and the content's units are realised under the component's id.
@MainActor
private func lazyFlattenComponent<C: Component>(_ component: C, into sources: inout [any LazyUnitSource],
                                                parent: GlobalElementID, pass: inout LayoutPass) -> Bool {
    var cursor = sources.count
    let id = component.enterComponent(under: parent, at: &cursor, pass: &pass)
    guard let nested = lazyNested(component.content, scope: id, pass: &pass) else { return false }
    sources.append(nested)
    return true
}

/// `group`'s units as one level realised under `scope`, with each source's per-frame hook already called.
@MainActor
func lazyNestedTable<G: ElementGroup>(_ group: G, scope: GlobalElementID, pass: inout LayoutPass) -> LazyUnitTable? {
    var nested: [any LazyUnitSource] = []
    guard lazyFlattenTree(group, into: &nested, parent: scope, pass: &pass) else { return nil }
    let table = LazyUnitTable(nested)
    table.begin(parent: scope, pass: &pass)
    return table
}

@MainActor
private func lazyNested<G: ElementGroup>(_ group: G, scope: GlobalElementID, pass: inout LayoutPass) -> LazyNestedSource? {
    lazyNestedTable(group, scope: scope, pass: &pass).map { LazyNestedSource(scope: scope, table: $0) }
}

extension Pair: LazyTreeFlattenable {
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        lazyFlattenTree(first, into: &sources, parent: parent, pass: &pass)
            && lazyFlattenTree(second, into: &sources, parent: parent, pass: &pass)
    }
}

extension LegacyContent: LazyTreeFlattenable {
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        lazyFlattenTree(content, into: &sources, parent: parent, pass: &pass)
    }
}

extension OptionalGroup: LazyTreeFlattenable {
    /// One structural slot (`ID-B`): the content's units under it when present, nothing (the slot noted
    /// absent) when not. The insertion fade is the eager path's; a lazy list's own splice is lane 7's.
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        let slot = GlobalElementID(component: .positional(sources.count), parent: parent)
        guard let wrapped else {
            pass.frame.stateTable.noteAbsent(slot)
            sources.append(LazyEmptySource())
            return true
        }
        pass.frame.stateTable.noteProduced(slot)
        guard let nested = lazyNested(wrapped, scope: slot, pass: &pass) else { return false }
        sources.append(nested)
        return true
    }
}

extension EitherGroup: LazyTreeFlattenable {
    /// Both slots reserved (`ID-C`, `ID-D`): the taken branch's units under its slot, and the untaken
    /// branch's slot noted absent and held by an empty source, so every source keeps one cursor index.
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        let first = GlobalElementID(component: .positional(sources.count), parent: parent)
        let second = GlobalElementID(component: .positional(sources.count + 1), parent: parent)
        switch self {
        case .first(let group):
            pass.frame.stateTable.noteProduced(first)
            pass.frame.stateTable.noteAbsent(second)
            guard let nested = lazyNested(group, scope: first, pass: &pass) else { return false }
            sources.append(nested)
            sources.append(LazyEmptySource())
        case .second(let group):
            pass.frame.stateTable.noteProduced(second)
            pass.frame.stateTable.noteAbsent(first)
            guard let nested = lazyNested(group, scope: second, pass: &pass) else { return false }
            sources.append(LazyEmptySource())
            sources.append(nested)
        }
        return true
    }
}

extension ForEach: LazyTreeFlattenable {
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        guard let source = LazyTreeForEachSource(forEach: self, parent: parent, segment: sources.count,
                                                 pass: &pass) else { return false }
        sources.append(source)
        return true
    }
}

extension DisclosureGroup: LazyTreeFlattenable {
    func lazyTreeFlatten(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                         pass: inout LayoutPass) -> Bool {
        inner.lazyTreeFlattenBody(into: &sources, parent: parent, pass: &pass)
    }
}

extension DisclosureGroupBody {
    /// The group as units: its label row, then (while expanded) its content's units, realised under the ids the
    /// eager body gives them. The eager body is `VStack { header; if expanded { content } }` under the component's
    /// id, so the row is member 0 and the `if`'s slot member 1 of the stack's level; the stack itself is bypassed.
    func lazyTreeFlattenBody(into sources: inout [any LazyUnitSource], parent: GlobalElementID,
                             pass: inout LayoutPass) -> Bool {
        var cursor = sources.count
        let id = enterComponent(under: parent, at: &cursor, pass: &pass)
        let stack = GlobalElementID.child(of: id, at: 0, name: nil)   // the body's `VStack` (no name)
        // `OG-J`: inside a content `List` the label row is the list's (chevron cell in the lead slot, no standalone look).
        let body = self
        var disclosure: LazyDisclosure?
        if ListRowChrome.isActive {
            let request = OutlineCascade.context?.request
            disclosure = LazyDisclosure(
                isExpanded: { body.isExpanded },
                set: { want in if body.isExpanded != want { body.toggle() } },
                cascade: { want in
                    if let request { request(id, want) } else if body.isExpanded != want { body.toggle() }
                })
        }
        var level: [any LazyUnitSource] = [ListRowChrome.isActive
            ? LazyLegacyStaticSource(group: listHeader(cascade: disclosure?.cascade), marksHeader: true,
                                     disclosure: disclosure)
            : LazyLegacyStaticSource(group: header)]
        let slot = GlobalElementID(component: .positional(1), parent: stack)
        // A pending ⌥ cascade (`OutlineCascade`): an expand builds the group open and every group below it open, queueing
        // each write for after the build; a collapse queues the write of each expanded group.
        let cascade = OutlineCascade.direction(for: id)
        var open = isExpanded
        if let cascade, let context = OutlineCascade.context {
            if cascade != open {
                context.queue(id) { if body.isExpanded != cascade { body.toggle() } }
            }
            if cascade { open = true }
        }
        if open {
            pass.frame.stateTable.noteProduced(slot)
            guard var nested = OutlineCascade.forcing(cascade, { lazyNested(makeContent(), scope: slot, pass: &pass) })
            else { return false }
            nested.depthStep = 1
            level.append(nested)
        } else {
            pass.frame.stateTable.noteAbsent(slot)
            level.append(LazyEmptySource())
        }
        let table = LazyUnitTable(level)
        table.begin(parent: stack, pass: &pass)
        sources.append(LazyNestedSource(scope: stack, table: table))
        return true
    }
}

// MARK: sources

/// A unit's id inside a nested level: the element it belongs to and the unit's own recorded key at that level.
struct LazyTreeUnitID: Hashable {
    let element: AnyHashable
    let inner: AnyHashable
}

/// A slot that holds no units (an `if` that is false, the untaken branch of an `if`/`else`, a collapsed group's
/// content): it keeps its cursor index.
@MainActor
struct LazyEmptySource: LazyUnitSource {
    var lazyUnitCount: Int { 0 }
    func lazyUnitID(_ unit: Int) -> AnyHashable { AnyHashable(LazyStaticUnitID()) }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {}
    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        preconditionFailure("an empty source has no unit to realise")
    }
}

/// One level of units realised under its own scope (a component's id, a branch or `if` slot, a disclosure's stack).
@MainActor
struct LazyNestedSource: LazyUnitSource {
    let scope: GlobalElementID
    let table: LazyUnitTable
    /// The levels of disclosure this level adds to its units' `depth` (`OG-J`): 1 for a disclosure group's content, 0 for
    /// a component's, an `if`'s or a branch's.
    var depthStep = 0

    var lazyUnitCount: Int { table.count }
    func lazyUnitID(_ unit: Int) -> AnyHashable { table.key(unit) }
    func lazyScrollID(_ unit: Int) -> AnyHashable { table.rawID(unit) }
    func lazySelectionTag(_ unit: Int) -> AnyHashable? { table.selectionTag(unit) }
    func lazyDepth(_ unit: Int) -> Int { table.depth(unit) + depthStep }
    func lazyDisclosure(_ unit: Int) -> LazyDisclosure? { table.disclosure(unit) }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {}   // the level's hooks ran when it was built

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let box = table.realize(unit, globalIndex: globalIndex, parent: scope, pass: &pass)
        box.depth += depthStep
        return box
    }
}

/// A `ForEach` whose elements hold a tree: every element's content is flattened (under the element's id-named
/// scope, as `LazyForEachSource` scopes it) to count its units, with prefix sums over the elements; units are
/// realised only for the window, `O(log elements)` to find an element and `O(depth)` levels below it.
@MainActor
struct LazyTreeForEachSource<Data: RandomAccessCollection, ID: Hashable, Content: ElementGroup>: LazyUnitSource {
    struct Built {
        let key: ID
        let scope: GlobalElementID
        let table: LazyUnitTable
    }
    let forEach: ForEach<Data, ID, Content>
    let elements: [Built]
    /// Each element's first unit, ascending, with the total last.
    let prefix: [Int]
    let needsKey: Bool

    init?(forEach: ForEach<Data, ID, Content>, parent: GlobalElementID, segment: Int, pass: inout LayoutPass) {
        self.forEach = forEach
        let slot = GlobalElementID(component: .positional(segment), parent: parent)
        pass.frame.stateTable.noteWindowedParent(slot)   // `LZ-H`; never `noteLoop`
        let needsKey = !(ID.self is DescriptionInjectiveID.Type)   // `FI-B`
        self.needsKey = needsKey
        var built: [Built] = []
        built.reserveCapacity(forEach.data.count)
        var prefix: [Int] = []
        prefix.reserveCapacity(forEach.data.count + 1)
        var total = 0
        var index = 0
        for element in forEach.data {
            let key = element[keyPath: forEach.idKeyPath]
            let scope = GlobalElementID.child(
                of: slot, at: index,
                name: ElementID(name: String(describing: key), key: needsKey ? IdentityKey(AnyHashable(key)) : nil))
            pass.frame.stateTable.noteNamed(scope, at: index)   // a no-op under a windowed parent, `LZ-H`
            guard let table = lazyNestedTable(forEach.content(element), scope: scope, pass: &pass) else { return nil }
            prefix.append(total)
            total += table.count
            built.append(Built(key: key, scope: scope, table: table))
            index += 1
        }
        prefix.append(total)
        self.elements = built
        self.prefix = prefix
    }

    var lazyUnitCount: Int { prefix[prefix.count - 1] }

    /// The element holding `unit` and the unit's index inside it, `O(log elements)`.
    private func locate(_ unit: Int) -> (element: Int, local: Int) {
        var low = 0, high = elements.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if prefix[middle] <= unit { low = middle } else { high = middle - 1 }
        }
        var element = low
        while element + 1 < elements.count, prefix[element + 1] <= unit { element += 1 }   // skip empty elements
        return (element, unit - prefix[element])
    }

    func lazyUnitID(_ unit: Int) -> AnyHashable {
        let (element, local) = locate(unit)
        return AnyHashable(LazyTreeUnitID(element: AnyHashable(elements[element].key),
                                          inner: elements[element].table.key(local)))
    }

    /// The element's first unit is the element's scroll target (its id); a later unit is its own level's.
    func lazyScrollID(_ unit: Int) -> AnyHashable {
        let (element, local) = locate(unit)
        return local == 0 ? AnyHashable(elements[element].key) : elements[element].table.rawID(local)
    }

    func lazySelectionTag(_ unit: Int) -> AnyHashable? {
        let (element, local) = locate(unit)
        return elements[element].table.selectionTag(local)
    }

    func lazyDepth(_ unit: Int) -> Int {
        let (element, local) = locate(unit)
        return elements[element].table.depth(local)
    }

    func lazyDisclosure(_ unit: Int) -> LazyDisclosure? {
        let (element, local) = locate(unit)
        return elements[element].table.disclosure(local)
    }

    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {
        pass.frame.stateTable.noteWindowedParent(slot)   // `LZ-H`; never `noteLoop`
    }

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let (index, local) = locate(unit)
        let built = elements[index]
        if pass.frame.notesScrollKeys { pass.frame.noteScrollKey(built.scope, AnyHashable(built.key)) }   // `DD-K`
        pass.frame.forEachIdentityWork.elements += 1   // `FI-B`, per realised unit
        if needsKey { pass.frame.forEachIdentityWork.keyed += 1 }
        return built.table.realize(local, globalIndex: globalIndex, parent: built.scope, pass: &pass)
    }
}
