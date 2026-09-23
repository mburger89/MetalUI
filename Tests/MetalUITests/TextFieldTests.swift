import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// TI-B / TI-C: a `TextField` in a real `Window` over the fake platform window.
// Input goes in through `simulateInput`, exactly as a platform delivers it.

@MainActor
private final class Model {
    var text: String
    var submits = 0
    var keyLog: [String] = []
    init(_ text: String = "") { self.text = text }
}

private func key(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

private func down(_ x: Float, _ y: Float, clicks: Int = 1, _ modifiers: Modifiers = []) -> InputEvent {
    .mouseDown(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y)), modifiers: modifiers, clickCount: clicks))
}

private func up(_ x: Float, _ y: Float) -> InputEvent {
    .mouseUp(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y))))
}

/// A 200-point window holding one field in a `Box`; the field fills the width
/// (greedy) and is centred vertically at its line height.
@MainActor
private func fieldWindow(_ model: Model, disabled: Bool = false, submits: Bool = true,
                         extra: @escaping @MainActor (TextField) -> TextField = { $0 })
    throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: 200) {
        var field = TextField("Name", text: model.text) { model.text = $0 }
        if submits { field = field.onSubmit { model.submits += 1 } }
        return Box { extra(field).disabled(disabled) }
    }
}

/// The field's frame, read from the last frame's hitboxes.
@MainActor
private func fieldBounds(_ window: Window) throws -> Bounds<Pixels> {
    try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }).bounds
}

@MainActor
private func caretX(_ window: Window, at boundary: Int) throws -> Float {
    let target = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }?.handlers.textInput)
    return Float(target.originX + target.caretOffsets[boundary])
}

@Test @MainActor func clickingAFieldFocusesItAndTypingEditsItsText() throws {
    let model = Model("hello")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    #expect(bounds.size.width.value == 200, "greedy: the field takes the offered width")
    #expect(window.focusedElement == nil)
    #expect(platform.textInputAreas.isEmpty, "no field focused, no text input")

    // A click just right of the "e" boundary puts the caret there.
    let y = bounds.origin.y.value + bounds.size.height.value / 2
    platform.simulateInput(down(try caretX(window, at: 2) + 0.5, y))
    platform.simulateInput(up(try caretX(window, at: 2) + 0.5, y))
    #expect(window.focusedElement != nil, "a click focuses a field, unlike every other element")
    platform.simulateInput(.textInput("XY"))
    #expect(model.text == "heXYllo")
    window.drawFrameIfNeeded()
    // Text input switched on with the caret after "XY", one point wide.
    let area = try #require(platform.textInputAreas.last ?? nil)
    #expect(area.origin.x.value == (try caretX(window, at: 4)) && area.size.width.value == 1)
    platform.simulateInput(key(TextEditing.deleteBackward))
    #expect(model.text == "heXllo")
}

@Test @MainActor func textGoesOnlyToAFocusedField() throws {
    let model = Model("a")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    #expect(platform.simulateInput(.textInput("z")) == false, "nothing focused: not claimed")
    #expect(model.text == "a")
    let bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(up(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    window.drawFrameIfNeeded()
    window.focus(nil)
    window.drawFrameIfNeeded()
    #expect(platform.textInputAreas.last == .some(nil), "unfocusing switches text input off")
    #expect(platform.simulateInput(.textInput("z")) == false)
    #expect(model.text == "a")
}

@Test @MainActor func aCompositionIsShownThenCommitted() throws {
    let model = Model("ab")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    let y = bounds.origin.y.value + 2
    platform.simulateInput(down(try caretX(window, at: 1), y))
    platform.simulateInput(up(try caretX(window, at: 1), y))
    platform.simulateInput(.textComposition(TextComposition(text: "にほ", selection: 2..<2)))
    #expect(model.text == "ab", "marked text is not the field's text")
    window.drawFrameIfNeeded()
    // The caret — and the input method's area — sits after the marked text.
    let area = try #require(platform.textInputAreas.last ?? nil)
    #expect(area.origin.x.value > (try caretX(window, at: 1)))
    platform.simulateInput(.textInput("日本"))
    #expect(model.text == "a日本b")
}

@Test @MainActor func anAppsKeymapBindingWinsOverEditingAndUnclaimedKeysBubble() throws {
    struct Clear: Action {}
    let model = Model("abc")
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Box {
            TextField("Name", text: model.text) { model.text = $0 }
        }
        .onKey { event in model.keyLog.append(event.charactersIgnoringModifiers); return true }
        .onAction(Clear.self) { _ in model.text = "" }
    }
    window.keymap = Keymap { KeyBinding("cmd-k", Clear()) }
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(up(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(key(TextEditing.deleteBackward))
    #expect(model.text == "ab" && model.keyLog.isEmpty, "the field claims its editing keys")
    platform.simulateInput(key("\t"))
    #expect(model.keyLog == ["\t"], "tab is not the field's: it bubbles to the ancestor's onKey")
    platform.simulateInput(key("k", .command))
    #expect(model.text == "", "the keymap binding ran, ahead of the field")
}

@Test @MainActor func copyCutAndPasteGoThroughThePlatformClipboard() throws {
    let model = Model("hello")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(up(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    let shortcut: Modifiers = TextEditing.platform == .mac ? .command : .control
    platform.simulateInput(key("a", shortcut))
    platform.simulateInput(key("c", shortcut))
    #expect(platform.clipboard == "hello" && model.text == "hello")
    platform.simulateInput(key("x", shortcut))
    #expect(model.text == "" && platform.clipboard == "hello")
    platform.clipboard = "pasted"
    platform.simulateInput(key("v", shortcut))
    #expect(model.text == "pasted")
}

@Test @MainActor func aDragSelectsAndAShiftClickExtends() throws {
    let model = Model("one two three")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let y = try fieldBounds(window).origin.y.value + 2
    platform.simulateInput(down(try caretX(window, at: 1), y))
    platform.simulateInput(.mouseDragged(MouseEvent(position: Point(x: Pixels(try caretX(window, at: 6)),
                                                                    y: Pixels(y)))))
    platform.simulateInput(up(try caretX(window, at: 6), y))
    platform.simulateInput(.textInput("X"))
    #expect(model.text == "oXo three", "the drag selected 1..<6 and typing replaced it")
    window.drawFrameIfNeeded()
    platform.simulateInput(down(try caretX(window, at: 0), y))
    platform.simulateInput(up(try caretX(window, at: 0), y))
    platform.simulateInput(down(try caretX(window, at: 3), y, [.shift]))
    platform.simulateInput(up(try caretX(window, at: 3), y))
    platform.simulateInput(key(TextEditing.deleteBackward))
    #expect(model.text == " three")
}

@Test @MainActor func returnRunsOnSubmitAndIsNotClaimedWithoutOne() throws {
    let model = Model("x")
    var (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    var bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 5, bounds.origin.y.value + 2))
    #expect(platform.simulateInput(key("\r")))
    #expect(model.submits == 1)
    (window, platform) = try fieldWindow(model, submits: false)
    window.drawFrameIfNeeded()
    bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 5, bounds.origin.y.value + 2))
    #expect(platform.simulateInput(key("\r")) == false)
    #expect(model.submits == 1)
}

@Test @MainActor func aDisabledFieldTakesNoFocusAndNoText() throws {
    let model = Model("x")
    let (window, platform) = try fieldWindow(model, disabled: true)
    window.drawFrameIfNeeded()
    #expect(window.lastHitboxes.allSatisfy { $0.handlers.textInput == nil }, "no hitbox: disabled (EV-E)")
    platform.simulateInput(down(100, 100))
    #expect(window.focusedElement == nil)
    #expect(platform.simulateInput(.textInput("z")) == false)
    #expect(model.text == "x")
}

@Test @MainActor func aFieldPublishesATextFieldToAccessibility() throws {
    let model = Model("typed")
    let (window, platform) = try fieldWindow(model)
    platform.simulateAccessibilityRequest(.activate)
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let field = try #require(tree.nodes.values.first { $0.role == .textField })
    #expect(field.label == "Name" && field.value == "typed")
}

@Test @MainActor func aLongTextScrollsToKeepTheCaretVisible() throws {
    let model = Model(String(repeating: "wide text ", count: 20))
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 10, bounds.origin.y.value + 2))
    let end: Modifiers = TextEditing.platform == .mac ? .command : []
    platform.simulateInput(key(TextEditing.platform == .mac ? TextEditing.rightArrow : TextEditing.end, end))
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    let caret = try #require(platform.textInputAreas.last ?? nil)
    let right = bounds.origin.x.value + bounds.size.width.value
    #expect(caret.origin.x.value <= right && caret.origin.x.value >= right - 2,
            "the caret at the end sits at the field's right edge: \(caret.origin.x.value) vs \(right)")
}
