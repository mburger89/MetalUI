import Testing
@testable import MetalUI

// G33 (c), ruling II-A. Each test builds its own `IdentityInterner`, so the process-wide table other tests fill cannot move a count.

@MainActor private func path(_ interner: IdentityInterner, _ components: [PathComponent]) -> GlobalElementID {
    var id: GlobalElementID?
    for c in components { id = interner.intern(component: c, parent: id) }
    return id!
}

/// The same path asked for twice is one object (the point of the interner); a different name, position or ancestor is another.
@Test @MainActor func theSamePathInternsToOneInstanceAndDifferentPathsDoNot() {
    let interner = IdentityInterner()
    let a = path(interner, [.positional(0), .named(ElementID("x")), .positional(2)])
    interner.advance()
    let b = path(interner, [.positional(0), .named(ElementID("x")), .positional(2)])
    #expect(a === b)
    #expect(a !== path(interner, [.positional(0), .named(ElementID("y")), .positional(2)]))
    #expect(a !== path(interner, [.positional(0), .named(ElementID("x")), .positional(3)]))
    #expect(a !== path(interner, [.positional(1), .named(ElementID("x")), .positional(2)]), "same tail, different ancestor")
    #expect(a.parent === b.parent)
}

/// Interning changes no equality: an interned id equals its separately built twin, and never the other way round.
@Test @MainActor func anInternedIdEqualsItsSeparatelyBuiltTwin() {
    let interner = IdentityInterner()
    let interned = path(interner, [.positional(0), .positional(1)])
    let built = GlobalElementID(component: .positional(1), parent: GlobalElementID(component: .positional(0), parent: nil))
    #expect(interned == built)
    #expect(interned !== built)
    #expect(interned.hashValue == built.hashValue)
}

/// Ten thousand ids a frame, none repeated, for two hundred frames: the table is swept, so it stays a few frames wide, not two million.
@Test @MainActor func aChurningTreeDoesNotGrowTheTableWithoutBound() {
    let interner = IdentityInterner()
    let root = path(interner, [.positional(0)])
    let perFrame = 10_000
    for frame in 0..<200 {
        interner.advance()
        for i in 0..<perFrame { _ = interner.intern(component: .positional(frame * perFrame + i), parent: root) }
    }
    #expect(interner.count <= 8 * perFrame, "table holds \(interner.count) ids after \(200 * perFrame) were minted")
}

/// An id something else still holds is never evicted, so the instance in a table's key and the instance interned later stay one object;
/// an unheld chain goes in a single sweep, children before parents.
@Test @MainActor func aReferencedIdSurvivesTheSweepAndAnUnreferencedChainDoesNot() {
    let interner = IdentityInterner()
    var held: [GlobalElementID: Int] = [:]
    held[path(interner, [.positional(0), .named(ElementID("held"))])] = 1
    var chain: [PathComponent] = [.positional(9)]
    for i in 0..<30 { chain.append(.positional(i)) }
    _ = path(interner, chain)
    for _ in 0..<200 { interner.advance() }
    let key = held.keys.first!
    #expect(path(interner, [.positional(0), .named(ElementID("held"))]) === key)
    #expect(interner.count == 2, "the held id and its parent remain, the unheld 31-deep chain is gone: \(interner.count)")
}
