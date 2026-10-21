import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func theStatsCanvasSummaryNamesTheCountsAndFollowsEdits() throws {
    let model = seededModel()
    let window = try jotterWindow(model)
    let words = model.notes.reduce(0) { $0 + $1.wordCount }
    try window.performToolbarItem("stats")
    #expect(try window.element(identifier: "stats-summary").value == "4 notes, \(words) words")
    // The bars: one per note, each named for its note and its count.
    let bars = try window.elements(where: { ($0.identifier ?? "").hasPrefix("bar-") })
    #expect(bars.count == 4)
    #expect(bars.map(\.label) == model.notes.map { "\($0.title): \($0.wordCount) words" })
    // An edit shows in the summary of the next frame.
    model.setBody("one two three", of: model.notes[0].id)
    let edited = model.notes.reduce(0) { $0 + $1.wordCount }
    window.window.setNeedsRedraw()
    window.tick()
    #expect(try window.element(identifier: "stats-summary").value == "4 notes, \(edited) words")
    #expect(try window.element(identifier: "bar-0").label == "Welcome to Jotter: 3 words")
    #expect(edited != words)
    // The toggle goes back.
    try window.performToolbarItem("stats")
    #expect(try window.element(identifier: "title-field").value == "Welcome to Jotter")
}
