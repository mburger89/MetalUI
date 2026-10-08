import CoreText
import Foundation
import Testing
import MetalUIScene
import MetalUITextSystem
@testable import MetalUIPortableText
@testable import MetalUIText

// Rich text, lane 1 (ruling `RT-H` item 5, spec test 1.10): the CoreText
// styled path is the oracle for the portable one. The three test faces are
// registered with CoreText for the process and with the portable resolver;
// each corpus case — mixed sizes and faces, kerning, tracking, baseline
// offsets, wraps, Latin and Arabic bidi, line limits — is laid out by both
// systems from the same font files at scales 1 and 2. Glyphs (key, pixel,
// baseline row, run) must be equal exactly; line boxes and segments within
// 1e-3 pt (the CFF face's metrics differ from CoreText's by up to 6.4e-5 pt,
// record §31).

private let styledFontsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts")
private let styledFaceFiles = ["NotoSans-Regular.ttf", "NotoSansArabic-Regular.ttf", "SourceSans3-Regular.otf"]

/// One run of a corpus case, by family.
private struct Piece {
    let string: String, family: String, size: Double
    var kerning = 0.0, tracking = 0.0, offset = 0.0
}

private func n(_ s: String, _ size: Double = 13, k: Double = 0, t: Double = 0, o: Double = 0) -> Piece {
    Piece(string: s, family: "Noto Sans", size: size, kerning: k, tracking: t, offset: o)
}
private func src(_ s: String, _ size: Double = 13, k: Double = 0, t: Double = 0, o: Double = 0) -> Piece {
    Piece(string: s, family: "Source Sans 3", size: size, kerning: k, tracking: t, offset: o)
}
private func ar(_ s: String, _ size: Double = 13) -> Piece {
    Piece(string: s, family: "Noto Sans Arabic", size: size)
}

private let styledCorpus: [[Piece]] = [
    [n("Hello "), src("World", 17), n(" again and again")],
    [n("AV", k: 2), n("AVA To"), src(" Ty", k: 1)],
    [n("office ", t: 3), n("office"), src(" fi", t: 2)],
    [n("x"), n("2", 9, o: 4), n(" + y"), n("i", 9, o: -3)],
    [n("abc "), ar("مرحبا بالعالم"), n(" def")],
    [n("The quick ", 11), src("brown fox", 26), n(" jumps over the lazy dog.", 11, k: 0.5)],
    [n("Ready\n"), src("Set", 17), n("\nGo", o: 2)],
]
private let styledWidths: [Double?] = [nil, 60, 120]
private let styledOptions = [
    TextLayoutOptions(),
    TextLayoutOptions(maxLines: 2, truncation: .tail),
    TextLayoutOptions(maxLines: 1, truncation: .head),
    TextLayoutOptions(maxLines: 1, truncation: .middle),
    TextLayoutOptions(alignment: .center),
]

@MainActor
private func build(_ pieces: [Piece], _ system: any TextSystem) -> StyledText {
    StyledText(pieces.map(\.string).joined(), runs: pieces.map { piece in
        StyledTextRun(length: piece.string.utf16.count, style: TextRunStyle(
            font: system.resolveFont(FontDescriptor(family: piece.family, size: piece.size)),
            kerning: piece.kerning, tracking: piece.tracking, baselineOffset: piece.offset))
    })
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-3 }

private func differences(_ apple: StyledTextLayout, _ portable: StyledTextLayout) -> [String] {
    var found: [String] = []
    if apple.glyphs != portable.glyphs {
        let first = zip(apple.glyphs, portable.glyphs).enumerated().first { $0.element.0 != $0.element.1 }
        found.append("glyphs \(apple.glyphs.count) vs \(portable.glyphs.count), first difference at "
                     + "\(first.map { "\($0.offset): \($0.element.0) vs \($0.element.1)" } ?? "the end")")
    }
    let a = apple.measurement, p = portable.measurement
    if !close(a.widestLine, p.widestLine) || !close(a.totalHeight, p.totalHeight) || a.lines.count != p.lines.count {
        found.append("measurement \(a.widestLine)×\(a.totalHeight) (\(a.lines.count)) vs "
                     + "\(p.widestLine)×\(p.totalHeight) (\(p.lines.count))")
    }
    for (index, (x, y)) in zip(a.lines, p.lines).enumerated()
    where x.range != y.range || !close(x.top, y.top) || !close(x.height, y.height) || !close(x.baseline, y.baseline)
        || !close(x.width, y.width) || !close(x.visibleMinX, y.visibleMinX) || !close(x.visibleMaxX, y.visibleMaxX)
        || !close(x.offsetX, y.offsetX) {
        found.append("line \(index): \(x) vs \(y)")
    }
    if apple.segments.count != portable.segments.count
        || zip(apple.segments, portable.segments).contains(where: {
            $0.run != $1.run || $0.line != $1.line || !close($0.minX, $1.minX) || !close($0.maxX, $1.maxX)
                || !close($0.baseline, $1.baseline) }) {
        found.append("segments \(apple.segments) vs \(portable.segments)")
    }
    return found
}

/// **1.10** (`RT-H` item 5). Every styled corpus case places the same glyphs,
/// line boxes and segments through the portable system as through the
/// CoreText one, at scales 1 and 2. Mutation: portable `shapeCascading`
/// chooses the covering face from run 0's font for every unit.
@MainActor
@Test func everyStyledCorpusCasePlacesTheSameGlyphsAsTheApplePath() throws {
    let urls = styledFaceFiles.map { styledFontsDirectory.appendingPathComponent($0) }
    for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    defer { for url in urls { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) } }
    let resolver = try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: urls[0])))
    try resolver.register([UInt8](Data(contentsOf: urls[1])))
    try resolver.register([UInt8](Data(contentsOf: urls[2])))
    let apple = CoreTextTextSystem(), portable = PortableTextSystem(resolver: resolver)
    for family in ["Noto Sans", "Noto Sans Arabic", "Source Sans 3"] {
        let a = apple.resolveFont(FontDescriptor(family: family, size: 13))
        let p = portable.resolveFont(FontDescriptor(family: family, size: 13))
        try #require(a == p, "set up: \(family) resolves to one face on both systems (\(a) vs \(p))")
    }
    var cases = 0, failures: [String] = []
    for pieces in styledCorpus {
        let appleText = build(pieces, apple), portableText = build(pieces, portable)
        try #require(appleText == portableText)
        for width in styledWidths {
            for options in styledOptions {
                for scale: Float in [1, 2] {
                    cases += 1
                    let origin = (x: 3.3, y: 7.6)
                    let a = apple.layOut(appleText, wrappingAt: width, options: options, origin: origin, scaleFactor: scale)
                    let p = portable.layOut(portableText, wrappingAt: width, options: options, origin: origin,
                                            scaleFactor: scale)
                    if a.glyphs.isEmpty { failures.append("\(appleText.string.debugDescription): CoreText drew nothing") }
                    for difference in differences(a, p) {
                        failures.append("\(appleText.string.debugDescription) w=\(String(describing: width)) "
                                        + "\(options) x\(scale): \(difference)")
                    }
                }
            }
        }
    }
    try #require(cases == styledCorpus.count * styledWidths.count * styledOptions.count * 2)
    #expect(failures.isEmpty, Comment(rawValue: "\(failures.count) of \(cases) cases differ:\n"
                                      + failures.prefix(12).joined(separator: "\n")))
}
