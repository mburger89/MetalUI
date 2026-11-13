import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeView` underlines and squiggles (rulings `CV-AM`, `CV-AN`, record 271): a `CodeUnderline` on a `CodeStyle`,
// the highest layer's winning per stretch, never part of a line's shaped layout, drawn after every row's glyphs.
// PLAIN imports; text is the harness's Noto Sans through `PortableTextSystem`.

private let squiggleColor = Color(red: 0.9, green: 0.1, blue: 0.2)
private let lineColor = Color(red: 0.1, green: 0.9, blue: 0.2).opacity(0.77)

/// Twelve distinct rows of 40 letters: no row is another's, none has a tab, so columns are plain.
private func letters(rows: Int = 12) -> String {
    (0..<rows).map { row in String((0..<40).map { Character(UnicodeScalar(UInt8(97 + ($0 + row) % 26))) }) }.joined(separator: "\n") + "\n"
}

/// The byte range of columns `from..<to` of `row` (the text is ASCII).
@MainActor private func columns(_ buffer: CodeBuffer, row: Int, _ from: Int, _ to: Int) -> Range<Int> {
    let line = buffer.snapshot().lineRange(row)
    return (line.lowerBound + from)..<(line.lowerBound + to)
}

@MainActor private func diagnose(_ decorations: CodeDecorations, _ buffer: CodeBuffer, _ runs: [(Range<Int>, CodeUnderline)],
                                 layer: CodeHighlightLayer = .diagnostics) {
    let coded = runs.map { CodeStyleRun(range: $0.0, style: decorations.register(CodeStyle(underline: $0.1))) }
    decorations.setHighlights(coded, in: 0..<buffer.utf8Count, layer: layer, asOf: buffer.version)
}

/// The 8-bit alpha of every texel of `image`, summed down each device column: x -> coverage.
private func profile(_ scene: Scene, _ image: MUIImage) -> [Int: Int] {
    let texture = scene.textures[Int(image.texture)]
    var sums: [Int: Int] = [:]
    for ty in 0..<texture.height {
        for tx in 0..<texture.width {
            sums[Int(image.bounds.origin.x) + tx, default: 0] += Int(texture.pixels[(ty * texture.width + tx) * 4 + 3])
        }
    }
    return sums
}

// MARK: Styling

/// (a) — per stretch the highest layer's underline wins, adjacent equal stretches join, and a layer with no
/// underline does not hide a lower layer's. **Mutation:** the layers walked highest first (the first underline
/// found wins) gives the syntax layer's wave where the diagnostics' dash belongs.
@Test @MainActor func theHighestLayerUnderlineWinsPerSegment() {
    let buffer = CodeBuffer(letters())
    let decorations = CodeDecorations(buffer: buffer)
    let dash = CodeUnderline(.line(.dash), color: lineColor), wave = CodeUnderline.wavy(squiggleColor)
    diagnose(decorations, buffer, [(columns(buffer, row: 0, 2, 12), wave)], layer: .syntax)
    diagnose(decorations, buffer, [(columns(buffer, row: 0, 5, 8), dash)], layer: .diagnostics)
    // A higher layer with a colour but no underline does not hide the wave.
    let red = decorations.register(CodeStyle(foreground: Color(red: 1, green: 0, blue: 0)))
    decorations.setHighlights([CodeStyleRun(range: columns(buffer, row: 0, 0, 40), style: red)], in: 0..<buffer.utf8Count,
                              layer: .semantic, asOf: buffer.version)
    let line = buffer.snapshot().lineRange(0)
    let styling = decorations.stylingOfLine(line)
    let got = styling.underlines.map { "\($0.range.lowerBound - line.lowerBound)..<\($0.range.upperBound - line.lowerBound):\($0.underline.shape)" }
    #expect(got == ["2..<5:wavy", "5..<8:line(MetalUI.Text.LineStyle.Pattern(kind: MetalUI.Text.LineStyle.Pattern.Kind.dash))",
                    "8..<12:wavy"], "\(got)")
}

/// (b) — an underline-only style reshapes nothing: the foreground partition and its digest are the same, so
/// the cached line layouts are kept. **Mutation:** `computeForeground` lets a run that only underlines win the
/// foreground partition (an underline in the digest) and every row shapes again.
@Test @MainActor func anUnderlineOnlyStyleReshapesNothing() throws {
    let buffer = CodeBuffer(letters())
    let decorations = CodeDecorations(buffer: buffer)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    window.resetFrameWork()
    diagnose(decorations, buffer, [(columns(buffer, row: 1, 3, 9), .wavy(squiggleColor)), (columns(buffer, row: 3, 0, 4), CodeUnderline())])
    window.window.setNeedsRedraw(); window.tick()
    let work = totalWork(window)
    #expect(work.codeLinesShaped == 0, "shaped \(work.codeLinesShaped)")
    #expect(work.rasterizedPixels > 0 && !window.scene.images.isEmpty, "and the squiggle was drawn")
}

/// (c) — zero-width ranges draw one character, at a line's end one space advance past the last glyph, on an
/// empty row one space, and at the end of the text under the last character. **Mutation:** no minimum (the empty
/// run dropped in `setHighlights`) leaves every underline list empty.
@Test @MainActor func zeroWidthAndEndOfLineRangesDrawOneCharacter() {
    let buffer = CodeBuffer("abcd\n\nef")
    let decorations = CodeDecorations(buffer: buffer)
    let solid = CodeUnderline(.line(.solid), color: lineColor)
    diagnose(decorations, buffer, [(2..<2, solid), (4..<4, solid), (5..<5, solid), (8..<8, solid)])
    let snapshot = buffer.snapshot()
    func ranges(_ row: Int) -> [Range<Int>] { decorations.stylingOfLine(snapshot.lineRange(row)).underlines.map(\.range) }
    #expect(ranges(0) == [2..<3, 4..<5], "inside the line: the character; at its end: the line break's first byte: \(ranges(0))")
    #expect(ranges(1) == [5..<6], "an empty row: its break: \(ranges(1))")
    #expect(ranges(2) == [7..<8], "the end of the text: the last character: \(ranges(2))")
}

/// (d) — a run that continues over the line break into the next row draws no tail on the first.
@Test @MainActor func aRunSpanningTwoRowsHasNoTailOnTheFirst() {
    let buffer = CodeBuffer("abcd\nefgh\n")
    let decorations = CodeDecorations(buffer: buffer)
    diagnose(decorations, buffer, [(2..<7, CodeUnderline(.line(.solid), color: lineColor))])
    let snapshot = buffer.snapshot()
    #expect(decorations.stylingOfLine(snapshot.lineRange(0)).underlines.map(\.range) == [2..<4])
    #expect(decorations.stylingOfLine(snapshot.lineRange(1)).underlines.map(\.range) == [5..<7])
}

// MARK: Paint

/// The underline rectangles of `lineColor`, left to right, with the row they sit in (by their top).
@MainActor private func lineRects(_ window: TestWindow) -> [MUIRect] {
    tintRects(window, alpha: 0.77).sorted { ($0.bounds.origin.y, $0.bounds.origin.x) < ($1.bounds.origin.y, $1.bounds.origin.x) }
}

/// (e) — a dotted underline is the text pattern's cycle (3 thicknesses on, 3 off), counted from the first column
/// of the line, not from the run: two runs starting at different columns land on one grid. **Mutation:** the
/// cycle's origin taken at the run's start puts the second row's dots off the first's grid.
@Test @MainActor func dottedUsesTheTextPatternCycle() throws {
    let buffer = CodeBuffer(letters())
    let decorations = CodeDecorations(buffer: buffer)
    let dot = CodeUnderline(.line(.dot), color: lineColor)
    diagnose(decorations, buffer, [(columns(buffer, row: 2, 3, 30), dot), (columns(buffer, row: 4, 8, 30), dot)])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    let rects = lineRects(window)
    let tops = Set(rects.map(\.bounds.origin.y)).sorted()
    try #require(tops.count == 2, "two rows of dots: \(tops)")
    let upper = rects.filter { $0.bounds.origin.y == tops[0] }, lower = rects.filter { $0.bounds.origin.y == tops[1] }
    #expect(upper.count > 8 && lower.count > 8, "\(upper.count), \(lower.count)")
    #expect(Set(upper.dropFirst().dropLast().map(\.bounds.size.width)) == [3], "dots are 3 thicknesses: \(upper.map(\.bounds.size.width))")
    for (a, b) in zip(upper.dropFirst(), upper.dropFirst(2)) { #expect(b.bounds.origin.x - a.bounds.origin.x == 6, "a 6-pixel cycle") }
    let grid = Int(upper[1].bounds.origin.x) % 6
    #expect(lower.dropFirst().allSatisfy { Int($0.bounds.origin.x) % 6 == grid }, "one grid for both rows: \(lower.map(\.bounds.origin.x))")
}

/// (f) — a squiggle is one path per run, its phase anchored at the line's first column: two runs on different
/// rows starting at different columns draw the same wave where they overlap, and the wave repeats every period.
/// **Mutation:** the first period started at the run's own start shifts the second run's phase.
@Test @MainActor func aWavyUnderlineIsOnePathPerRunAnchoredAtTheLineStart() throws {
    let buffer = CodeBuffer(letters())
    let decorations = CodeDecorations(buffer: buffer)
    let wave = CodeUnderline.wavy(squiggleColor)
    diagnose(decorations, buffer, [(columns(buffer, row: 1, 3, 30), wave), (columns(buffer, row: 3, 6, 30), wave)])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    let scene = window.scene
    let images = scene.images.sorted { $0.bounds.origin.y < $1.bounds.origin.y }
    try #require(images.count == 2, "one path per run: \(images.count)")
    let a = profile(scene, images[0]), b = profile(scene, images[1])
    let shared = Set(a.keys).intersection(b.keys).sorted().dropFirst(2).dropLast(2)
    try #require(shared.count > 40, "the runs overlap: \(shared.count)")
    #expect(shared.allSatisfy { a[$0] == b[$0] }, "one wave for both: \(shared.map { "\($0):\(a[$0] ?? -1)/\(b[$0] ?? -1)" })")
    let xs = a.keys.sorted().dropFirst(2).dropLast(2)
    #expect(xs.dropLast(4).allSatisfy { a[$0] == a[$0 + 4] }, "a 4-pixel period at 12 points: \(xs.map { a[$0] ?? 0 })")
}

/// (g) — scrolling by whole pixels re-rasterizes nothing: the squiggle is a translation of the same path, down
/// by rows and along by columns. **Mutation:** a half-pixel offset that follows the row's top (the baseline kept
/// fractional) rasterizes again on the first row that moves by an odd pitch.
@Test(arguments: [Float(1), Float(2)]) @MainActor func aSquiggleIsCachedAcrossAScroll(scale: Float) throws {
    let buffer = CodeBuffer(letters(rows: 60))
    let decorations = CodeDecorations(buffer: buffer)
    diagnose(decorations, buffer, [(columns(buffer, row: 4, 3, 30), .wavy(squiggleColor))])
    let window = try codeWindow(buffer: buffer, decorations: decorations, width: 400, height: 200, scale: scale)
    window.window.setNeedsRedraw(); window.tick()
    #expect(totalWork(window).rasterizedPixels > 0 && window.scene.images.count == 1, "the first frames rasterized the wave")
    let pitch = codePitch(scale: scale)
    for (dx, dy) in [(0, -pitch), (0, -pitch), (-3, 0), (-7, -pitch)] as [(Float, Float)] {
        window.scroll(at: pt(200, 100), byDeltaX: dx, deltaY: dy)
        #expect(window.scene.images.count == 1, "still on screen")
        #expect(window.lastFrameWork.rasterizedPixels == 0, "scrolled (\(dx), \(dy)): rasterized \(window.lastFrameWork.rasterizedPixels)")
    }
}

/// (h) — a squiggle is painted after every row's glyphs and backgrounds, so one reaching into the next row is not
/// covered by that row's tint. **Mutation:** painting a row's underline inside the row loop puts the first row's
/// wave before the second row's background in scene order.
@Test @MainActor func squigglesPaintAfterTheNextRowsBackground() throws {
    let buffer = CodeBuffer(letters())
    let decorations = CodeDecorations(buffer: buffer)
    let tint = decorations.register(CodeStyle(background: Color(red: 0, green: 0.3, blue: 1).opacity(0.61)))
    decorations.setHighlights([CodeStyleRun(range: columns(buffer, row: 1, 0, 40), style: tint)], in: 0..<buffer.utf8Count,
                              layer: .annotations, asOf: buffer.version)
    diagnose(decorations, buffer, [(columns(buffer, row: 0, 2, 30), .wavy(squiggleColor))])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    let background = try #require(tintRects(window, alpha: 0.61).first)
    let scene = window.scene
    let rect = try #require(scene.rects.firstIndex { abs($0.background.a - 0.61) < 0.001 })
    func position(_ kind: PrimitiveKind, _ index: Int) -> Int? {
        scene.drawList.firstIndex { $0.kind == kind && index >= $0.start && index < $0.start + $0.count }
    }
    _ = background
    let tintAt = try #require(position(.rect, rect)), waveAt = try #require(position(.image, 0))
    #expect(waveAt > tintAt, "the wave (draw run \(waveAt)) is above the next row's background (run \(tintAt))")
}

/// (i) — at the end of a line the underline reaches one space advance past the last glyph: as wide as an
/// underlined space (a solid line, so the rectangle's width is the number). **Mutation:** the extent clamped to
/// the line's end gives a zero-width tail and no rectangle.
@Test @MainActor func anEndOfLineRangeIsOneSpaceAdvanceWide() throws {
    let buffer = CodeBuffer("mm mm\nxx\n")
    let decorations = CodeDecorations(buffer: buffer)
    let solid = CodeUnderline(.line(.solid), color: lineColor)
    diagnose(decorations, buffer, [(2..<3, solid), (5..<5, solid)])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    window.window.setNeedsRedraw(); window.tick()
    let rects = lineRects(window)
    try #require(rects.count == 2, "\(rects.count)")
    #expect(rects[1].bounds.origin.x > rects[0].bounds.origin.x + 10, "the tail is past the last glyph")
    #expect(abs(rects[0].bounds.size.width - rects[1].bounds.size.width) <= 1, "(within the rounding of two column edges) the tail \(rects[1].bounds.size.width) is a space's width \(rects[0].bounds.size.width)")
    #expect(rects[0].bounds.size.width > 1)
}

/// (j) — a repaint with underlines on screen recomputes neither styling nor row scans and rasterizes nothing
/// (the extension of `anIdleRepaintRecomputesNeitherStylingNorRowScans`).
@Test @MainActor func anIdleRepaintWithUnderlinesRecomputesAndRasterizesNothing() throws {
    let buffer = CodeBuffer(codeText(lines: 300))
    let decorations = CodeDecorations(buffer: buffer)
    let style = decorations.register(CodeStyle(foreground: Color(hue: 0.123, saturation: 0.8, brightness: 0.9)))
    decorations.highlightProvider = RecordingProvider(style: style)
    diagnose(decorations, buffer, [(columns(buffer, row: 1, 2, 6), .wavy(squiggleColor)), (columns(buffer, row: 2, 0, 4), CodeUnderline())])
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    let styled = decorations.stylingComputations, scanned = decorations.needingHighlightScans
    for _ in 0..<5 {
        window.window.setNeedsRedraw(); window.tick()
        #expect(window.lastFrameWork.rasterizedPixels == 0)
    }
    #expect(decorations.stylingComputations == styled && decorations.needingHighlightScans == scanned)
    #expect(!window.scene.images.isEmpty)
}

/// (k) — the API: `Text.LineStyle` converts, `wavy` defaults to the text colour, styles differing only in their
/// underline are distinct.
@Test func anUnderlineConvertsFromATextLineStyle() {
    let converted = CodeUnderline(Text.LineStyle(pattern: .dash, color: .red))
    #expect(converted == CodeUnderline(.line(.dash), color: .red))
    #expect(CodeUnderline.wavy().color == nil && CodeUnderline.wavy() == CodeUnderline(.wavy))
    #expect(CodeStyle(underline: .wavy()) != CodeStyle() && CodeStyle().underline == nil)
}

