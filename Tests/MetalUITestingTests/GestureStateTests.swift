@testable import MetalUI
import MetalUITesting
import Testing

// G1 lane 1 — `@GestureState` and `Gesture.updating(_:body:)` (rulings `GS-A`…`GS-F`, spec
// `docs/superpowers/specs/2026-10-21-gesture-state-design.md` §5 lane 1). Everything runs through the real `Window`
// over `MetalUITesting` (portable: macOS, Linux, Windows); nothing sleeps; the clock is `TestWindow`'s. Probe lines
// (`docs/probes/swiftui-gesture-state.swift`, header) are named by arm: G1…G13, recorded 2026-10-21; the critic
// round could not re-take `G7`/`G7e` (screen locked, `GS-O`), so the two simultaneous-writer pins and divergence
// 645's row stand on the recorded lines. Geometry: a 400 × 300 window, a 200 × 200 chip centred at (200, 150).

@MainActor private final class GSLog {
    var entries: [String] = []
    var resets = 0
    var transactions: [Bool] = []
    func add(_ entry: String) { entries.append(entry) }
    /// The log with consecutive duplicates collapsed: one event may build more than once (a settle build).
    var distinct: [String] {
        var out: [String] = []
        for entry in entries where out.last != entry { out.append(entry) }
        return out
    }
}

private func at(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }
private let center = at(200, 150)
private func down(_ p: Point<Pixels> = center, count: Int = 1) -> InputEvent {
    .mouseDown(MouseEvent(position: p, clickCount: count))
}
private func dragged(_ p: Point<Pixels>) -> InputEvent { .mouseDragged(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels> = center, count: Int = 1) -> InputEvent {
    .mouseUp(MouseEvent(position: p, clickCount: count))
}
private func odown(_ p: Point<Pixels> = center) -> InputEvent {
    .otherMouseDown(MouseEvent(position: p, clickCount: 1, buttonNumber: 2))
}
private func odragged(_ p: Point<Pixels>) -> InputEvent {
    .otherMouseDragged(MouseEvent(position: p, clickCount: 1, buttonNumber: 2))
}
private func moved(_ p: Point<Pixels>) -> InputEvent { .mouseMoved(MouseEvent(position: p)) }

@MainActor private func record(_ log: GSLog, _ label: String, _ value: Int) -> Int {
    log.add("\(label) s=\(value)")
    return value
}

/// A window whose one child is `chip` (a `Component` is not an `Element`; a `Column` roots it).
@MainActor private func chipWindow<C: ElementGroup>(_ chip: @escaping @MainActor () -> C) throws -> TestWindow {
    try harnessWindow { Column { chip() } }
}

@MainActor private func chipBody<G: Gesture>(_ log: GSLog, _ label: String, _ s: Int, _ gesture: G) -> some ElementGroup {
    Rectangle().frame(width: Pixels(200 + Float(record(log, label, s) * 0)), height: Pixels(200)).gesture(gesture)
}

// MARK: - 1: a drag moves a view and snaps back (G1)

private struct DragChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
    }
}

/// **1.1** (`G1`). Press, two moves, release: the body reads 1, 2, 3 and 0 at the release frame.
/// Mutation: delete `finished`'s queue in `act` (drag arm) and in `fail` → stays at 3.
@Test @MainActor func aDragUpdatingMovesAViewDuringTheDragAndSnapsBackAtTheRelease() throws {
    let log = GSLog()
    let window = try chipWindow { DragChip(log: log) }
    #expect(log.distinct == ["body s=0"], "\(log.distinct)")
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick()
    window.send(dragged(at(220, 150))); window.tick()
    window.send(up(at(220, 150))); window.tick()
    #expect(log.distinct == ["body s=0", "body s=1", "body s=2", "body s=3", "body s=0"], "\(log.distinct)")
}

// MARK: - 2, 3: order against onChanged and onEnded (G8, G13, G6)

private struct OrderChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0)
            .updating($s) { _, st, _ in st += 1 }
            .onChanged { _ in log.add("changed s=\(s)") }
            .onEnded { _ in log.add("ended s=\(s)") })
    }
}

/// **1.2** (`G8`). `onEnded` reads the state already reset; `onChanged` declared after `updating` reads the new value.
/// Mutation: queue `finished` after the ended callback.
@Test @MainActor func theResetRunsBeforeOnEndedAndOnChangedReadsTheWrite() throws {
    let log = GSLog()
    let window = try chipWindow { OrderChip(log: log) }
    window.send(down()); window.send(dragged(at(210, 150))); window.send(up(at(210, 150))); window.tick()
    let calls = log.entries.filter { !$0.hasPrefix("body") }
    #expect(calls == ["changed s=1", "changed s=2", "ended s=0"], "\(calls)")
}

private struct ChangedFirstChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0)
            .onChanged { _ in log.add("changed s=\(s)") }
            .updating($s) { _, st, _ in st += 1 })
    }
}

private struct TwoStatesChip: Component {
    let log: GSLog
    @GestureState var a = 0
    @GestureState var b = 0
    var content: some ElementGroup {
        chipBody(log, "body", a + b * 100, DragGesture(minimumDistance: 0)
            .updating($a) { _, st, _ in st += 1; log.add("upd a") }
            .updating($b) { _, st, _ in st += 10; log.add("upd b") })
    }
}

/// **1.3** (`G13`, `G6`). `onChanged` declared before `updating` runs first and reads the old value; two updates run in
/// declaration order and both writes are seen together, then both reset. Mutation: always run updates first.
@Test @MainActor func updatingOrderFollowsDeclarationAgainstOnChanged() throws {
    let log = GSLog()
    let window = try chipWindow { ChangedFirstChip(log: log) }
    window.send(down()); window.send(dragged(at(210, 150))); window.send(up(at(210, 150))); window.tick()
    let calls = log.entries.filter { !$0.hasPrefix("body") }
    #expect(calls == ["changed s=0", "changed s=1"], "onChanged declared first reads the value before the write: \(calls)")

    let two = GSLog()
    let w2 = try chipWindow { TwoStatesChip(log: two) }
    w2.send(down()); w2.tick()
    w2.send(dragged(at(210, 150))); w2.tick()
    w2.send(up(at(210, 150))); w2.tick()
    #expect(two.entries.filter { $0.hasPrefix("upd") } == ["upd a", "upd b", "upd a", "upd b"], "\(two.entries)")
    // a + 100 b: 1 + 1000 then 2 + 2000 then 0 (G6: body a=1 b=10 … then a=0 b=0; here b writes 10 per event).
    #expect(two.distinct.last == "body s=0", "\(two.distinct)")
    #expect(two.distinct.contains("body s=1001") && two.distinct.contains("body s=2002"), "\(two.distinct)")
}

// MARK: - 4, 5: long press (G3, G4, G12)

private struct HoldChip: Component {
    let log: GSLog
    let minimum: Double
    @GestureState var held = false
    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(200), height: Pixels(200))
            .gesture(LongPressGesture(minimumDuration: minimum)
                .updating($held) { value, st, _ in st = value; log.add("upd \(value)") })
            .overlay { Rectangle().frame(width: Pixels(held ? 10 : 20), height: Pixels(10)).id("flag") }
    }
}

@MainActor private func flagIsOn(_ window: TestWindow) throws -> Bool {
    try window.frame(ofID: "flag").size.width.value == 10
}

/// **1.4** (`G3`, `G4`). `updating` runs at the press with `true`; the reset comes at the maturity while still held,
/// not at the release. Mutation: remove `finished` from the long-press ended arm.
@Test @MainActor func aLongPressUpdatingIsTrueFromThePressAndResetsWhenItEndsWhileHeld() throws {
    let log = GSLog()
    let window = try chipWindow { HoldChip(log: log, minimum: 0.3) }
    #expect(try !flagIsOn(window))
    window.send(down()); window.tick()
    #expect(try flagIsOn(window), "true from the press")
    window.advance(by: 0.1)
    #expect(try flagIsOn(window), "held, not yet mature")
    window.advance(by: 0.4)
    #expect(try !flagIsOn(window), "reset at the maturity, the pointer still down")
    window.send(up()); window.tick()
    #expect(try !flagIsOn(window))
    #expect(log.entries == ["upd true"], "the body ran once: \(log.entries)")
}

/// **1.5** (`G3`, `G12`). A release before the minimum fails the long press, and the reset is at that release; a pointer
/// that leaves `maximumDistance` fails it at the move, long before the release. Mutation: remove the queue from `fail`.
@Test @MainActor func aLongPressThatFailsResetsAtTheFailureNotTheRelease() throws {
    let log = GSLog()
    let window = try chipWindow { HoldChip(log: log, minimum: 0.5) }
    window.send(down()); window.tick()
    window.advance(by: 0.1)
    #expect(try flagIsOn(window))
    window.send(up()); window.tick()
    #expect(try !flagIsOn(window), "released before the minimum (G3)")

    window.send(down()); window.tick()
    #expect(try flagIsOn(window))
    window.send(dragged(at(250, 150))); window.tick()
    #expect(try !flagIsOn(window), "left maximumDistance: reset at the move, pointer still down (G12)")
    window.send(up(at(250, 150))); window.tick()
    #expect(try !flagIsOn(window))
}

// MARK: - 6, 7: taps never run; a drag begins at its minimum (G2, G5, G5b)

private struct TapChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, TapGesture()
            .updating($s) { _, _, _ in log.add("tap updating ran") }
            .onEnded { log.add("tap ended") })
    }
}

private struct SpatialTapChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, SpatialTapGesture()
            .updating($s) { _, _, _ in log.add("spatial updating ran") }
            .onEnded { _ in log.add("spatial ended") })
    }
}

/// **1.6** (`G2`, `G5b`). `updating` on a tap and a spatial tap compiles and never runs; the tap still ends.
/// Mutation: wire the tap's ended callback to the update body.
@Test @MainActor func aTapGestureUpdatingCompilesAndNeverRuns() throws {
    let log = GSLog()
    let window = try chipWindow { TapChip(log: log) }
    window.click(at: center)
    window.advance(by: 0.5)
    let spatial = GSLog()
    let w2 = try chipWindow { SpatialTapChip(log: spatial) }
    w2.click(at: center)
    w2.advance(by: 0.5)
    #expect(log.entries.filter { !$0.hasPrefix("body") } == ["tap ended"], "\(log.entries)")
    #expect(spatial.entries.filter { !$0.hasPrefix("body") } == ["spatial ended"], "\(spatial.entries)")
}

private struct FarChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 10).updating($s) { _, st, _ in st += 1 })
    }
}

/// **1.7** (`G5`). Under `minimumDistance` nothing runs; the first update is the first recognized change.
/// Mutation: run the update at the press.
@Test @MainActor func updatingBeginsWithTheFirstRecognizedChange() throws {
    let log = GSLog()
    let window = try chipWindow { FarChip(log: log) }
    window.send(down()); window.tick()
    window.send(dragged(at(203, 150))); window.tick()
    #expect(log.distinct == ["body s=0"], "3 pt of 10: \(log.distinct)")
    window.send(dragged(at(220, 150))); window.tick()
    #expect(log.distinct == ["body s=0", "body s=1"], "\(log.distinct)")
    window.send(up(at(220, 150))); window.tick()
    #expect(log.distinct.last == "body s=0", "\(log.distinct)")
}

// MARK: - 8: every cancel path resets once

private struct CancelChip: Component {
    let log: GSLog
    let button: MouseButton
    @GestureState(wrappedValue: 0, reset: { _, _ in GestureStateResets.count += 1 }) var s: Int
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0, button: button).updating($s) { _, st, _ in st += 1 })
    }
}

private struct PinchChip: Component {
    let log: GSLog
    @GestureState(wrappedValue: 1.0, reset: { _, _ in GestureStateResets.count += 1 }) var scale: Double
    var content: some ElementGroup {
        chipBody(log, "body", Int(scale * 100), MagnifyGesture().updating($scale) { v, st, _ in st = v.magnification })
    }
}

@MainActor private enum GestureStateResets { static var count = 0 }

/// **1.8** (`GS-C`, `IF-F`, `GC-C`). One arm per `IF-F`/`GC-` path; the `reset:` closure counts its calls and reads 1
/// per path. Mutations: `cancel()` stops draining the finish callbacks; `abandon()` likewise.
@Test @MainActor func everyCancelPathResetsOnce() throws {
    // (a) a replaced primary press: the old arena is abandoned.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { CancelChip(log: GSLog(), button: .primary) }
        window.send(down()); window.send(dragged(at(210, 150)))
        #expect(GestureStateResets.count == 0)
        window.send(down())   // a press that finds the arena still pressing: a lost release (GC-C)
        #expect(GestureStateResets.count == 1, "abandon: \(GestureStateResets.count)")
        window.send(up()); window.tick()
        #expect(GestureStateResets.count == 2, "the new press's own release: \(GestureStateResets.count)")
    }
    // (b) a button arena whose release was lost: a move with no button down.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { CancelChip(log: GSLog(), button: .middle) }
        window.send(odown()); window.send(odragged(at(210, 150)))
        window.send(moved(at(215, 150)))
        #expect(GestureStateResets.count == 1, "lost button release: \(GestureStateResets.count)")
        window.send(.otherMouseUp(MouseEvent(position: at(215, 150), clickCount: 1, buttonNumber: 2)))
        #expect(GestureStateResets.count == 1, "a late release finds no arena: \(GestureStateResets.count)")
    }
    // (c) a stale button arena: the same button presses again.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { CancelChip(log: GSLog(), button: .middle) }
        window.send(odown()); window.send(odragged(at(210, 150)))
        window.send(odown())
        #expect(GestureStateResets.count == 1, "stale button arena: \(GestureStateResets.count)")
    }
    // (d) a stale pinch arena: a second .began of a kind the arena holds.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { PinchChip(log: GSLog()) }
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0, phase: .began)))
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0.1, phase: .changed)))
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0, phase: .began)))
        #expect(GestureStateResets.count == 1, "stale pinch arena: \(GestureStateResets.count)")
    }
    // (e) the window leaves key mid-pinch.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { PinchChip(log: GSLog()) }
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0, phase: .began)))
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0.1, phase: .changed)))
        window.setControlActiveState(.inactive)
        #expect(GestureStateResets.count == 1, "key loss: \(GestureStateResets.count)")
        window.send(.magnify(MagnifyEvent(position: center, magnification: 0, phase: .ended)))
        #expect(GestureStateResets.count == 1, "a late end finds no arena: \(GestureStateResets.count)")
    }
    // (f) the window closes mid-drag.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { CancelChip(log: GSLog(), button: .primary) }
        window.send(down()); window.send(dragged(at(210, 150)))
        window.close()
        #expect(GestureStateResets.count == 1, "window close: \(GestureStateResets.count)")
    }
    // (g) a drag that is not cancelled by key loss: the release still ends it, one reset.
    do {
        GestureStateResets.count = 0
        let window = try chipWindow { CancelChip(log: GSLog(), button: .primary) }
        window.send(down()); window.send(dragged(at(210, 150)))
        window.setControlActiveState(.inactive)
        #expect(GestureStateResets.count == 0, "key loss is not a cancel of a drag (C4)")
        window.send(up(at(210, 150)))
        #expect(GestureStateResets.count == 1)
    }
}

// MARK: - 9: disabled mid-drag resets at the release

@MainActor private final class DisableModel { var disabled = false }

private struct DisableChip: Component {
    let log: GSLog
    let model: DisableModel
    @GestureState(wrappedValue: 0, reset: { _, _ in GestureStateResets.count += 1 }) var s: Int
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
            .disabled(model.disabled)
    }
}

/// **1.9** (`GS-C`, probe `C2`). A gesture disabled mid-drag resets at the release, not at the disable.
/// Mutation: run the reset at the disable.
@Test @MainActor func aDisabledOwnerResetsAtTheReleaseAndNotBefore() throws {
    GestureStateResets.count = 0
    let log = GSLog()
    let model = DisableModel()
    let window = try chipWindow { DisableChip(log: log, model: model) }
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick()
    model.disabled = true
    window.window.setNeedsRedraw(); window.tick()
    #expect(GestureStateResets.count == 0, "not at the disable: \(GestureStateResets.count)")
    window.send(up(at(210, 150))); window.tick()
    #expect(GestureStateResets.count == 1, "at the release: \(GestureStateResets.count)")
    #expect(log.distinct.last == "body s=0", "\(log.distinct)")
}

// MARK: - 10: the reset's and the update's transactions (G8, G9, G10, G11)

private struct TransactionChip: Component {
    let log: GSLog
    let animateUpdate: Bool
    @GestureState(wrappedValue: 0, resetTransaction: Transaction(animation: .easeOut(duration: 0.25))) var s: Int
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0)
            .updating($s) { _, st, t in
                st += 1
                if animateUpdate { t.animation = .linear(duration: 0.1) }
            })
            .transaction { t in log.transactions.append(t.animation != nil) }
    }
}

private struct PlainResetChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
            .transaction { t in log.transactions.append(t.animation != nil) }
    }
}

private struct ResetClosureChip: Component {
    let log: GSLog
    @GestureState(wrappedValue: 0, reset: { v, t in
        GestureStateResets.count += 1
        GestureStateResets.lastValue = v
        t.animation = .easeOut(duration: 0.2)
    }) var s: Int
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
            .transaction { t in log.transactions.append(t.animation != nil) }
    }
}

extension GestureStateResets { @MainActor static var lastValue = -1 }

@MainActor private func runThreeMovesAndRelease(_ window: TestWindow) {
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick()
    window.send(dragged(at(220, 150))); window.tick()
}

/// **1.10** (`G9`–`G11`). The default reset has no animation; `resetTransaction` animates the reset build only; the
/// `reset:` closure runs once with the pre-reset value; an update body's animation applies to its own builds.
/// Mutations: ignore `resetTransaction`; park the update's transaction even when it has no animation.
@Test @MainActor func theResetClosureAndTransactionApply() throws {
    // G9: the default reset has no animation.
    let plain = GSLog()
    let w1 = try chipWindow { PlainResetChip(log: plain) }
    runThreeMovesAndRelease(w1)
    plain.transactions.removeAll()
    w1.send(up(at(220, 150))); w1.tick()
    #expect(!plain.transactions.isEmpty && plain.transactions.allSatisfy { !$0 }, "\(plain.transactions)")

    // G8: resetTransaction animates the reset, not the updates.
    let reset = GSLog()
    let w2 = try chipWindow { TransactionChip(log: reset, animateUpdate: false) }
    w2.send(down()); w2.tick()
    w2.send(dragged(at(210, 150))); w2.tick()
    #expect(reset.transactions.allSatisfy { !$0 }, "updates carry no animation: \(reset.transactions)")
    reset.transactions.removeAll()
    w2.send(up(at(210, 150))); w2.tick()
    #expect(reset.transactions.contains(true), "the reset build animates: \(reset.transactions)")

    // G10: a transaction set inside the body applies to that update's build.
    let upd = GSLog()
    let w3 = try chipWindow { TransactionChip(log: upd, animateUpdate: true) }
    w3.send(down()); w3.tick()
    upd.transactions.removeAll()
    w3.send(dragged(at(210, 150))); w3.tick()
    #expect(upd.transactions.contains(true), "\(upd.transactions)")

    // G11: the reset closure runs once, with the value before the reset, and its animation applies.
    GestureStateResets.count = 0
    GestureStateResets.lastValue = -1
    let closure = GSLog()
    let w4 = try chipWindow { ResetClosureChip(log: closure) }
    runThreeMovesAndRelease(w4)
    closure.transactions.removeAll()
    w4.send(up(at(220, 150))); w4.tick()
    #expect(GestureStateResets.count == 1 && GestureStateResets.lastValue == 3,
            "\(GestureStateResets.count) \(GestureStateResets.lastValue)")
    #expect(closure.transactions.contains(true), "\(closure.transactions)")
}

// MARK: - 12: two writers into one state (G7, G7b, G7c, G7d, G7e) — divergence 645

private struct TwoWritersChip: Component {
    let log: GSLog
    let longPressFirst: Bool
    let longPressWrites: Bool
    @GestureState var a = 0
    var content: some ElementGroup {
        let drag = DragGesture(minimumDistance: 0).updating($a) { _, st, _ in st += 1 }
        let hold = LongPressGesture(minimumDuration: 0.3).updating($a) { _, st, _ in if longPressWrites { st += 100 } }
        if longPressFirst {
            chipBody(log, "body", a, hold.simultaneously(with: drag))
        } else {
            chipBody(log, "body", a, drag.simultaneously(with: hold))
        }
    }
}

/// **1.12a** (`G7`, `G7d`, `G7e`; **divergence 645, pinned wrong on purpose**). Every body of an event starts from the
/// value committed before the event and the last body run wins; the order is MetalUI's arena order (declaration), where
/// SwiftUI runs the last-declared member first. So drag declared first and a writing long press second end on the long
/// press's 100 (SwiftUI: 1, `G7`), and a no-op long press second leaves 0 (SwiftUI: 1, `G7d`); long press declared first
/// leaves the drag's 1 (SwiftUI: 0, `G7e`). Mutation: take `base` from the live value every time (the first reads 101).
@Test @MainActor func simultaneousWritersStartFromTheEventsCommittedValueAndTheLastWins() throws {
    let writes = GSLog()
    let w1 = try chipWindow { TwoWritersChip(log: writes, longPressFirst: false, longPressWrites: true) }
    w1.send(down()); w1.tick()
    #expect(writes.distinct.last == "body s=100", "base per event, last body wins (645): \(writes.distinct)")

    let noop = GSLog()
    let w2 = try chipWindow { TwoWritersChip(log: noop, longPressFirst: false, longPressWrites: false) }
    w2.send(down()); w2.tick()
    #expect(noop.distinct.last == "body s=0", "the no-op body writes its copy back last (645, G7d): \(noop.distinct)")

    let first = GSLog()
    let w3 = try chipWindow { TwoWritersChip(log: first, longPressFirst: true, longPressWrites: false) }
    w3.send(down()); w3.tick()
    #expect(first.distinct.last == "body s=1", "the drag runs last (645, G7e): \(first.distinct)")
}

/// **1.12b** (`G7b`, `G7c`). Any writer ending resets the shared state: the long press maturing while the drag still
/// holds resets it, and the next drag move writes again; a release resets it. Mutation: remove the dirty guard
/// (the maturity's reset would run again at the release).
@Test @MainActor func anyWriterEndingResetsTheSharedState() throws {
    let log = GSLog()
    let window = try chipWindow { TwoWritersChip(log: log, longPressFirst: false, longPressWrites: false) }
    window.send(down()); window.tick()
    #expect(log.distinct.last == "body s=0" || log.distinct.last == "body s=1", "\(log.distinct)")
    window.advance(by: 0.5)
    #expect(log.distinct.last == "body s=0", "the long press ended while held: \(log.distinct)")
    window.send(dragged(at(210, 150))); window.tick()
    #expect(log.distinct.last == "body s=0" || log.distinct.last == "body s=1", "\(log.distinct)")
    window.send(up(at(210, 150))); window.tick()
    #expect(log.distinct.last == "body s=0", "\(log.distinct)")
}

// MARK: - 13: a `GestureState` is a `$state<n>` slot, not an eighth reserved name (GS-A)

private struct SlotsChip: Component {
    @State var a = 1
    @GestureState var g = 0
    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(200 + Float(a * 0)), height: Pixels(200))
            .gesture(DragGesture(minimumDistance: 0).updating($g) { _, st, _ in st += 1 })
    }
}

/// **1.13** (`GS-A`). One `@State` and one `@GestureState` seed `$state0` and `$state1`, nothing else, and a drag writes
/// the second. `theSevenRetentionSlotsAreMutuallyDistinct` is unmoved. Mutation: give the box its own slot name.
@Test @MainActor func aGestureStateIsAStateSlotNotAnEighth() throws {
    let window = try chipWindow { SlotsChip() }
    let names = window.window.stateTable.ids.map { "\($0)" }
    #expect(names.filter { $0.contains("$state0") }.count == 1, "\(names)")
    #expect(names.filter { $0.contains("$state1") }.count == 1 || !names.contains { $0.contains("$state1") },
            "\(names)")
    window.send(down()); window.tick()
    let after = window.window.stateTable.ids.map { "\($0)" }
    #expect(after.contains { $0.contains("$state1") }, "the drag's write landed in $state1: \(after)")
    #expect(!after.contains { $0.contains("$gesture") || $0.contains("$gs") }, "no eighth slot name: \(after)")
}

// MARK: - 14: a write is a state write for the memo (GS-A)

private struct EqChip: Component, Equatable {
    static func == (a: EqChip, b: EqChip) -> Bool { true }
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        chipBody(log, "body", s, DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
    }
}

/// **1.14** (`GS-A`). An `.equatable()` component that reads a `GestureState` re-evaluates per drag event, so the view
/// shows each value, and is skipped again at rest. Mutation: write through a private store (no version bump): the memo
/// skips and the body log stays at 0.
@Test @MainActor func aGestureStateWriteIsAStateWriteForTheMemoAndRetainedPaths() throws {
    let log = GSLog()
    let window = try chipWindow { EqChip(log: log).equatable() }
    window.send(down()); window.tick()
    window.send(dragged(at(210, 150))); window.tick()
    window.send(dragged(at(220, 150))); window.tick()
    #expect(log.distinct == ["body s=0", "body s=1", "body s=2", "body s=3"], "\(log.distinct)")
    window.send(up(at(220, 150))); window.tick()
    #expect(log.distinct.last == "body s=0", "\(log.distinct)")
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let work = window.frameWork
    try #require(work.count == 3)
    #expect(work.map(\.contentEvaluations).reduce(0, +) == 0 && work.map(\.contentSkips).reduce(0, +) > 0,
            "skipped at rest: \(work.map(\.contentEvaluations)) \(work.map(\.contentSkips))")
}

// MARK: - 15: one element value placed twice resets its own occurrence (ID-F)

private struct HalfChip: Component {
    let log: GSLog
    @GestureState var s = 0
    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(200 + Float(record(log, "body", s) * 0)), height: Pixels(100))
            .gesture(DragGesture(minimumDistance: 0).updating($s) { _, st, _ in st += 1 })
    }
}

/// **1.15** (`ID-F`, `GS-A`). `Column { chip; chip }` places one value twice: dragging the first writes and resets the
/// first occurrence's slot, the second reads 0 throughout. Mutation: resolve with `slotID` only (the last-bound slot).
@Test @MainActor func anElementValuePlacedTwiceResetsItsOwnOccurrence() throws {
    let log = GSLog()
    let chip = HalfChip(log: log)
    let window = try harnessWindow { Column { chip; chip } }
    func lastPair() -> [String] { Array(log.entries.suffix(2)) }
    window.send(down(at(200, 100))); window.tick()
    window.send(dragged(at(210, 100))); window.tick()
    #expect(lastPair() == ["body s=2", "body s=0"], "the first occurrence moved: \(lastPair())")
    window.send(up(at(210, 100))); window.tick()
    #expect(lastPair() == ["body s=0", "body s=0"], "and reset: \(lastPair())")
}
