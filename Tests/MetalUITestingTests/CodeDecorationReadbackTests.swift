import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Reading highlights back (ruling `CV-AT`, record 284, Alloy G36): `CodeDecorations.highlights(in:layer:)` and
// `paintedRuns(in:)`. PLAIN imports; the harness text system.

private let hueA = 0.111, hueB = 0.222
private func fg(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.8, brightness: 0.9) }

/// Twelve rows of 40 distinct-ish letters, no spaces: every byte is a glyph.
private func letters(rows: Int = 12) -> String {
    (0..<rows).map { row in String((0..<40).map { Character(UnicodeScalar(UInt8(97 + ($0 + row) % 26))) }) }.joined(separator: "\n") + "\n"
}

/// 1 — a layer's runs read back clipped to the asked range, in order, with the id they were set with; another
/// layer's runs are not in them. **Mutation:** dropping the clamp returns the whole run; reading the wrong layer
/// index returns `[]` or the other layer's runs.
@Test @MainActor func aLayersRunsReadBackClippedToTheRange() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA))), b = d.register(CodeStyle(foreground: fg(hueB)))
    d.setHighlights([CodeStyleRun(range: 0..<3, style: a), CodeStyleRun(range: 10..<20, style: b)],
                    in: 0..<buffer.utf8Count, layer: .semantic, asOf: buffer.version)
    d.setHighlights([CodeStyleRun(range: 1..<2, style: b)], in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
    let all = d.highlights(in: 0..<buffer.utf8Count, layer: .semantic)
    #expect(all.map(\.range) == [0..<3, 10..<20])
    #expect(all.map(\.style) == [a, b])
    let clipped = d.highlights(in: 2..<15, layer: .semantic)
    #expect(clipped.map(\.range) == [2..<3, 10..<15])
    #expect(d.highlights(in: 3..<10, layer: .semantic).isEmpty, "the gap holds no run")
    #expect(d.highlights(in: 0..<buffer.utf8Count, layer: .syntax).map(\.range) == [1..<2])
    #expect(d.style(clipped[0].style).foreground == fg(hueA), "the run's id resolves to its style")
}

/// 2 — an empty layer, an empty range and a range past the text read `[]`.
/// **Mutation:** returning the tree's unstyled `.unknown` stretches as runs makes the first fail.
@Test @MainActor func anEmptyLayerReadsEmpty() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    #expect(d.highlights(in: 0..<buffer.utf8Count, layer: .diagnostics).isEmpty)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    d.setHighlights([CodeStyleRun(range: 0..<3, style: a)], in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
    #expect(d.highlights(in: 5..<5, layer: .syntax).isEmpty)
    #expect(d.highlights(in: 100_000..<200_000, layer: .syntax).isEmpty)
    #expect(d.highlights(in: 0..<buffer.utf8Count, layer: .semantic).isEmpty, "another layer stays empty")
    #expect(d.paintedRuns(in: 0..<0).isEmpty)
}

/// 3 — runs follow an edit above them, as paint sees them. **Mutation:** reading without `sync()` leaves the
/// runs at their old offsets.
@Test @MainActor func runsFollowAnEditAboveThem() throws {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    d.setHighlights([CodeStyleRun(range: 50..<55, style: a)], in: 0..<buffer.utf8Count, layer: .semantic, asOf: buffer.version)
    _ = try buffer.replace(0..<0, with: "XYZ")
    #expect(d.highlights(in: 0..<buffer.utf8Count, layer: .semantic).map(\.range) == [53..<58])
    #expect(d.paintedRuns(in: 0..<buffer.utf8Count).map(\.range) == [53..<58])
}

/// 4 — the painted accessor agrees with the frame: two layers overlap (`semantic` over `syntax`), a diagnostics
/// underline crosses both, and the glyphs the window draws carry the colours `paintedRuns` reports.
/// **Mutation:** merging the layers in descending order, or ignoring the underline, fails the run list; a
/// separate re-implementation that drifts from `stylingOfLine` fails the glyph counts.
@Test @MainActor func thePaintedAccessorAgreesWithTheFrame() throws {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    let b = d.register(CodeStyle(foreground: fg(hueB)))
    let wave = CodeUnderline.wavy(Color(red: 0.9, green: 0.1, blue: 0.2))
    let squiggle = d.register(CodeStyle(underline: wave))
    let v = buffer.version, n = buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 0..<10, style: a)], in: 0..<n, layer: .syntax, asOf: v)
    d.setHighlights([CodeStyleRun(range: 4..<7, style: b)], in: 0..<n, layer: .semantic, asOf: v)
    d.setHighlights([CodeStyleRun(range: 2..<8, style: squiggle)], in: 0..<n, layer: .diagnostics, asOf: v)
    let painted = d.paintedRuns(in: 0..<20)
    let colorA = CodeStyle(foreground: fg(hueA)), colorB = CodeStyle(foreground: fg(hueB))
    #expect(painted == [
        CodePaintedRun(range: 0..<2, style: colorA),
        CodePaintedRun(range: 2..<4, style: CodeStyle(foreground: fg(hueA), underline: wave)),
        CodePaintedRun(range: 4..<7, style: CodeStyle(foreground: fg(hueB), underline: wave)),
        CodePaintedRun(range: 7..<8, style: CodeStyle(foreground: fg(hueA), underline: wave)),
        CodePaintedRun(range: 8..<10, style: colorA),
    ], "\(painted)")
    #expect(d.paintedRuns(in: 3..<5).map(\.range) == [3..<4, 4..<5], "clipped to the range")
    _ = colorB

    let window = try codeWindow(buffer: buffer, decorations: d)
    window.window.setNeedsRedraw(); window.tick()
    let drawnA = window.scene.glyphs.filter { abs($0.color.h - Float(hueA)) < 0.001 }.count
    let drawnB = window.scene.glyphs.filter { abs($0.color.h - Float(hueB)) < 0.001 }.count
    let wantA = painted.filter { $0.style.foreground == fg(hueA) }.reduce(0) { $0 + $1.range.count }
    let wantB = painted.filter { $0.style.foreground == fg(hueB) }.reduce(0) { $0 + $1.range.count }
    #expect(wantA == 7 && wantB == 3)
    #expect(drawnA == wantA, "painted glyphs of the first colour: \(drawnA)")
    #expect(drawnB == wantB, "painted glyphs of the second colour: \(drawnB)")
}

/// 5 — a background run paints as a background of the painted style, and a read of an unstyled buffer is `[]`
/// without computing any line styling. **Mutation:** the accessor computing styling when no layer has runs
/// raises `stylingComputations`.
@Test @MainActor func backgroundsReadBackAndAnUnstyledBufferCostsNothing() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    #expect(d.paintedRuns(in: 0..<buffer.utf8Count).isEmpty)
    #expect(d.stylingComputations == 0)
    let tint = Color(red: 1, green: 1, blue: 0).opacity(0.3)
    let s = d.register(CodeStyle(background: tint))
    d.setHighlights([CodeStyleRun(range: 3..<6, style: s)], in: 0..<buffer.utf8Count, layer: .annotations, asOf: buffer.version)
    #expect(d.paintedRuns(in: 0..<buffer.utf8Count) == [CodePaintedRun(range: 3..<6, style: CodeStyle(background: tint))])
}
