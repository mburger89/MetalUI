import Testing
import MetalUICore
@testable import MetalUI

// Plan task 10, part 1, lane 1 (`docs/superpowers/specs/2026-09-25-data-and-scrolling-design.md`
// §4, rulings `DD-B`, `DD-C`, `DD-L`): `ForEach` over identified data, and the
// loop reset rule that retires divergence 74 for `ForEach` and `for` alike.
// SwiftUI's answers are probe arms F1–F10 of
// `docs/probes/swiftui-data-and-scrolling.swift` and S6 of
// `docs/probes/swiftui-scrollviewreader-scope.swift`.
//
// Every frame is driven through `Frame.render`, whose `stateTable.sweep()` is
// where the loop rule runs — a layout-only frame never resets.
//
// **Four minting copies note a loop** (`ArrayGroup`'s untyped and typed entries,
// `ForEach`'s untyped and typed entries): each test names the copy its mutation
// is applied to, and each copy is mutated on its own.
//
// State is read through `ConditionalCounter`/`ProposalConditionalCounter`
// (`ConditionalIdentityTests.swift`): a count that steps by `step` per frame, so
// a retained entry reads more than one step on a returning element's first
// frame back, and an adopted count differs from an own one when steps differ.

private let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
private let root = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func named(_ parent: GlobalElementID, _ name: String) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: 0, name: ElementID(name))
}

/// Renders `make(step)` for each step against one table, through `Frame.render`,
/// calling `after` once each frame is done.
@MainActor
@discardableResult
private func render<Root: Element, Step>(_ steps: [Step], table: StateTable = StateTable(),
                                         _ make: (Step) -> Root,
                                         after: () -> Void = {}) -> StateTable {
    for step in steps {
        var tree = make(step)
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
        after()
    }
    return table
}

// MARK: - The `for` loop's reset (`DD-C`): 1.12, 1.13

/// **1.12 — a `for` loop's NAMED iteration dropped at the tail starts fresh on
/// its return.** `Row { for x in xs { C.id(x) } }` over [a, b], [a], [a, b]: b
/// reads **1**, a reads 3.
///
/// A name nothing replaces is not departed by `ID-R` (its position is simply
/// not evaluated), so until `DD-C` b's entries were retained and handed back —
/// **red before: 2**. The loop rule's named-children half resets it.
/// Mutation **M1h** (the sweep's named-children half removed, the positional
/// half kept) reddens this.
@MainActor
@Test func aForLoopsNamedIterationDroppedAtTheTailStartsFreshOnReturn() {
    let reads = ConditionalReads()
    render([["a", "b"], ["a"], ["a", "b"]]) { xs in
        Row {
            for x in xs { ConditionalCounter(x, reads).id(x) }
        }
    }
    let loop = child(root, 0)
    #expect(reads.ids["b"] == child(named(loop, "b"), 0), "\(String(describing: reads.ids["b"]))")
    #expect(reads.values["b"] == 1, "the dropped named iteration starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["a"] == 3, "the surviving iteration keeps counting: \(reads.values)")
}

/// **1.13 — a `for` loop inside a PROPOSAL container resets its dropped tail.**
/// `HStack { for i in 0..<n { P } }`, n 2 → 1 → 2, goes through the TYPED
/// `ArrayGroup` copy (`ProposalElementGroup.swift`): iteration 1 reads **1**,
/// iteration 0 reads 3.
///
/// **Red before: 2** (the typed copy never reset either). Mutation **M1i** (the
/// typed `ArrayGroup` copy's `noteLoop` removed) reddens this test alone — the
/// untyped copy's tests go through `Row`.
@MainActor
@Test func aForLoopInsideAProposalContainerResetsItsDroppedTail() {
    let reads = ConditionalReads()
    let table = StateTable()
    for n in [2, 1, 2] {
        var tree = HStack(spacing: Pixels(0)) {
            for i in 0..<n { ProposalConditionalCounter("\(i)", reads) }
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    let loop = child(root, 0)
    #expect(reads.ids["1"] == child(loop, 1), "\(String(describing: reads.ids["1"]))")
    #expect(reads.values["1"] == 1, "the dropped iteration starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["0"] == 3, "the surviving iteration keeps counting: \(reads.values)")
}

// MARK: - `ForEach` identity (`DD-B`): 1.1–1.9

/// An identified datum: `id` is the key, `label` what the counter records under,
/// `step` its per-frame increment.
private struct Item: Identifiable {
    let id: String
    var label: String
    var step: Int = 1
    init(_ id: String, label: String? = nil, step: Int = 1) {
        self.id = id
        self.label = label ?? id
        self.step = step
    }
}

/// `Row { ForEach(items) { C(item.label, step: item.step) } }` over each step.
@MainActor
@discardableResult
private func renderItems(_ steps: [[Item]], _ reads: ConditionalReads,
                         table: StateTable = StateTable()) -> StateTable {
    render(steps, table: table) { items in
        Row {
            ForEach(items) { item in ConditionalCounter(item.label, reads, step: item.step) }
        }
    }
}

/// The loop slot a `ForEach` that is its container's first member takes.
private let loop = child(root, 0)

/// The id a `ForEach` element's single counter is laid out at.
private func member(_ key: String, _ index: Int = 0) -> GlobalElementID {
    child(named(loop, key), index)
}

/// **1.1 — a `ForEach` keeps each element's state through a reorder** (probe
/// F1). [a, b] → [b, a], a stepping by 1 and b by 10: a reads 2 and b 20 — each
/// its own count, under its own name.
///
/// Mutation **M1a** (the element scope minted `.positional(offset)` instead of
/// the key's name) makes state follow the position: each reads 11.
@MainActor
@Test func aForEachKeepsEachElementsStateThroughAReorder() {
    let reads = ConditionalReads()
    let a = Item("a"), b = Item("b", step: 10)
    renderItems([[a, b], [b, a]], reads)
    #expect(reads.values["a"] == 2, "a's own count (11 is b's): \(reads.values)")
    #expect(reads.values["b"] == 20, "b's own count (11 is a's): \(reads.values)")
    #expect(reads.ids["a"] == member("a"), "\(String(describing: reads.ids["a"]))")
    #expect(reads.ids["b"] == member("b"), "\(String(describing: reads.ids["b"]))")
}

/// **1.2 — a `ForEach` element removed and re-added starts fresh** (probe F2).
/// [a, b], [a], [a, b]: b reads **1**, a reads 3.
///
/// Mutation **M1b** (the untyped entry's `noteLoop` call removed) retains b's
/// entry: it reads 2.
@MainActor
@Test func aForEachElementRemovedAndReAddedStartsFresh() {
    let reads = ConditionalReads()
    renderItems([[Item("a"), Item("b")], [Item("a")], [Item("a"), Item("b")]], reads)
    #expect(reads.values["b"] == 1, "the returning element starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["a"] == 3, "the surviving element keeps counting: \(reads.values)")
}

/// **1.3 — a `ForEach` over a range resets its dropped tail** (probe F3).
/// `ForEach(0..<n)`, n 2 → 1 → 2: element 1 reads **1**, element 0 reads 3, at
/// `root/0/"1"/0`.
///
/// Mutation **M1b** reddens this (element 1 reads 2).
@MainActor
@Test func aForEachOverARangeResetsItsDroppedTail() {
    let reads = ConditionalReads()
    render([2, 1, 2]) { n in
        Row { ForEach(0..<n) { i in ConditionalCounter("\(i)", reads) } }
    }
    #expect(reads.ids["1"] == member("1"), "\(String(describing: reads.ids["1"]))")
    #expect(reads.values["1"] == 1, "the returning element starts fresh (2 is retention): \(reads.values)")
    #expect(reads.values["0"] == 3, "\(reads.values)")
}

/// **1.4 — the key decides whether state follows the value or the position.**
/// Arm 1 (probe F4): `id: \.self` over [b] → [a, b], b stepping by 10: b keeps
/// its count (20) though its position moved from 0 to 1, and a is new (1).
/// Arm 2 (probe F5): indices as ids — [x@0] → [y@0, x@1]: the element at id 0
/// keeps the count whatever its label (2), and the one at id 1 is new (1).
///
/// Mutation **M1a** reddens arm 1 (a reads 11, adopting b's position-0 entry;
/// b reads 10). Arm 2 is the same under M1a, because the key IS the position —
/// which is F5's point.
@MainActor
@Test func theKeyDecidesWhetherStateFollowsTheValueOrThePosition() {
    let values = ConditionalReads()
    render([["b"], ["a", "b"]]) { keys in
        Row {
            ForEach(keys, id: \.self) { key in ConditionalCounter(key, values, step: key == "b" ? 10 : 1) }
        }
    }
    #expect(values.values["b"] == 20, "b's count followed its id to position 1: \(values.values)")
    #expect(values.values["a"] == 1, "a is new (11 adopts b's position): \(values.values)")

    struct Indexed { let index: Int; let label: String }
    let positions = ConditionalReads()
    render([[Indexed(index: 0, label: "x")],
            [Indexed(index: 0, label: "y"), Indexed(index: 1, label: "x")]]) { rows in
        Row {
            ForEach(rows, id: \.index) { row in ConditionalCounter(row.label, positions) }
        }
    }
    #expect(positions.values["y"] == 2, "the id-0 element keeps the count, whatever it shows: \(positions.values)")
    #expect(positions.values["x"] == 1, "the id-1 element is new: \(positions.values)")
    #expect(positions.ids["y"] == member("0"), "\(String(describing: positions.ids["y"]))")
}

/// **1.5 — a `ForEach` removing a MIDDLE element keeps the others' state** (probe
/// F6). [a, b, c] → [a, c] → [a, b, c]: a and c keep counting (3 each), and b,
/// re-added, reads **1**.
///
/// b's position is taken by c, so `ID-R` departs b already; c moved and was
/// produced, so it keeps its state. Mutation **M1c** (the scope's `noteNamed`
/// call removed) leaves nothing noted at any position: b reads 2.
@MainActor
@Test func aForEachRemovingAMiddleElementKeepsTheOthersState() {
    let reads = ConditionalReads()
    renderItems([[Item("a"), Item("b"), Item("c")], [Item("a"), Item("c")],
                 [Item("a"), Item("b"), Item("c")]], reads)
    #expect(reads.values["a"] == 3, "\(reads.values)")
    #expect(reads.values["c"] == 3, "c moved to b's position and kept its own count: \(reads.values)")
    #expect(reads.values["b"] == 1, "the removed middle element starts fresh: \(reads.values)")
}

/// **1.6 — a `ForEach` is one slot, so the trailing sibling keeps its state**
/// (probe F9). `Row { ForEach(items); t }` and `HStack { ForEach(0..<n); t }`,
/// shrinking [a, b] → [a] and 2 → 1: t stays at `root/1` and reads 2 in both.
/// The elements step by 10, so an adopted count would read 11.
///
/// Mutation **M1d** (the `ForEach` consumes no slot: its elements named directly
/// under the parent, advancing the parent's cursor) moves t to `root/2` then
/// `root/1`: t reads 1 on the first frame at each, so it reads 1.
@MainActor
@Test func aForEachIsOneSlotSoTheTrailingSiblingKeepsItsState() {
    let legacy = ConditionalReads()
    render([["a", "b"], ["a"]]) { keys in
        Row {
            ForEach(keys, id: \.self) { key in ConditionalCounter(key, legacy, step: 10) }
            ConditionalCounter("t", legacy)
        }
    }
    #expect(legacy.ids["t"] == child(root, 1), "\(String(describing: legacy.ids["t"]))")
    #expect(legacy.values["t"] == 2, "the trailing element's own count: \(legacy.values)")

    let proposal = ConditionalReads()
    let table = StateTable()
    for n in [2, 1] {
        var tree = HStack(spacing: Pixels(0)) {
            ForEach(0..<n) { i in ProposalConditionalCounter("\(i)", proposal) }
            ProposalConditionalCounter("t", proposal)
        }
        Frame(contentSize: size, scaleFactor: 1, stateTable: table).render(&tree)
    }
    #expect(proposal.ids["t"] == child(root, 1), "\(String(describing: proposal.ids["t"]))")
    #expect(proposal.values["t"] == 2, "the trailing element's own count: \(proposal.values)")
}

/// **1.7 — an element moved to another `ForEach` starts fresh** (probe F10),
/// and the first `ForEach` has reset it when it returns there. `Row { ForEach
/// A; ForEach B }`: a in A, then in B, then in A again — it reads **1** on each
/// frame, its three homes each new (`root/0/"a"`, `root/1/"a"`, `root/0/"a"`).
///
/// Mutation **M1c** (the scope's `noteNamed` removed) leaves A's entry for a
/// retained: a reads 2 on the third frame. **M1b** reddens it too.
@MainActor
@Test func anElementMovedToAnotherForEachStartsFresh() {
    let reads = ConditionalReads()
    var seen: [Int] = []
    var paths: [GlobalElementID] = []
    let homes: [([String], [String])] = [(["a"], []), ([], ["a"]), (["a"], [])]
    render(homes) { home in
        Row {
            ForEach(home.0, id: \.self) { key in ConditionalCounter(key, reads) }
            ForEach(home.1, id: \.self) { key in ConditionalCounter(key, reads) }
        }
    } after: {
        seen.append(reads.values["a"] ?? -1)
        if let id = reads.ids["a"] { paths.append(id) }
    }
    #expect(seen == [1, 1, 1], "each home starts fresh: \(seen)")
    #expect(paths == [member("a"), child(named(child(root, 1), "a"), 0), member("a")], "\(paths)")
}

/// **1.8 — a duplicate id produces only the first element** (probe F7, `DD-B`
/// item 5). [x "first", x "second"]: one node under the `Row`, and only the
/// first element's content was evaluated.
///
/// Mutation **M1e** (the per-frame dedupe removed, both halves) produces both:
/// three nodes, and "second" recorded.
@MainActor
@Test func aForEachDuplicateIDProducesOnlyTheFirstElement() {
    let reads = ConditionalReads()
    let frame = Frame(contentSize: size, scaleFactor: 1)
    var tree = Row {
        ForEach([Item("x", label: "first"), Item("x", label: "second")]) { item in
            ConditionalCounter(item.label, reads)
        }
    }
    frame.render(&tree)
    #expect(reads.values["first"] == 1, "\(reads.values)")
    #expect(reads.values["second"] == nil, "the duplicate's content is never evaluated: \(reads.values)")
    #expect(frame.tree.nodeCount == 2, "the Row and one element: \(frame.tree.nodeCount)")
}

/// **1.9 — a `ForEach` element of TWO members resets both on its return**
/// (probe F8). Each element is `{ C(key-1); C(key-2) }` in one scope; [a, b],
/// [a], [a, b]: b-1 and b-2 read **1**, at `root/0/"b"/0` and `/1`.
///
/// Mutation **M1b** reddens this (both read 2).
@MainActor
@Test func aForEachElementOfTwoMembersResetsBothOnReturn() {
    let reads = ConditionalReads()
    render([["a", "b"], ["a"], ["a", "b"]]) { keys in
        Row {
            ForEach(keys, id: \.self) { key in
                ConditionalCounter("\(key)-1", reads)
                ConditionalCounter("\(key)-2", reads)
            }
        }
    }
    #expect(reads.ids["b-1"] == member("b", 0) && reads.ids["b-2"] == member("b", 1), "\(reads.ids)")
    #expect(reads.values["b-1"] == 1 && reads.values["b-2"] == 1, "both members start fresh: \(reads.values)")
    #expect(reads.values["a-1"] == 3 && reads.values["a-2"] == 3, "\(reads.values)")
}

// MARK: - The typed copy: 1.10

/// `ProposalConditionalCounter` that also records its prepainted bounds.
private struct PlacedCounter: ProposalElement {
    let label: String
    let reads: ConditionalReads
    let placed: PlacedBounds

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        var value = 0
        pass.withState(id, initial: 0) { $0 += 1; value = $0 }
        reads.values[label] = value
        reads.ids[label] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        placed.bounds[label] = bounds
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private final class PlacedBounds {
    var bounds: [String: Bounds<Pixels>] = [:]
}

/// **1.10 — a `ForEach` inside a proposal stack places every element and resets
/// its dropped tail.** `HStack(spacing: 0) { ForEach(0..<n) { P } }` goes through
/// the TYPED entry: at n = 3 the three leaves sit 10 apart and the frame holds
/// four nodes; n 3 → 1 → 3 resets elements 1 and 2 (1 each) and keeps 0 (3).
///
/// Mutation **M1f** (the typed entry's `noteLoop` removed) reddens this test
/// alone — elements 1 and 2 read 2; every other `ForEach` test goes through a
/// `Row`, whose untyped entry keeps its own call.
@MainActor
@Test func aForEachInsideAProposalStackPlacesEveryElementAndResetsItsDroppedTail() throws {
    let reads = ConditionalReads()
    let placed = PlacedBounds()
    let table = StateTable()
    var last: Frame?
    for n in [3, 1, 3] {
        var tree = HStack(spacing: Pixels(0)) {
            ForEach(0..<n) { i in PlacedCounter(label: "\(i)", reads: reads, placed: placed) }
        }
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        frame.render(&tree)
        last = frame
    }
    let xs = try (0..<3).map { try #require(placed.bounds["\($0)"], "leaf \($0) never prepainted").origin.x.value }
    #expect(xs[1] == xs[0] + 10 && xs[2] == xs[1] + 10, "each element placed 10 apart: \(xs)")
    #expect(last?.tree.nodeCount == 4, "the HStack and three leaves")
    #expect(reads.ids["2"] == member("2"), "\(String(describing: reads.ids["2"]))")
    #expect(reads.values["1"] == 1 && reads.values["2"] == 1, "the dropped tail starts fresh: \(reads.values)")
    #expect(reads.values["0"] == 3, "\(reads.values)")
}

// MARK: - What the loop rule leaves alone, and what it costs: 1.14, 1.15

/// **1.14 — a surviving `ForEach` element's `List` keeps its windowed rows'
/// state** (`TB-AH`, `DD-C` item 3). Each element holds a 20-pt `ScrollView {
/// List }` of 12 rows; row 4 is scrolled in (reads 3), the `ForEach` shrinks
/// [a, b] → [a] while a's row 4 is scrolled out for two generations, and row 4
/// comes back reading **4** — the loop reset b, and nothing under a.
///
/// Only the loop's DIRECT children are considered: the rows are the `List`'s
/// children, two levels down, and out of the window their entries are unmarked.
/// Mutation **M1j** (the loop rule resets every UNMARKED entry under the slot,
/// not only departed direct children) resets the out-of-window row: it reads 1.
@MainActor
@Test func aSurvivingForEachElementsListKeepsItsWindowedRowsState() throws {
    let reads = ConditionalReads()
    let rows = (0..<12).map { Item("row\($0)") }
    let table = StateTable()
    func tree(_ keys: [String]) -> some Element {
        Column {
            ForEach(keys, id: \.self) { key in
                Box {
                    ScrollView(.vertical, elementID: ElementID("scroller-\(key)")) {
                        List(rows, rowHeight: Pixels(20)) { row in
                            Box { ConditionalCounter("\(key)-\(row.id)", reads) }
                        }
                    }
                }.cssHeight(Pixels(20))
            }
        }
    }
    let scroller = GlobalElementID.child(of: child(named(loop, "a"), 0), at: 0, name: ElementID("scroller-a"))
    func renderFrame(_ keys: [String], offset: Double?) {
        if let offset {
            let current = table.peek(scroller, as: ScrollState.self) ?? ScrollState()
            table.write(scroller, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                              viewportExtent: current.viewportExtent))
        }
        var root = tree(keys)
        Frame(contentSize: Size(width: Pixels(100), height: Pixels(40)), scaleFactor: 1,
              stateTable: table).render(&root)
    }

    renderFrame(["a", "b"], offset: nil)        // cold: every row built
    renderFrame(["a", "b"], offset: 100)        // a's window [3, 8): row 4 in
    renderFrame(["a", "b"], offset: 100)
    try #require(reads.values["a-row4"] == 3, "set up: \(String(describing: reads.values["a-row4"]))")
    renderFrame(["a"], offset: 0)               // b dropped; a's row 4 out for two generations
    renderFrame(["a"], offset: 0)
    try #require(reads.values["b-row0"] != nil, "set up: b's rows were built")
    reads.values["a-row4"] = nil
    renderFrame(["a"], offset: 80)              // a's window [2, 7): row 4 back
    #expect(reads.values["a-row4"] == 4,
            "a surviving element's List row keeps TB-AH's retention: \(String(describing: reads.values["a-row4"]))")
}

/// **1.15 — a steady loop queues no reset.** A 1000-element `ForEach` and a
/// 1000-iteration `for` beside it, rendered three times unchanged: the
/// cumulative `subtreeResetScans` and `departedNameResets` and the last sweep's
/// `lastResetScanWork` read **0** — derived before the run: nothing shrank, so
/// no positional tail and no departed name exists.
///
/// Mutation **M1k** (the positional rule's `previous > extent` written
/// `previous >= extent`) queues a scan per loop on every steady frame.
@MainActor
@Test func aSteadyLoopQueuesNoReset() {
    let reads = ConditionalReads()
    let table = StateTable()
    render([0, 1, 2], table: table) { _ in
        Row {
            ForEach(0..<1000) { i in ConditionalCounter("e\(i)", reads) }
            for i in 0..<1000 { ConditionalCounter("f\(i)", reads) }
        }
    }
    #expect(reads.values["e999"] == 3 && reads.values["f999"] == 3, "every element laid out each frame")
    #expect(table.subtreeResetScans == 0, "scans: \(table.subtreeResetScans)")
    #expect(table.departedNameResets == 0, "name resets: \(table.departedNameResets)")
    #expect(table.lastResetScanWork == 0, "scan work: \(table.lastResetScanWork)")
}

// MARK: - Divergence 79 (`DD-L`): 1.16

/// **1.16 — divergence 79's pin: ids that collide in DESCRIPTION produce only
/// the first** (`DD-L`, pinned wrong on purpose). Ids `AnyHashable(1)` and
/// `AnyHashable("1")` differ in value and both describe as `"1"`: one node, the
/// first element's content. SwiftUI produces both (probe S6).
///
/// Mutation **M1l** (the dedupe's name half removed) produces both at one id —
/// three nodes and "string" recorded; 1.8 stays green on the value half.
@MainActor
@Test func aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst() {
    struct Keyed { let key: AnyHashable; let label: String }
    let reads = ConditionalReads()
    let frame = Frame(contentSize: size, scaleFactor: 1)
    var tree = Row {
        ForEach([Keyed(key: AnyHashable(1), label: "int"), Keyed(key: AnyHashable("1"), label: "string")],
                id: \.key) { keyed in ConditionalCounter(keyed.label, reads) }
    }
    frame.render(&tree)
    #expect(reads.values["int"] == 1, "\(reads.values)")
    #expect(reads.values["string"] == nil, "divergence 79: the description-colliding id is not produced: \(reads.values)")
    #expect(frame.tree.nodeCount == 2, "the Row and one element: \(frame.tree.nodeCount)")
}
