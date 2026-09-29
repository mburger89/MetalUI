import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 3 — `@FocusState` and `.focused(_:)` (ruling
// `IX-J`; spec §6, tests 3.7–3.12 and 3.20). SwiftUI's spelling (SDK
// `FocusState`, `focused(_:)`, `focused(_:equals:)`); its following of every
// focus mover, including `IX-I`'s drop, is probe arm F1's `focused=false`.
//
// "From input" here is the test itself calling a closure the body captured,
// between frames — never from inside a phase.

private func key(_ characters: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: modifiers, timestamp: 0))
}

private enum Field: Hashable {
    case a, b, c, d, text
}

/// What the form's body read, and the writes it exposes to the test.
@MainActor
private final class FormModel {
    var flag: [Bool] = []
    var field: [Field?] = []
    var setFlag: (Bool) -> Void = { _ in }
    var setField: (Field?) -> Void = { _ in }
    var showB = true
    var text = ""
    var lastFlag: Bool? { flag.last }
    var lastField: Field?? { field.last }
}

/// A 20×20 box.
@MainActor
private func square() -> some StyledElement {
    Box().frame(width: Pixels(20), height: Pixels(20))
}

/// Tab order: `f` (flag), `a`, `b` (inside `if model.showB`), the text field,
/// then `d` (disabled) — `c` is bound but not focusable and `d` is disabled,
/// so neither is in the tab order.
private struct Form: Component {
    @FocusState var flag: Bool
    @FocusState var field: Field?
    let model: FormModel

    var content: some ElementGroup {
        let _ = model.flag.append(flag)
        let _ = model.field.append(field)
        let _ = model.setFlag = { [flag = $flag] in flag.wrappedValue = $0 }
        let _ = model.setField = { [field = $field] in field.wrappedValue = $0 }
        square().focusable().focused($flag)
        square().focusable().focused($field, equals: .a)
        if model.showB { square().focusable().focused($field, equals: .b) }
        square().focused($field, equals: .c)
        TextField("t", text: model.text) { [model] in model.text = $0 }.focused($field, equals: .text)
        square().focusable().focused($field, equals: .d).disabled(true)
    }
}

/// Draws until the window is clean (at most four frames).
@MainActor
private func settle(_ window: Window) {
    for _ in 0..<4 { window.drawFrameIfNeeded() }
}

@MainActor
private func formWindow(_ model: FormModel) throws -> (Window, FakePlatformWindow, [GlobalElementID]) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400) {
        Row { Form(model: model) }
    }
    window.drawFrameIfNeeded()
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 4, "set up: f, a, b and the field are focusable: \(order)")
    try #require(window.focusedElement == nil && model.lastFlag == false && model.lastField == .some(nil),
                 "set up: nothing is focused and both states read their default")
    return (window, platform, order)
}

// MARK: - 3.7 a write moves focus

/// **3.7 — a `@FocusState` write from input moves focus on the next frame**,
/// Bool and `equals:` (`IX-J` item 2). `flag = true` focuses `f`; `field = .b`
/// focuses `b`, and `flag` then reads `false`; `field = .c` — bound to a box
/// that is not focusable — leaves focus on `b` and `field` reads `.b` again.
///
/// Mutation **M3a** (the write applied without the last frame's focusability
/// check, so the frame's own `resolveFocus` must clear the non-focusable
/// target) reddens the `.c` arm: focus ends `nil`, not `b`.
@MainActor
@Test func aFocusStateWriteFromInputMovesFocusOnTheNextFrame() throws {
    let model = FormModel()
    let (window, _, order) = try formWindow(model)

    model.setFlag(true)
    settle(window)
    #expect(window.focusedElement == order[0], "`flag = true` focuses the flag's box")
    #expect(model.lastFlag == true, "and `flag` reads true")

    model.setField(.b)
    settle(window)
    #expect(window.focusedElement == order[2], "`field = .b` focuses b")
    #expect(model.lastField == .some(.b) && model.lastFlag == false, "field reads .b, flag false")

    model.setField(.c)
    settle(window)
    #expect(window.focusedElement == order[2], "a write naming a non-focusable box leaves focus where it was")
    #expect(model.lastField == .some(.b), "and field reads .b again: \(model.field.suffix(3))")
}

// MARK: - 3.8 every mover

/// **3.8 — a `@FocusState` reads the window's focus after every mover** (`IX-J`
/// item 4): Tab, `Window.focus(_:)`, a `TextField` press, and `IX-I`'s drop
/// (F1's `focused=false`) — `b` removed by its `if` while focused reads `nil`.
///
/// Mutation **M3b** (the value changes only through its own writes — the
/// after-frame write-back removed) reddens every arm.
@MainActor
@Test func aFocusStateReadsTheWindowsFocusAfterEveryMover() throws {
    let model = FormModel()
    let (window, platform, order) = try formWindow(model)

    platform.simulateInput(key("\t"))
    settle(window)
    try #require(window.focusedElement == order[0], "Tab focuses f")
    #expect(model.lastFlag == true && model.lastField == .some(nil), "Tab: flag true")

    platform.simulateInput(key("\t"))
    settle(window)
    #expect(model.lastFlag == false && model.lastField == .some(.a), "Tab again: field .a")

    window.focus(order[2])
    settle(window)
    #expect(model.lastField == .some(.b), "Window.focus: field .b")

    let fieldBox = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the text field")
    let centre = Point(x: Pixels(fieldBox.bounds.origin.x.value + fieldBox.bounds.size.width.value / 2),
                       y: Pixels(fieldBox.bounds.origin.y.value + fieldBox.bounds.size.height.value / 2))
    platform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    settle(window)
    #expect(window.focusedElement == order[3], "a press focuses the field")
    #expect(model.lastField == .some(.text), "a TextField press: field .text")

    window.focus(order[2])
    settle(window)
    try #require(model.lastField == .some(.b), "set up: b focused again")
    model.showB = false
    window.setNeedsRedraw()
    settle(window)
    #expect(window.focusedElement == nil, "b's removal drops focus (IX-I)")
    #expect(model.lastField == .some(nil), "the drop: field nil (F1)")
}

// MARK: - 3.9 false / nil

/// **3.9 — writing `false` or `nil` clears focus only if its element holds it**
/// (`IX-J` item 2). With `a` focused, `flag = false` leaves it; `field = nil`
/// clears it. With `f` focused, `field = nil` leaves it.
///
/// Mutation **M3c** (clear unconditionally) reddens both "leaves" arms.
@MainActor
@Test func writingFalseOrNilClearsFocusOnlyIfItsElementHoldsIt() throws {
    let model = FormModel()
    let (window, _, order) = try formWindow(model)

    window.focus(order[1])
    settle(window)
    try #require(model.lastField == .some(.a), "set up: a focused")
    model.setFlag(false)
    settle(window)
    #expect(window.focusedElement == order[1], "flag = false leaves a's focus alone")
    model.setField(nil)
    settle(window)
    #expect(window.focusedElement == nil, "field = nil clears a's focus")

    window.focus(order[0])
    settle(window)
    try #require(model.lastFlag == true, "set up: f focused")
    model.setField(nil)
    settle(window)
    #expect(window.focusedElement == order[0], "field = nil leaves f's focus alone")
    #expect(model.lastFlag == true, "and flag still reads true")
}

// MARK: - 3.10 `.focused` is not focusability

/// A `.focused` box with no `.focusable()`, alone.
private struct Unfocusable: Component {
    @FocusState var flag: Bool
    let model: FormModel
    var content: some ElementGroup {
        let _ = model.flag.append(flag)
        let _ = model.setFlag = { [flag = $flag] in flag.wrappedValue = $0 }
        square().focused($flag).id("n")
    }
}

/// **3.10 — `.focused` does not make an element focusable** (`IX-J` item 3):
/// the box is not in the tab order, `flag = true` focuses nothing and `flag`
/// reads false again, Tab lands nowhere, and `Window.focus` on it is cleared.
///
/// Mutation **M3d** (`.focused` sets `isFocusable`) reddens it.
@MainActor
@Test func focusedDoesNotMakeAnElementFocusable() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let model = FormModel()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Row { Unfocusable(model: model) }
    }
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let n = GlobalElementID.child(of: GlobalElementID.child(of: root, at: 0, name: nil), at: 0, name: ElementID("n"))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.lastElementBounds[n] != nil, "set up: the box is at \(n)")
    #expect(window.lastFocusRegistry.tabOrder.isEmpty, "the box is not focusable")

    model.setFlag(true)
    settle(window)
    #expect(window.focusedElement == nil, "flag = true focuses nothing")
    #expect(model.lastFlag == false, "and flag reads false again")

    platform.simulateInput(key("\t"))
    settle(window)
    #expect(window.focusedElement == nil, "Tab lands nowhere")

    window.focus(n)
    settle(window)
    #expect(window.focusedElement == nil, "Window.focus on it is cleared by the frame")
    #expect(model.lastFlag == false, "flag never read true")
}

// MARK: - 3.11 disabled

/// **3.11 — a `@FocusState` write naming a disabled element focuses nothing**
/// (K1, `IX-J` item 2): with nothing focused, `field = .d` leaves focus nil;
/// with `a` focused, it leaves `a` focused, and `field` reads `.a` again.
///
/// Mutation **M3e** is M3a's site (in this implementation the only validation
/// a write gets before its frame is the last frame's focus registry, which a
/// disabled element never joins): the check dropped, the frame's own
/// `resolveFocus` clears the disabled target and focus ends `nil`, not `a`.
@MainActor
@Test func aFocusStateWriteNamingADisabledElementFocusesNothing() throws {
    let model = FormModel()
    let (window, _, order) = try formWindow(model)

    model.setField(.d)
    settle(window)
    #expect(window.focusedElement == nil, "a disabled target takes no focus")
    #expect(model.lastField == .some(nil), "field reads nil again")

    window.focus(order[1])
    settle(window)
    try #require(model.lastField == .some(.a), "set up: a focused")
    model.setField(.d)
    settle(window)
    #expect(window.focusedElement == order[1], "a disabled target leaves a focused")
    #expect(model.lastField == .some(.a), "field reads .a again")
}

// MARK: - 3.12 never from a phase

/// **3.12 — a `@FocusState` never writes from a phase** (`IX-J` item 4). Steady
/// frames: after each, `stateTable.isDirty` and `needsRedraw` stay false — the
/// state wrote nothing. A focus change (Tab) writes once: the frame after it
/// leaves the table dirty, the next frame does not.
///
/// Mutation **M3f** (the value written back every frame, changed or not)
/// reddens it.
@MainActor
@Test func aFocusStateNeverWritesFromAPhase() throws {
    let model = FormModel()
    let (window, platform, _) = try formWindow(model)
    settle(window)
    for frame in 1...3 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        #expect(!window.stateTable.isDirty && !window.needsRedraw, "steady frame \(frame) wrote nothing")
    }
    platform.simulateInput(key("\t"))
    window.drawFrameIfNeeded()
    #expect(window.stateTable.isDirty && window.needsRedraw, "the frame that moved focus is followed by one write")
    window.drawFrameIfNeeded()
    #expect(!window.stateTable.isDirty && !window.needsRedraw, "and only one")
    #expect(model.lastFlag == true, "the write was the flag's")
}

// MARK: - 3.20 binding sites

/// An `Element` (not a `Component`) holding a `@FocusState`, binding itself.
private struct FocusElement: Element {
    @FocusState var flag: Bool
    let model: FormModel
    var elementID: ElementID? { nil }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        model.flag.append(flag)
        model.setFlag = { [flag = $flag] in flag.wrappedValue = $0 }
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID,
                ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        var handlers = Handlers()
        handlers.isFocusable = true
        handlers.focusBinding = FocusBindingTarget(state: $flag.box, value: AnyHashable(true))
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

/// **3.20 — a `@FocusState` works inside a `Component` and inside an
/// `AnyElement`** (`ID-E`'s binding sites). Each arm: `flag = true` focuses the
/// bound element and `flag` reads true; Tab away (an ordinary focusable box
/// after it) and it reads false.
///
/// Mutation **M3m** (seeding skipped under `AnyElementBox`) reddens the
/// `AnyElement` arm.
@MainActor
@Test func aFocusStateSurvivesInsideAComponentAndAnAnyElement() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for arm in ["component", "anyElement"] {
        let model = FormModel()
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            Row {
                if arm == "component" { Unfocusable2(model: model) } else { AnyElement(FocusElement(model: model)) }
                square().focusable()
            }
        }
        window.drawFrameIfNeeded()
        let order = window.lastFocusRegistry.tabOrder
        try #require(order.count == 2, "\(arm), set up: two focusable elements: \(order)")
        model.setFlag(true)
        settle(window)
        #expect(window.focusedElement == order[0], "\(arm): flag = true focuses the bound element")
        #expect(model.lastFlag == true, "\(arm): flag reads true")
        platform.simulateInput(key("\t"))
        settle(window)
        #expect(window.focusedElement == order[1], "\(arm): Tab moves on")
        #expect(model.lastFlag == false, "\(arm): flag reads false")
    }
}

/// `Unfocusable`, made focusable — 3.20's `Component` arm.
private struct Unfocusable2: Component {
    @FocusState var flag: Bool
    let model: FormModel
    var content: some ElementGroup {
        let _ = model.flag.append(flag)
        let _ = model.setFlag = { [flag = $flag] in flag.wrappedValue = $0 }
        square().focusable().focused($flag)
    }
}
