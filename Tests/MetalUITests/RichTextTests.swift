import CoreText
import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIDemoContent
import MetalUITextSystem
@testable import MetalUIPortableText
@testable import MetalUIText
@testable import MetalUI

// Rich text, lane 2 — the `Text` element (rulings RT-E…RT-L, RT-R; spec §4.2,
// tests 2.1–2.3, 2.9, 2.13–2.16, 2.18–2.23 and RT-R's own arm). The paint
// geometry tests (2.4–2.8, 2.11, 2.17) are `RichTextPaintTests.swift`; the
// compile guards (2.24, 2.25) `RichTextCompileGuards.swift`; the portable
// window test (2.26) `MetalUICrossPlatformTests/RichTextPortableWindowTests.swift`;
// 2.12 is the styled arm of `everyDecorationScopingSiteContainsItsOwnContent`.
//
// **`+` is called through a deprecated protocol witness reached by a generic
// constraint** (`RT-O` item 9, `LR-CV`, `swift-deprecated-witness-silence.sh`):
// a bare call from a `@Test` would warn against the 0-`warning:` gate.

// MARK: - Shared helpers (lane 2's two MetalUITests files)

/// The requirement a deprecated witness answers without a warning at the call.
@MainActor
protocol RichTextConcatenating {
    func concatenate(_ parts: [Text]) -> Text
}

/// `parts[0] + parts[1] + …`, through the deprecated `+`.
struct DeprecatedTextPlus: RichTextConcatenating {
    @available(*, deprecated, message: "calls the deprecated Text + Text on purpose: it is the subject of lane 2's rich-text tests (RT-E, RT-O item 9)")
    func concatenate(_ parts: [Text]) -> Text {
        parts.dropFirst().reduce(parts[0]) { $0 + $1 }
    }
}

@MainActor
private func concatenateThrough<C: RichTextConcatenating>(_ witness: C, _ parts: [Text]) -> Text {
    witness.concatenate(parts)
}

/// `Text + Text + …` (ruling RT-E), with no warning at the call site.
@MainActor
func rtJoin(_ parts: Text...) -> Text { concatenateThrough(DeprecatedTextPlus(), parts) }

/// One headless frame of `element` over `system` (CoreText by default).
@MainActor
func rtFrame<E: Element>(_ element: E, system: (any TextSystem)? = nil, side: Float = 300, scale: Float = 1,
                         accessibility: Bool = false) -> Frame {
    let frame = Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)), scaleFactor: scale,
                      textSystem: system, collectsAccessibility: accessibility, reportsUnlowerableFields: true)
    var root = element
    frame.render(&root)
    return frame
}

/// `text` at the window's top-left corner: a flex-start `Row` declared at the
/// window's size (`inFilledRow`'s shape), so the text's box starts at (0, 0).
@MainActor
func rtTopLeft<G: ElementGroup>(_ element: G, side: Float = 300) -> some Element {
    Row { element }.alignItems(.flexStart).cssWidth(Pixels(side)).cssHeight(Pixels(side))
}

/// `text` resolved as its element resolves it (ruling RT-E item 2).
@MainActor
func rtResolved(_ text: Text, _ system: any TextSystem,
                environment: EnvironmentValues = EnvironmentValues()) -> ResolvedRichText {
    resolveRichText(text.content, own: text.styleRequest, rich: text.rich, in: environment, system: system)
}

/// Whether a scene colour is `expected`, exactly.
func rtSame(_ color: MUIHsla, _ expected: Hsla) -> Bool {
    color.h == expected.h && color.s == expected.s && color.l == expected.l && color.a == expected.a
}

/// A face's key in `system` at `size` points, optionally `weight`.
@MainActor
func rtKey(_ system: any TextSystem, _ size: Double = 13, weight: Font.Weight? = nil) -> FontKey {
    system.resolveFont(FontDescriptor(size: size, weight: weight?.value))
}

/// A spy text system (`RT-O` item 15): forwards every requirement to a real
/// CoreText system and records which were called, and at which widths.
final class RichTextSpySystem: TextSystem, @unchecked Sendable {
    let base = CoreTextTextSystem()
    private(set) var plainCalls: [String] = []
    private(set) var styledCalls: [String] = []
    private(set) var styledMeasureWidths: [Double?] = []
    private(set) var styledLayOutWidths: [Double?] = []

    func reset() {
        plainCalls = []; styledCalls = []; styledMeasureWidths = []; styledLayOutWidths = []
    }

    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { base.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { base.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> TextMeasurement {
        plainCalls.append("measure")
        return base.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        plainCalls.append("placeGlyphs")
        return base.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin,
                                scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        plainCalls.append("caretOffsets")
        return base.caretOffsets(string, font: font)
    }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                    options: TextLayoutOptions) -> [Range<Int>] {
        plainCalls.append("lineRanges")
        return base.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func measure(_ text: StyledText, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> StyledTextMeasurement {
        styledCalls.append("measure")
        styledMeasureWidths.append(width)
        return base.measure(text, wrappingAt: width, options: options)
    }
    func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        styledCalls.append("layOut")
        styledLayOutWidths.append(width)
        return base.layOut(text, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics {
        styledCalls.append("decorationMetrics")
        return base.decorationMetrics(font)
    }
    func rasterize(_ key: GlyphKey) -> GlyphImage { base.rasterize(key) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

private func note(_ message: String) -> Comment { Comment(rawValue: message) }

// MARK: - 2.1

/// **2.1** (`C2`, `C2b`, `C3`, `C3b`, `C12b`; ruling RT-E item 2). Per-run
/// resolved faces and colours: an inner colour, weight or font wins; the
/// concatenation's own modifier reaches only the runs that left it unset.
/// Red before: no `+`. Mutation **M2.1**: `resolveRichText` takes
/// `own.foreground ?? run.foreground` (the outer wins).
@MainActor
@Test func concatenationPushesEachSidesTextFieldsIntoItsUnsetRuns() throws {
    let system = CoreTextTextSystem()
    let environment = EnvironmentValues()
    func key(_ font: Font, weight: Font.Weight? = nil, italic: Bool = false) -> FontKey {
        system.resolveFont(resolveTextStyle(TextStyleRequest(font: .explicit(font), weight: weight, italic: italic),
                                            in: environment).descriptor)
    }
    let colours = rtResolved(rtJoin(Text("ab").foregroundColor(.red), Text("cd")).foregroundColor(.blue), system)
    try #require(colours.paints.count == 2, "two runs: \(colours.paints)")
    #expect(colours.paints.map(\.foreground) == [.red, .blue], "C2: the inner red wins, the outer blue reaches cd")

    let weights = rtResolved(rtJoin(Text("ab").fontWeight(.light), Text("cd")).bold(), system)
    try #require(weights.text.runs.count == 2, "two runs")
    #expect(weights.text.runs[0].style.font == key(.system(size: 13), weight: .light), "C2b: light stays light")
    #expect(weights.text.runs[1].style.font == key(.system(size: 13), weight: .bold), "C2b: the outer bold")

    let fonts = rtResolved(rtJoin(Text("ab").font(.title), Text("cd")).font(.caption), system)
    try #require(fonts.text.runs.count == 2, "two runs")
    #expect(fonts.text.runs[0].style.font == key(.title), "C3: the inner title wins")
    #expect(fonts.text.runs[1].style.font == key(.caption), "C3: the outer caption")

    let italic = rtResolved(rtJoin(Text("ab").bold(), Text("cd")).italic(), system)
    try #require(italic.text.runs.count == 2, "two runs")
    #expect(italic.text.runs[0].style.font == key(.system(size: 13), weight: .bold, italic: true),
            "C3b: a whole-text modifier styles every unset run")
    #expect(italic.text.runs[1].style.font == key(.system(size: 13), italic: true))
}

// MARK: - 2.1b (lane 2 review: the rich fields' values)

/// **2.1b** (ruling RT-E items 2–3; lane 2's review). The `Text`-level rich
/// fields reach the seam with their **values**, at the text's own level and
/// pushed through `+`: `.kerning(2)`, `.tracking(3)` and `.baselineOffset(4)`
/// resolve to those literal `TextRunStyle`s (an inner value wins over the
/// outer one), and `.monospaced()` resolves the system face's monospaced
/// design. Mutations **V5**–**V8** resolve kerning, tracking, baseline offset
/// or monospaced as `0`/`false` in `resolveRichText`.
@MainActor
@Test func theRichFieldsReachTheSeamWithTheirValues() throws {
    let system = CoreTextTextSystem()
    let plain = rtKey(system)
    func styles(_ text: Text) -> [TextRunStyle] { rtResolved(text, system).text.runs.map(\.style) }

    #expect(styles(Text("ab").kerning(2)) == [TextRunStyle(font: plain, kerning: 2)])
    #expect(styles(Text("ab").tracking(3)) == [TextRunStyle(font: plain, tracking: 3)])
    #expect(styles(Text("ab").baselineOffset(4)) == [TextRunStyle(font: plain, baselineOffset: 4)])

    #expect(styles(rtJoin(Text("ab"), Text("cd").kerning(2)))
            == [TextRunStyle(font: plain), TextRunStyle(font: plain, kerning: 2)], "kerning pushed into its run")
    #expect(styles(rtJoin(Text("ab").tracking(1), Text("cd")).tracking(3))
            == [TextRunStyle(font: plain, tracking: 1), TextRunStyle(font: plain, tracking: 3)],
            "the inner tracking wins, the outer reaches cd")
    #expect(styles(rtJoin(Text("ab").baselineOffset(4), Text("cd")))
            == [TextRunStyle(font: plain, baselineOffset: 4), TextRunStyle(font: plain)],
            "baseline offset pushed into its run")

    let monospaced = system.resolveFont(resolveTextStyle(
        TextStyleRequest(font: .explicit(.system(size: 13).monospaced())), in: EnvironmentValues()).descriptor)
    try #require(monospaced != plain, "set up: the monospaced design is its own face")
    #expect(styles(Text("ab").monospaced()) == [TextRunStyle(font: monospaced)])
    #expect(styles(rtJoin(Text("ab").monospaced(), Text("cd")))
            == [TextRunStyle(font: monospaced), TextRunStyle(font: plain)], "monospaced pushed into its run")
}

/// **2.1c** (ruling RT-E item 2; lane 2's review). `underline(false)` is an
/// explicit "none" an outer underline does not reach:
/// `(Text("a").underline(false) + Text("b")).underline()` resolves no
/// underline on "a" and draws **one** underline rect, starting where "b"
/// starts. Mutation **V4**: `underline(false)` stores `nil` (unset).
@MainActor
@Test func underlineFalseIsANoneTheOuterUnderlineDoesNotReach() throws {
    let system = CoreTextTextSystem()
    let text = rtJoin(Text("a").underline(false), Text("b")).underline()
    let resolved = rtResolved(text, system)
    try #require(resolved.paints.count == 2, "two runs: \(resolved.paints)")
    #expect(resolved.paints[0].underline == nil, "a: the explicit none")
    #expect(resolved.paints[1].underline != nil, "b: the outer underline")

    let frame = rtFrame(rtTopLeft(text), system: system)
    let rects = frame.scene.rects
    try #require(frame.scene.glyphs.count == 2, "set up: two glyphs")
    try #require(rects.count == 1, "one underline: \(rects.map(\.bounds))")
    let a = system.measure("a", font: rtKey(system), wrappingAt: nil, options: TextLayoutOptions()).widestLine
    #expect(abs(Double(rects[0].bounds.origin.x) - a) < 1, "the underline starts at b (\(a)): \(rects[0].bounds)")
}

// MARK: - 2.2

/// **2.2** (`C1`). `Text("Abcdefghij").bold() + Text("klm")` answers CoreText's
/// attributed line width, derived here with `CTLineGetTypographicBounds` over
/// the two faces; the element's background box is that width, rounded. Red
/// before: the stub measured the concatenated plain string. Mutation **M2.2**:
/// measure the concatenated plain string in the first run's face.
@MainActor
@Test func aStyledTextMeasuresAsCoreTextsAttributedLine() throws {
    let system = CoreTextTextSystem()
    let bold = rtKey(system, weight: .bold), regular = rtKey(system)
    let boldFont = try #require(system.cache.font(for: bold)), regularFont = try #require(system.cache.font(for: regular))
    let attributed = NSMutableAttributedString(string: "Abcdefghij", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): boldFont.ctFont])
    attributed.append(NSAttributedString(string: "klm", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): regularFont.ctFont]))
    let expected = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    let plainWidth = system.measure("Abcdefghijklm", font: regular, wrappingAt: nil).widestLine
    try #require(abs(expected - plainWidth) > 1, "the bold run must widen the line: \(expected) vs \(plainWidth)")

    let text = rtJoin(Text("Abcdefghij").bold(), Text("klm"))
    let answer = richTextMeasurement(rtResolved(text, system), system: system,
                                     proposal: ProposedSize(width: nil, height: nil))
    #expect(abs(answer.size.width - expected) < 1e-6, "measured \(answer.size.width), CoreText \(expected)")

    let frame = rtFrame(rtTopLeft(text.background(.accent)), system: system)
    let box = try #require(frame.scene.rects.first { rtSame($0.background, frame.resolve(.accentColor)) })
    #expect(Double(box.bounds.size.width) == expected.rounded(),
            "the element's box: \(box.bounds.size.width) vs round(\(expected))")
}

// MARK: - 2.3

/// **2.3** (ruling RT-F item 3). A spy system forwarding to CoreText records
/// the calls: a plain text — even bold, italic, coloured or in another font —
/// reaches only the plain requirements; an underline, `kerning(0)` or two runs
/// reach only the styled ones. Red before: the stub drew everything plain.
/// Mutation **M2.3**: invert the fast path's `kerning` clause.
@MainActor
@Test func aPlainTextTakesThePlainCalls() throws {
    let system = RichTextSpySystem()
    func calls(_ text: Text) -> (plain: Set<String>, styled: Set<String>) {
        system.reset()
        _ = rtFrame(rtTopLeft(text), system: system)
        return (Set(system.plainCalls), Set(system.styledCalls))
    }
    let plainOnes: [(String, Text)] = [
        ("Text(\"a\")", Text("a")),
        ("bold, red, italic", Text("a").bold().foregroundColor(.red).italic()),
        ("font(.title)", Text("a").font(.title)),
        ("one run of two equal texts", rtJoin(Text("a"), Text("b"))),
    ]
    for (name, text) in plainOnes {
        let seen = calls(text)
        #expect(seen.styled.isEmpty && seen.plain.isSuperset(of: ["measure", "placeGlyphs"]),
                note("\(name) takes only the plain calls: \(seen)"))
    }
    let styledOnes: [(String, Text)] = [
        ("underline()", Text("a").underline()),
        ("kerning(0)", Text("a").kerning(0)),
        ("two runs", rtJoin(Text("a").bold(), Text("b"))),
    ]
    for (name, text) in styledOnes {
        let seen = calls(text)
        #expect(seen.plain.isEmpty && seen.styled.isSuperset(of: ["measure", "layOut"]),
                note("\(name) takes only the styled calls: \(seen)"))
    }
}

// MARK: - 2.9

/// **2.9** (ruling RT-F item 5; `RT-R` item 3). A window, two frames of a
/// styled text: the second shapes nothing (`ShapingCache.misses` unmoved),
/// and paint lays out at the width layout answered — the text's widest line,
/// fractional here — not at its rounded box. Red before: the stub drew plain
/// (no styled call). Mutation **M2.9**: paint lays out at the rounded box
/// width (the second arm; the warm-frame arm cannot see it, the rounded width
/// being asked again on the warm frame and hitting).
@MainActor
@Test func aWarmFrameOfAStyledTextShapesNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let system = RichTextSpySystem()
    let text = rtJoin(Text("Count 7 ").bold(), Text("items here")).font(size: 22)
    let answer = system.base.measure(rtResolved(text, system.base).text, wrappingAt: 300,
                                     options: TextLayoutOptions()).widestLine
    try #require(answer != answer.rounded(), "set up: the answer is fractional, so rounding moves it: \(answer)")
    let platformWindow = try FakePlatformWindow(device: device, size: 300)
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false, textSystem: system) {
        rtTopLeft(text)
    }
    window.drawFrameIfNeeded()
    let laidOut = system.styledLayOutWidths.compactMap { $0 }
    try #require(!laidOut.isEmpty, "the styled path drew")
    #expect(laidOut.allSatisfy { $0 == answer }, "paint lays out at the width layout answered: \(laidOut) vs \(answer)")
    let misses = system.base.cache.misses
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(system.base.cache.misses == misses, "a warm frame shapes nothing: \(system.base.cache.misses - misses)")
    withExtendedLifetime(window) {}
}

// MARK: - 2.13

/// **2.13** (ruling RT-L item 1). A styled text publishes its whole
/// concatenated string where a plain one publishes its own; an all-empty
/// concatenation publishes none (`E0`). Green on arrival: the stub's `string`
/// was already the concatenation (the property is computed over the content).
/// Mutation **M2.13**: publish the first run's string.
@MainActor
@Test func aStyledTextPublishesItsConcatenatedString() throws {
    let frame = rtFrame(rtTopLeft(rtJoin(Text("Hello ").bold(), Text("world").foregroundColor(.red))),
                        accessibility: true)
    let texts = frame.axEmissions.compactMap(\.text)
    #expect(texts == ["Hello world"], "the whole string: \(texts)")
    let empty = rtFrame(rtTopLeft(rtJoin(Text("").bold(), Text(""))), accessibility: true)
    #expect(empty.axEmissions.compactMap(\.text).isEmpty, "an empty concatenation is no text")
}

// MARK: - 2.14–2.16 (RT-G)

/// A 10-point line then a 30-point line (`C6`'s shape): `"aa\n"` in 10, `"BB"`
/// in 30, the hard break inside the first run.
@MainActor
private func tenThenThirty() -> Text {
    rtJoin(Text("aa\n").font(size: 10), Text("BB").font(size: 30))
}

/// **2.14** (`C16`, `C16b`; ruling RT-G item 3). A finite height keeps as many
/// leading lines as fit their summed heights: `lh10 + lh30 − 1` keeps one line
/// (`lh10` tall), `lh10 + lh30` keeps two. Red before: the stub capped by the
/// first line's height. Mutations **M2.14a** cap by `⌊h / first line height⌋`
/// (the first arm), **M2.14b** by `⌊h / tallest line height⌋` (the second).
@MainActor
@Test func aMixedTextCapsLinesByTheirSummedHeights() throws {
    let system = CoreTextTextSystem()
    let lh10 = system.fontMetrics(rtKey(system, 10)).lineHeight, lh30 = system.fontMetrics(rtKey(system, 30)).lineHeight
    let resolved = rtResolved(tenThenThirty(), system)
    let open = richTextMeasurement(resolved, system: system, proposal: ProposedSize(width: nil, height: nil))
    try #require(open.size.height == lh10 + lh30, "set up: two lines, \(open.size.height) vs \(lh10) + \(lh30)")
    let short = richTextMeasurement(resolved, system: system,
                                    proposal: ProposedSize(width: nil, height: lh10 + lh30 - 1))
    #expect(short.size.height == lh10, "one line in lh10 + lh30 − 1: \(short.size.height)")
    let exact = richTextMeasurement(resolved, system: system, proposal: ProposedSize(width: nil, height: lh10 + lh30))
    #expect(exact.size.height == lh10 + lh30, "two lines in lh10 + lh30: \(exact.size.height)")
}

/// **2.15** (`C18`; ruling RT-G item 3). `lineLimit(3, reservesSpace: true)`
/// pads with the **first run's** line height: `B30 + a10` is `3 × lh30`,
/// `a10 + B30` is `max(3 × lh10, the mixed line)`. Red before: the stub
/// reserved nothing. Mutation **M2.15**: pad with the tallest line's height.
@MainActor
@Test func reservedSpaceUsesTheFirstRunsLineHeight() throws {
    let system = CoreTextTextSystem()
    var environment = EnvironmentValues()
    environment.textLineLimit = TextLineLimit(min: 3, max: 3)
    let m10 = system.fontMetrics(rtKey(system, 10)), m30 = system.fontMetrics(rtKey(system, 30))
    let mixed = (max(m10.ascent, m30.ascent) + max(m10.descent, m30.descent) + max(m10.leading, m30.leading))
        .rounded(.up)
    let proposal = ProposedSize(width: nil, height: nil)
    let bigFirst = richTextMeasurement(rtResolved(rtJoin(Text("B").font(size: 30), Text("a").font(size: 10)),
                                                  system, environment: environment), system: system, proposal: proposal)
    #expect(bigFirst.size.height == 3 * m30.lineHeight, "B30 + a10: \(bigFirst.size.height) vs 3 × \(m30.lineHeight)")
    let smallFirst = richTextMeasurement(rtResolved(rtJoin(Text("a").font(size: 10), Text("B").font(size: 30)),
                                                    system, environment: environment), system: system, proposal: proposal)
    try #require(3 * m10.lineHeight != 3 * mixed, "the two rules must differ")
    #expect(smallFirst.size.height == max(3 * m10.lineHeight, mixed),
            "a10 + B30: \(smallFirst.size.height) vs max(3 × \(m10.lineHeight), \(mixed))")
}

/// **2.16** (ruling RT-G item 2). A mixed text's baselines come from its
/// lines: first `round(ascent₁)`, last `top(last) + round(ascentₙ)` for the
/// `C6` shape. Red before: the stub used the plain formula. Mutation
/// **M2.16**: `first + (n − 1) × lineHeight₀`.
@MainActor
@Test func aMixedTextReportsBaselinesFromItsLines() throws {
    let system = CoreTextTextSystem()
    let m10 = system.fontMetrics(rtKey(system, 10)), m30 = system.fontMetrics(rtKey(system, 30))
    let answer = richTextMeasurement(rtResolved(tenThenThirty(), system), system: system,
                                     proposal: ProposedSize(width: nil, height: nil))
    #expect(answer.firstBaseline == m10.ascent.rounded(), "first: \(answer.firstBaseline)")
    #expect(answer.lastBaseline == m10.lineHeight + m30.ascent.rounded(), "last: \(answer.lastBaseline)")
}

// MARK: - 2.18

/// **2.18** (ruling RT-K, divergence 150). A link registers nothing a plain
/// text does not: the hitboxes, focus order and accessibility records of a
/// text with a link run equal those of the same text without it. Green on
/// arrival (the pin of an absence). Mutation **M2.18**: register a pointer
/// hitbox per link segment.
@MainActor
@Test func aLinkRegistersNothingAPlainTextDoesNot() throws {
    func frame(link: String?) -> Frame {
        rtFrame(rtTopLeft(Text(content: .runs([TextRunRequest(string: "see "),
                                               TextRunRequest(string: "docs", link: link)]))),
                accessibility: true)
    }
    let linked = frame(link: "https://example.com"), plain = frame(link: nil)
    #expect(linked.hitboxes.count == plain.hitboxes.count, "hitboxes: \(linked.hitboxes.count)")
    #expect(linked.focusRegistry.tabOrder == plain.focusRegistry.tabOrder, "focus order")
    #expect(linked.axEmissions.map(\.text) == plain.axEmissions.map(\.text)
                && linked.axEmissions.map(\.isClickable) == plain.axEmissions.map(\.isClickable),
            "accessibility records: \(linked.axEmissions.map(\.text))")
    #expect(linked.axEmissions.compactMap(\.text) == ["see docs"], "the link is part of the text's string")
}

// MARK: - 2.19

/// The operand whose decoration traps, by case — exit tests capture nothing.
@MainActor
private func concatenateDecorated(_ index: Int) -> Text {
    let decorated: Text = switch index {
    case 0: Text("a").margin(Pixels(2))
    case 1: Text("a").background(.accent)
    case 2: Text("a").onClick {}
    case 3: Text("a").id("x")
    default: Text("a")
    }
    return rtJoin(Text("b").bold(), decorated)
}

/// The decorated operand on the **left** (lane 2's review): `.background`.
@MainActor
private func concatenateDecoratedOnTheLeft() -> Text {
    rtJoin(Text("a").background(.accent), Text("b").bold())
}

/// **2.19** (exit tests; ruling RT-E item 4, divergence 155). Concatenating a
/// text that carries a style (`.margin` — `.padding` returns a
/// `ModifiedElement`, so it cannot be an operand at all, `RT-R` item 2), a
/// decoration (`.background`), a handler (`.onClick`) or an id traps, naming
/// the field; the control — plain operands — exits normally. The left
/// operand is checked too (one arm, `.background` on the left). Mutations
/// **M2.19**: delete the precondition; **V1**: delete the left operand's check.
@Test func concatenatingADecoratedTextTraps() async {
    func check(_ result: ExitTest.Result?, _ field: String, side: String = "right") {
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("the \(side) operand carries \(field)") && stderr.contains("divergence 155"),
                note("arm \(field): aborted, but not at the operand check:\n\(stderr)"))
    }
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = concatenateDecorated(0) }
    }, "style")
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = concatenateDecorated(1) }
    }, "decoration")
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = concatenateDecorated(2) }
    }, "handlers.onClick")
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = concatenateDecorated(3) }
    }, "elementID")
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = concatenateDecoratedOnTheLeft() }
    }, "decoration", side: "left")
    await #expect(processExitsWith: .success) {
        await MainActor.run { _ = concatenateDecorated(99) }
    }
}

// MARK: - 2.20

/// **2.20** (`RT-O` item 1). The operand check reads every `Handlers` member
/// through `Mirror`: every child of `Handlers()` is a recognised kind and
/// there are **19** (`feat/input-apis` added `pointer`, the merge added its
/// arm; `feat/key-focus` added `keyboard`, `KF-I`); setting any one member makes the check name it. Red before: the
/// stub answered "default" for everything. Mutations **M2.20a** drop the
/// optional rule (the optional members' arms), **M2.20b** drop the
/// `Equatable` rule (`isFocusable`, `allowsHitTesting`, `axNode`), **M2.20c**
/// drop the collection rule (`actions`, `gestures`).
@MainActor
@Test func theOperandCheckSeesEveryHandlersMember() throws {
    let children = Array(Mirror(reflecting: Handlers()).children)
    try #require(children.count == 19, "Handlers has \(children.count) members: \(children.map { $0.label ?? "?" })")
    for child in children {
        try #require(mirrorFieldKind(child.value) != .unrecognised,
                     note("\(child.label ?? "?") is a kind the check cannot read"))
    }
    #expect(firstSetHandlersMember(Handlers()) == nil, "the default is default")

    func arm(_ name: String, _ set: (inout Handlers) -> Void) {
        var handlers = Handlers()
        set(&handlers)
        #expect(firstSetHandlersMember(handlers) == name, note("\(name): the check named \(String(describing: firstSetHandlersMember(handlers)))"))
    }
    arm("onClick") { $0.onClick = {} }
    arm("onKey") { $0.onKey = { _ in false } }
    arm("isFocusable") { $0.isFocusable = true }
    arm("actions") { $0.actions = [ObjectIdentifier(Int.self): { _ in }] }
    arm("keyContext") { $0.keyContext = KeyContext("editor") }
    arm("axNode") { $0.axNode.label = "x" }
    arm("allowsHitTesting") { $0.allowsHitTesting = false }
    arm("contentShapeInset") { $0.contentShapeInset = Edges(all: Pixels(1)) }
    arm("textInput") {
        $0.textInput = TextInputTarget(text: "", caretOffsets: [], originX: 0,
                                       caretRect: Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                         size: Size(width: Pixels(0), height: Pixels(0))),
                                       onChange: { _ in }, onSubmit: nil)
    }
    arm("valueTrack") {
        $0.valueTrack = ValueTrackTarget(minX: 0, width: 1, thumb: 0, bounds: 0...1, step: nil, write: { _ in })
    }
    arm("gestures") { $0.gestures = [GestureAttachment(TapGesture(), priority: .normal)] }
    arm("keyboardShortcut") { $0.keyboardShortcut = ShortcutTarget(KeyboardShortcut("a"), action: {}) }
    arm("contentShape") { $0.contentShape = ContentShape(Rectangle()) }
    arm("focusBinding") {
        $0.focusBinding = FocusBindingTarget(state: FocusState<Bool>.Box(defaultValue: false), value: true)
    }
    arm("dropDestination") {
        $0.dropDestination = DropDestinationTarget(String.self, action: { _, _ in false }, isTargeted: { _ in })
    }
    arm("contextual") { $0.contextual = ContextualAttachment(menu: nil, help: "x") }
    arm("hover") { $0.hover = HoverAttachment(onHover: { _ in }, onContinuousHover: nil) }
    arm("pointer") { $0.pointer = PointerAttachment(scrollWheel: nil, style: .rectSelection) }
    arm("keyboard") { $0.keyboard = KeyboardAttachment(isKeyRegion: true) }
}

// MARK: - 2.21

/// The pair-kerned string (`RT-O` item 7) on two centred lines, the first
/// shorter, so the second line's alignment offset is not 0.
private let kernedLines = "To\nAVAVAV To Ty"

/// **2.21** (`RT-F` item 3, `RT-O` item 7). In a window, `Text(s).kerning(0)`
/// — the styled path — draws exactly the glyph primitives `Text(s)` draws:
/// the pair kerning kept, the centred lines offset once. Green on arrival
/// (the stub drew every text plain); it is the pin its mutations need.
/// Mutations **M2.21a** add the first line's alignment offset
/// to the styled origin (offset twice), **M2.21b** lane 1's always-set-kern.
@MainActor
@Test func aOneRunStyledTextDrawsThePlainSprites() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func glyphs(_ text: Text) throws -> [String] {
        let platformWindow = try FakePlatformWindow(device: device, size: 300)
        let window = Window(platformWindow: platformWindow, startsDisplayLink: false) {
            rtTopLeft(text.multilineTextAlignment(.center))
        }
        window.drawFrameIfNeeded()
        defer { withExtendedLifetime(window) {} }
        return window.lastScene.glyphs.map {
            "\($0.bounds.origin.x),\($0.bounds.origin.y),\($0.bounds.size.width),\($0.atlasBounds.origin.x),\($0.atlasBounds.origin.y)"
        }
    }
    let plain = try glyphs(Text(kernedLines))
    try #require(plain.count >= 12, "set up: the text drew its glyphs")
    #expect(try glyphs(Text(kernedLines).kerning(0)) == plain, "kerning(0) draws the plain sprites")
}

// MARK: - 2.22

/// **2.22**. `ProposalText` and `Text` of one styled content draw equal glyphs
/// and rects; so do an outer rich field through `proposalLayout()` and
/// `ProposalText("a").underline()` against `Text("a").underline()` (lane 2's
/// review). Red before: the stub dropped the segments' styles. Mutations
/// **M2.22**: `proposalLayout()` drops `content`; **V3**: it drops `rich`;
/// **V10**: `ProposalText.underline` is a no-op.
@MainActor
@Test func proposalTextDrawsTheSameStyledSpritesAsText() throws {
    let text = rtJoin(Text("ab").foregroundColor(.red), Text("cd").underline(), Text("ef").strikethrough())
    func primitives(_ frame: Frame) -> [String] {
        frame.scene.glyphs.map { "g \($0.bounds.origin.x),\($0.bounds.origin.y) \($0.color.h),\($0.color.l)" }
            + frame.scene.rects.map { "r \($0.bounds.origin.x),\($0.bounds.origin.y),\($0.bounds.size.width),\($0.bounds.size.height)" }
    }
    let legacy = primitives(rtFrame(HStack(spacing: 0) { text }))
    let proposal = primitives(rtFrame(HStack(spacing: 0) { text.proposalLayout() }))
    try #require(legacy.contains { $0.hasPrefix("r ") }, "set up: the decorations drew: \(legacy)")
    #expect(proposal == legacy, "proposal \(proposal)\nlegacy \(legacy)")

    // A Text-level rich field outside the concatenation (lane 2's review):
    // `proposalLayout()` carries `rich` (mutation V3).
    let outer = rtJoin(Text("ab"), Text("cd").bold()).underline()
    let outerLegacy = primitives(rtFrame(HStack(spacing: 0) { outer }))
    try #require(outerLegacy.filter { $0.hasPrefix("r ") }.count == 1, "set up: one underline: \(outerLegacy)")
    #expect(primitives(rtFrame(HStack(spacing: 0) { outer.proposalLayout() })) == outerLegacy,
            "proposalLayout() keeps the outer underline")

    // ProposalText's own rich modifier (mutation V10: a no-op underline).
    let direct = primitives(rtFrame(HStack(spacing: 0) { Text("a").underline() }))
    try #require(direct.contains { $0.hasPrefix("r ") }, "set up: Text(\"a\").underline() drew a rect")
    #expect(primitives(rtFrame(HStack(spacing: 0) { ProposalText("a").underline() })) == direct,
            "ProposalText(\"a\").underline() draws Text's underline")
}

// MARK: - 2.23

/// **2.23** (ruling RT-L item 2). `withAnimation` changing a run's colour: the
/// next frame draws the new colour (it snaps, as a plain text's glyph colour
/// does). Green on arrival (a pin). Mutation **M2.23**: route the run colour
/// through `animatedColor`.
@MainActor
@Test func aRunsColourSnapsUnderAnAnimation() throws {
    let harness = TransitionHarness()
    func text(_ color: Color) -> Text { rtJoin(Text("ab").foregroundColor(color), Text("cd").bold()) }
    harness.frame(0, nil, rtTopLeft(text(.red)))
    let next = harness.frame(0.1, .linear(duration: 1), rtTopLeft(text(.blue)))
    let blue = next.resolve(.blue)
    try #require(next.scene.glyphs.count == 4, "four glyphs")
    #expect(rtSame(next.scene.glyphs[0].color, blue) && rtSame(next.scene.glyphs[1].color, blue),
            "the new colour, at once: \(next.scene.glyphs.map(\.color))")
}

// MARK: - RT-R item 1

/// **RT-R item 1**. A `Text` keeps neighbouring runs that differ only in paint
/// apart at the seam (`StyledText(keepingNeighbours:)`), and both systems lay
/// such a text out exactly as the merged one — same glyphs, same lines — with
/// one segment per run: a ligature (`of|fice`) and a kerning pair (`A|V`)
/// split across the boundary. Red before: the initialiser did not exist.
/// Mutation **M2.R1**: build a `Text`'s styled text with the merging
/// initialiser (2.4 reddens: two colours in one run).
@MainActor
@Test func neighboursThatDifferOnlyInPaintLayOutAsOneRun() throws {
    let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts")
    let noto = try [UInt8](Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let systems: [(String, any TextSystem)] = [("CoreText", CoreTextTextSystem()),
                                               ("portable", PortableTextSystem(resolver: try PortableFontResolver(defaultFont: noto)))]
    for (name, system) in systems {
        let style = TextRunStyle(font: rtKey(system, 20))
        let string = "of" + "fice AV"
        let merged = StyledText(string, style: style)
        let kept = StyledText(keepingNeighbours: string, runs: [StyledTextRun(length: 2, style: style),
                                                                StyledTextRun(length: 6, style: style),
                                                                StyledTextRun(length: 1, style: style)])
        try #require(kept.runs.count == 3, "kept apart")
        for scale: Float in [1, 2] {
            let a = system.layOut(merged, wrappingAt: nil, options: TextLayoutOptions(), origin: (x: 3, y: 5),
                                  scaleFactor: scale)
            let b = system.layOut(kept, wrappingAt: nil, options: TextLayoutOptions(), origin: (x: 3, y: 5),
                                  scaleFactor: scale)
            #expect(a.glyphs.map(\.glyph) == b.glyphs.map(\.glyph), note("\(name) ×\(scale): the same glyphs"))
            #expect(a.measurement == b.measurement, note("\(name) ×\(scale): the same lines"))
            #expect(b.segments.map(\.run) == [0, 1, 2] && a.segments.count == 1,
                    note("\(name) ×\(scale): one segment per run: \(b.segments.map(\.run))"))
        }
    }
}
