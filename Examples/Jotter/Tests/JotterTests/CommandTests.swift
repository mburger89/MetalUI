import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func theCommandsMenuShortcutsRunTheirActions() throws {
    let model = seededModel()
    let (app, window) = try jotterApp(model)
    let titles = app.menuBar.flatMap { menu in menu.items.map(\.title) }
    #expect(titles.contains("New Note") && titles.contains("Duplicate Note") && titles.contains("Delete Note"))

    // The shortcut and the menu item run the same action.
    window.typeKey("n", modifierFlags: .primary)
    #expect(model.notes.count == 5)
    #expect(model.notes.first?.title == "Untitled")
    try app.performMenuBarItem("File", "New Note")
    #expect(model.notes.count == 6)

    // Duplicate copies the selection, under a new id.
    let selected = try #require(model.selectedNote)
    window.typeKey("d", modifierFlags: .primary)
    #expect(model.notes.count == 7)
    #expect(model.selectedNote?.id != selected.id)
    #expect(model.selectedNote?.title == selected.title + " copy")

    // Delete asks first; the answer is the dialog's. A focused text field keeps ⌘⌫ for itself
    // (delete to the line start), so focus moves to the list first, by a click on a row.
    try window.click(window.element(identifier: rowIdentifier(model.notes[0])))
    window.typeKey(.delete, modifierFlags: .primary)
    let dialog = try #require(window.presentedAlert)
    #expect(dialog.buttons.map(\.title) == ["Delete", "Cancel"])
    try window.respondToAlert(button: "Cancel")
    #expect(model.notes.count == 7)

    // View > Statistics toggles the panel; Theme toggles the scheme.
    try app.performMenuBarItem("View", "Statistics")
    #expect(model.showsStats)
    try app.performMenuBarItem("View", "Dark Appearance")
    #expect(model.scheme == .dark)
}

@MainActor
@Test func theFileCommandsOpenThePanels() throws {
    let model = seededModel()
    let (app, window) = try jotterApp(model)
    try app.performMenuBarItem("File", "Export...")
    #expect(window.presentedFileDialog?.kind == .save(defaultFilename: "Jotter"))
    try window.cancelFileDialog()
    try app.performMenuBarItem("File", "Open...")
    #expect(window.presentedFileDialog?.kind == .open(allowsMultipleSelection: false))
    try window.cancelFileDialog()
}
