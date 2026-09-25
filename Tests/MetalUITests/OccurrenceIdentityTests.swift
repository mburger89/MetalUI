import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 8, lane 1 (rulings ID-E and ID-F; spec
// `docs/superpowers/specs/2026-09-25-composition-identity-design.md` §3.4–§3.5).
//
// **One element VALUE placed twice.** `State.Box` is a class, so two copies of
// one value share it; each occurrence binds it to its own slot in every phase.
// A handler registered by one occurrence captures that shared box. Since ID-F
// the box remembers every slot it was bound to in one generation, and input
// dispatch names the element it is dispatching to (`StateDispatch.owner`), so
// the handler writes the occurrence whose own id — or an ancestor's — owns the
// slot. SwiftUI: probe `swiftui-composition-identity.swift` arms S1 and S4 (one
// `Counter` value placed twice keeps two storages).
//
// **Not covered here, on purpose:** a closure run OUTSIDE input dispatch (a
// direct call, a timer) still reaches the last-bound occurrence — divergence 71,
// pinned by `IdentityTests`' direct-call test, which this lane leaves unedited.
//
// **`AnyElement` binds** (ID-E): `@State` and `@Environment` inside the erased
// box are seeded in layout, prepaint and paint, like any element's (probe S2,
// S3).

// MARK: - Fixtures

@MainActor
private func slot(_ id: GlobalElementID, _ ordinal: Int) -> GlobalElementID {
    GlobalElementID.child(of: id, at: ordinal, name: ElementID("$state\(ordinal)"))
}

private struct Bump: Action {}

/// One leaf with four `@State` counters, each written by one dispatch kind:
/// a click (and an accessibility press, which runs the same `onClick`), a raw
/// key, a keymap action, an accessibility adjustment. 20 × 20, focusable.
///
/// The handlers capture the property WRAPPERS (`_clicks`, …), which share the
/// class box — the only way an element can write its own state from a handler,
/// since a `mutating` phase cannot capture `self`.
private struct OccurrenceProbe: Element {
    @State var clicks = 0          // ordinal 0
    @State var keys = 0            // ordinal 1
    @State var actions = 0         // ordinal 2
    @State var adjusts = 0         // ordinal 3
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        let clicks = _clicks, keys = _keys, actions = _actions, adjusts = _adjusts
        var handlers = Handlers()
        handlers.onClick = { clicks.wrappedValue += 1 }
        handlers.onKey = { _ in keys.wrappedValue += 1; return true }
        handlers.isFocusable = true
        handlers.actions[ObjectIdentifier(Bump.self)] = { _ in actions.wrappedValue += 1 }
        handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] = { _ in
            adjusts.wrappedValue += 1
        }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// The two occurrences' element ids, in registration (left-to-right) order.
@MainActor
private func occurrenceIDs(_ window: Window) throws -> [GlobalElementID] {
    let ids = window.lastHitboxes.filter { $0.handlers.onClick != nil }.map(\.id)
    try #require(ids.count == 2, "each occurrence registers its own hitbox, got \(ids.count)")
    try #require(ids[0] != ids[1], "control: the two occurrences have distinct ids")
    return ids
}

/// Each occurrence's value of the `@State` at `ordinal`, read from the table.
@MainActor
private func counts(_ window: Window, _ ids: [GlobalElementID], ordinal: Int) -> [Int] {
    ids.map { window.stateTable.peek(slot($0, ordinal), as: Int.self) ?? 0 }
}

@MainActor
private func clickCentre(of id: GlobalElementID, in window: Window, _ platform: FakePlatformWindow) throws {
    let hit = try #require(window.lastHitboxes.last { $0.id == id && $0.handlers.onClick != nil })
    let point = Point(x: hit.bounds.origin.x + Pixels(hit.bounds.size.width.value / 2),
                      y: hit.bounds.origin.y + Pixels(hit.bounds.size.height.value / 2))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

private func keyDown(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

/// A window whose content places ONE `OccurrenceProbe` value twice in a `Row`.
@MainActor
private func twicePlacedWindow() throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: 200) {
        let probe = OccurrenceProbe()
        return Row { probe; probe }
    }
}

// MARK: - O1.1–O1.3: each dispatch site resolves its own occurrence

/// **O1.1.** A click writes the `@State` of the occurrence that was clicked,
/// through a real `Window`'s click dispatch (M1a, M1b).
@MainActor
@Test func aClickWritesTheStateOfTheOccurrenceThatWasClicked() throws {
    let (window, platform) = try twicePlacedWindow()
    window.drawFrameIfNeeded()
    let ids = try occurrenceIDs(window)

    try clickCentre(of: ids[0], in: window, platform)
    #expect(counts(window, ids, ordinal: 0) == [1, 0],
            "occurrence 0 was clicked; last-bound dispatch reads [0, 1]")
    drawUntilClean(window)
    try #require(try occurrenceIDs(window) == ids, "control: ids are stable across frames")

    try clickCentre(of: ids[1], in: window, platform)
    #expect(counts(window, ids, ordinal: 0) == [1, 1])
    // The shape is still counted: dispatch resolves it, it does not remove it.
    #expect(window.stateTable.aliasedStateBoxes > 0)
}

/// **O1.2.** A raw `onKey` writes the state of the focused occurrence that
/// handled the key, not the last-bound one (M1c).
@MainActor
@Test func aKeyHandlerWritesTheStateOfTheOccurrenceThatHandledIt() throws {
    let (window, platform) = try twicePlacedWindow()
    window.drawFrameIfNeeded()
    let ids = try occurrenceIDs(window)
    window.focus(ids[0])
    drawUntilClean(window)
    try #require(window.focusedElement == ids[0], "control: occurrence 0 holds focus")

    #expect(platform.simulateInput(keyDown("x")), "the focused probe claims the key")
    #expect(counts(window, ids, ordinal: 1) == [1, 0],
            "only occurrence 0 handled the key; last-bound dispatch reads [0, 1]")
}

/// **O1.3.** A keymap action, an accessibility press and an accessibility
/// adjustment each write their own occurrence. Each arm has its own counter
/// and targets occurrence 0 (the NOT-last-bound one), so each of M1d, M1e and
/// M1f reddens its own arm only.
@MainActor
@Test func anActionAndAnAccessibilityPressAndAdjustEachWriteTheirOwnOccurrence() throws {
    let (window, platform) = try twicePlacedWindow()
    window.keymap = Keymap { KeyBinding("cmd-i", Bump()) }
    window.drawFrameIfNeeded()
    let ids = try occurrenceIDs(window)

    // Arm 1: a keymap action dispatched along occurrence 0's focus chain.
    window.focus(ids[0])
    drawUntilClean(window)
    #expect(platform.simulateInput(keyDown("i", [.command])), "the action was handled")
    #expect(counts(window, ids, ordinal: 2) == [1, 0], "action arm")
    drawUntilClean(window)

    // Arm 2: an accessibility press on occurrence 0 runs its `onClick`.
    #expect(platform.simulateAccessibilityRequest(.press(AccessibilityNodeID(ids[0]))))
    #expect(counts(window, ids, ordinal: 0) == [1, 0], "press arm")
    drawUntilClean(window)

    // Arm 3: an accessibility increment on occurrence 0.
    #expect(platform.simulateAccessibilityRequest(.increment(AccessibilityNodeID(ids[0]))))
    #expect(counts(window, ids, ordinal: 3) == [1, 0], "adjust arm")
}

// MARK: - O1.4: a Component's state, written from inside its body

/// A `Component` with `@State`, whose body is one clickable box writing it.
private struct CountingComponent: Component {
    @State var n = 0
    var content: some ElementGroup {
        Box().cssWidth(Pixels(20)).cssHeight(Pixels(20)).onClick { n += 1 }
    }
}

/// **O1.4.** A `Component` value placed twice: a click on one occurrence's
/// INNER box writes that occurrence's state. The owner is the inner box; the
/// state's element is its ancestor, the component (M1g: an exact-match-only
/// resolution misses it).
@MainActor
@Test func aComponentPlacedTwiceWritesTheOccurrenceWhoseInnerHandlerRan() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let component = CountingComponent()
        return Row { component; component }
    }
    window.drawFrameIfNeeded()
    let boxes = try occurrenceIDs(window)
    let components = try boxes.map { try #require($0.parent) }
    try #require(components[0] != components[1])

    try clickCentre(of: boxes[0], in: window, platform)
    #expect(counts(window, components, ordinal: 0) == [1, 0],
            "occurrence 0's inner box ran; last-bound dispatch reads [0, 1]")
    drawUntilClean(window)
    try clickCentre(of: boxes[1], in: window, platform)
    #expect(counts(window, components, ordinal: 0) == [1, 1])
}

// MARK: - O1.5: environment

private struct OccurrenceKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var occurrenceProbe: Int {
        get { self[OccurrenceKey.self] }
        set { self[OccurrenceKey.self] = newValue }
    }
}

@MainActor
private final class ReadLog {
    var reads: [Int] = []
}

/// A clickable leaf whose `onClick` records its `@Environment` value.
private struct EnvironmentReader: Element {
    @Environment(\.occurrenceProbe) var probe
    let log: ReadLog
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        let probe = _probe, log = log
        var handlers = Handlers()
        handlers.onClick = { log.reads.append(probe.wrappedValue) }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// **O1.5.** One value under two scopes (7 and 9): each click's handler reads
/// its own occurrence's environment (M1h).
@MainActor
@Test func aDispatchedHandlerReadsItsOwnOccurrencesEnvironment() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ReadLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let reader = EnvironmentReader(log: log)
        return Row {
            reader.environment(\.occurrenceProbe, 7)
            reader.environment(\.occurrenceProbe, 9)
        }
    }
    window.drawFrameIfNeeded()
    let ids = try occurrenceIDs(window)
    try clickCentre(of: ids[0], in: window, platform)
    try clickCentre(of: ids[1], in: window, platform)
    #expect(log.reads == [7, 9], "last-bound dispatch reads [9, 9]")
}

// MARK: - O1.6: a text field's edit and submit callbacks

/// A `Component` holding the field's text (and a submit counter) in `@State`.
private struct FieldComponent: Component {
    @State var text = ""           // ordinal 0
    @State var submits = 0         // ordinal 1
    var content: some ElementGroup {
        TextField("Name", text: text) { text = $0 }.onSubmit { submits += 1 }
    }
}

/// **O1.6.** A field's edit callback, and its submit callback, write the
/// component occurrence that holds the field that was edited (M1i, M1l).
@MainActor
@Test func aTextFieldEditWritesTheOccurrenceThatWasEdited() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let field = FieldComponent()
        return Column { field; field }
    }
    window.drawFrameIfNeeded()
    let fields = window.lastHitboxes.filter { $0.handlers.textInput != nil }
    try #require(fields.count == 2, "each occurrence registers its own field, got \(fields.count)")
    let components = try fields.map { try #require($0.id.parent) }
    try #require(components[0] != components[1])

    // A press focuses a field (TI-B).
    let bounds = fields[0].bounds
    let point = Point(x: bounds.origin.x + Pixels(4), y: bounds.origin.y + Pixels(bounds.size.height.value / 2))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    try #require(window.focusedElement == fields[0].id, "control: occurrence 0's field is focused")

    platform.simulateInput(.textInput("a"))
    let texts = components.map { window.stateTable.peek(slot($0, 0), as: String.self) ?? "" }
    #expect(texts == ["a", ""], "occurrence 0 was edited; last-bound dispatch writes occurrence 1")

    drawUntilClean(window)
    #expect(platform.simulateInput(keyDown("\r")), "return submits the focused field")
    #expect(counts(window, components, ordinal: 1) == [1, 0], "submit arm")
}

// MARK: - O1.7–O1.8: AnyElement binds (ID-E)

@MainActor
private final class IDLog {
    var ids: [GlobalElementID] = []
}

/// Increments its `@State` in every layout and records its id.
private struct LayoutCounter: Element {
    @State var n = 0
    let log: IDLog
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        n += 1
        log.ids.append(id)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

/// **O1.7.** `@State` inside an `AnyElement` persists across frames: three
/// frames of `n += 1` read 3 (M1j).
@MainActor
@Test func stateInsideAnAnyElementPersistsAcrossFrames() throws {
    let table = StateTable()
    let log = IDLog()
    for _ in 0..<3 {
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)),
                          scaleFactor: 1, stateTable: table)
        var root = Row { AnyElement(LayoutCounter(log: log)) }
        frame.render(&root)
    }
    try #require(log.ids.count == 3)
    try #require(Set(log.ids).count == 1, "control: one id across the three frames")
    #expect(table.peek(slot(log.ids[0], 0), as: Int.self) == 3,
            "an unbound @State inside AnyElement writes nothing and reads nil")
}

@MainActor
private final class StampLog {
    var next = 0
    var prepaint: [Int] = []
    var paint: [Int] = []
}

/// Stamps a fresh number into its `@State` in layout, reads it back in
/// prepaint and paint.
private struct StampingLeaf: Element {
    @State var stamp = 0
    let log: StampLog
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.next += 1
        stamp = log.next
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint.append(stamp)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint.append(stamp)
    }
}

/// **O1.8.** One `AnyElement` VALUE placed twice: each occurrence reads its
/// own stamp in prepaint and paint, `[1, 2]` both times (M1k: a layout-only
/// bind reads `[2, 2]`).
@MainActor
@Test func stateInsideAnAnyElementIsReboundForPrepaintAndPaint() {
    let log = StampLog()
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)),
                      scaleFactor: 1, stateTable: StateTable())
    let erased = AnyElement(StampingLeaf(log: log))
    var root = Row { erased; erased }
    frame.render(&root)
    #expect(log.prepaint == [1, 2], "an unbound box reads [0, 0]; a layout-only bind [2, 2]")
    #expect(log.paint == [1, 2])
}

// MARK: - O1.9: a Component's @Environment, the first occurrence's snapshot

/// A `Component` whose `@Environment` value is read by its inner box's click.
private struct EnvironmentComponent: Component {
    @Environment(\.occurrenceProbe) var probe
    let log: ReadLog
    var content: some ElementGroup {
        Box().cssWidth(Pixels(20)).cssHeight(Pixels(20)).onClick { log.reads.append(probe) }
    }
}

/// **O1.9.** One `Component` value holding `@Environment`, placed twice under
/// two scopes (7 and 9): a click on each occurrence's inner box reads its own
/// scope. A `Component` binds only in layout (ID-N item 2), so nothing re-binds
/// occurrence 0 after occurrence 1 — its snapshot exists only because the
/// box records the previous occurrence when a second id binds (`Environment`'s
/// `box.occurrences = [(previous, last)]`; mutation V10 drops it and reads
/// `[9, 9]`). O1.5's `Element` cannot see that line: its prepaint and paint
/// re-bind re-add occurrence 0.
@MainActor
@Test func aComponentsEnvironmentKeepsTheFirstOccurrencesSnapshot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ReadLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        let component = EnvironmentComponent(log: log)
        return Row {
            component.environment(\.occurrenceProbe, 7)
            component.environment(\.occurrenceProbe, 9)
        }
    }
    window.drawFrameIfNeeded()
    let ids = try occurrenceIDs(window)
    try clickCentre(of: ids[0], in: window, platform)
    try clickCentre(of: ids[1], in: window, platform)
    #expect(log.reads == [7, 9], "dropping the first occurrence's snapshot reads [9, 9]")
}

// MARK: - O1.10: a frame built inside a dispatched handler

@MainActor
private final class PaintLog {
    var ids: [GlobalElementID] = []
    var reads: [Int] = []
}

/// Records its id and its `@Environment` value in paint.
private struct EnvironmentPainter: Element {
    @Environment(\.occurrenceProbe) var probe
    let log: PaintLog
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.ids.append(id)
        log.reads.append(probe)
    }
}

/// **O1.10.** A frame built while input dispatch names an owner still reads
/// each occurrence's own per-phase binding: `Frame.render` suspends the
/// dispatch owner for the build (ID-O item 2). Without the suspension,
/// occurrence 1's paint resolves to the owner's occurrence and reads
/// `[7, 7]`.
@MainActor
@Test func aFrameBuiltInsideADispatchedHandlerReadsEachOccurrencesBinding() throws {
    let log = PaintLog()
    let table = StateTable()
    let painter = EnvironmentPainter(log: log)
    func build() -> some Element {
        Row {
            painter.environment(\.occurrenceProbe, 7)
            painter.environment(\.occurrenceProbe, 9)
        }
    }
    func newFrame() -> Frame {
        Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1, stateTable: table)
    }
    var first = build()
    newFrame().render(&first)
    try #require(log.reads == [7, 9], "control: outside dispatch each occurrence reads its scope")
    try #require(log.ids.count == 2 && log.ids[0] != log.ids[1])
    let owner = log.ids[0]

    log.ids = []
    log.reads = []
    var second = build()
    StateDispatch.dispatching(to: owner) { newFrame().render(&second) }
    #expect(log.reads == [7, 9], "the owner leaking into the build reads [7, 7]")
    #expect(StateDispatch.owner == nil, "control: the owner is restored after dispatch")
}

// MARK: - O1.11–O1.12: a later generation forgets the earlier one's occurrences (the closeout)

/// A leaf with one `@State` counter, written by the test through the shared box
/// (the way a captured handler writes it), and one `@Environment` read.
private struct GenerationProbe: Element {
    @State var count = 0
    @Environment(\.occurrenceProbe) var probe
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private func generationFrame(_ table: StateTable) -> Frame {
    Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1, stateTable: table)
}

/// **O1.11 — a `@State` box forgets the previous generation's occurrences**
/// (`ID-F`'s clause "cleared by the first bind of a later generation",
/// `State.bind`'s `box.occurrences = nil`; record §55 §9.2's mutation B2, which
/// reddened nothing at `da2d820`). One value placed twice in frame 1 — `Row { p;
/// Box { p } }`, occurrences at `root/0/0` and `root/0/1/0` — then ONCE in frame
/// 2, as `Row { Box { p } }` at `root/0/0/0`. A write dispatched to frame 2's
/// only occurrence must land on its own slot.
///
/// Red under **B2** (the clearing branch left empty): the box still holds frame
/// 1's two occurrences, the owner's ancestor walk meets the stale `root/0/0`
/// first, and the write lands on that dead slot — own slot `nil`, stale slot 1.
@MainActor
@Test func aStateBoxForgetsTheOccurrencesOfAnEarlierGeneration() throws {
    let table = StateTable()
    let p = GenerationProbe()
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let row0 = GlobalElementID.child(of: root, at: 0, name: nil)
    let stale = row0                                            // frame 1's first occurrence
    let own = GlobalElementID.child(of: row0, at: 0, name: nil) // frame 2's only occurrence

    var first = Row { p; Box { p } }
    generationFrame(table).render(&first)
    try #require(table.aliasedStateBoxes > 0, "control: frame 1 places the value twice")

    var second = Row { Box { p } }
    generationFrame(table).render(&second)
    StateDispatch.dispatching(to: own) { p.count += 1 }

    #expect(table.peek(slot(own, 0), as: Int.self) == 1, "the write lands on frame 2's own occurrence")
    #expect(table.peek(slot(stale, 0), as: Int.self) == nil, "and not on frame 1's dead slot")
}

/// **O1.12 — an `@Environment` box forgets the previous generation's
/// occurrences** (`Environment.bind`'s copy of the same clause). Frame 1 places
/// one value under scopes 7 and 9 — `Row { p(7); Box { p(9) } }` — frame 2 once,
/// under 5, as `Row { Box { p(5) } }`. Read during dispatch to frame 2's
/// occurrence, the environment is 5.
///
/// Red under **B2e** (`Environment.bind`'s clearing branch left empty): the stale
/// occurrence at `root/0/0` resolves first and the read is frame 1's 7.
@MainActor
@Test func anEnvironmentBoxForgetsTheOccurrencesOfAnEarlierGeneration() throws {
    let table = StateTable()
    let p = GenerationProbe()
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let own = GlobalElementID.child(of: GlobalElementID.child(of: root, at: 0, name: nil), at: 0, name: nil)

    var first = Row {
        p.environment(\.occurrenceProbe, 7)
        Box { p.environment(\.occurrenceProbe, 9) }
    }
    generationFrame(table).render(&first)
    try #require(StateDispatch.dispatching(to: GlobalElementID.child(of: root, at: 0, name: nil)) { p.probe } == 7,
                 "control: frame 1 recorded both occurrences, and dispatch picks the first")

    var second = Row { Box { p.environment(\.occurrenceProbe, 5) } }
    generationFrame(table).render(&second)
    #expect(StateDispatch.dispatching(to: own) { p.probe } == 5,
            "frame 2's only occurrence reads its own scope, not frame 1's")
}
