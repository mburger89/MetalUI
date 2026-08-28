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
/// `lineHeight { ascent }` left the whole suite green at 371 tests).
private func ctLineHeight(_ ctFont: CTFont) -> Double {
    Double(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
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
/// participates in; the paint test below uses `render` instead.
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

// MARK: - `newLeaf` has a production caller

/// **The row this task exists to delete.** `newLeaf` is the only thing that
/// attaches a `MeasureFunction` and nothing in `Sources/` called it, so every
/// production node's `tree.measure()` was `nil` — §9.2's content branch and
/// §4.5's automatic minimum were live for containers and dead for leaves.
///
/// The `Box` half is not decoration. "The text node has a measure function" also
/// passes if `requestNode` started attaching one to everything, which would make
/// every container answer from a closure instead of from its children.
@MainActor
@Test func aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot() {
    var text = Text(sample)
    let (textFrame, textNode) = laidOut(&text, width: 400)
    #expect(textFrame.tree.measure(textNode) != nil)
    #expect(textFrame.tree.children(textNode).isEmpty)

    var box = Box()
    let (boxFrame, boxNode) = laidOut(&box, width: 400)
    #expect(boxFrame.tree.measure(boxNode) == nil)
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
    var column = Column { Text(sample).width(Pixels(50)) }
    let (frame, root) = laidOut(&column, width: 400)
    let rect = frame.tree.layout(frame.tree.children(root)[0])
    #expect(rect.width == 50)
    // 4 x 15.3105 = 61.24, rounded to whole pixels by the engine.
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

// MARK: - What wrapping buys, end to end

/// **A long label in a narrow column wraps instead of running off the end** —
/// the reason wrapping is in M2 rather than deferred.
///
/// 120pt of system 13pt holds three lines of the label, so the box is
/// `3 × 15.3105 = 45.93` tall, rounded to 46. A single-line implementation would
/// report one line and 16.
///
/// **`.alignItems(.stretch)` is load-bearing and is not incidental to the
/// wrap.** `Column` centres by default (ruling EP-8), and a centred child takes
/// its cross size from `collectItems`' `auto` branch, which offers
/// `.maxContent` — so the same label in a *centring* column is laid out 270 wide
/// inside a 120 column while still being sized 46 tall, as if it had wrapped.
/// That divergence is measured against WebKit and pinned by
/// `aCentringColumnDoesNotShrinkWrapItsTextUnlikeWebKit` below.
@MainActor
@Test func aLongLabelInAStretchedColumnWrapsRatherThanOverflowing() {
    var column = Column { Text(label) }.alignItems(.stretch)
    let (frame, root) = laidOut(&column, width: 120)
    let rect = frame.tree.layout(frame.tree.children(root)[0])

    let lineHeight = ctLineHeight(font.ctFont)
    #expect(rect.width == 120)
    #expect(rect.height == (3 * lineHeight).rounded())
    #expect(rect.height > 2 * lineHeight)

    // The same label in a column wide enough for one line is one line tall, so
    // the height above is the wrap and not a constant.
    var wide = Column { Text(label) }.alignItems(.stretch)
    let (wideFrame, wideRoot) = laidOut(&wide, width: 400)
    #expect(wideFrame.tree.layout(wideFrame.tree.children(wideRoot)[0]).height
            == lineHeight.rounded())
}

/// **An `auto` cross size is max-content where WebKit shrink-wraps it, and the
/// two axes of the same box then disagree.** Not introduced here — `Text` is
/// what makes it visible, because text is the first content whose min-content
/// and max-content differ.
///
/// The label's box in a 120-wide centring column comes out **270 wide and 46
/// tall**: the height is the three lines it takes at 120, and the width is the
/// one line it would take if nothing wrapped it. It hangs 75pt off each side.
///
/// WebKit's answer is 120 wide. Measured without any text at all —
/// `anAutoCrossSizeIsMaxContentRatherThanFitContentUnlikeWebKit` in
/// `MetalUILayoutTests` carries the repro and the numbers (WebKit `120x40`,
/// engine `200x40`), because the rule is the engine's and not this element's.
/// Fixing it belongs to a sizing plan: it moves an item's stored cross size,
/// which every ancestor consumes and 61 goldens depend on.
@MainActor
@Test func aCentringColumnDoesNotShrinkWrapItsTextUnlikeWebKit() {
    var column = Column { Text(label) }
    let (frame, root) = laidOut(&column, width: 120)
    let rect = frame.tree.layout(frame.tree.children(root)[0])

    #expect(rect.width == ctAdvance(label, font.ctFont).rounded())
    #expect(rect.width > 120)
    #expect(rect.x < 0)
    // Sized as if it had wrapped, laid out as if it had not.
    #expect(rect.height == (3 * ctLineHeight(font.ctFont)).rounded())
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

// MARK: - Paint

/// A `Text` paints its background and **no glyphs** — the atlas and the text
/// pipeline are Tasks 5-7. This is the whole of what `render` produces for one,
/// and it is here so that "text draws nothing yet" is a checked fact rather than
/// a sentence in a doc comment.
@MainActor
@Test func aTextPaintsItsBackgroundAndNoGlyphsYet() {
    let frame = Frame(contentSize: Size(width: Pixels(120), height: Pixels(600)),
                      scaleFactor: 1)
    var column = Column { Text(label).background(.surface) }.alignItems(.stretch)
    frame.render(&column)

    let scene = frame.finalizedScene()
    #expect(scene.rects.count == 1)
    if let rect = scene.rects.first {
        #expect(rect.bounds.size.width == 120)
        #expect(rect.bounds.size.height == Float((3 * ctLineHeight(font.ctFont)).rounded()))
    }
}
