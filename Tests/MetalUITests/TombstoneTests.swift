import Testing
import MetalUICore
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
/// own `prepaint` has run once, so frame 0 builds every row — 100,001 entries
/// for a 100k list against a steady state of 19. Task 1 made the sweep retain,
/// which turns that transient into a permanent one until something reaps it.
///
/// A steady-state test cannot see this: 19 never approaches any threshold, so a
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
