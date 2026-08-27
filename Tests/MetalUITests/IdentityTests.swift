import Testing
import MetalUICore
@testable import MetalUI

// Structural identity (design spec `2026-08-27-structural-identity-design.md`).
//
// **No golden and no browser oracle can reach any of this.** The milestone
// changes an identity key and touches no layout, so every guard in this file is
// hand-written and each one exists because a specific mutation would otherwise
// leave the suite green. The mutations are named at the tests they redden.
//
// `CountingElement` comes from `StateTableTests.swift`: it stamps `+= 1` into
// its cross-frame state every `requestLayout`, so a state entry's *value* says
// how many frames found the same key, and `table.count` says how many distinct
// keys were produced.

/// The rule this milestone exists for: an element with no `.id()` holds state
/// across frames. Before this, an unnamed element got scratch state that was
/// discarded on return.
///
/// **This test is the only guard on the ROOT's own identity, and none of the
/// six mutations run while implementing this milestone reaches it** — measured,
/// `--no-parallel`, all six green here while reddening twelve distinct tests
/// between them, none of which is this one. That is why it asserts
/// the key (`.positional(0)` under no parent) and not only `table.count == 1`:
/// a count of 1 is also what a root that got one shared wrong key every frame
/// would produce. The mutation that would redden it is a change to
/// `Frame.render`'s `child(of: nil, at: 0, name: element.elementID)`, and the
/// mechanism that keeps it honest is that the id is spelled out here.
@MainActor
@Test func anAnonymousElementHoldsStateAcrossFrames() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    for _ in 0..<3 {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var element = CountingElement(nil)     // no name
        frame.render(&element)
    }
    #expect(table.count == 1)
    #expect(table.peek(GlobalElementID.child(of: nil, at: 0, name: nil), as: Int.self) == 3)
}

/// Position discriminates siblings, so two unnamed siblings do not collide.
/// Before this milestone neither had an identity at all.
///
/// **This is the test the brief named for deleting `cursor += 1`**, and it does
/// redden: with the cursor pinned at 0 both children get `.positional(0)`, one
/// entry, counted twice. Measured, `--no-parallel`, 356 tests — deleting that
/// line reddens **three**: this one,
/// `theIndexSpaceIsFlatRatherThanNested` and
/// `reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem`. The other two
/// are not redundant with it: they see the collapse at three children and
/// across two frames respectively.
@MainActor
@Test func twoUnnamedSiblingsDoNotShareOneStateEntry() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var row = Row { CountingElement(nil); CountingElement(nil) }
    frame.render(&row)
    #expect(table.count == 2)
}

/// The flat index space: the builder nests `Pair`s, identity does not.
///
/// `Row { A; B; C }` is `Row<Pair<Pair<A, B>, C>>` — pinned at the type level by
/// `aThreeChildBlockNestsPairsRatherThanFlattening` — and the paths asserted
/// here are two components deep for all three children, not three for the last
/// two. A `Pair` that handed its second half a fresh cursor, or wrapped either
/// half in an id of its own, reddens this.
@MainActor
@Test func theIndexSpaceIsFlatRatherThanNested() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(200), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var row = Row { CountingElement(nil); CountingElement(nil); CountingElement(nil) }
    frame.render(&row)
    // Three children of one row: 0, 1, 2 — not [0], [1,0], [1,1].
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    for index in 0..<3 {
        #expect(table.peek(GlobalElementID.child(of: root, at: index, name: nil),
                           as: Int.self) == 1)
    }
    #expect(table.count == 3)
}

/// **A named list carries state through a reorder.** This is the whole reason a
/// name replaces a position rather than joining it: if the index were also in
/// the key, moving an item would mint a new key and reset it.
///
/// Measured, `--no-parallel`, 356 tests: spelling `child(of:at:name:)`'s
/// component as
/// `name.map { PathComponent.named(ElementID("\($0.name)#\(index)")) }` —
/// the index folded into the name rather than replaced by it — reddens
/// **five**: this one, `aNameReplacesThePositionRatherThanJoiningIt`
/// (`GlobalElementIDTests.swift`), `childOfAnUnnamedParentStillHasAnIdentity`
/// (`StateTableTests.swift`), `aContainerGivesItsChildrenPathsBuiltFromItsOwn`
/// (`ElementLayoutTests.swift`) and `twoSiblingsWithTheSameIDShareOneStateEntry`
/// (`ElementGroupTrapTests.swift`). This is the only one of the five that shows
/// the *consequence* — a moved item's state resetting — rather than the shape of
/// the component.
@MainActor
@Test func reorderingANamedListCarriesEachItemsState() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(300), height: Pixels(100))

    let first = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var forward = Row { for n in ["a", "b"] { CountingElement(n) } }
    first.render(&forward)

    // Same two elements, opposite order. Each keeps its own entry and count.
    let second = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var reversed = Row { for n in ["b", "a"] { CountingElement(n) } }
    second.render(&reversed)

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: ElementID("a")),
                       as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: ElementID("b")),
                       as: Int.self) == 2)
    #expect(table.count == 2)
}

/// **An unnamed list does not**, because position IS the identity there. The
/// counts stay at 2 but they belong to the slots, not to the items — which is
/// exactly why `.id()` exists.
///
/// Read together with the test above, this pair is the differential: the same
/// two frames, the same two elements, and the only difference is whether the
/// items carry a name.
@MainActor
@Test func reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(300), height: Pixels(100))
    for _ in 0..<2 {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row { CountingElement(nil); CountingElement(nil) }
        frame.render(&row)
    }
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: nil), as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: root, at: 1, name: nil), as: Int.self) == 2)
    #expect(table.count == 2)
}

// MARK: - `EitherGroup`'s two branches

/// Flipping an `if`/`else` **resets** the subtree's state rather than carrying
/// it across two structurally different elements — SwiftUI's rule, and the one
/// `EitherGroup`'s phase-mismatch trap already applies mid-frame.
///
/// **Nothing in the suite covered this before**, and that is measured rather
/// than assumed: giving both branches the same component — `.positional(branchIndex)`
/// in place of `.positional(branchIndex + 1)` in `EitherGroup.requestGroupLayout` —
/// reddens **exactly this test and the one below it**, both added by the same
/// commit, and nothing else in 356. `flippingAnEitherBranchBetweenPhasesTraps`
/// is about a branch changing *between phases* and stays green; the three
/// type-level builder tests cannot see a key at all.
///
/// The `== 1` is the load-bearing assertion. Were the branches to share a
/// component, the second frame would find the first frame's entry and write 2.
@MainActor
@Test func flippingAnEitherBranchResetsTheBranchesState() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row {
            if flag { CountingElement(nil) } else { CountingElement(nil) }
        }
        frame.render(&row)
    }

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let ifBranch = GlobalElementID.child(of: root, at: 0, name: nil)
    let elseBranch = GlobalElementID.child(of: root, at: 1, name: nil)

    // The `if` branch's element stopped being produced and was swept.
    #expect(table.peek(GlobalElementID.child(of: ifBranch, at: 0, name: nil),
                       as: Int.self) == nil)
    #expect(table.peek(GlobalElementID.child(of: elseBranch, at: 0, name: nil),
                       as: Int.self) == 1)
    #expect(table.count == 1)
}

/// The branches stay disjoint **whatever they contain**, which a flat pair of
/// indices would not manage.
///
/// This is the test that distinguishes the implementation from the obvious
/// alternative. Numbering both branches' members directly in the container's
/// space — the first branch from `cursor`, the second from `cursor + 1` —
/// separates them only while each holds exactly one element. Here the first
/// branch holds two, so its *second* member and the second branch's only member
/// would both be `.positional(cursor + 1)`, and the `else` element would inherit
/// the count of a `Box` it has nothing to do with: `2` below instead of `1`.
///
/// `EitherGroup` gives the taken branch an id of its own and numbers members
/// from 0 inside it, so the collision is unreachable at any branch size.
@MainActor
@Test func aBranchWithTwoMembersDoesNotLeakStateIntoAOneMemberBranch() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row {
            if flag {
                CountingElement(nil)
                CountingElement(nil)
            } else {
                CountingElement(nil)
            }
        }
        frame.render(&row)
    }

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let elseBranch = GlobalElementID.child(of: root, at: 1, name: nil)

    #expect(table.count == 1)
    #expect(table.peek(GlobalElementID.child(of: elseBranch, at: 0, name: nil),
                       as: Int.self) == 1)
}

// MARK: - `OptionalGroup` — an `if` with no `else`

/// An element after a vanishing `if` **adopts that element's state entry**; it
/// does not reset.
///
/// **This is the pin the plan's risk list and design spec §5 both claimed
/// already existed.** Both say "adding a sibling shifts later siblings'
/// identity" is *pinned as deliberate*, and before this test `grep` found no
/// test pinning it — one inaccurate sentence at `OptionalGroup` was standing in
/// for two claimed pins. The sentence said the later siblings were "reset",
/// which is what intuition says and is not what happens: `OptionalGroup`
/// consumes no index when absent, so the trailing element slides from
/// `.positional(1)` to `.positional(0)` and finds the vanished element's entry
/// sitting there.
///
/// **Deliberate, per ruling EP-5**, because it is SwiftUI's behaviour for an
/// unkeyed `if`. It is a sharp edge and the remedy is the test below.
@MainActor
@Test func anElementAfterAVanishingIfAdoptsTheVanishedElementsState() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row {
            if flag { CountingElement(nil) }
            CountingElement(nil)
        }
        frame.render(&row)
    }

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    // 2, not 1: the trailing element continued a count it never started. A
    // `1` here would mean the slot was reset; a `nil` at slot 0 with `2` at
    // slot 1 would mean the absent branch had reserved its index.
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: nil), as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: root, at: 1, name: nil), as: Int.self) == nil)
    #expect(table.count == 1)
}

/// Naming the **later sibling** is the remedy; naming the conditional content is
/// not.
///
/// Both halves are asserted because the obvious advice is the wrong one. A name
/// replaces a position (`PathComponent`), so a named trailing element is not in
/// the shifting index space at all and carries its count across the flip —
/// **2**, and no adoption. Naming the *conditional content* instead moves only
/// the vanishing element out of slot 0, which stops the adoption and leaves the
/// trailing element starting from scratch at slot 0 — **1**. That is better than
/// inheriting a stranger's state and still not "survives".
@MainActor
@Test func namingTheLaterSiblingIsWhatSurvivesAVanishingIf() {
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)

    // Remedy: the trailing element carries a name.
    let named = StateTable()
    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: named)
        var row = Row {
            if flag { CountingElement(nil) }
            CountingElement("tail")
        }
        frame.render(&row)
    }
    #expect(named.peek(GlobalElementID.child(of: root, at: 0, name: ElementID("tail")),
                       as: Int.self) == 2)
    #expect(named.count == 1)

    // Not the remedy: the *conditional content* carries the name instead.
    let misplaced = StateTable()
    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: misplaced)
        var row = Row {
            if flag { CountingElement("conditional") }
            CountingElement(nil)
        }
        frame.render(&row)
    }
    // No adoption — but the trailing element still moved slot and restarted.
    #expect(misplaced.peek(GlobalElementID.child(of: root, at: 0, name: nil),
                           as: Int.self) == 1)
    #expect(misplaced.count == 1)
}
