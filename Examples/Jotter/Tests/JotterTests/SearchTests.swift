import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func searchFiltersTheSidebarAndClearingRestoresIt() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    // "MILK" is in the body of "Shopping" only, and in another case.
    try window.performToolbarItem("search", action: .text("MILK"))
    #expect(try rowIDs(window) == [rowIdentifier(model.notes[1])])
    // A title match and a body match both count; nothing matches a stranger.
    try window.performToolbarItem("search", action: .text("ideas"))
    #expect(try rowIDs(window) == [rowIdentifier(model.notes[2])])
    try window.performToolbarItem("search", action: .text("zzz"))
    #expect(try rowIDs(window).isEmpty)
    try window.performToolbarItem("search", action: .text(""))
    #expect(try rowIDs(window) == model.notes.map(rowIdentifier))
}
