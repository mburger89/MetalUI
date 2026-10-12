import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Spec §4 tests 4.10–4.18 and 4.20–4.24 (rulings SL-A…SL-M): the selection
// binding end to end, through `TestWindow` over the real `Window` — plain
// imports, public API only (the work-counter arms 4.15 and 4.19 need
// `@testable` and live in `HarnessTextSelectionWorkTests.swift`). A model is a
// plain class; its writes ask the window for a redraw, as `@Observable` would.
// Every literal below is derived from the text before the run: "hello world"
// is 11 Characters, "hello" is 0..<5.

@available(macOS 15, *)
private func index(_ text: String, _ offset: Int) -> String.Index {
    text.index(text.startIndex, offsetBy: offset)
}

@available(macOS 15, *)
func caret(_ offset: Int, in text: String) -> TextSelection {
    TextSelection(insertionPoint: index(text, offset))
}

@available(macOS 15, *)
func span(_ lower: Int, _ upper: Int, in text: String) -> TextSelection {
    TextSelection(range: index(text, lower)..<index(text, upper))
}

/// The Character offsets a single-range selection names in `text`, through the
/// standard library only.
@available(macOS 15, *)
func offsets(_ selection: TextSelection?, in text: String) -> Range<Int>? {
    guard case .selection(let range)? = selection?.indices else { return nil }
    return text.distance(from: text.startIndex, to: range.lowerBound)
        ..< text.distance(from: text.startIndex, to: range.upperBound)
}

/// The caller's side of a field: the text, the selection binding's value and a
/// log of every write the field made to it.
@available(macOS 15, *)
@MainActor final class SelModel {
    var text: String { didSet { redraw?() } }
    var selection: TextSelection? { didSet { redraw?() } }
    /// Every selection the field wrote, in order (offsets in `text` at the write).
    var published: [Range<Int>?] = []
    var textWrites = 0
    var redraw: (@MainActor () -> Void)?

    init(_ text: String, selection: TextSelection? = nil) {
        self.text = text
        self.selection = selection
    }

    var textBinding: Binding<String> {
        Binding(get: { self.text }, set: { self.textWrites += 1; self.text = $0 })
    }
    var selectionBinding: Binding<TextSelection?> {
        Binding(get: { self.selection },
                set: { new in
                    self.published.append(offsets(new, in: self.text))
                    self.selection = new
                })
    }
    func field(_ placeholder: String = "Title") -> TextField {
        TextField(placeholder, text: textBinding, selection: selectionBinding)
    }
    func editor(_ placeholder: String = "Note") -> TextEditor {
        TextEditor(placeholder, text: textBinding, selection: selectionBinding)
    }
    /// What the binding reads now, in Characters.
    var read: Range<Int>? { offsets(selection, in: text) }
}

@available(macOS 15, *)
@MainActor func fieldWindow(_ model: SelModel) throws -> TestWindow {
    let window = try harnessWindow { model.field().id("field") }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    return window
}

@available(macOS 15, *)
@MainActor func focusField(_ window: TestWindow, _ label: String = "Title") throws {
    try window.focus(window.element(label: label))
}

func midY(_ b: Bounds<Pixels>) -> Float { b.origin.y.value + b.size.height.value / 2 }

/// A ⌘ (control off Apple) key straight through the platform window, with no frame.
@MainActor func sendKey(_ window: TestWindow, _ key: String, _ modifiers: EventModifiers = []) {
    let event = KeyEvent(charactersIgnoringModifiers: key, characters: key, modifiers: modifiers,
                         timestamp: window.now)
    _ = window.send(.keyDown(event))
    _ = window.send(.keyUp(event))
}

// MARK: 4.10, 4.11 — the two requested cases

/// 4.10 — use case 1: a title opens with its whole text selected. Focused from
/// code with the binding already whole-range, `typeText("New")` replaces it;
/// the control (the same field with no binding) gives today's measured
/// `Newhello`. Mutation: skip `reconcile` in `TextField.prepaint`.
@available(macOS 15, *)
@Test @MainActor func aTitleOpensWithItsWholeTextSelectedAndTypingReplacesIt() throws {
    let model = SelModel("hello", selection: span(0, 5, in: "hello"))
    let window = try fieldWindow(model)
    try focusField(window)
    #expect(model.published.isEmpty, "focus from code writes nothing (divergence 266)")
    window.typeText("New")
    #expect(model.text == "New")
    #expect(model.read == 3..<3, "typing published the caret after the inserted text")

    // The control: no binding, the caret stays where it was, at the start.
    var plain = "hello"
    let control = try harnessWindow {
        TextField("Title", text: Binding(get: { plain }, set: { plain = $0 }))
    }
    try control.focus(control.element(label: "Title"))
    control.typeText("New")
    #expect(plain == "Newhello")
}

/// 4.11 — use case 2: a note opens with the caret at its end and typing
/// appends; with a trailing line the caret is on the last line. Mutation: skip
/// `reconcile` in `TextEditor.prepaint`.
@available(macOS 15, *)
@Test @MainActor func aNoteOpensWithTheCaretAtItsEndAndAppends() throws {
    let note = "one"
    let model = SelModel(note, selection: caret(3, in: note))
    let window = try harnessWindow { model.editor().id("note") }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try focusField(window, "Note")
    window.typeText("!")
    #expect(model.text == "one!")
    #expect(model.read == 4..<4)

    let lines = "one\ntwo\n"
    let second = SelModel(lines, selection: caret(8, in: lines))
    let other = try harnessWindow { second.editor().id("note") }
    second.redraw = { [unowned other] in other.window.setNeedsRedraw() }
    try focusField(other, "Note")
    other.typeText("x")
    #expect(second.text == "one\ntwo\nx", "the caret was on the empty last line")
    #expect(second.read == 9..<9)
}

// MARK: 4.12 — a write from code

/// 4.12 — a write from a code path moves the caret on the next frame. A button
/// (a click does not take the field's focus) writes `insertion@2`; the frame
/// that click draws applies it and typing gives `heXllo`. The key that arrives
/// in the same turn as the write, before that frame, still sees the old caret
/// (SwiftUI's W3). Mutation: invert the `seenBinding` comparison in `reconcile`.
@available(macOS 15, *)
@Test @MainActor func aWriteFromACodePathMovesTheCaretOnTheNextFrame() throws {
    let model = SelModel("hello")
    let window = try harnessWindow {
        VStack(spacing: 8) {
            model.field()
            Button("Move") { model.selection = caret(2, in: model.text) }
        }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try focusField(window)
    try window.click(window.element(label: "Move"))
    window.typeText("X")
    #expect(model.text == "heXllo")
    #expect(model.read == 3..<3)

    // W3: a write, then a key with no frame between, sees the old caret.
    let late = SelModel("hello")
    let second = try harnessWindow { late.field() }
    late.redraw = { [unowned second] in second.window.setNeedsRedraw() }
    try focusField(second)
    late.selection = caret(2, in: late.text)
    _ = second.send(.textInput("X"))
    second.tick()
    #expect(late.text == "Xhello", "the write was not yet applied when the key arrived")
    #expect(late.read == 1..<1, "the key's own publish is the later instruction")
}

// MARK: 4.13, 4.14 — what the binding reads

enum SelectionArm: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case typing, click, doubleClick, shiftArrow, selectAll, delete
    var testDescription: String { rawValue }
}

/// 4.13 — after each input the binding reads SwiftUI's answer (probe arms
/// R1–R9): typing `ins@` after the inserted text, a click `ins@n`, a double
/// click the word, ⇧← twice the extended range, ⌘A `0..<n`, delete `ins@n`.
/// Mutation: delete the `defer` in `onInput` (every arm red).
@available(macOS 15, *)
@Test(arguments: SelectionArm.allCases) @MainActor func theFieldPublishesAfterEachInput(arm: SelectionArm) throws {
    let model = SelModel("hello world")
    let window = try fieldWindow(model)
    let field = try window.frame(ofID: "field")
    let right = pt(field.maxX.value - 10, midY(field))
    let left = pt(field.minX.value + 20, midY(field))
    switch arm {
    case .typing:
        try focusField(window)
        window.typeText("X")
        #expect(model.text == "Xhello world")
        #expect(model.read == 1..<1)
    case .click:
        window.click(at: right)
        #expect(model.read == 11..<11)
    case .doubleClick:
        window.doubleClick(at: left)
        #expect(model.read == 0..<5, "the word under the pointer")
    case .shiftArrow:
        window.click(at: right)
        window.typeKey(.leftArrow, modifierFlags: .shift)
        window.typeKey(.leftArrow, modifierFlags: .shift)
        #expect(model.read == 9..<11)
    case .selectAll:
        try focusField(window)
        window.typeKey("a", modifierFlags: .primary)
        #expect(model.read == 0..<11)
    case .delete:
        window.click(at: right)
        window.typeKey(.delete)
        #expect(model.text == "hello worl")
        #expect(model.read == 10..<10)
    }
}

/// 4.14 — Tab into a bound field selects its text (AppKit's rule, `TI-J`) and
/// that select-all reaches the binding. Mutation: publish only in
/// `dispatchTextInput`.
@available(macOS 15, *)
@Test @MainActor func tabbingIntoAFieldPublishesItsSelectAll() throws {
    let model = SelModel("hello")
    var other = ""
    let window = try harnessWindow {
        VStack(spacing: 8) {
            TextField("First", text: Binding(get: { other }, set: { other = $0 }))
            model.field("Second")
        }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    window.typeKey(.tab)
    #expect(model.published.isEmpty, "the first field took the focus")
    window.typeKey(.tab)
    #expect(model.read == 0..<5)
}

// MARK: 4.16, 4.17

/// 4.16 — a backward selection keeps its direction across a re-written equal
/// range. ⇧← twice leaves anchor 11, head 9; the app writes the same range as a
/// *multi*-selection (a value the field did not publish, so it is applied); the
/// range equals the state's, so nothing moves, and ⇧← extends leftward from the
/// kept anchor. Mutation: apply even when the range equals the state's (drop
/// `r != state.selection`).
@available(macOS 15, *)
@Test @MainActor func aBackwardSelectionKeepsItsDirectionAcrossTheEcho() throws {
    let model = SelModel("hello world")
    let window = try fieldWindow(model)
    let field = try window.frame(ofID: "field")
    window.click(at: pt(field.maxX.value - 10, midY(field)))
    window.typeKey(.leftArrow, modifierFlags: .shift)
    window.typeKey(.leftArrow, modifierFlags: .shift)
    #expect(model.read == 9..<11)
    // The same value, rewritten: not an instruction.
    model.selection = span(9, 11, in: model.text)
    window.tick()
    // The same range spelled differently: applied, equal to the state's, no move.
    var set = RangeSet<String.Index>()
    set.insert(contentsOf: index(model.text, 9)..<index(model.text, 11))
    model.selection = TextSelection(ranges: set)
    window.tick()
    window.typeKey(.leftArrow, modifierFlags: .shift)
    #expect(model.read == 8..<11, "the anchor stayed at the right end")
}

/// 4.17 — a selection write does not corrupt undo and ends the typing group.
/// Type `a`, move the caret away and back by two writes, type `b`: one ⌘Z removes
/// only `b` (without the write the two coalesce, the control), a second restores
/// the empty text, redo replays. A second case: a write, then undo of the earlier
/// group still undoes and publishes the restored caret. Mutations: (a) clear the
/// history in `reconcile`; (b) do not end `openGroup`.
@available(macOS 15, *)
@Test @MainActor func aSelectionWriteDoesNotCorruptUndoAndEndsTheTypingGroup() throws {
    // The control: typing coalesces without a write.
    let control = SelModel("")
    let plain = try fieldWindow(control)
    try focusField(plain)
    plain.typeText("a")
    plain.typeText("b")
    plain.typeKey("z", modifierFlags: .primary)
    #expect(control.text == "", "one undo removes both coalesced letters")

    let model = SelModel("")
    let window = try fieldWindow(model)
    try focusField(window)
    window.typeText("a")
    #expect(model.text == "a")
    model.selection = caret(0, in: model.text)
    window.tick()
    model.selection = caret(1, in: model.text)
    window.tick()
    window.typeText("b")
    #expect(model.text == "ab")
    window.typeKey("z", modifierFlags: .primary)
    #expect(model.text == "a", "the write ended the typing group: only b is undone")
    #expect(model.read == 1..<1, "undo published the restored caret")
    window.typeKey("z", modifierFlags: .primary)
    #expect(model.text == "", "the history survived the writes")
    window.typeKey("z", modifierFlags: [.primary, .shift])
    #expect(model.text == "a", "redo replays")

    // Second case: a write after typing, then an undo of the earlier group.
    let again = SelModel("")
    let second = try fieldWindow(again)
    try focusField(second)
    second.typeText("a")
    again.selection = caret(0, in: again.text)
    second.tick()
    again.selection = caret(1, in: again.text)
    second.tick()
    second.typeText("b")
    again.selection = caret(0, in: again.text)
    second.tick()
    second.typeKey("z", modifierFlags: .primary)
    #expect(again.text == "a")
    #expect(again.read == 1..<1)
}

// MARK: 4.18

/// 4.18 — two edits between frames publish against the edited text. With the
/// whole text selected and a long clipboard, two pastes are sent with no frame
/// between; the second composes on the first through `Window.editedText`, and
/// the binding reads the offset in the *edited* text, which is longer than the
/// text the frame showed. Mutation: publish with `target.text` instead of
/// `currentText`.
@available(macOS 15, *)
@Test @MainActor func twoEditsBetweenFramesPublishAgainstTheEditedText() throws {
    let model = SelModel("hello")
    let window = try fieldWindow(model)
    try focusField(window)
    window.platformWindow.clipboard = "a much longer line"          // 18 Characters
    sendKey(window, "a", .primary)
    sendKey(window, "v", .primary)
    sendKey(window, "v", .primary)
    #expect(model.text == "a much longer linea much longer line", "the second paste composed on the first")
    #expect(model.read == 36..<36)
    window.tick()
    #expect(model.read == 36..<36, "the frame between kept it")
}

// MARK: 4.20, 4.21, 4.22, 4.23, 4.24

/// 4.20 — a stale selection neither traps nor is rewritten. Indices of a longer
/// string clamp (typing appends), the binding is not written before the edit; a
/// text replaced from code leaves it stale and the next edit clamps (probe arms
/// S1, S2, W6, W8). Mutation: remove the clamp in `TextSelection.offsets`.
@available(macOS 15, *)
@Test @MainActor func aStaleSelectionNeitherTrapsNorIsRewritten() throws {
    let longer = "hello world!!"
    let model = SelModel("hi", selection: span(5, 13, in: longer))
    let window = try fieldWindow(model)
    try focusField(window)
    #expect(model.published.isEmpty, "the binding is not rewritten to the clamped value")
    window.typeText("X")
    #expect(model.text == "hiX", "indices past the end clamp to it")

    // Replaced from code: the binding is stale, the next edit clamps.
    let other = SelModel("hello", selection: caret(5, in: "hello"))
    let second = try fieldWindow(other)
    try focusField(second)
    other.text = "hi"
    second.tick()
    #expect(other.published.isEmpty)
    second.typeText("X")
    #expect(other.text == "hiX")
}

/// 4.21 — a bound selection is kept while the field is not focused. Written
/// while unfocused, then the field is focused from code and a key arrives in the
/// same turn, before any frame with the focus: it replaces the range (`hXo`).
/// Mutation: apply only when focused.
@available(macOS 15, *)
@Test @MainActor func aBoundSelectionIsKeptWhileTheFieldIsNotFocused() throws {
    let model = SelModel("hello")
    let window = try fieldWindow(model)
    model.selection = span(1, 4, in: model.text)
    window.tick()
    let element = try window.element(label: "Title")
    _ = window.platformWindow.simulateAccessibilityRequest(.focus(element.id))
    _ = window.send(.textInput("X"))
    window.tick()
    #expect(model.text == "hXo")
}

/// 4.22 — a write during composition is held back and the marked text stays.
/// Compose at the start, write `insertion@5`, draw: the commit lands where the
/// composition began (`漢hello`), not at the written caret, and the commit's own
/// publish wins (`ins@1`, `SL-H`). Mutation: delete the composition guard in
/// `reconcile`.
@available(macOS 15, *)
@Test @MainActor func aWriteDuringCompositionIsHeldBackAndTheMarkedTextStays() throws {
    let model = SelModel("hello")
    let window = try fieldWindow(model)
    try focusField(window)
    _ = window.send(.textComposition(TextComposition(text: "か", selection: 1..<1)))
    window.tick()
    #expect(model.published.isEmpty, "nothing is published while composing")
    model.selection = caret(5, in: model.text)
    window.tick()
    #expect(model.published.isEmpty)
    _ = window.send(.textInput("漢"))
    window.tick()
    #expect(model.text == "漢hello", "the commit landed where the composition began")
    #expect(model.read == 1..<1, "the commit's publish superseded the held write")
}

/// 4.23 — text and selection written in one handler apply against the new text.
/// A button replaces a two-Character title with a nineteen-Character one and
/// selects all of it; typing replaces the whole new text. Mutation: convert
/// against the previous frame's text.
@available(macOS 15, *)
@Test @MainActor func aTextAndASelectionWrittenInOneHandlerApplyAgainstTheNewText() throws {
    let model = SelModel("hi")
    let window = try harnessWindow {
        VStack(spacing: 8) {
            model.field()
            Button("Rename") {
                model.text = "a much longer title"
                model.selection = span(0, 19, in: model.text)
            }
        }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try focusField(window)
    try window.click(window.element(label: "Rename"))
    window.typeText("Z")
    #expect(model.text == "Z")
}

/// 4.24 — a `TextEditor` publishes across lines and reveals a written caret.
/// Down from the start publishes the second line's offset (6); a write at the
/// end of a long text scrolls the caret into the editor's rect. Mutation: do
/// not set `revealsCaret` in `reconcile`.
@available(macOS 15, *)
@Test @MainActor func aTextEditorPublishesAcrossLinesAndRevealsAWrittenCaret() throws {
    let model = SelModel("line1\nline2\nline3")
    let window = try harnessWindow { model.editor().id("note") }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try focusField(window, "Note")
    window.typeKey(.downArrow)
    #expect(model.read == 6..<6, "the start of the second line")

    let long = (1...60).map { "line \($0)" }.joined(separator: "\n")
    let big = SelModel(long)
    let tall = try harnessWindow {
        big.editor().frame(height: Pixels(100)).id("note")
    }
    big.redraw = { [unowned tall] in tall.window.setNeedsRedraw() }
    try focusField(tall, "Note")
    let field = try tall.frame(ofID: "note")
    big.selection = caret(long.count, in: long)
    tall.tick()
    let last = try #require(tall.platformWindow.textInputAreas.last)
    let area = try #require(last)
    #expect(area.origin.y.value >= field.minY.value && area.maxY.value <= field.maxY.value + 1,
            "the caret was scrolled into view: \(area) in \(field)")
}
