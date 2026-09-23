import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// LB-E: MetalUI's Apple wrapping, `Shaper.shape(_:font:wrappingAt:)`, is the
// oracle for `PortableText.lines`. Same font file in both, via `OracleFont`.
//
// Measured before the assertion was written (`METALUI_LINEBREAK_MEASURE=1`,
// 2026-09-23, macOS 27.0, libunibreak 8.0, HarfBuzz 14.5.0): over the whole
// corpus — both fonts, four sizes, no width and 98 widths from 4 to 320 pt,
// seventeen strings — boundaryDifferences=0 advanceDifferences=0 at 1e-9 pt.
// Four rules got there, each from a measured disagreement (record, LB-D/E):
// whitespace hangs; a line's advance is its share of the paragraph's shaping
// (kerning into the next line kept, hard breaks zero wide); a word too wide
// breaks before its overflowing cluster, and a cluster too wide between
// graphemes, re-shaping from any start inside a cluster; tabs go to 28 pt
// stops.

let wrapStrings = [
    "The quick brown fox jumps over the lazy dog.",
    "Ready\nSet\nGo",
    "Ready\n",
    "A line with  two spaces and a trailing space ",
    "Supercalifragilisticexpialidocious is a long word.",
    "Hyphen-ated words, slashes/and dashes — em dash; punctuation (brackets) \"quotes\".",
    "Numbers 1,234.56 and 78% and $9.99 stay together.",
    "Affix the fluffy waffle: AV To Ty LT jig!",
    "e\u{301}te\u{301} cafe\u{301} na\u{303}o",
    "non\u{A0}breaking\u{A0}spaces stay\u{A0}joined",
    "soft\u{AD}hyphen\u{AD}ated word\u{AD}breaks",
    "tab\tseparated\tcolumns",
    "a\u{2028}b\u{2029}c\r\nd\re",
    "trailing   \n  leading",
    "   ",
    "x",
    "https://example.com/path/to/resource?query=1&x=2",
]
let wrapWidths: [Double?] = [nil] + stride(from: 4.0, through: 320.0, by: 3.25).map { $0 }
let wrapSizes: [Double] = [11, 13, 17, 26]

struct WrapDifference: CustomStringConvertible {
    let file: String, size: Double, width: Double?, text: String
    let apple: [(Range<Int>, Double)], portable: [(Range<Int>, Double)]
    var description: String {
        func fmt(_ l: [(Range<Int>, Double)]) -> String {
            l.map { "\($0.0.lowerBound)..<\($0.0.upperBound)@\(String(format: "%.3f", $0.1))" }.joined(separator: " ")
        }
        return "\(file) \(size)pt w=\(width.map { "\($0)" } ?? "nil") \(text.debugDescription)\n  apple    \(fmt(apple))\n  portable \(fmt(portable))"
    }
}

func appleLines(_ text: String, font: ResolvedFont, width: Double?) -> [(Range<Int>, Double)] {
    Shaper.shape(text, font: font, wrappingAt: width).lines.map { line in
        let range = CTLineGetStringRange(line.line)
        return (range.location..<(range.location + range.length), line.advance)
    }
}

func wrapDifferences(advanceTolerance: Double) throws -> (cases: Int, boundaries: [WrapDifference], advances: [WrapDifference]) {
    var cases = 0
    var boundaries: [WrapDifference] = [], advances: [WrapDifference] = []
    for file in fontFiles {
        let font = try OracleFont(file)
        for size in wrapSizes {
            for width in wrapWidths {
                for text in wrapStrings {
                    cases += 1
                    let apple = appleLines(text, font: font.apple(size: size), width: width)
                    let portable = try PortableText.lines(text, font: font.portable(size: size), wrappingAt: width)
                        .map { ($0.range, $0.advance) }
                    let difference = WrapDifference(file: file, size: size, width: width, text: text,
                                                    apple: apple, portable: portable)
                    if apple.map(\.0) != portable.map(\.0) { boundaries.append(difference); continue }
                    if zip(apple, portable).contains(where: { abs($0.1 - $1.1) > advanceTolerance }) {
                        advances.append(difference)
                    }
                }
            }
        }
    }
    return (cases, boundaries, advances)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_LINEBREAK_MEASURE"] == "1"))
func measureWrapDifferences() throws {
    let (cases, boundaries, advances) = try wrapDifferences(advanceTolerance: 1e-9)
    print("LB-E cases=\(cases) boundaryDifferences=\(boundaries.count) advanceDifferences=\(advances.count)")
    var byString: [String: (Int, Int)] = [:]
    for d in boundaries { byString[d.text, default: (0, 0)].0 += 1 }
    for d in advances { byString[d.text, default: (0, 0)].1 += 1 }
    for (text, counts) in byString.sorted(by: { $0.key < $1.key }) {
        print("BYSTRING boundary=\(counts.0) advance=\(counts.1) \(text.debugDescription)")
    }
    let focus = ProcessInfo.processInfo.environment["METALUI_LINEBREAK_FOCUS"]
    for d in boundaries where focus.map({ d.text.hasPrefix($0) }) ?? true { print("BOUNDARY \(d)") }
    for d in advances.prefix(10) where focus.map({ d.text.hasPrefix($0) }) ?? true { print("ADVANCE \(d)") }
}

@Test func everyCorpusCaseWrapsExactlyAsMetalUIsApplePath() throws {
    let (cases, boundaries, advances) = try wrapDifferences(advanceTolerance: 1e-9)
    try #require(cases == fontFiles.count * wrapSizes.count * wrapWidths.count * wrapStrings.count)
    #expect(boundaries.isEmpty, "\(boundaries.count) cases break differently; first: \(boundaries.first.map { "\($0)" } ?? "")")
    #expect(advances.isEmpty, "\(advances.count) cases measure differently; first: \(advances.first.map { "\($0)" } ?? "")")
}

/// The corpus exercises what the four rules are for, so an agreement is not
/// an agreement about nothing: some cases wrap at a break opportunity, some
/// break inside a word, some split a ligature, and a tab reaches a stop.
@Test func theWrapCorpusReachesEveryRule() throws {
    let font = try OracleFont(notoSans).portable(size: 11)
    // Wraps at spaces.
    #expect(try PortableText.lines("The quick brown fox", font: font, wrappingAt: 40).count > 1)
    // A word wider than the line breaks inside it.
    let long = try PortableText.lines("Supercalifragilistic", font: font, wrappingAt: 30)
    #expect(long.count > 1 && long.allSatisfy { !$0.range.isEmpty })
    // "ffi" is one glyph in Noto Sans; at 7.25 pt it is split between graphemes.
    let affix = try PortableText.lines("Affix", font: font, wrappingAt: 7.25).map(\.range)
    #expect(affix == [0..<1, 1..<2, 2..<4, 4..<5])
    // A tab advances to the 28 pt stop.
    let tab = try PortableText.lines("tab\t", font: font, wrappingAt: nil)
    #expect(tab.map(\.advance) == [28])
}
