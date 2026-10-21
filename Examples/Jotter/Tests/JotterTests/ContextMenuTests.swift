import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func contextMenuDuplicateCopiesTheNote() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let original = model.notes[1]
    try window.rightClick(window.element(identifier: rowIdentifier(original)))
    let menu = try #require(window.presentedMenu)
    #expect(menu.items.filter { $0.kind == .action }.map(\.title) == ["Duplicate", "Delete"])
    try window.chooseMenuItem("Duplicate")
    #expect(model.notes.count == 5)
    let copy = model.notes[2]
    #expect(copy.id != original.id, "a copy has its own id")
    #expect(copy.title == "Shopping copy")
    #expect(copy.body == original.body)
    #expect(model.notes[1] == original, "the original is untouched, just before its copy")
    #expect(model.selection == copy.id)
    #expect(Set(model.notes.map(\.id)).count == 5)
}
