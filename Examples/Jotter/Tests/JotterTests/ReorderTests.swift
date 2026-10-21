import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func draggingARowOntoAnotherReordersTheModel() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let ids = model.notes.map(\.id)
    // Dragged down, the note lands after its target: [0, 1, 2, 3] -> [1, 2, 0, 3].
    let first = try window.element(identifier: rowIdentifier(model.notes[0]))
    let third = try window.element(identifier: rowIdentifier(model.notes[2]))
    window.drag(from: centre(of: first), to: centre(of: third), steps: 8)
    #expect(model.notes.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
    #expect(try rowIDs(window) == model.notes.map(rowIdentifier), "the sidebar shows the new order")
    // Dragged up, it lands before its target: the last row onto the first.
    let last = try window.element(identifier: rowIdentifier(model.notes[3]))
    let top = try window.element(identifier: rowIdentifier(model.notes[0]))
    window.drag(from: centre(of: last), to: centre(of: top), steps: 8)
    #expect(model.notes.map(\.id) == [ids[3], ids[1], ids[2], ids[0]])
    // A drag is not a click: the selection did not move.
    #expect(model.selection == ids[0])
}
