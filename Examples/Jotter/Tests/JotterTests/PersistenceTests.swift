import Foundation
import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func exportWritesVersionedJSONAndImportReadsItBack() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let original = model.notes
    let file = scratchFile("notes.json")

    try window.performToolbarItem("export")
    let save = try #require(window.presentedFileDialog)
    #expect(save.kind == .save(defaultFilename: "Jotter"))
    try window.respondToFileDialog(choosing: [file.path])
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("\"version\" : 1"), "the file names its version")
    #expect(window.presentedFileDialog == nil)

    // Change the notes, then open the file: it replaces them, it does not append.
    try window.performToolbarItem("delete")
    try window.respondToAlert(button: "Delete")
    try window.performToolbarItem("new")
    #expect(model.notes.map(\.id) != original.map(\.id))
    try window.performToolbarItem("import")
    let open = try #require(window.presentedFileDialog)
    #expect(open.kind == .open(allowsMultipleSelection: false))
    try window.respondToFileDialog(choosing: [file.path])
    #expect(model.notes == original)
    #expect(model.selection == original.first?.id)
    #expect(try rowIDs(window) == original.map(rowIdentifier))
}

@MainActor
@Test func importingGarbageShowsAnAlertAndKeepsTheNotes() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let original = model.notes
    let garbage = scratchFile("garbage.json")
    try Data("this is not json".utf8).write(to: garbage)
    try window.performToolbarItem("import")
    try window.respondToFileDialog(choosing: [garbage.path])
    let alert = try #require(window.presentedAlert)
    #expect(alert.title == "Could not open the file")
    #expect(alert.message == "That file is not a Jotter file.")
    try window.respondToAlert(button: "OK")
    #expect(model.notes == original, "a failed load changes nothing")

    // A well-formed file of a newer version is refused by name.
    let future = scratchFile("future.json")
    try Data(#"{"version": 2, "notes": []}"#.utf8).write(to: future)
    try window.performToolbarItem("import")
    try window.respondToFileDialog(choosing: [future.path])
    #expect(try #require(window.presentedAlert).message == "Jotter files of version 2 are not supported.")
    try window.respondToAlert(button: "OK")
    #expect(model.notes == original)
}
