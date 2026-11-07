import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeView` (rulings `CV-K`..`CV-Q`, record 227): the leaf, the line-layout cache, geometry, scrolling, the
// scroll anchor, selection and copy, decorations. PLAIN imports; text is the harness's Noto Sans through
// `PortableTextSystem`, so every number below is the same on macOS, Linux and Windows. Every perf pin counts
// work (`FrameWork`), never a clock; the fixtures have distinct lines, mixing ASCII, 2-, 3- and 4-byte
// scalars, ZWJ emoji, tabs and CRLF, so a content-hash cache cannot collapse them.

#if os(macOS)
let codePrimary: EventModifiers = .command
#else
let codePrimary: EventModifiers = .control
#endif

@MainActor func codeText(lines: Int) -> String {
    var out = ""
    out.reserveCapacity(lines * 40)
    for i in 0..<lines {
        switch i % 7 {
        case 0: out += "let value\(i) = \(i * 7919 % 10007) // line \(i)\n"
        case 1: out += "\tif x\(i) > 0 { return \"caf\u{E9} \u{4E16}\u{754C} \(i)\" }\n"
        case 2: out += "func f\(i)(_ a: Int) -> Int { a &+ \(i) }\r\n"
        case 3: out += "// \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} family \(i) \u{1F600}\n"
        case 4: out += "\t\tlet t\(i) = [\(i), \(i + 1), \(i + 2)]\n"
        case 5: out += String(repeating: " ", count: i % 30) + "\n"   // distinct, including the empty one at row 0
        default: out += "struct S\(i) { var v = \(i) }\n"
        }
    }
    return out
}

/// The line pitch in points the harness font gives at `size`, rounded to whole device pixels at `scale`.
@MainActor func codePitch(scale: Float, size: Double = 12) -> Float {
    let system = harnessTextSystem()
    let font = system.resolveFont(FontDescriptor(family: nil, size: size, design: .monospaced))
    return Float((system.measure(" ", font: font, wrappingAt: nil).totalHeight * Double(scale)).rounded()) / scale
}

@MainActor func codeWindow(buffer: CodeBuffer, decorations: CodeDecorations, width: Float = 400, height: Float = 200,
                           scale: Float = 1, numbers: Bool = true) throws -> TestWindow {
    try harnessWindow(size: sz(width, height), scaleFactor: scale) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(numbers)
    }
}

@MainActor func totalWork(_ window: TestWindow) -> FrameWork {
    window.frameWork.reduce(FrameWork(), +)
}

/// 1.1 — opening a file shapes only the rows on screen, and the count does not depend on the file's size
/// (Alloy's addendum 6: "open = visible rows shaped"). **Red before:** a spelling that shapes every line on
/// open shapes 100 000. **Mutation:** the row loop runs over `0..<displayRows`.
@Test(arguments: [1_000, 100_000]) @MainActor func openingShapesOnlyTheVisibleRows(lines: Int) throws {
    let buffer = CodeBuffer(codeText(lines: lines))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let open = totalWork(window)
    let visible = Int((200 / codePitch(scale: 1)).rounded(.up))
    #expect(open.codeLinesPainted == visible, "painted \(open.codeLinesPainted), visible \(visible)")
    #expect(open.codeLinesShaped == visible + 1, "shaped \(open.codeLinesShaped): the visible rows and one of overscan")
    #expect(open.codeGlyphsEmitted > 0)
}

/// 1.2 — the same cost at both sizes, side by side (so a regression names both numbers).
@Test @MainActor func theOpenCostIsTheSameAt1kAnd100kLines() throws {
    var shaped: [Int] = [], painted: [Int] = [], glyphs: [Int] = []
    for lines in [1_000, 100_000] {
        let buffer = CodeBuffer(codeText(lines: lines))
        let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
        let w = totalWork(window)
        shaped.append(w.codeLinesShaped); painted.append(w.codeLinesPainted); glyphs.append(w.codeGlyphsEmitted)
    }
    #expect(shaped[0] == shaped[1] && painted[0] == painted[1] && glyphs[0] == glyphs[1],
            "shaped \(shaped), painted \(painted), glyphs \(glyphs)")
}

/// 1.3 — a scroll of exactly one row shapes exactly one line (the row entering the overscan) and paints
/// the visible count; a frame with no scroll shapes none.
@Test(arguments: [1_000, 100_000]) @MainActor func scrollingOneRowShapesOneLine(lines: Int) throws {
    let buffer = CodeBuffer(codeText(lines: lines))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    let pitch = codePitch(scale: 1)
    let visible = Int((200 / pitch).rounded(.up))
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch)
    window.resetFrameWork()
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch)
    let one = totalWork(window)
    #expect(one.codeLinesShaped == 1, "one row entered: shaped \(one.codeLinesShaped)")
    #expect(one.codeLinesPainted == visible || one.codeLinesPainted == visible + 1, "painted \(one.codeLinesPainted)")
    window.resetFrameWork()
    window.window.setNeedsRedraw()
    window.tick()
    #expect(totalWork(window).codeLinesShaped == 0, "a warm frame shapes nothing")
}

// MARK: - Geometry, tabs, tints

@MainActor func tintRects(_ window: TestWindow, alpha: Float) -> [MUIRect] {
    window.scene.rects.filter { abs($0.background.a - alpha) < 0.001 }
}

/// 2.1 — every row's top and height are whole device pixels, at the fractional scale Windows uses: a tint
/// over rows 2..<4 is a rect `2 * pitchPx` tall whose top is `2 * pitchPx` from the view's, both integers.
/// **Mutation:** `pitchPx` taken as `Int(lineHeight * scale)` truncated instead of rounded, or the pitch
/// kept fractional, moves the rect off the integer grid or off `2 * pitchPx`.
@Test @MainActor func rowsAreWholeDevicePixelsAtAFractionalScale() throws {
    let buffer = CodeBuffer(codeText(lines: 50))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 2..<4, background: Color(red: 1, green: 0, blue: 0).opacity(0.37))],
                                   asOf: buffer.version)
    let window = try codeWindow(buffer: buffer, decorations: decorations, scale: 1.25)
    let pitchPx = Int((codePitch(scale: 1.25) * 1.25).rounded())
    let tint = try #require(tintRects(window, alpha: 0.37).first)
    #expect(tint.bounds.size.height == Float(2 * pitchPx), "tint height \(tint.bounds.size.height), pitch \(pitchPx)")
    #expect(tint.bounds.origin.y == Float(2 * pitchPx), "tint top \(tint.bounds.origin.y)")
    #expect(tint.bounds.origin.y.rounded() == tint.bounds.origin.y)
}

/// 2.2 — a tab advances to the next multiple of `tabWidth` space advances from the pen's real end, not from a
/// glyph count: `"\t"` is 4 advances wide, `"il\t"` is also 4 (not 2 + 4), and `"\t\t"` is 8.
/// **Mutation:** the stop computed from the number of glyphs placed (`count + tab`) reddens the second.
@Test @MainActor func tabsStopOnMultiplesOfTheSpaceAdvance() throws {
    let buffer = CodeBuffer("\tx\nil\tx\n\t\tx\n")
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations, numbers: false)
    let system = harnessTextSystem()
    let font = system.resolveFont(FontDescriptor(family: nil, size: 12, design: .monospaced))
    let advance = Float(system.measure(" ", font: font, wrappingAt: nil).widestLine)
    func width(of range: Range<Int>) -> Float {
        buffer.select(range, reveal: false)
        window.window.setNeedsRedraw(); window.tick()
        return tintRects(window, alpha: 0.3).first?.bounds.size.width ?? -1
    }
    #expect(abs(width(of: 0..<1) - 4 * advance) <= 1, "one tab")
    #expect(abs(width(of: 3..<6) - 4 * advance) <= 1, "il + tab ends on the stop at 4 advances")
    #expect(abs(width(of: 8..<10) - 8 * advance) <= 1, "two tabs")
}

/// 2.3 — line tints and gutter bars are drawn: one tint rect over consecutive equal rows, and a bar in the gutter.
@Test @MainActor func lineTintsMergeAndGutterBarsDraw() throws {
    let buffer = CodeBuffer(codeText(lines: 50))
    let decorations = CodeDecorations(buffer: buffer)
    let green = Color(red: 0, green: 1, blue: 0)
    decorations.setLineDecorations([CodeLineDecoration(lines: 1..<4, gutterBar: green.opacity(0.61), background: green.opacity(0.29))],
                                   asOf: buffer.version)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    #expect(tintRects(window, alpha: 0.29).count == 1, "three equal rows are one rectangle")
    #expect(tintRects(window, alpha: 0.61).count == 1, "and one bar")
    let bar = try #require(tintRects(window, alpha: 0.61).first)
    #expect(bar.bounds.size.height == 3 * codePitch(scale: 1))
}

// MARK: - Selection, copy, scrolling

@MainActor func selectedText(_ buffer: CodeBuffer) -> String {
    buffer.snapshot().text(in: buffer.primarySelection.range)
}

/// 3.1 — dragging selects, and the copy key writes the selection as plain text (read-only copy).
/// **Mutation:** the copy handler returning `[]`, or the drag selecting nothing, reddens it.
@Test @MainActor func draggingSelectsAndCopyWritesTheSelection() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    window.drag(from: pt(60, 6), to: pt(140, 6))
    let selection = buffer.primarySelection.range
    let line0 = buffer.snapshot().lineRange(0)
    #expect(!selection.isEmpty && line0.contains(selection.lowerBound) && selection.upperBound <= line0.upperBound,
            "selected \(selection) in \(line0)")
    window.typeKey("c", modifierFlags: codePrimary)
    let rep = try #require(window.clipboardRepresentations.first, "the copy wrote a representation")
    #expect(String(decoding: rep.bytes, as: UTF8.self) == selectedText(buffer))
    #expect(!selectedText(buffer).isEmpty)
}

/// 3.2 — a double click selects the word, a press in the gutter selects the line with its break, and a plain
/// click puts the caret (an empty selection) where it lands.
@Test @MainActor func doubleClickSelectsAWordAndAGutterPressALine() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    window.click(at: pt(60, 6))
    #expect(buffer.primarySelection.isEmpty && buffer.snapshot().lineRange(0).contains(buffer.primarySelection.head))
    window.doubleClick(at: pt(85, 6))
    #expect(selectedText(buffer) == "value0", "double click: \(selectedText(buffer))")
    let pitch = codePitch(scale: 1)
    window.click(at: pt(10, pitch + 4))
    let snap = buffer.snapshot()
    let line1 = snap.offset(of: CodePoint(row: 1, column: 0))..<snap.offset(of: CodePoint(row: 2, column: 0))
    #expect(buffer.primarySelection.range == line1, "gutter press: \(buffer.primarySelection.range) vs \(line1)")
}

/// 3.3 — the wheel scrolls both axes, clamped; the vertical and horizontal indicators draw, and the
/// horizontal clamp counts the width measured, not only the estimate (a row of wide glyphs the estimate from
/// the space advance would call narrow). **Mutation:** the clamp built from the estimate alone leaves
/// `maxScrollXPx` 0 for the wide line, so the second expectation reddens.
@Test @MainActor func theWheelScrollsBothAxesAndTheClampCountsMeasuredWidth() throws {
    let wide = String(repeating: "W", count: 120)
    let buffer = CodeBuffer(wide + "\n" + codeText(lines: 200))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    window.window.setNeedsRedraw(); window.tick()
    buffer.select(0..<1, reveal: false)
    window.window.setNeedsRedraw(); window.tick()
    let x0 = try #require(tintRects(window, alpha: 0.3).first).bounds.origin.x
    window.scroll(at: pt(200, 100), byDeltaX: -60, deltaY: 0)
    let x1 = try #require(tintRects(window, alpha: 0.3).first).bounds.origin.x
    #expect(x0 - x1 == 60, "scrolled 60 points left: \(x0) -> \(x1)")
    #expect(window.scene.rects.contains { $0.bounds.size.height == 3 && $0.bounds.origin.y == 195 }, "the horizontal indicator")
    window.scroll(at: pt(200, 100), byDeltaX: -100_000, deltaY: 0)
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -100_000)
    window.scroll(at: pt(200, 100), byDeltaX: 100_000, deltaY: 100_000)
    window.scroll(at: pt(200, 100), byDeltaX: -100_000, deltaY: 0)
    #expect(window.scene.rects.contains { $0.bounds.size.width == 3 && $0.bounds.origin.x == 395 }, "the vertical indicator")
    window.scroll(at: pt(200, 100), byDeltaX: 100_000, deltaY: 100_000)
    let back = totalWork(window)
    _ = back
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: 100_000)
    #expect(window.scene.glyphs.count > 0, "scrolled back to the top")
}

/// 3.4 — lines inserted above the viewport do not move what the reader is looking at: the scroll anchor is a
/// byte offset mapped through the buffer's edit log. **Mutation:** the anchor kept as a row number reddens it.
@Test @MainActor func linesInsertedAboveKeepTheTopRowInPlace() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    let pitch = codePitch(scale: 1)
    window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch * 100)
    window.click(at: pt(60, 2))
    let before = buffer.snapshot().point(at: buffer.primarySelection.head).row
    #expect(before == 100, "the top row after a 100-row scroll: \(before)")
    let text = buffer.snapshot().line(before)
    buffer.replace(0..<0, with: String(repeating: "added\n", count: 20))
    window.window.setNeedsRedraw(); window.tick()
    window.click(at: pt(60, 2))
    let after = buffer.snapshot().point(at: buffer.primarySelection.head).row
    #expect(after == before + 20 && buffer.snapshot().line(after) == text, "the same text, 20 rows lower: row \(after)")
}

/// 3.5 — `select(_:reveal: true)` centres the line (Alloy's addendum 5): the head's row is at the middle of
/// the viewport one frame later, from the top and from far below.
@Test @MainActor func revealCentresTheSelectionsLine() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    let pitch = codePitch(scale: 1)
    for target in [700, 20, 990] {
        let offset = buffer.snapshot().offset(of: CodePoint(row: target, column: 0))
        buffer.select(offset..<offset, reveal: true)
        window.window.setNeedsRedraw(); window.tick()
        let middle = (200 - pitch) / 2 + pitch / 2
        window.click(at: pt(60, middle))
        let row = buffer.snapshot().point(at: buffer.primarySelection.head).row
        let expected = min(target, 1000 - 1 - Int(((200 - pitch) / 2 / pitch).rounded(.down)) + 0)
        #expect(abs(row - target) <= (target == 990 ? 6 : 0), "target \(target), middle row \(row), \(expected)")
    }
}

// MARK: - Decorations

/// A provider that records what it was asked and colours whole rows, answering synchronously unless told not to.
@MainActor final class RecordingProvider: CodeHighlightProvider {
    var calls: [Range<Int>] = []
    var style: CodeStyleID
    var answers = true
    init(style: CodeStyleID) { self.style = style }
    func decorations(_ decorations: CodeDecorations, needHighlightsForRows rows: Range<Int>, in snapshot: CodeSnapshot) {
        calls.append(rows)
        guard answers else { return }
        let lo = snapshot.lineRange(rows.lowerBound).lowerBound, hi = snapshot.lineRange(rows.upperBound - 1).upperBound
        let runs = rows.map { CodeStyleRun(range: snapshot.lineRange($0), style: style) }.filter { !$0.range.isEmpty }
        decorations.setHighlights(runs, in: lo..<hi, layer: .syntax, asOf: snapshot.version)
    }
}

@MainActor func glyphColorAlphas(_ window: TestWindow, hue: Float) -> Int {   // glyphs of one text colour
    window.scene.glyphs.filter { abs($0.color.h - hue) < 0.001 }.count
}

/// 4.1 — the provider is asked once, after the frame and outside every phase (its answer is an `@Observable`
/// write, which a phase would lose), for the rows it is missing; its answer colours the glyphs in the same
/// tick; and nothing asks again while nothing changes.
/// **Mutation:** the request raised from `prepaint` itself (not queued) is a phase-time write and the colour
/// never reaches the frame; the dedupe removed asks every frame.
@Test @MainActor func theProviderIsAskedOnceAfterTheFrameAndItsAnswerColoursTheText() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let decorations = CodeDecorations(buffer: buffer)
    let red = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    let provider = RecordingProvider(style: red)
    decorations.highlightProvider = provider
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    #expect(provider.calls.count == 1, "asked \(provider.calls)")
    #expect(provider.calls.first?.lowerBound == 0)
    #expect(glyphColorAlphas(window, hue: 0.123) > 100, "the answer coloured the text: \(glyphColorAlphas(window, hue: 0.123))")
}

/// 4.1b — the provider is asked **outside every phase**, so its answer (an observed write) is in the same
/// presented frame by the lifecycle drain's one settle build (`LC-E`), and an unanswered ask is not repeated
/// while nothing changes. **Mutations:** the call made from `prepaint` itself leaves the open frame at one
/// build (a phase-time write is stale); the dedupe removed asks on every redraw.
@Test @MainActor func theProvidersAnswerIsInTheFrameThatAskedAndAnUnansweredAskIsNotRepeated() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let decorations = CodeDecorations(buffer: buffer)
    let red = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    let provider = RecordingProvider(style: red)
    decorations.highlightProvider = provider
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    #expect(window.frameWork.first?.builds == 2, "the open frame built once for the view and once after the answer: \(window.frameWork.first?.builds as Any)")
    #expect(glyphColorAlphas(window, hue: 0.123) > 100, "and presented the coloured text")
    // An unanswered ask is made once.
    let silent = CodeBuffer(codeText(lines: 1000))
    let silentDecorations = CodeDecorations(buffer: silent)
    let quiet = RecordingProvider(style: silentDecorations.register(CodeStyle(foreground: .red)))
    quiet.answers = false
    silentDecorations.highlightProvider = quiet
    let second = try codeWindow(buffer: silent, decorations: silentDecorations)
    for _ in 0..<3 { second.window.setNeedsRedraw(); second.tick() }
    #expect(quiet.calls.count == 1, "asked \(quiet.calls.count) times for rows nobody answered")
}

/// 4.2 — typing never flashes unstyled text: an edit marks the row stale, the old colour stays until the
/// provider answers (here it does not), and the provider is asked for that row.
@Test @MainActor func anEditKeepsTheOldColoursAndAsksAgain() throws {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let decorations = CodeDecorations(buffer: buffer)
    let red = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    let provider = RecordingProvider(style: red)
    decorations.highlightProvider = provider
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    let before = glyphColorAlphas(window, hue: 0.123)
    provider.answers = false
    provider.calls = []
    let start = buffer.snapshot().offset(of: CodePoint(row: 3, column: 0))
    buffer.replace(start..<start, with: "xx")
    window.window.setNeedsRedraw(); window.tick()
    #expect(glyphColorAlphas(window, hue: 0.123) >= before, "the row keeps its colour: \(before) -> \(glyphColorAlphas(window, hue: 0.123))")
    #expect(provider.calls.count == 1 && provider.calls[0].contains(3), "asked \(provider.calls)")
}

/// 4.3 — highlights given for an older version are mapped forward through the edits since: a run on row 5
/// given at version v lands on the same text after 3 lines were inserted above.
/// **Mutation:** `setHighlights` ignoring `asOf` puts the colour 3 rows too high.
@Test @MainActor func highlightsGivenForAnOlderVersionAreMappedForward() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    let style = decorations.register(CodeStyle(foreground: Color(hue: 0.5, saturation: 1, brightness: 1)))
    let version = buffer.version
    let row5 = buffer.snapshot().lineRange(5)
    buffer.replace(0..<0, with: "a\nb\nc\n")
    decorations.setHighlights([CodeStyleRun(range: row5, style: style)], in: 0..<buffer.snapshot().utf8Count - 6, layer: .syntax, asOf: version)
    let now = buffer.snapshot()
    let styled = decorations.stylingOfLine(now.lineRange(8)).foreground
    let early = decorations.stylingOfLine(now.lineRange(5)).foreground
    #expect(styled.contains { $0.style == style }, "row 8 carries the run: \(styled)")
    #expect(!early.contains { $0.style == style }, "row 5 does not: \(early)")
}

/// 4.4 — line decorations shift with newlines above them, in a number of tree nodes that does not grow with
/// the row count (a counter; 1k against 100k rows). **Mutation:** an array-backed store moving every later
/// decoration visits O(n) entries; the tree's difference stays inside the constant.
@Test @MainActor func lineDecorationsShiftInLogarithmicWork() throws {
    var visited: [Int] = []
    for lines in [1_000, 100_000] {
        let buffer = CodeBuffer(String(repeating: "x\n", count: lines))
        let decorations = CodeDecorations(buffer: buffer)
        let decos = stride(from: 10, to: lines - 2, by: 3).map {
            CodeLineDecoration(lines: $0..<($0 + 1), gutterBar: Color(hue: 0.3, saturation: 1, brightness: 1))
        }
        decorations.setLineDecorations(decos, asOf: buffer.version)
        decorations.sync()
        let start = buffer.snapshot().offset(of: CodePoint(row: 5, column: 0))
        let before = RunTreeStats.nodesVisited
        buffer.replace(start..<start, with: "\n")
        decorations.sync()
        visited.append(RunTreeStats.nodesVisited - before)
        #expect(decorations.lineDecoration(row: 11)?.gutterBar != nil, "row 10 moved to 11")
        #expect(decorations.lineDecoration(row: 14)?.gutterBar != nil, "row 13 moved to 14")
        #expect(decorations.lineDecoration(row: 10) == nil)
    }
    #expect(visited[1] - visited[0] <= 40, "nodes visited for one newline: \(visited) at 1k and 100k rows")
}

/// 4.5 — the annotations layer is drawn as a background under the syntax text: a rectangle over the run's
/// bytes on its row, while the syntax layer's foreground still colours the glyphs.
@Test @MainActor func annotationBackgroundsSitUnderSyntaxText() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    let author = decorations.register(CodeStyle(background: Color(hue: 0.9, saturation: 1, brightness: 1).opacity(0.43)))
    let syntax = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    let row = buffer.snapshot().lineRange(2)
    decorations.setHighlights([CodeStyleRun(range: row, style: author)], in: row, layer: .annotations, asOf: buffer.version)
    decorations.setHighlights([CodeStyleRun(range: row, style: syntax)], in: row, layer: .syntax, asOf: buffer.version)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let rect = try #require(tintRects(window, alpha: 0.43).first)
    let colored = window.scene.glyphs.filter { abs($0.color.h - 0.123) < 0.001 }
    #expect(!colored.isEmpty, "the syntax colour reaches the glyphs")
    // A scene draws its rects before its glyphs, so a background rect is under the text by construction.
    #expect(rect.bounds.origin.y == 2 * codePitch(scale: 1), "the run background is on row 2: \(rect.bounds.origin.y)")
    #expect(rect.bounds.size.height == codePitch(scale: 1))
}

/// 4.6 — a highlight that splits a line the cache already holds re-colours exactly the glyphs of its range:
/// the foreground partition is in the cache key, so the line is laid out again with its two parts.
/// **Mutation:** the key without the digest returns the old one-part layout and colours the whole row.
@Test @MainActor func aHighlightThatSplitsACachedLineRecoloursExactlyItsGlyphs() throws {
    let buffer = CodeBuffer(String(repeating: "let value = 1\n", count: 20))
    let decorations = CodeDecorations(buffer: buffer)
    let style = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    #expect(glyphColorAlphas(window, hue: 0.123) == 0)
    decorations.setHighlights([CodeStyleRun(range: 0..<3, style: style)], in: 0..<3, layer: .syntax, asOf: buffer.version)
    window.window.setNeedsRedraw(); window.tick()
    #expect(glyphColorAlphas(window, hue: 0.123) == 3, "the three glyphs of `let`: \(glyphColorAlphas(window, hue: 0.123))")
}

/// 4.7 — a scale change re-shapes the visible lines (the scale is in the cache key; a glyph key carries the
/// scale it was rasterized for). **Mutation:** the key without the scale serves 1x glyphs at 2x.
@Test @MainActor func aScaleChangeShapesTheVisibleLinesAgain() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    window.resetFrameWork()
    window.setScaleFactor(2)
    window.tick()
    #expect(totalWork(window).codeLinesShaped >= 5, "shaped \(totalWork(window).codeLinesShaped) after the scale changed")
}

/// 4.8 — the cache keeps two frames, not every line ever seen: after 300 one-row scrolls it holds a few
/// screens of entries. **Mutation:** a cache that never rotates holds all 300 rows.
@Test @MainActor func theLineCacheKeepsOnlyTwoFramesOfLines() throws {
    let buffer = CodeBuffer(codeText(lines: 2000))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let pitch = codePitch(scale: 1)
    for _ in 0..<300 { window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch) }
    let visible = Int((200 / pitch).rounded(.up))
    #expect(decorations.lineCache.count <= 2 * (2 * (visible + 3)), "entries held: \(decorations.lineCache.count)")
}

// MARK: - The leaf, retention, observation

private struct CodeCard: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup { CodeView(buffer: buffer, decorations: decorations).font(size: 12) }
    static func == (l: CodeCard, r: CodeCard) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

/// 5.1 — the leaf's measure reads nothing of the buffer: a keystroke re-lays-out no ancestor (the whole
/// layout is restored from the memo), and two views of different buffers and faces measure the same.
/// **Mutation:** the measure closure reading `buffer.utf8Count` makes the leaf unkeyable, so the memo misses
/// on the edit and `layoutMeasureCalls` is not 0.
@Test @MainActor func aKeystrokeInTheBufferRelaysOutNothing() throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Text("title")
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).frame(height: Pixels(120))
        }
    }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    window.resetFrameWork()
    buffer.replace(0..<0, with: "x")
    window.window.setNeedsRedraw(); window.tick()
    let w = totalWork(window)
    #expect(w.layoutMeasureCalls == 0, "measure calls \(w.layoutMeasureCalls): the leaf's key must cover its closure")
    #expect(w.layoutMemoMisses == 0 && w.layoutMemoRootHits >= 1, "memo misses \(w.layoutMemoMisses), root hits \(w.layoutMemoRootHits)")
    #expect(w.codeLinesShaped == 1, "one edited line re-shaped: \(w.codeLinesShaped)")
}

@Test @MainActor func twoViewsOfDifferentBuffersAndFacesMeasureTheSame() throws {
    let a = CodeBuffer("short"), b = CodeBuffer(codeText(lines: 5000))
    let da = CodeDecorations(buffer: a), db = CodeDecorations(buffer: b)
    let window = try harnessWindow(size: sz(300, 400)) {
        VStack(spacing: 0) {
            CodeView(buffer: a, decorations: da).font(size: 11).id("a")
            CodeView(buffer: b, decorations: db).font(size: 30).tabWidth(8).id("b")
        }
    }
    let fa = try window.frame(ofID: "a"), fb = try window.frame(ofID: "b")
    #expect(fa.size == fb.size, "\(fa.size) vs \(fb.size)")
}

/// 5.2 — an unfocused `CodeView` inside an `.equatable()` component replays its paint and prepaint, and an
/// edit to the buffer (an observed read) still repaints it (Stop condition: `METALUI_VERIFY_RETAINED=1` is
/// run over this test, which also compares every replay against a fresh run).
@Test @MainActor func anUnfocusedCodeViewIsRetainedAndAnEditRepaintsIt() throws {
    let buffer = CodeBuffer(codeText(lines: 300))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(20), height: Pixels(20)).focusable()
            CodeCard(buffer: buffer, decorations: decorations).equatable().frame(height: Pixels(150))
        }
    }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    window.resetFrameWork()
    window.window.setNeedsRedraw(); window.tick()
    let idle = totalWork(window)
    #expect(idle.retainedHits >= 1, "hits \(idle.retainedHits), misses \(idle.retainedMisses), ineligible \(idle.retainedIneligibleReasons)")
    #expect(idle.codeLinesShaped == 0)
    let glyphs = window.scene.glyphs.count
    buffer.replace(0..<0, with: String(repeating: "wide text wide text wide text ", count: 3) + "\n")
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.scene.glyphs.count > glyphs, "the edit repainted the retained view: \(glyphs) -> \(window.scene.glyphs.count)")
}

/// 5.3 — an edit alone redraws the window: no `setNeedsRedraw`, the observation does it (on Linux and Windows
/// the hop is asynchronous, so the wait is `runUntilIdle`).
@Test @MainActor func aBufferEditRedrawsTheWindowByObservation() async throws {
    let buffer = CodeBuffer(codeText(lines: 100))
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    let glyphs = window.scene.glyphs.count
    buffer.replace(0..<0, with: String(repeating: "wide text wide text wide text ", count: 3) + "\n")
    try await window.runUntilIdle()
    #expect(window.scene.glyphs.count > glyphs, "\(glyphs) -> \(window.scene.glyphs.count)")
    let tinted = decorations.register(CodeStyle(background: Color(hue: 0.9, saturation: 1, brightness: 1).opacity(0.47)))
    decorations.setHighlights([CodeStyleRun(range: 0..<5, style: tinted)], in: 0..<5, layer: .annotations, asOf: buffer.version)
    try await window.runUntilIdle()
    #expect(tintRects(window, alpha: 0.47).count == 1, "a decoration write redraws too")
}

// MARK: - Long lines, allocations

/// 6.1 — a 20 KB line is shaped in a column window, not whole: the bytes shaped on open are a small fraction
/// of the line, and scrolling horizontally shapes a new window only past the 256-column margin.
@Test @MainActor func aLongLineIsShapedInAWindow() throws {
    let long = (0..<3000).map { "tok\($0 % 997) " }.joined()   // ~20 KB, distinct
    #expect(long.utf8.count > 18_000)
    let buffer = CodeBuffer("short\n" + long + "\nshort\n")
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    #expect(decorations.shapedBytes < 4_000, "shaped \(decorations.shapedBytes) bytes of a 20 KB line")
    let afterOpen = decorations.shapedBytes
    window.scroll(at: pt(200, 100), byDeltaX: -20, deltaY: 0)
    #expect(decorations.shapedBytes - afterOpen == 0, "a 20 pt scroll stays inside the window")
    window.scroll(at: pt(200, 100), byDeltaX: -4_000, deltaY: 0)
    #expect(decorations.shapedBytes > afterOpen && decorations.shapedBytes < afterOpen + 4_000, "a far scroll shapes one more window")
}

#if canImport(Darwin)
import MetalUITestSupport

/// Distinct lines of one byte length, so the glyph count of a row is the same at every scroll position.
@MainActor func fixedWidthText(lines: Int) -> String {
    var out = ""
    out.reserveCapacity(lines * 24)
    for i in 0..<lines { out += "row\(String(i + 1_000_000)) = \(i % 10)\n" }
    return out
}

/// 6.2 — the heap allocations of a warm scroll frame do not grow with the file or the scroll position
/// (Darwin, `malloc_logger`; differential, never an absolute number), line numbers off so a longer number is
/// not a difference. At one position the two sizes differ only by the rope's height (2 against 3 levels), a
/// few allocations per visible row, so the same-position pin is "within 20 per visible row"; the position
/// pin is that 90 000 rows down costs what 600 rows down does (within the same bound again, not 150x more).
/// An O(n) spelling (counting lines to the anchor, copying the text) is orders over both.
/// **Mutation:** `makePlan` reading `snap.text` once per frame.
@Test @MainActor func aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition() throws {
    var counts: [String: Int] = [:]
    let visible = Int((200 / codePitch(scale: 1)).rounded(.up)) + 1
    for (lines, positions) in [(1_000, [0, 600]), (100_000, [0, 600, 90_000])] {
        let buffer = CodeBuffer(fixedWidthText(lines: lines))
        let window = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer), numbers: false)
        let pitch = codePitch(scale: 1)
        for position in positions {
            window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -pitch * Float(position))
            for _ in 0..<6 { window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -1) }   // warm: sub-row steps
            counts["\(lines)@\(position)"] = try #require(countAllocations { window.scroll(at: pt(200, 100), byDeltaX: 0, deltaY: -1) })
        }
    }
    let bound = 20 * visible
    for position in [0, 600] {
        let a = counts["1000@\(position)"]!, b = counts["100000@\(position)"]!
        #expect(abs(a - b) <= bound, "1k against 100k at \(position): \(a) vs \(b), bound \(bound)")
    }
    let deep = counts["100000@90000"]!, shallow = counts["100000@600"]!
    #expect(abs(deep - shallow) <= 3 * bound, "90 000 rows down \(deep) against 600 rows down \(shallow)")
}
#endif
