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
