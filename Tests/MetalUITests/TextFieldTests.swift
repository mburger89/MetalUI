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
                         authority: LayoutAuthority? = nil,
                         extra: @escaping @MainActor (TextField) -> TextField = { $0 })
    throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: 200, layoutAuthority: authority) {
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
    // Bound to the field's own select-all key, so the order is visible: the
    // keymap first clears the text; the field first would only select it.
    let shortcut = TextEditing.platform == .mac ? "cmd-a" : "ctrl-a"
    window.keymap = Keymap { KeyBinding(shortcut, Clear()) }
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    platform.simulateInput(down(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(up(bounds.origin.x.value + 150, bounds.origin.y.value + 2))
    platform.simulateInput(key(TextEditing.deleteBackward))
    #expect(model.text == "ab" && model.keyLog.isEmpty, "the field claims its editing keys")
    platform.simulateInput(key("\t"))
    #expect(model.keyLog == ["\t"], "tab is not the field's: it bubbles to the ancestor's onKey")
    platform.simulateInput(key("a", TextEditing.platform == .mac ? .command : .control))
    #expect(model.text == "", "the keymap binding ran, ahead of the field's select-all")
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
    // Moving left inside the scrolled view keeps the scroll: the caret walks
    // left across the field rather than staying pinned to the edge.
    for _ in 0..<10 { platform.simulateInput(key(TextEditing.leftArrow)) }
    window.drawFrameIfNeeded()
    let moved = try #require(platform.textInputAreas.last ?? nil)
    let tenBack = try caretX(window, at: model.text.count - 10)
    #expect(moved.origin.x.value == tenBack && moved.origin.x.value < right - 30,
            "the scroll stayed where the end put it: \(moved.origin.x.value)")
}

/// Both authorities. The proposal engine offers the field the width and it
/// takes it, one line tall (SwiftUI's greedy `TextField`); the legacy CSS
/// engine sizes it as it sizes a `Text` — its natural width, stretched across
/// by `Box` (EP-8) — and the line is centred in whatever height it gets.
/// Typing edits the same way under both. `.legacy` is pinned here on purpose,
/// as the second arm of the pair (owner: stage 9, which deletes the legacy
/// authority).
@Test(arguments: [LayoutAuthority.proposal, .legacy])
@MainActor func aFieldLaysOutAndEditsUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    let model = Model("ab")
    let (window, platform) = try fieldWindow(model, authority: authority)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    let target = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }?.handlers.textInput)
    let line = target.caretRect.size.height.value
    if authority == .proposal {
        #expect(bounds.size.width.value == 200 && bounds.size.height.value == line)
    } else {
        // "Name" is wider than "ab": the placeholder's width plus the caret.
        #expect(bounds.size.width.value < 60 && bounds.size.height.value == 200)
    }
    let centred = bounds.origin.y.value + (bounds.size.height.value - line) / 2
    #expect(target.caretRect.origin.y.value == centred, "\(authority): the line is centred")
    platform.simulateInput(down(try caretX(window, at: 2), bounds.origin.y.value + 2))
    platform.simulateInput(.textInput("c"))
    #expect(model.text == "abc", "\(authority)")
}

/// TI-C's paint, read off the frame's scene (fake window at scale 1, so scene
/// units are points): the placeholder at 45 % of the text colour's alpha, a
/// 1-point caret only while focused and collapsed, the selection behind the
/// text in the accent at 30 %, and the composition's 1-point underline.
@Test @MainActor func aFieldPaintsItsPlaceholderCaretSelectionAndComposition() throws {
    let model = Model("")
    let (window, platform) = try fieldWindow(model)
    window.drawFrameIfNeeded()
    let bounds = try fieldBounds(window)
    let theme = window.theme
    var scene = try #require(window.lastScene)
    let text = theme[.textPrimary]
    #expect(!scene.glyphs.isEmpty && scene.glyphs.allSatisfy { abs($0.color.a - text.a * 0.45) < 1e-6 },
            "an empty field paints its placeholder, dimmed")
    func caretRects(_ scene: Scene) -> [MUIRect] {
        scene.rects.filter { $0.bounds.size.width == 1 && $0.background.a == text.a }
    }
    #expect(caretRects(scene).isEmpty, "no caret while unfocused")

    platform.simulateInput(down(bounds.origin.x.value + 20, bounds.origin.y.value + 2))
    platform.simulateInput(.textInput("hello"))
    window.drawFrameIfNeeded()
    scene = try #require(window.lastScene)
    #expect(scene.glyphs.count == 5 && scene.glyphs.allSatisfy { $0.color.a == text.a }, "the text, full strength")
    let caret = try #require(caretRects(scene).first)
    #expect(caret.bounds.origin.x == Float(try caretX(window, at: 5)), "the caret after the typed text")

    platform.simulateInput(down(try caretX(window, at: 1), bounds.origin.y.value + 2))
    platform.simulateInput(.mouseDragged(MouseEvent(position: Point(x: Pixels(try caretX(window, at: 4)),
                                                                    y: bounds.origin.y))))
    window.drawFrameIfNeeded()
    scene = try #require(window.lastScene)
    let accent = theme[.accent]
    let selection = try #require(scene.rects.first { abs($0.background.a - accent.a * 0.3) < 1e-6 })
    #expect(selection.bounds.origin.x == Float(try caretX(window, at: 1)))
    #expect(abs(selection.bounds.size.width - Float(try caretX(window, at: 4) - caretX(window, at: 1))) < 1e-3)
    #expect(caretRects(scene).isEmpty, "no caret over a selection")

    platform.simulateInput(down(try caretX(window, at: 5), bounds.origin.y.value + 2))
    platform.simulateInput(.textComposition(TextComposition(text: "ka", selection: 2..<2)))
    window.drawFrameIfNeeded()
    scene = try #require(window.lastScene)
    #expect(scene.glyphs.count == 7, "the composition is drawn inline")
    #expect(scene.rects.contains { $0.bounds.size.height == 1 && $0.bounds.size.width > 1 },
            "the composition is underlined")
}
