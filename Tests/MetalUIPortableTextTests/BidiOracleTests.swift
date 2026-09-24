import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// BD-A…BD-C: bidi and script itemization against CoreText. Noto Sans is the
// requested face and Noto Sans Arabic its fallback — on the Apple side through
// `kCTFontCascadeListAttribute`, on the portable side through the resolver —
// over paragraphs mixing Latin and Arabic in both directions, wrapped.

let bidiStrings = [
    "Hello مرحبا world",
    "مرحبا بالعالم",
    "مرحبا Hello بالعالم",
    "The word سلام means peace.",
    "سلام (peace) والسلام",
    "Numbers ١٢٣ and 456 in text",
    "العدد 123 في النص",
    "Line one مرحبا\nسطر ثاني with English",
    "أ ب ت ث ج ح خ د ذ ر ز س ش ص ض ط ظ ع غ ف ق ك ل م ن ه و ي",
    "left, then عربي, then left again, then عربي آخر.",
]

@MainActor
func appleBidiFont(size: Double) throws -> ResolvedFont {
    func descriptor(_ file: String) throws -> CTFontDescriptor {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts").appendingPathComponent(file)
        return try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
    }
    let cascaded = CTFontDescriptorCreateCopyWithAttributes(try descriptor("NotoSans-Regular.ttf"), [
        kCTFontCascadeListAttribute: [try descriptor("NotoSansArabic-Regular.ttf")]] as CFDictionary)
    return ResolvedFont(ctFont: CTFontCreateWithFontDescriptor(cascaded, CGFloat(size), nil))
}

func portableBidiFont(size: Double) throws -> PortableFont {
    let resolver = try PortableFontResolver(defaultFont: fontBytes("NotoSans-Regular.ttf"))
    try resolver.register(fontBytes("NotoSansArabic-Regular.ttf"))
    return try resolver.resolve(family: nil, size: size)
}

@MainActor
func bidiDifferences() throws -> (cases: Int, rtlGlyphs: Int, lineDiffs: [String], placementDiffs: [String]) {
    var cases = 0, rtlGlyphs = 0
    var lineDiffs: [String] = [], placementDiffs: [String] = []
    for size in [13.0, 17] {
        let apple = try appleBidiFont(size: size), portable = try portableBidiFont(size: size)
        for width in [nil] + stride(from: 40.0, through: 320, by: 20).map({ Optional($0) }) {
            for text in bidiStrings {
                cases += 1
                let label = "\(size)pt w=\(width.map { "\($0)" } ?? "nil") \(text.debugDescription)"
                let aLines = appleLines(text, font: apple, width: width).map(\.0)
                let pLines = try PortableText.lines(text, font: portable, wrappingAt: width).map(\.range)
                if aLines != pLines { lineDiffs.append("\(label): apple \(aLines) portable \(pLines)"); continue }
                let a = Shaper.shape(text, font: apple, wrappingAt: width)
                    .placedGlyphs(at: (3.3, 7.6), font: apple, scaleFactor: 2)
                    .map { FallbackPlaced(face: $0.key.font.postScriptName, id: $0.key.glyph, pixelX: $0.pixelX,
                                          variant: $0.key.subpixelVariant, baselineY: $0.baselineY) }
                let p = try PortableText.placements(text, font: portable, origin: (3.3, 7.6), wrappingAt: width,
                                                    scaleFactor: 2).placements.map {
                    let split = GlyphImage.subpixelPlacement(forDeviceX: $0.deviceX)
                    return FallbackPlaced(face: $0.font.key.postScriptName, id: $0.id, pixelX: split.pixelX,
                                          variant: split.variant, baselineY: $0.baselineY)
                }
                rtlGlyphs += a.filter { $0.face == "NotoSansArabic-Regular" }.count
                if a != p {
                    let i = (0..<min(a.count, p.count)).first { a[$0] != p[$0] } ?? min(a.count, p.count)
                    placementDiffs.append("\(label): \(a.count) vs \(p.count); at \(i): apple \(a[max(0, i-1)..<min(a.count, i+3)]) portable \(p[max(0, i-1)..<min(p.count, i+3)])")
                }
            }
        }
    }
    return (cases, rtlGlyphs, lineDiffs, placementDiffs)
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_BIDI_MEASURE"] == "1"))
func measureBidiDifferences() throws {
    let (cases, rtl, lines, placements) = try bidiDifferences()
    print("BIDI cases=\(cases) arabicGlyphs=\(rtl) lineDiffs=\(lines.count) placementDiffs=\(placements.count)")
    for line in lines.prefix(12) { print("BIDI LINES \(line)") }
    for line in placements.prefix(20) { print("BIDI PLACE \(line)") }
}

/// Measured: 320 cases, 4,608 Arabic glyphs, line boundaries and every glyph's
/// face, id, device pixel, variant and baseline equal. Three rules got there:
/// UAX #9 visual order, a right-to-left line's trailing whitespace hung off
/// its left edge, and a line splitting lam-alef re-shaped (record §41).
@MainActor
@Test func bidiParagraphsPlaceEveryGlyphAsCoreTextDoes() throws {
    let (cases, arabicGlyphs, lines, placements) = try bidiDifferences()
    try #require(cases == 320)
    #expect(arabicGlyphs > 3000)
    #expect(lines.isEmpty, "\(lines.first ?? "")")
    #expect(placements.isEmpty, "\(placements.count) differ; first: \(placements.first ?? "")")
}

/// CoreText's two behaviours at a break between joined Arabic letters, both
/// measured (BD-C): a line starting with the alef of a split lam-alef shows it
/// unjoined (re-shaped), a line starting with a mim after lam keeps the joined
/// form (the paragraph's shaping).
@MainActor
@Test func aSplitLamAlefIsReshapedAndAnyOtherSplitJoinIsNot() throws {
    let portable = try portableBidiFont(size: 17)
    let apple = try appleBidiFont(size: 17)
    for (text, width, joinedAtStart) in [("سلام (peace) والسلام", 40.0, false), ("مرحبا بالعالم", 40.0, true)] {
        let laid = try PortableText.layOut(text, font: portable, wrappingAt: width)
        let last = try #require(laid.last)
        let firstUnit = last.line.range.lowerBound
        let alone = try PortableText.layOut(String(decoding: Array(text.utf16)[firstUnit...], as: UTF16.self),
                                            font: portable, wrappingAt: nil)
        let reshapedID = try #require(alone.first?.glyphs.last?.id)   // the logical first letter, drawn rightmost
        let drawnID = try #require(last.glyphs.last?.id)
        #expect((drawnID != reshapedID) == joinedAtStart, "\(text)")
        let appleLast = try #require(Shaper.shape(text, font: apple, wrappingAt: width)
            .placedGlyphs(at: (0, 0), font: apple, scaleFactor: 1).last)
        #expect(appleLast.key.glyph == drawnID, "\(text): CoreText drew \(appleLast.key.glyph)")
    }
}

/// The control: in logical order (no visual reordering) a right-to-left
/// paragraph with English inside differs from CoreText, so the equality above
/// is the bidi's doing. (A left-to-right paragraph holding one Arabic run would
/// not do: its runs are already in visual order, and HarfBuzz returns the
/// Arabic run's glyphs visually.)
@MainActor
@Test func logicalOrderDiffersFromCoreTextForMixedText() throws {
    let apple = try appleBidiFont(size: 13), portable = try portableBidiFont(size: 13)
    let text = "مرحبا Hello بالعالم"
    let a = Shaper.shape(text, font: apple, wrappingAt: nil).placedGlyphs(at: (0, 0), font: apple, scaleFactor: 1)
        .map(\.key.glyph)
    let logical = try PortableText.shapeCascading(text, font: portable).map(\.glyph.id)
    let visual = try PortableText.placements(text, font: portable, origin: (0, 0), wrappingAt: nil, scaleFactor: 1)
        .placements.map(\.id)
    #expect(a == visual)
    #expect(a != logical)
}
