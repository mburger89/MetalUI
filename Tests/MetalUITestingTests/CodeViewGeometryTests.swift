import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeViewGeometry` (`CV-AJ`, `CV-AK`, Alloy G35 A): point to offset and range to rectangles, view-local, for the last
// drawn frame. The view sits below a 50 pt spacer and inside a 30 pt inset, so view-local is never the window's.

private let geometryOrigin = pt(30, 50)
private let selectionAlpha: Float = 0.29

@MainActor private func geometryFixture(lines: Int = 60, inset: Bool = true) throws
    -> (window: TestWindow, buffer: CodeBuffer, decorations: CodeDecorations, geometry: CodeViewGeometry) {
    let buffer = CodeBuffer(codeText(lines: lines))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.theme.selection = Color(red: 0, green: 0, blue: 1).opacity(Double(selectionAlpha))
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 600)) {
        VStack(spacing: 0) {
            Color.clear.frame(height: inset ? 50 : 0)
            HStack(spacing: 0) {
                Color.clear.frame(width: inset ? 30 : 0)
                CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry)
            }
        }
    }
    return (window, buffer, decorations, geometry)
}

@MainActor private func inWindow(_ local: Point<Pixels>) -> Point<Pixels> {
    pt(local.x.value + geometryOrigin.x.value, local.y.value + geometryOrigin.y.value)
}

@MainActor private func byteRange(of needle: String, inRow row: Int, _ buffer: CodeBuffer) -> Range<Int> {
    let snap = buffer.snapshot()
    let line = snap.line(row)
    let r = line.range(of: needle)!
    let start = snap.lineRange(row).lowerBound + line.utf8.distance(from: line.startIndex, to: r.lowerBound)
    return start..<(start + needle.utf8.count)
}

private func center(_ r: Bounds<Pixels>) -> Point<Pixels> {
    pt(r.origin.x.value + r.size.width.value / 2, r.origin.y.value + r.size.height.value / 2)
}

/// 1 — a point resolves to the character under it, the nearest boundary a press would place, the row and the region,
/// for a view that is not at the window origin. **Mutation:** `hit(at:)` not adding the origin back lands rows and a
/// gutter's width off.
@Test @MainActor func hitReportsTheCharacterUnderThePointAndTheRegion() throws {
    let (window, buffer, _, geometry) = try geometryFixture()
    #expect(geometry.version == buffer.version)
    let accent = byteRange(of: "\u{E9}", inRow: 1, buffer)
    let family = byteRange(of: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", inRow: 3, buffer)
    for (character, row) in [(accent, 1), (family, 3), (byteRange(of: "v", inRow: 0, buffer), 0)] {
        let rect = try #require(geometry.rects(for: character).first)
        let hit = try #require(geometry.hit(at: center(rect)))
        #expect(hit.region == .text && hit.row == row, "\(hit)")
        #expect(hit.character == character, "the grapheme under \(center(rect)): \(hit) wanted \(character)")
        window.click(at: inWindow(center(rect)))
        #expect(buffer.primarySelection.head == hit.offset, "a press at the same point places the caret at the hit's offset")
    }
    let line0 = buffer.snapshot().lineRange(0)
    let past = try #require(geometry.hit(at: pt(350, 3)))
    #expect(past.region == .pastLineEnd && past.row == 0 && past.character == nil && past.offset == line0.upperBound, "\(past)")
}

/// 2 — a range over three rows is one rectangle per row segment, clipped to the range, and equals what the selection
/// paints (less the 4 pt line-break tail on all but the last). **Mutation:** `rects(forBounds:)` using `row.range`
/// instead of the clipped range.
@Test @MainActor func rectsForARangeSpanningRowsAreOnePerVisibleSegment() throws {
    let (window, buffer, _, geometry) = try geometryFixture()
    let snap = buffer.snapshot()
    let start = snap.lineRange(0).lowerBound + 4, end = snap.lineRange(2).lowerBound + 6
    let rects = geometry.rects(for: start..<end)
    #expect(rects.count == 3, "\(rects)")
    buffer.selections = [CodeSelection(anchor: start, head: end)]
    window.tick()
    let painted = window.scene.rects.filter { abs($0.background.a - selectionAlpha) < 0.001 }.sorted { $0.bounds.origin.y < $1.bounds.origin.y }
    #expect(painted.count == 3, "\(painted.map(\.bounds))")
    for (i, (rect, paint)) in zip(rects, painted).enumerated() {
        let b = paint.bounds
        #expect(abs(b.origin.x - (rect.origin.x.value + geometryOrigin.x.value)) < 0.01, "row \(i) x")
        #expect(abs(b.origin.y - (rect.origin.y.value + geometryOrigin.y.value)) < 0.01, "row \(i) y")
        #expect(abs(b.size.height - rect.size.height.value) < 0.01, "row \(i) height")
        let tail: Float = i < 2 ? 4 : 0
        #expect(abs(b.size.width - (rect.size.width.value + tail)) < 0.01, "row \(i) width \(b.size.width) vs \(rect.size.width.value)")
    }
    #expect(geometry.rects(for: 5..<5).count == 1 && geometry.rects(for: 5..<5)[0].size.width.value == 0)
}

/// 3 — a virtual row and the gutter report their regions. **Mutation:** the virtual-row and gutter checks dropped (both
/// report `.text`).
@Test @MainActor func aVirtualRowAndTheGutterReportTheirRegions() throws {
    let (_, buffer, decorations, geometry) = try geometryFixture(inset: false)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 3), lines: ["- removed one"],
                                               gutterBar: nil, background: nil, gutterMarker: nil)], asOf: buffer.version)
    let window = try harnessWindow(size: sz(400, 600)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry)
    }
    _ = window
    let pitch = codePitch(scale: 1)
    let virtual = try #require(geometry.hit(at: pt(60, 3.5 * pitch)))
    #expect(virtual.region == .virtualRow && virtual.row == nil && virtual.character == nil, "\(virtual)")
    #expect(virtual.offset == buffer.snapshot().lineRange(3).lowerBound, "resolves to the row it sits before: \(virtual)")
    let after = try #require(geometry.hit(at: pt(60, 4.5 * pitch)))
    #expect(after.region == .text && after.row == 3, "\(after)")
    let gutter = try #require(geometry.hit(at: pt(3, 0.5 * pitch)))
    #expect(gutter.region == .gutter && gutter.row == 0 && gutter.character == nil, "\(gutter)")
    #expect(geometry.rects(for: buffer.snapshot().lineRange(3)).count == 1)
}

/// 4 — after a scroll and after an edit the answers are the new frame's. **Mutation:** the plan written only on the
/// first frame.
@Test @MainActor func geometryAfterScrollMatchesTheNewFrame() throws {
    let (window, buffer, _, geometry) = try geometryFixture()
    let pitch = codePitch(scale: 1)
    #expect(geometry.visibleRows?.lowerBound == 0)
    window.scroll(at: inWindow(pt(100, 100)), byDeltaX: 0, deltaY: -pitch * 10)
    let rows = try #require(geometry.visibleRows)
    #expect(rows.lowerBound == 10 && rows.count > 5, "\(rows)")
    let hit = try #require(geometry.hit(at: pt(60, pitch / 2)))
    #expect(hit.row == 10)
    window.click(at: inWindow(pt(60, pitch / 2)))
    #expect(buffer.snapshot().point(at: buffer.primarySelection.head).row == 10)
    #expect(geometry.rects(for: buffer.snapshot().lineRange(2)).isEmpty, "a scrolled-off row has none")
    let before = try #require(geometry.version)
    buffer.replace(0..<0, with: "x")
    window.tick()
    #expect(geometry.version == buffer.version && geometry.version != before)
}

/// 5 — the caret rectangle is the painted caret's, view-local. **Mutation:** the origin not subtracted.
@Test @MainActor func caretRectMatchesThePaintedCaret() throws {
    let (window, buffer, _, geometry) = try geometryFixture()
    window.click(at: inWindow(pt(80, 40)))
    window.tick()
    let bars = caretBars(window)
    let bar = try #require(bars.first, "one caret bar")
    let caret = try #require(geometry.caretRect())
    #expect(abs(bar.bounds.origin.x - (caret.origin.x.value + geometryOrigin.x.value)) < 0.01, "\(bar.bounds) vs \(caret)")
    #expect(abs(bar.bounds.origin.y - (caret.origin.y.value + geometryOrigin.y.value)) < 0.01)
    #expect(caret.size.width.value == bar.bounds.size.width && caret.size.height.value == bar.bounds.size.height)
    #expect(geometry.hit(at: pt(caret.origin.x.value, caret.origin.y.value + 1))?.offset == buffer.primarySelection.head)
    buffer.selections = [CodeSelection(caret: buffer.snapshot().utf8Count)]
    window.tick()
    #expect(geometry.caretRect() == nil, "a caret far below the shown rows has no rectangle")
}
