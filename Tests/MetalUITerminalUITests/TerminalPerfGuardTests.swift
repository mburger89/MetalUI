import Foundation
import MetalUIScene
import MetalUIShaderTypes
import MetalUITerminal
import MetalUITesting
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 6 (`TRM-BK`): the counted guards of the view's frame cost that earlier phases left open, and the UI half
// of the gated bench. Each test names the mutation it was shown red against.

/// **1** (`TRM-BK` item 1) A selection frame is a surface-only frame: a selection set or cleared through the source
/// (what a drag does through `perform`) redraws the rows it covers and costs 0 builds and 0 element requests, one surface
/// draw and one snapshot. Setting one from outside the view costs one more, empty frame: the draw sees a selection whose
/// Copy text the view has not fetched and asks the emulator's queue for it (`syncSelectionText`), so the second frame takes
/// a snapshot with no damaged rows (0 rows drawn, still 0 builds and 0 element requests); the third draws nothing. Clearing
/// costs the one frame. Mutation: the draw that finds the selection changed calls `trigger.requestRedraw()` (the frames
/// never stop: the last checks fail); a build requested by the selection would show in `builds` and `elementRequests` (2).
@MainActor @Test func aSelectionFrameIsSurfaceOnly() async throws {
    let rig = try TermRig()
    await rig.settle()
    for i in 0..<10 { rig.feed("line \(i)\r\n") }
    await rig.frame(); await rig.settle()
    let draws = rig.window.surfaceDrawCount, takes = rig.model.statistics.snapshotsTaken
    rig.source.perform { $0.selection = .linear(TerminalRange(lowerBound: TerminalPosition(row: 0, col: 1),
                                                              upperBound: TerminalPosition(row: 8, col: 3))) }
    await rig.frame()
    var work = rig.window.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1,
            "set: \(work.builds) \(work.elementRequests) \(work.surfaceOnlyFrames)")
    #expect(rig.window.surfaceDrawCount == draws + 1 && rig.model.statistics.snapshotsTaken == takes + 1)
    #expect(rig.model.statistics.lastRows == Array(0...8), "\(rig.model.statistics.lastRows)")
    await rig.frame()                                  // the Copy text fetch's publish: no rows
    work = rig.window.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && rig.model.statistics.lastRows.isEmpty,
            "fetch: \(work.builds) \(work.elementRequests) \(rig.model.statistics.lastRows)")
    await rig.frame(); await rig.frame()
    #expect(rig.window.surfaceDrawCount == draws + 2, "then nothing more is drawn: \(rig.window.surfaceDrawCount - draws)")
    rig.source.perform { $0.selection = nil }
    await rig.frame()
    work = rig.window.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1,
            "cleared: \(work.builds) \(work.elementRequests) \(work.surfaceOnlyFrames)")
    await rig.frame(); await rig.frame()
    #expect(rig.window.surfaceDrawCount == draws + 3, "\(rig.window.surfaceDrawCount - draws)")
}

/// The instances that are rects (a glyph instance over the sink's solid square).
@MainActor private func rectCount(_ sink: SurfaceTextSink) -> Int {
    guard let slot = sink.solidSlot else { return 0 }
    let inset = Float(SurfaceTextSink.solidInset), inner = Float(SurfaceTextSink.solidSide - 2 * SurfaceTextSink.solidInset)
    return sink.glyphs.filter {
        $0.atlasBounds.origin.x == Float(slot.x) + inset && $0.atlasBounds.origin.y == Float(slot.y) + inset
            && $0.atlasBounds.size.width == inner
    }.count
}

/// **2** (`TRM-BK` item 1) Glyph instances are at most damaged rows x columns plus the rects: drawing only the damaged
/// rows of a 200 x 60 grid of ASCII records, for each, at most one glyph instance per column and the rects (backgrounds
/// and decorations) on top, and nothing for an undamaged row. Mutation: the painter records each cell's glyph twice
/// (the bound fails), or draws every row of the snapshot (the damaged-row count fails).
@MainActor @Test func glyphInstancesAreBoundedByDamagedCellsPlusRects() throws {
    let (painter, _) = notoPainter()
    let atlas = GlyphAtlas(width: 2048, height: 2048)
    var screen = ""
    for r in 0..<60 {
        screen += (r % 5 == 0 ? "\u{1B}[31;44m" : "\u{1B}[0m")
            + String((0..<200).map { c in Character(UnicodeScalar(UInt8(33 + (r * 7 + c) % 90))) }) + "\r\n"
    }
    let emulator = TerminalEmulator(cols: 200, rows: 60)
    Array(screen.utf8).withUnsafeBytes { emulator.feed($0) }
    let first = emulator.publishSnapshot()
    let warm = makeSink(atlas)                            // warm the cache and the atlas, then measure
    for row in first.damagedRows { painter.draw(row.row, at: row.index, columns: 200, origin: (0, 0), into: warm) }
    Array("\u{1B}[3;1Hxyz\u{1B}[40;5H\u{1B}[1mbold\u{1B}[0m".utf8).withUnsafeBytes { emulator.feed($0) }
    let snapshot = emulator.publishSnapshot()
    #expect(snapshot.damagedRows.count == 2, "\(snapshot.damagedRows.map(\.index))")
    let sink = makeSink(atlas)
    for row in snapshot.damagedRows { painter.draw(row.row, at: row.index, columns: 200, origin: (0, 0), into: sink) }
    let rects = rectCount(sink)
    #expect(rects > 0 && rects < sink.glyphs.count)
    #expect(sink.glyphs.count <= snapshot.damagedRows.count * 200 + rects,
            "\(sink.glyphs.count) instances, \(rects) rects, \(snapshot.damagedRows.count) damaged rows")
    #expect(sink.glyphs.count - rects >= 190, "and the glyphs are really counted: \(sink.glyphs.count - rects)")
    let none = makeSink(atlas)
    #expect(emulator.publishSnapshot().damagedRows.isEmpty && none.glyphs.isEmpty)
}

// MARK: - The UI half of the gated bench (`METALUI_RUN_TERMINAL_BENCH=1 swift test -c release --filter TerminalBench`)

@Suite struct TerminalBenchUI {
    private static let enabled = ProcessInfo.processInfo.environment["METALUI_RUN_TERMINAL_BENCH"] == "1"

    private func milliseconds(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    /// Surface-only frame CPU: recording every row of a full 200 x 60 grid (coloured ASCII, the cache and atlas warm)
    /// into the sink, which is the whole of the view's CPU work in an output frame that redraws the screen. Target
    /// 1 ms (Alloy's proposal); one damaged row is timed too.
    @MainActor @Test(.enabled(if: TerminalBenchUI.enabled)) func surfaceOnlyFrameCPUOfAFullGrid() throws {
        let (painter, _) = notoPainter()
        let atlas = GlyphAtlas(width: 2048, height: 2048)
        var screen = ""
        for r in 0..<60 {
            screen += "\u{1B}[3\(r % 8)m" + String((0..<100).map { c in Character(UnicodeScalar(UInt8(33 + (r * 7 + c) % 90))) })
                + "\u{1B}[0m" + String((0..<100).map { c in Character(UnicodeScalar(UInt8(33 + (r * 3 + c) % 90))) }) + "\r\n"
        }
        let emulator = TerminalEmulator(cols: 200, rows: 60)
        Array(screen.utf8).withUnsafeBytes { emulator.feed($0) }
        let rows = emulator.publishSnapshot().damagedRows
        let warm = makeSink(atlas)
        for row in rows { painter.draw(row.row, at: row.index, columns: 200, origin: (0, 0), into: warm) }
        let clock = ContinuousClock()
        var full = Double.infinity, one = Double.infinity, instances = 0
        for _ in 0..<50 {
            let sink = makeSink(atlas)
            full = min(full, milliseconds(clock.measure { for row in rows { painter.draw(row.row, at: row.index, columns: 200, origin: (0, 0), into: sink) } }))
            instances = sink.glyphs.count
            let single = makeSink(atlas)
            one = min(one, milliseconds(clock.measure { painter.draw(rows[0].row, at: 0, columns: 200, origin: (0, 0), into: single) }))
        }
        print("terminal bench: surface-only frame, 200x60 full grid \(Int(full * 1000)) us (\(instances) instances), one row \(Int(one * 1000)) us (target at most 1000 us for the full grid)")
        #expect(full < 50, "a floor far above the 1 ms target, so only a broken build fails")
    }

    /// Key to pty write, inside the dispatch: a committed character through the window's event path to the `onInput`
    /// closure that writes the pty, timed on the main actor with no frame between.
    @MainActor @Test(.enabled(if: TerminalBenchUI.enabled)) func keyToPtyWriteInsideTheDispatch() async throws {
        let rig = try TermRig()
        await rig.settle()
        await rig.focusTerminal()
        let clock = ContinuousClock()
        var best = Double.infinity, total = 0.0
        let count = 200
        for _ in 0..<count {
            rig.log.inputs = []
            let elapsed = milliseconds(clock.measure { rig.window.send(.textInput("a")) })
            #expect(rig.sent == [[0x61]])
            best = min(best, elapsed); total += elapsed
        }
        print("terminal bench: key to pty write inside dispatch: best \(Int(best * 1_000_000)) ns, mean \(Int(total / Double(count) * 1_000_000)) ns over \(count) keys")
        #expect(best < 5, "a floor far above a sensible dispatch, so only a broken build fails")
    }
}
