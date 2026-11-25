import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 2 of the hierarchical lists, identity and geometry (rulings `OG-B`, `OG-C`): the same recursive tree laid out by
// an eager `VStack` and by a `LazyVStack` gets the SAME element ids, so `@State` survives moving the tree between the two
// containers over one `StateTable`, and the lazy path's rows sit where the eager group puts them (label row 24, then
// the children, no indent, 0 spacing). The tree is small enough that the lazy window holds every unit.

@MainActor private final class Node: Identifiable {
    let name: String
    var expanded: Bool
    var kids: [Node]
    nonisolated var id: String { name }

    init(_ name: String, expanded: Bool = false, kids: [Node] = []) {
        self.name = name
        self.expanded = expanded
        self.kids = kids
    }
}

@MainActor private final class Serials {
    var next = 0
    var seen: [String: Int] = [:]
    func mint() -> Int { next += 1; return next }
}

private struct LeafRow: Component {
    let name: String
    let serials: Serials
    @State private var serial: Int

    init(name: String, serials: Serials) {
        self.name = name
        self.serials = serials
        _serial = State(wrappedValue: serials.mint())
    }

    var content: some ProposalElementGroup {
        let _ = serials.seen[name] = serial
        Color.gray.frame(height: Pixels(20))
    }
}

private struct NodeRow: Component {
    let node: Node
    let serials: Serials

    @ElementBuilder var content: some ElementGroup {
        if !node.kids.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { node.expanded }, set: { node.expanded = $0 })) {
                ForEach(node.kids) { NodeRow(node: $0, serials: serials) }
            } label: { Text(node.name) }
        } else {
            LeafRow(name: node.name, serials: serials)
        }
    }
}

/// A (open: a1, B (open: b1, b2), a2), C (closed: c1), d.
@MainActor private func tree() -> [Node] {
    [Node("A", expanded: true, kids: [Node("a1"), Node("B", expanded: true, kids: [Node("b1"), Node("b2")]), Node("a2")]),
     Node("C", kids: [Node("c1")]),
     Node("d")]
}

@MainActor private func render(_ roots: [Node], serials: Serials, lazy: Bool, states: StateTable) -> Frame {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(1000)), scaleFactor: 1, stateTable: states,
                      recordsElementBounds: true)
    if lazy {
        var root = ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) { ForEach(roots) { NodeRow(node: $0, serials: serials) } }
        }
        frame.render(&root)
    } else {
        var root = ProposalScrollView {
            VStack(alignment: .leading, spacing: Pixels(0)) { ForEach(roots) { NodeRow(node: $0, serials: serials) } }
        }
        frame.render(&root)
    }
    return frame
}

/// **Identity equals the eager `VStack`'s.** One tree, one `StateTable`: rendered by a `LazyVStack`, then a `VStack`,
/// then a `LazyVStack`, every leaf reads the serial minted at its FIRST appearance (the `@State` seeded under the
/// same id each time: moving the tree between the containers keeps it), and the lazy frame's element ids are a subset
/// of the eager frame's (the eager group's own stack, which the lazy path bypasses, is the only difference). The 5
/// leaves are a1, b1, b2, a2, d (c1 is under a collapsed group: no state). Mutations: a lazily flattened `Component` not
/// entered with `enterComponent` (its level missing from the ids: the serials differ); the `if`/`else` branch slot
/// numbered 0 and 1 swapped; the disclosure's content slot numbered 0 instead of 1 (the leaves' ids move).
@Test @MainActor func theSameTreeKeepsItsStateMovedBetweenAVStackAndALazyVStack() {
    let serials = Serials()
    let states = StateTable()
    let roots = tree()
    let lazy1 = render(roots, serials: serials, lazy: true, states: states)
    let first = serials.seen
    #expect(Set(first.keys) == ["a1", "b1", "b2", "a2", "d"], "\(first.keys.sorted())")
    #expect(Set(first.values).count == 5, "five distinct serials: \(first)")
    let eager = render(roots, serials: serials, lazy: false, states: states)
    #expect(serials.seen == first, "eager read the lazy frame's serials: \(serials.seen) vs \(first)")
    let lazy2 = render(roots, serials: serials, lazy: true, states: states)
    #expect(serials.seen == first, "and back: \(serials.seen) vs \(first)")
    let lazyIDs = Set(lazy1.elementBounds.keys), eagerIDs = Set(eager.elementBounds.keys)
    #expect(lazyIDs == Set(lazy2.elementBounds.keys))
    #expect(lazyIDs.isSubset(of: eagerIDs), "lazy-only ids: \(lazyIDs.subtracting(eagerIDs))")
    #expect(eagerIDs.subtracting(lazyIDs).count == 3, "the eager groups' own stacks only (A, B and C): \(eagerIDs.subtracting(lazyIDs).count)")
}

/// **Geometry equals the eager group's** for full-width children: every id both frames share has the same bounds
/// (A's label row 0 .. 24, a1 24 .. 44, B's row 44 .. 68, b1, b2, a2, C's row, d: label rows 24, leaves 20, no
/// indent). Mutation: the label row's height read as 20 or the children spaced by the stack's 8.
@Test @MainActor func theLazyPathPlacesRowsWhereTheEagerGroupDoes() {
    let serials = Serials()
    let roots = tree()
    let lazy = render(roots, serials: serials, lazy: true, states: StateTable())
    let eager = render(roots, serials: serials, lazy: false, states: StateTable())
    let shared = Set(lazy.elementBounds.keys).intersection(eager.elementBounds.keys)
    #expect(shared.count == lazy.elementBounds.count && shared.count > 15, "shared \(shared.count) of \(lazy.elementBounds.count)")
    let differing = shared.filter { lazy.elementBounds[$0] != eager.elementBounds[$0] }
    #expect(differing.isEmpty, "differing: \(differing.map { ($0, String(describing: lazy.elementBounds[$0]), String(describing: eager.elementBounds[$0])) })")
}
