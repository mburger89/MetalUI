import Testing
import MetalUICore
@testable import MetalUI

// C14b-3 lane A (`RW-B`, `RW-C`, `RW-D`, `RW-E`): the `StateTable`'s two read-only entry points, directly. A read or an
// unchanged compared write moves no version, no `writeCount` and taints nothing, but keeps its entry live and joins the
// read journal; a changed compared write is today's `withState` in every respect. Counts and values, never time.

private func rwID(_ names: String...) -> GlobalElementID {
    var current: GlobalElementID?
    for name in names { current = GlobalElementID.child(of: current, at: 0, name: ElementID(name)) }
    return current!
}

/// Opens one recorder of each of the three windows that a write must taint: paint, prepaint and graft.
@MainActor private struct OpenWindows {
    let paint = SubtreeRecorder()
    let prepaint = PrepaintRecorder()
    let graft = GraftRecorder()

    init(on table: StateTable) {
        let log = RetainLog(); log.recorders.append(paint); table.retainLog = log
        let pre = PrepaintLog(); pre.recorders.append(prepaint); table.prepaintLog = pre
        table.contentMemos.journal.open.append(graft)
    }

    var taints: (paint: String?, prepaint: String?, graft: String?) { (paint.taint, prepaint.taint, graft.taint) }
}

/// **Test 2** — `readState`, an equal compared write and a changed one, entry by entry. Red before: the entry points do not
/// exist (compile error). **Mutations:** `readState` bumping the version reddens the first and third arms; the compared
/// write always bumping (or never bumping) reddens the second (or the fourth).
@Test @MainActor func readStateAndAnUnchangedWriteDoNotBumpTheVersion() {
    let table = StateTable()
    let id = rwID("a")

    // Absent: a creation, a write.
    let seeded = table.readState(id, initial: 7)
    #expect(seeded == 7)
    let created = table.entryVersion(id)
    #expect(created != 0 && table.writeCount == 1, "an absent entry is created: version \(created), writes \(table.writeCount)")

    // A read: nothing moves.
    #expect(table.readState(id, initial: 99) == 7)
    #expect(table.entryVersion(id) == created && table.writeCount == 1, "a read moves no version and no write count")

    // An equal write: nothing moves.
    table.withState(id, initial: 0, unchanged: { $0 == $1 }) { $0 = 7 }
    #expect(table.entryVersion(id) == created && table.writeCount == 1, "an equal compared write is a read")

    // A changed write: today's write.
    table.withState(id, initial: 0, unchanged: { $0 == $1 }) { $0 = 8 }
    let changed = table.entryVersion(id)
    #expect(changed > created && table.writeCount == 2, "a changed compared write bumps: \(created) -> \(changed)")
    #expect(table.peek(id, as: Int.self) == 8)

    // The body runs once, the stored value is the body's result.
    var runs = 0
    table.withState(id, initial: 0, unchanged: { $0 == $1 }) { runs += 1; $0 = 9 }
    #expect(runs == 1 && table.peek(id, as: Int.self) == 9, "a changed compared write runs its body once: \(runs)")

    // An absent entry under a compared write is a creation.
    let other = rwID("b")
    table.withState(other, initial: 1, unchanged: { $0 == $1 }) { $0 = 1 }
    #expect(table.entryVersion(other) != 0 && table.writeCount == 4, "an absent entry is created by a compared write")

    // Another type clobbers, as `withState(id, initial:)` does: a write with the initial value.
    let typed = rwID("c")
    table.withState(typed, initial: "text") { $0 = "kept" }
    let before = table.entryVersion(typed)
    #expect(table.readState(typed, initial: 5) == 5, "a read of the wrong type is a creation with the initial value")
    #expect(table.entryVersion(typed) > before)
}

/// The read journal and liveness (`RW-D`, `RW-E`). **Mutation:** `noteRead` not appending reddens the journal arms;
/// `touchLive` not marking (or `noteLiveRead` not calling it) reddens the liveness arms.
@Test @MainActor func aReadJoinsTheJournalAndKeepsItsEntryLive() {
    let table = StateTable()
    let read = rwID("read"), idle = rwID("idle"), slot = rwID("owner", "$ax")
    table.withState(read, initial: 1) { $0 = 1 }
    table.withState(idle, initial: 1) { $0 = 1 }
    table.withState(slot, initial: 1) { $0 = 1 }
    table.sweep()
    #expect(table.readJournal.isEmpty)

    _ = table.readState(read, initial: 0)
    #expect(table.readJournal == [read], "a read is journaled")
    _ = table.peek(idle, as: Int.self)
    _ = table.peek(slot, as: Int.self)
    #expect(table.readJournal == [read, idle], "a peek is journaled; a `$ax` slot has its own channel and is left out")
    table.withState(read, initial: 0, unchanged: { $0 == $1 }) { _ in }
    #expect(table.readJournal.count == 3, "an unchanged compared write is a read too")
    table.withState(read, initial: 0, unchanged: { $0 == $1 }) { $0 = 5 }
    #expect(table.readJournal.count == 3, "a changed one is a write, not a read")

    // Only the read entry was marked: after a sweep it is live, the peeked one is not.
    table.sweep()
    #expect(table.isLive(read), "a read keeps its entry live")
    #expect(!table.isLive(idle), "a peek does not mark")
    #expect(table.readJournal.isEmpty, "the journal is per frame")

    // `touchLive` is a mark without a version and without a journal event.
    let version = table.entryVersion(idle)
    table.touchLive(idle)
    table.sweep()
    #expect(table.isLive(idle) && table.entryVersion(idle) == version && table.readJournal.isEmpty)
}

/// A read-only access fills the three liveness channels (`RW-E`) and the graft journal (`RW-D`). **Mutation:** one channel's
/// append removed per arm.
@Test @MainActor func aReadFillsEveryLivenessChannelAndTheGraftJournal() {
    let table = StateTable()
    let id = rwID("a")
    table.withState(id, initial: 1) { $0 = 1 }
    let windows = OpenWindows(on: table)
    _ = table.readState(id, initial: 0)
    #expect(table.retainLog?.lives == [id], "paint record's liveness channel")
    #expect(table.prepaintLog?.lives == [id], "prepaint ledger's liveness channel")
    let events = table.contentMemos.journal.events
    var liveEvents = 0, readEvents = 0
    for event in events {
        if case .liveState(let live) = event, live == id { liveEvents += 1 }
        if case .stateRead(let read, let version) = event, read == id, version == table.entryVersion(id) { readEvents += 1 }
    }
    #expect(liveEvents == 1 && readEvents == 1, "graft journal: \(liveEvents) live, \(readEvents) read")
    #expect(windows.taints == (nil, nil, nil), "a read taints nothing: \(windows.taints)")
}

/// **Test 3** — a changed compared write taints every open window with `stateWrite`; an equal one taints none. **Mutations
/// (three arms):** the paint, the prepaint or the graft taint removed from `withState`'s write path.
@Test @MainActor func aChangedCompareWriteTaintsEveryOpenWindow() {
    let table = StateTable()
    let id = rwID("a")
    table.withState(id, initial: 1) { $0 = 1 }

    let equal = OpenWindows(on: table)
    table.withState(id, initial: 0, unchanged: { $0 == $1 }) { $0 = 1 }
    #expect(equal.taints == (nil, nil, nil), "an equal write taints nothing: \(equal.taints)")

    table.withState(id, initial: 0, unchanged: { $0 == $1 }) { $0 = 2 }
    #expect(equal.paint.taint == "stateWrite", "paint window: \(String(describing: equal.paint.taint))")
    #expect(equal.prepaint.taint == "stateWrite", "prepaint window: \(String(describing: equal.prepaint.taint))")
    #expect(equal.graft.taint == "stateWrite", "graft window: \(String(describing: equal.graft.taint))")

    // The plain write is unchanged: it taints even when it stores an equal value.
    let plain = OpenWindows(on: table)
    table.withState(id, initial: 0) { $0 = 2 }
    #expect(plain.taints == ("stateWrite", "stateWrite", "stateWrite"), "the plain `withState` keeps its taint: \(plain.taints)")
}

/// A replay's two calls: `touchLive` and `noteRead` (`RW-E`, `RW-D`) leave no version, write or taint, and `noteRead` records the
/// version the entry has now for a graft to check. **Mutation:** `noteRead` journaling a stale version reddens the last arm.
@Test @MainActor func aReplayedReadAndLivenessMoveNoVersionAndTaintNothing() {
    let table = StateTable()
    let id = rwID("a")
    table.withState(id, initial: 1) { $0 = 1 }
    let windows = OpenWindows(on: table)
    let version = table.entryVersion(id), writes = table.writeCount
    table.touchLive(id)
    table.noteRead(id)
    #expect(table.entryVersion(id) == version && table.writeCount == writes && windows.taints == (nil, nil, nil))
    var seen: UInt64?
    for event in table.contentMemos.journal.events { if case .stateRead(_, let v) = event { seen = v } }
    #expect(seen == version, "the journaled version is the entry's current one")
}
