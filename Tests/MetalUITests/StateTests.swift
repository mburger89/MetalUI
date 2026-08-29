import Testing
import MetalUICore
@testable import MetalUI

/// The storage contract for `@State`, ahead of Task 2's reflection-driven
/// seeding — nothing here calls `bind` except by hand.

@MainActor
@Test func anUnboundStateReturnsItsInitialValueAndDiscardsWrites() throws {
    // An unbound wrapper must not trap — an element constructed outside a
    // frame is legal, and a trap there would make `List(data) { Row($0) }`
    // crash at the point the closure is *built* rather than run.
    let s = State(wrappedValue: 7)
    #expect(s.wrappedValue == 7)
    s.wrappedValue = 9
    #expect(s.wrappedValue == 7, "an unbound write has nowhere to go")
}

@MainActor
@Test func aBoundStateReadsAndWritesTheTableUnderItsOwnSlotID() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let s = State(wrappedValue: 0)
    s.bind(to: table, id: owner, slot: 0)

    s.wrappedValue = 5
    #expect(s.wrappedValue == 5)

    let slotID = GlobalElementID.child(of: owner, at: 0,
                                       name: ElementID("$state0"))
    #expect(table.peek(slotID, as: Int.self) == 5)
}

/// Two slots on one element must not share an entry. The ordinal lives in the
/// NAME, not in `at:` — a name replaces a position rather than joining it
/// (`ElementID.swift:79`), so `at:` is ignored whenever a name is supplied.
@MainActor
@Test func twoSlotsOnOneElementGetDistinctEntries() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let a = State(wrappedValue: 1), b = State(wrappedValue: 2)
    a.bind(to: table, id: owner, slot: 0)
    b.bind(to: table, id: owner, slot: 1)

    a.wrappedValue = 10
    b.wrappedValue = 20
    #expect(a.wrappedValue == 10)
    #expect(b.wrappedValue == 20)
}

/// A slot id can never collide with a positional child's, because positional
/// children carry no name.
@MainActor
@Test func aSlotIDCannotCollideWithAPositionalChild() throws {
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let slot0 = GlobalElementID.child(of: owner, at: 0, name: ElementID("$state0"))
    let child0 = GlobalElementID.child(of: owner, at: 0, name: nil)
    #expect(slot0 != child0)
}
