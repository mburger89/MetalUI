import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeDecorations.paintedVirtualRows(at:)` (`CV-CA`, Alloy: a plugin's message row paints a bar on its virtual row and
// the test must read its owner, colour and tag back instead of asserting `virtualLineCount`). PLAIN imports; the
// harness text system. Narrow builder blocks (`PE-K`).

private let planHue = Color(hue: 0.1, saturation: 1, brightness: 1)
private let diffHue = Color(hue: 0.6, saturation: 1, brightness: 1)
private let plugin = CodeDecorationOwner("plugin", priority: 1)
private let diff = CodeDecorationOwner("diff", priority: 9)

private func text(_ lines: Int) -> String { (0..<lines).map { "line\($0) = x" }.joined(separator: "\n") + "\n" }

/// 1 - the groups of two owners at one gap read back in display order (the lower priority first, whatever order they
/// were set in), each with its owner, tag, bar, tint, marker and lines (cut at the first line break); `.after(line: 9)`
/// names the gap `.before(line: 10)` does; a gap with nothing, and an empty marker, read as nothing.
/// **Mutations:** the groups returned in reverse; `owner` read as `nil`; the walk not stopped at the gap (a neighbouring
/// gap's rows come too); the marker not filtered for empty text.
@Test @MainActor func aVirtualRowsBarOwnerTagAndLinesReadBack() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    let v = buffer.version
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 10), lines: ["- gone", "- also\nhidden"], gutterBar: diffHue,
                                               background: Color.red.opacity(0.3), tag: 7)], asOf: v, owner: diff)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .after(line: 9), lines: ["! note"], gutterBar: planHue,
                                               gutterMarker: CodeGutterMarker("!", severity: 2), tag: 5),
                                CodeVirtualRow(anchor: .before(line: 12), lines: ["next gap"], gutterBar: planHue, gutterMarker: CodeGutterMarker(""))],
                               asOf: v, owner: plugin)
    let both = decorations.paintedVirtualRows(at: .before(line: 10))
    #expect(both.map(\.owner) == ["plugin", "diff"], "ascending priority: \(both.map(\.owner))")
    #expect(both[0] == CodePaintedVirtualRow(anchor: .after(line: 9), lines: ["! note"], gutterBar: planHue,
                                             gutterMarker: CodeGutterMarker("!", severity: 2), tag: 5, owner: "plugin"))
    #expect(both[1] == CodePaintedVirtualRow(anchor: .before(line: 10), lines: ["- gone", "- also"], background: Color.red.opacity(0.3),
                                             gutterBar: diffHue, tag: 7, owner: "diff"), "a line is cut at its first break")
    #expect(decorations.paintedVirtualRows(at: .after(line: 9)) == both, "one gap, two spellings")
    #expect(decorations.paintedVirtualRows(at: .before(line: 11)).isEmpty && decorations.paintedVirtualRows(at: .before(line: 9)).isEmpty)
    let other = decorations.paintedVirtualRows(at: .before(line: 12))
    #expect(other.count == 1 && other[0].gutterMarker == nil && other[0].lines == ["next gap"], "an empty marker paints nothing")
    #expect(decorations.paintedVirtualRows(at: .before(line: 1000)).isEmpty, "past the end clamps to the gap after the last row")
}

/// 2 - the rows follow edits: two rows inserted above move the group's gap down by two, and a row set for an older
/// version lands mapped forward. **Mutation:** reading before the edit cursor drains (no `sync()`).
@Test @MainActor func anEditAboveMovesTheReadBackGap() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    let old = buffer.version
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["x"], gutterBar: planHue, tag: 1)], asOf: old, owner: plugin)
    buffer.replace(0..<0, with: "a\nb\n")
    #expect(decorations.paintedVirtualRows(at: .before(line: 5)).isEmpty)
    #expect(decorations.paintedVirtualRows(at: .before(line: 7)).first?.tag == 1)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 20), lines: ["y"], tag: 2)], asOf: old, owner: diff)   // old row 20
    #expect(decorations.paintedVirtualRows(at: .before(line: 22)).first?.owner == "diff")
}

/// 3 - agreement: the read-back is what the scene holds. A two-line group's bar is one 3 pt rect of the read-back's colour
/// over exactly its two display rows, below the five buffer rows above it, and the tint spans the same rows.
/// **Mutation:** the bar colour read from the neighbouring group (an owner mix-up).
@Test @MainActor func theVirtualReadBackIsWhatTheViewPaints() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["- a", "- b"], gutterBar: diffHue,
                                               background: Color.red.opacity(0.37))], asOf: buffer.version, owner: diff)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["! c"], gutterBar: planHue)], asOf: buffer.version, owner: plugin)
    let win = try harnessWindow(size: sz(400, 600)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
    let pitch = codePitch(scale: 1)
    let groups = decorations.paintedVirtualRows(at: .before(line: 5))
    #expect(groups.count == 2 && groups[0].owner == "plugin" && groups[1].owner == "diff")
    let bars = win.scene.rects.filter { $0.bounds.size.width == 3 }.sorted { $0.bounds.origin.y < $1.bounds.origin.y }
    #expect(bars.count == 2, "\(bars.map(\.bounds))")
    #expect(bars[0].bounds.origin.y == 5 * pitch && bars[0].bounds.size.height == pitch && abs(Double(bars[0].background.h) - 0.1) < 0.002)
    #expect(bars[1].bounds.origin.y == 6 * pitch && bars[1].bounds.size.height == 2 * pitch && abs(Double(bars[1].background.h) - 0.6) < 0.002)
    #expect(groups[0].gutterBar == planHue && groups[0].lines.count == 1 && groups[1].gutterBar == diffHue && groups[1].lines.count == 2)
    let tint = try #require(win.scene.rects.first { abs($0.background.a - 0.37) < 0.001 })
    #expect(tint.bounds.origin.y == 6 * pitch && tint.bounds.size.height == 2 * pitch && groups[1].background == Color.red.opacity(0.37))
}

// MARK: Cost

private struct VCost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
}

private struct VCard: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    }
    static func == (l: VCard, r: VCard) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

@MainActor private func steadyCost(reads: Int) async throws -> (VCost, FrameWork, Int) {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["- a"], gutterBar: planHue, tag: 1)],
                               asOf: buffer.version, owner: plugin)
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            ForEach(0..<1, id: \.self) { _ in
                VCard(buffer: buffer, decorations: decorations).equatable().frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    for _ in 0..<reads { _ = decorations.paintedVirtualRows(at: .before(line: 5)) }
    try await w.runUntilIdle()
    let framesFromReads = w.frameWork.count   // a read that touched observed state would ask for one
    w.window.setNeedsRedraw()
    try await w.runUntilIdle()
    let f = totalWork(w)
    return (VCost(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible, frames: w.frameWork.count),
            f, framesFromReads)
}

/// 4 - a view with virtual rows costs the same steady frame (2 requests, 0/1/0 retention, 0 lines shaped) whether or not
/// the app reads them back: the accessor keeps no state and schedules nothing. **Mutation:** the read bumping the
/// decorations' `revision` (a redraw and a reshape per read).
@Test @MainActor func readingVirtualRowsBackCostsTheViewNothing() async throws {
    let none = try await steadyCost(reads: 0), many = try await steadyCost(reads: 50)
    #expect(none.0 == VCost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "\(none.0)")
    #expect(many.0 == none.0 && many.1 == none.1 && many.2 == 0 && none.2 == 0, "\(many.1) vs \(none.1), frames from the reads \(many.2)")
    #expect(none.1.codeLinesShaped == 0, "a steady frame shapes nothing")
}
