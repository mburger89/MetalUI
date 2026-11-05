import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// The first-draw seat (rulings `FC-E`, record 215; divergence 186 narrowed to fields). SwiftUI's answers are the
// probe `docs/probes/swiftui-initial-focus.swift`; each test names its arm. Windows are 200 x 200 over
// `FakePlatformWindow`. The seat is read through a `@FocusState<Int?>` bound to each candidate (`seen.last`), so a
// test reads WHICH element holds focus, not only that one does.

// MARK: - Harness

@MainActor private final class ISModel {
    var seen: [Int?] = []
    var set: (Int?) -> Void = { _ in }
    var showFirst = true
    var showLate = false
    var text = ""
    var last: Int?? { seen.last }
}

@MainActor private func sq(_ w: Float = 200, _ h: Float = 40) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h))
}

/// A component binding `@FocusState<Int?>` and handing it to `build`.
private struct Seat<Body: ElementGroup>: Component {
    @FocusState var f: Int?
    let model: ISModel
    let build: (ISModel, FocusState<Int?>.Binding) -> Body
    var content: some ElementGroup {
        let _ = model.seen.append(f)
        let _ = model.set = { [f = $f] in f.wrappedValue = $0 }
        build(model, $f)
    }
}

@MainActor private func draw(_ window: Window, _ frames: Int = 5) {
    for _ in 0..<frames where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// Opens a 200 x 200 window over `build`, draws until clean and answers what the bound `@FocusState` reads.
@MainActor private func seatOf<Body: ElementGroup>(
    _ build: @escaping (ISModel, FocusState<Int?>.Binding) -> Body
) throws -> (seat: Int??, window: Window, model: ISModel) {
    let model = ISModel()
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) { Row { Seat(model: model, build: build) } }
    window.drawFrameIfNeeded()
    draw(window)
    return (model.last, window, model)
}

@MainActor private func item(_ f: FocusState<Int?>.Binding, _ i: Int, _ h: Float = 40) -> some StyledElement {
    sq(200, h).focusable().focused(f, equals: i)
}

// MARK: - The table

/// **I0, I0n.** A lone `.focusable()` is focused after the first draw, with no input, and its `@FocusState` reads it
/// after the settling frame (it read `nil` on the first).
@MainActor
@Test func aLoneFocusableIsFocusedAndItsFocusStateReadsItAfterTheSettlingFrame() throws {
    let (seat, window, model) = try seatOf { _, f in Column { item(f, 0) } }
    #expect(seat == .some(0), "I0: the lone focusable is seated: \(model.seen)")
    #expect(model.seen.first == .some(nil), "the first frame's body read nil: \(model.seen)")
    #expect(window.focusedElement == window.lastFocusRegistry.tabOrder.first)
}

/// **LF7, I1, I6, I7, I9, I11, LF9, I8, I26.** What is and is not a candidate, row by row, each with the expected
/// element (index into the bound values). Mutations: include controls (`I1`, `I6`), include `.activate` (`I7`), drop the
/// disabled / hidden gates (`I11`, `LF9`), exclude `.edit` (`I8`), gate on `allowsHitTesting` (`I26`).
@MainActor
@Test func onlyClickFocusableElementsAreCandidatesAndTheFirstOneIsSeated() throws {
    func row(_ label: String, _ expected: Int?, _ build: @escaping (ISModel, FocusState<Int?>.Binding) -> some ElementGroup,
             sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (seat, _, model) = try seatOf(build)
        #expect(seat == .some(expected), "\(label): expected \(String(describing: expected)), saw \(model.seen)",
                sourceLocation: sourceLocation)
    }
    try row("LF7 [Button]", nil) { _, f in Column { Button("b") {}.frame(width: Pixels(200), height: Pixels(40)).focused(f, equals: 0) } }
    try row("I1 [Button, focusable]", 1) { _, f in
        Column { Button("b") {}.frame(width: Pixels(200), height: Pixels(40)).focused(f, equals: 0); item(f, 1) } }
    try row("I6a [Toggle, focusable]", 1) { _, f in
        Column { Toggle("t", isOn: .constant(false)).focused(f, equals: 0); item(f, 1) } }
    try row("I6b [Slider, focusable]", 1) { _, f in
        Column { Slider(value: .constant(0.5), in: 0...1).focused(f, equals: 0); item(f, 1) } }
    try row("I6c [Picker, focusable]", 1) { _, f in
        Column {
            Picker("p", selection: .constant(0)) { Text("a").tag(0); Text("b").tag(1) }.focused(f, equals: 0)
            item(f, 1)
        } }
    try row("I7 [.activate, focusable]", 1) { _, f in
        Column { sq().focusable(interactions: .activate).focused(f, equals: 0); item(f, 1) } }
    try row("I9 [focusable(false), focusable]", 1) { _, f in
        Column { sq().focusable(false).focused(f, equals: 0); item(f, 1) } }
    try row("I11 [hidden, focusable]", 1) { _, f in
        Column { item(f, 0).hidden(); item(f, 1) } }
    try row("LF9 [disabled, focusable]", 1) { _, f in
        Column { item(f, 0).disabled(true); item(f, 1) } }
    try row("I8 [.edit, focusable]", 0) { _, f in
        Column { sq().focusable(interactions: .edit).focused(f, equals: 0); item(f, 1) } }
    try row("I26 [allowsHitTesting(false) focusable, focusable]", 0) { _, f in
        Column { item(f, 0).allowsHitTesting(false); item(f, 1) } }
}

/// **G5, G7, G8.** A focusable inside a `ScrollView` is not a candidate (the design's scroller exclusion; SwiftUI seats
/// a `ScrollView`'s content, `G5`/`G7`, a divergence recorded with 186), and a `LazyVStack` outside one is
/// (`G8`). Mutation: drop the `activeScrollerFrame == nil` condition.
@MainActor
@Test func aFocusableInsideAScrollViewIsNotSeatedButOneOutsideIs() throws {
    let (alone, _, m1) = try seatOf { _, f in ScrollView { item(f, 0) } }
    #expect(alone == .some(nil), "G5 (MetalUI): nothing in a scroller is seated: \(m1.seen)")
    let (beside, _, m2) = try seatOf { _, f in
        Column { ScrollView { item(f, 0) }.frame(width: Pixels(200), height: Pixels(80)); item(f, 1) } }
    #expect(beside == .some(1), "G7 (MetalUI): the focusable outside the scroller is seated: \(m2.seen)")
    let (lazy, _, m3) = try seatOf { _, f in LazyVStack(spacing: 0) { item(f, 0) } }
    #expect(lazy == .some(0), "G8: a LazyVStack is seated: \(m3.seen)")
}

/// **G1, G3, G4.** The seat is the topmost candidate by final position, ties in tree order. `G1`: an earlier element
/// offset down loses to a later one above it. Mutations: tree order instead of top (`G1`), the latest instead of the first
/// on a tie (`G3`, `G4`).
@MainActor
@Test func theSeatIsTheTopmostCandidateAndATieGoesToTheFirstInTreeOrder() throws {
    let (g1, w1, m1) = try seatOf { _, f in
        ZStack(alignment: .topLeading) {
            sq(50, 50).focusable().focused(f, equals: 0).offset(y: Pixels(100))
            sq(50, 50).focusable().focused(f, equals: 1)
        } }
    #expect(g1 == .some(1), "G1: the later element is higher: \(m1.seen) \(w1.lastFocusRegistry.tabOrder)")
    let (g3, _, m3) = try seatOf { _, f in
        HStack(spacing: 0) { sq(50, 50).focusable().focused(f, equals: 0); sq(50, 50).focusable().focused(f, equals: 1) } }
    #expect(g3 == .some(0), "G3: side by side, the same top: tree order: \(m3.seen)")
    let (g4, _, m4) = try seatOf { _, f in
        ZStack(alignment: .topLeading) {
            sq(50, 50).focusable().focused(f, equals: 0)
            sq(50, 50).focusable().focused(f, equals: 1)
        } }
    #expect(g4 == .some(0), "G4: stacked, the same top: tree order: \(m4.seen)")
}

/// **I20.** A write from `onAppear` wins over the seat (`f = 1` over a first focusable).
@MainActor
@Test func anOnAppearFocusStateWriteWinsOverTheSeat() throws {
    let (seat, _, model) = try seatOf { m, f in
        Column { item(f, 0); item(f, 1) }.onAppear { m.set(1) }
    }
    #expect(seat == .some(1), "I20: the appear write wins: \(model.seen)")
}

/// **Text fields are not candidates** (the 2026-11-04 decision; divergence 186 narrowed to fields). A lone field takes
/// no focus, and `[TextField, focusable]` and `[focusable, TextField]` seat the focusable.
@MainActor
@Test func aTextFieldIsNotSeatedAndAFocusableAroundItIs() throws {
    let (alone, window, m1) = try seatOf { m, f in
        Column { TextField("t", text: m.text) { [m] in m.text = $0 }.focused(f, equals: 0) } }
    #expect(alone == .some(nil) && window.focusedElement == nil, "LF1 (MetalUI): a lone field takes no focus: \(m1.seen)")
    let (after, _, m2) = try seatOf { m, f in
        Column { TextField("t", text: m.text) { [m] in m.text = $0 }.focused(f, equals: 0); item(f, 1) } }
    #expect(after == .some(1), "LF5b: [TextField, focusable] seats the focusable: \(m2.seen)")
    let (before, _, m3) = try seatOf { m, f in
        Column { item(f, 0); TextField("t", text: m.text) { [m] in m.text = $0 }.focused(f, equals: 1) } }
    #expect(before == .some(0), "LF5: [focusable, TextField] seats the focusable: \(m3.seen)")
}

// MARK: - When it runs

/// **L1, L3.** The seat runs on the first drawn frame only: a focusable inserted afterwards is not seated, even though
/// the first frame had no candidate (the flag flips whether or not one exists), and clearing focus from code stays
/// cleared through further frames. Mutations: seat on every frame; keep the flag unset when no candidate exists (`L1`).
@MainActor
@Test func theSeatRunsOnTheFirstDrawnFrameOnly() throws {
    // L1: nothing to seat on the first frame; one inserted later is not seated.
    let (seat, window, model) = try seatOf { m, f in
        Column { sq().focused(f, equals: 9); if m.showLate { item(f, 0) } }
    }
    #expect(seat == .some(nil) && window.focusedElement == nil, "set up: nothing to seat on the first frame: \(model.seen)")
    model.showLate = true
    window.setNeedsRedraw()
    draw(window)
    #expect(window.lastFocusRegistry.tabOrder.count == 1, "control: the late focusable exists")
    #expect(window.focusedElement == nil && model.last == .some(nil), "L1: not seated: \(model.seen)")

    // L3: cleared from code, it stays nil on every later frame.
    let (_, w2, m2) = try seatOf { _, f in Column { item(f, 0); item(f, 1) } }
    try #require(m2.last == .some(0), "set up: seated")
    w2.focus(nil)
    for _ in 0..<4 { w2.setNeedsRedraw(); w2.drawFrameIfNeeded() }
    #expect(w2.focusedElement == nil && m2.last == .some(nil), "L3: stays nil, no re-seat: \(m2.seen)")
}

/// A focus already held when the window first draws is kept: the seat fills an empty slot only.
/// Mutation: seat when already focused.
@MainActor
@Test func aFocusAlreadyHeldWhenTheWindowFirstDrawsIsKept() throws {
    func make(_ model: ISModel) throws -> Window {
        try makeFakeWindowOnDefaultDevice(size: 200) {
            Row { Seat(model: model) { _, f in Column { item(f, 0); item(f, 1) } } }
        }.0
    }
    // The second focusable's id, learnt from an identical window (ids are deterministic).
    let probe = try make(ISModel())
    probe.drawFrameIfNeeded()
    let second = try #require(probe.lastFocusRegistry.tabOrder.dropFirst().first)
    let model = ISModel()
    let window = try make(model)
    window.focus(second)
    window.drawFrameIfNeeded()
    draw(window)
    #expect(model.last == .some(1), "the held focus stays, not the first focusable: \(model.seen)")
}

/// **The first frame under `.equatable()`.** A seat candidate inside an `.equatable()` subtree is still seated: the
/// first frame evaluates it, so the candidate is noted.
@MainActor
@Test func aFocusableInsideAnEquatableSubtreeIsSeatedOnTheFirstFrame() throws {
    let (seat, _, model) = try seatOf { _, f in
        Column { EquatableFocusable(f: f).equatable() }
    }
    #expect(seat == .some(0), "the equatable subtree's focusable is seated: \(model.seen)")
}

private struct EquatableFocusable: Component, Equatable {
    let f: FocusState<Int?>.Binding
    nonisolated static func == (a: Self, b: Self) -> Bool { true }
    var content: some ElementGroup { item(f, 0) }
}

/// The seat costs one extra frame (it paints the ring) and then the window is idle: it does not keep the display link
/// awake. Counted work, no clock.
@MainActor
@Test func theSeatDoesNotKeepTheDisplayLinkAwake() throws {
    let model = ISModel()
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) { Row { Seat(model: model) { _, f in Column { item(f, 0) } } } }
    window.drawFrameIfNeeded()
    var frames = 1
    while window.needsRedraw && frames < 8 { window.drawFrameIfNeeded(); frames += 1 }
    #expect(model.last == .some(0), "set up: seated")
    #expect(!window.needsRedraw && !window.hasActiveAnimations, "the window went clean after \(frames) frames")
    #expect(frames <= 3, "the seat costs one or two extra frames, then idle: \(frames)")
    let before = window.framesDrawn
    for _ in 0..<5 { window.drawFrameIfNeeded() }
    #expect(window.framesDrawn == before, "idle: no frame is drawn")
}

/// The seat owes the window one more frame, which paints the ring (focus is drawn, `PaintPass.isFocused`), and no
/// `@FocusState` is needed to say so. Mutation: seat without `setNeedsRedraw()` (green until this test).
@MainActor
@Test func theSeatOwesOneFrameThatPaintsTheFocusedElement() throws {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) { Row { Column { sq().focusable() } } }
    window.drawFrameIfNeeded()
    try #require(window.focusedElement != nil, "set up: seated")
    #expect(window.needsRedraw, "the first frame drew the element unfocused, so a frame is owed")
    window.drawFrameIfNeeded()
    #expect(!window.needsRedraw, "and one is all that is owed")
}

// MARK: - Divergence 217 (a focused focusable removed)

/// **L2, L4, L5; divergence 217's pin.** SwiftUI moves focus from a removed focused `.focusable()` to an existing
/// one; MetalUI clears it (`IX-I`). A focusable that is still there does not catch it, and neither does a newly
/// inserted one.
@MainActor
@Test func aFocusedFocusableThatIsRemovedClearsFocusAndNoneTakesItsPlace() throws {
    let (seat, window, model) = try seatOf { m, f in
        Column { if m.showFirst { item(f, 0) }; item(f, 1); if m.showLate { item(f, 9) } }
    }
    try #require(seat == .some(0), "set up: the first is seated")
    model.showFirst = false
    model.showLate = true
    window.setNeedsRedraw()
    draw(window)
    #expect(window.focusedElement == nil && model.last == .some(nil),
            "divergence 217: focus is cleared, not moved to the existing or the new focusable: \(model.seen)")
}
