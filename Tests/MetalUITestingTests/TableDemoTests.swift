@testable import MetalUI
import MetalUIDemoContent
import MetalUITesting
import Testing

/// **B7** The table demo (`METALUI_TABLE_DEMO=1`) builds and realises cells, and one wheel step through its 1 000 000 x 200 table is one build
/// (`TBL-M`). Mutation: the demo's rows count every `count` read as a full scan is not testable here; the pin is the
/// build count, red if a step needs a second build (the header or window staleness loop).
@Test @MainActor func theTableDemoBuildsAndScrollsInOneBuildPerStep() async throws {
    let w = try harnessWindow(size: sz(1100, 700)) { tableDemoContent() }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    #expect(w.lastFrameWork.tableCellsRealized > 0, "cells \(w.lastFrameWork.tableCellsRealized)")
    w.resetFrameWork()
    w.scroll(at: Point(x: Pixels(500), y: Pixels(300)), byDeltaX: 0, deltaY: -24)
    try await w.runUntilIdle()
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(all.builds == 1, "builds \(all.builds)")
}

/// **TCM-demo** The demo's cell-mode sheet builds, takes a click, edits a cell and commits it (`TCM-F`, record 394): the switch is on
/// the row table by default, so `theTableDemoBuildsAndScrollsInOneBuildPerStep` is unchanged. Mutation: the sheet's `onCommit` does
/// not store the text (the edited cell keeps its old value).
@Test @MainActor func theTableDemosCellModeEditsASheet() async throws {
    let w = try harnessWindow(size: sz(1100, 700)) { tableDemoContent() }
    try await w.runUntilIdle()
    try w.click(try w.element(label: "Cell mode"))
    try await w.runUntilIdle()
    // Column 2 of row 2 is editable (column 0 is the frozen "#" column, whose cells are not).
    w.click(at: Point(x: Pixels(60 + 120 + 60 + 12), y: Pixels(12 + 30 + 6 + 20 + 28 + 24 + 12)))
    try await w.runUntilIdle()
    w.typeText("Q"); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    _ = try w.element(label: "Committed (2, 2): \"Q\"")   // the sheet's log line names the cell and the text
}
