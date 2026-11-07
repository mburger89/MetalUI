import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Virtual rows, scroll sync, reveal and the accessibility node of `CodeView` (rulings `CV-S`..`CV-U`, record
// 227 run 2). PLAIN imports; the harness text system, so every number is the same on macOS, Linux and Windows.
// Perf pins count work (`RunTreeStats.nodesVisited`, `FrameWork`), never a clock.

let virtualTintAlpha: Float = 0.41
let virtualBarAlpha: Float = 0.53

@MainActor func virtualRows(_ decorations: CodeDecorations, _ rows: [CodeVirtualRow]) {
    decorations.setVirtualRows(rows, asOf: decorations.buffer.version)
}

@MainActor func redTint(_ alpha: Float) -> Color { Color(red: 1, green: 0, blue: 0).opacity(Double(alpha)) }

/// The buffer row a press at display row `display` (view-local) lands in.
@MainActor func rowUnderPress(_ window: TestWindow, _ buffer: CodeBuffer, display: Float, pitch: Float) -> Int {
    window.click(at: pt(60, display * pitch + pitch / 2))
    return buffer.snapshot().point(at: buffer.primarySelection.head).row
}

/// 7.1 — virtual rows take display rows and are not buffer rows: two lines before row 3 tint a rect of two
/// pitches at display row 3, a press on display row 5 lands in buffer row 3, and the gutter bar covers the two.
/// **Mutation:** `displayRow(ofBufferRow:)` ignoring the gaps puts the tint under row 3's text and lands the
/// press in row 5.
@Test @MainActor func virtualRowsTakeDisplayRowsAndNotBufferRows() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    virtualRows(decorations, [CodeVirtualRow(anchor: .before(line: 3), lines: ["- removed one", "- removed two"],
                                             gutterBar: redTint(virtualBarAlpha),
                                             background: redTint(virtualTintAlpha), gutterMarker: CodeGutterMarker("-"))])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let pitch = codePitch(scale: 1)
    #expect(decorations.virtualLineCount == 2)
    let tint = try #require(tintRects(window, alpha: virtualTintAlpha).first)
    #expect(tint.bounds.origin.y == 3 * pitch && tint.bounds.size.height == 2 * pitch, "tint at \(tint.bounds)")
    #expect(tintRects(window, alpha: virtualBarAlpha).first?.bounds.size.height == 2 * pitch, "the bar spans both lines")
    #expect(rowUnderPress(window, buffer, display: 2, pitch: pitch) == 2)
    #expect(rowUnderPress(window, buffer, display: 5, pitch: pitch) == 3, "display row 5 is buffer row 3")
    #expect(rowUnderPress(window, buffer, display: 6, pitch: pitch) == 4)
}

/// 7.2 — a virtual row is not selectable: a press on it puts the caret at the start of the row it sits before
/// and selects nothing, and a drag across it selects buffer text only.
/// **Mutation:** the hit test treating a virtual line as text selects part of its own (empty) range.
@Test @MainActor func aVirtualRowCannotBeSelected() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    virtualRows(decorations, [CodeVirtualRow(anchor: .after(line: 2), lines: ["VIRTUAL TEXT THAT IS LONG", "AND MORE"])])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let pitch = codePitch(scale: 1)
    let row3 = buffer.snapshot().offset(of: CodePoint(row: 3, column: 0))
    window.click(at: pt(150, 3 * pitch + pitch / 2))   // display row 3: the first virtual line
    #expect(buffer.primarySelection.range == row3..<row3, "caret at the start of the next buffer row: \(buffer.primarySelection.range)")
    window.drag(from: pt(60, 2 * pitch + pitch / 2), to: pt(60, 6 * pitch + pitch / 2))
    window.typeKey("c", modifierFlags: codePrimary)
    let rep = try #require(window.clipboardRepresentations.first)
    let copied = String(decoding: rep.bytes, as: UTF8.self)
    #expect(!copied.contains("VIRTUAL") && !copied.contains("AND MORE") && !copied.isEmpty, "copied \(copied.debugDescription)")
}

/// 7.3 — the scroll extent counts virtual lines and the reveal centres through them: with 50 virtual lines above
/// row 60, revealing row 60 puts it in the middle of the viewport, and the wheel reaches the last buffer row.
/// **Mutation:** `maxTopPx` counted from the buffer rows alone stops the wheel 50 rows short of the end.
@Test @MainActor func scrollingAndRevealGoThroughTheRowMap() throws {
    let buffer = CodeBuffer(codeText(lines: 200))
    let decorations = CodeDecorations(buffer: buffer)
    virtualRows(decorations, [CodeVirtualRow(anchor: .before(line: 10), lines: (0..<50).map { "removed \($0)" })])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let pitch = codePitch(scale: 1)
    let offset = buffer.snapshot().offset(of: CodePoint(row: 60, column: 0))
    buffer.select(offset..<offset, reveal: true)
    window.window.setNeedsRedraw(); window.tick()
    let middle = (200 - pitch) / 2 + pitch / 2
    window.click(at: pt(60, middle))
    #expect(buffer.snapshot().point(at: buffer.primarySelection.head).row == 60, "centred through the virtual lines")
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -1_000_000)
    window.click(at: pt(60, 200 - pitch / 2))
    let end = buffer.snapshot().point(at: buffer.primarySelection.head).row
    #expect(end == 200, "the wheel reaches the end (the empty row after the final newline): row \(end)")
}

/// 7.4 — an edit above moves the virtual rows with their buffer row and the reader stays where they were: after
/// 20 lines are inserted above, the top row's text is the same and the tint is still over the same text.
/// **Mutation:** `CodeRowMap.splice` not called from `apply(_:)` leaves the virtual rows 20 rows too high.
@Test @MainActor func anEditAboveKeepsVirtualRowsWithTheirRowAndTheReaderInPlace() throws {
    let buffer = CodeBuffer(codeText(lines: 300))
    let decorations = CodeDecorations(buffer: buffer)
    virtualRows(decorations, [CodeVirtualRow(anchor: .before(line: 53), lines: ["gone"], background: redTint(virtualTintAlpha))])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let pitch = codePitch(scale: 1)
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch * 50)
    let before = tintRects(window, alpha: virtualTintAlpha).first?.bounds.origin.y
    #expect(before == 3 * pitch, "the tint is at display row 3 when row 50 is on top: \(before as Any)")
    buffer.replace(0..<0, with: String(repeating: "added\n", count: 20))
    window.window.setNeedsRedraw(); window.tick()
    #expect(tintRects(window, alpha: virtualTintAlpha).first?.bounds.origin.y == before, "same place on screen")
    #expect(rowUnderPress(window, buffer, display: 0, pitch: pitch) == 70, "the reader's row moved down by 20")
    // A newline below the viewport changes nothing on screen; one at the anchor row moves the tint down.
    let start = buffer.snapshot().offset(of: CodePoint(row: 71, column: 0))
    buffer.replace(start..<start, with: "\n")
    window.window.setNeedsRedraw(); window.tick()
    #expect(tintRects(window, alpha: virtualTintAlpha).first?.bounds.origin.y == before.map { $0 + pitch }, "a newline above the gap moves it a row")
}

/// 7.5 — rows given for an older version are mapped forward: given at version v, then three lines inserted at the
/// top, the group lands before the same text.
/// **Mutation:** `setVirtualRows` ignoring `asOf` puts it 3 rows too high.
@Test @MainActor func virtualRowsGivenForAnOlderVersionAreMappedForward() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    let version = buffer.version
    buffer.replace(0..<0, with: "a\nb\nc\n")
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["x"], background: redTint(virtualTintAlpha))], asOf: version)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    #expect(tintRects(window, alpha: virtualTintAlpha).first?.bounds.origin.y == 8 * codePitch(scale: 1), "before the old row 5, now row 8")
}

/// 7.6 — filler rows are blank virtual rows by the same mechanism, and two views whose rows complement each
/// other (50 lines against 47 lines and 3 filler) end on the same display row: the side-by-side premise.
/// **Mutation:** `virtualCount` left out of `displayRowCount` stops the filler view 3 rows short.
@Test @MainActor func fillerRowsAlignTwoViews() throws {
    let a = CodeBuffer(codeText(lines: 50)), b = CodeBuffer(codeText(lines: 47))
    let da = CodeDecorations(buffer: a), db = CodeDecorations(buffer: b)
    virtualRows(db, [.filler(3, at: .before(line: 10), background: redTint(virtualTintAlpha))])
    let pitch = codePitch(scale: 1)
    let wa = try codeWindow(buffer: a, decorations: da), wb = try codeWindow(buffer: b, decorations: db)
    wa.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -1_000_000)
    wb.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -1_000_000)
    let last = Float(Int(200 / pitch)) - 1
    #expect(rowUnderPress(wa, a, display: last, pitch: pitch) == 49 - 0 && rowUnderPress(wb, b, display: last, pitch: pitch) == 46)
    #expect(db.virtualLineCount == 3 && da.virtualLineCount == 0)
}

/// 7.7 — a newline above many virtual rows shifts them in logarithmic work: the nodes visited for one newline
/// differ by a small constant between 100 and 10 000 groups. **Mutation:** shifting by a loop over every group
/// visits 10 000 nodes.
@Test @MainActor func aNewlineAboveManyVirtualRowsShiftsThemInLogarithmicWork() throws {
    var visited: [Int] = []
    for groups in [100, 10_000] {
        let buffer = CodeBuffer(String(repeating: "x\n", count: 30_000))
        let decorations = CodeDecorations(buffer: buffer)
        let rows = (0..<groups).map { CodeVirtualRow(anchor: .before(line: 20 + 2 * $0), lines: ["v\($0)"]) }
        decorations.setVirtualRows(rows, asOf: buffer.version)
        decorations.sync()
        let start = buffer.snapshot().offset(of: CodePoint(row: 5, column: 0))
        let before = RunTreeStats.nodesVisited
        buffer.replace(start..<start, with: "\n")
        decorations.sync()
        visited.append(RunTreeStats.nodesVisited - before)
        #expect(decorations.virtualLineCount == groups)
    }
    #expect(visited[1] - visited[0] <= 60, "nodes visited for one newline: \(visited) at 100 and 10 000 groups")
    #expect(visited[1] < 400, "and not proportional to the groups: \(visited)")
}

/// 7.8 — opening with 10 000 virtual groups (20 000 lines) in a 100 000-line file shapes only the visible rows:
/// the same count as with none, and the gutter and glyph work is the visible rows'. **Mutation:** a row loop over
/// every display row shapes tens of thousands.
@Test @MainActor func openingWithTenThousandVirtualGroupsShapesOnlyTheVisibleRows() throws {
    let buffer = CodeBuffer(codeText(lines: 100_000))
    let decorations = CodeDecorations(buffer: buffer)
    let rows = (0..<10_000).map { CodeVirtualRow(anchor: .before(line: 10 * $0 + 4), lines: ["- old \($0) a", "- old \($0) b"],
                                                  background: redTint(virtualTintAlpha), gutterMarker: CodeGutterMarker("-")) }
    decorations.setVirtualRows(rows, asOf: buffer.version)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let visible = Int((200 / codePitch(scale: 1)).rounded(.up))
    let open = totalWork(window)
    #expect(open.codeLinesPainted == visible, "painted \(open.codeLinesPainted), visible \(visible)")
    #expect(open.codeLinesShaped <= visible + 1, "shaped \(open.codeLinesShaped): the visible rows and one of overscan")
    #expect(decorations.virtualLineCount == 20_000)
    window.resetFrameWork()
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -codePitch(scale: 1))
    #expect(totalWork(window).codeLinesShaped <= 2, "a one-row scroll shapes the entering row")
}

// MARK: - Scroll sync

@MainActor func syncedWindow(_ a: CodeBuffer, _ b: CodeBuffer, sa: CodeScrollState, sb: CodeScrollState,
                             calls: CallLog) throws -> TestWindow {
    let da = CodeDecorations(buffer: a), db = CodeDecorations(buffer: b)
    return try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            CodeView(buffer: a, decorations: da).font(size: 12).scrollState(sa)
                .onScroll { calls.a += 1; sb.position = $0 }.id("a")
            CodeView(buffer: b, decorations: db).font(size: 12).scrollState(sb)
                .onScroll { calls.b += 1; sa.position = $0 }.id("b")
        }
    }
}

@MainActor final class CallLog { var a = 0, b = 0 }

/// 8.1 — the scroll position is observable and settable: the wheel moves it (in display rows), an assignment
/// scrolls the view, and the assignment is not reported to `onScroll`.
/// **Mutation:** reporting an adopted position (`silent` false) calls `onScroll` for the assignment.
@Test @MainActor func theScrollPositionIsObservableAndSettable() async throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let decorations = CodeDecorations(buffer: buffer)
    let state = CodeScrollState()
    var reported: [CodeScrollPosition] = []
    let window = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).scrollState(state).onScroll { reported.append($0) }
    }
    let pitch = codePitch(scale: 1)
    #expect(state.position == CodeScrollPosition(row: 0, x: 0))
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch * 10)
    try await window.runUntilIdle()
    #expect(abs(state.position.row - 10) < 0.01, "the wheel moved it to \(state.position)")
    #expect(reported.count == 1 && abs(reported[0].row - 10) < 0.01, "reported \(reported)")
    state.position = CodeScrollPosition(row: 400, x: 0)
    try await window.runUntilIdle()
    #expect(rowUnderPress(window, buffer, display: 0, pitch: pitch) == 400, "the assignment scrolled the view")
    #expect(reported.count == 1, "an assigned position is not reported: \(reported)")
    #expect(state.position.row == 400)
    state.position = CodeScrollPosition(row: 1_000_000, x: 0)   // past the end: clamped, and stored clamped
    try await window.runUntilIdle()
    #expect(state.position.row < 1000 && state.position.row > 900, "clamped: \(state.position)")
}

/// 8.2 — two views synced through `onScroll` have equal positions after a wheel on either, with no feedback:
/// each callback runs once for the view that was wheeled and never for the one that was assigned.
/// **Mutation:** the adopted position reported (not silent) makes B call back into A and `calls` exceed 1.
@Test @MainActor func twoViewsSyncedThroughOnScrollShowNoFeedbackLoop() async throws {
    let a = CodeBuffer(codeText(lines: 500)), b = CodeBuffer(codeText(lines: 500))
    let sa = CodeScrollState(), sb = CodeScrollState()
    let calls = CallLog()
    let window = try syncedWindow(a, b, sa: sa, sb: sb, calls: calls)
    let pitch = codePitch(scale: 1)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -pitch * 7)   // on A
    try await window.runUntilIdle()
    #expect(sa.position == sb.position && abs(sa.position.row - 7) < 0.01, "A \(sa.position), B \(sb.position)")
    #expect(calls.a == 1 && calls.b == 0, "A called back \(calls.a) times, B \(calls.b)")
    window.scroll(at: pt(300, 100), byDeltaX: 0, deltaY: -pitch * 5)   // on B
    try await window.runUntilIdle()
    #expect(sa.position == sb.position && abs(sa.position.row - 12) < 0.01, "A \(sa.position), B \(sb.position)")
    #expect(calls.a == 1 && calls.b == 1, "A \(calls.a), B \(calls.b)")
    // Both really show row 12 on top.
    #expect(rowUnderPress(window, a, display: 0, pitch: pitch) == 12)
    window.click(at: pt(260, 2))
    #expect(b.snapshot().point(at: b.primarySelection.head).row == 12)
    // And they stay put when nothing moves.
    window.window.setNeedsRedraw(); window.tick()
    try await window.runUntilIdle()
    #expect(calls.a == 1 && calls.b == 1)
}

/// 8.3 — horizontal sync: the x offset (points) is published and adopted too.
@Test @MainActor func theHorizontalOffsetIsSyncedToo() async throws {
    let wide = String(repeating: "W", count: 200) + "\n"
    let a = CodeBuffer(wide + codeText(lines: 50)), b = CodeBuffer(wide + codeText(lines: 50))
    let sa = CodeScrollState(), sb = CodeScrollState()
    let window = try syncedWindow(a, b, sa: sa, sb: sb, calls: CallLog())
    window.scroll(at: pt(100, 100), byDeltaX: -50, deltaY: 0)
    try await window.runUntilIdle()
    #expect(abs(sa.position.x - 50) < 0.01 && sb.position == sa.position, "A \(sa.position), B \(sb.position)")
}

/// 8.4 — synced views with virtual filler keep the same display row: a position in rows is the same place in a
/// view whose rows differ in buffer row but not in display row.
@Test @MainActor func aSyncedPositionIsInDisplayRowsSoFillerKeepsViewsAligned() async throws {
    let a = CodeBuffer(codeText(lines: 500)), b = CodeBuffer(codeText(lines: 497))
    let da = CodeDecorations(buffer: a), db = CodeDecorations(buffer: b)
    virtualRows(db, [.filler(3, at: .before(line: 5))])
    let sa = CodeScrollState(), sb = CodeScrollState()
    let window = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            CodeView(buffer: a, decorations: da).font(size: 12).scrollState(sa).onScroll { sb.position = $0 }
            CodeView(buffer: b, decorations: db).font(size: 12).scrollState(sb).onScroll { sa.position = $0 }
        }
    }
    let pitch = codePitch(scale: 1)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -pitch * 20)
    try await window.runUntilIdle()
    #expect(rowUnderPress(window, a, display: 0, pitch: pitch) == 20)
    window.click(at: pt(260, 2))
    #expect(b.snapshot().point(at: b.primarySelection.head).row == 17, "display row 20 is buffer row 17 behind three filler lines")
}

// MARK: - Reveal

/// 9.1 — `select(_:reveal: true)` centres the head's display row in **every** view showing the buffer: the anchor
/// is the middle of the viewport (`(height - pitch) / 2` above the row's top), clamped at both ends.
/// **Mutation:** centring only the first view, or placing the row at the top, reddens it.
@Test @MainActor func revealCentresTheLineInEveryViewOfTheBuffer() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let da = CodeDecorations(buffer: buffer), db = CodeDecorations(buffer: buffer)
    let window = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            CodeView(buffer: buffer, decorations: da).font(size: 12)
            CodeView(buffer: buffer, decorations: db).font(size: 12)
        }
    }
    let pitch = codePitch(scale: 1)
    let offset = buffer.snapshot().offset(of: CodePoint(row: 500, column: 0))
    buffer.select(offset..<offset, reveal: true)
    window.window.setNeedsRedraw(); window.tick()
    let middle = (200 - pitch) / 2 + pitch / 2
    for x: Float in [100, 300] {
        window.click(at: pt(x, middle))
        #expect(buffer.snapshot().point(at: buffer.primarySelection.head).row == 500, "view at x \(x)")
    }
}

// MARK: - Accessibility

/// 10.1 — one `.textArea` node whose value is the visible rows' text, capped at 64 KB, built only while a client
/// is active. **Mutation:** building the text unconditionally leaves `accessibilityTextBuilds` nonzero in the
/// inactive window; the whole document as the value overshoots the cap.
@Test @MainActor func theAccessibilityNodeCarriesTheVisibleRowsCapped() throws {
    CodeViewStats.accessibilityTextBuilds = 0
    let quiet = CodeBuffer(codeText(lines: 500))
    let inactive = try harnessWindow(size: sz(400, 200), options: .init(accessibilityClientActive: false)) {
        CodeView(buffer: quiet, decorations: CodeDecorations(buffer: quiet)).font(size: 12)
    }
    inactive.window.setNeedsRedraw(); inactive.tick()
    #expect(CodeViewStats.accessibilityTextBuilds == 0, "no client, no text built")

    let long = String(repeating: "abcdefghij", count: 2_000)   // 20 KB per line
    let buffer = CodeBuffer((0..<40).map { "\($0) " + long }.joined(separator: "\n"))
    let decorations = CodeDecorations(buffer: buffer)
    virtualRows(decorations, [CodeVirtualRow(anchor: .before(line: 0), lines: ["VIRTUAL FIRST"])])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let nodes = try window.elements(role: .textArea)
    #expect(nodes.count == 1, "one node: \(nodes.count)")
    let value = try #require(nodes.first?.value)
    let head = String(value.prefix(40))
    #expect(head.hasPrefix("VIRTUAL FIRST\n0 abcdefghij"), "the visible rows in display order: \(head.debugDescription)")
    #expect(value.utf8.count <= 64 * 1024 && value.utf8.count > 60 * 1024, "capped near 64 KB: \(value.utf8.count)")
    #expect(!value.contains("39 abc"), "rows below the viewport are not in it")
    #expect(CodeViewStats.accessibilityTextBuilds > 0)
}
