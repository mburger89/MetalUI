import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Spec §5 tests 5.1–5.15 (rulings IM-A…IM-J): the input-method driver, through
// `TestWindow` over the real `Window` — plain imports, public API only, and
// platform-neutral (no AppKit). The model is `SelModel`
// (`HarnessTextSelectionTests.swift`). Every literal below is derived from the
// text before the run: "hello" is 5 Characters, "helloni" is 7, "hello world" 11.

/// A field window over `model` with the caret at the text's end: a click on
/// the field's right edge focuses it (`TI-`) and places the caret there.
@available(macOS 15, *)
@MainActor func endCaretWindow(_ model: SelModel) throws -> TestWindow {
    let window = try fieldWindow(model)
    let field = try window.frame(ofID: "field")
    window.click(at: pt(field.maxX.value - 10, midY(field)))
    return window
}

// MARK: 5.1, 5.2, 5.3 — marked text and its commit

/// 5.1 — marked text lives in the field, not in the binding. Mutation: `setMarkedText`
/// sends `.textInput(text)` instead of `.textComposition`.
@available(macOS 15, *)
@Test @MainActor func aMarkedTextIsInTheFieldNotInTheBinding() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "ni")
    #expect(window.markedSelection == 2..<2, "a nil range is a caret at the end")
    #expect(model.text == "hello")
    #expect(model.textWrites == 0)
    #expect(window.setMarkedText("ni hao"))
    #expect(window.markedText == "ni hao")
    #expect(model.textWrites == 0, "an update writes nothing either")
}

/// 5.2 — `commitMarkedText()` is AppKit's `unmarkText`: the marked text becomes
/// the text, once. Mutation: `TextEditing.insert` stops clearing the composition.
@available(macOS 15, *)
@Test @MainActor func commitMarkedTextCommitsTheMarkedTextOnce() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    window.setMarkedText("ni")
    #expect(window.platformWindow.markedText == "ni", "the platform's mirror follows")
    #expect(window.commitMarkedText())
    #expect(model.text == "helloni")
    #expect(model.textWrites == 1)
    #expect(window.markedText == "")
    #expect(window.platformWindow.markedText == "")
    #expect(!window.commitMarkedText(), "nothing marked: AppKit's unmarkText guard")
    #expect(model.textWrites == 1)
}

/// 5.3 — `commitMarkedText(_:)` is `insertText`: the candidate replaces the marked
/// text. Mutation: the verb sends the marked text instead of the argument.
@available(macOS 15, *)
@Test @MainActor func commitMarkedTextWithACandidateReplacesTheMarkedText() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    window.setMarkedText("ni")
    #expect(window.commitMarkedText("你"))
    #expect(model.text == "hello你")
    #expect(model.textWrites == 1)
    #expect(window.markedText == "")
}

// MARK: 5.4, 5.5 — cancel and the selection in the marked text

/// 5.4 (`IM-F`) — cancel restores. "world" selected, an input method marks "ni"
/// over it, cancel: the text and the selection are untouched, nothing is
/// written. Mutation: cancel sends `.textInput("")`.
@available(macOS 15, *)
@Test @MainActor func cancelMarkedTextRestoresTheFieldAndWritesNothing() throws {
    let model = SelModel("hello world", selection: span(6, 11, in: "hello world"))
    let window = try fieldWindow(model)
    try focusField(window)
    #expect(model.read == 6..<11)
    window.setMarkedText("ni")
    #expect(window.cancelMarkedText())
    #expect(window.markedText == "")
    #expect(model.text == "hello world")
    #expect(model.textWrites == 0)
    #expect(model.read == 6..<11)
    window.typeText("W")
    #expect(model.text == "hello W", "the selection is still live: typing replaces it")
}

/// 5.5 — a range within the marked text is kept, clamped to it. Mutation: the
/// range is ignored (always the end).
@available(macOS 15, *)
@Test @MainActor func aSelectionRangeInTheMarkedTextIsKept() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    window.setMarkedText("ni hao", selectedRange: 3..<6)
    #expect(window.markedSelection == 3..<6)
    window.setMarkedText("ni hao", selectedRange: 10..<20)
    #expect(window.markedSelection == 6..<6, "clamped into the six Characters")
}

// MARK: 5.6 — SL-H end to end

/// 5.6 (`IM-G`, divergence 326) — a selection written while composing is held
/// back and superseded by the commit. Controls: the same write with no
/// composition applies. Mutations: `reconcile`'s composing guard removed;
/// `publication`'s composing guard removed.
@available(macOS 15, *)
@Test @MainActor func aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit() throws {
    let control = SelModel("hello")
    let plain = try endCaretWindow(control)
    control.selection = span(0, 1, in: control.text)
    plain.tick()
    plain.typeText("X")
    #expect(control.text == "Xello", "the control: with no composition the write applies and typing replaces it")

    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    let publishedBefore = model.published.count
    window.setMarkedText("ni")
    model.selection = span(0, 1, in: model.text)
    window.tick()
    #expect(model.published.count == publishedBefore, "nothing is published mid-composition")
    #expect(window.markedSelection == 2..<2)
    #expect(window.markedText == "ni")
    window.commitMarkedText()
    #expect(model.text == "helloni", "the held write did not move the commit")
    #expect(model.published.last == 7..<7, "the commit published the caret after the committed text")
    #expect(model.read == 7..<7)
}

// MARK: 5.7, 5.8 — accessibility and keys while composing

/// 5.7 (`IM-E`, divergence 325) — the AX value is the committed text while
/// composing. Mutation: the AX node built from the displayed (spliced) string.
@available(macOS 15, *)
@Test @MainActor func theFieldsAccessibilityValueIsTheCommittedTextWhileComposing() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    #expect(try window.focusedElement?.value == "hello")
    window.setMarkedText("ni")
    #expect(try window.focusedElement?.value == "hello")
    window.setMarkedText("ni hao")
    #expect(try window.focusedElement?.value == "hello")
    window.commitMarkedText()
    #expect(try window.focusedElement?.value == "helloni hao", "the commit commits the marked text as it stands")
}

/// 5.8 — keys belong to the input method while it composes. Mutation: the
/// `composition.text.isEmpty` early return in `TextEditing.keyDown` removed.
@available(macOS 15, *)
@Test @MainActor func typingWhileComposingBelongsToTheInputMethod() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    window.setMarkedText("ni hao", selectedRange: 3..<3)
    window.typeKey(.leftArrow)
    window.typeKey(.delete)
    #expect(model.text == "hello")
    #expect(model.textWrites == 0)
    #expect(window.markedText == "ni hao")
    #expect(window.markedSelection == 3..<3)
}

// MARK: 5.9, 5.10, 5.11 — gating, the platform's mirror, focus

/// 5.9 (`IM-C`) — no focused field, no input method. Mutation: the
/// `isTextInputActive` guard removed from the verbs.
@available(macOS 15, *)
@Test @MainActor func anInputMethodCannotBeDrivenWithoutAFocusedField() throws {
    let model = SelModel("hello")
    let window = try fieldWindow(model)
    #expect(!window.setMarkedText("ni"))
    #expect(!window.commitMarkedText())
    #expect(!window.commitMarkedText("你"))
    #expect(!window.cancelMarkedText())
    #expect(window.markedText == "")
    #expect(window.markedSelection == nil)
    #expect(model.text == "hello")
    #expect(model.textWrites == 0)
    #expect(window.platformWindow.markedText == "")
    let field = try window.frame(ofID: "field")
    window.click(at: pt(field.maxX.value - 10, midY(field)))
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "ni")
}

/// 5.10 (`IM-C`) — the platform drops marked text when the caret goes, with no
/// event to `Window`. Mutation: `setTextInputArea` does not clear the mirror.
@available(macOS 15, *)
@Test @MainActor func theHeadlessPlatformDropsMarkedTextWhenTheCaretGoes() throws {
    let model = SelModel("hello")
    let window = try endCaretWindow(model)
    window.setMarkedText("ni")
    #expect(window.platformWindow.markedText == "ni")
    window.platformWindow.setTextInputArea(nil)
    #expect(window.platformWindow.markedText == "")
    #expect(model.text == "hello")
    #expect(model.textWrites == 0, "AppKit sends the window nothing")
    #expect(!window.setMarkedText("again"), "and the input method is no longer a client")
}

/// 5.11 (`IM-I`) — a composition does not survive its field losing focus.
/// Measured first. Mutation: the focus-change clear removed.
@available(macOS 15, *)
@Test @MainActor func aCompositionDoesNotSurviveItsFieldLosingFocus() throws {
    let first = SelModel("hello")
    let second = SelModel("world")
    let window = try harnessWindow {
        VStack {
            first.field("One").id("one")
            second.field("Two").id("two")
        }
    }
    first.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    second.redraw = first.redraw
    try focusField(window, "One")
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "ni")
    try focusField(window, "Two")
    #expect(window.markedText == "")
    try focusField(window, "One")
    #expect(window.markedText == "", "no stale marked text when refocused")
    #expect(first.text == "hello")
    #expect(first.textWrites == 0)
}

// MARK: 5.12, 5.13 — a plain binding, a TextEditor

/// A draft with a log of every write, as an app's model.
@available(macOS 15, *)
@MainActor final class Draft {
    var text: String { didSet { writes.append(text); redraw?() } }
    var writes: [String] = []
    var redraw: (@MainActor () -> Void)?
    init(_ text: String) { self.text = text }
}

/// 5.12 — a composition into a `TextField`'s binding reaches the model's draft
/// only as committed text, once. Mutation: `Window.dispatch` `.textComposition`
/// also calls `applyEdit`.
@available(macOS 15, *)
@Test @MainActor func aCompositionIntoATextFieldsBindingReachesTheModelsDraft() throws {
    let draft = Draft("hello")
    let window = try harnessWindow {
        TextField("Title", text: Binding(get: { draft.text }, set: { draft.text = $0 })).id("field")
    }
    draft.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    let field = try window.frame(ofID: "field")
    window.click(at: pt(field.maxX.value - 10, midY(field)))
    window.setMarkedText("n")
    window.setMarkedText("ni")
    #expect(draft.writes.isEmpty, "the draft sees no marked text")
    window.commitMarkedText("你")
    #expect(draft.writes == ["hello你"])
    #expect(draft.text == "hello你")
}

/// 5.13 — a `TextEditor` composes at its caret. "ab\ncd" with the caret after
/// "ab": the marked text is shown on the first line (the text input area is
/// the caret rect), and the commit inserts there. Mutation: the `display`
/// splice in `TextField.swift` puts the marked text at the end of the text.
@available(macOS 15, *)
@Test @MainActor func aTextEditorComposesLikeAField() throws {
    let note = "ab\ncd"
    let model = SelModel(note, selection: caret(2, in: note))
    let window = try harnessWindow { model.editor().id("note") }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try focusField(window, "Note")
    let rest = try #require(window.platformWindow.textInputAreas.last ?? nil)
    #expect(window.setMarkedText("ni"))
    #expect(window.markedSelection == 2..<2)
    let during = try #require(window.platformWindow.textInputAreas.last ?? nil)
    #expect(during.origin.y == rest.origin.y, "the marked text is on the caret's line")
    #expect(during.origin.x > rest.origin.x, "and the caret moved right past it")
    #expect(model.textWrites == 0)
    window.commitMarkedText()
    #expect(model.text == "abni\ncd")
    #expect(model.textWrites == 1)
    #expect(model.read == 4..<4)
}

// MARK: 5.14, 5.15 — undo after a selection write (IM-H)

/// 5.14 (`IM-H`, `SL-O`) — the undo contract after a selection write, measured.
/// Mutations: `reconcile` stops clearing `openGroup`; `recording` keeps the
/// old selection.
@available(macOS 15, *)
@Test @MainActor func theUndoContractAfterASelectionWrite() throws {
    // (3) the control: no write, one step.
    let control = SelModel("")
    let plain = try fieldWindow(control)
    try focusField(plain)
    plain.typeText("a"); plain.typeText("b"); plain.typeText("c")
    plain.typeKey("z", modifierFlags: .primary)
    #expect(control.text == "")

    // (1), (2) a write ends the group; undo restores the written selection.
    let model = SelModel("")
    let window = try fieldWindow(model)
    try focusField(window)
    window.typeText("a"); window.typeText("b")
    model.selection = caret(0, in: model.text)
    window.tick()
    window.typeText("c")
    #expect(model.text == "cab")
    window.typeKey("z", modifierFlags: .primary)
    #expect(model.text == "ab", "only c is undone")
    #expect(model.read == 0..<0, "the caret the write left, before c was typed")
    window.typeKey("z", modifierFlags: .primary)
    #expect(model.text == "", "the second step removes ab")

    // (4) a write equal to the field's own selection ends nothing.
    let same = SelModel("")
    let equal = try fieldWindow(same)
    try focusField(equal)
    equal.typeText("a"); equal.typeText("b")
    same.selection = caret(2, in: same.text)
    equal.tick()
    equal.typeText("c")
    equal.typeKey("z", modifierFlags: .primary)
    #expect(same.text == "", "an equal write is not an instruction: one step")
}

/// 5.15 (`IM-H` (5)) — a commit of one grapheme continues the typing group, a
/// longer one is its own step. Mutation: `insert`'s `inserted.count == 1` rule changed.
@available(macOS 15, *)
@Test @MainActor func aCommitOfOneGraphemeContinuesTheTypingGroupAndALongerOneDoesNot() throws {
    let one = SelModel("")
    let single = try fieldWindow(one)
    try focusField(single)
    single.typeText("a")
    single.setMarkedText("ni")
    single.commitMarkedText("你")
    #expect(one.text == "a你")
    single.typeKey("z", modifierFlags: .primary)
    #expect(one.text == "", "one grapheme joins the typing group: one step")

    let two = SelModel("")
    let double = try fieldWindow(two)
    try focusField(double)
    double.typeText("a")
    double.setMarkedText("ni hao")
    double.commitMarkedText("你好")
    #expect(two.text == "a你好")
    double.typeKey("z", modifierFlags: .primary)
    #expect(two.text == "a", "two graphemes are their own step")
}

// MARK: Recipe — the exact code of `docs/testing.md` "Recipe: driving an input method"

@MainActor final class ComposeRecipeModel {
    var text = "hello"
    var writes: [String] = []
}

/// The worked example in `docs/testing.md`, run for real so the doc cannot rot.
/// Change this test and the doc together. Mutation: `setMarkedText` sends
/// `.textInput` (the first `writes` expectation reddens).
@Test @MainActor func theInputMethodRecipeRuns() throws {
    let model = ComposeRecipeModel()
    let window = try harnessWindow {
        TextField("Name", text: model.text) { model.writes.append($0); model.text = $0 }
            .frame(width: Pixels(200), height: Pixels(24))
            .accessibilityIdentifier("name")
    }
    try window.click(try window.element(identifier: "name"))

    // The input method marks text: the field shows it, the model has not heard.
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "ni")
    #expect(model.writes.isEmpty)
    #expect(try window.focusedElement?.value == "hello", "the AX value is the committed text")

    // It commits the candidate it chose: one write, the marked text gone.
    #expect(window.commitMarkedText("你"))
    #expect(model.writes.count == 1)
    #expect(window.markedText == "")

    // A cancelled composition writes nothing.
    window.setMarkedText("hao")
    window.cancelMarkedText()
    #expect(model.writes.count == 1)
}
