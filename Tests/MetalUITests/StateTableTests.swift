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

/// **Inverted by the tombstones milestone's Task 1 — this asserted the OLD
/// contract.** It used to be named `stateIsSweptWhenTheElementStopsBeingProduced`
/// and asserted `table.peek(id("b")) == nil` and `table.count == 1`: before
/// this task, `sweep()` deleted every entry `marked` did not contain, so `b`'s
/// entry vanished, value and all, the moment it stopped being produced.
///
/// **That is exactly the behaviour spec §3 (design spec
/// `2026-09-01-tombstones-and-ax-design.md`) requires this milestone to stop
/// doing** — an AX client holding `b`'s `GlobalElementID` needs it to keep
/// answering, as an invalid handle, rather than the table forgetting it ever
/// existed. So this is not a regression to chase; it is the change working.
/// `b`'s entry now survives as a tombstone: its value is still `9` and
/// `isLive` reports `false` because no frame has marked it since. `table.count`
/// is `2`, not `1`, because the tombstone is still an entry.
@MainActor
@Test func anElementThatStopsBeingProducedIsRetainedAsATombstone() {
    let table = StateTable()
    table.withState(id("a"), initial: 0) { $0 = 7 }
    table.withState(id("b"), initial: 0) { $0 = 9 }
    table.sweep()

    // Next frame produces only `a`. `b` is no longer produced, so the sweep
    // that follows tombstones it rather than deleting it.
    table.withState(id("a"), initial: 0) { _ in }
    table.sweep()

    #expect(table.peek(id("a"), as: Int.self) == 7)
    #expect(table.peek(id("b"), as: Int.self) == 9, "a tombstone keeps its value")
    #expect(!table.isLive(id("b")), "but reports itself not live — no frame has marked it since")
    #expect(table.isLive(id("a")))
    // Both entries are retained now: the live one and the tombstone.
    #expect(table.count == 2)
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
///
/// **A native 10×10 leaf since stage 6a** (record §38, disposition R): its
/// tests are about the state table and identity, not the leaf's layout, so a
/// test that puts it under a legacy container (`IdentityTests`' `Row`s) runs
/// under the proposal authority.
struct CountingElement: Element {
    let elementID: ElementID?
    init(_ name: String?) { elementID = name.map(ElementID.init) }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Int) {
        pass.withState(id, initial: 0) { $0 += 1 }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, 0)
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

/// **Inverted by the tombstones milestone's Task 1, and renamed —
/// `anElementThatStopsBeingProducedIsSweptByTheNextFrame` said what no longer
/// happens.** An element that stops being produced no longer loses its state
/// on the next sweep; it loses only its liveness, which is the mechanism
/// behind §9's AX handles reading as invalid rather than crashing, and it is
/// what makes exit transitions buildable in a later milestone instead of
/// impossible in this one.
///
/// **This is still the DEDICATED pin for the sweep's ORDERING — but no longer
/// the only test that reddens under the mutation, and that "only" was a
/// review finding, not a re-derivation of mine.** Moving `stateTable.sweep()`
/// in `Frame.render` from after the phases to before them used to redden only
/// this test, via `peek`/`count`, because under the old delete-on-sweep
/// semantics the wrong ordering left `a`'s entry alive with the wrong value.
/// **Under tombstones `peek` and `count` no longer discriminate the mutation
/// at all**: nothing is ever deleted, so both orderings land on `count == 2`
/// and `peek(a) == 1` regardless of when `sweep()` runs. Re-derived and
/// checked against the mutation (not assumed): the ordering only changes
/// whether `sweep()`, when it runs at the *start* of frame 2, still sees `a`'s
/// mark from frame 1's `marked` set (which is cleared only inside `sweep()`
/// itself) — so under the wrong ordering `a` reads `isLive == true` one frame
/// longer than it should. `!isLive(id("a"))` below is therefore the specific
/// assertion that reddens under the mutation — not `isLive(id("b"))`, whose
/// entry is created live directly by `withState` regardless of when `sweep()`
/// runs relative to `requestLayout`, so it agrees under both orderings — and
/// it is why this test could not simply keep its old shape with `!= nil`
/// swapped in for `== nil`.
///
/// **What I did not check, and a review did: this task's own inversions gave
/// two `IdentityTests` cases the same sensitivity, incidentally.**
/// `flippingAnEitherBranchResetsTheBranchesState` and
/// `anElementAfterAVanishingIfAdoptsTheVanishedElementsState`
/// (`IdentityTests.swift`) also added an `isLive` assertion on an abandoned
/// branch's entry when Task 1 inverted them, and that assertion happens to be
/// sensitive to the same one-frame liveness lag this test exists to pin —
/// moving `sweep()` reddens all three, not one. Neither of the two is a
/// second ordering guard: what each test is actually *for* (branch state
/// resets rather than continues; a vacated slot is not "reserved") has
/// nothing to do with sweep ordering, so do not preserve their `isLive` lines
/// on the theory that they guard it — this test is still the one written for
/// that purpose, and the only one whose comment claims it.
@MainActor
@Test func anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    let first = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var a = CountingElement("a")
    first.render(&a)
    #expect(table.count == 1)
    #expect(table.isLive(id("a")))

    // The next frame produces a different element. `a` is not marked, so the
    // sweep at the end of that frame tombstones it — the value stays, the
    // liveness does not.
    let second = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var b = CountingElement("b")
    second.render(&b)

    #expect(table.peek(id("a"), as: Int.self) == 1, "the tombstone keeps its value")
    #expect(!table.isLive(id("a")), "but is no longer live — the load-bearing assertion")
    #expect(table.peek(id("b"), as: Int.self) == 1)
    #expect(table.isLive(id("b")))
    #expect(table.count == 2, "both the live entry and the tombstone are retained")
}
