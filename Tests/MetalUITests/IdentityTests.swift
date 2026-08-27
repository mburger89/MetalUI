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
/// Reddened by reverting `GlobalElementID.child(of:at:name:)` to the
/// nil-propagating form, and by anything that stops `Frame.render` giving an
/// unnamed root a `.positional` component.
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
/// **This is the test that deleting `cursor += 1` reddens** — with the cursor
/// pinned at 0 both children get `.positional(0)`, one entry, counted twice.
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
/// Reddened by making `child(of:at:name:)` fold the index into a `.named`
/// component: the moved items mint fresh keys, so both counts restart at 1 and
/// the table holds four entries rather than two.
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
/// **Nothing in the suite covered this before.** The Step 7 mutation "give
/// `EitherGroup`'s two branches the same component" reddened nothing without
/// it: `flippingAnEitherBranchBetweenPhasesTraps` is about a branch changing
/// *between phases*, and the three type-level builder tests cannot see a key.
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
