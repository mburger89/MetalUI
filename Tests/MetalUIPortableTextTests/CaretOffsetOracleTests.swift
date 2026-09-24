import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText
import MetalUITextSystem
import MetalUIHarfBuzz

// TI-E: caret offsets. `CoreTextTextSystem.caretOffsets` asks the `CTLine`
// (`CTLineGetOffsetForStringIndex` at each grapheme boundary's UTF-16 offset);
// `PortableTextSystem.caretOffsets` sums shaped advances. The Apple path is
// the oracle, over the same font files as the other portable oracles.
//
// Measured before the assertion was written (2026-09-23, macOS 27.0, HarfBuzz
// 14.5.0): 280 cases — both Latin faces × four sizes × 31 strings (the Apple
// path corpus, ligature-prone, kerning and combining-mark strings, and every
// wrap string without a hard break), and the fallback corpus × four sizes
// through the Source Sans 3 → Noto Sans cascade — 6,216 grapheme boundaries.
// A plain advance sum differed in 185 of the first 272 cases. Three rules took
// that to 0 at 1e-9 pt (146 still differ at exactly 0, each in the last bits
// of a float sum — CoreText reads a tab stop as 27.999999999999996):
//
// - a caret between two clusters sits halfway through the kern (CoreText's
//   `A|V` in Noto Sans at 1000 pt is 619: `A` kerned 639 → 599);
// - a caret inside a ligature sits at the face's `GDEF` ligature caret
//   (Noto Sans' `f|f` at 301 of 688, `f|f|i` at 315 and 631 of 946 — an even
//   split would read 344 and 315.3/630.7) and, with no caret list, at an even
//   split (Source Sans 3's `f|f` at 288.5 of 577, unrounded);
// - neither rule moves a caret after a default ignorable, whose advance
//   HarfBuzz zeroes (the soft hyphen: 8 cases until this rule).
//
// Not in the corpus, measured and left: a `ZWJ` between two letters in Source
// Sans 3 (CoreText falls back to another face for the whole grapheme), and a
// string ending in a soft hyphen (CoreText's caret before it reads 0).

/// Ligature-prone strings, and graphemes of several scalars the two Latin
/// faces draw (combining marks, stacked).
let caretStrings = corpusStrings + [
    "office", "ffi", "ffl", "fl", "fi fl ffi ffl", "the affluent official waffles",
    "e\u{301}te\u{301} cafe\u{301}", "a\u{308}\u{301}o\u{323}\u{302} n\u{303}",
    "fi\u{301}", "tab\tseparated", "trailing space ", "   ", "AVA To Ty r. rg",
] + wrapStrings.filter { !$0.unicodeScalars.contains(where: isHardBreakScalar) }

func isHardBreakScalar(_ scalar: Unicode.Scalar) -> Bool {
    [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029].contains(scalar.value)
}

@MainActor
func caretDifferences(tolerance: Double) throws -> (cases: Int, boundaries: Int, differences: [String]) {
    var cases = 0, boundaries = 0
    var differences: [String] = []
    func compare(_ label: String, _ text: String, apple: ResolvedFont, portable: PortableFont) throws {
        cases += 1
        let a = Shaper.caretOffsets(text, font: apple)
        let p = try PortableText.caretOffsets(text, font: portable)
        boundaries += a.count
        guard a.count == p.count else {
            differences.append("\(label) \(text.debugDescription): \(a.count) vs \(p.count) offsets"); return
        }
        if let i = a.indices.first(where: { abs(a[$0] - p[$0]) > tolerance }) {
            differences.append("\(label) \(text.debugDescription) boundary \(i): apple \(a[i]) portable \(p[i])")
        }
    }
    for file in fontFiles {
        let font = try OracleFont(file)
        for size in wrapSizes {
            for text in caretStrings {
                try compare("\(file) \(size)pt", text, apple: font.apple(size: size), portable: font.portable(size: size))
            }
        }
    }
    for size in wrapSizes {
        let apple = try appleCascade(size: size), portable = try portableCascade(size: size)
        for text in fallbackStrings { try compare("fallback \(size)pt", text, apple: apple, portable: portable) }
    }
    return (cases, boundaries, differences)
}

/// Every grapheme boundary, both Latin faces and the fallback cascade, equal
/// to CoreText's within 1e-9 pt (measured: 280 cases, 6,216 boundaries, 0
/// differing).
@MainActor
@Test func everyCaretOffsetIsCoreTexts() throws {
    let (cases, boundaries, differences) = try caretDifferences(tolerance: 1e-9)
    try #require(cases == 280)
    #expect(boundaries == 6216)
    #expect(differences.isEmpty, note("\(differences.count) differ; first: \(differences.first ?? "")"))
}

/// The three measured rules, each at 1000 pt (so points are design units) on
/// the face that shows it, through both text systems.
@MainActor
@Test func theCaretSitsHalfwayThroughAKernAtALigatureCaretOrAtAnEvenSplit() throws {
    let noto = try OracleFont(notoSans), source = try OracleFont(sourceSans)
    let expected: [(OracleFont, String, [Double])] = [
        (noto, "AV", [0, 619, 1199]),            // A kerned 639 → 599: halfway, 619
        (noto, "ff", [0, 301, 688]),             // GDEF caret, not 344
        (noto, "ffi", [0, 315, 631, 946]),       // GDEF carets, not 315.33/630.67
        (source, "ff", [0, 288.5, 577]),         // no caret list: even split
        (noto, "a\u{AD}b", [0, 561, 561, 1176]), // the soft hyphen: no kern rule
    ]
    for (font, text, offsets) in expected {
        let apple = CoreTextTextSystem(), portable = try PortableTextSystem(
            resolver: PortableFontResolver(defaultFont: font.data))
        apple.cache.registerFont(font.apple(size: 1000))
        let appleKey = font.apple(size: 1000).key
        let portableKey = portable.resolveFont(family: nil, size: 1000)
        #expect(apple.caretOffsets(text, font: appleKey) == offsets, "CoreText \(font.file) \(text.debugDescription)")
        #expect(portable.caretOffsets(text, font: portableKey) == offsets, "portable \(font.file) \(text.debugDescription)")
    }
}

/// Graphemes of several scalars — combining marks, an emoji modifier, a ZWJ
/// family, a flag — and the edge cases, through both text systems.
let caretContractStrings = [
    "", "a", " ", "office", "e\u{301}te\u{301}", "a\u{308}\u{301}b",
    "👍🏽 ok", "👨‍👩‍👧 family", "🇩🇪 flag", "tab\tstop", "The quick brown fox.",
]

@MainActor
@Test func caretOffsetsAreOnePerGraphemeBoundaryFromZeroToTheMeasuredWidth() throws {
    let font = try OracleFont(notoSans)
    let apple = CoreTextTextSystem()
    apple.cache.registerFont(font.apple(size: 17))
    let portable = try PortableTextSystem(resolver: PortableFontResolver(defaultFont: font.data))
    let systems: [(String, any TextSystem, FontKey)] = [
        ("CoreText", apple, font.apple(size: 17).key),
        ("portable", portable, portable.resolveFont(family: nil, size: 17)),
    ]
    for (name, system, key) in systems {
        #expect(system.caretOffsets("", font: key) == [0], "\(name)")
        for text in caretContractStrings {
            let offsets = system.caretOffsets(text, font: key)
            let label = note("\(name) \(text.debugDescription): \(offsets)")
            try #require(offsets.count == text.count + 1, label)
            #expect(offsets.first == 0, label)
            #expect(offsets.last == system.measure(text, font: key, wrappingAt: nil).widestLine, label)
            #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, label)
        }
    }
}

/// Right-to-left and mixed paragraphs (TI-E: bidirectional carets are out of
/// scope, so no equality with CoreText's visual answer): the portable offsets
/// are still one per grapheme boundary, non-decreasing in logical order, and
/// end at the measured width.
@MainActor
@Test func rightToLeftCaretOffsetsAreLogicalAndEndAtTheMeasuredWidth() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
    try resolver.register(fontBytes(notoSansArabic))
    let system = PortableTextSystem(resolver: resolver)
    let apple = CoreTextTextSystem()
    let cascade = try appleBidiFont(size: 17)
    apple.cache.registerFont(cascade)
    let key = system.resolveFont(family: nil, size: 17)
    let strings = bidiStrings.filter { !$0.unicodeScalars.contains(where: isHardBreakScalar) }
    try #require(strings.count == bidiStrings.count - 1)
    for text in strings {
        let offsets = system.caretOffsets(text, font: key)
        let label = note("\(text.debugDescription): \(offsets)")
        try #require(offsets.count == text.count + 1, label)
        #expect(offsets.first == 0, label)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, label)
        #expect(abs(offsets.last! - system.measure(text, font: key, wrappingAt: nil).widestLine) <= 1e-9, label)
        #expect(apple.caretOffsets(text, font: cascade.key).count == text.count + 1, label)
    }
}
