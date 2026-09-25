import MetalUICore
import MetalUILayout

/// SwiftUI's `ForEach`: one group of elements per item of an identified
/// collection (plan task 10, part 1, ruling `DD-B`).
///
/// ```swift
/// Column { ForEach(people) { person in Text(person.name) } }        // Identifiable
/// Column { ForEach(names, id: \.self) { name in Text(name) } }      // a key path
/// HStack { ForEach(0..<3) { i in Color.red } }                      // a range
/// ```
///
/// **One structural slot, one identity level per element.** The whole `ForEach`
/// takes ONE index of its container's cursor space, as a `for` loop's
/// `ArrayGroup` does (`ID-B`; probe F9: the trailing sibling keeps its state
/// when the `ForEach` shrinks). Under that slot each element is a scope NAMED by
/// its id — `String(describing: element[keyPath: id])` — under which the
/// element's content numbers from 0, the shape a `GridRow` and an `.id()` group
/// already have. So an element's `@State` follows its id through a reorder (F1)
/// and a middle removal (F6), stays with the position when the ids are indices
/// (F5), and is scoped to its `ForEach`: an id moved into another `ForEach` is
/// a new element (F10). An element of two members is one scope (F8).
///
/// **An element the `ForEach` stops producing is reset** (`DD-C`): the
/// `ForEach` notes its slot (`StateTable.noteLoop`), and the sweep resets every
/// element scope the slot held last frame and produced nowhere this frame —
/// `$focus`/`$ax` excepted — so an element that returns starts fresh (F2, F3,
/// F8). A `for` loop resets by the same rule. A `List` inside a SURVIVING
/// element keeps `TB-AH`'s retention for its rows (which are not the loop's
/// children).
///
/// **Duplicate ids: only the first element is produced** (F7, `DD-B` item 5) —
/// and "duplicate" means equal in **value or in description** (`DD-L`): ids
/// `AnyHashable(1)` and `AnyHashable("1")` would mint one name, so the second
/// is not produced, where SwiftUI produces both (probe S6; **divergence 79**,
/// pinned wrong on purpose by `aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst`).
/// A `List`'s rows carry the same description collision (its type doc).
///
/// **The content closure runs during layout, once per produced element per
/// frame**, and what it built is threaded to prepaint and paint in the group
/// layout — never re-run, never stored on `self` (the rebuilt-between-phases
/// hazard `EitherGroup.mismatch` documents).
///
/// **Two entry points, sharing one production** (`produceElements`): the
/// untyped `requestGroupLayout` for a legacy container, and the typed
/// `requestProposalGroupLayout` when the content is proposal content. Only the
/// content registration and the `noteLoop` call are written twice, so each
/// entry's `noteLoop` is pinned on its own (mutations M1b and M1f).
///
/// Not in part 1: `ForEach(_: Binding<C>)` (part 2, `DD-J`).
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: ElementGroup>: ElementGroup {
    public var data: Data
    public var content: (Data.Element) -> Content

    /// The key path each element's id is read through (`\.id`, `\.self`, …).
    let idKeyPath: KeyPath<Data.Element, ID>

    /// A `ForEach` over `data`, each element identified by `id`.
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @ElementBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.idKeyPath = id
        self.content = content
    }

    /// What each produced element built, threaded to prepaint and paint.
    public struct Layout {
        var members: [Member]
    }

    /// One produced element: the content its closure returned (mutated by its
    /// phases, so stored back) and that content's own group layout.
    struct Member {
        var content: Content
        var layout: Content.GroupLayout
    }

    /// The production both entries share: the slot, the per-frame dedupe (by
    /// value and by minted name, `DD-L`), each element's named scope and its
    /// `noteNamed`, and the content closure — with `register` laying out one
    /// element's content under its scope. Returns the slot and the extent for
    /// the caller's own `noteLoop`.
    private func produceElements<Node>(
        under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass,
        register: (inout Content, GlobalElementID, inout LayoutPass) -> ([Node], Content.GroupLayout)
    ) -> (slot: GlobalElementID, extent: Int, nodes: [Node], layout: Layout) {
        let slot = GlobalElementID(component: .positional(cursor), parent: parent)
        cursor += 1
        var seenIDs = Set<ID>()
        var seenNames = Set<String>()
        var offset = 0
        var nodes: [Node] = []
        var members: [Member] = []
        members.reserveCapacity(data.count)
        for element in data {
            let key = element[keyPath: idKeyPath]
            let name = String(describing: key)
            // `DD-B` item 5 (F7) and `DD-L` (S6): a later element whose id — by
            // value, or by the name it would mint — already appeared is not produced.
            guard seenIDs.insert(key).inserted, seenNames.insert(name).inserted else { continue }
            let scope = GlobalElementID.child(of: slot, at: offset, name: ElementID(name))
            pass.frame.stateTable.noteNamed(scope, at: offset)  // `ID-R`, the scope's own copy
            offset += 1
            var built = content(element)
            let (childNodes, childLayout) = register(&built, scope, &pass)
            nodes.append(contentsOf: childNodes)
            members.append(Member(content: built, layout: childLayout))
        }
        return (slot, offset, nodes, Layout(members: members))
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let produced = produceElements(under: parent, at: &cursor, pass: &pass) { built, scope, pass in
            var inner = 0
            return built.requestGroupLayout(under: scope, at: &inner, pass: &pass)
        }
        pass.frame.stateTable.noteLoop(produced.slot, extent: produced.extent)  // `DD-C`
        return (produced.nodes, produced.layout)
    }

    public mutating func prepaintGroup(layout: inout Layout,
                                       pass: inout PrepaintPass) -> [Content.GroupPrepaint] {
        var prepaints: [Content.GroupPrepaint] = []
        prepaints.reserveCapacity(layout.members.count)
        for index in layout.members.indices {
            var member = layout.members[index]
            prepaints.append(member.content.prepaintGroup(layout: &member.layout, pass: &pass))
            layout.members[index] = member
        }
        return prepaints
    }

    public mutating func paintGroup(layout: inout Layout,
                                    prepaint: inout [Content.GroupPrepaint],
                                    pass: inout PaintPass) {
        for index in layout.members.indices {
            var member = layout.members[index]
            member.content.paintGroup(layout: &member.layout, prepaint: &prepaint[index], pass: &pass)
            layout.members[index] = member
        }
    }
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    /// A `ForEach` over `Identifiable` data, each element identified by its `id`.
    public init(_ data: Data, @ElementBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int {
    /// A `ForEach` over a constant range, each element identified by its index.
    public init(_ data: Range<Int>, @ElementBuilder content: @escaping (Int) -> Content) {
        self.init(data, id: \.self, content: content)
    }
}

extension ForEach: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: `produceElements` with the typed registration, and its
    /// own `noteLoop` (pinned by
    /// `aForEachInsideAProposalStackPlacesEveryElementAndResetsItsDroppedTail`,
    /// mutation M1f).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let produced = produceElements(under: parent, at: &cursor, pass: &pass) { built, scope, pass in
            var inner = 0
            return built.requestProposalGroupLayout(under: scope, at: &inner, pass: &pass)
        }
        pass.frame.stateTable.noteLoop(produced.slot, extent: produced.extent)  // `DD-C`, the copy's own
        return (produced.nodes, produced.layout)
    }
}
