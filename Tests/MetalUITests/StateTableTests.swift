import Testing
import MetalUICore
@testable import MetalUI

/// Spec §4.3 — the side table keyed by `GlobalElementID`, marked on access and
/// swept after each frame. That dictionary plus mark-sweep is the whole of this
/// framework's reconciliation.

private func id(_ names: String...) -> GlobalElementID {
    GlobalElementID(names.map(ElementID.init))
}

@MainActor
@Test func stateSurvivesARebuildWhenTheElementIsProducedAgain() {
    let table = StateTable()
    table.withState(id("a"), initial: 0) { $0 = 7 }
    table.sweep()

    // Produced again on the next frame: the value is still there, not re-seeded.
    var seen = -1
    table.withState(id("a"), initial: 0) { seen = $0 }
    #expect(seen == 7)
}

@MainActor
@Test func stateIsSweptWhenTheElementStopsBeingProduced() {
    let table = StateTable()
    table.withState(id("a"), initial: 0) { $0 = 7 }
    table.withState(id("b"), initial: 0) { $0 = 9 }
    table.sweep()

    // Next frame produces only `a`. `b` is gone after the sweep that follows.
    table.withState(id("a"), initial: 0) { _ in }
    table.sweep()

    #expect(table.peek(id("a"), as: Int.self) == 7)
    #expect(table.peek(id("b"), as: Int.self) == nil)
    // Absolute, not relative: comparing two counts that both drop to zero would
    // pass when the table sweeps everything.
    #expect(table.count == 1)
}

/// Identity is the **path**, not the local id.
///
/// This is the test that separates a working table from one that passes anyway:
/// a naive `[ElementID: State]` satisfies both tests above and fails this one.
/// It is the same failure shape as `AnyElementBox` being a class — two things
/// that should be distinct silently sharing one slot — which is why §4.3
/// specifies a path rather than a name.
@MainActor
@Test func sameLocalIDUnderDifferentParentsDoesNotShareState() {
    let table = StateTable()
    table.withState(id("left", "item"), initial: 0) { $0 = 1 }
    table.withState(id("right", "item"), initial: 0) { $0 = 2 }

    #expect(table.peek(id("left", "item"), as: Int.self) == 1)
    #expect(table.peek(id("right", "item"), as: Int.self) == 2)
    #expect(table.count == 2)
}

/// An anonymous element gets scratch state, and its identified children get no
/// identity at all.
///
/// `child(of:_:)` returns nil when either end is anonymous, so identity does not
/// resume below an unidentified element. The alternative — letting an anonymous
/// element forward its parent's path — is unsafe for a mechanical reason:
/// `Element`'s phases receive exactly one `GlobalElementID?`, so an element that
/// forwarded its parent's path to its children would also be *holding* that
/// path, and `withState` on it would read and write the parent's own entry.
@MainActor
@Test func anIdentifiedChildOfAnAnonymousParentHasNoIdentity() {
    let anonymous: GlobalElementID? = GlobalElementID.child(of: .root, nil)
    #expect(anonymous == nil)

    let childOfAnonymous = GlobalElementID.child(of: anonymous, ElementID("item"))
    #expect(childOfAnonymous == nil)

    // And an anonymous element's state is scratch: written, then discarded.
    let table = StateTable()
    table.withState(childOfAnonymous, initial: 0) { $0 = 42 }
    #expect(table.count == 0)
}

/// Two anonymous siblings' same-named children **cannot** collide, because
/// neither child has an identity to collide on.
///
/// Recorded because the natural worry — "two anonymous siblings would give their
/// same-named children the same path" — is true of the *rejected* design, not
/// this one. Here both children get `nil`, so nothing is shared; the cost is
/// that neither can hold state at all. Fixing that needs a positional component
/// folded into the key, which is a change to §4.3 and is not made here.
@MainActor
@Test func twoAnonymousSiblingsChildrenCannotCollideBecauseNeitherHasIdentity() {
    let leftAnon = GlobalElementID.child(of: .root, nil)
    let rightAnon = GlobalElementID.child(of: .root, nil)
    let a = GlobalElementID.child(of: leftAnon, ElementID("item"))
    let b = GlobalElementID.child(of: rightAnon, ElementID("item"))

    #expect(a == nil)
    #expect(b == nil)

    let table = StateTable()
    table.withState(a, initial: 0) { $0 = 1 }
    table.withState(b, initial: 0) { $0 = 2 }
    #expect(table.count == 0)
}

/// The sweep runs **after** the frame, not before.
///
/// Sweeping first would discard every entry the previous frame established,
/// which is the whole point of the table.
@MainActor
@Test func sweepingBeforeTheFrameWouldDiscardEverythingItExistsToKeep() {
    let table = StateTable()
    table.withState(id("a"), initial: 0) { $0 = 7 }

    // A second sweep with no intervening access removes it — which is exactly
    // what a sweep-first ordering would do to every entry, every frame.
    table.sweep()
    table.sweep()
    #expect(table.peek(id("a"), as: Int.self) == nil)
}
