import Testing
import MetalUICore
@testable import MetalUI

/// Spec §4.3 — the side table keyed by `GlobalElementID`, marked on access and
/// swept after each frame. That dictionary plus mark-sweep is the whole of this
/// framework's reconciliation.

/// Builds a path from a sequence of local names, root to leaf — the
/// linked-list equivalent of the old struct's `GlobalElementID([ElementID]...)`
/// array literal. Every component here is `.named`; `at: 0` is inert because
/// a name always wins over a position (`PathComponent`'s doc comment).
private func id(_ names: String...) -> GlobalElementID {
    var current: GlobalElementID?
    for name in names {
        current = GlobalElementID.child(of: current, at: 0, name: ElementID(name))
    }
    return current!
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

/// **Formerly `anIdentifiedChildOfAnAnonymousParentHasNoIdentity`.** That test
/// asserted `GlobalElementID.child(of:_:)` returned `nil` when either end was
/// anonymous — the old struct's `(GlobalElementID?, ElementID?) ->
/// GlobalElementID?`. Structural identity's `child(of:at:name:)` has no
/// `Optional` in that return position (design spec §3.3): every element gets
/// an identity, named or positional, so that assertion is not weakened, it is
/// uncompilable — there is no longer a `nil` for it to return. Rewritten to
/// assert what replaced it: the constructor never returns `nil`, and a name
/// given at construction is what the resulting id carries.
///
/// What this test used to *guard* — that an unidentified container's
/// identified descendants get no identity — is a behaviour, not a signature,
/// and it was still live when this rewrite was made, through the real
/// production path (a container calling `ElementGroup`'s conformances) rather
/// than the type's static method. **That behaviour has since been reversed**,
/// which is what this milestone existed to do: the test named it is now
/// `anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition` in
/// `ElementLayoutTests.swift`, and it asserts the unnamed container contributes
/// a `.positional` component instead of stopping the path. So the sentence above
/// describes what this test used to guard, not a rule anything still holds.
@MainActor
@Test func childOfAnUnnamedParentStillHasAnIdentity() {
    let unnamed = GlobalElementID.child(of: nil, at: 0, name: nil)
    let namedChild = GlobalElementID.child(of: unnamed, at: 0, name: ElementID("item"))

    #expect(namedChild.parent == unnamed)
    #expect(namedChild.component == .named(ElementID("item")))

    // Where the old rule discarded this element's state as scratch
    // (`table.count == 0`), it now holds a real entry.
    let table = StateTable()
    table.withState(namedChild, initial: 0) { $0 = 42 }
    #expect(table.count == 1)
}

/// **Formerly `twoAnonymousSiblingsChildrenCannotCollideBecauseNeitherHasIdentity`.**
/// That test built two anonymous siblings with `child(of: .root, nil)` and
/// asserted both their named children came back `nil` — again the old
/// struct's optional-returning signature, gone along with `.root`. Rewritten
/// to assert what replaced it: siblings built under **distinct** parents
/// (here, distinct positional indices — the shape a real cursor produces)
/// never collide, named or not.
///
/// The behavioural question the old test's name asked — do two anonymous
/// siblings' identified children collide — has the same answer it always
/// had, "no." Unlike the previous rewrite, this one has **no** surviving
/// witness through a real container:
/// `anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition`
/// in `ElementLayoutTests.swift` builds exactly one unnamed container, so it
/// cannot see a sibling pair at all. The sibling case here is
/// correct-by-construction instead — two ids built with different `at:`
/// indices differ in their `.positional` component (or, once named, their
/// parent), so `==`'s chain walk cannot equate them — and is exercised
/// directly by `pathsDifferingOnlyInAnAncestorAreNotEqual` in
/// `GlobalElementIDTests.swift`, which this test's construction mirrors.
/// What changed since the old rule is that "no" now means "each gets its own
/// identity and its own state," not "neither gets an identity at all" —
/// visible below as `table.count == 2`, not `0`.
@MainActor
@Test func childrenOfDistinctUnnamedParentsDoNotCollide() {
    let left = GlobalElementID.child(of: nil, at: 0, name: nil)
    let right = GlobalElementID.child(of: nil, at: 1, name: nil)
    let a = GlobalElementID.child(of: left, at: 0, name: ElementID("item"))
    let b = GlobalElementID.child(of: right, at: 0, name: ElementID("item"))

    #expect(a != b)

    let table = StateTable()
    table.withState(a, initial: 0) { $0 = 1 }
    table.withState(b, initial: 0) { $0 = 2 }
    #expect(table.count == 2)
}

// MARK: - The table reached through a Frame

/// An element that stamps a per-frame counter into its cross-frame state.
///
/// `internal` rather than `private` so `IdentityTests.swift` can drive the same
/// element: structural identity's tests differ from these only in whether the
/// element is named, and two copies of this probe would be two things to keep
/// in step.
struct CountingElement: Element {
    let elementID: ElementID?
    init(_ name: String?) { elementID = name.map(ElementID.init) }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        pass.withState(id, initial: 0) { $0 += 1 }
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(10))),
                          height: .length(.pixels(Pixels(10))))
        return (pass.requestNode(style: style, children: []), 0)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout Int, pass: inout PrepaintPass) -> Int { 0 }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
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
    #expect(table.peek(id("counter"), as: Int.self) == 3)
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

    #expect(table.peek(id("a"), as: Int.self) == nil)
    #expect(table.peek(id("b"), as: Int.self) == 1)
    #expect(table.count == 1)
}
