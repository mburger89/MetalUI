import Testing
import MetalUI
import MetalUITesting

// Lane 1's end-to-end wiring of the selection binding (SL-B, SL-D): the real
// `Window` over the headless platform. The full matrix is
// `HarnessTextSelectionTests.swift` (lane 2).

@MainActor private final class SelectionModel {
    var text: String
    var selection: Any?
    init(_ text: String) { self.text = text }
}

@available(macOS 15, *)
@MainActor private func current(_ model: SelectionModel) -> TextSelection? { model.selection as? TextSelection }

@available(macOS 15, *)
@Test @MainActor func aBoundWholeSelectionIsInTheFirstFrameAndTypingReplacesIt() throws {
    let model = SelectionModel("hello")
    model.selection = TextSelection(range: model.text.startIndex..<model.text.endIndex)
    let window = try harnessWindow {
        TextField("Title", text: Binding(get: { model.text }, set: { model.text = $0 }),
                  selection: Binding(get: { current(model) }, set: { model.selection = $0 }))
    }
    try window.focus(window.element(label: "Title"))
    window.typeText("New")
    #expect(model.text == "New")
}

@available(macOS 15, *)
@Test @MainActor func withoutABindingTheCaretStaysAtTheStart() throws {
    let model = SelectionModel("hello")
    let window = try harnessWindow {
        TextField("Title", text: Binding(get: { model.text }, set: { model.text = $0 }))
    }
    try window.focus(window.element(label: "Title"))
    window.typeText("New")
    #expect(model.text == "Newhello")
}

@available(macOS 15, *)
@Test @MainActor func aNoteOpensWithTheCaretAtItsEndAndTheEditorPublishesTyping() throws {
    let model = SelectionModel("one\ntwo")
    model.selection = TextSelection(insertionPoint: model.text.endIndex)
    let window = try harnessWindow {
        TextEditor("Note", text: Binding(get: { model.text }, set: { model.text = $0 }),
                   selection: Binding(get: { current(model) }, set: { model.selection = $0 }))
    }
    try window.focus(window.element(label: "Note"))
    window.typeText("!")
    #expect(model.text == "one\ntwo!")
    let selection = try #require(current(model))
    #expect(selection == TextSelection(insertionPoint: model.text.endIndex))
}

@available(macOS 15, *)
@Test @MainActor func aClickAndTypingPublishTheirCaretToTheBinding() throws {
    let model = SelectionModel("hello")
    let window = try harnessWindow {
        TextField("Title", text: Binding(get: { model.text }, set: { model.text = $0 }),
                  selection: Binding(get: { current(model) }, set: { model.selection = $0 }))
    }
    // The click lands right of the text: the caret goes to its end and is published.
    window.click(at: pt(200, 150))
    #expect(current(model) == TextSelection(insertionPoint: "hello".endIndex))
    window.typeText("X")
    #expect(model.text == "helloX")
    #expect(current(model) == TextSelection(insertionPoint: model.text.endIndex))
}
