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

// MARK: - E3.10: a name that returns (the closeout, ruling `ID-R`)

/// **E3.10 — an `.id` that goes a → b → a starts the returning name fresh**
/// (probe X9–X11, revision 3: SwiftUI's returning name reads a new serial, and
/// X10's constant name keeps one; ruling `ID-R`, record §55 §10). Four frames,
/// names a, a, b, a, one table, five spellings: an element's own `.id` on a
/// `Box` in a `Row` and at the ROOT (`Frame.render`'s root id), an
/// `IdentifiedGroup` under a `VStack` (the typed entry) and under a `Row` (the
/// untyped one), and a named leaf that keeps its count at its own id (the
/// reset includes the departed id, not only what is under it). Each returning probe reads **1**, not the 3 of the old count
/// (2) plus the returning frame. The control (a, a, a, a) keeps counting to 4 in
/// every spelling, so the 1 is the rename's doing and not a fresh table.
///
/// Red before (`89a8337`'s sources): every changed arm reads 3 — a departed
/// name's entries are unmarked, not deleted, and `TB-AH`'s reap only runs past
/// `sweepThreshold`, so a name back within the bound found them (record §55
/// §9.3). Mutation **MRa** (`StateTable.noteNamed` records nothing) reddens it.
@MainActor
@Test func anIDThatReturnsToAnEarlierNameStartsFresh() {
    let changed = ["a", "a", "b", "a"]
    let constant = ["a", "a", "a", "a"]

    for (steps, expected) in [(changed, 1), (constant, 4)] {
        let box = render(steps) { n, reads in Row { Box { ConditionalCounter("p", reads) }.id(n) } }
        #expect(box.values["p"] == expected, "Box in a Row over \(steps): \(String(describing: box.values["p"]))")

        let rootBox = render(steps) { n, reads in Box { ConditionalCounter("p", reads) }.id(n) }
        #expect(rootBox.values["p"] == expected, "root Box over \(steps): \(String(describing: rootBox.values["p"]))")

        let typed = render(steps) { n, reads in
            VStack { HStack { ProposalConditionalCounter("p", reads) }.id(n) }
        }
        #expect(typed.values["p"] == expected, "IdentifiedGroup in a VStack over \(steps): \(String(describing: typed.values["p"]))")

        let untyped = render(steps) { n, reads in
            Row { HStack { ProposalConditionalCounter("p", reads) }.id(n) }
        }
        #expect(untyped.values["p"] == expected, "IdentifiedGroup in a Row over \(steps): \(String(describing: untyped.values["p"]))")

        // The named element keeps its count at its OWN id, not under it — the
        // reset includes the departed id itself.
        let own = render(steps) { n, reads in Row { NamedCounter(name: n, reads: reads) } }
        #expect(own.values["p"] == expected, "a counter at its own named id over \(steps): \(String(describing: own.values["p"]))")
    }
}

/// `ConditionalCounter` with a name of its own: it counts under `withState(id,
/// …)` at its OWN (named) id, the way `ScrollView` keeps its offset.
private struct NamedCounter: Element {
    let name: String
    let reads: ConditionalReads
    var elementID: ElementID? { ElementID(name) }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        var value = 0
        pass.withState(id, initial: 0) { $0 += 1; value = $0 }
        reads.values["p"] = value
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// **E3.11 — a name that leaves one position for a sibling's keeps its state**
/// (the rename reset's other half, ruling `ID-R`: a name is reset only when it
/// is produced NOWHERE in the frame that dropped it). Two named `Box`es in a
/// `Row` swap names each frame — `[x, y]`, `[y, x]`, `[x, y]` — so both
/// positions change name every frame and neither name vanishes: `x` and `y`
/// each read 3. The control for E3.10's reset: resetting by position alone
/// (mutation **MRb**, the produced-anywhere check dropped) reads 1 and 1.
///
/// Green before (pin).
@MainActor
@Test func aNameThatMovesToASiblingsPositionKeepsItsState() {
    let reads = render([["x", "y"], ["y", "x"], ["x", "y"]]) { names, reads in
        Row {
            Box { ConditionalCounter(names[0], reads) }.id(names[0])
            Box { ConditionalCounter(names[1], reads) }.id(names[1])
        }
    }
    #expect([reads.values["x"], reads.values["y"]] == [3, 3], "each name keeps its own count: \(reads.values)")
}

/// A `Component` that declares its own name, over one counter.
private struct NamedCounterComponent: Component {
    let name: String
    let reads: ConditionalReads
    var elementID: ElementID? { ElementID(name) }
    var content: some ElementGroup { ConditionalCounter("p", reads) }
}

/// **E3.12 — every other naming site departs its old name too** (ruling
/// `ID-R`: `StateTable.noteNamed` is called at each site that mints a named id,
/// and each call is a copy — Practices, "a copy of a pinned implementation is
/// unpinned"). Names a, a, b, a against one table, three spellings E3.10 does
/// not reach: an erased element (`AnyElement`'s own group entry, a copy of
/// `enteringGroupMember`), a `Component` that declares its `elementID` (its
/// untyped group entry), and a name on an INNER modifier layer (`Box { p }
/// .padding(2).id(n).padding(4)`: `.id` names the first padding layer, which
/// the second `.padding` makes an inner layer — `ModifiedContent`'s
/// `innermostID`; `Box { p }.id(n).padding(4)` would not reach it, the named
/// `Box` there being the chain's content, noted by `enteringGroupMember`).
/// Each returning probe reads 1; the constant control reads 4.
///
/// Red before: every changed arm reads 3. Mutations **MRd** (`AnyElement`'s
/// note deleted), **MRe** (the untyped `Component` note deleted) and **MRf**
/// (`innermostID`'s note deleted) each redden their own arm alone.
@MainActor
@Test func everyNamingSiteStartsAReturningNameFresh() {
    for (steps, expected) in [(["a", "a", "b", "a"], 1), (["a", "a", "a", "a"], 4)] {
        let erased = render(steps) { n, reads in
            Row { AnyElement(Box { ConditionalCounter("p", reads) }.id(n)) }
        }
        #expect(erased.values["p"] == expected, "AnyElement over \(steps): \(String(describing: erased.values["p"]))")

        let component = render(steps) { n, reads in Row { NamedCounterComponent(name: n, reads: reads) } }
        #expect(component.values["p"] == expected, "named Component over \(steps): \(String(describing: component.values["p"]))")

        let inner = render(steps) { n, reads in
            Row { Box { ConditionalCounter("p", reads) }.padding(Pixels(2)).id(n).padding(Pixels(4)) }
        }
        #expect(inner.values["p"] == expected, "inner-layer name over \(steps): \(String(describing: inner.values["p"]))")
    }
}

// MARK: - E3.13: the resets' work is one pass over the table

/// Renders `make(step)` for each step against `table` and returns, per frame,
/// the entries its sweep's resets visited (`lastResetScanWork`) and the table's
/// count after the sweep.
@MainActor
private func resetWork<Root: Element, Step>(_ steps: [Step], table: StateTable,
                                            _ make: (Step) -> Root) -> [(work: Int, count: Int)] {
    steps.map { step in
        var tree = make(step)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
        return (table.lastResetScanWork, table.count)
    }
}

/// **E3.13 — the resets cost one pass over the table, however many names
/// depart or conditionals go absent in one frame** (`ID-R` item 8; CLAUDE.md
/// Practices: a work count, a branching tree, red on arrival). Three trees,
/// each a counter per leaf holding one entry at its own id, so a table of `T`
/// entries is `T` leaves:
///
/// - **A**, 1000 named rows in a `VStack`, every name replaced each frame
///   (`g0-i`, `g1-i`, `g2-i`). `T` = 1000. At the renaming frame's sweep the
///   table holds the last frame's 1000 plus this frame's 1000, so one pass
///   visits **2000**; the old per-name scan read 1 500 500 (Σ 2000 − k).
/// - **B**, 100 named `VStack`s of 100 named leaves each, `T` = 10 000; all 100
///   outer names replaced: one pass visits the old 10 000 plus the new 10 000,
///   **20 000** (per-name: 1 505 000); none replaced, the control: **0** (no
///   pass at all).
/// - **C**, 1000 unnamed `VStack { if flag { counter } }` all going false in
///   one frame (`ID-C`'s `noteAbsent`, the other reset): nothing new is written,
///   one pass visits **1000** (per-transition: 500 500, Σ 1000 − k).
///
/// Each figure is an upper bound (a cheaper pass passes); each arm also reads
/// the table after the sweep, so a pass that deletes nothing cannot pass.
/// Mutation **MRl** (the reset pass run once per departed name and per absent
/// slot again, the pre-fix cost) reddens A, B and C.
@MainActor
@Test func theResetsScanTheTableOncePerSweep() throws {
    let reads = ConditionalReads()

    let a = resetWork([0, 1, 2], table: StateTable()) { g in
        VStack { for i in 0..<1000 { ProposalConditionalCounter("r", reads).id("g\(g)-\(i)") } }
    }
    try #require(a.count == 3)
    #expect(a[0].work == 0, "A, first frame: nothing departs: \(a[0])")
    #expect(a[1].work <= 2000 && a[2].work <= 2000, "A, 1000 names replaced: one pass: \(a)")
    #expect(a[1].count == 1000 && a[2].count == 1000, "A: every departed name was reset: \(a)")

    for (renamed, bound) in [(0, 0), (100, 20_000)] {
        let b = resetWork([0, 1], table: StateTable()) { g in
            HStack {
                for i in 0..<100 {
                    VStack { for j in 0..<100 { ProposalConditionalCounter("c", reads).id("c\(j)") } }
                        .id(i < renamed ? "g\(g)-\(i)" : "s\(i)")
                }
            }
        }
        try #require(b.count == 2)
        #expect(b[1].work <= bound, "B, \(renamed) of 100 outer names replaced: \(b)")
        #expect(b[1].count == 10_000, "B, \(renamed) replaced: the table settles at 10 000: \(b)")
    }

    let c = resetWork([true, false], table: StateTable()) { flag in
        VStack { for _ in 0..<1000 { VStack { if flag { ProposalConditionalCounter("f", reads) } } } }
    }
    try #require(c.count == 2)
    #expect(c[1].work <= 1000, "C, 1000 conditionals gone absent: one pass: \(c)")
    #expect(c[1].count == 0, "C: every absent subtree was reset: \(c)")
}
