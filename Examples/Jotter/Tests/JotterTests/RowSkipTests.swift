import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func anUnchangedRowIsNotEvaluatedWhenAnotherNoteIsEdited() throws {
    let model = seededModel()
    // `recordsLayout: false`: the window does only production work, so the counters are the app's.
    let window = try jotterWindow(model, recordsLayout: false)
    window.resetFrameWork()
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.lastFrameWork.contentEvaluations == 0, "a frame with nothing changed evaluates no row")
    #expect(window.lastFrameWork.contentSkips == 4, "all four rows are skipped")
    // One note's body changes: its row is evaluated, the other three are skipped.
    model.setBody("something else entirely", of: model.notes[2].id)
    window.window.setNeedsRedraw()
    window.tick()
    let work = window.lastFrameWork
    #expect(work.contentEvaluations == 1)
    #expect(work.contentSkips == 3)
    #expect(work.contentRefusals == 0)
}
