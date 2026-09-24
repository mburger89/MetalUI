import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// Roadmap item 3 (rulings LB-L…): min- and max-content, and the unbreakable
// runs under them, against MetalUI's Apple path — the `CFStringTokenizer` walk
// (`appleUnbreakableRuns`, below), the min-content it gives
// (`appleMinContentWidth`) and `Shaper.shape(wrappingAt: nil).widestLine`.
//
// **The Apple arm's tokenizer is a test-local copy since stage 9** (`LR-FD`
// item 3): stage 9 deleted tokenizer min-content from production —
// `Shaper.unbreakableRuns` (`UnbreakableRuns.swift`) and
// `ShapingCache.minContentWidth` — and this oracle is the one caller that still
// needs CoreText's answer. The walk below is copied verbatim from
// `UnbreakableRuns.swift` at `b9a5d7f` (`unbreakableRuns(of:)` and
// `runs(walking:over:)`), less the two test counters stage 9 deleted with it;
// the min-content is `ShapingCache.minContentWidth`'s loop, less its memo. The
// oracle read the same agreement before and after the move
// (`measureContentSizeDifferences`'s output identical, record §51).

/// `string` split at every UAX #14 soft-wrap opportunity, with trailing
/// whitespace removed from each piece — CoreText's (`CFStringTokenizer`'s)
/// unbreakable runs. Verbatim from `appleUnbreakableRuns(of:)` at `b9a5d7f`,
/// less its `runCallCounter`/`tokenizerCreationCounter` bumps. A tokenizer per
/// call, `nil` locale.
private func appleUnbreakableRuns(of string: String) -> [String] {
    let cf = string as CFString
    let length = CFStringGetLength(cf)
    guard length > 0 else { return [] }
    guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cf, CFRangeMake(0, length),
            kCFStringTokenizerUnitLineBreak, nil)
    else { return [] }
    return appleRuns(walking: tokenizer, over: string)
}

/// The UAX #14 walk: every token `tokenizer` yields over `string`, trailing
/// whitespace trimmed, blank runs dropped. Verbatim from
/// `Shaper.runs(walking:over:)` at `b9a5d7f`.
private func appleRuns(walking tokenizer: CFStringTokenizer, over string: String) -> [String] {
    let utf16 = Array(string.utf16)
    var runs: [String] = []
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        var run = Substring(String(
            decoding: utf16[range.location ..< range.location + range.length],
            as: UTF16.self))
        while let last = run.last, last.isWhitespace { run = run.dropLast() }
        if !run.isEmpty { runs.append(String(run)) }
    }
    return runs
}

/// CoreText's min-content: the widest unbreakable run, each shaped on a line of
/// its own through `cache`. `ShapingCache.minContentWidth(_:font:)`'s miss
/// branch at `b9a5d7f`, verbatim less the memo.
@MainActor
private func appleMinContentWidth(_ string: String, font: ResolvedFont, cache: ShapingCache) -> Double {
    var width = 0.0
    for run in appleUnbreakableRuns(of: string) {
        width = max(width, cache.shaped(run, font: font, wrappingAt: nil).widestLine)
    }
    return width
}
//
// Measured first (`METALUI_CONTENT_MEASURE=1`, 2026-09-23, macOS 27.0,
// libunibreak 8.0): with no language, 2 of 35 strings' runs differed, and a
// probe over every ordered pair of 47 class samples, with and without a space
// between, differed in 347 of 4,418. libunibreak's own `"en"` tailoring
// (U+2018 and U+201C opening, U+201D closing) took that to 123, all small
// kana; its `-strict` suffix (CJ as NS) to **0** (LB-L). Thai still differs:
// CoreText breaks it with a dictionary and libunibreak has none (LB-M).
// Widths differ only for strings a bundled face cannot draw, which CoreText
// draws from a fallback font (roadmap item 11); the width oracle keeps the
// strings each face covers (LB-N).

let runStrings = wrapStrings + [
    "a bb supercalifragilistic dd",
    "well-known thing",
    "hello\nworld",
    "日本語のテキスト。句読点「かぎ」",
    "สวัสดีครับ ภาษาไทย",
    "مرحبا بالعالم",
    "👩\u{200D}💻 emoji 🇩🇪 flags",
    "a/b\\c|d e—f g–h (i) [j] {k}",
    "price: $1,234.56 — 50% off!",
    "ellipsis… and \u{2026} and ... too",
    "zero\u{200B}width\u{200B}space",
    "word\u{2060}joiner",
    "",
    "   leading and trailing   ",
    "http://a.b/c?d=e&f=g#h",
    "e.g. i.e. U.S.A.",
    "don't can't won't",
    "«quoted» „quoted“ “quoted”",
]

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_CONTENT_MEASURE"] == "1"))
@MainActor func measureContentSizeDifferences() throws {
    var runDiffs = 0
    for text in runStrings {
        let apple = appleUnbreakableRuns(of: text)
        let portable = PortableText.unbreakableRuns(of: text)
        if apple != portable {
            runDiffs += 1
            print("RUNS \(text.debugDescription)\n  apple    \(apple)\n  portable \(portable)")
        }
    }
    print("RUNS differing=\(runDiffs) of \(runStrings.count)")
    var minDiffs = 0, maxDiffs = 0, cases = 0
    for file in fontFiles {
        let font = try OracleFont(file)
        for size in wrapSizes {
            let cache = ShapingCache()
            for text in runStrings {
                cases += 1
                let appleMin = appleMinContentWidth(text, font: font.apple(size: size), cache: cache)
                let portableMin = try PortableText.minContentWidth(text, font: font.portable(size: size))
                if abs(appleMin - portableMin) > 1e-9 {
                    minDiffs += 1
                    print("MIN \(file) \(size) \(text.debugDescription): apple \(appleMin) portable \(portableMin)")
                }
                let appleMax = Shaper.shape(text, font: font.apple(size: size), wrappingAt: nil).widestLine
                let portableMax = try PortableText.maxContentWidth(text, font: font.portable(size: size))
                if abs(appleMax - portableMax) > 1e-9 {
                    maxDiffs += 1
                    print("MAX \(file) \(size) \(text.debugDescription): apple \(appleMax) portable \(portableMax)")
                }
            }
        }
    }
    print("SIZES cases=\(cases) minDiffs=\(minDiffs) maxDiffs=\(maxDiffs)")
}

/// One representative character per UAX #14 class, and every quotation
/// mark variant.
let classSamples: [(String, String)] = [
    ("AL", "a"), ("NU", "1"), ("SP", " "), ("BA", "-"), ("HY", "\u{2010}"), ("BB", "\u{B4}"), ("B2", "\u{2014}"),
    ("OP", "("), ("CP", ")"), ("CL", "}"), ("EX", "!"), ("IS", ","), ("IS.", "."), ("SY", "/"),
    ("PR", "$"), ("PO", "%"), ("NS", "\u{3005}"), ("ID", "日"), ("IN", "\u{2026}"), ("GL", "\u{A0}"),
    ("WJ", "\u{2060}"), ("ZW", "\u{200B}"), ("CM", "\u{301}"), ("ZWJ", "\u{200D}"), ("EB", "\u{1F466}"),
    ("EM", "\u{1F3FB}"), ("RI", "\u{1F1E9}"), ("HL", "\u{5D0}"), ("CJ", "\u{3041}"), ("AI", "\u{A7}"),
    ("QU\"", "\""), ("QU'", "'"), ("Pi“", "\u{201C}"), ("Pf”", "\u{201D}"), ("Pi‘", "\u{2018}"), ("Pf’", "\u{2019}"),
    ("Pi«", "\u{AB}"), ("Pf»", "\u{BB}"), ("Pi‹", "\u{2039}"), ("Pf›", "\u{203A}"), ("„", "\u{201E}"), ("‟", "\u{201F}"),
    ("⹂", "\u{2E42}"), ("OP「", "\u{300C}"), ("CL」", "\u{300D}"), ("OP‚", "\u{201A}"), ("BK", "\u{2028}"),
]

/// Every ordered pair of class samples, with and without a space between,
/// between two letters: 47 × 47 × 2 = 4,418 strings.
func classPairStrings() -> [String] {
    classSamples.flatMap { first in
        classSamples.flatMap { second in ["", " "].map { "x" + first.1 + $0 + second.1 + "y" } }
    }
}

/// LB-L: libunibreak under `"en-strict"` breaks every class pair exactly as
/// CoreText's tokenizer does.
@Test func everyClassPairBreaksAsCoreTextDoes() {
    let strings = classPairStrings()
    #expect(strings.count == 4_418)
    let differing = strings.filter { appleUnbreakableRuns(of: $0) != PortableText.unbreakableRuns(of: $0) }
    #expect(differing.isEmpty, "\(differing.count) differ; first \(differing.first.map { $0.debugDescription } ?? "")")
}

/// Thai is the one corpus script whose runs differ.
let dictionaryScriptStrings = runStrings.filter { $0.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) } }

@Test func everyCorpusStringButThaiSplitsIntoCoreTextsRuns() throws {
    try #require(dictionaryScriptStrings.count == 1)
    for text in runStrings where !dictionaryScriptStrings.contains(text) {
        #expect(PortableText.unbreakableRuns(of: text) == appleUnbreakableRuns(of: text), "\(text.debugDescription)")
    }
}

/// Pinned wrong on purpose (LB-M): CoreText breaks Thai between words from a
/// dictionary; libunibreak has no dictionary, so a Thai phrase is one run
/// between spaces. Reddens if either side changes.
@Test func thaiBreaksOnlyAtSpacesWhereCoreTextUsesADictionary() {
    let text = "สวัสดีครับ ภาษาไทย"
    #expect(PortableText.unbreakableRuns(of: text) == ["สวัสดีครับ", "ภาษาไทย"])
    #expect(appleUnbreakableRuns(of: text) == ["สวัสดี", "ครับ", "ภาษา", "ไทย"])
}

/// The English curly quotes LB-L tailors, wrapped: `lines` breaks where
/// CoreText's typesetter does at every width, not only where its tokenizer
/// does.
@Test func englishCurlyQuotesWrapAsCoreTextDoes() throws {
    let font = try OracleFont("NotoSans-Regular.ttf")
    for text in ["a‘ b ‘c’ d”e", "he said “no” then", "“Quoted,” she said, ‘and nested.’"] {
        for width in stride(from: 10.0, through: 150, by: 5) {
            #expect(appleLines(text, font: font.apple(size: 13), width: width).map(\.0)
                    == (try PortableText.lines(text, font: font.portable(size: 13), wrappingAt: width).map(\.range)),
                    "\(text) at \(width)")
        }
    }
}

/// Pinned wrong on purpose (LB-M): German-style quotes, where U+201C closes.
/// Here CoreText's **typesetter** breaks after `„hi“ ` at 45 pt although its
/// own tokenizer — and so libunibreak under LB-L — gives no opportunity there
/// (and at 120 pt it does not break after `„quoted“ ` in the longer string
/// even where that line would fit). A typesetter heuristic, not a class rule;
/// `lines` follows the tokenizer. Reddens if either side changes.
@Test func germanQuotesWrapWhereCoreTextsTypesetterLeavesItsTokenizer() throws {
    let font = try OracleFont("NotoSans-Regular.ttf")
    let text = "say „hi“ now"
    #expect(PortableText.unbreakableRuns(of: text) == appleUnbreakableRuns(of: text))
    #expect(appleLines(text, font: font.apple(size: 13), width: 45).map(\.0) == [0..<9, 9..<12])
    #expect(try PortableText.lines(text, font: font.portable(size: 13), wrappingAt: 45).map(\.range)
            == [0..<4, 4..<11, 11..<12])
}

/// Whether `face` has a glyph for every visible scalar of `text` — a string
/// it does not cover is drawn from a fallback font on the Apple path.
func covers(_ font: PortableFont, _ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { scalar in
        scalar.properties.isWhitespace || scalar.properties.isDefaultIgnorableCodePoint
            || scalar.value < 0x20 || font.raster.glyph(for: scalar) != 0
    }
}

@MainActor @Test func minAndMaxContentMatchMetalUIsApplePathForEveryCoveredString() throws {
    var compared = 0
    for file in fontFiles {
        let font = try OracleFont(file)
        for size in wrapSizes {
            let cache = ShapingCache()
            let portable = try font.portable(size: size)
            for text in runStrings where covers(portable, text) {
                compared += 1
                let appleMin = appleMinContentWidth(text, font: font.apple(size: size), cache: cache)
                let appleMax = Shaper.shape(text, font: font.apple(size: size), wrappingAt: nil).widestLine
                #expect(abs(try PortableText.minContentWidth(text, font: portable) - appleMin) <= 1e-9,
                        "\(file) \(size)pt min \(text.debugDescription)")
                #expect(abs(try PortableText.maxContentWidth(text, font: portable) - appleMax) <= 1e-9,
                        "\(file) \(size)pt max \(text.debugDescription)")
            }
        }
    }
    // 2 faces × 4 sizes × the covered strings; `theWidthCorpusSkipsOnlyWhatAFaceCannotDraw`
    // says which those are.
    #expect(compared == 2 * 4 * 31)
}

/// The width oracle skips exactly the non-Latin strings, and in both faces.
@Test func theWidthCorpusSkipsOnlyWhatAFaceCannotDraw() throws {
    for file in fontFiles {
        let portable = try OracleFont(file).portable(size: 13)
        let skipped = runStrings.filter { !covers(portable, $0) }
        #expect(skipped == ["日本語のテキスト。句読点「かぎ」", "สวัสดีครับ ภาษาไทย", "مرحبا بالعالم",
                            "👩\u{200D}💻 emoji 🇩🇪 flags"], "\(file)")
    }
}

@Test func contentSizesOfAnEmptyStringAreZero() throws {
    let font = try OracleFont("NotoSans-Regular.ttf").portable(size: 13)
    #expect(PortableText.unbreakableRuns(of: "").isEmpty)
    #expect(try PortableText.minContentWidth("", font: font) == 0)
    #expect(try PortableText.maxContentWidth("", font: font) == 0)
}

/// TX-K: max-content is one line per hard break, so it is the widest
/// line, not the sum; TX-F: runs carry no trailing whitespace.
@Test func maxContentIsTheWidestHardLineAndRunsCarryNoTrailingSpace() throws {
    let font = try OracleFont("NotoSans-Regular.ttf").portable(size: 13)
    let long = try PortableText.maxContentWidth("a much longer line", font: font)
    #expect(try PortableText.maxContentWidth("short\na much longer line\nmid", font: font) == long)
    #expect(PortableText.unbreakableRuns(of: "a bb   ccc  \n dd") == ["a", "bb", "ccc", "dd"])
    #expect(try PortableText.minContentWidth("a bb ccc", font: font)
            == PortableText.maxContentWidth("ccc", font: font))
}
