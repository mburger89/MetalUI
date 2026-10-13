import Testing
import MetalUI
import MetalUITesting
import MetalUIDemoContent

// The text-selection demo (`METALUI_SELECTION_DEMO=1`, ruling `SL-N`) under the
// harness: a double click on the title opens the rename field with the whole
// title selected, so typing replaces it; "Open note" puts the caret at the
// note's end. Mutation: skip `reconcile` in `TextField.prepaint` (the title
// keeps its caret at the start) or in `TextEditor.prepaint`.

@available(macOS 15, *)
@Test @MainActor func theSelectionDemoRenamesWithTheWholeTitleSelectedAndOpensANoteAtItsEnd() throws {
    selectionDemoModel.reset()
    defer { selectionDemoModel.reset() }
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(560)),
                                content: selectionDemoContent)
    let title = try window.element(label: "Quarterly plan")
    try window.doubleClick(title)
    #expect(selectionDemoModel.renaming)
    window.tick()
    #expect(try window.focusedElement?.label == "Title", "the rename field took the focus from code")
    window.typeText("Plan B")
    #expect(selectionDemoModel.title == "Plan B", "all of the title was selected")
    #expect(SelectionDemoModel.readout(selectionDemoModel.titleSelection, in: selectionDemoModel.title)
            == "selection 6..<6")

    try window.click(window.element(label: "Open note"))
    window.tick()
    window.typeText("!")
    #expect(selectionDemoModel.note == "Line one\nLine two\nLine three!", "the caret was at the end")
}
