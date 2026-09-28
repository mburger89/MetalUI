import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText
import MetalUITextSystem

// TE-C item 3, TE-I, TE-T: a line limit's truncation on the portable path
// against MetalUI's Apple path, whose truncated line is CoreText's own
// `CTLineCreateTruncatedLine` (a `…` token in the resolved font). Same font
// files on both sides; every case compares each laid-out line's source range
// and advance, and every glyph's face, id, device pixel, subpixel variant and
// baseline — the kept string, its width and where it is drawn.
//
// The corpus: Latin with kerning pairs, ligatures and leading/trailing spaces
// (Noto Sans, glyf; Source Sans 3, CFF), combining marks both precomposed and
// stacked, CJK (the system's Hiragino Sans GB, macOS only like the rest of
// this file), and Arabic (Noto Sans Arabic, with Noto Sans as its cascade on
// both sides, which draws the token Noto Sans Arabic lacks) — at two sizes,
// widths from narrower than the token to wider than the text, one and two
// kept lines, in all three modes, the alignment cycling through all three.
// Hard-break strings reach TE-T's paragraph rule (probe
// `swiftui-truncation-edges.swift` E1, E2, E4).

let truncationLatin = [
    "The quick brown fox jumps over the lazy dog.",
    "Affix the fluffy waffle: AV To Ty LT jig!",
    "   leading and trailing   ",
    "Alpha beta gamma delta epsilon zeta eta theta",
    "Ready\nSet\nGo",
    "Alpha beta gamma\ndelta epsilon zeta eta theta",
    "Alpha beta gamma delta epsilon zeta eta theta\nmore",
]
let truncationMarks = ["e\u{301}te\u{301} cafe\u{301} na\u{303}o e\u{302}\u{323}x q\u{301}\u{302}\u{303}z end"]
let truncationCJK = ["日本語のテキストを切り詰める。中文字符串也一样。", "ABC 漢字 def ghi 仮名かな"]
let truncationArabic = ["مرحبا بالعالم العربي", "مَرْحَبًا بالعالم يا صديقي"]
let truncationSizes: [Double] = [13, 17]
let truncationWidths: [Double?] = [nil, 4, 8, 10.5] + stride(from: 12.0, through: 222, by: 7).map { $0 }
let truncationModes: [TextTruncation] = [.tail, .head, .middle]
let truncationAlignments: [TextLineAlignment] = [.leading, .center, .trailing]
let hiraginoPath = "/System/Library/Fonts/Hiragino Sans GB.ttc"

/// One font on both sides: how to make it at a size.
struct TruncationFont {
    let name: String
    let apple: (Double) throws -> ResolvedFont
    let portable: (Double) throws -> PortableFont
}

func truncationFonts() throws -> [(TruncationFont, [String])] {
    let noto = try OracleFont(notoSans), source = try OracleFont(sourceSans)
    let hiraginoData = try Data(contentsOf: URL(fileURLWithPath: hiraginoPath))
    let hiraginoBytes = [UInt8](hiraginoData)
    let hiraginoName = try PortableFont(data: hiraginoBytes, size: 13).key.postScriptName
    let hiraginoDescriptor = try #require(
        (CTFontManagerCreateFontDescriptorsFromData(hiraginoData as CFData) as? [CTFontDescriptor])?.first {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == hiraginoName
        }, "no CoreText face named \(hiraginoName) in \(hiraginoPath)")
    func arabicApple(_ size: Double) throws -> ResolvedFont {
        func descriptor(_ file: String) throws -> CTFontDescriptor {
            try #require((CTFontManagerCreateFontDescriptorsFromData(Data(fontBytes(file)) as CFData)
                          as? [CTFontDescriptor])?.first)
        }
        let cascaded = CTFontDescriptorCreateCopyWithAttributes(try descriptor(notoSansArabic), [
            kCTFontCascadeListAttribute: [try descriptor(notoSans)]] as CFDictionary)
        return ResolvedFont(ctFont: CTFontCreateWithFontDescriptor(cascaded, CGFloat(size), nil))
    }
    func arabicPortable(_ size: Double) throws -> PortableFont {
        let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSansArabic))
        try resolver.register(fontBytes(notoSans))
        return try resolver.resolve(family: nil, size: size)
    }
    return [
        (TruncationFont(name: notoSans, apple: { noto.apple(size: $0) }, portable: { try noto.portable(size: $0) }),
         truncationLatin + truncationMarks),
        (TruncationFont(name: sourceSans, apple: { source.apple(size: $0) },
                        portable: { try source.portable(size: $0) }), truncationLatin),
        (TruncationFont(name: hiraginoName,
                        apple: { ResolvedFont(ctFont: CTFontCreateWithFontDescriptor(hiraginoDescriptor, CGFloat($0), nil)) },
                        portable: { try PortableFont(data: hiraginoBytes, size: $0) }), truncationCJK),
        (TruncationFont(name: notoSansArabic, apple: arabicApple, portable: arabicPortable), truncationArabic),
    ]
}

struct TruncatedLayout: Equatable {
    let lines: [Range<Int>]
    let advances: [Double]
    let glyphs: [FallbackPlaced]

    func agrees(with other: TruncatedLayout) -> Bool {
        lines == other.lines && glyphs == other.glyphs && advances.count == other.advances.count
            && zip(advances, other.advances).allSatisfy { abs($0 - $1) <= 1e-9 }
    }
    var summary: String {
        "lines \(lines.map { "\($0.lowerBound)..<\($0.upperBound)" }) advances "
            + advances.map { String(format: "%.3f", $0) }.joined(separator: " ")
            + " glyphs \(glyphs.map(\.description).joined(separator: " "))"
    }
}

@MainActor
func appleTruncatedLayout(_ text: String, font: ResolvedFont, width: Double?,
                          options: TextLayoutOptions) -> TruncatedLayout {
    let shaped = Shaper.shape(text, font: font, wrappingAt: width, options: options)
    return TruncatedLayout(
        lines: shaped.lines.map(\.sourceRange), advances: shaped.lines.map(\.advance),
        glyphs: shaped.placedGlyphs(at: (3.3, 7.6), font: font, scaleFactor: 2).map {
            FallbackPlaced(face: $0.key.font.postScriptName, id: $0.key.glyph, pixelX: $0.pixelX,
                           variant: $0.key.subpixelVariant, baselineY: $0.baselineY)
        })
}

func portableTruncatedLayout(_ text: String, font: PortableFont, width: Double?,
                             options: TextLayoutOptions) throws -> TruncatedLayout {
    let (lines, placements) = try PortableText.placements(text, font: font, origin: (3.3, 7.6), wrappingAt: width,
                                                         options: options, scaleFactor: 2)
    return TruncatedLayout(
        lines: lines.map(\.line.range), advances: lines.map(\.line.advance),
        glyphs: placements.map {
            let split = GlyphImage.subpixelPlacement(forDeviceX: $0.deviceX)
            return FallbackPlaced(face: $0.font.key.postScriptName, id: $0.id, pixelX: split.pixelX,
                                  variant: split.variant, baselineY: $0.baselineY)
        })
}

struct TruncationDifference: CustomStringConvertible {
    let font: String, size: Double, width: Double?, options: TextLayoutOptions, text: String
    let apple: TruncatedLayout, portable: TruncatedLayout
    var description: String {
        "\(font) \(size)pt w=\(width.map { "\($0)" } ?? "nil") \(options.truncation) "
            + "maxLines=\(options.maxLines.map(String.init) ?? "nil") \(options.alignment) \(text.debugDescription)\n"
            + "  apple    \(apple.summary)\n  portable \(portable.summary)"
    }
}

@MainActor
func truncationDifferences() throws -> (cases: Int, truncated: Int, differences: [TruncationDifference]) {
    var cases = 0, truncated = 0
    var differences: [TruncationDifference] = []
    for (font, strings) in try truncationFonts() {
        for size in truncationSizes {
            let apple = try font.apple(size), portable = try font.portable(size)
            for width in truncationWidths {
                for text in strings {
                    for maxLines in [1, 2] {
                        for mode in truncationModes {
                            let options = TextLayoutOptions(
                                maxLines: maxLines, truncation: mode,
                                alignment: truncationAlignments[cases % truncationAlignments.count])
                            cases += 1
                            let a = appleTruncatedLayout(text, font: apple, width: width, options: options)
                            let p = try portableTruncatedLayout(text, font: portable, width: width, options: options)
                            let untruncated = Shaper.shape(text, font: apple, wrappingAt: width).lines.count
                            if untruncated > maxLines, width != nil { truncated += 1 }
                            if !a.agrees(with: p) {
                                differences.append(TruncationDifference(
                                    font: font.name, size: size, width: width, options: options, text: text,
                                    apple: a, portable: p))
                            }
                        }
                    }
                }
            }
        }
    }
    return (cases, truncated, differences)
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_TRUNCATION_MEASURE"] == "1"))
func measureTruncationDifferences() throws {
    let (cases, truncated, differences) = try truncationDifferences()
    print("TE-C truncation cases=\(cases) truncated=\(truncated) differences=\(differences.count)")
    var byKey: [String: Int] = [:]
    for d in differences { byKey["\(d.font) \(d.options.truncation) \(d.text.debugDescription)", default: 0] += 1 }
    for (key, count) in byKey.sorted(by: { $0.key < $1.key }) { print("BYKEY \(count) \(key)") }
    let focus = ProcessInfo.processInfo.environment["METALUI_TRUNCATION_FOCUS"]
    for d in differences.filter({ d in focus.map { "\(d)".contains($0) } ?? true }).prefix(25) { print("DIFF \(d)") }
}

/// 1.5. Every corpus case lays out, truncates and places exactly as the
/// Apple path does — Latin, combining marks and CJK in all three modes, and
/// Arabic in tail mode, the default — except the one class ruling TE-U names
/// and pins: an Arabic (right-to-left) suffix in head or middle mode, where
/// CoreText sometimes keeps one more cluster at the suffix's edge than the
/// share rule. Measured 2026-09-28 (`METALUI_TRUNCATION_MEASURE=1`): 7,980
/// cases, 6,093 truncated, 38 differing, every one of them that class.
@MainActor
@Test func thePortableTruncationKeepsCoreTextsStringInEveryMode() throws {
    let (cases, truncated, differences) = try truncationDifferences()
    let strings = 2 * truncationLatin.count + truncationMarks.count + truncationCJK.count + truncationArabic.count
    try #require(cases == strings * truncationSizes.count * truncationWidths.count * 2 * truncationModes.count)
    #expect(truncated > cases / 3, "the corpus must truncate: \(truncated) of \(cases)")
    let unruled = differences.filter { !($0.font == notoSansArabic && $0.options.truncation != .tail) }
    #expect(unruled.isEmpty, "\(unruled.count) of \(cases) differ outside TE-U's class; first: \(unruled.first.map { "\($0)" } ?? "")")
    #expect(differences.count == 38, "TE-U pins 38 right-to-left head/middle differences; measured \(differences.count)")
}

/// TE-U's pin of both answers, one case: "مَرْحَبًا بالعالم يا صديقي" at 13 pt,
/// head mode, width 26. CoreText keeps "قي" (the last two letters, 16.003 pt,
/// with the 10.283 pt token over the width by 0.286); the portable path keeps
/// "ي" alone (9.568 pt), the longest suffix that fits by the share rule.
@MainActor
@Test func aRightToLeftHeadTruncationKeepsOneClusterLessThanCoreText() throws {
    let arabic = try truncationFonts().first { $0.0.name == notoSansArabic }!.0
    let options = TextLayoutOptions(maxLines: 1, truncation: .head)
    let text = truncationArabic[1]
    let apple = appleTruncatedLayout(text, font: try arabic.apple(13), width: 26, options: options)
    let portable = try portableTruncatedLayout(text, font: try arabic.portable(13), width: 26, options: options)
    let ellipsis = FallbackPlaced(face: "NotoSans-Regular", id: 526, pixelX: 0, variant: 0, baselineY: 0).id
    #expect(apple.glyphs.map(\.id) == [318, 104, 287, 52, ellipsis], "CoreText: \(apple.summary)")
    #expect(portable.glyphs.map(\.id) == [318, 104, ellipsis], "portable: \(portable.summary)")
    #expect(abs(apple.advances[0] - 26.286) < 0.001 && abs(portable.advances[0] - 19.851) < 0.001)
}

/// The corpus reaches what the rules are for, on the Apple side, so the
/// agreement above is not about nothing: each mode drops text and draws the
/// token, a narrow width is narrower than the token, and the Arabic token
/// comes from the cascade.
@MainActor
@Test func theTruncationCorpusReachesEveryRule() throws {
    let noto = try OracleFont(notoSans).apple(size: 13)
    let text = "The quick brown fox jumps over the lazy dog."
    let ellipsis = CTFontGetGlyphWithName(noto.ctFont, "ellipsis" as CFString)
    for mode in truncationModes {
        let shaped = Shaper.shape(text, font: noto, wrappingAt: 60, options: TextLayoutOptions(maxLines: 1, truncation: mode))
        let glyphs = shaped.placedGlyphs(at: (0, 0), font: noto, scaleFactor: 1)
        #expect(shaped.lines.count == 1, "\(mode)")
        #expect(glyphs.contains { $0.key.glyph == ellipsis }, "\(mode) draws the token")
        #expect(glyphs.count < 15, "\(mode) drops text")
    }
    let arabic = try truncationFonts().first { $0.0.name == notoSansArabic }!.0
    let placed = Shaper.shape(truncationArabic[0], font: try arabic.apple(13), wrappingAt: 40,
                              options: TextLayoutOptions(maxLines: 1))
        .placedGlyphs(at: (0, 0), font: try arabic.apple(13), scaleFactor: 1)
    #expect(placed.contains { $0.key.font.postScriptName == "NotoSans-Regular" }, "the Arabic token is Noto Sans's")
}
