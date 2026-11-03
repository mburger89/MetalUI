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
/// `retainsDepartedValues` forced false (M8b).
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

// MARK: Scroll, focus, animation

private func erStyle(width: Float?, height: Float?, column: Bool = false) -> Style {
    var s = Style()
    if column { s.flexDirection = .column }
    if let width { s.size.width = .length(.pixels(Pixels(width))) }
    if let height { s.size.height = .length(.pixels(Pixels(height))) }
    s.flexShrink = 0
    return s
}

@MainActor private func erOffset(_ window: Window) -> Double? {
    let regions = window.lastScrollRegions
    guard !regions.isEmpty else { return nil }
    let id = regions[0].id
    return window.stateTable.peek(id, as: ScrollState.self)?.offset
}

/// **A swap resets a scroll offset** (`ER-A`; the `departedRoots.contains(id)` conjunct of `resetQueuedEntries`: a
/// `ScrollView` keeps its offset at its own, bare id, with no slot name under it). `AnyElement(ScrollView{..})` swapped
/// for a scroller of another content type starts at 0, and the old one comes back at 0 (its offset entry sits at the departed level's own id, which only `departedRoots.contains(id)` removes). Mutation (M6): that conjunct removed.
@MainActor
@Test func aSwapResetsAScrollOffset() throws {
    let m = LCModel()
    let (window, platform) = try lcWindow(size: 100) {
        Box(style: erStyle(width: 100, height: 100, column: true)) {
            m.flag
                ? AnyElement(ScrollView { Box(style: erStyle(width: 100, height: 1000)) })
                : AnyElement(ScrollView { Stack { Box(style: erStyle(width: 100, height: 1000)) } })
        }
    }
    eraDraw(window)
    _ = platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: Pixels(50), y: Pixels(50)),
                                                        delta: Point(x: Pixels(0), y: Pixels(-40)))))
    eraDraw(window)
    try #require((erOffset(window) ?? 0) > 0, "set up: the scroller scrolled: \(String(describing: erOffset(window)))")
    m.flag = true
    eraDraw(window)
    #expect((erOffset(window) ?? 0) == 0, "the new scroller starts at 0: \(String(describing: erOffset(window)))")
    m.flag = false
    eraDraw(window)
    #expect((erOffset(window) ?? 0) == 0, "and the old scroller comes back at 0, not at the offset it left with: \(String(describing: erOffset(window)))")
}

/// A focusable element (`@State` count, recorded id) of two types, for the focus arm.
private final class ERIDs { var ids: [String: GlobalElementID] = [:] }
private struct ERFocusA: Element {
    let ids: ERIDs
    @State var count = 0
    var elementID: ElementID? { nil }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        ids.ids["a"] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = true
        pass.registerHandlers(handlers, at: bounds, id: id)
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}
private struct ERFocusB: Element {
    let ids: ERIDs
    @State var count = 0
    var elementID: ElementID? { nil }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        ids.ids["b"] = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = true
        pass.registerHandlers(handlers, at: bounds, id: id)
    }
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// **`AVF`.** A focused element inside an `AnyElement` whose type changes loses focus in the swap frame (the old level's
/// `$focus` slot is reset, `IX-I`) and does not get it back when the old type returns. Mutation (M7): `noteNamed` of
/// the level deleted (the old `$focus` slot survives until the reap and focus clears a frame late, or returns).
@MainActor
@Test func aFocusedElementLosesFocusInTheSwapFrameAndDoesNotGetItBack() throws {
    let m = LCModel(), ids = ERIDs()
    let (window, _) = try lcWindow {
        Column { m.flag ? AnyElement(ERFocusB(ids: ids)) : AnyElement(ERFocusA(ids: ids)) }
    }
    eraDraw(window)
    let a = try #require(ids.ids["a"])
    window.focus(a)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == a, "set up: A is focused")
    m.flag = true
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "focus is gone in the swap frame (AVF): \(String(describing: window.focusedElement))")
    m.flag = false
    eraDraw(window)
    #expect(window.focusedElement == nil, "and does not return with the old type (AVF)")
}

/// **`AV6a`.** A swap under `withAnimation` has no ghost and no baseline carried across: B's tile is at its final width in
/// the first animated frame and there is one tile (SwiftUI: the old content's `disappear` fires at once, no removal
/// ghost). Mutation (M10): the level removed, so `$anim` is shared and B interpolates from A's width.
@MainActor
@Test func aSwapUnderAnAnimationIsInstant() throws {
    let m = LCModel()
    let (window, platform) = try lcWindow(size: 200, startsDisplayLink: true) {
        Column {
            m.flag ? AnyElement(Stack { ERB(w: 0) }.frame(width: Pixels(60), height: Pixels(20)))
                   : AnyElement(Stack { ERA(w: 0) }.frame(width: Pixels(10), height: Pixels(20)))
        }
    }
    eraDraw(window)
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 1)) { m.flag = true }
    window.drawFrameIfNeeded()
    platform.simulateTick(timestamp: 100.3)
    let tiles = window.lastScene.rects.filter { $0.bounds.size.height == 20 }
    #expect(tiles.count == 1, "no ghost of A: \(tiles.count) tiles")
    #expect(tiles.first.map { $0.bounds.size.width } == 20, "B's own seed width, not interpolated from A's: \(tiles.map { $0.bounds.size.width })")
}

// MARK: Named positions and direct callers

/// **A named element keeps its name at the position** (`ER-A`): `scrollTo` reaches a `.id("t")` element inside an
/// `AnyElement`, which `recordElementBounds` records under the position's id, not the `$erased` level. A characterization:
/// **mutation M12 (that record taken under the level) leaves it green** (`scrollTo` resolves the name some other way);
/// the mutation is reddened by `aNamedElementKeepsItsNameThroughAScopeWhenErased` (`ScopeForwardTests`) alone.
@MainActor
@Test func aScrollToReachesANamedElementInAnAnyElement() throws {
    let (window, _) = try lcWindow(size: 100) {
        Box(style: erStyle(width: 100, height: 100, column: true)) {
            ScrollViewReader { proxy in
                let _ = ERProxy.proxy = proxy
                ScrollView {
                    Box(style: erStyle(width: 100, height: nil, column: true)) {
                        Box(style: erStyle(width: 100, height: 200))
                        AnyElement(Box(style: erStyle(width: 100, height: 10)).id("t"))
                        Box(style: erStyle(width: 100, height: 1000))
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    window.recordsElementBounds = true
    window.setNeedsRedraw()
    var frames = 0
    while window.needsRedraw && frames < 6 { window.drawFrameIfNeeded(); frames += 1 }
    let proxy = try #require(ERProxy.proxy)
    proxy.scrollTo("t", anchor: .top)
    frames = 0
    while window.needsRedraw && frames < 6 { window.drawFrameIfNeeded(); frames += 1 }
    let id = try #require(window.lastScrollRegions.first).id
    #expect(window.stateTable.peek(id, as: ScrollState.self)?.offset == 200, "the erased named element is the target")
}
@MainActor private enum ERProxy { static var proxy: ScrollViewProxy? }

/// **A direct caller owns its identity** (`ER-B`): a custom-style `Button` lays its erased label out through
/// `AnyElement.requestLayout(_:pass:)` at its own id, and nothing it registers sits under an `$erased` level; the
/// control, an `AnyElement` entered as a group member, does. Mutation (M13b): the level minted in
/// `AnyElement`'s three direct methods.
@MainActor
@Test func aDirectRequestLayoutMintsNoLevel() {
    func erasedLevels(_ id: GlobalElementID) -> Int {
        var count = 0, current: GlobalElementID? = id
        while let c = current {
            if case .named(let name) = c.component, name.name == "$erased" { count += 1 }
            current = c.parent
        }
        return count
    }
    func hitboxes<E: Element>(_ element: E) -> [GlobalElementID] {
        var root = element
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1, stateTable: StateTable(), theme: .light)
        frame.render(&root)
        return frame.hitboxes.map(\.id)
    }
    let button = hitboxes(Column { Button("B") {}.buttonStyle(ERPaddedStyle()) })
    #expect(!button.isEmpty && button.allSatisfy { erasedLevels($0) == 0 }, "a custom-style Button registers at its own id: \(button.map(erasedLevels))")
    let control = hitboxes(Column { AnyElement(Box(style: erStyle(width: 20, height: 20)).onClick {}) })
    #expect(!control.isEmpty && control.allSatisfy { erasedLevels($0) == 1 }, "control: a group-entered AnyElement does: \(control.map(erasedLevels))")
}
private struct ERPaddedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.padding(10).background(.accent)
    }
}

// MARK: Cost

/// **A steady erased position costs one name and no scan** (`ER-A`): over a steady run the reset pass never scans
/// (`lastResetScanWork == 0`), the table holds what an unboxed twin does, and a swap frame is the one that scans
/// (`departedNameResets` +1). Mutation (M3, a key that changes every build: the name always departs; M18, `previous != id` dropped, is an equivalent mutant, record 201).
@MainActor
@Test func aSteadyErasedPositionCostsOneNameAndNoScan() throws {
    func run(erased: Bool, _ steps: [Bool]) -> (scans: [Int], resets: [Int], counts: [Int]) {
        let table = StateTable()
        var scans: [Int] = [], resets: [Int] = [], counts: [Int] = []
        for flag in steps {
            var tree = Row {
                if erased {
                    flag ? AnyElement(Stack { ERB(w: 0) }) : AnyElement(Stack { ERA(w: 0) })
                } else {
                    Stack { ERA(w: 0) }
                }
            }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1, stateTable: table).render(&tree)
            scans.append(table.lastResetScanWork); resets.append(table.departedNameResets); counts.append(table.count)
        }
        return (scans, resets, counts)
    }
    let steady = run(erased: true, [false, false, false, false])
    let twin = run(erased: false, [false, false, false, false])
    #expect(steady.scans[2...] == [0, 0], "a steady frame scans nothing: \(steady.scans)")
    #expect(steady.resets[1] == steady.resets[3], "and departs nothing: \(steady.resets)")
    #expect(steady.counts == twin.counts, "the table holds what the unboxed twin's does: \(steady.counts) vs \(twin.counts)")
    let swapped = run(erased: true, [false, false, false, true])
    #expect(swapped.resets[3] == swapped.resets[2] + 1, "a swap departs the old level once: \(swapped.resets)")
    #expect(swapped.scans[3] > 0, "and is the frame that scans: \(swapped.scans)")
}

// MARK: The residual (ER-C)

/// **`AV3d`, `AV3e`: the residual (divergence 211) and its control.** SwiftUI makes a modifier part of the erased type, so
/// `AnyView(X)` -> `AnyView(X.background(.red))` resets (probe `AV3d`) and so does `.padding` -> `.opacity` (`AV3e`).
/// Here `Stack.background(_:)` is a legacy decoration returning `Self`: it writes the element's own `Style`, the wrapped
/// type does not change and the written 11 is **kept** (arm `background`, pinned wrong on purpose; the second 11 is the
/// background's own rect, also 20 tall). `.padding` and `.opacity` are different `ModifiedContent` layers, a different
/// type: that arm resets to 10, SwiftUI's answer (the control that the key does see a layer change). A fix of the first
/// would key the level by the decoration too.
@MainActor
@Test(arguments: ["background", "paddingToOpacity"]) func aLegacyDecorationIsNotATypeChangeUnderAnAnyElement(arm: String) throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            if arm == "background" {
                m.flag ? AnyElement(Stack { ERA(w: m.value) }.background(.accent)) : AnyElement(Stack { ERA(w: m.value) })
            } else {
                m.flag ? AnyElement(Stack { ERA(w: m.value) }.opacity(0.5)) : AnyElement(Stack { ERA(w: m.value) }.padding(Pixels(4)))
            }
        }
    }
    eraDraw(window)
    m.value = 1
    eraDraw(window)
    let before = eraWidths(window)
    try #require(before == [11], "set up: A is written: \(before)")
    m.flag = true
    eraDraw(window)
    if arm == "background" {
        #expect(eraWidths(window) == [11, 11], "the decoration is not a type change: the 11 is kept (SwiftUI resets, divergence 211): \(eraWidths(window))")
    } else {
        #expect(eraWidths(window) == [10], "a different modifier layer is a different type (AV3e): \(eraWidths(window))")
    }
}
#endif
