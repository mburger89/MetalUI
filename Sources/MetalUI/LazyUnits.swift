import MetalUICore
import MetalUILayout

// Lazy containers, units (item L1, rulings `LZ-B`, `LZ-H`; spec section 3.1).
//
// A lazy container's content is read as an ordered list of UNITS, each realised on demand:
// one per element of a `ForEach` over proposal content, one per static leaf (a `ProposalElement`
// or a proposal `Component`), none for an `EmptyGroup`, a `Pair` being its two halves in order.
// Anything else (`if`, `switch`, `for` members, `LegacyContent`, a `ForEach` of legacy rows) is
// not a unit source: the container turns EAGER and realises every member every frame as a
// `VStack` would (`LZ-B`, divergence 636).
//
// **Every member consumes exactly ONE cursor index** (a `ForEach` takes one structural slot, a
// leaf or a component one index through `enteringGroupMember`), so a segment's cursor base is its
// ordinal among the segments, and the identity a realised unit gets is what the same member would
// have in a `VStack`'s content: the stack's own id, positional at the segment ordinal, and for a
// `ForEach` element the id-named scope under that slot (`FI-A`, `FI-B`).
//
// **A lazy `ForEach` never calls `noteLoop`** (`LZ-H`): `DD-C`'s reset of what a loop stopped
// producing is exactly what a moving window must not trigger. It calls `noteWindowedParent(slot)`
// instead, so the element scopes' `noteNamed` is a no-op and a scrolled-out child keeps `@State`
// the `List` way (`TB-AH`'s bounded retention).

/// The key a unit is recorded under in the container's `RowExtentIndex`: its segment and its
/// source's own id, so two `ForEach`es over equal ids never alias.
struct LazyUnitKey: Hashable {
    let segment: Int
    let id: AnyHashable
}

/// A static member's id (its ordinal among the segments is its segment; the key carries no more).
struct LazyStaticUnitID: Hashable {}

/// What a realised unit hands to prepaint and paint: its nodes and its two later phases, closed
/// over the unit's own mutable content and layout (`ForEach.Member`'s shape, type-erased because
/// the realised set is a window that changes every frame).
@MainActor
final class LazyUnitBox {
    /// The unit's index among all units.
    let unit: Int
    /// The unit's recorded key (`LazyUnitKey`).
    let key: AnyHashable
    /// The nodes the unit registered, in order (0, 1 or several).
    let nodes: [ProposalNodeID]
    /// How many disclosure levels the unit sits below (`OG-J`): each `DisclosureGroup` content level its source passed
    /// through adds one, an outline row adds its own depth. Read by a content `List`'s row chrome; nothing else reads it.
    var depth = 0
    /// Whether the unit is a disclosure group's label row (a content `List` draws its chevron in the row's lead slot).
    var isDisclosureHeader = false
    /// The value `.tag(_:)` gave the unit's element (`OG-E`), if its content is tagged.
    var selectionTag: AnyHashable?
    private let prepaintBody: @MainActor (inout PrepaintPass) -> Void
    private let paintBody: @MainActor (inout PaintPass) -> Void

    init(unit: Int, key: AnyHashable, nodes: [ProposalNodeID],
         prepaint: @escaping @MainActor (inout PrepaintPass) -> Void,
         paint: @escaping @MainActor (inout PaintPass) -> Void) {
        self.unit = unit
        self.key = key
        self.nodes = nodes
        self.prepaintBody = prepaint
        self.paintBody = paint
    }

    func prepaint(_ pass: inout PrepaintPass) { prepaintBody(&pass) }
    func paint(_ pass: inout PaintPass) { paintBody(&pass) }

    /// A box over `content` after its layout request: the three phases of a group member.
    static func make<G: ElementGroup>(unit: Int, key: AnyHashable, nodes: [ProposalNodeID],
                                              content: G, layout: G.GroupLayout) -> LazyUnitBox {
        var content = content
        var layout = layout
        var prepainted: G.GroupPrepaint?
        let box = LazyUnitBox(unit: unit, key: key, nodes: nodes,
                              prepaint: { pass in prepainted = content.prepaintGroup(layout: &layout, pass: &pass) },
                              paint: { pass in
                                  guard var held = prepainted else { return }
                                  prepainted = nil
                                  content.paintGroup(layout: &layout, prepaint: &held, pass: &pass)
                                  prepainted = held
                              })
        box.selectionTag = (content as? any ListRowTagged)?.listRowTag
        return box
    }
}

/// What a content `List` can do with a disclosure group's label unit at input time, without realising it (`OG-E`,
/// `OG-F`): read whether it is expanded, set that, or cascade the change through every descendant.
struct LazyDisclosure {
    /// Whether the group is expanded now (read live, at input time).
    let isExpanded: @MainActor () -> Bool
    /// Writes the group's own expansion, as a click on its chevron does (the binding, or the state slot), and nothing else.
    let set: @MainActor (Bool) -> Void
    /// ⌥→ and ⌥← (`P-K4`, `P-K5`): expands the group and every descendant, or collapses it and every expanded one. A
    /// content list's cannot reach a descendant that was never built, so it is a request the next build carries out
    /// (`OutlineCascade`); an outline's walks its data and writes at once.
    let cascade: @MainActor (Bool) -> Void
}

/// A source of lazily realised units (package: the lazy core's own seam; `LazyContainerGuards`'
/// plain-import guard pins it unreachable).
@MainActor
protocol LazyUnitSource {
    /// How many units the source holds, in `O(1)`.
    var lazyUnitCount: Int { get }

    /// The id units of this source are identified by (a `ForEach` element's id; a static member's
    /// `LazyStaticUnitID`), for `scrollTo` and the index.
    func lazyUnitID(_ unit: Int) -> AnyHashable

    /// The id `scrollTo` and a position binding know the unit by (`SP-B`): its own id unless a source nests
    /// units whose own ids repeat (a `ForEach` of sections).
    func lazyScrollID(_ unit: Int) -> AnyHashable

    /// The `.tag(_:)` value of unit `unit`'s element, or `nil` (`OG-E`): what a content `List` selects by before it falls
    /// back to the unit's id. Called at input time, for units that may not be realised, so it builds the element but lays
    /// nothing out.
    func lazySelectionTag(_ unit: Int) -> AnyHashable?

    /// How many disclosure levels unit `unit` sits below, as its realised box's `depth` will say (`OG-E`, `OG-F`), at
    /// input time and for a unit that may not be realised.
    func lazyDepth(_ unit: Int) -> Int

    /// The disclosure of unit `unit` when it is a group's label row, else `nil` (`OG-E`).
    func lazyDisclosure(_ unit: Int) -> LazyDisclosure?

    /// Called once per frame before any of this source's units is realised, with the source's one
    /// structural slot (`LZ-H`: `noteWindowedParent`).
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass)

    /// Realises unit `unit` (an index into this source) under `slot`'s parent, as the member at
    /// the source's cursor index would be realised in a `VStack`.
    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox
}

extension LazyUnitSource {
    func lazyScrollID(_ unit: Int) -> AnyHashable { lazyUnitID(unit) }
    func lazySelectionTag(_ unit: Int) -> AnyHashable? { nil }
    func lazyDepth(_ unit: Int) -> Int { 0 }
    func lazyDisclosure(_ unit: Int) -> LazyDisclosure? { nil }
}

/// A content group that can list its units (conformers: `ForEach` over proposal content, `Pair`,
/// `EmptyGroup`); anything that does not conform is a static member or makes the container eager.
@MainActor
protocol LazyFlattenable {
    /// Appends this group's sources in order; `false` when some member is not a unit source.
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool
}

/// Lists `group`'s sources, or `nil` when a member makes the container eager (`LZ-B`).
@MainActor
func lazyFlatten<G: ProposalElementGroup>(_ group: G) -> [any LazyUnitSource]? {
    var sources: [any LazyUnitSource] = []
    return lazyFlattenMember(group, into: &sources) ? sources : nil
}

@MainActor
func lazyFlattenMember<G: ProposalElementGroup>(_ group: G, into sources: inout [any LazyUnitSource]) -> Bool {
    if let flattenable = group as? any LazyFlattenable {
        return flattenable.lazyFlatten(into: &sources)
    }
    // A member that consumes exactly one cursor index and registers its own nodes: an element or
    // a proposal component. Everything else (`if`, `switch`, `for`, `LegacyContent`) is not.
    if group is any ProposalElement || group is any Component {
        sources.append(LazyStaticSource(group: group))
        return true
    }
    return false
}

/// A legacy group a lazy container can read: a `ForEach` of legacy rows, or one legacy element or
/// component, adopted through `LegacyContent` (`LZ-S`, amending `LZ-B`: an `.equatable()` row is
/// legacy content, and a lazy stack of them must stay windowed).
@MainActor
protocol LazyLegacyFlattenable {
    func lazyFlattenLegacy(into sources: inout [any LazyUnitSource]) -> Bool
}

/// A legacy member that consumes exactly one cursor index but is neither an `Element` nor a `Component`.
protocol LazyLegacyStaticMember {}
extension EquatableComponent: LazyLegacyStaticMember {}

extension LegacyContent: LazyFlattenable {
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool {
        if let legacy = content as? any LazyLegacyFlattenable {
            return legacy.lazyFlattenLegacy(into: &sources)
        }
        if content is any Element || content is any Component || content is any LazyLegacyStaticMember {
            sources.append(LazyLegacyStaticSource(group: content))
            return true
        }
        return false
    }
}

extension ForEach: LazyLegacyFlattenable {
    func lazyFlattenLegacy(into sources: inout [any LazyUnitSource]) -> Bool {
        sources.append(LazyLegacyForEachSource(forEach: self))
        return true
    }
}

extension EmptyGroup: LazyFlattenable {
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool { true }
}

extension Pair: LazyFlattenable where First: ProposalElementGroup, Second: ProposalElementGroup {
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool {
        lazyFlattenMember(first, into: &sources) && lazyFlattenMember(second, into: &sources)
    }
}

extension ForEach: LazyFlattenable where Content: ProposalElementGroup {
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool {
        if Content.self is any LazySectionContent.Type {   // `SP-H`: a `ForEach` of `Section`s
            guard let source = LazySectionForEachSource(forEach: self) else { return false }
            sources.append(source)
            return true
        }
        sources.append(LazyForEachSource(forEach: self))
        return true
    }
}

/// One static member, one unit.
@MainActor
struct LazyStaticSource<G: ProposalElementGroup>: LazyUnitSource {
    let group: G
    var lazyUnitCount: Int { 1 }
    func lazyUnitID(_ unit: Int) -> AnyHashable { AnyHashable(LazyStaticUnitID()) }
    func lazySelectionTag(_ unit: Int) -> AnyHashable? { (group as? any ListRowTagged)?.listRowTag }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {}

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        var member = group
        var cursor = cursorBase
        let (nodes, layout) = member.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return LazyUnitBox.make(unit: globalIndex,
                                key: AnyHashable(LazyUnitKey(segment: segment, id: lazyUnitID(unit))),
                                nodes: nodes, content: member, layout: layout)
    }
}

/// A `ForEach` over proposal content: one unit per element, identified as `ForEach` identifies
/// (`FI-A`, `FI-B`).
@MainActor
struct LazyForEachSource<Data: RandomAccessCollection, ID: Hashable, Content: ProposalElementGroup>: LazyUnitSource {
    let forEach: ForEach<Data, ID, Content>

    var lazyUnitCount: Int { forEach.data.count }

    func lazyUnitID(_ unit: Int) -> AnyHashable {
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        return AnyHashable(forEach.data[index][keyPath: forEach.idKeyPath])
    }

    func lazySelectionTag(_ unit: Int) -> AnyHashable? {
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        return (forEach.content(forEach.data[index]) as? any ListRowTagged)?.listRowTag
    }

    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {
        pass.frame.stateTable.noteWindowedParent(slot)   // `LZ-H`; never `noteLoop`
    }

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let slot = GlobalElementID(component: .positional(cursorBase), parent: parent)
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        let element = forEach.data[index]
        let key = element[keyPath: forEach.idKeyPath]
        let needsKey = !(ID.self is DescriptionInjectiveID.Type)   // `FI-B`
        let scope = GlobalElementID.child(
            of: slot, at: unit,
            name: ElementID(name: String(describing: key), key: needsKey ? IdentityKey(AnyHashable(key)) : nil))
        pass.frame.stateTable.noteNamed(scope, at: unit)   // a no-op under a windowed parent, `LZ-H`
        if pass.frame.notesScrollKeys { pass.frame.noteScrollKey(scope, AnyHashable(key)) }   // `DD-K`
        pass.frame.forEachIdentityWork.elements += 1       // `FI-B`, counted per element
        if needsKey { pass.frame.forEachIdentityWork.keyed += 1 }
        var built = forEach.content(element)
        var inner = 0
        let (nodes, layout) = built.requestProposalGroupLayout(under: scope, at: &inner, pass: &pass)
        return LazyUnitBox.make(unit: globalIndex, key: AnyHashable(LazyUnitKey(segment: segment, id: AnyHashable(key))),
                                nodes: nodes, content: built, layout: layout)
    }
}

/// One legacy static member (an element, a component, an `.equatable()` component), one unit: the
/// untyped entry, its nodes minted as `ProposalNodeID`s with presentations dropped, exactly as
/// `LegacyContent` does (`LZ-S`).
@MainActor
struct LazyLegacyStaticSource<G: ElementGroup>: LazyUnitSource {
    let group: G
    /// Whether the unit is a disclosure group's label row (`OG-J`).
    var marksHeader = false
    /// What input can do to that group (`OG-E`).
    var disclosure: LazyDisclosure?
    var lazyUnitCount: Int { 1 }
    func lazyDisclosure(_ unit: Int) -> LazyDisclosure? { disclosure }
    func lazyUnitID(_ unit: Int) -> AnyHashable { AnyHashable(LazyStaticUnitID()) }
    func lazySelectionTag(_ unit: Int) -> AnyHashable? { (group as? any ListRowTagged)?.listRowTag }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {}

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        var member = group
        var cursor = cursorBase
        let (nodes, layout) = member.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        let box = LazyUnitBox.make(unit: globalIndex,
                                   key: AnyHashable(LazyUnitKey(segment: segment, id: lazyUnitID(unit))),
                                   nodes: pass.frame.lowering.droppingPresentations(nodes).map(ProposalNodeID.init),
                                   content: member, layout: layout)
        box.isDisclosureHeader = marksHeader
        return box
    }
}

/// A `ForEach` over legacy rows (`Row`, `Box`, an `.equatable()` component): `LazyForEachSource`'s
/// identity, the untyped entry of each element (`LZ-S`).
@MainActor
struct LazyLegacyForEachSource<Data: RandomAccessCollection, ID: Hashable, Content: ElementGroup>: LazyUnitSource {
    let forEach: ForEach<Data, ID, Content>

    var lazyUnitCount: Int { forEach.data.count }

    func lazyUnitID(_ unit: Int) -> AnyHashable {
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        return AnyHashable(forEach.data[index][keyPath: forEach.idKeyPath])
    }

    func lazySelectionTag(_ unit: Int) -> AnyHashable? {
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        return (forEach.content(forEach.data[index]) as? any ListRowTagged)?.listRowTag
    }

    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {
        pass.frame.stateTable.noteWindowedParent(slot)   // `LZ-H`; never `noteLoop`
    }

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let slot = GlobalElementID(component: .positional(cursorBase), parent: parent)
        let index = forEach.data.index(forEach.data.startIndex, offsetBy: unit)
        let element = forEach.data[index]
        let key = element[keyPath: forEach.idKeyPath]
        let needsKey = !(ID.self is DescriptionInjectiveID.Type)   // `FI-B`
        let scope = GlobalElementID.child(
            of: slot, at: unit,
            name: ElementID(name: String(describing: key), key: needsKey ? IdentityKey(AnyHashable(key)) : nil))
        pass.frame.stateTable.noteNamed(scope, at: unit)
        if pass.frame.notesScrollKeys { pass.frame.noteScrollKey(scope, AnyHashable(key)) }
        pass.frame.forEachIdentityWork.elements += 1
        if needsKey { pass.frame.forEachIdentityWork.keyed += 1 }
        var built = forEach.content(element)
        var inner = 0
        let (nodes, layout) = built.requestGroupLayout(under: scope, at: &inner, pass: &pass)
        return LazyUnitBox.make(unit: globalIndex,
                                key: AnyHashable(LazyUnitKey(segment: segment, id: AnyHashable(key))),
                                nodes: pass.frame.lowering.droppingPresentations(nodes).map(ProposalNodeID.init),
                                content: built, layout: layout)
    }
}

/// The units of one container: its sources, each with its first global unit and cursor index.
@MainActor
struct LazyUnitTable {
    let sources: [any LazyUnitSource]
    /// Each source's first global unit, ascending; a trailing entry holds the total.
    let starts: [Int]

    init(_ sources: [any LazyUnitSource]) {
        self.sources = sources
        var starts: [Int] = []
        starts.reserveCapacity(sources.count + 1)
        var total = 0
        for source in sources {
            starts.append(total)
            total += source.lazyUnitCount
        }
        starts.append(total)
        self.starts = starts
    }

    /// The number of units.
    var count: Int { starts[starts.count - 1] }

    /// The source holding global unit `unit` and the unit's index in it (`O(log segments)`).
    func locate(_ unit: Int) -> (segment: Int, local: Int) {
        var low = 0, high = sources.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= unit { low = middle } else { high = middle - 1 }
        }
        // A source with no units shares its start with the next; skip forward to one that holds `unit`.
        var segment = low
        while segment + 1 < sources.count, starts[segment + 1] <= unit { segment += 1 }
        return (segment, unit - starts[segment])
    }

    /// The recorded key of global unit `unit`.
    func key(_ unit: Int) -> AnyHashable {
        let (segment, local) = locate(unit)
        return AnyHashable(LazyUnitKey(segment: segment, id: sources[segment].lazyUnitID(local)))
    }

    /// The raw id of global unit `unit` (a `ForEach` element's id), for `scrollTo`.
    func rawID(_ unit: Int) -> AnyHashable {
        let (segment, local) = locate(unit)
        return sources[segment].lazyScrollID(local)
    }

    /// The disclosure level of global unit `unit` (`OG-E`).
    func depth(_ unit: Int) -> Int {
        let (segment, local) = locate(unit)
        return sources[segment].lazyDepth(local)
    }

    /// The disclosure of global unit `unit` when it is a group's label row (`OG-E`).
    func disclosure(_ unit: Int) -> LazyDisclosure? {
        let (segment, local) = locate(unit)
        return sources[segment].lazyDisclosure(local)
    }

    /// The `.tag(_:)` value of global unit `unit`'s element, or `nil` (`OG-E`).
    func selectionTag(_ unit: Int) -> AnyHashable? {
        let (segment, local) = locate(unit)
        return sources[segment].lazySelectionTag(local)
    }

    /// Realises global unit `unit` under `parent`.
    /// `globalIndex` is the unit's index in the OUTERMOST table when this one is a nested level (`OG-C`).
    func realize(_ unit: Int, globalIndex: Int? = nil, parent: GlobalElementID, pass: inout LayoutPass) -> LazyUnitBox {
        let (segment, local) = locate(unit)
        return sources[segment].realizeLazyUnit(local, globalIndex: globalIndex ?? unit, segment: segment, parent: parent,
                                                cursorBase: segment, pass: &pass)
    }

    /// Calls each source's once-per-frame hook.
    func begin(parent: GlobalElementID, pass: inout LayoutPass) {
        for (segment, source) in sources.enumerated() {
            source.beginLazyFrame(slot: GlobalElementID(component: .positional(segment), parent: parent), pass: &pass)
        }
    }
}
