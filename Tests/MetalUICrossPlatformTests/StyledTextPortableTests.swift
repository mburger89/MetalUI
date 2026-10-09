import Foundation
import Testing
import MetalUIPortableText
import MetalUITextSystem

// Rich text, lane 1 — the styled seam on every platform (rulings `RT-F`,
// `RT-G`; spec tests 1.16, 1.17). Runs on Linux and Windows CI too: the
// portable system is what those platforms draw.

private let fontsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts")

private func key(_ name: String, _ size: Double = 13) -> FontKey {
    FontKey(resolvedPostScriptName: name, size: size, variations: [],
            matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
}

/// **1.16** (`RT-F` item 1; `C17`). `StyledText` drops zero-length runs and
/// merges equal neighbours; an empty string keeps exactly its first run's
/// style. Mutation: skip the merge.
@Test func zeroLengthRunsAreDroppedAndEqualNeighboursMerge() {
    let a = TextRunStyle(font: key("A")), b = TextRunStyle(font: key("B")), c = TextRunStyle(font: key("C"))
    let text = StyledText("abcdef", runs: [StyledTextRun(length: 0, style: c), StyledTextRun(length: 2, style: a),
                                           StyledTextRun(length: 1, style: a), StyledTextRun(length: 0, style: b),
                                           StyledTextRun(length: 3, style: b)])
    #expect(text.runs == [StyledTextRun(length: 3, style: a), StyledTextRun(length: 3, style: b)])
    let separated = StyledText("abc", runs: [StyledTextRun(length: 1, style: a), StyledTextRun(length: 0, style: b),
                                             StyledTextRun(length: 2, style: a)])
    #expect(separated.runs == [StyledTextRun(length: 3, style: a)], "a dropped run's neighbours merge")
    let empty = StyledText("", runs: [StyledTextRun(length: 0, style: b), StyledTextRun(length: 0, style: a)])
    #expect(empty.runs == [StyledTextRun(length: 0, style: b)])
    #expect(StyledText("x", style: c).runs == [StyledTextRun(length: 1, style: c)])
}

/// **1.17** (`RT-G` items 1–2). The portable system lays a styled text out on
/// every platform: Noto Sans 10 + 30 on one line is the 30-point line (height
/// and baseline from `PortableFontMetrics`), and a run raised 5 points grows a
/// 16-point line by 5 with its glyph 5 rows up. Mutation: sum ascents.
@MainActor
@Test func thePortableSystemLaysOutAStyledTextOnEveryPlatform() throws {
    let data = [UInt8](try Data(contentsOf: fontsDirectory.appendingPathComponent("NotoSans-Regular.ttf")))
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: data))
    let small = system.resolveFont(FontDescriptor(size: 10)), large = system.resolveFont(FontDescriptor(size: 30))
    let m30 = try PortableFont(data: data, size: 30).metrics
    let mixed = StyledText("a B", runs: [StyledTextRun(length: 2, style: TextRunStyle(font: small)),
                                         StyledTextRun(length: 1, style: TextRunStyle(font: large))])
    let measured = system.measure(mixed, wrappingAt: nil, options: TextLayoutOptions())
    #expect(measured.lines.map(\.height) == [m30.lineHeight])
    #expect(measured.lines.first?.baseline == m30.ascent)
    #expect(measured.totalHeight == m30.lineHeight)

    let body = system.resolveFont(FontDescriptor(size: 16))
    let m16 = try PortableFont(data: data, size: 16).metrics
    let raised = StyledText("ab", runs: [StyledTextRun(length: 1, style: TextRunStyle(font: body)),
                                         StyledTextRun(length: 1, style: TextRunStyle(font: body, baselineOffset: 5))])
    let layout = system.layOut(raised, wrappingAt: nil, options: TextLayoutOptions(), origin: (x: 0, y: 0),
                               scaleFactor: 1)
    let box = try #require(layout.measurement.lines.first)
    #expect(box.height == m16.lineHeight + 5)
    #expect(box.baseline == m16.ascent + 5)
    try #require(layout.glyphs.count == 2)
    #expect(layout.glyphs[1].glyph.baselineY == layout.glyphs[0].glyph.baselineY - 5)
}
