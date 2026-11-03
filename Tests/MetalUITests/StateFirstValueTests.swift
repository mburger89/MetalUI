#if canImport(Darwin)
import Testing
import MetalUICore
import MetalUITestSupport
@testable import MetalUI

// `FV-A`, `FV-B` (record 199): a `@State` keeps its default's first evaluation for the view's lifetime
// (`StateTable.mark(_:seeding:)`, called by `State.bind`), divergence 125 retired. SwiftUI's side: probe
// `swiftui-lifecycle.swift` `D2` (the monitor), `D3` (a parameter-seeded value type), `D5`/`D5b` (the `AnyView`
// swap). The monitor test itself is `LifecycleTests`' `aNeverWrittenStateDefaultKeepsItsFirstEvaluationForTheViewsLifetime`.

private func id(_ names: String...) -> GlobalElementID {
    var current: GlobalElementID?
    for name in names { current = GlobalElementID.child(of: current, at: 0, name: ElementID(name)) }
    return current!
}

/// `D3`'s shape: a value-type `@State` seeded from a changing parent parameter through `init`; the tile is `10 + s` wide.
private struct FVSeeded: Component {
    let v: Int
    @State var s: Int
    init(v: Int) { self.v = v; _s = State(wrappedValue: v) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(10 + s)), height: Pixels(20)).background(.accent)
    }
}

/// `D5`'s two types: each an `Int` `@State` of its own seed (10 and 20), drawn as its width.
private struct FVSeedA: Component {
    @State var n: Int
    init() { _n = State(wrappedValue: 10) }
    var content: some ElementGroup { Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent) }
}
private struct FVSeedB: Component {
    @State var n: Int
    init() { _n = State(wrappedValue: 20) }
    var content: some ElementGroup { Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent) }
}
/// `D5b`'s A: the same seed 10, written to 11 in `onAppear`.
private struct FVWriterA: Component {
    @State var n: Int
    init() { _n = State(wrappedValue: 10) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent).onAppear { n = 11 }
    }
}

/// The widths of the 20-tall tiles in paint order.
@MainActor private func fvWidths(_ window: Window) -> [Float] {
    window.lastScene.rects.filter { $0.bounds.size.height == 20 }.map { $0.bounds.size.width }
}

// MARK: The first value is kept

/// **`D3`** (`FV-A`). A value-type `@State` seeded from a parent parameter does not follow it: SwiftUI reads `s=0`
/// at `v=0, 1, 2` (probe `D3`), and so does this. Mutation: the seed overwrites (`mark(_:seeding:)` storing on a
/// present entry too) reads 15, then 17.
@MainActor
@Test func aSeedFromAParentParameterDoesNotFollowIt() throws {
    let m = LCModel()
    m.shown = true
    let (window, _) = try lcWindow { Column { if m.shown { FVSeeded(v: m.value) } } }
    window.drawFrameIfNeeded()
    try #require(fvWidths(window) == [10])
    m.value = 5
    window.drawFrameIfNeeded()
    #expect(fvWidths(window) == [10], "the first value is kept, not the parent's 5 (D3): \(fvWidths(window))")
    m.value = 9
    window.drawFrameIfNeeded()
    #expect(fvWidths(window) == [10], "and still: \(fvWidths(window))")
}

/// **`ID-C`, `ID-R`, `DD-C` over a seeded entry.** Content an evaluated conditional, a changed `.id` or a shrunk loop
/// removes starts fresh when it returns: the seed is taken again from the new parameter, not kept. The `loop` arm keeps
/// index 0's entry while index 1's is reset. Mutations, one arm each: `noteAbsent` not queueing its slot (`if`),
/// `noteNamed` not queueing the departed name (`id`), `noteLoop` not queueing the dropped extent (`loop`).
@MainActor
@Test(arguments: ["if", "id", "loop"]) func aReturningSeededStateStartsFresh(arm: String) throws {
    let m = LCModel()
    m.shown = true
    m.value = 1
    let (window, _) = try lcWindow {
        Column {
            if arm == "if" { if m.shown { FVSeeded(v: m.value) } }
            if arm == "id" { FVSeeded(v: m.value).id("k\(m.key)") }
            if arm == "loop" { ForEach(0..<m.count, id: \.self) { i in FVSeeded(v: m.value + i) } }
        }
    }
    m.count = 2
    window.drawFrameIfNeeded()
    try #require(fvWidths(window) == (arm == "loop" ? [11, 12] : [11]), "set up: \(fvWidths(window))")
    m.value = 7
    window.drawFrameIfNeeded()
    try #require(fvWidths(window) == (arm == "loop" ? [11, 12] : [11]), "set up: the seeds are kept: \(fvWidths(window))")
    switch arm {
    case "if": m.shown = false
    case "id": m.key = 1
    default: m.count = 1
    }
    window.drawFrameIfNeeded()
    if arm == "if" { try #require(fvWidths(window) == []) }
    if arm == "loop" { try #require(fvWidths(window) == [11], "set up: index 0 stays: \(fvWidths(window))") }
    switch arm {
    case "if": m.shown = true
    case "id": m.key = 0
    default: m.count = 2
    }
    window.drawFrameIfNeeded()
    if arm == "loop" {
        #expect(fvWidths(window) == [11, 18], "index 0 kept its seed, index 1 was reset and seeded again: \(fvWidths(window))")
    } else {
        #expect(fvWidths(window) == [17], "seeded again from the parameter 7 (the id arm: ID-R reset the name when it departed): \(fvWidths(window))")
    }
}

// MARK: A seed is not a write

/// **`FV-A`, `FV-B`.** `mark(_:seeding:)` on an absent slot stores the value and is not a write: no `isDirty`, no
/// `onWrite`, no `writeCount`; it is live, versioned from the write counter (nonzero, and strictly above every number
/// handed out before, also when the slot is reset and seeded again), and a second seed of the same slot keeps the
/// first value and its version. Mutations: the seed through `write` (`isDirty`, `onWrite`); `version: 0` (the
/// version arm); `versionCounter` read but not advanced (the strictly-above arm).
@MainActor
@Test func aSeedIsNotAWriteAndIsVersioned() {
    let table = StateTable()
    var fired = 0
    table.onWrite = { fired += 1 }
    let slot = id("cond")
    let state = GlobalElementID.child(of: slot, at: 0, name: ElementID("$state0"))
    table.noteProduced(slot)
    table.mark(state, seeding: 5)
    #expect(table.peek(state, as: Int.self) == 5)
    #expect(table.isLive(state))
    #expect(table.writeCount == 0 && !table.isDirty && fired == 0, "writeCount \(table.writeCount), dirty \(table.isDirty), fired \(fired)")
    let first = table.entryVersion(state)
    #expect(first > 0, "an entry has a version; 0 is no entry")
    table.mark(state, seeding: 9)
    #expect(table.peek(state, as: Int.self) == 5 && table.entryVersion(state) == first, "a second seed keeps the first value and version")
    table.sweep()

    // Reset by an evaluated conditional that produced nothing, then produced again: a fresh entry, a new number.
    table.noteAbsent(slot)
    table.sweep()
    #expect(table.peek(state, as: Int.self) == nil, "set up: the reset removed the entry")
    table.withState(id("other"), initial: 0) { $0 = 1 }       // takes the next number
    let other = table.entryVersion(id("other"))
    table.noteProduced(slot)
    table.mark(state, seeding: 8)
    let second = table.entryVersion(state)
    #expect(table.peek(state, as: Int.self) == 8)
    #expect(second > other && second > first, "versions never repeat: \(first), \(other), \(second)")
    #expect(table.writeCount == 1 && fired == 0, "only the one withState wrote: \(table.writeCount), \(fired)")
}

/// **`FV-B` at the window.** A first frame that seeds a `@State` leaves the window clean: the same frame count, no
/// redraw owed, `writeCount` equal to a twin with no `@State`. Mutation: the seed through `write` (`onWrite` raises
/// `needsRedraw` and `writeCount` moves).
@MainActor
@Test func aSeedWritesNothingAndLeavesTheWindowClean() throws {
    let (seeded, _) = try lcWindow { Column { FVSeeded(v: 3) } }
    let (plain, _) = try lcWindow { Column { Box().frame(width: Pixels(13), height: Pixels(20)).background(.accent) } }
    seeded.drawFrameIfNeeded()
    plain.drawFrameIfNeeded()
    try #require(fvWidths(seeded) == [13] && fvWidths(plain) == [13], "set up")
    #expect(seeded.stateTable.writeCount == plain.stateTable.writeCount,
            "a seed is not a write: \(seeded.stateTable.writeCount) vs \(plain.stateTable.writeCount)")
    #expect(!seeded.stateTable.isDirty)
    #expect(!seeded.needsRedraw, "nothing owes another frame")
    #expect(seeded.stateTable.count == plain.stateTable.count + 1, "one entry per declared @State")
}

// MARK: The bound (`TB-AH`)

private struct FVListItem: Identifiable { let id: String }

@MainActor private enum FVSerial {
    static var last = 0
    static func next() -> Int { last += 1; return last }
}

/// A row with a never-written `@State` seeded from a counter, so every build constructs a different default and the
/// slot's value says which build's default it holds. It writes nothing.
private struct FVSeedRow: Element {
    @State var serial: Int
    init() { _serial = State(wrappedValue: FVSerial.next()) }
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.lowerLegacyNode(Style(), declared: Style(), children: [], site: .box), ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
                        pass: inout PaintPass) {}
}

/// **`TB-AH` for a seeded slot** (`FV-A`; `TombstoneTests`' excursion with a row that is never written). A `List` row
/// outside the window is not evaluated, so its seeded entry is a tombstone: it keeps its first value across an
/// excursion of `staleAfterGenerations` generations and is reaped (the table is over `sweepThreshold`) by one longer,
/// after which the row is seeded again from the build that returns. Mutation: `staleAfterGenerations` 2 to 3 (the long
/// row keeps its first value).
@MainActor
@Test func aSeededStateInAListRowHoldsWithinTheBoundButNotPastIt() throws {
    func px(_ v: Float) -> Pixels { Pixels(v) }
    let data = (0..<12).map { FVListItem(id: "row\($0)") }
    let shortIndex = 4, longIndex = 7
    let table = StateTable()
    let paddingIDs = (0..<260).map { GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)")) }
    for id in paddingIDs { table.write(id, 0) }
    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data, rowHeight: px(20)) { _ in FVSeedRow() }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    let contentSize = Size<Pixels>(width: px(100), height: px(20))
    func renderFrame(offset: Double?) {
        for id in paddingIDs { table.mark(id) }
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        Frame(contentSize: contentSize, scaleFactor: 1, stateTable: table).render(&tree)
    }
    let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
    func slotID(_ index: Int) -> GlobalElementID {
        let box = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[index].id))
        return GlobalElementID.child(of: GlobalElementID.child(of: box, at: 0, name: nil), at: 0, name: ElementID("$state0"))
    }
    let shortSlot = slotID(shortIndex), longSlot = slotID(longIndex)

    renderFrame(offset: nil)                    // cold: every row built
    let shortFirst = try #require(table.peek(shortSlot, as: Int.self), "set up: the short row was seeded")
    let longFirst = try #require(table.peek(longSlot, as: Int.self), "set up: the long row was seeded")
    renderFrame(offset: 100); renderFrame(offset: 100)
    #expect(table.peek(shortSlot, as: Int.self) == shortFirst && table.peek(longSlot, as: Int.self) == longFirst,
            "built again, both keep their first value")
    renderFrame(offset: 0); renderFrame(offset: 0)      // both out for exactly `staleAfterGenerations`
    renderFrame(offset: 80)                              // the short row returns; the long row crosses the bound
    #expect(table.isLive(shortSlot))
    #expect(table.peek(shortSlot, as: Int.self) == shortFirst, "within the bound the seeded entry holds its first value")
    renderFrame(offset: 140)                             // the long row returns
    #expect(table.isLive(longSlot))
    let longAgain = try #require(table.peek(longSlot, as: Int.self))
    #expect(longAgain != longFirst, "past the bound the entry was reaped and the row is seeded again: \(longFirst) then \(longAgain)")
}

// MARK: Allocation (`PA-E`)

private struct FVWide { var a = 1, b = 2, c = 3, d = 4, e = 5 }

/// **`PA-E` over the seeding spelling.** A steady `mark(_:seeding:)` of present ids allocates what `mark` does: the
/// seed is boxed into `Any` only on a miss. Counted as a difference to the plain `mark` at 100 and 1000 calls with a
/// value wide enough that boxing it allocates (40 bytes). Mutation: `initial()` boxed before the lookup (the
/// difference is one allocation a call).
@MainActor
@Test func aSteadySeedingMarkAllocatesNothingMore() throws {
    let table = StateTable()
    let ids = (0..<1000).map { id("e\($0)") }
    for key in ids { table.mark(key, seeding: FVWide()) }
    for key in ids { table.mark(key, seeding: FVWide()) }       // warm: `marked` and the journal reach their size
    func seeding(_ n: Int) throws -> Int {
        let slice = Array(ids[0..<n])
        return try #require(countAllocations { for key in slice { table.mark(key, seeding: FVWide()) } })
    }
    func plain(_ n: Int) throws -> Int {
        let slice = Array(ids[0..<n])
        return try #require(countAllocations { for key in slice { table.mark(key) } })
    }
    let small = try seeding(100) - plain(100), large = try seeding(1000) - plain(1000)
    #expect(small <= 10 && large <= 10, "seeding a present slot allocated more than mark: \(small) at 100, \(large) at 1000")
}

// MARK: `AnyElement` (divergence 210)

/// **`D5`, `D5b`: pinned wrong on purpose (divergence 210).** An `AnyView` whose wrapped type changes at one position
/// resets its state in SwiftUI: `SeedB` reads its own seed 20 after `SeedA` (10), and after a `SeedA` that wrote 11
/// (probes `D5`, `D5b`). An `AnyElement` has no type tracking, so both share `$state0` under the one id: `SeedB` reads
/// `SeedA`'s 10 (never written: the case `FV-A` made newly wrong, 20 before it) and 11 (written: always so). A fix
/// that resets on a type change reddens both arms: read divergence 210 first.
@MainActor
@Test(arguments: ["seeded", "written"]) func anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced(arm: String) throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            if arm == "seeded" {
                m.flag ? AnyElement(Stack { FVSeedB() }) : AnyElement(Stack { FVSeedA() })
            } else {
                m.flag ? AnyElement(Stack { FVSeedB() }) : AnyElement(Stack { FVWriterA() })
            }
        }
    }
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    try #require(fvWidths(window) == (arm == "seeded" ? [10] : [11]), "set up: A reads its own value: \(fvWidths(window))")
    m.flag = true
    window.drawFrameIfNeeded()
    #expect(fvWidths(window) == (arm == "seeded" ? [10] : [11]),
            "B reads A's slot (divergence 210; SwiftUI resets and reads 20): \(fvWidths(window))")
}
#endif
