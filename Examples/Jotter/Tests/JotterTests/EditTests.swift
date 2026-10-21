import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func typingInTheTitleAndBodyEditsTheSelectedNoteOnly() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let before = model.notes
    // The second note is selected, so an edit that wrote to the first would show.
    try window.click(window.element(identifier: rowIdentifier(before[1])))
    try window.click(window.element(identifier: "title-field"))
    window.typeKey("a", modifierFlags: .primary)
    window.typeText("Groceries")
    #expect(model.notes[1].title == "Groceries")
    try window.click(window.element(identifier: "body-field"))
    window.typeKey("a", modifierFlags: .primary)
    window.typeText("eggs and rye #errands")
    #expect(model.notes[1].body == "eggs and rye #errands")
    #expect(model.notes[0] == before[0], "the first note is untouched")
    #expect(model.notes[2] == before[2])
    #expect(model.notes.map(\.id) == before.map(\.id))
    #expect(try window.element(label: "Groceries").role == .staticText, "the row follows the edit")
}

@MainActor
@Test func theWordCountFollowsTheBodyOfTheSelectedNote() async throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    try await window.runUntilIdle()
    #expect(model.selectedWordCount == model.notes[0].wordCount)
    try window.click(window.element(identifier: "body-field"))
    window.typeKey("a", modifierFlags: .primary)
    window.typeText("one two three")
    try await window.runUntilIdle()
    #expect(model.selectedWordCount == 3)
    #expect(try window.element(label: "3 words").role == .staticText)
    // Another note, another count: the task re-runs for the note shown, not only for its text.
    try window.click(window.element(identifier: rowIdentifier(model.notes[1])))
    try await window.runUntilIdle()
    #expect(model.selectedWordCount == model.notes[1].wordCount)
}
