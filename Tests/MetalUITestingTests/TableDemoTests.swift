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
