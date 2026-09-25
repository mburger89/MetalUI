import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 8, lane 3 (`docs/superpowers/specs/2026-09-25-composition-identity-design.md`
// §3.6, ruling `ID-G`): `.id(_:)` on every element group. `IdentifiedGroup`
// consumes ONE cursor index, named, numbers its content from 0 under that id,
// and contributes its content's nodes unchanged. `StyledElement.id(_:) -> Self`
// is untouched and still wins for every `StyledElement` (E3.8, E3.9 and guard
// G3.1). SwiftUI's answers are probe arms X1–X8 of
// `docs/probes/swiftui-composition-identity.swift`.
//
// **Two entries, one slot helper**: the untyped `requestGroupLayout` (a legacy
// parent) and the typed `requestProposalGroupLayout` (a proposal parent). E3.1
// runs both — a `Row` parent and a `VStack` parent — so a mutation of either
// entry has an arm that sees it.

private let size = Size<Pixels>(width: Pixels(300), height: Pixels(200))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func named(_ parent: GlobalElementID, _ index: Int, _ name: String) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: ElementID(name))
}

/// Renders `make(step)` for each step against one table, through `Frame.render`,
/// and returns the reads.
@MainActor
private func render<Root: Element, Step>(_ steps: [Step], _ make: (Step, ConditionalReads) -> Root)
    -> ConditionalReads {
    let table = StateTable()
    let reads = ConditionalReads()
    for step in steps {
        var tree = make(step, reads)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    return reads
}

/// A `Component` with its own `@State` — counted in `content`, as
/// `ComponentTests`' `Counter` counts — and two counting members.
private struct StatefulPair: Component {
    @State var own = 0
    let reads: ConditionalReads

    var content: some ElementGroup {
        own += 1
        reads.values["own"] = own
        return TwoCounters(first: "a", second: "b", reads: reads)
    }
}

// MARK: - E3.1–E3.3: an id on a container resets what is inside it

/// **E3.1 — an `.id` on a proposal stack resets its content when it changes**
/// (probe X4: `.id(generation)` on an `HStack` resets its child). `HStack {
/// probe }.id("g\(n)")` inside a `VStack` (the typed entry) and inside a `Row`
/// (the untyped entry): three frames at one name count 1, 2, 3; a fourth frame
/// at a new name restarts at 1.
///
/// Red before: does not compile (`value of type 'HStack<…>' has no member
/// 'id'`). Mutation **M3a** (`IdentifiedGroup` numbers under `.positional(cursor)`,
/// the name ignored) keeps the count at 4 in both arms.
@MainActor
@Test func anIDOnAProposalStackResetsItsContentWhenItChanges() {
    let steps = [0, 0, 0, 1]
    let typed = render(steps) { n, reads in
        VStack { HStack { ProposalConditionalCounter("p", reads) }.id("g\(n)") }
    }
    #expect(typed.values["p"] == 1, "VStack parent: a changed id restarts the probe; read \(String(describing: typed.values["p"]))")
    #expect(typed.ids["p"] == child(child(named(root, 0, "g1"), 0), 0), "typed: \(String(describing: typed.ids["p"]))")

    let untyped = render(steps) { n, reads in
        Row { HStack { ProposalConditionalCounter("p", reads) }.id("g\(n)") }
    }
    #expect(untyped.values["p"] == 1, "Row parent: a changed id restarts the probe; read \(String(describing: untyped.values["p"]))")
    #expect(untyped.ids["p"] == child(child(named(root, 0, "g1"), 0), 0), "untyped: \(String(describing: untyped.ids["p"]))")

    // Control: the name held constant keeps counting (X1), so the reset above
    // is the name's doing, not a fresh table.
    let kept = render([0, 0, 0, 0]) { n, reads in
        VStack { HStack { ProposalConditionalCounter("p", reads) }.id("g\(n)") }
    }
    #expect(kept.values["p"] == 4, "a constant id keeps its content's state; read \(String(describing: kept.values["p"]))")
}

/// **E3.2 — an `.id` on a `Grid` and on a `GridRow` resets their cells** (probe
/// X5). Each arm: three frames at one name, a fourth at a new one; the cell
/// restarts at 1. The row arm's sibling row (unnamed) keeps counting — the id
/// resets only what is under it.
///
/// Red before: does not compile. Mutation **M3a**.
@MainActor
@Test func anIDOnAGridAndOnAGridRowResetsTheirCells() {
    let steps = [0, 0, 0, 1]
    let grid = render(steps) { n, reads in
        VStack {
            Grid { GridRow { ProposalConditionalCounter("cell", reads) } }.id("g\(n)")
        }
    }
    #expect(grid.values["cell"] == 1, "grid: \(String(describing: grid.values["cell"]))")

    let row = render(steps) { n, reads in
        VStack {
            Grid {
                GridRow { ProposalConditionalCounter("cell", reads) }.id("r\(n)")
                GridRow { ProposalConditionalCounter("other", reads) }
            }
        }
    }
    #expect(row.values["cell"] == 1, "row: \(String(describing: row.values["cell"]))")
    #expect(row.values["other"] == 4, "the unnamed row keeps counting: \(String(describing: row.values["other"]))")
}

/// **E3.3 — an `.id` on a `Component` resets its own state and its members'**
/// (probe X6: a custom view whose body is a `Group` resets both views). A
/// `StatefulPair` — its own `@State` and two counting members — `.id("c\(n)")`
/// in a `Row`: three frames at one name read 3, 3, 3; a fourth at a new name
/// reads 1, 1, 1. Before this ruling a `Component` could be named only by
/// declaring `var elementID`.
///
/// Red before: does not compile (`value of type 'StatefulPair' has no member
/// 'id'`). Mutation **M3a**.
@MainActor
@Test func anIDOnAComponentResetsItsStateAndItsMembers() {
    let three = render([0, 0, 0]) { n, reads in Row { StatefulPair(reads: reads).id("c\(n)") } }
    #expect([three.values["own"], three.values["a"], three.values["b"]] == [3, 3, 3],
            "a constant id keeps all three: \(three.values)")
    let changed = render([0, 0, 0, 1]) { n, reads in Row { StatefulPair(reads: reads).id("c\(n)") } }
    #expect([changed.values["own"], changed.values["a"], changed.values["b"]] == [1, 1, 1],
            "a changed id resets the component and both members: \(changed.values)")
}

// MARK: - E3.4–E3.5: one slot, layout-transparent

/// **E3.4 — an `.id` on a group takes one slot and numbers its content inside
/// it.** `Row { (a; b).id("x"); c }`: `a` at `root/named(x)/0`, `b` at
/// `root/named(x)/1`, and the trailing `c` at `root/1` — the id consumed one
/// index of the row's cursor, however many members it wraps.
///
/// Red before: does not compile. Mutation **M3b** (the content numbered with the
/// outer cursor under the parent) puts `a` and `b` at `root/1` and `root/2` and
/// `c` at `root/3`.
@MainActor
@Test func anIDOnAGroupTakesOneSlotAndNumbersItsContentInside() {
    let reads = render([0]) { _, reads in
        Row {
            TwoCounters(first: "a", second: "b", reads: reads).content.id("x")
            ConditionalCounter("c", reads)
        }
    }
    let slot = named(root, 0, "x")
    #expect(reads.ids["a"] == child(slot, 0), "a: \(String(describing: reads.ids["a"]))")
    #expect(reads.ids["b"] == child(slot, 1), "b: \(String(describing: reads.ids["b"]))")
    #expect(reads.ids["c"] == child(root, 1), "c: \(String(describing: reads.ids["c"]))")
}

/// **E3.5 — an `.id` on a group is layout-transparent.** `VStack { HStack { a;
/// b }.id("x") }` against the same tree without the id, in a 300×200 frame:
/// the same node count, the same emitted rects, and the same recorded bounds
/// (compared as a sorted list, since the ids differ by the name's level).
///
/// Red before: does not compile. Mutation **M3c** (the content registered under
/// an extra one-child `ZStack`) moves the node count by one.
@MainActor
@Test func anIDOnAGroupIsLayoutTransparent() {
    func run<Root: Element>(_ tree: Root) -> (nodes: Int, rects: [[Float]], bounds: [[Float]]) {
        var tree = tree
        let frame = Frame(contentSize: size, scaleFactor: 1, recordsElementBounds: true)
        frame.render(&tree)
        let rects = frame.finalizedScene().rects.map {
            [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height]
        }
        let bounds = frame.elementBounds.values.map {
            [$0.origin.x.value, $0.origin.y.value, $0.size.width.value, $0.size.height.value]
        }.sorted { $0.lexicographicallyPrecedes($1) }
        return (frame.tree.nodeCount, rects, bounds)
    }
    let identified = run(VStack {
        HStack {
            Rectangle(width: Pixels(40), height: Pixels(20), color: .accent)
            Rectangle(width: Pixels(30), height: Pixels(50), color: .surface)
        }.id("x")
    })
    let plain = run(VStack {
        HStack {
            Rectangle(width: Pixels(40), height: Pixels(20), color: .accent)
            Rectangle(width: Pixels(30), height: Pixels(50), color: .surface)
        }
    })
    #expect(identified.nodes == plain.nodes, "nodes \(identified.nodes) vs \(plain.nodes)")
    #expect(identified.rects == plain.rects, "rects \(identified.rects) vs \(plain.rects)")
    #expect(identified.bounds == plain.bounds, "bounds \(identified.bounds) vs \(plain.bounds)")
    #expect(identified.rects.count == 2, "both rectangles paint: \(identified.rects)")
}

// MARK: - E3.6–E3.7: names in a loop, duplicate names

/// A proposal counter keyed by its label, for loop items.
@MainActor
private func item(_ label: String, _ reads: ConditionalReads) -> IdentifiedGroup<ProposalConditionalCounter> {
    ProposalConditionalCounter(label, reads).id(label)
}

/// **E3.6 — a named proposal item keeps its state through a loop reorder**
/// (`ForEach`'s rule, the job `reorderingANamedListCarriesEachItemsState` pins
/// for legacy content). `HStack { for x in items { probe(x).id(x) } }` over
/// `["a"]`, `["a", "b"]`, `["b", "a"]`: `a` reads 3 and `b` 2 — each its own
/// count, whatever its position.
///
/// Red before: does not compile. Mutation **M3a**: positions, not names — `b`,
/// now first, reads `a`'s 3, and `a` reads `b`'s 2.
@MainActor
@Test func aNamedProposalItemKeepsItsStateThroughALoopReorder() {
    let reads = render([["a"], ["a", "b"], ["b", "a"]]) { items, reads in
        HStack { for x in items { item(x, reads) } }
    }
    #expect(reads.values["a"] == 3, "a: \(String(describing: reads.values["a"]))")
    #expect(reads.values["b"] == 2, "b: \(String(describing: reads.values["b"]))")
}

/// **E3.7 — two sibling groups with the same `.id` share one identity**
/// (divergence 72, ruling `ID-H`, on the new API; SwiftUI keeps them distinct,
/// probe X2). `VStack { HStack { a }.id("x"); HStack { b }.id("x") }`, one
/// frame: `a` and `b` resolve to the same id and one entry, so `b` reads 2.
///
/// Red before: does not compile. Mutation **M3a**: positions keep them apart,
/// 1 and 1.
@MainActor
@Test func twoSiblingGroupsWithTheSameIDShareOneIdentity() {
    let reads = render([0]) { _, reads in
        VStack {
            HStack { ProposalConditionalCounter("a", reads) }.id("x")
            HStack { ProposalConditionalCounter("b", reads) }.id("x")
        }
    }
    #expect(reads.ids["a"] == reads.ids["b"], "one identity: \(String(describing: reads.ids["a"])) vs \(String(describing: reads.ids["b"]))")
    #expect([reads.values["a"], reads.values["b"]] == [1, 2], "one entry, counted twice: \(reads.values)")
}

// MARK: - E3.8–E3.9: `StyledElement.id` (pins)

/// **E3.8 — changing an element's `.id` resets its state** (probe A1, X8). The
/// existing `StyledElement.id(_:) -> Self` on a `Box` over a counter:
/// `Row { Box { probe }.id("a\(n)") }` — a constant name keeps (4), a changed
/// one restarts (1). A pin of behaviour that already held (record §55 §3's
/// unpinned M row).
///
/// Green before (pin). Mutation **M3d** (`GlobalElementID.child(of:at:name:)`
/// ignores `name`) reddens this among many.
@MainActor
@Test func changingAnElementsIDResetsItsState() {
    let kept = render([0, 0, 0, 0]) { n, reads in Row { Box { ConditionalCounter("p", reads) }.id("a\(n)") } }
    #expect(kept.values["p"] == 4, "constant: \(String(describing: kept.values["p"]))")
    let changed = render([0, 0, 0, 1]) { n, reads in Row { Box { ConditionalCounter("p", reads) }.id("a\(n)") } }
    #expect(changed.values["p"] == 1, "changed: \(String(describing: changed.values["p"]))")
}

/// **E3.9 — an `.id` written inside a modifier still resets when it changes**
/// (probe X7; ruling `ID-M` item 5). `Row { Box { probe }.id("a\(n)")
/// .padding(Pixels(4)) }`: the padding layer takes the row's slot and the named
/// `Box` sits under it; a constant name keeps (4), a changed one restarts (1).
/// `.id()` outermost is still the rule for index stability in a `for` loop;
/// this pins only the reset.
///
/// Green before (pin). Mutation **M3d**.
@MainActor
@Test func anIDWrittenInsideAModifierStillResetsWhenItChanges() {
    let kept = render([0, 0, 0, 0]) { n, reads in
        Row { Box { ConditionalCounter("p", reads) }.id("a\(n)").padding(Pixels(4)) }
    }
    #expect(kept.values["p"] == 4, "constant: \(String(describing: kept.values["p"]))")
    let changed = render([0, 0, 0, 1]) { n, reads in
        Row { Box { ConditionalCounter("p", reads) }.id("a\(n)").padding(Pixels(4)) }
    }
    #expect(changed.values["p"] == 1, "changed: \(String(describing: changed.values["p"]))")
}
