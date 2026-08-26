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

// MARK: - The table reached through a Frame

/// An element that stamps a per-frame counter into its cross-frame state.
private struct CountingElement: Element {
    let elementID: ElementID?
    init(_ name: String?) { elementID = name.map(ElementID.init) }

    func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        pass.withState(id, initial: 0) { $0 += 1 }
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(10))),
                          height: .length(.pixels(Pixels(10))))
        return (pass.requestNode(style: style, children: []), 0)
    }

    func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
               layout: inout Int, prepaint: inout Int, pass: inout PaintPass) {}
}

/// State survives across frames **because the window owns the table, not the
/// frame**.
///
/// A `Frame` that constructed its own `StateTable` would hand every element
/// fresh state every frame — and every other test in this file would still pass,
/// because they exercise `StateTable` directly and never go through a `Frame`.
/// This is the only test that can see the difference.
@MainActor
@Test func aSharedTableCarriesStateAcrossFramesWhileAPerFrameTableWouldNot() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    for _ in 0..<3 {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var element = CountingElement("counter")
        frame.render(&element)
    }

    // Three frames, one element, one entry: the count accumulated rather than
    // resetting, and the sweep kept the entry it was still marking.
    #expect(table.peek(GlobalElementID([ElementID("counter")]), as: Int.self) == 3)
    #expect(table.count == 1)
}

/// An element that stops being produced loses its state on the next sweep, and
/// this is the mechanism behind §14's "no exit transitions".
///
/// **This is also the only test that pins the sweep's ORDERING.** Moving
/// `stateTable.sweep()` in `Frame.render` from after the phases to before them
/// reddens exactly this test and nothing else. A previous
/// `sweepingBeforeTheFrameWouldDiscardEverythingItExistsToKeep` claimed that
/// job and did not do it: it reddened only under "never sweep", which
/// `stateIsSweptWhenTheElementStopsBeingProduced` already covers, and stayed
/// green under the real ordering mutation. It was deleted rather than renamed —
/// a test that duplicates another while claiming unique coverage is worse than
/// no test, because the name is what people trust.
@MainActor
@Test func anElementThatStopsBeingProducedIsSweptByTheNextFrame() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    let first = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var a = CountingElement("a")
    first.render(&a)
    #expect(table.count == 1)

    // The next frame produces a different element. `a` is not marked, so the
    // sweep at the end of that frame removes it.
    let second = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var b = CountingElement("b")
    second.render(&b)

    #expect(table.peek(GlobalElementID([ElementID("a")]), as: Int.self) == nil)
    #expect(table.peek(GlobalElementID([ElementID("b")]), as: Int.self) == 1)
    #expect(table.count == 1)
}
