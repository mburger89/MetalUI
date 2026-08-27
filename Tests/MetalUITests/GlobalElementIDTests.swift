import Testing
@testable import MetalUI

@Test func aRootIdHasNoParent() {
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(root.parent == nil)
    #expect(root.component == .positional(0))
}

@Test func aNameReplacesThePositionRatherThanJoiningIt() {
    let named = GlobalElementID.child(of: nil, at: 3, name: ElementID("a"))
    #expect(named.component == .named(ElementID("a")))
}

/// Structural equality, not reference identity. Two paths built separately —
/// as two frames do — are `==` and never `===`.
@Test func twoSeparatelyBuiltIdenticalPathsAreEqualButNotIdentical() {
    let a = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                  at: 1, name: nil)
    let b = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                  at: 1, name: nil)
    #expect(a == b)
    #expect(a !== b)
    #expect(a.hashValue == b.hashValue)
}

/// `==` respects the ancestor, independent of hash quality. Two paths
/// differing only in an ancestor are `!=`, and a `Set` keeps them as two
/// entries — but **this does not exercise `cachedHash` at all**: `==` walks
/// the full chain regardless of what the hash says, and `Set`/`Dictionary`
/// fall back to `==` on any hash collision, so this test passes under any
/// hash whatsoever, including one that ignores the parent entirely. The hash
/// itself is guarded separately, by
/// `theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor` below.
@Test func pathsDifferingOnlyInAnAncestorAreNotEqual() {
    let left = GlobalElementID.child(of: nil, at: 0, name: nil)
    let right = GlobalElementID.child(of: nil, at: 1, name: nil)
    let underLeft = GlobalElementID.child(of: left, at: 0, name: ElementID("item"))
    let underRight = GlobalElementID.child(of: right, at: 0, name: ElementID("item"))

    #expect(underLeft != underRight)

    var set: Set<GlobalElementID> = []
    set.insert(underLeft)
    set.insert(underRight)
    #expect(set.count == 2)
}

/// **Not the most dangerous line in this milestone — this comment said it was,
/// and ruling SI-E retired the claim by measurement.** Omitting the parent from
/// `cachedHash` does *not* make two unrelated elements share state on its own:
/// `==` uses the hash as a fast **reject** and falls through to a chain walk,
/// and `Set`/`Dictionary` resolve collisions through `==` rather than through
/// distribution. `Hashable` permits collisions. A degraded hash alone is a
/// **performance** defect — a sharp one after this milestone, because once every
/// node is identified most components are `.positional(k)` and every node at the
/// same index in the tree hashes into one bucket, which takes `StateTable`
/// quadratic per frame.
///
/// **The danger is the combination**, and the load-bearing line is `==`'s chain
/// walk, not this hash. `ElementID.swift` carries the whole statement at `==`,
/// which is where no test can reach it.
///
/// So what this test pins is the hash **alone**, and it is the only thing that
/// does. `pathsDifferingOnlyInAnAncestorAreNotEqual` cannot see the omission —
/// `==` walks the chain, so it returns the right answer under any hash at all.
/// Measured, `--no-parallel` — edit: delete
/// `hasher.combine(parent?.cachedHash ?? 0)` from `GlobalElementID.init` — that
/// test stays green and this one reddens, alone, out of **360**.
///
/// **The 348 this comment used to claim was never a measurement of the suite it
/// was written against.** Counting `@Test` across `Tests/`: **348** at
/// `97c0277`, **349** at `0effc4c` — the commit that wrote the sentence — and
/// 358 at the commit before this one. The twin of this error was caught and
/// fixed in `ElementID.swift` during Task 1 and missed here; ruling SI-H is the
/// general form. Re-measured rather than re-derived.
@Test func theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor() {
    let left = GlobalElementID.child(of: nil, at: 0, name: nil)
    let right = GlobalElementID.child(of: nil, at: 1, name: nil)
    let underLeft = GlobalElementID.child(of: left, at: 0, name: ElementID("item"))
    let underRight = GlobalElementID.child(of: right, at: 0, name: ElementID("item"))
    #expect(underLeft.hashValue != underRight.hashValue)
}

/// Equality must walk the chain. A hash-equality shortcut turns a collision
/// into a wrong answer rather than a slow lookup.
@Test func differentDepthsWithTheSameTailAreNotEqual() {
    let shallow = GlobalElementID.child(of: nil, at: 0, name: nil)
    let deep = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil),
                                     at: 0, name: nil)
    #expect(shallow != deep)
}

/// A named component and a positional one never coincide, whatever the index.
@Test func aNamedComponentNeverEqualsAPositionalOne() {
    let named = GlobalElementID.child(of: nil, at: 0, name: ElementID("0"))
    let positional = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(named != positional)
}
