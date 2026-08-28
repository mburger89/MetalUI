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
@Test func anEmptyStringIsOneEmptyLineWhetherWrappedOrNot() {
    for width: Double? in [nil, 0.5, 100] {
        let shaped = Shaper.shape("", font: font, wrappingAt: width)
        #expect(shaped.lines.count == 1)
        #expect(shaped.widestLine == 0)
        #expect(abs(shaped.totalHeight - font.metrics.lineHeight) < 0.001)
    }
}
