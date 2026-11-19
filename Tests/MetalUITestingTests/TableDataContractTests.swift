@testable import MetalUI
import MetalUITesting
import Testing

// The row-source contract (`TBL-D`, record 389; Review Focus 1): a table reads `data.count` once per build and `data[i]` once per
// realised row, and nothing else, so a million rows cost what ten do. `CountingRows` counts every `count`, `endIndex` and `subscript`
// read; a read in a path the table owns that scans the data shows here as a count of thousands.

/// **B5-1** At the steady offsets of a 1 000 000-row table one steady frame reads the 28 realised rows once each and the count once:
/// `subscriptReads == 28`, `countReads == 1`, `tableDataReads == 28`. Mutation: read `data[i]` twice per row (once for the id and once
/// for the value): 56.
@Test @MainActor func aTableReadsEachRealisedRowOnceAndTheCountOncePerBuild() async throws {
    let rows = CountingRows(1_000_000)
    let w = try tableFixture(rows: 1_000_000, columns: 200, data: rows)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    rows.resetCounts()
    w.resetFrameWork()
    w.window.setNeedsRedraw(); w.tick()
    #expect(rows.subscriptReads == steadyRows, "subscript reads \(rows.subscriptReads)")
    #expect(rows.countReads == 1, "count reads \(rows.countReads)")
    #expect(w.lastFrameWork.tableDataReads == steadyRows, "table reads \(w.lastFrameWork.tableDataReads)")
    #expect(w.lastFrameWork.builds == 1)
}

/// **B5-2** One scroll step reads only the new window: 28 rows' values, never the rows between. Mutation: none beyond B5-1's (the
/// step is the same build).
@Test @MainActor func aScrollStepReadsOnlyTheNewWindow() async throws {
    let rows = CountingRows(1_000_000)
    let w = try tableFixture(rows: 1_000_000, columns: 200, data: rows)
    try await scrollTable(w, x: steadyOffsets.x, y: steadyOffsets.y)
    rows.resetCounts()
    w.resetFrameWork()
    w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -24)
    try await w.runUntilIdle()
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(rows.subscriptReads == steadyRows * all.builds, "reads \(rows.subscriptReads) over \(all.builds) builds")
    #expect(all.builds == 1, "builds \(all.builds)")
    #expect(rows.subscriptReads == steadyRows)
}
