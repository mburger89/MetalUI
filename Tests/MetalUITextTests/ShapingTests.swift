import CoreText
import Foundation
import Testing
@testable import MetalUIText

/// A fresh resolve per access rather than a stored global: `ResolvedFont` holds
/// a `CTFont` and is deliberately not `Sendable` (see its doc comment), so the
/// plan's `private let font = …` does not compile at file scope under Swift 6 —
/// "let 'font' is not concurrency-safe". Ruling TX-A. `CTFontCreateUIFontForLanguage`
/// is itself cached by CoreText, so this costs a lookup, not a face.
private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

/// The CoreText spelling of the font attribute. The plan's drafts used
/// `NSAttributedString.Key.font`, which is **AppKit's**, not Foundation's — it
/// does not compile without `import AppKit`, and `MetalUIText` is a CoreText-only
/// module (spec §3.1). Ruling TX-A: the test moves, not the module.
private let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)

@Test func anUnwrappedStringIsOneLineWhoseAdvanceMatchesCoreText() {
    let s = "Hello, world"
    let shaped = Shaper.shape(s, font: font, wrappingAt: nil)
    let attr = NSAttributedString(string: s, attributes: [ctFontKey: font.ctFont])
    let expected = CTLineGetTypographicBounds(
        CTLineCreateWithAttributedString(attr), nil, nil, nil)
    #expect(shaped.lines.count == 1)
    #expect(abs(shaped.widestLine - expected) < 0.001)
    #expect(abs(shaped.lines[0].advance - expected) < 0.001)

    // One line is exactly one line height — not `1`, and not `ascent` alone.
    // Without this, `totalHeight` could drop the `lineHeight` factor entirely
    // and `aStringWiderThanItsWidthWrapsToMoreThanOneLine`'s `>` comparison
    // below would still hold, because a line *count* orders the same way.
    #expect(abs(shaped.totalHeight - font.metrics.lineHeight) < 0.001)
    #expect(font.metrics.lineHeight > 0)
}

@Test func aStringWiderThanItsWidthWrapsToMoreThanOneLine() {
    let s = "The quick brown fox jumps over the lazy dog"
    let wide = Shaper.shape(s, font: font, wrappingAt: 1000)
    let narrow = Shaper.shape(s, font: font, wrappingAt: 80)
    #expect(wide.lines.count == 1)
    #expect(narrow.lines.count > 1)
    #expect(narrow.widestLine <= 80.001)
    #expect(narrow.totalHeight > wide.totalHeight)

    // The wrapped text is genuinely narrower than the unwrapped one, so
    // `widestLine` is measured per display line rather than copied off the
    // whole string.
    #expect(narrow.widestLine < wide.widestLine)
}

/// Every line must come from CoreText's own break decisions, so a wrapped line
/// never exceeds the width it was given **unless CoreText cannot break it any
/// further**.
///
/// **Rewritten twice from the plan's draft, and both rewrites were forced by a
/// mutation rather than by reading (ruling TX-A).**
///
/// *The draft could not fail (taxonomy shape 1).* It read
/// `line.advance <= width + 0.001 || shaped.lines.count == 1 || line.advance ==
/// shaped.widestLine`. The last disjunct exempts the widest line — which is
/// always the *first* line to exceed the width, so the case the test is named
/// for was the one case it excused. An implementation ignoring `width` and
/// returning one full-width line satisfies both escape clauses at once.
///
/// *The first rewrite asked the wrong oracle (taxonomy shape 9's tell, applied
/// to a test rather than a fixture).* It decided "unbreakable" by re-offering
/// the overflowing line's substring to `Shaper.shape` — the function under
/// test. Measured: under the mutation "ignore `wrappingAt`, always one line",
/// the re-offer returned one line too, so the test stayed green on a shaper
/// that does not wrap at all. **A test whose oracle is the code under test
/// mutates along with it.**
///
/// The oracle here is therefore raw CoreText, reached without going through
/// `Shaper`: ask `CTTypesetterSuggestLineBreak` what it would do with the
/// overflowing line's own text at the same width. A suggestion covering the
/// whole substring means genuinely unbreakable and the overflow is legal; a
/// shorter one means the wrap loop passed up a break.
@Test func noWrappedLineExceedsTheOfferedWidthUnlessItIsUnbreakable() {
    let s = "Supercalifragilistic expialidocious antidisestablishmentarianism"
    let utf16 = Array(s.utf16)
    let ctFont = font.ctFont
    var overflowsSeen = 0
    var fitsSeen = 0

    /// The longest prefix of `text` CoreText itself would put on one line at
    /// `width`, in UTF-16 units.
    func coreTextWouldBreakAfter(_ text: String, width: Double) -> Int {
        let attr = NSAttributedString(string: text, attributes: [ctFontKey: ctFont])
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        return CTTypesetterSuggestLineBreak(typesetter, 0, width)
    }

    for width in [40.0, 90.0, 150.0, 400.0] {
        let shaped = Shaper.shape(s, font: font, wrappingAt: width)
        for shapedLine in shaped.lines {
            guard shapedLine.advance > width + 0.001 else { fitsSeen += 1; continue }
            overflowsSeen += 1

            let range = CTLineGetStringRange(shapedLine.line)
            let text = String(decoding: utf16[range.location ..< range.location + range.length],
                              as: UTF16.self)
            let coreTextPrefix = coreTextWouldBreakAfter(text, width: width)
            #expect(coreTextPrefix == range.length,
                    """
                    line \(text.debugDescription) measures \(shapedLine.advance) at \
                    width \(width), and CoreText would have broken it after \
                    \(coreTextPrefix) of its \(range.length) UTF-16 units — so the \
                    wrap loop passed up a break opportunity.
                    """)
        }
    }

    // Both arms of the assertion above were actually exercised — otherwise the
    // loop is a green no-op over a sample that never overflows and never fits.
    #expect(overflowsSeen > 0)
    #expect(fitsSeen > 0)
}

/// **`widestLine` is the MAXIMUM line advance, not the first line's.**
///
/// Measured gap, not a hypothesis: `widestLine: lines.first?.advance ?? 0` was
/// **green across all 371 tests** before this test existed. Every other shaping
/// test happens to use a sample whose first line is also its widest, or asserts
/// an inequality that a first-line answer satisfies. §3.4 defines min-content as
/// the *widest* line and Task 4's measure function consumes exactly that, so a
/// first-line answer is wrong for every string whose longest word is not first —
/// which is most of them.
///
/// **The review's suggested width of 20 does not produce this shape, and the
/// test moves rather than the claim (ruling TX-A).** At 20pt the system font at
/// 13pt cannot fit `"ccc"` (21.59) on a line at all, so CoreText character-wraps
/// it to `"cc"` / `"c"` and the widest line becomes the *middle* one — which
/// still kills the mutation, but by accident rather than by the stated property.
/// At 25 the intended three lines appear: `"a "` 10.68, `"bb "` 19.40,
/// `"ccc"` 21.59.
@Test func widestLineIsTheWidestLineNotTheFirst() {
    let shaped = Shaper.shape("a bb ccc", font: font, wrappingAt: 25)
    #expect(shaped.lines.count == 3)
    #expect(shaped.widestLine == shaped.lines.last!.advance)
    #expect(shaped.widestLine > shaped.lines.first!.advance)
}

/// **The non-termination guard (spec §3.4).** `CTTypesetterSuggestLineBreak`
/// takes a width by construction, and a non-positive width is an ill-formed
/// request rather than a narrower line. Spec §3.4 requires callers to offer a
/// **small positive** width and requires the violation to be loud, so this is a
/// `precondition` — a clamp would silently answer a different question.
///
/// **What this test does NOT pin, measured rather than assumed.** The plan
/// expected the trap to come from the *zero-length-break* precondition inside
/// the wrap loop, on the premise that `CTTypesetterSuggestLineBreak` at width 0
/// returns a zero-length break and hangs. On this OS it does not: it returns 1
/// at width 0, at negative widths, and at every start index of every string
/// probed — see the mechanism recorded at that precondition in
/// `ShapedText.swift`. So the loop guard is unreachable from any input and this
/// test reddens for the width precondition alone.
@Test func shapingAtAZeroWidthTraps() async {
    await #expect(processExitsWith: .failure) {
        let f = FontResolver.resolve(family: nil, size: 13)
        _ = Shaper.shape("anything", font: f, wrappingAt: 0)
    }
}

@Test func shapingAtASmallPositiveWidthTerminates() async {
    await #expect(processExitsWith: .success) {
        let f = FontResolver.resolve(family: nil, size: 13)
        let shaped = Shaper.shape("a bb ccc", font: f, wrappingAt: 0.5)
        precondition(!shaped.lines.isEmpty)
    }
}

/// The empty-string branch, which exists because the two paths disagree without
/// it: the wrap loop's `while start < length` never runs on an empty string and
/// would return **zero** lines, while the unwrapped path returns one. An empty
/// `Text` would then measure one line high with no width offered and nothing
/// high with one — a height that appears and disappears with the container.
///
/// **Since hard line breaks moved the unwrapped case onto the same loop**
/// (`width: nil` is the loop at `+infinity`), the guard covers `nil` too: without
/// it an empty string would now be zero lines for every width, `nil` included,
/// so every arm below reddens rather than only the wrapped ones.
@Test func anEmptyStringIsOneEmptyLineWhetherWrappedOrNot() {
    for width: Double? in [nil, 0.5, 100] {
        let shaped = Shaper.shape("", font: font, wrappingAt: width)
        #expect(shaped.lines.count == 1)
        #expect(shaped.widestLine == 0)
        #expect(abs(shaped.totalHeight - font.metrics.lineHeight) < 0.001)
    }
}

// MARK: - Hard line breaks (finding B-6)

/// CoreText's own advance for `text` on one line, reached without `Shaper` —
/// the independent oracle for the hard-break tests below (shape 12).
private func ctAdvance(_ text: String) -> Double {
    let attr = NSAttributedString(string: text, attributes: [ctFontKey: font.ctFont])
    return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attr), nil, nil, nil)
}

/// Baseline-to-baseline distance from CoreText's three numbers, ceiled the way
/// `FontMetrics.lineHeight` ceils — computed here rather than read off the
/// property, so a height assertion does not share a summand with the code under
/// test.
private func ctLineHeight() -> Double {
    let f = font.ctFont
    return ceil(Double(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)))
}

/// **A hard line break ends a line whether or not a width is offered.**
///
/// `shape(wrappingAt: nil)` used to build ONE `CTLine` for the whole string,
/// which lays every hard break's segments side by side, while the wrapping
/// branch's `CTTypesetterSuggestLineBreak` always breaks after one. So
/// `.maxContent` reported the **sum** of the segments where every definite
/// width reported the widest: `"Ready\nSet\nGo"` at 13pt measured **75.004**
/// unwrapped against **37.565** wrapped, one line tall against three — and a
/// `Text` placed at that width in a centring `Column` drew its three lines
/// half the over-report left of centre.
///
/// **The separator set is CoreText's, measured, and wider than the finding
/// named.** U+000A, U+000D, CR LF, U+2028 and U+2029 were reported; the
/// typesetter also breaks after U+0085 (NEL), U+000B (VT) and U+000C (FF). Each
/// separator's line advance is exactly its visible segment's standalone
/// advance — the separator prices at zero — so the oracle is the three
/// segments shaped on their own by `CTLineCreateWithAttributedString`, which
/// has no loop and no width in it.
@Test(arguments: ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}", "\u{0085}", "\u{000B}", "\u{000C}"])
func aHardLineBreakEndsALineWhenNoWidthIsOffered(separator: String) throws {
    let segments = ["Ready", "Set", "Go"]
    let s = segments.joined(separator: separator)
    let segmentAdvances = segments.map(ctAdvance)
    let widest = try #require(segmentAdvances.max())

    // The sample is one the defect is visible in: CoreText's whole-string line
    // prices all three segments side by side. Without this the assertions
    // below could hold against the one-line implementation on a sample whose
    // segments happened to sum to their maximum.
    #expect(ctAdvance(s) > widest + 30)

    let shaped = Shaper.shape(s, font: font, wrappingAt: nil)
    try #require(shaped.lines.count == segments.count,
                 "\(s.debugDescription) shaped to \(shaped.lines.count) line(s) unwrapped")

    // Each line is one segment plus the separator that ends it, contiguous.
    var location = 0
    for (i, line) in shaped.lines.enumerated() {
        let range = CTLineGetStringRange(line.line)
        let length = segments[i].utf16.count
            + (i < segments.count - 1 ? separator.utf16.count : 0)
        #expect(range.location == location && range.length == length,
                "line \(i): \(range.location)+\(range.length), expected \(location)+\(length)")
        #expect(abs(line.advance - segmentAdvances[i]) < 0.001)
        location += length
    }
    #expect(abs(shaped.widestLine - widest) < 0.001)
    #expect(abs(shaped.totalHeight - 3 * ctLineHeight()) < 0.001)

    // What `Text` relies on: it MEASURES unwrapped and PAINTS wrapped at the
    // width it measured, so the two must agree on the lines. At the old
    // over-report the paint shape was already three lines while the measure
    // shape was one.
    let atMeasuredWidth = Shaper.shape(s, font: font, wrappingAt: shaped.widestLine)
    #expect(atMeasuredWidth.lines.count == shaped.lines.count)
    #expect(abs(atMeasuredWidth.widestLine - shaped.widestLine) < 0.001)
}

/// **A leading, trailing or doubled hard break, unwrapped.** Each range below
/// is CoreText's own answer from `CTTypesetterSuggestLineBreak`, measured at
/// widths `.infinity`, `.greatestFiniteMagnitude`, `1e7` and `1000` alike, and
/// the wrapping branch has always given it.
///
/// **A trailing break does not open an empty last line** — `"Ready\n"` is one
/// line, the separator inside it. That is CoreText's typesetter, not a rule
/// this module chose, and it is stated so nobody reads the one-line answer as
/// the old defect surviving: the doubled break is the case that discriminates,
/// three lines where the old unwrapped path gave one.
@Test func aLeadingTrailingOrDoubledHardBreakIsOneLinePerBreakUnwrapped() throws {
    let cases: [(string: String, ranges: [(Int, Int)], visible: [String])] = [
        ("Ready\n", [(0, 6)], ["Ready"]),
        ("\n", [(0, 1)], [""]),
        ("a\n\nb", [(0, 2), (2, 1), (3, 1)], ["a", "", "b"]),
        ("\nGo", [(0, 1), (1, 2)], ["", "Go"]),
    ]
    for c in cases {
        let shaped = Shaper.shape(c.string, font: font, wrappingAt: nil)
        try #require(shaped.lines.count == c.ranges.count,
                     "\(c.string.debugDescription) shaped to \(shaped.lines.count) line(s) unwrapped")
        for (i, line) in shaped.lines.enumerated() {
            let range = CTLineGetStringRange(line.line)
            #expect(range.location == c.ranges[i].0 && range.length == c.ranges[i].1,
                    "\(c.string.debugDescription) line \(i): \(range.location)+\(range.length)")
            #expect(abs(line.advance - ctAdvance(c.visible[i])) < 0.001)
        }
        #expect(abs(shaped.totalHeight - Double(c.ranges.count) * ctLineHeight()) < 0.001)
    }
}

/// Everything about a `CTLine` that `ShapedText` and `placedGlyphs` read, and
/// the rest of what CoreText will say about it: per run, the glyphs, their
/// positions, advances and string indices, the run's status and range; per
/// line, the typographic bounds, string range, trailing whitespace and glyph
/// count. Compared with `==`, not a tolerance.
private struct LineDump: Equatable {
    struct Run: Equatable {
        var glyphs: [CGGlyph]
        var positions: [CGPoint]
        var advances: [CGSize]
        var indices: [CFIndex]
        var status: UInt32
        var location: CFIndex
        var length: CFIndex
    }
    var runs: [Run]
    var bounds: [Double]

    init(_ line: CTLine) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let range = CTLineGetStringRange(line)
        bounds = [width, Double(ascent), Double(descent), Double(leading),
                  Double(range.location), Double(range.length),
                  CTLineGetTrailingWhitespaceWidth(line), Double(CTLineGetGlyphCount(line))]
        runs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).map { run in
            let n = CTRunGetGlyphCount(run)
            let all = CFRange(location: 0, length: 0)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            var advances = [CGSize](repeating: .zero, count: n)
            var indices = [CFIndex](repeating: 0, count: n)
            CTRunGetGlyphs(run, all, &glyphs)
            CTRunGetPositions(run, all, &positions)
            CTRunGetAdvances(run, all, &advances)
            CTRunGetStringIndices(run, all, &indices)
            let r = CTRunGetStringRange(run)
            return Run(glyphs: glyphs, positions: positions, advances: advances, indices: indices,
                       status: CTRunGetStatus(run).rawValue, location: r.location, length: r.length)
        }
    }
}

/// **For a string with no hard break, the unwrapped shape is exactly the line
/// `CTLineCreateWithAttributedString` builds** — the guard on the hard-break
/// fix, which replaced that call with the typesetter loop at an infinite width.
///
/// Green before the fix and after it, by design: it pins what the fix must not
/// change. The corpus covers what a typesetter could plausibly treat
/// differently from a whole-string line — base-RTL and mixed bidi, CJK, a ZWJ
/// family, regional indicators, a combining mark, Thai and Devanagari
/// clusters, leading and trailing spaces, ZWSP/NBSP/soft hyphen, ligature and
/// kerning pairs.
///
/// **The last string is the one that discriminates the width**, and why it is
/// long: 4,000 repetitions, 136,000 UTF-16 units, 854,547pt at 13pt. The
/// round-2 review recorded `1e4` as byte-identical too; that held for short
/// strings only — measured, this string breaks at **1,564** units at width 1e4
/// and at **15,912** at 1e5. So "large" had to mean `.infinity`. This sample
/// catches a finite width up to about 8.5e5 and no further.
@Test func anUnwrappedBreakFreeStringIsTheLineCoreTextBuildsWhole() throws {
    let corpus = [
        "Hello, world",
        "a bb supercalifragilistic dd",
        "مرحبا بالعالم",
        "Hello مرحبا world",
        "שלום abc 123",
        "漢字かなカナ混じり文",
        "👨‍👩‍👧‍👦 🇩🇪 e\u{301}",
        "สวัสดีครับ",
        "नमस्ते दुनिया",
        "   leading and trailing   ",
        "\u{200B}zw\u{00A0}nb\u{00AD}sh",
        "fi ffl AV To",
        String(repeating: "antidisestablishmentarianism word ", count: 4000),
    ]
    for s in corpus {
        let attr = NSAttributedString(string: s, attributes: [ctFontKey: font.ctFont])
        let whole = LineDump(CTLineCreateWithAttributedString(attr))

        let shaped = Shaper.shape(s, font: font, wrappingAt: nil)
        try #require(shaped.lines.count == 1,
                     "\(s.prefix(24).debugDescription) shaped to \(shaped.lines.count) lines unwrapped")
        #expect(LineDump(shaped.lines[0].line) == whole,
                "\(s.prefix(24).debugDescription) differs from CTLineCreateWithAttributedString")
        #expect(shaped.lines[0].advance == whole.bounds[0])
    }
}
