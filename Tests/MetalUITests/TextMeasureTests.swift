import CoreText
import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

// Task 4 — the measure function, `Text`, and `newLeaf`'s first production
// caller.
//
// **Every size assertion below has an oracle that is not this code.** Widths
// come from `CTLineGetTypographicBounds` on a line built straight from
// `NSAttributedString`, and heights from `CTFontGetAscent + Descent + Leading`
// times a line count that is named in the test. That is deliberate: the two
// defects Task 2 shipped and fixed were both "the oracle is the code under
// test" (proposed taxonomy shape 12), where the expectation moves with the
// mutation and the test cannot fail. `Shaper` and `ShapedText` are *never* the
// oracle here, even though they are a module away and separately tested.

/// A fresh resolve per access rather than a stored `let`: `ResolvedFont` holds a
/// `CTFont` and is deliberately not `Sendable`, so a file-scope `let` does not
/// compile under Swift 6 (ruling TX-A, third time on this branch). CoreText
/// caches the face, so this costs a lookup.
private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

private let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)

/// The advance CoreText itself reports for `text` on one line — the oracle for
/// every width below, reached without `Shaper`.
private func ctAdvance(_ text: String, _ ctFont: CTFont) -> Double {
    let attributed = NSAttributedString(string: text, attributes: [ctFontKey: ctFont])
    return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
}

/// Baseline-to-baseline distance, added up from CoreText's three numbers rather
/// than read off `FontMetrics.lineHeight` — which is the property under test's
/// own summand, and would move with it (shape 12; measured on this branch:
/// `lineHeight { ascent }` left the whole suite green at 371 tests). Rounded up
/// to a whole point, matching `FontMetrics.lineHeight`'s own `ceil`
/// (line-height rounding) — applied here from the raw CoreText sum, not by
/// calling the property, so this stays an independent oracle for the rounding
/// too.
private func ctLineHeight(_ ctFont: CTFont) -> Double {
    ceil(Double(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)))
}

/// `"a bb supercalifragilistic dd"` — one long unbreakable run among short ones,
/// so min-content, max-content and a wrapped width are three different numbers.
private let sample = "a bb supercalifragilistic dd"

/// Nine short words, so a 120pt column wraps it to three lines.
private let label = "The quick brown fox jumps over the lazy dog"

/// Lays `element` out in a `width × height` frame and hands back the frame and
/// the root node, so a test can read any node's resolved rect.
///
/// **Not `Frame.render`**, which does not give back the root id. It runs the
/// layout phase and the engine, which is everything a measure function
/// participates in. At `Frame`'s default authority (the four `.legacy` callers
/// stage 6b pinned, `LR-DI`, were retired at stage 7b, record §49 rows 232–235).
@MainActor
private func laidOut<E: Element>(_ element: inout E, width: Double, height: Double = 600,
                                 cache: ShapingCache = ShapingCache()) -> (Frame, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: Pixels(Float(width)), height: Pixels(Float(height))),
                      scaleFactor: 1, stateTable: StateTable(), shapingCache: cache)
    var pass = LayoutPass(frame: frame)
    let (root, _) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                          pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame, root)
}

// MARK: - The three sizing modes (spec §3.4)

/// Max-content is one line's full advance; min-content is the widest
/// **unbreakable run**; a definite width is the widest line the text wraps to.
///
/// Every expectation is CoreText's own answer for a hand-identified string:
/// - max-content — the whole sample on one line, **159.821**;
/// - min-content — `"supercalifragilistic"` alone, **110.348**;
/// - at 120 — the widest of the three lines the sample wraps to is
///   `"supercalifragilistic "`, **with** its trailing space, **113.928**.
///
/// The last two are 3.58 apart, which is the whole of the trailing-space rule
/// and is what a `trimmingCharacters` deleted from `unbreakableRuns` would move.
@MainActor
@Test func theThreeSizingModesAnswerWithCoreTextsOwnNumbers() {
    let font = font
    let cache = ShapingCache()
    let lineHeight = ctLineHeight(font.ctFont)

    let maxContent = textMeasure(sample, font: font, cache: cache,
                                 known: .unspecified, available: .maxContent)
    #expect(abs(maxContent.width - ctAdvance(sample, font.ctFont)) < 0.001)
    #expect(abs(maxContent.height - lineHeight) < 0.001)

    let minContent = textMeasure(sample, font: font, cache: cache,
                                 known: .unspecified, available: .minContent)
    #expect(abs(minContent.width - ctAdvance("supercalifragilistic", font.ctFont)) < 0.001)

    let wrapped = textMeasure(sample, font: font, cache: cache,
                              known: .unspecified, available: .definite(120))
    #expect(abs(wrapped.width - ctAdvance("supercalifragilistic ", font.ctFont)) < 0.001)
    // Three lines: "a bb " / "supercalifragilistic " / "dd".
    #expect(abs(wrapped.height - 3 * lineHeight) < 0.001)

    // The three modes are three answers, not one. Without this a measure
    // function that ignored `available` entirely would satisfy each assertion
    // above only by accident of which oracle it matched.
    #expect(minContent.width < wrapped.width)
    #expect(wrapped.width < maxContent.width)
    #expect(maxContent.height < wrapped.height)
}

/// **Min-content is the longest run and not the widest character**, which is
/// where §3.4's wording and this platform part company.
///
/// `CTTypesetterSuggestLineBreak` breaks *inside* a word it cannot fit, so
/// "typeset at a small positive width and take the widest line" answers
/// **11.489** for this sample — the width of one `"m"`-ish glyph — where CSS's
/// min-content is **110.348**. A tenth of the right answer, and in the direction
/// that matters: §4.5's automatic minimum would then let a `Row` squeeze a long
/// label until CoreText broke it mid-word, which is exactly the failure §3.4
/// says wrapping is in M2 to prevent.
///
/// The second half is the differential that shows the answer is not merely
/// *bigger* but **exact**: shaping the sample at the reported min-content width
/// keeps `"supercalifragilistic"` whole, and shaping it 0.35pt narrower does not
/// — CoreText breaks it into `"supercalifragilisti"` / `"c dd"`. The trailing
/// space hangs past the break, which is why 110.348 holds a run that measures
/// 113.928 with its space.
@MainActor
@Test func minContentIsTheLongestRunNotTheWidestCharacter() {
    let font = font
    let cache = ShapingCache()

    let minContent = textMeasure(sample, font: font, cache: cache,
                                 known: .unspecified, available: .minContent).width
    #expect(abs(minContent - ctAdvance("supercalifragilistic", font.ctFont)) < 0.001)

    // What the tiny-width spelling of §3.4 would have answered. The typesetter
    // puts one character on each line — 25 of them for this sample — so the
    // widest is whichever character carries the *trailing space* of its word:
    // "a ", "b " or "c ". CoreText prices those three directly, without the
    // shaper. (Measured: 11.489, against a bare widest character of 7.909 —
    // the 3.58 gap is the space, and it is why this must not be spelled as
    // `max(over characters)`, which was this assertion's first, wrong form.)
    let widestTinyLine = ["a ", "b ", "c "].map { ctAdvance($0, font.ctFont) }.max()!
    let tinyWidth = Shaper.shape(sample, font: font, wrappingAt: 0.5).widestLine
    #expect(abs(tinyWidth - widestTinyLine) < 0.001)
    #expect(minContent > 9 * tinyWidth)

    // The exactness differential: at the reported width the long run stays
    // whole, 0.35pt narrower it does not.
    let atMinContent = Shaper.shape(sample, font: font, wrappingAt: minContent)
    let justUnder = Shaper.shape(sample, font: font, wrappingAt: minContent - 0.35)
    #expect(abs(atMinContent.widestLine - ctAdvance("supercalifragilistic ", font.ctFont)) < 0.001)
    #expect(abs(justUnder.widestLine - ctAdvance("supercalifragilisti", font.ctFont)) < 0.001)
}

/// A `known` size wins over the measured one on either axis (§5.5) —
/// `measureNode`'s existing contract, exercised by a production leaf for the
/// first time.
///
/// The height still comes from the shape, so a `Text` told it is 50 wide is
/// **four lines** tall rather than one: `known` states the box on the axis it
/// names, not on the other one.
@MainActor
@Test func anExplicitKnownSizeWinsOverTheMeasuredOne() {
    let font = font
    let cache = ShapingCache()
    let lineHeight = ctLineHeight(font.ctFont)

    let narrow = textMeasure(sample, font: font, cache: cache,
                             known: OptionalSizeD(width: 50, height: nil),
                             available: .maxContent)
    #expect(narrow.width == 50)
    #expect(abs(narrow.height - 4 * lineHeight) < 0.001)

    let fixedHeight = textMeasure(sample, font: font, cache: cache,
                                  known: OptionalSizeD(width: nil, height: 7),
                                  available: .maxContent)
    #expect(fixedHeight.height == 7)
    #expect(abs(fixedHeight.width - ctAdvance(sample, font.ctFont)) < 0.001)

    // And through the element, where the engine is what applies `known`.
    var column = Column { Text(sample).frame(width: Pixels(50)) }
    let (frame, root) = laidOut(&column, width: 400)
    let rect = frame.tree.layout(frame.tree.children(root)[0])
    #expect(rect.width == 50)
    // lineHeight is 16 (ceil(15.3105), line-height rounding), so 4 x 16 = 64 —
    // already a whole number, and `.rounded()` here is the engine's own
    // pixel-rounding pass rather than anything moving it further.
    #expect(rect.height == (4 * lineHeight).rounded())
}

/// **Ruling TX-E: a zero available extent measures rather than traps.**
///
/// `Shaper.shape` preconditions on `width > 0` and `precondition` is live in
/// `-O`, so an unclamped zero terminates a release build. It is not a
/// pathological input: a `Column` whose own width is 0 offers exactly
/// `.definite(0)` to its child's flex base size, which is the second half of
/// this test.
///
/// **The whole case runs in a subprocess** (ruling CS-C). Asserting "this does
/// not trap" in-process cannot fail as a red test — it fails as a dead process
/// and a truncated run with no summary line, which is taxonomy shape 11 and the
/// hardest failure in this repo to notice.
@MainActor
@Test func aZeroAvailableExtentMeasuresRatherThanTraps() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let font = FontResolver.resolve(family: nil, size: 13)
            let cache = ShapingCache()

            let zero = textMeasure(sample, font: font, cache: cache,
                                   known: .unspecified, available: .definite(0))
            // One character per line: 25 of them, so the answer is a tall sliver
            // rather than nothing.
            precondition(zero.width > 0 && zero.height > 20 * ctLineHeight(font.ctFont))

            let knownZero = textMeasure(sample, font: font, cache: cache,
                                        known: OptionalSizeD(width: 0, height: nil),
                                        available: .maxContent)
            precondition(knownZero.width == 0 && knownZero.height > 0)

            // The engine's own route to a definite 0: a container with no width
            // hands its child a zero cross extent through `flexBaseSize`.
            var column = Column { Text(sample) }
            let (frame, root) = laidOut(&column, width: 0)
            precondition(frame.tree.layout(frame.tree.children(root)[0]).height > 0)
        }
    }
}

// MARK: - The cache is the window's, not the frame's

/// **One shaping cache across frames, and a second frame adds no misses.**
///
/// `Frame` takes the cache the way it takes the `StateTable`: the window owns
/// it and hands the same instance to every frame. A `Frame` that constructed its
/// own would re-shape every string through CoreText on every frame — three times
/// per text item per layout, since §4.5's automatic minimum probes every item —
/// and **no other test in the repo can see it**, because a single-frame test
/// cannot tell a warm cache from a cold one.
///
/// The miss count is the only observable, which is why this test reaches into
/// `MetalUIText` with `@testable`.
@MainActor
@Test func twoFramesShareOneShapingCacheRatherThanReShapingEachFrame() {
    let cache = ShapingCache()

    var first = Column { Text(label) }.alignItems(.stretch)
    _ = laidOut(&first, width: 120, cache: cache)
    let missesAfterFirstFrame = cache.misses
    let hitsAfterFirstFrame = cache.hits

    var second = Column { Text(label) }.alignItems(.stretch)
    _ = laidOut(&second, width: 120, cache: cache)

    #expect(missesAfterFirstFrame > 0)
    #expect(cache.misses == missesAfterFirstFrame)
    #expect(cache.hits > hitsAfterFirstFrame)
}
