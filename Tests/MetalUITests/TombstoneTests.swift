import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// **An entry unmarked by a frame is retained, not deleted** — the whole of
/// spec §3, and the line every other task in this milestone stands on.
///
/// Before this change `sweep()` was `storage.filter { marked.contains($0.key) }`
/// and the value was gone. `peek` must still return it, and `isLive` must report
/// that the element was not produced — an AX handle reads that as invalid, a
/// returning element re-marks it and reads its value back.
@MainActor
@Test func anUnmarkedEntryIsRetainedAsATombstoneWithItsValue() {
    let table = StateTable()
    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("row"))

    table.write(id, 42)
    #expect(table.isLive(id), "an entry written this frame is live")

    table.sweep()

    #expect(table.peek(id, as: Int.self) == 42, "the value must survive the sweep")
    #expect(!table.isLive(id), "an entry no frame marked must report itself not live")
    #expect(table.count == 1, "the entry is retained, not deleted")
}

/// A tombstoned entry that is marked again is live again, with its value.
@MainActor
@Test func markingATombstonedEntryMakesItLiveAgain() {
    let table = StateTable()
    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("row"))
    table.write(id, 7)
    table.sweep()
    #expect(!table.isLive(id))

    table.mark(id)
    #expect(table.isLive(id), "re-marking resurrects the entry")
    #expect(table.peek(id, as: Int.self) == 7, "and its value was never lost")
}

/// **The cold-frame spike must FALL, and this is the only assertion that can
/// see it.** Ruling MP-I: a `ScrollView`'s viewport is not measured until its
/// own `prepaint` has run once, so frame 0 builds every row — 100,002 entries
/// for a 100k list against a steady state of 20. **Read both as a derivation,
/// not a fresh measurement of the sum**: this paragraph's original 100,001
/// and 19 came from a harness that is not preserved as a runnable test and
/// was NOT re-run this round — they are inherited, unverified figures. The
/// **+1** on each is what this milestone's Task 7 fix round DID directly
/// re-measure, twice, on two different harnesses (reverting the `List`'s
/// `AXNode` emission in the real 10k-row suite test drops every figure by
/// exactly one; a separate differential probe showed the identical flat +1
/// under different scroll parameters) — a `List` unconditionally emitting
/// its own `AXNode` is a permanent `$ax` retention slot that adds exactly one
/// resident entry, cold frame and steady state alike. Task 1 made the sweep
/// retain, which turns that transient into a permanent one until something
/// reaps it.
///
/// A steady-state test cannot see this: 20 never approaches any threshold, so a
/// policy that never reaps at all passes it.
@MainActor
@Test func theColdFrameSpikeIsReapedRatherThanRetainedForever() {
    let table = StateTable()
    let ids = (0..<100_000).map {
        GlobalElementID.child(of: nil, at: $0, name: ElementID("row\($0)"))
    }
    for id in ids { table.write(id, 1) }
    #expect(table.count == 100_000, "the cold frame really did create them all")

    // Steady state: only the last 19 are produced from here on.
    let live = Array(ids.suffix(19))
    for _ in 0..<(StateTable.staleAfterGenerations + 2) {
        for id in live { table.mark(id) }
        table.sweep()
    }

    #expect(table.count <= StateTable.sweepThreshold, """
            the cold-frame spike was retained: \(table.count) entries survive a \
            steady state of \(live.count). A policy sized against the steady set \
            passes every other test in this file and leaks the whole list here.
            """)
    for id in live {
        #expect(table.peek(id, as: Int.self) == 1, "a live entry must not be reaped")
    }
}

// MARK: - Task 3: divergence 12, closed as bounded

/// A row that increments its own `@State` every time it is actually built —
/// `StateTests.CounterElement`'s idiom. `elementID` is COMPUTED, not stored,
/// so `Mirror` sees only `count`: its ordinal is 0, matching every other
/// single-`@State` fixture in this suite (`$state0`).
///
/// **Spelled through the legacy lowering on both authorities** (stage 4, lane 4;
/// `ListTests.Row`'s own re-spelling, `LR-BW`). It registered `pass.requestNode`
/// outright until then, which under `.proposal` hits `Frame.requestNode`'s
/// backstop and **aborts the run** —
/// `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` below is that abort
/// kept as an observable. `lowerLegacyNode` over no children forwards to
/// `lowerLegacyLeaf` over a 0×0 native leaf by itself, which is the lowering of a
/// childless `Box`, so the two branches describe the same box.
///
/// **The `@State` write stays outside the branch**, deliberately: it is what this
/// fixture exists for, and a production count that depended on the authority
/// would make the two excursion arms incomparable rather than comparable.
private struct ExcursionRow: Element {
    @State var count = 0
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        count += 1
        if pass.lowersToProposal {
            return (pass.lowerLegacyNode(Style(), declared: Style(), children: [],
                                         site: .customElement), ())
        }
        return (pass.frame.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

private struct ExcursionItem: Identifiable {
    let id: String
}

// MARK: - The red-before for the excursion test's `.proposal` arm (`LR-BX`)

/// **`ExcursionRow`'s registration exactly as it stood at `16d6696`**, kept as a
/// live fixture so the probe below keeps a subject after `ExcursionRow` itself is
/// re-spelled through `lowerLegacyNode` (stage 4, lane 4).
///
/// It carries no `@State`: the probe never reads a slot, it reads a trap.
private struct LegacySpelledExcursionRow: Element {
    var elementID: ElementID? { nil }

    @available(*, deprecated, message: "spelled with the deprecated legacy registrar on purpose: it is the subject of aLegacySpelledExcursionRowAbortsAProductionProposalFrame, which reads the customElement trap (stage 6a, LR-CV)")
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **The red this lane could not take in-process** (`LR-BX`, spec §6 lane 4).
/// `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` is about to run
/// under both layout authorities. Running it under `.proposal` with its row
/// spelled as `pass.requestNode(style:children:)` does not fail — it hits
/// `Frame.requestNode`'s backstop (the one
/// `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` pins) and **aborts the
/// whole run**, with no summary line and no list of what failed. So the red is
/// taken here, in a child process, in `ListTests`'
/// `aLegacySpelledListRowAbortsAProductionProposalFrame`'s shape.
///
/// A **production** frame: no `reportsUnlowerableFields`, which is what the
/// excursion test builds and what `Window` builds.
///
/// Recorded, with the assertion temporarily pointed at a string that cannot
/// match (reverted; `git status --short` clean afterwards):
///
///     MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode
///     has no proposal lowering (plan task 7, stage 6a); a tree containing it
///     cannot run under the proposal layout authority.
///
/// The message names **stage 9** since stage 6a moved `.customElement`'s owner
/// (`LR-CW`); the assertion below reads the part before the stage.
@Test func aLegacySpelledExcursionRowAbortsAProductionProposalFrame() async {
    let node = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let data = (0..<12).map { ExcursionItem(id: "row\($0)") }
            var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(data, rowHeight: Pixels(20)) { _ in LegacySpelledExcursionRow() }
            }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(20)),
                  scaleFactor: 1, stateTable: StateTable(),
                  layoutAuthority: .proposal).render(&tree)
        }
    }
    let err = String(decoding: node?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("customElement.requestNode has no proposal lowering"),
            "aborted, but not at the row's requestNode:\n\(err)")
}

/// **The design's premise about `FocusTests`' row, measured and found wrong.**
/// Spec §6 lane 4 says `TombstoneTests.ExcursionRow` and `FocusTests`' row "both
/// abort under `.proposal` today". Only the first does.
/// `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` builds its rows as
/// `Box().focusable()` — a `Box`, which stage 1 lowered, and `focusable()` is a
/// `Self`-returning modifier that writes `handlers`, not a registration — so the
/// identical tree under `.proposal` **runs to completion**. This arm is the
/// positive control for the one above: the abort is the row's spelling, not the
/// `List`, not the `ScrollView` and not `@State`. `LR-CF` records the correction.
@Test func aBoxSpelledListRowDoesNotAbortAProductionProposalFrame() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let data = (0..<12).map { ExcursionItem(id: "row\($0)") }
            var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(data, rowHeight: Pixels(20)) { _ in Box().focusable() }
            }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(20)),
                  scaleFactor: 1, stateTable: StateTable(),
                  layoutAuthority: .proposal).render(&tree)
        }
    }
}

/// **Divergence 12, closed as BOUNDED, not absolute.** A `List` row scrolled
/// out of the window and back keeps its `@State` — *within the retention
/// window* (`StateTable.staleAfterGenerations`, 2 generations) — and loses it
/// once the excursion runs longer than that. "Fixed" and "fixed for
/// `staleAfterGenerations` generations" are different claims and only the
/// second is true; this test asserts both halves rather than either alone.
///
/// **The first half — the short excursion survives — is a REGRESSION GUARD,
/// not a red-first proof.** Tasks 1-2 (the sweep's tombstone retention and
/// its generation-based reap) already closed divergence 12 before this test
/// was written, so that half PASSES on arrival against this branch's HEAD. A
/// reader who assumes every test in this milestone was red first would draw
/// the wrong conclusion here; recorded rather than left implied.
///
/// **The second half — the long excursion does NOT survive — is the one that
/// is genuinely new, and it is what keeps the first half honest.** A policy
/// that retains every tombstone forever (never reaps at all) would also pass
/// the first half; only the second distinguishes "bounded" from "unbounded."
/// Verified by mutation (task report): reverting `sweep()` to its
/// pre-tombstone shape — deleting every unmarked entry on the spot, the
/// operation `anUnmarkedEntryIsRetainedAsATombstoneWithItsValue`'s own doc
/// comment describes — reddens the SHORT excursion's assertion (the row is
/// deleted the very next sweep it is not produced, long before it is due
/// back) and leaves the LONG excursion's alone (both policies delete row 7
/// once it goes unmarked, so both produce the fresh-`0`-then-`1` value this
/// half expects) — the opposite of a correct implementation, and exactly the
/// asymmetry that proves the second half is not vacuous on its own.
///
/// **Constructed, not observed** (the brief's own words): the demo's `List`
/// rows carry no `@State` at all — measured live set of 1, the scroller's own
/// offset — so `demoLikeRows(_:)` in `MeasurePerformanceTests.swift` cannot
/// see this divergence, and this fixture builds a stateful row type instead.
/// The scroll is driven by writing `ScrollState` into the table directly
/// (`table.write`), not by simulating wheel events — `ScrollRoutingTests.swift`'s
/// `stateTable.peek(id, as: ScrollState.self)` idiom, run in reverse.
///
/// **A synthetic padding set holds `storage.count` above `sweepThreshold` for
/// the whole test — without it the reap never engages at all, and the second
/// half would pass VACUOUSLY.** This fixture's own real entries (a dozen rows
/// plus the scroller) never come close to 256 on their own, the same gap
/// `theColdFrameSpikeIsReapedRatherThanRetainedForever` exists to close for a
/// raw `StateTable`; 260 padding ids, marked fresh every frame below so they
/// never themselves go stale, keep the table over threshold throughout.
/// **This alone is not enough to prove the reap is gated ON the threshold at
/// all** — see `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`
/// below for why, and for the mutation this test cannot catch.
///
/// **Runs under BOTH layout authorities since plan task 7's stage 4, lane 4**
/// (spec §4.1 row 2, `LR-BU`). Stage 4 replaced `List`'s spacer-plus-rows flex
/// column with a single `WindowedRowsLayout` on the proposal path, so which rows
/// are *built* — and therefore which `StateTable` entries a generation marks — is
/// decided by `visibleRange` on one path and could have been decided by the
/// layout on the other. It is not: `visibleRange` is untouched (spec §3.3), and
/// this test is what says so about retention rather than about geometry. Every
/// literal below — the offsets, the windows they select, the counts 1/3/4 — is
/// unchanged on both paths; the only difference is `layoutAuthority`.
///
/// Mutation **M4a** (`staleAfterGenerations` 2 → 3) must redden this test's long
/// half on **both** authorities, and `FocusTests`' twin likewise.
@MainActor
@Test(arguments: AuthorityCoverage.authorities)
func aListRowsStateSurvivesABoundedExcursionButNotALongerOne(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func px(_ v: Float) -> Pixels { Pixels(v) }
    let rowHeight = px(20)
    let data = (0..<12).map { ExcursionItem(id: "row\($0)") }
    let shortIndex = 4   // brought back after a 2-generation excursion
    let longIndex = 7    // left out for 3 generations — one past the bound

    let table = StateTable()

    // 260 ids nothing else in this test ever reads by value — pure ballast to
    // keep `storage.count` over `sweepThreshold` (256) for every sweep below.
    let paddingIDs = (0..<260).map {
        GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)"))
    }
    for id in paddingIDs { table.write(id, 0) }

    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data, rowHeight: rowHeight) { _ in ExcursionRow() }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    // A 1-row-tall viewport: `overscan` (2) either side is what turns "one
    // row visible" into the 5-row windows the offsets below were chosen against.
    let contentSize = Size<Pixels>(width: px(100), height: px(20))

    // Marks the padding, optionally moves the scroller's stored offset
    // (preserving whatever `viewportExtent` `ScrollView`'s own prepaint last
    // measured, so this write cannot itself undo windowing), and renders one
    // frame.
    func renderFrame(offset: Double?) {
        for id in paddingIDs { table.mark(id) }
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset,
                                                lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        let frame = Frame(contentSize: contentSize, scaleFactor: 1, stateTable: table,
                          layoutAuthority: authority)
        frame.render(&tree)
    }

    // A row's `GlobalElementID` HAND-COMPUTED from the exact chain the
    // framework itself builds, rather than recovered from `frame.scrollRegions`
    // — a geometry-based recovery (`ListTests.idOfRow`'s technique) does not
    // survive contact with a REAL `ScrollView`: a row painting above the
    // viewport is intersected with the active clip before it is recorded
    // (`Frame.insertHitbox`), so several rows can land at the same clipped
    // `y == 0` and a naive y-match picks the wrong one. Measured directly
    // (a throwaway probe) rather than assumed. Hand-computing sidesteps that
    // entirely and is the same idiom `StateTests.stateOrdinalsAreTheMirrorIndexNotThePositionAmongStateChildren`
    // uses for its own slot ids.
    //
    // The chain, outside-in: `scrollerID` (this tree's root, named
    // "scroller") → `listID` (`ScrollView`'s sole, unnamed content — position
    // 0 under `scrollerID`, from `Element`'s default `requestGroupLayout`) →
    // the row's own wrapping `Box`, NAMED after `datum.id`
    // (`List.requestLayout`'s `.id(String(describing: datum.id))`, parented
    // directly on `listID` — `List.requestLayout` passes its OWN id straight
    // into its internal box's `requestLayout`, minting no sub-id of its own)
    // → the row element itself, unnamed, position 0 under that box (its sole
    // content). A name replaces a position rather than joining it
    // (`ElementID.swift`), so the `at:` argument below is never consulted
    // once a `name:` is supplied — passed as 0 throughout for that reason.
    let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
    func rowID(_ index: Int) -> GlobalElementID {
        let boxID = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[index].id))
        return GlobalElementID.child(of: boxID, at: 0, name: nil)
    }
    func slotID(_ index: Int) -> GlobalElementID {
        GlobalElementID.child(of: rowID(index), at: 0, name: ElementID("$state0"))
    }
    let shortSlot = slotID(shortIndex)
    let longSlot = slotID(longIndex)

    // Frame 1: cold. No `ScrollView.prepaint` has run yet, so its published
    // `viewportExtent` is 0 and `List` builds every row (ruling MP-I) rather
    // than windowing.
    renderFrame(offset: nil)
    #expect(table.peek(shortSlot, as: Int.self) == 1)
    #expect(table.peek(longSlot, as: Int.self) == 1)

    // Frames 2-3: offset 100 puts both rows in the window ([3, 8), overscan
    // included). Two more productions each — a baseline of 3 — high enough
    // that "continues from 3" and "resets to a fresh 1" cannot be confused.
    renderFrame(offset: 100)
    renderFrame(offset: 100)
    #expect(table.peek(shortSlot, as: Int.self) == 3)
    #expect(table.peek(longSlot, as: Int.self) == 3)

    // Frames 4-5: offset 0 windows to [0, 3) — BOTH target rows leave the
    // window. Two generations pass with neither marked: exactly
    // `staleAfterGenerations`, the edge of the retention window rather than
    // past it (`lastSeenGeneration + staleAfterGenerations < generation` is a
    // strict `<`, so a gap of exactly 2 does not qualify).
    renderFrame(offset: 0)
    renderFrame(offset: 0)

    // Frame 6: offset 80 windows to [2, 7) — the SHORT row (index 4) returns;
    // the LONG row (index 7) is still excluded, and its excursion crosses the
    // bound on this very sweep (3 generations unmarked, one past the limit).
    renderFrame(offset: 80)
    #expect(table.isLive(shortSlot), "the short row must actually be built this frame, not merely retain a stale value")
    #expect(table.peek(shortSlot, as: Int.self) == 4,
            "the short row's 2-generation excursion is WITHIN staleAfterGenerations: its @State must survive")

    // Frame 7: offset 140 windows to [5, 10) — the LONG row returns. Its
    // tombstone was already reaped at frame 6's sweep, so this build reads a
    // fresh `@State`, not the 3 it held before leaving — under the SAME
    // identity, since that is what CLAUDE.md's divergence 12/17 language
    // means by "identity survives, state does not": the hand-computed id
    // above never changed, only what `sweep()` did to the entry under it.
    renderFrame(offset: 140)
    #expect(table.isLive(longSlot), "the long row must actually be built this frame, not merely retain a stale value")
    #expect(table.peek(longSlot, as: Int.self) == 1,
            "the long row's 3-generation excursion exceeded staleAfterGenerations: its @State must NOT survive")
}

/// **The threshold half of divergence 12's bound, isolated from `List`
/// entirely — and the reason the test above cannot stand in for this one.**
/// That test's padding keeps `storage.count` over `sweepThreshold` for its
/// whole run, on purpose (see its own doc comment) — which means it never
/// once exercises the GATE itself. A mutation that deletes
/// `storage.count > Self.sweepThreshold` from `sweep()` — "reap once stale,
/// full stop, ignoring how large the table is" — reaps every stale entry in
/// both tests' padding-laden runs exactly as today's gated code does, since
/// the gate was already true throughout. Measured by actually running that
/// mutation against the full suite with this test absent: **it reddens
/// nothing** — the same finding Task 2's own review made with a throwaway
/// probe rather than a committed test.
///
/// A single entry, staled far past `staleAfterGenerations` while
/// `storage.count` stays at 1 — nowhere near `sweepThreshold` — is what
/// separates the two policies: gated code leaves it alone forever; ungated
/// code reaps it three sweeps after the last mark, exactly as it would above
/// threshold. **This test is a genuine red-first proof, not a regression
/// guard**: it reddens under that mutation (checked below) and is green
/// against today's `sweep()`.
@MainActor
@Test func aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold() {
    let table = StateTable()
    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("lone"))
    table.write(id, 42)

    // Ten sweeps with nothing ever marking `id` again — many multiples of
    // `staleAfterGenerations` (2), so this is not merely at the boundary.
    for _ in 0..<10 { table.sweep() }

    #expect(table.count == 1, "storage never approaches sweepThreshold (256) in this test")
    #expect(table.peek(id, as: Int.self) == 42,
            "a stale entry must not be reaped while storage.count stays at or below sweepThreshold — reaping is gated on table size, not on staleness alone")
}
