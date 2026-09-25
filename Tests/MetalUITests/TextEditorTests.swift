import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// TI-H: a `TextEditor` in a real `Window` over the fake platform window.

@MainActor
private final class Notes {
    var text: String
    init(_ text: String = "") { self.text = text }
}

private func key(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

private func down(_ x: Float, _ y: Float) -> InputEvent {
    .mouseDown(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y)), clickCount: 1))
}

private func up(_ x: Float, _ y: Float) -> InputEvent {
    .mouseUp(MouseEvent(position: Point(x: Pixels(x), y: Pixels(y))))
}

/// A `size`-point square window holding one editor in a `Box`.
@MainActor
private func editorWindow(_ notes: Notes, size: Int = 200) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: size) {
        Box { TextEditor("Notes", text: notes.text) { notes.text = $0 } }
    }
}

@MainActor
private func target(_ window: Window) throws -> (bounds: Bounds<Pixels>, target: TextInputTarget) {
    let hitbox = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    return (hitbox.bounds, try #require(hitbox.handlers.textInput))
}

/// The caret the last frame drew, from the input method's area.
@MainActor
private func caret(_ platform: FakePlatformWindow) throws -> Bounds<Pixels> {
    try #require(platform.textInputAreas.last ?? nil)
}

@Test @MainActor func returnStartsANewLineAndTheCaretMovesDownALine() throws {
    let notes = Notes()
    let (window, platform) = try editorWindow(notes)
    window.drawFrameIfNeeded()
    let (bounds, first) = try target(window)
    #expect(bounds.size.width.value == 200 && bounds.size.height.value == 200, "greedy on both axes")
    #expect(first.lines?.lines.count == 1)
    platform.simulateInput(down(bounds.origin.x.value + 5, bounds.origin.y.value + 2))
    platform.simulateInput(.textInput("one"))
    platform.simulateInput(key("\r"))
    #expect(notes.text == "one\n")
    window.drawFrameIfNeeded()
    let lineHeight = try target(window).target.lineHeight
    // A final line break opens an empty line, and the caret is on it.
    #expect(try target(window).target.lines?.lines.count == 2)
    #expect(try caret(platform).origin.y.value == bounds.origin.y.value + Float(lineHeight))
    platform.simulateInput(.textInput("two"))
    #expect(notes.text == "one\ntwo")
    window.drawFrameIfNeeded()
    let caretOnTwo = try caret(platform)
    #expect(caretOnTwo.origin.y.value == bounds.origin.y.value + Float(lineHeight), "on the second line")
    platform.simulateInput(key(TextEditing.upArrow))
    window.drawFrameIfNeeded()
    let caretOnOne = try caret(platform)
    // Up lands on the first line at the boundary nearest the same x — "one"
    // and "two" are not the same width, so near, not equal; the `!` typed
    // below pins which boundary.
    #expect(caretOnOne.origin.y.value == bounds.origin.y.value
            && abs(caretOnOne.origin.x.value - caretOnTwo.origin.x.value) < 5, "up keeps the column")
    platform.simulateInput(.textInput("!"))
    #expect(notes.text == "one!\ntwo")
}

@Test @MainActor func aPressOnALaterLinePlacesTheCaretThere() throws {
    let notes = Notes("first\nsecond\nthird")
    let (window, platform) = try editorWindow(notes)
    window.drawFrameIfNeeded()
    let (bounds, t) = try target(window)
    let lines = try #require(t.lines)
    try #require(lines.lines.count == 3)
    // Just right of "sec" on line 1.
    let x = Float(t.originX + lines.lines[1].offsets[3]) + 0.5
    let y = Float(t.originY + t.lineHeight * 1.5)
    platform.simulateInput(down(x, y))
    platform.simulateInput(up(x, y))
    platform.simulateInput(.textInput("X"))
    #expect(notes.text == "first\nsecXond\nthird")
    _ = bounds
}

@Test @MainActor func longTextWrapsAtTheEditorsWidth() throws {
    let notes = Notes(String(repeating: "word ", count: 40))
    let (window, _) = try editorWindow(notes)
    window.drawFrameIfNeeded()
    let (bounds, t) = try target(window)
    let lines = try #require(t.lines)
    #expect(lines.lines.count > 3, "wraps into several lines")
    #expect(lines.lines.allSatisfy { ($0.offsets.last ?? 0) <= Double(bounds.size.width.value) + 30 },
            "each line is about the editor's width (trailing space hangs)")
    #expect(lines.lines.dropLast().allSatisfy { !$0.endsInHardBreak })
}

@Test @MainActor func theWheelScrollsAndTypingScrollsTheCaretBackIntoView() throws {
    let notes = Notes((1...40).map { "line \($0)" }.joined(separator: "\n"))
    let (window, platform) = try editorWindow(notes, size: 120)
    window.drawFrameIfNeeded()
    var (bounds, t) = try target(window)
    #expect(t.maxScrollY > 0, "forty lines overflow a 120-point editor")
    // Focus at the start, then wheel down: the content moves, the caret does not.
    platform.simulateInput(down(bounds.origin.x.value + 2, bounds.origin.y.value + 2))
    platform.simulateInput(up(bounds.origin.x.value + 2, bounds.origin.y.value + 2))
    window.drawFrameIfNeeded()
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: bounds.origin.x + Pixels(10),
                                                                    y: bounds.origin.y + Pixels(10)),
                                                    delta: Point(x: Pixels(0), y: Pixels(-100)),
                                                    modifiers: [], timestamp: 0)))
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    (bounds, t) = try target(window)
    #expect(Double(bounds.origin.y.value) - t.originY == 100, "scrolled 100 and not snapped back to the caret")
    // Typing reveals the caret again: back to the top.
    platform.simulateInput(.textInput("x"))
    window.drawFrameIfNeeded()
    (bounds, t) = try target(window)
    #expect(Double(bounds.origin.y.value) - t.originY == 0)
    // A wheel right after an edit, with no frame between: the wheel wins, the
    // edit's reveal does not snap it back.
    platform.simulateInput(.textInput("y"))
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: bounds.origin.x + Pixels(10),
                                                                    y: bounds.origin.y + Pixels(10)),
                                                    delta: Point(x: Pixels(0), y: Pixels(-40)),
                                                    modifiers: [], timestamp: 0)))
    window.drawFrameIfNeeded()
    (bounds, t) = try target(window)
    #expect(Double(bounds.origin.y.value) - t.originY == 40)
    // ⌘↓ / ctrl-End to the end: the last line is in view at the bottom.
    let toEnd = TextEditing.platform == .mac ? key(TextEditing.downArrow, .command) : key(TextEditing.end, .control)
    platform.simulateInput(toEnd)
    window.drawFrameIfNeeded()
    (bounds, t) = try target(window)
    let caretRect = try caret(platform)
    #expect(abs(Double(caretRect.origin.y.value + caretRect.size.height.value)
                - Double(bounds.origin.y.value + bounds.size.height.value)) < 0.01, "the caret line sits at the bottom")
}

@Test @MainActor func anEditorPublishesATextArea() throws {
    let notes = Notes("hello")
    let (window, platform) = try editorWindow(notes)
    platform.simulateAccessibilityRequest(.activate)
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let node = try #require(tree.nodes.values.first { $0.role == .textArea })
    #expect(node.label == "Notes" && node.value == "hello")
}

@Test @MainActor func anEditorPaintsEachLineAndTheCaretOnItsLine() throws {
    let notes = Notes("ab\ncde")
    let (window, platform) = try editorWindow(notes)
    window.drawFrameIfNeeded()
    let (bounds, t) = try target(window)
    #expect(window.lastScene.glyphs.count == 5, "five glyphs; the line break draws nothing")
    let second = window.lastScene.glyphs.filter { Double($0.bounds.origin.y) > t.originY + t.lineHeight / 2 }
    #expect(second.count == 3, "cde on the second line")
    // Focus at the end: the caret is a 1-point rect on line 1.
    platform.simulateInput(down(bounds.origin.x.value + 150, bounds.origin.y.value + Float(t.lineHeight) * 1.5))
    window.drawFrameIfNeeded()
    let text = window.theme[.textPrimary]
    let caret = try #require(window.lastScene.rects.first { $0.bounds.size.width == 1 && $0.background.a == text.a })
    #expect(Double(caret.bounds.origin.y) == t.originY + t.lineHeight)
}

/// Greedy on both axes, as SwiftUI's `TextEditor` is — its lines drawn from
/// the top however tall it is — and, offered no height, its lines' height.
/// (Until stage 9 this test also ran the CSS engine, which sized the editor as
/// content and let `Box` stretch it; that engine is gone.)
@Test @MainActor func anEditorTakesTheOfferedSizeAndItsContentHeightWhenOfferedNone() throws {
    let notes = Notes("a\nb\nc")
    let (window, _) = try editorWindow(notes)
    window.drawFrameIfNeeded()
    let (bounds, t) = try target(window)
    #expect(t.lines?.lines.count == 3)
    #expect(bounds.size.width.value == 200 && bounds.size.height.value == 200)
    #expect(t.originY == Double(bounds.origin.y.value), "lines start at the top, not centred")
    // Offered no height (a vertical scroll's content), it answers its lines.
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (scrolled, _) = try makeFakeWindow(device: device, size: 200) {
        ScrollView(.vertical) { TextEditor(text: notes.text) { notes.text = $0 } }
    }
    scrolled.drawFrameIfNeeded()
    let (content, u) = try target(scrolled)
    #expect(abs(Double(content.size.height.value) - 3 * u.lineHeight) < 0.01,
            "three lines tall: \(content.size.height.value) vs \(3 * u.lineHeight)")
}
