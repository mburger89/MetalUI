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
//
// **Stage 6a (record §38, disposition R):** `CountingElement` and this file's
// two probes register native leaves, so every test here whose tree holds a
// legacy container (`Row`) runs under the proposal authority. Identity is
// assigned by the element groups, which read no authority; no assertion moved.

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
/// entry, counted twice. **Re-measured 2026-08-27, `--no-parallel`, 358 tests**
/// — edit: delete the `cursor += 1` line from `Element.requestGroupLayout` in
/// `ElementGroup.swift` — reddens **five**: this one,
/// `theIndexSpaceIsFlatRatherThanNested`,
/// `reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem`,
/// `anElementAfterAVanishingIfAdoptsTheVanishedElementsState` and
/// `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` (names and count as of
/// that measurement, before `ID-B` renamed the last two
/// `anElementAfterAVanishingIfKeepsItsOwnState` and
/// `namingEitherSideOfAVanishingIfLeavesTheTrailingSiblingsStateAlone`; not
/// re-run since). The other four are not
/// redundant with it: they see the collapse at three children, across two
/// frames, and — the last two — through a vanishing `if`. **This comment said
/// "three" until Task 4 re-ran it** — the count was taken before the fix commit
/// that added the last two, which is ruling SI-H.
@MainActor
@Test func twoUnnamedSiblingsDoNotShareOneStateEntry() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
    var row = Row { CountingElement(nil); CountingElement(nil) }
    frame.render(&row)
    // 2 (one per sibling) + 1 — the `Row`'s own `$anim` baseline. The
    // animation milestone's Task 4 wired `Row` (via its wrapped `Box`)
    // through `animated(_:_:for:pass:)`, which unconditionally persists a
    // `$anim` slot for the container on its first frame — every `Row`/
    // `Column`/`Stack` fixture in this file gains exactly one entry for it.
    #expect(table.count == 3)
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
    // 3 (one per child) + 1 — the `Row`'s own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing above.
    #expect(table.count == 4)
}

/// **A named list carries state through a reorder.** This is the whole reason a
/// name replaces a position rather than joining it: if the index were also in
/// the key, moving an item would mint a new key and reset it.
///
/// **Re-measured 2026-08-27, `--no-parallel`, 358 tests**: spelling
/// `child(of:at:name:)`'s component as
/// `name.map { PathComponent.named(ElementID("\($0.name)#\(index)")) }` —
/// the index folded into the name rather than replaced by it — reddens
/// **six**: this one, `aNameReplacesThePositionRatherThanJoiningIt`
/// (`GlobalElementIDTests.swift`), `childOfAnUnnamedParentStillHasAnIdentity`
/// (`StateTableTests.swift`), `aContainerGivesItsChildrenPathsBuiltFromItsOwn`
/// (`ElementLayoutTests.swift`), `twoSiblingsWithTheSameIDShareOneStateEntry`
/// (`ElementGroupTrapTests.swift`) and
/// `namingTheLaterSiblingIsWhatSurvivesAVanishingIf` (renamed
/// `namingEitherSideOfAVanishingIfLeavesTheTrailingSiblingsStateAlone` by
/// `ID-B`; the count predates it and was not re-run). This comment said "five"
/// until Task 4 re-ran it, missing the last — the count was taken before the fix
/// commit that added it (ruling SI-H). This is the only one of the six that
/// shows the *consequence* — a moved item's state resetting — rather than the
/// shape of the component.
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
    // Plan task 8, ruling `ID-B` (T row): the `for` loop takes ONE slot,
    // `root/0`, and its members number inside it, so a named item is
    // `root/0/named(n)` — the name still replaces its position WITHIN the loop,
    // the `ForEach` analogue. Before `ID-B` the items sat directly under `root`.
    let loop = GlobalElementID.child(of: root, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: loop, at: 0, name: ElementID("a")),
                       as: Int.self) == 2)
    #expect(table.peek(GlobalElementID.child(of: loop, at: 0, name: ElementID("b")),
                       as: Int.self) == 2)
    // 2 ("a" and "b") + 1 — the `Row`'s own `$anim` baseline (one entry
    // total across both frames, since the root's own identity is the same
    // both times), on `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing.
    #expect(table.count == 3)
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
    // 2 (one per slot) + 1 — the `Row`'s own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing above.
    #expect(table.count == 3)
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
/// commit, and nothing else — re-measured 2026-08-27, `--no-parallel`, and this
/// is one of the two counts in the milestone that survived re-measurement
/// unchanged, out of 358 rather than the 356 first recorded.
/// `flippingAnEitherBranchBetweenPhasesTraps`
/// is about a branch changing *between phases* and stays green; the three
/// type-level builder tests cannot see a key at all.
///
/// The `== 1` on the `else` branch's value is the load-bearing assertion.
/// Were the branches to share a component, the second frame would find the
/// first frame's entry and write 2.
///
/// **Two assertions inverted by the tombstones milestone's Task 1** — the `if`
/// branch's entry no longer disappears when its element stops being produced,
/// it tombstones. That does not touch what this test exists to prove: the two
/// branches are still **distinct entries** rather than one shared one (the
/// `else` branch's value is still 1, not a continued 2), which is the
/// reset-not-carried property in this test's name. What changed is only that
/// the abandoned `if` branch's entry is now still there, holding the value it
/// had, reporting itself not live.
///
/// **That `!isLive` assertion is incidentally sensitive to `Frame.render`'s
/// sweep-after-phases ordering** — found by a review, not by design: moving
/// `stateTable.sweep()` above the phases makes this line redden too, because
/// it exercises the same one-frame liveness lag
/// `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`
/// (`StateTableTests.swift`) exists to pin. This test is not a second guard
/// on that ordering — its own purpose (distinct entries, not a shared one) is
/// unrelated to it — so do not read the `!isLive` line as pinning ordering,
/// and do not remove it on the theory that the dedicated pin already covers
/// it; the two happen to overlap, they do not replace each other.
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

    // The `if` branch's element stopped being produced, and its branch was
    // EVALUATED absent on the frame after one that produced it, so its entry
    // is deleted (plan task 8, ruling `ID-C`; T row). Until `ID-C` it
    // tombstoned here — value 1, not live — and came back reading 2 if the
    // branch flipped back (probe V9: SwiftUI starts it fresh).
    let ifContentID = GlobalElementID.child(of: ifBranch, at: 0, name: nil)
    #expect(table.peek(ifContentID, as: Int.self) == nil)
    #expect(!table.isLive(ifContentID))
    #expect(table.peek(GlobalElementID.child(of: elseBranch, at: 0, name: nil),
                       as: Int.self) == 1)
    // The live `else` branch's entry + 1 for the `Row`'s own `$anim` baseline,
    // on `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing. 3 until `ID-C`
    // removed the `if` branch's tombstone. A shared-component regression would
    // still show up as the `else` entry reading 2, above.
    #expect(table.count == 2)
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
///
/// **`table.count` inverted by the tombstones milestone's Task 1**, for the
/// same reason as the test above: the abandoned `if` branch's two members no
/// longer vanish when frame 2 stops producing them, they tombstone. `3`, not
/// `1` — the two `if`-branch tombstones plus the one live `else`-branch
/// entry. The collision this test actually guards against would still show
/// up as the `else` entry's value below reading `2` instead of `1`.
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

    // The live `else`-branch entry + 1 — the `Row`'s own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing. 4 until plan task
    // 8's `ID-C` (T row) deleted the two `if`-branch tombstones when the branch
    // was evaluated absent.
    #expect(table.count == 2)
    #expect(table.peek(GlobalElementID.child(of: elseBranch, at: 0, name: nil),
                       as: Int.self) == 1)
}

// MARK: - `OptionalGroup` — an `if` with no `else`

/// **An element after a vanishing `if` keeps its own state** (plan task 8,
/// ruling `ID-B`; spec C2.1; probe V1 and, for the second arm, G7).
///
/// **Renamed from `anElementAfterAVanishingIfAdoptsTheVanishedElementsState`**,
/// which pinned the opposite as deliberate: `OptionalGroup` consumed no index
/// when absent, so the trailing element slid from `.positional(1)` to
/// `.positional(0)` and read the vanished element's **2**. That rested on
/// `SI-G`'s claim that SwiftUI shifts, which no probe had run; probe V1 shows
/// SwiftUI's trailing view keeping its own serial. Since `ID-B` the `if` takes
/// ONE slot (`root/0`) whether or not it has content, its content numbers
/// inside it (`root/0/0`), and the trailing element stays at `root/1` — reading
/// its own 2. The vanished content's entry is deleted, not tombstoned (`ID-C`:
/// the `if` was evaluated absent after a frame that produced it).
///
/// The second arm is probe G7's: the trailing sibling is a two-member
/// `Component` with a `.padding` — a modified group — and both members keep
/// their own counts.
///
/// Mutation M2a (the UNTYPED `OptionalGroup` advances the cursor only when
/// `wrapped != nil`) reddens this.
@MainActor
@Test func anElementAfterAVanishingIfKeepsItsOwnState() {
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
    let ifSlot = GlobalElementID.child(of: root, at: 0, name: nil)
    // 2: the trailing element counted both frames at its own `root/1`. Adoption
    // would leave `root/1` at 1 (frame 1's only) and put 2 at `root/0`.
    #expect(table.peek(GlobalElementID.child(of: root, at: 1, name: nil), as: Int.self) == 2)
    // The `if` content's entry is gone (`ID-C`), and nothing was ever stored at
    // the slot itself.
    #expect(table.peek(GlobalElementID.child(of: ifSlot, at: 0, name: nil), as: Int.self) == nil)
    #expect(table.peek(ifSlot, as: Int.self) == nil)
    // The trailing entry + 1 — the `Row`'s own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing.
    #expect(table.count == 2)

    // Probe G7's arm: a modified two-member group after the vanishing `if`.
    let reads = ConditionalReads()
    let groupTable = StateTable()
    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: groupTable)
        var row = Row {
            if flag { ConditionalCounter("vanishing", reads) }
            TwoCounters(first: "m0", second: "m1", reads: reads).padding(Pixels(4))
        }
        frame.render(&row)
    }
    #expect(reads.values["m0"] == 2, "member 0 keeps its own count: \(reads.values)")
    #expect(reads.values["m1"] == 2, "member 1 keeps its own count: \(reads.values)")
}

/// **Naming either side of a vanishing `if` leaves the trailing sibling's state
/// alone** (plan task 8, `ID-B`). **Renamed from
/// `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`**, whose two arms pinned
/// the old rule's remedy: naming the trailing sibling kept its count (2), and
/// naming the conditional content only stopped the adoption, the trailing
/// element restarting at slot 0 (1). Since `ID-B` a vanishing `if` moves no
/// sibling, so both arms read 2 — naming the trailing sibling past an `if`
/// still works and is no longer needed.
@MainActor
@Test func namingEitherSideOfAVanishingIfLeavesTheTrailingSiblingsStateAlone() {
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)

    // The trailing element carries a name.
    let named = StateTable()
    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: named)
        var row = Row {
            if flag { CountingElement(nil) }
            CountingElement("tail")
        }
        frame.render(&row)
    }
    #expect(named.peek(GlobalElementID.child(of: root, at: 1, name: ElementID("tail")),
                       as: Int.self) == 2)
    // The live "tail" + 1 — the `Row`'s own `$anim` baseline. The `if`
    // content's entry is deleted (`ID-C`), not tombstoned as it was (3).
    #expect(named.count == 2)

    // The conditional content carries the name instead.
    let misplaced = StateTable()
    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: misplaced)
        var row = Row {
            if flag { CountingElement("conditional") }
            CountingElement(nil)
        }
        frame.render(&row)
    }
    // The trailing element stays at `root/1` and keeps counting — 2, where the
    // old rule moved it to slot 0 and restarted it at 1.
    #expect(misplaced.peek(GlobalElementID.child(of: root, at: 1, name: nil),
                           as: Int.self) == 2)
    // The trailing entry + 1 — the `Row`'s own `$anim` baseline; the named
    // conditional's entry is deleted with its slot (`ID-C`). 4 before.
    #expect(misplaced.count == 2)
}

// MARK: - The two index-arithmetic lines the branch shipped unguarded

/// **`EitherGroup` reserves BOTH of its index slots, because it may take
/// either.** `cursor += 2` runs before the branch is chosen, so `.first` uses
/// `branchIndex` and `.second` uses `branchIndex + 1`; whichever runs, the other
/// slot must stay reserved or something else in the container lands on it.
///
/// **The comment at that line, and ruling SI-F, both justified `+= 2` with the
/// wrong property, and this test is why the justification changed.** They said a
/// later sibling's index must not depend on which branch was taken — but the
/// cursor advances *before* the switch, so that holds under `+= 1` too.
/// Measured, `Row { if flag { C() } else { C() }; C() }` across a flip: the
/// trailing element sits at `.positional(2)` under `+= 2` and `.positional(1)`
/// under `+= 1`, and **counts 2 either way**. Its state survives the mutation,
/// so it cannot pin the line — which is exactly why the line was unguarded on a
/// 358-test suite.
///
/// What does break is a sibling that lands on the *untaken* slot and then goes
/// one level deeper, which this test builds. Measured, `--no-parallel`, 358
/// tests — edit: `cursor += 2` → `cursor += 1` in
/// `EitherGroup.requestGroupLayout` (`ElementGroup.swift`):
///
/// - this composition — the trailing `Row`'s child and the `else` branch's
///   member share one path, `table.count` collapses 2 → 1, and the shared entry
///   reads **3** across the two frames instead of 1 and 2;
/// - `Row { if a { C() } else { C() }; if b { C() } else { C() } }` — the
///   collision spec §3.5 names — collapses 2 → 1 the same way, reading **2**.
///
/// The `== 1` on the branch member is as load-bearing as the count: a shared
/// entry shows up there as a 3.
///
/// **`table.count` inverted by the tombstones milestone's Task 1** — see the
/// re-measurement note above the assertion itself for what the mutation now
/// does to it, checked rather than assumed.
@MainActor
@Test func aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))

    for flag in [true, false] {
        let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)
        var row = Row {
            if flag { CountingElement(nil) } else { CountingElement(nil) }
            Row { CountingElement(nil) }
        }
        frame.render(&row)
    }

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    // The `if`/`else` owns indices 0 and 1; the trailing `Row` is index 2.
    let takenBranch = GlobalElementID.child(of: root, at: 1, name: nil)   // `.second`, frame 2
    let sibling = GlobalElementID.child(of: root, at: 2, name: nil)

    #expect(table.peek(GlobalElementID.child(of: takenBranch, at: 0, name: nil),
                       as: Int.self) == 1)
    #expect(table.peek(GlobalElementID.child(of: sibling, at: 0, name: nil),
                       as: Int.self) == 2)
    // 2: the live `else`-branch entry and the live sibling entry — the
    // tombstoned `if`-branch entry from frame 1 is deleted since plan task 8's
    // `ID-C` (T row; 5 before it). The `peek` values above are still the
    // load-bearing assertions against a shared-entry regression.
    // + 2 — this fixture has TWO `Row`s (the root and the nested trailing
    // one), each now carrying its own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing.
    #expect(table.count == 4)
}

/// **An erased element is still one element and therefore one index.**
/// `AnyElement.requestGroupLayout` has its own copy of `Element`'s default —
/// including its own `cursor += 1` — and nothing reached it: two `AnyElement`
/// siblings did not exist in any test, so the whole erased path was outside the
/// index space's coverage.
///
/// The claim this pins is asserted in two places — CLAUDE.md's `AnyElement` row
/// ("boxing every child moves no path and no `StateTable` entry") and
/// `ElementBuilder.swift`'s note that the boxing mutation reddens only
/// type-level tests. Both were true by inspection and measured by nothing.
///
/// Measured, `--no-parallel`, 358 tests — edit: delete `cursor += 1` from
/// `AnyElement.requestGroupLayout` (`ElementGroup.swift`, **not** `Element`'s
/// default, which its own tests already cover) — reddens exactly this test:
/// both erased siblings take `.positional(0)`, `table.count` collapses 2 → 1,
/// and the single entry reads 2.
@MainActor
@Test func twoErasedSiblingsDoNotShareOneStateEntry() {
    let table = StateTable()
    let size = Size<Pixels>(width: Pixels(100), height: Pixels(100))
    let frame = Frame(contentSize: size, scaleFactor: 1, stateTable: table)

    var row = Row {
        AnyElement(CountingElement(nil))
        AnyElement(CountingElement(nil))
    }
    frame.render(&row)

    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    #expect(table.peek(GlobalElementID.child(of: root, at: 0, name: nil), as: Int.self) == 1)
    #expect(table.peek(GlobalElementID.child(of: root, at: 1, name: nil), as: Int.self) == 1)
    // 2 (one per erased sibling) + 1 — the `Row`'s own `$anim` baseline, on
    // `twoUnnamedSiblingsDoNotShareOneStateEntry`'s footing.
    #expect(table.count == 3)
}

// MARK: - One element VALUE placed twice

/// Reads the `@State` each occurrence can see, in a phase AFTER layout.
@MainActor
final class StampRecorder {
    var stampsInPrepaint: [Int] = []
}

/// Stamps a **distinct** number into its own `@State` during `requestLayout`,
/// then reads it back in `prepaint`.
///
/// The three properties that make this able to fail are the ones
/// `twoCopiesOfOneElementDoNotShareLayoutState` names for `LayoutState`: the
/// two children are **copies of one value**, they are the **same type**, and
/// the stamp is **read back in a later phase**. The fourth, specific to
/// `@State`, is that the two occurrences must stamp **different** numbers —
/// `State.swift`'s own open-question note records that a probe where both
/// advance in lockstep reads `[1, 1, 2, 2, 3, 3]` and proves nothing.
private struct StampedStateProbe: Element {
    @State var stamp = 0
    let counter: InstanceCounter
    let recorder: StampRecorder
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        stamp = counter.next()                       // occurrence 0 -> 1, occurrence 1 -> 2
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        recorder.stampsInPrepaint.append(stamp)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **One element value placed twice must not share one `@State` box.**
///
/// This is the differential probe `State.swift`'s open-question note asks for
/// and records as never having been written. `State.Box` is a **class**, so two
/// copies of one element value share it; `StateBinder.bind` runs only inside
/// layout (`ElementGroup.swift:112`, `Component.swift:130`, `Frame.swift:1211`)
/// and `prepaintGroup`/`paintGroup` never rebind. The second occurrence's
/// `bind` therefore leaves the shared box pointing at ITS slot, and the first
/// occurrence reads the second's value in every phase after layout.
///
/// Each occurrence stamps a distinct number, so a wrong slot reads a wrong
/// NUMBER rather than merely a wrong entry — which is exactly what the
/// lockstep probe in `State.swift`'s note could not distinguish.
@MainActor
@Test func oneElementValuePlacedTwiceDoesNotShareItsState() {
    let counter = InstanceCounter()
    let recorder = StampRecorder()
    let table = StateTable()

    let probe = StampedStateProbe(counter: counter, recorder: recorder)
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)),
                      scaleFactor: 1, stateTable: table)
    var root = Row { probe; probe }
    frame.render(&root)

    // Layout stamped 1 into the first occurrence's slot and 2 into the
    // second's; each must read back its own.
    #expect(recorder.stampsInPrepaint == [1, 2],
            "occurrences read \(recorder.stampsInPrepaint) — a shared box reads [2, 2]")
    // NOT asserted on `table.count`: a `Row` wraps a `Box`, which mints a
    // `$anim` retention slot of its own, so the table holds three entries and
    // the count cannot discriminate this defect. The stamps can.
    #expect(Set(recorder.stampsInPrepaint).count == 2,
            "the two occurrences read the same value, so they shared one slot")
}

/// Registers a click handler that writes to its OWN `@State`, capturing the
/// property wrapper — which is how any element that mutates its state from a
/// handler has to be written, since a `mutating` phase cannot capture `self`.
private struct ClickableStateProbe: Element {
    @State var stamp = 0
    let counter: InstanceCounter
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        stamp = counter.next()
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        let state = _stamp                       // shares the class box
        var handlers = Handlers()
        handlers.onClick = { state.wrappedValue += 100 }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **Divergence 71, kept (plan task 8, ruling `ID-F`): a closure run OUTSIDE
/// input dispatch writes the occurrence that bound LAST.** Renamed from
/// `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` (spec lane 2's R
/// row); the assertions are unchanged.
///
/// One element value placed twice shares one `State.Box` (a class), and a
/// handler captures that box. Since `ID-F` every INPUT path — a click, a key, an
/// action, an accessibility press or adjust, a text field's edit or submit —
/// runs its handler under `StateDispatch.dispatching(to:)`, and an aliased box
/// resolves to the dispatched element's own occurrence (lane 1's O1.1–O1.6).
/// This test calls the first occurrence's `onClick` DIRECTLY, with no dispatch
/// owner — the shape of a timer, a task or any closure a caller invokes itself —
/// so the box falls back to its last-bound slot: occurrence 0 reads **1** and
/// occurrence 1 reads **102**. SwiftUI moves the caller's own occurrence here
/// (probe S5); MetalUI cannot, because `Mirror` cannot re-point a copy's box
/// (`State.swift`'s note), so the remedy for a closure run outside dispatch is
/// two values. `StateTable.aliasedStateBoxes` still counts the shape.
@MainActor
@Test func aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence() {
    let counter = InstanceCounter()
    let table = StateTable()
    let probe = ClickableStateProbe(counter: counter)
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)),
                      scaleFactor: 1, stateTable: table)
    var root = Row { probe; probe }
    frame.render(&root)

    let ids = frame.hitboxes.map(\.id)
    #expect(ids.count == 2, "each occurrence registers its own hitbox, got \(ids.count)")
    guard ids.count == 2 else { return }

    // Fire ONLY the first occurrence's handler.
    frame.hitboxes[0].handlers.onClick?()

    // The `@State` slot is a NAMED CHILD of the element id, not the id itself
    // (`State.swift:88`).
    func slot(_ id: GlobalElementID) -> GlobalElementID {
        GlobalElementID.child(of: id, at: 0, name: ElementID("$state0"))
    }
    let first = table.peek(slot(ids[0]), as: Int.self)
    let second = table.peek(slot(ids[1]), as: Int.self)

    // Divergence 71: with no dispatch owner the write reaches the last-bound
    // occurrence. Through a real click the answers are 101 and 2 (`ID-F`).
    #expect(first == 1, "occurrence 0 was clicked; its own slot should have moved to 101")
    #expect(second == 102, "occurrence 1 was never clicked, yet received the write")

    // And the shape is detected, which is what makes it findable in an app.
    #expect(table.aliasedStateBoxes > 0,
            "one value placed twice must be counted as an aliased state box")
}
