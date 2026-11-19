@testable import MetalUI
import MetalUITesting
import Testing

// What a window with no table costs (`TBL-M`, record 388; spec section 6). PR A adds `Frame.tableWork` and five public `FrameWork`
// fields, every one of them 0 in a window with no table, and two literals measured on master `91a9904e` BEFORE any change that
// stays unchanged afterwards. The table's own cost pins arrive with `Table` itself (PR B). Every count is read after
// `runUntilIdle` (off Darwin a dirty mark hops through a Task) and summed over `frameWork`, never `lastFrameWork`. The harness
// text system; windows kept alive.

@MainActor private final class DxLog { var lastBuiltDx: Float = -1; var builds = 0 }

/// `PointerDragFrameCostTests`' `WriterChip` (R5's fixture), restated here because that one is private.
private struct WriterChip: Component {
    let log: DxLog
    @State var dx: Float = 0
    var content: some ElementGroup {
        let _ = { log.lastBuiltDx = dx; log.builds += 1 }()
        VStack(spacing: 0) {
            Rectangle().frame(width: Pixels(200), height: Pixels(200))
                .gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { v in dx = Float(v.translation.width.value) })
            Rectangle().frame(width: Pixels(20 + dx), height: Pixels(10))
        }
    }
}

private struct PlainRow: Identifiable { let id: Int }

/// **T1** A window holding no table reports no table work, in any of the five fields, summed over every frame it took to
/// settle. Mutation: initialise `TableWork.coldFrames` to 1 (every build then counts a cold table frame).
@Test @MainActor func aWindowWithoutATableReportsNoTableWork() async throws {
    let w = try harnessWindow { Text("a") }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    let all = w.frameWork.reduce(FrameWork(), +)
    #expect(all.builds > 0)
    #expect(all.tableRowsRealized == 0, "rows \(all.tableRowsRealized)")
    #expect(all.tableCellsRealized == 0, "cells \(all.tableCellsRealized)")
    #expect(all.tableColumnsResolved == 0, "columns \(all.tableColumnsResolved)")
    #expect(all.tableDataReads == 0, "reads \(all.tableDataReads)")
    #expect(all.tableColdFrames == 0, "cold \(all.tableColdFrames)")
}

/// **T2** A window with no table keeps its steady element requests: R5's `WriterChip` fixture costs 6 and a `List` of 40 rows at
/// `rowHeight` 28 in a 300-point `ScrollView` costs the literal below, both measured on master `91a9904e` before this PR touched
/// anything (`List.window` now forwards to `UniformWindow.lines`, unchanged). Mutation: `List.overscan = 3`, which moves the
/// `List` literal (more rows realised).
@Test @MainActor func aWindowWithoutATableKeepsItsSteadyRequests() async throws {
    let log = DxLog()
    let chip = try harnessWindow { Column { WriterChip(log: log) } }
    try await chip.runUntilIdle()
    chip.window.setNeedsRedraw(); chip.tick()
    let steady = chip.lastFrameWork.elementRequests
    print("TBL-M R5 literal: steady elementRequests \(steady)")
    #expect(steady == 6, "steady \(steady)")

    let list = try harnessWindow(size: sz(300, 300)) {
        ScrollView { List((0..<40).map(PlainRow.init), rowHeight: Pixels(28)) { r in Text("row \(r.id)") } }
            .frame(width: Pixels(300), height: Pixels(300))
    }
    try await list.runUntilIdle()
    list.window.setNeedsRedraw(); list.tick()
    let listSteady = list.lastFrameWork.elementRequests
    print("TBL-M List literal: steady elementRequests \(listSteady)")
    #expect(listSteady == 28, "list steady \(listSteady)")
}
