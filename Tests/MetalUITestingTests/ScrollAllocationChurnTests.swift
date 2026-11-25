@testable import MetalUI
import Foundation
import MetalUITesting
import MetalUITestSupport
import Testing

// `SB-AG` to `HP-L` (record 412): what one scroll step of a table of `.equatable()` cells allocates, in a debug build, on
// the harness text system. The step is a translated replay (`retainedTranslated > 0`), so what is counted is the retained
// path's own work: the move of each cell's paint record (`movedPaintRecord`), the replay of its final stream (`replayPaint`), the
// build journal's copies at the close of each occurrence's window (`closeGraftWindow`) and the growth of the scene's arrays.
// The numbers are ceilings measured on this fixture, a few percent over: a change that restores an old copy goes over them.

private struct ChurnRow: Identifiable { let id: Int }
private final class ChurnRows: RandomAccessCollection {
    let n: Int
    init(_ n: Int) { self.n = n }
    var startIndex: Int { 0 }
    var endIndex: Int { n }
    subscript(position: Int) -> ChurnRow { ChurnRow(id: position) }
}

private struct ChurnCell: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text) }
}

private struct ChurnPane: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Table(ChurnRows(1_000_000)) {
            TableColumnForEach(0..<5) { c in
                TableColumn("c\(c)") { r in ChurnCell(text: "r\(r.id)c\(c)").equatable() }.width(Pixels(110))
            }
        }.tableRowHeight(Pixels(24))
    }
    static func == (l: ChurnPane, r: ChurnPane) -> Bool { true }
}

/// A pane that never changes beside the table (Alloy's file tree and chat): its record is replayed as it stands every frame, an
/// op for every glyph, the final stream's single-group arm (`SB-AG`).
private struct ChurnSidebar: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { i in Text("Sources/Module/File\(i).swift").frame(height: Pixels(22)) }
        }
    }
    static func == (l: ChurnSidebar, r: ChurnSidebar) -> Bool { true }
}

/// Three `.equatable()` wrappers around the pane, as Alloy nests it: an outer occurrence's record holds every cell's leaves.
private struct ChurnOuter3: Component, @MainActor Equatable {
    var content: some ElementGroup { ChurnPane().equatable() }
    static func == (l: ChurnOuter3, r: ChurnOuter3) -> Bool { true }
}
private struct ChurnOuter2: Component, @MainActor Equatable {
    var content: some ElementGroup { VStack(spacing: 0) { ChurnOuter3().equatable() } }
    static func == (l: ChurnOuter2, r: ChurnOuter2) -> Bool { true }
}
private struct ChurnOuter1: Component, @MainActor Equatable {
    var content: some ElementGroup { VStack(spacing: 0) { ChurnOuter2().equatable() } }
    static func == (l: ChurnOuter1, r: ChurnOuter1) -> Bool { true }
}

/// A window with the pane scrolled far from the top and warmed, so every step that follows moves a window of cached cells.
@MainActor private func churnWindow() async throws -> TestWindow {
    let options = HeadlessPlatformWindow.Options(accessibilityClientActive: false)
    let w = try harnessWindow(size: sz(800, 500), options: options, recordsLayout: false) {
        HStack(spacing: 0) { ChurnSidebar().equatable().frame(width: Pixels(200)); ChurnOuter1().equatable() }
    }
    try await w.runUntilIdle()
    w.scroll(at: pt(400, 250), byDeltaX: 0, deltaY: -12000)
    try await w.runUntilIdle()
    for _ in 0..<8 { w.scroll(at: pt(400, 250), byDeltaX: 0, deltaY: -24); try await w.runUntilIdle() }
    return w
}

/// **AC-1** One step of the scroll: the cells translate (so the retained path is the one counted), and the step allocates under
/// the ceilings. Mutations: `movedPaintRecord` moving the final stream a second time (`old.finalIsScene` ignored): the
/// allocations rise by two arrays per glyph; `replayPaint` flattening each op's leaves (`op.leaves.flatMap(\.0)` for every op): by
/// one per glyph; `closeGraftWindow` copying the journal's slice at the close: the bytes rise by a journal per window;
/// the scene's arrays are pinned by `theSecondFrameReservesWhatTheFirstFrameHeld` (a fixture this small grows them by 13 allocations).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 compares every hit with a fresh run: the allocation count is not its to read"))
@MainActor func aScrollStepOfRetainedCellsAllocatesUnderItsCeiling() async throws {
    #if canImport(Darwin)
    let w = try await churnWindow()
    w.resetFrameWork()
    var seen: (allocations: Int, bytes: Int)?
    seen = countAllocatedBytes { w.scroll(at: pt(400, 250), byDeltaX: 0, deltaY: -24) }
    let measured = try #require(seen)
    let work = w.frameWork.reduce(FrameWork(), +)
    print("G47 churn step: allocations \(measured.allocations) bytes \(measured.bytes) translated \(work.retainedTranslated) hits \(work.retainedHits) misses \(work.retainedMisses)")
    #expect(work.retainedTranslated > 0, "the step replays translated cells: \(work.retainedTranslated)")
    #expect(measured.allocations <= churnAllocationCeiling, "allocations \(measured.allocations)")
    #expect(measured.bytes <= churnByteCeiling, "bytes \(measured.bytes)")
    withExtendedLifetime(w) {}
    #endif
}

/// **AC-2** A redraw with nothing moved replays every cached cell's final stream as it stands (`op.leaves.flatMap(\.0)` made an array
/// per glyph): the frame hits, and it allocates under the ceilings. Mutation: the single-group arm of `replayPaint` removed.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 compares every hit with a fresh run: the allocation count is not its to read"))
@MainActor func aRedrawOfRetainedCellsReplaysTheFinalStreamWithoutCopies() async throws {
    #if canImport(Darwin)
    let w = try await churnWindow()
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick(); try await w.runUntilIdle() }
    w.resetFrameWork()
    var seen: (allocations: Int, bytes: Int)?
    w.window.setNeedsRedraw()
    seen = countAllocatedBytes { w.tick() }
    let measured = try #require(seen)
    let work = w.frameWork.reduce(FrameWork(), +)
    print("G47 redraw: allocations \(measured.allocations) bytes \(measured.bytes) hits \(work.retainedHits) misses \(work.retainedMisses) builds \(work.builds)")
    #expect(work.builds > 0 && work.retainedHits > 0, "the redraw replays cached cells: builds \(work.builds) hits \(work.retainedHits)")
    #expect(measured.allocations <= redrawAllocationCeiling, "allocations \(measured.allocations)")
    #expect(measured.bytes <= redrawByteCeiling, "bytes \(measured.bytes)")
    withExtendedLifetime(w) {}
    #endif
}

// Measured on this fixture in a debug build (`--build-system native`): a scroll step 66027 allocations, 4604158 bytes; a redraw
// 57710, 3785794. With each change restored: the final stream moved twice (`finalIsScene` ignored) 74011 / 5276766 and 60713 /
// 3977658; the final stream flattened per op 68427 / 5013758 and 60109 / 4195130; the journal copied at the close 67237 / 4951614 and
// 58919 / 4132986. The ceilings sit between the measurement and the smallest of those.
private let churnAllocationCeiling = 66600
private let churnByteCeiling = 4_700_000
private let redrawAllocationCeiling = 58300
private let redrawByteCeiling = 3_880_000
