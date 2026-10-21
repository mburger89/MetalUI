import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func launchShowsTheSeededNotesAndSelectsTheFirst() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    #expect(try rowIDs(window) == model.notes.map(rowIdentifier))
    #expect(model.selection == model.notes.first?.id)
    #expect(try window.element(identifier: "title-field").value == "Welcome to Jotter")
}

@MainActor
@Test func newNoteAddsARowSelectsItAndFocusesTheTitle() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    try window.performToolbarItem("new")
    window.tick()
    let first = try #require(model.notes.first)
    #expect(model.notes.count == 5)
    #expect(first.title == "Untitled")
    #expect(model.selection == first.id)
    #expect(try rowIDs(window).first == rowIdentifier(first))
    #expect(try window.focusedElement?.identifier == "title-field")
}

@MainActor
@Test func selectingARowShowsItsNoteInTheDetail() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let second = model.notes[1]
    try window.click(window.element(identifier: rowIdentifier(second)))
    #expect(model.selection == second.id)
    #expect(try window.element(identifier: "title-field").value == "Shopping")
    #expect(try window.element(identifier: "body-field").value == second.body)
}
