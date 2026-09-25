import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 3's typed builder-group entries, measured through a real `Frame`
// (ruling MC-H; verifier finding on lane 3).
//
// Lane 3 gave `ArrayGroup`, `OptionalGroup`, `Pair` and `Component` a second
// layout entry, `requestProposalGroupLayout` (`ProposalElementGroup.swift`,
// `ProposalNodeID.swift`), and every `for`, `if` and component inside a proposal
// container now goes through it rather than through the untyped
// `requestGroupLayout` those types already had. The doc says each copy mirrors
// its untyped entry line for line; only `Pair`'s was pinned. The verifier
// mutated the other three and the whole suite stayed green. Each test below is
// named for the line its copy must keep, and each reddens under that mutation
// (record §10, ruling MC-H's Mutations line).

@MainActor
private final class GroupEntryProbe {
    var bounds: [String: Bounds<Pixels>] = [:]
    var ids: [String: GlobalElementID] = [:]
    /// Whether prepaint saw the value's own layout-time write.
    var sawLayoutWrite: [String: Bool] = [:]
}

/// A 10×10 native leaf. Its `@State` starts at `start` and is incremented once
/// during layout; with `writesDuringLayout` it also sets a STORED flag during
/// layout, which prepaint reads back off `self`.
private struct EntryLeaf: ProposalElement {
    @State var value: Int
    var name: String
    var probe: GroupEntryProbe
    var writesDuringLayout: Bool
    var laidOut = false

    init(_ name: String, probe: GroupEntryProbe, start: Int = 0, writesDuringLayout: Bool = false) {
        _value = State(wrappedValue: start)
        self.name = name
        self.probe = probe
        self.writesDuringLayout = writesDuringLayout
    }

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        value += 1
        if writesDuringLayout { laidOut = true }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        probe.bounds[name] = bounds
        probe.ids[name] = id
        probe.sawLayoutWrite[name] = laidOut
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

private let frameSize = Size(width: Pixels(140), height: Pixels(90))

/// The root id `Frame.render` builds for an unnamed root element.
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func stateSlot(of id: GlobalElementID) -> GlobalElementID {
    GlobalElementID.child(of: id, at: 0, name: ElementID("$state0"))
}

// MARK: - ArrayGroup: every member's nodes reach the container

/// **A `for` loop inside an `HStack` places each iteration in its own slot, as
/// three separate statements do.**
///
/// The oracle is the same three leaves written as three statements, which go
/// through `Pair`'s typed entry (already pinned); the loop goes through
/// `ArrayGroup`'s. The oracle's x origins are required 10 apart first, so
/// "the loop matches the oracle" is a comparison that can fail (practices shape
/// 15). Ids are compared too: a loop's items number inside the loop's one slot
/// (plan task 8, `ID-B`; they shared the container's flat index space before).
///
/// Mutation (verifier's P3, recorded under MC-H): `ArrayGroup`'s typed entry
/// appending only the first group's nodes. Unmutated the loop's leaves sit at
/// three distinct x origins; mutated, the two unappended leaves are laid out as
/// orphans.
@MainActor
@Test func aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot() throws {
    let statements = GroupEntryProbe()
    do {
        var root = HStack(spacing: Pixels(0)) {
            EntryLeaf("0", probe: statements)
            EntryLeaf("1", probe: statements)
            EntryLeaf("2", probe: statements)
        }
        Frame(contentSize: frameSize, scaleFactor: 1).render(&root)
    }
    let loop = GroupEntryProbe()
    let frame = Frame(contentSize: frameSize, scaleFactor: 1)
    do {
        var root = HStack(spacing: Pixels(0)) {
            for index in 0..<3 { EntryLeaf("\(index)", probe: loop) }
        }
        frame.render(&root)
    }

    let oracle = try (0..<3).map { try #require(statements.bounds["\($0)"], "oracle leaf \($0) never prepainted") }
    try #require(oracle[1].origin.x.value == oracle[0].origin.x.value + 10
                 && oracle[2].origin.x.value == oracle[1].origin.x.value + 10,
                 "the oracle's leaves must sit 10 apart, or the comparison cannot fail: \(oracle)")

    let placed = try (0..<3).map { try #require(loop.bounds["\($0)"], "loop leaf \($0) never prepainted") }
    print("MC-H ArrayGroup typed entry: loop x \(placed.map(\.origin.x.value)), "
          + "statements x \(oracle.map(\.origin.x.value)), nodeCount \(frame.tree.nodeCount)")
    #expect(placed == oracle, "loop \(placed) vs statements \(oracle)")
    // Plan task 8, `ID-B` (T row): the loop takes ONE slot, `root/0`, and its
    // iterations number inside it — `root/0/i`, not `root/i` as before.
    let loopSlot = GlobalElementID.child(of: rootID, at: 0, name: nil)
    for index in 0..<3 {
        #expect(loop.ids["\(index)"] == GlobalElementID.child(of: loopSlot, at: index, name: nil),
                "loop leaf \(index)'s id: \(String(describing: loop.ids["\(index)"]))")
    }
    // HStack plus three leaves.
    #expect(frame.tree.nodeCount == 4)
}

// MARK: - OptionalGroup: the member's layout-time writes survive into prepaint

/// **An element inside an `if` inside an `HStack` sees its own layout-time write
/// in prepaint, as the same element does outside the `if`.**
///
/// A group's later phases run on the value `requestGroupLayout` mutated, so
/// `OptionalGroup` must store its member back after laying it out. Two
/// controls: the element outside any `if` reads `true` (the write-back the `if`
/// must match), and the element that makes no layout write reads `false` (the
/// instrument can read `false`).
///
/// Mutation (verifier's P2, recorded under MC-H): `OptionalGroup`'s typed entry
/// losing `wrapped = inner`, which reads the `if` arm `false`.
@MainActor
@Test func anElementInsideAnIfInsideAProposalContainerKeepsItsLayoutTimeWrites() throws {
    func render<Content: ProposalElementGroup>(@ElementBuilder _ body: () -> Content) {
        var root = HStack(spacing: Pixels(0), content: body)
        Frame(contentSize: frameSize, scaleFactor: 1).render(&root)
    }
    let probe = GroupEntryProbe()
    let flag = true
    render { EntryLeaf("plain", probe: probe, writesDuringLayout: true) }
    render { EntryLeaf("no write", probe: probe) }
    render { if flag { EntryLeaf("if", probe: probe, writesDuringLayout: true) } }

    print("MC-H OptionalGroup typed entry: \(probe.sawLayoutWrite)")
    try #require(probe.sawLayoutWrite["plain"] == true,
                 "outside an if the write must be visible: \(String(describing: probe.sawLayoutWrite["plain"]))")
    try #require(probe.sawLayoutWrite["no write"] == false,
                 "the instrument must be able to read false: \(String(describing: probe.sawLayoutWrite["no write"]))")
    #expect(probe.sawLayoutWrite["if"] == true,
            "inside an if: \(String(describing: probe.sawLayoutWrite["if"]))")
}

// MARK: - Component: content starts at index 0 under the component's own id

/// A proposal `Component` over one stateful leaf, whose `@State` starts at `start`.
private struct EntryComponent: Component, ProposalElementGroup {
    var name: String
    var start: Int
    var probe: GroupEntryProbe

    var content: some ProposalElementGroup {
        EntryLeaf(name, probe: probe, start: start)
    }
}

/// **A proposal `Component`'s content is `.positional(0)` under the component's
/// own id, and its `@State` lives there — distinct from a sibling component's.**
///
/// Two components in one `HStack`, their leaves' `@State` starting at 7 and 20
/// and each incremented once during layout. Each leaf's `$state0` slot, at the
/// id the design says it has, must read 8 and 21. The ids are required
/// distinct first, so two components collapsing onto one slot cannot read
/// correctly.
///
/// Mutation (verifier's P4, recorded under MC-H): `Component`'s typed default
/// starting its content at `innerCursor = 1`, which moves both leaves to
/// `.positional(1)` and leaves the expected slots empty.
@MainActor
@Test func aProposalComponentsContentIsPositionZeroUnderItsOwnID() throws {
    let probe = GroupEntryProbe()
    let frame = Frame(contentSize: frameSize, scaleFactor: 1)
    var root = HStack(spacing: Pixels(0)) {
        EntryComponent(name: "first", start: 7, probe: probe)
        EntryComponent(name: "second", start: 20, probe: probe)
    }
    frame.render(&root)

    let firstComponent = GlobalElementID.child(of: rootID, at: 0, name: nil)
    let secondComponent = GlobalElementID.child(of: rootID, at: 1, name: nil)
    let expectedFirst = GlobalElementID.child(of: firstComponent, at: 0, name: nil)
    let expectedSecond = GlobalElementID.child(of: secondComponent, at: 0, name: nil)
    try #require(expectedFirst != expectedSecond, "the two expected ids must differ")

    let table = frame.stateTable
    print("MC-H Component typed default: first \(String(describing: probe.ids["first"])), "
          + "second \(String(describing: probe.ids["second"])), "
          + "slots \(String(describing: table.peek(stateSlot(of: expectedFirst), as: Int.self))) "
          + "\(String(describing: table.peek(stateSlot(of: expectedSecond), as: Int.self)))")
    #expect(probe.ids["first"] == expectedFirst, "first leaf: \(String(describing: probe.ids["first"]))")
    #expect(probe.ids["second"] == expectedSecond, "second leaf: \(String(describing: probe.ids["second"]))")
    #expect(table.peek(stateSlot(of: expectedFirst), as: Int.self) == 8)
    #expect(table.peek(stateSlot(of: expectedSecond), as: Int.self) == 21)
    #expect(table.isLive(stateSlot(of: expectedFirst)))
    #expect(table.isLive(stateSlot(of: expectedSecond)))
}
