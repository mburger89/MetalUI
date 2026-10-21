import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func deleteAsksForConfirmationAndOnlyConfirmDeletes() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    try window.performToolbarItem("delete")
    let dialog = try #require(window.presentedAlert)
    #expect(dialog.buttons.map(\.title) == ["Delete", "Cancel"])
    #expect(model.notes.count == 4, "nothing is deleted before the answer")
    try window.respondToAlert(button: "Cancel")
    #expect(model.notes.count == 4, "Cancel keeps the note")
    #expect(window.presentedAlert == nil)
    try window.performToolbarItem("delete")
    try window.respondToAlert(button: "Delete")
    #expect(model.notes.count == 3)
    #expect(try rowIDs(window).count == 3)
}

@MainActor
@Test func deletingTheSelectedNoteSelectsTheNeighbour() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let originals = model.notes
    // The first note goes: the note that took its place is selected.
    try window.performToolbarItem("delete")
    try window.respondToAlert(button: "Delete")
    #expect(model.selection == originals[1].id)
    // The last note goes: the one before it is selected.
    try window.click(window.element(identifier: rowIdentifier(originals[3])))
    try window.performToolbarItem("delete")
    try window.respondToAlert(button: "Delete")
    #expect(model.selection == originals[2].id)
    #expect(try window.element(identifier: "title-field").value == "Ideas")
    // Deleting a note that is not selected leaves the selection alone.
    try window.rightClick(window.element(identifier: rowIdentifier(originals[1])))
    try window.chooseMenuItem("Delete")
    try window.respondToAlert(button: "Delete")
    #expect(model.notes.map(\.id) == [originals[2].id])
    #expect(model.selection == originals[2].id)
}
