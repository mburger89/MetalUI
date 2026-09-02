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
