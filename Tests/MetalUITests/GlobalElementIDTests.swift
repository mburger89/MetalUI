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

/// **The most dangerous line in this milestone.** If the cached hash omits the
/// parent, two paths differing only in an ancestor land in the same bucket and
/// compare by a hash that cannot tell them apart — two unrelated elements
/// silently share state.
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
