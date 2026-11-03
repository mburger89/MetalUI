#if canImport(Darwin)
import Testing
import Observation
import MetalUICore
import MetalUITestSupport
@testable import MetalUI

// `ER-A`..`ER-D` (record 201): an `AnyElement` whose wrapped type changes at one position is a different element, as an
// `AnyView` whose type changes is in SwiftUI: its state, focus, `.task`, lifecycle and memos reset, and a swap back starts
// fresh. SwiftUI's side is `docs/probes/swiftui-lifecycle.swift` arms `D5`, `D5b`, `AV1`..`AV6c` and
// `swiftui-key-focus.swift` `AVF` (header readings); MetalUI's mechanism is `ElementGroup.swift`'s `AnyElement` group
// entry (a keyed `$erased` level under the position, noted through `noteNamed`).
//
// **Every instrument declares its stored properties in one order (`w`, `height`, `log`, `n`)**: the `@State` slot is
// named by its property's position (`$state<k>`), so two types whose `@State` sits at different positions never shared
// a slot and could not show divergence 210 at all (the first run of this file read `[20]` with the old code).
//
// The instruments: `ERA`, `ERB`, `ERS` are three distinct `Component` types with an `Int` `@State` of seed 10, 20 and 30,
// drawn as the width of a tile; an `onChange(of: w)` writes 11, 21 and 31, so a state is written by a model step (input)
// and not by an appearance. `ERGen<T>` is one generic type with a seed of 10.

private let eraHeights: [Float] = [20, 21, 22]

/// The widths of the tiles of one height, in paint order.
@MainActor private func eraWidths(_ window: Window, height: Float = 20) -> [Float] {
    window.lastScene.rects.filter { $0.bounds.size.height == height }.map { $0.bounds.size.width }
}

private struct ERA: Component {
    let w: Int
    var height: Float = 20
    var log: LCLog?
    @State var n: Int
    init(w: Int = 0, height: Float = 20, log: LCLog? = nil) {
        self.w = w; self.height = height; self.log = log
        _n = State(wrappedValue: 10)
    }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(height)).background(.accent)
            .onChange(of: w) { n = 11 }
            .onAppear { log?.add("appear A n=\(n)") }
            .onDisappear { log?.add("disappear A n=\(n)"); n = 99 }
    }
}

private struct ERB: Component {
    let w: Int
    var height: Float = 20
    var log: LCLog?
    @State var n: Int
    init(w: Int = 0, log: LCLog? = nil) { self.w = w; self.log = log; _n = State(wrappedValue: 20) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent)
            .onChange(of: w) { n = 21 }
            .onAppear { log?.add("appear B n=\(n)") }
            .onDisappear { log?.add("disappear B n=\(n)") }
    }
}

private struct ERS: Component {
    let w: Int
    var height: Float = 22
    var log: LCLog?
    @State var n: Int
    init(w: Int = 0) { self.w = w; _n = State(wrappedValue: 30) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(22)).background(.accent).onChange(of: w) { n = 31 }
    }
}

private struct ERGen<T>: Component {
    let w: Int
    var height: Float = 20
    var log: LCLog?
    @State var n: Int
    init(_ type: T.Type, w: Int = 0) { self.w = w; _n = State(wrappedValue: 10) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent).onChange(of: w) { n = 11 }
    }
}

@MainActor private func eraDraw(_ window: Window) {
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
}

// MARK: The swap resets

/// **`D5`, `D5b` (probes), `ER-A`: the inverted pin.** An `AnyView` whose wrapped type changes resets its state: `SeedB`
/// reads its own 20 after `SeedA` (10, never written: arm `seeded`) and after a `SeedA` that was written to 11 (arm
/// `written`). This replaces `anAnyElementSwapKeepsTheSlotOfTheTypeItReplaced`, the pin of divergence 210, which read
/// `[10]` and `[11]`. Mutation (record 201, M1): the wrapped element laid out under the position's own id (no
/// `$erased` level).
@MainActor
@Test(arguments: ["seeded", "written"]) func anAnyElementSwapReadsTheNewTypesOwnValue(arm: String) throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column { m.flag ? AnyElement(Stack { ERB(w: m.value) }) : AnyElement(Stack { ERA(w: m.value) }) }
    }
    eraDraw(window)
    if arm == "written" {
        m.value = 1
        eraDraw(window)
    }
    try #require(eraWidths(window) == (arm == "seeded" ? [10] : [11]), "set up: A reads its own value: \(eraWidths(window))")
    m.flag = true
    eraDraw(window)
    #expect(eraWidths(window) == [20], "B reads its own seed (D5, D5b), not A's slot: \(eraWidths(window))")
}

/// **`AV1`.** A written 11, swapped to B, swapped back: A reads 10, not its old 11 (SwiftUI does not revive), and a B
/// written between reads its seed again on the way back from A. Mutation (M2, the `Mirror` of the M15 shape): the
/// `$erased` level keyed by the type but `noteNamed` not called, so the old entry survives under its own level and
/// comes back.
@MainActor
@Test(arguments: ["a-written", "b-written"]) func anAnyElementSwapBackStartsFresh(arm: String) throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column { m.flag ? AnyElement(Stack { ERB(w: m.value) }) : AnyElement(Stack { ERA(w: m.value) }) }
    }
    eraDraw(window)
    if arm == "a-written" {
        m.value = 1
        eraDraw(window)
        try #require(eraWidths(window) == [11])
        m.flag = true
        eraDraw(window)
        try #require(eraWidths(window) == [20], "set up: B is fresh: \(eraWidths(window))")
        m.flag = false
        eraDraw(window)
        #expect(eraWidths(window) == [10], "A reads its seed again, not the 11 it left with (AV1): \(eraWidths(window))")
    } else {
        m.flag = true
        eraDraw(window)
        m.value = 1
        eraDraw(window)
        try #require(eraWidths(window) == [21], "set up: B written: \(eraWidths(window))")
        m.flag = false
        eraDraw(window)
        m.flag = true
        eraDraw(window)
        #expect(eraWidths(window) == [20], "B reads its seed again, not the 21 it left with (AV1): \(eraWidths(window))")
    }
}

/// **`AV2`, `AV3c`.** The same wrapped type keeps its state: two `AnyElement(...)` expressions of one `E` in a ternary,
/// with a different parameter, are one element (no `appear`/`disappear`, the written 11 stays).
/// Mutation (M3): the level keyed by a per-instance counter.
@MainActor
@Test func theSameWrappedTypeKeepsItsState() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            m.flag ? AnyElement(Stack { ERA(w: m.value, height: 21, log: log) })
                   : AnyElement(Stack { ERA(w: m.value, height: 20, log: log) })
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    try #require(eraWidths(window) == [11])
    _ = log.take()
    m.flag = true
    eraDraw(window)
    #expect(eraWidths(window, height: 21) == [11], "a rebuild of the same type keeps its 11 (AV2): \(eraWidths(window, height: 21))")
    #expect(log.take().isEmpty, "and fires nothing: \(log.entries)")
    m.flag = false
    eraDraw(window)
    #expect(eraWidths(window) == [11] && log.take().isEmpty, "and back: \(eraWidths(window))")
}

/// **`AV3a`.** `Gen<Int>` and `Gen<String>` are two types: the swap resets. Mutation (M4): the level keyed by
/// `String(describing: E.self)` cut at `<`.
@MainActor
@Test func differingGenericsAreDifferentTypes() throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            m.flag ? AnyElement(Stack { ERGen(String.self, w: m.value) }) : AnyElement(Stack { ERGen(Int.self, w: m.value) })
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    try #require(eraWidths(window) == [11])
    m.flag = true
    eraDraw(window)
    #expect(eraWidths(window) == [10], "Gen<String> is a new element with its own seed (AV3a): \(eraWidths(window))")
}

/// **`AV3b`.** `Stack` and `Row` around one leaf are two types: the leaf's state resets with the swap.
@MainActor
@Test func aContainerOfAnotherTypeResetsItsDescendants() throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            m.flag ? AnyElement(Row { ERA(w: m.value) }) : AnyElement(Column { ERA(w: m.value) })
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    try #require(eraWidths(window) == [11])
    m.flag = true
    eraDraw(window)
    #expect(eraWidths(window) == [10], "the leaf under a Row is fresh (AV3b): \(eraWidths(window))")
}

/// **`AV4a`, `AV4b`.** A nested `AnyElement` resets only what changed: an inner swap resets the inner element and keeps
/// its sibling (`inner`); an outer swap resets an inner element of an unchanged type (`outer`). Mutation (M5): the inner
/// entry skips the `$erased` level.
@MainActor
@Test(arguments: ["inner", "outer"]) func aNestedAnyElementResetsOnlyWhatChanged(arm: String) throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            if arm == "inner" {
                AnyElement(Column {
                    m.flag ? AnyElement(Stack { ERB(w: m.value) }) : AnyElement(Stack { ERA(w: m.value) })
                    ERS(w: m.value)
                })
            } else {
                m.flag ? AnyElement(Row { AnyElement(Stack { ERA(w: m.value) }) })
                       : AnyElement(Column { AnyElement(Stack { ERA(w: m.value) }) })
            }
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    try #require(eraWidths(window) == [11], "set up: \(eraWidths(window))")
    m.flag = true
    eraDraw(window)
    if arm == "inner" {
        #expect(eraWidths(window) == [20], "the inner swap resets the inner element (AV4a): \(eraWidths(window))")
        #expect(eraWidths(window, height: 22) == [31], "and keeps the sibling: \(eraWidths(window, height: 22))")
    } else {
        #expect(eraWidths(window) == [10], "an outer type change resets the inner AnyElement (AV4b): \(eraWidths(window))")
    }
}

// MARK: Lifecycle and tasks

/// **`AV5a`, `AV5b`, `AV5c`.** A swap runs the old content's `onDisappear` once and the new content's `onAppear`
/// once (`LC-F` order, appears first: SwiftUI runs the disappearance first, a new divergence row, `ER-C`); the old
/// `onDisappear` reads the value A left with (11, `LC-I`'s overlay) and its write (99) is lost, so A reads 10 on the
/// way back; a modifier outside the `AnyElement` fires nothing. Mutations: the level removed (M1: nothing fires);
/// `retainsDepartedValues` forced false (M8b: the disappear reads the seed).
@MainActor
@Test func aSwapRunsDisappearAndAppearOnce() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            (m.flag ? AnyElement(Stack { ERB(w: m.value, log: log) }) : AnyElement(Stack { ERA(w: m.value, log: log) }))
                .onAppear { log.add("outer appear") }.onDisappear { log.add("outer disappear") }
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    try #require(eraWidths(window) == [11])
    _ = log.take()
    m.flag = true
    eraDraw(window)
    #expect(log.take() == ["appear B n=20", "disappear A n=11"], "once each, A read its own 11 (AV5a, AV5b)")
    #expect(eraWidths(window) == [20])
    m.flag = false
    eraDraw(window)
    #expect(log.take() == ["appear A n=10", "disappear B n=20"], "and back, A starts at its seed (the 99 written in onDisappear is lost)")
    #expect(eraWidths(window) == [10], "\(eraWidths(window))")
}

/// **`AV5d`.** A running `.task` is cancelled by the swap and the new content's task starts; a rebuild of the same type
/// does not restart it. Mutation (M9): the level removed (the task keeps running).
@MainActor
@Test func aSwapCancelsTheOldTaskAndStartsTheNew() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            m.flag ? AnyElement(Stack { ERTaskB(tick: m.value, log: log) }) : AnyElement(Stack { ERTaskA(tick: m.value, log: log) })
        }
    }
    eraDraw(window)
    try #require(log.take() == ["start A"])
    m.value = 1                      // a rebuild with no swap
    eraDraw(window)
    #expect(log.take().isEmpty, "a rebuild of the same type restarts nothing: \(log.entries)")
    m.flag = true
    eraDraw(window)
    #expect(log.take().sorted() == ["cancel A", "start B"], "the old task is cancelled and the new one started (AV5d)")
}

private struct ERTaskA: Component {
    let tick: Int
    var height: Float = 20
    let log: LCLog
    var content: some ElementGroup {
        Box().frame(width: Pixels(10), height: Pixels(20)).background(.accent)
            .task { log.add("start A"); await untilCancelled { log.add("cancel A") } }
    }
}
private struct ERTaskB: Component {
    let tick: Int
    var height: Float = 20
    let log: LCLog
    var content: some ElementGroup {
        Box().frame(width: Pixels(10), height: Pixels(20)).background(.accent)
            .task { log.add("start B"); await untilCancelled { log.add("cancel B") } }
    }
}
#endif
