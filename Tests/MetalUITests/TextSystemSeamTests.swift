import CoreText
import Foundation
import Testing
import MetalUIPortableText
@testable import MetalUI
@testable import MetalUIText

// TS-A…TS-D: `Text` and `ProposalText` measure and draw through the frame's
// `TextSystem`. The same tree rendered through the CoreText system and the
// portable one — both on Noto Sans, registered with CoreText for the process
// and handed to the portable resolver as its default — puts the same sprites
// in the scene: every glyph's rect, and every text box's layout.

private let notoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

@MainActor
private func portableSystem() throws -> PortableTextSystem {
    PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: notoURL))))
}

/// Every glyph sprite of `frame`, as whole-pixel rects in paint order.
@MainActor
private func sprites(_ frame: Frame) -> [[Float]] {
    frame.finalizedScene().glyphs.map {
        [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height]
    }
}

@MainActor
private func render<E: Element>(_ make: () -> E, system: any TextSystem, scale: Float) -> Frame {
    let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: scale,
                      textSystem: system)
    var root = make()
    frame.render(&root)
    return frame
}

/// Several `Text`s — one wrapping over four lines, one with kerning pairs, one
/// with a hard break — in a legacy column, at scale 1 and 2.
@MainActor
private func legacyTree() -> some Element {
    Column {
        Text("The quick brown fox jumps over the lazy dog, twice over.")
            .font(family: "Noto Sans", size: 17).frame(width: Pixels(150))
        Text("Kerning AV To Ty").font(family: "Noto Sans", size: 13)
        Text("Ready\nSet").font(family: "NotoSans-Regular", size: 22)
    }.alignItems(.flexStart)
}

@MainActor
@Test func theCoreTextAndPortableSystemsDrawTheSameSprites() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    for scale: Float in [1, 2] {
        let apple = sprites(render(legacyTree, system: CoreTextTextSystem(), scale: scale))
        let portable = sprites(render(legacyTree, system: try portableSystem(), scale: scale))
        try #require(apple.count > 60, "the tree must draw text at scale \(scale)")
        #expect(portable == apple, "scale \(scale): \(portable.count) portable sprites vs \(apple.count)")
    }
}

@MainActor
private func proposalTree() -> some Element {
    VStack(alignment: .leading) {
        ProposalText("A proposal text that wraps at the width it is offered here.")
            .font(family: "Noto Sans", size: 15)
        ProposalText("AV To").font(family: "Noto Sans", size: 26)
    }.frame(width: Pixels(180))
}

/// The same, through `ProposalText` under a native root — the other element
/// that measures and draws through the seam.
@MainActor
@Test func proposalTextDrawsTheSameSpritesThroughEitherSystem() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let apple = sprites(render(proposalTree, system: CoreTextTextSystem(), scale: 2))
    let portable = sprites(render(proposalTree, system: try portableSystem(), scale: 2))
    try #require(apple.count > 40)
    #expect(portable == apple)
}

/// Without a text system, a frame uses CoreText over the cache it was given —
/// so every test that inspects a frame's `ShapingCache` still sees it filled.
@MainActor
@Test func aFrameWithoutATextSystemUsesCoreTextOverItsOwnCache() {
    let cache = ShapingCache()
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                      shapingCache: cache)
    let system = frame.textSystem as? CoreTextTextSystem
    #expect(system?.cache === cache)
    var root = Text("fills the cache")
    frame.render(&root)
    #expect(cache.storageCount > 0)
}

/// The portable system draws the frame, not CoreText: with its default face
/// Source Sans 3 and every request unmatched, the sprites differ from the
/// Noto Sans ones — so the equality above is not both frames quietly using
/// the same engine.
@MainActor
@Test func thePortableSystemIsTheOneThatDraws() throws {
    let sourceURL = notoURL.deletingLastPathComponent().appendingPathComponent("SourceSans3-Regular.otf")
    let source = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: sourceURL))))
    let noto = sprites(render(legacyTree, system: try portableSystem(), scale: 1))
    let sourceSprites = sprites(render(legacyTree, system: source, scale: 1))
    try #require(!noto.isEmpty && !sourceSprites.isEmpty)
    #expect(noto != sourceSprites)
}

/// A frame given the portable system never shapes through CoreText, in either
/// phase: the CoreText cache it also holds stays empty. Equal sprites alone
/// could not show this — with Noto Sans registered in both engines, a `Text`
/// that measured through one and drew through the other would look the same.
///
/// **The positive control** (stage 9, `LR-FE`): the same tree, the same kind
/// of cache, through the CoreText system fills that cache — so the empty
/// cache below is the portable system's doing, not an instrument that counts
/// nothing. Until stage 9 the test looped over both layout authorities (and
/// read the min-content memo too, deleted with tokenizer min-content,
/// `LR-FD`); neither arm read a non-zero count, so the loop carried no
/// control. Red once with the control frame given the portable system
/// (record §51).
@MainActor
@Test func aPortableFrameNeverShapesThroughCoreText() throws {
    let controlCache = ShapingCache()
    let control = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: 2,
                        shapingCache: controlCache, textSystem: CoreTextTextSystem(cache: controlCache))
    var controlRoot = legacyTree()
    control.render(&controlRoot)
    try #require(control.finalizedScene().glyphs.count > 60)
    #expect(controlCache.storageCount > 0, "control: the CoreText system shapes into the cache")

    do {
        let cache = ShapingCache()
        let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: 2,
                          shapingCache: cache, textSystem: try portableSystem())
        var root = legacyTree()
        frame.render(&root)
        try #require(frame.finalizedScene().glyphs.count > 60)
        #expect(cache.storageCount == 0)
    }
    // And `ProposalText`, the other element on the seam.
    let cache = ShapingCache()
    let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: 2,
                      shapingCache: cache, textSystem: try portableSystem())
    var root = proposalTree()
    frame.render(&root)
    try #require(frame.finalizedScene().glyphs.count > 40)
    #expect(cache.storageCount == 0, "ProposalText")
}

/// TI-H: both systems' `lineRanges` forward to the wrapping the line-breaking
/// oracle already pins equal (13,464 cases) — here, through the seam itself,
/// the two systems break the same strings at the same widths into the same
/// UTF-16 ranges, hard breaks included, and a wrapped editor's lines follow.
@MainActor
@Test func bothSystemsBreakLinesAtTheSameRanges() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let apple = CoreTextTextSystem(), portable = try portableSystem()
    let strings = ["", "one line", "first\nsecond\n", "a much longer paragraph that has to wrap across lines",
                   "tab\tand  two spaces\nthen a café and naïve text", "\n\n"]
    var compared = 0
    for string in strings {
        for width: Double? in [nil, 40, 90, 200] {
            let a = apple.lineRanges(string, font: apple.resolveFont(family: "Noto Sans", size: 13), wrappingAt: width)
            let p = portable.lineRanges(string, font: portable.resolveFont(family: nil, size: 13), wrappingAt: width)
            #expect(a == p, "\(string.debugDescription) at \(String(describing: width))")
            #expect(a.first?.lowerBound == 0 && a.last?.upperBound == string.utf16.count
                    || (string.isEmpty && a == [0..<0]), "ranges cover the string")
            compared += 1
        }
    }
    try #require(compared == 24)
    // A width forces more than one line, and hard breaks are kept in the range.
    let wrapped = portable.lineRanges("a much longer paragraph that has to wrap across lines",
                                      font: portable.resolveFont(family: nil, size: 13), wrappingAt: 90)
    #expect(wrapped.count > 2)
    #expect(portable.lineRanges("ab\ncd", font: portable.resolveFont(family: nil, size: 13), wrappingAt: nil)
            == [0..<3, 3..<5])
}

// MARK: - TE-C, TE-T: layout options and metrics through both systems
// (plan task 11 part 1, lane 1; spec rows 1.6–1.10). Each arm runs the same
// request through `CoreTextTextSystem` (CoreText's truncated line) and
// `PortableTextSystem` on Noto Sans and requires the same answer — and, where
// the arm names a behaviour, that the CoreText answer IS that behaviour, read
// by an instrument independent of the seam (a `CTLine` built here).

/// Both systems on Noto Sans at `size`, with the fonts each resolves.
@MainActor
private func seamPair(size: Double = 13) throws
    -> (apple: CoreTextTextSystem, appleFont: FontKey, portable: PortableTextSystem, portableFont: FontKey) {
    let apple = CoreTextTextSystem(), portable = try portableSystem()
    return (apple, apple.resolveFont(family: "Noto Sans", size: size),
            portable, portable.resolveFont(family: nil, size: size))
}

/// The glyph ids CoreText draws for `string` on one line in Noto Sans at 13 —
/// or, with `truncatedAt`, for `CTLineCreateTruncatedLine` of it with a `…`
/// token — read straight from CoreText, not through the seam.
@MainActor
private func coreTextGlyphIDs(_ string: String, truncatedAt width: Double? = nil,
                              mode: CTLineTruncationType = .end) throws -> [CGGlyph] {
    let font = CTFontCreateWithName("NotoSans-Regular" as CFString, 13, nil)
    func line(_ s: String) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(
            string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }
    var drawn = line(string)
    if let width {
        drawn = try #require(CTLineCreateTruncatedLine(drawn, width, mode, line("\u{2026}")))
    }
    var ids: [CGGlyph] = []
    for run in CTLineGetGlyphRuns(drawn) as! [CTRun] {
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        ids += glyphs
    }
    return ids
}

private let ctModes: [(TextTruncation, CTLineTruncationType)] = [(.tail, .end), (.head, .start), (.middle, .middle)]

/// **1.6** (X8). Past the limit, the kept lines stand and the rest of the
/// string from the last kept line's start is truncated as ONE line at the
/// wrap width — here line 2 is exactly CoreText's truncated line of "gamma
/// delta epsilon zeta eta theta" at 100, in every mode, and the portable
/// system places the same glyphs. Mutation **M1g** (truncate line n−1's own
/// text only) keeps "gamma delta " and reddens the id comparison.
@MainActor
@Test func theDroppedLinesAreTruncatedAsOneLineAfterTheKeptOnes() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    let text = "Alpha beta gamma delta epsilon zeta eta theta"
    let untruncated = apple.placeGlyphs(text, font: appleFont, wrappingAt: 100, origin: (0, 0), scaleFactor: 1)
    for (mode, ct) in ctModes {
        let options = TextLayoutOptions(maxLines: 2, truncation: mode)
        let a = apple.placeGlyphs(text, font: appleFont, wrappingAt: 100, options: options, origin: (0, 0), scaleFactor: 1)
        let p = portable.placeGlyphs(text, font: portableFont, wrappingAt: 100, options: options,
                                     origin: (0, 0), scaleFactor: 1)
        #expect(p == a, "\(mode): the systems agree")
        let baselines = Array(Set(a.map(\.baselineY))).sorted()
        try #require(baselines.count == 2, "\(mode): two lines drawn, not \(baselines.count)")
        let line1 = a.filter { $0.baselineY == baselines[0] }.map(\.key.glyph)
        let line2 = a.filter { $0.baselineY == baselines[1] }.map(\.key.glyph)
        #expect(line1 == (try coreTextGlyphIDs("Alpha beta ")), "\(mode): line 1 is kept whole")
        #expect(line2 == (try coreTextGlyphIDs("gamma delta epsilon zeta eta theta", truncatedAt: 100, mode: ct)),
                "\(mode): line 2 is the rest truncated as one line")
        #expect(a.count < untruncated.count, "\(mode): text is dropped")
        #expect(apple.lineRanges(text, font: appleFont, wrappingAt: 100, options: options) == [0..<11, 11..<45])
        #expect(portable.lineRanges(text, font: portableFont, wrappingAt: 100, options: options) == [0..<11, 11..<45])
        // TE-H item 3: a limit below 1 acts as 1, at the seam itself, on both
        // systems (without the clamp, `lines[maxLines - 1]` traps at 0).
        let one = apple.placeGlyphs(text, font: appleFont, wrappingAt: 100,
                                    options: TextLayoutOptions(maxLines: 1, truncation: mode),
                                    origin: (0, 0), scaleFactor: 1)
        try #require(Set(one.map(\.baselineY)).count == 1)
        for below in [0, -1] {
            let clamped = TextLayoutOptions(maxLines: below, truncation: mode)
            #expect(apple.placeGlyphs(text, font: appleFont, wrappingAt: 100, options: clamped,
                                      origin: (0, 0), scaleFactor: 1) == one, "\(mode) maxLines \(below): CoreText")
            #expect(portable.placeGlyphs(text, font: portableFont, wrappingAt: 100, options: clamped,
                                         origin: (0, 0), scaleFactor: 1) == one, "\(mode) maxLines \(below): portable")
            #expect(apple.lineRanges(text, font: appleFont, wrappingAt: 100, options: clamped) == [0..<45])
            #expect(portable.lineRanges(text, font: portableFont, wrappingAt: 100, options: clamped) == [0..<45])
            #expect(apple.measure(text, font: appleFont, wrappingAt: 100, options: clamped)
                    == apple.measure(text, font: appleFont, wrappingAt: 100,
                                     options: TextLayoutOptions(maxLines: 1, truncation: mode)))
            #expect(portable.measure(text, font: portableFont, wrappingAt: 100, options: clamped)
                    == portable.measure(text, font: portableFont, wrappingAt: 100,
                                        options: TextLayoutOptions(maxLines: 1, truncation: mode)))
        }
    }
}

/// **1.6b** (TE-T, probe `swiftui-truncation-edges.swift` E1, E2, E4). With a
/// hard break in the rest, the last kept line is the rest's first paragraph:
/// in tail mode it takes a token whenever text follows, even when it fits
/// ("Set…", and "Ready…" at one line); in head and middle mode a paragraph
/// that fits is drawn whole ("Set"); a paragraph that overflows is CoreText's
/// truncated line of the paragraph alone. Both systems agree.
@MainActor
@Test func aHardBreakEndsTheTruncatedLineAtItsParagraph() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    func lastLine(_ text: String, _ options: TextLayoutOptions) -> [CGGlyph] {
        let a = apple.placeGlyphs(text, font: appleFont, wrappingAt: 100, options: options, origin: (0, 0), scaleFactor: 1)
        let p = portable.placeGlyphs(text, font: portableFont, wrappingAt: 100, options: options,
                                     origin: (0, 0), scaleFactor: 1)
        #expect(p == a, "\(text.debugDescription) \(options): the systems agree")
        let last = a.map(\.baselineY).max()
        return a.filter { $0.baselineY == last }.map(\.key.glyph)
    }
    let ellipsis = try coreTextGlyphIDs("\u{2026}")
    for (mode, ct) in ctModes {
        let two = TextLayoutOptions(maxLines: 2, truncation: mode)
        let set = try coreTextGlyphIDs("Set")
        #expect(lastLine("Ready\nSet\nGo", two) == (mode == .tail ? set + ellipsis : set), "E1 \(mode)")
        let para = "gamma delta epsilon zeta eta theta"
        #expect(lastLine("Alpha beta \(para)\nmore", two) == (try coreTextGlyphIDs(para, truncatedAt: 100, mode: ct)),
                "E4 \(mode)")
    }
    #expect(lastLine("Ready\nSet\nGo", TextLayoutOptions(maxLines: 1)) == (try coreTextGlyphIDs("Ready")) + ellipsis,
            "E1 one line")
    // E5: an EMPTY paragraph as the last kept line takes no token in any
    // mode, even with text after it — SwiftUI draws "A" alone for "A\n\nB" at
    // lineLimit(2), and nothing for "\nB\nC" at lineLimit(1) (0 px; the
    // token's reading 54 px off).
    let lineHeight = apple.fontMetrics(appleFont).lineHeight
    // "A\n" drawn alone: the hard break draws the space glyph (`drawnGlyph`).
    let a = apple.placeGlyphs("A\n", font: appleFont, wrappingAt: 100, origin: (0, 0), scaleFactor: 1).map(\.key.glyph)
    try #require(a.first == (try coreTextGlyphIDs("A")).first)
    let aWidth = apple.measure("A", font: appleFont, wrappingAt: nil).widestLine
    try #require(aWidth > 5)
    for (mode, _) in ctModes {
        for (text, maxLines, glyphs, widest) in [("A\n\nB", 2, a, aWidth), ("\nB\nC", 1, [], 0.0)] {
            let options = TextLayoutOptions(maxLines: maxLines, truncation: mode)
            let drawn = apple.placeGlyphs(text, font: appleFont, wrappingAt: 100, options: options,
                                          origin: (0, 0), scaleFactor: 1)
            #expect(drawn.map(\.key.glyph) == glyphs, "E5 \(text.debugDescription) \(mode): CoreText")
            #expect(portable.placeGlyphs(text, font: portableFont, wrappingAt: 100, options: options,
                                         origin: (0, 0), scaleFactor: 1) == drawn,
                    "E5 \(text.debugDescription) \(mode): the systems agree")
            let expected = TextMeasurement(widestLine: widest, totalHeight: Double(maxLines) * lineHeight)
            #expect(apple.measure(text, font: appleFont, wrappingAt: 100, options: options) == expected,
                    "E5 \(text.debugDescription) \(mode): CoreText measure")
            #expect(portable.measure(text, font: portableFont, wrappingAt: 100, options: options) == expected,
                    "E5 \(text.debugDescription) \(mode): portable measure")
        }
    }
}

/// **1.6c** (TE-T, E3). Narrower than the token, CoreText's truncation has no
/// answer; the line keeps the longest prefix of whole clusters that fits, at
/// least one, and no token — "H" at 10 and, overflowing, at 4. Both systems.
@MainActor
@Test func aWidthNarrowerThanTheTokenKeepsTheLongestPrefixThatFits() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    let h = try coreTextGlyphIDs("H")
    for mode in [TextTruncation.tail, .head, .middle] {
        for width in [4.0, 10] {
            let options = TextLayoutOptions(maxLines: 1, truncation: mode)
            let a = apple.placeGlyphs("Hello", font: appleFont, wrappingAt: width, options: options,
                                      origin: (0, 0), scaleFactor: 1)
            let p = portable.placeGlyphs("Hello", font: portableFont, wrappingAt: width, options: options,
                                         origin: (0, 0), scaleFactor: 1)
            #expect(a.map(\.key.glyph) == h, "\(mode) at \(width)")
            #expect(p == a, "\(mode) at \(width): the systems agree")
        }
    }
}

/// **1.7.** A line limit, each truncation mode and each alignment, through
/// `placeGlyphs` at scales 1 and 2: the same glyphs on both systems.
/// Separated: alignment moves the glyphs (a centred layout differs from a
/// leading one), and a limit changes them. Mutation **M1h** (portable
/// alignment factor 0) reddens the equality for every centred and trailing
/// case.
///
/// **One case is a subpixel tie, ruled by TE-U and pinned**: CoreText moves
/// the glyphs after a middle token as a run, the portable path walks their
/// pens, and the two sums differ in the last bit; at scale 1 one pen lands
/// on an exact variant boundary (59.625 against 59.624999999999996 device
/// pixels) and rounds a quarter pixel apart. Every other glyph of all 864
/// cases is identical.
private func sameGlyphsBarAVariantTie(_ a: [TextGlyph], _ p: [TextGlyph]) -> (same: Bool, ties: Int) {
    guard a.count == p.count else { return (false, 0) }
    var ties = 0
    for (x, y) in zip(a, p) where x != y {
        let step = (x.pixelX * 4 + x.key.subpixelVariant) - (y.pixelX * 4 + y.key.subpixelVariant)
        guard abs(step) == 1, x.key.glyph == y.key.glyph, x.key.font == y.key.font, x.baselineY == y.baselineY
        else { return (false, ties) }
        ties += 1
    }
    return (true, ties)
}

@MainActor
@Test func theSeamsLayoutOptionsPlaceTheSameGlyphsOnBothSystems() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair(size: 15)
    let strings = ["The quick brown fox jumps over the lazy dog, twice over.", "Kerning AV To Ty\nReady\nSet",
                   "  spaced  words  "]
    var compared = 0, moved = 0, limited = 0
    var tied: [String] = []
    for scale: Float in [1, 2] {
        for string in strings {
            for width: Double? in [nil, 60, 100, 150] {
                let plain = apple.placeGlyphs(string, font: appleFont, wrappingAt: width,
                                              origin: (3.3, 7.6), scaleFactor: scale)
                for maxLines: Int? in [nil, 1, 2, 3] {
                    for mode in [TextTruncation.tail, .head, .middle] {
                        for alignment in [TextLineAlignment.leading, .center, .trailing] {
                            let options = TextLayoutOptions(maxLines: maxLines, truncation: mode, alignment: alignment)
                            let a = apple.placeGlyphs(string, font: appleFont, wrappingAt: width, options: options,
                                                      origin: (3.3, 7.6), scaleFactor: scale)
                            let p = portable.placeGlyphs(string, font: portableFont, wrappingAt: width,
                                                         options: options, origin: (3.3, 7.6), scaleFactor: scale)
                            try #require(!a.isEmpty)
                            let label = "\(string.debugDescription) w=\(String(describing: width)) \(options) ×\(scale)"
                            let (same, ties) = sameGlyphsBarAVariantTie(a, p)
                            #expect(same, "\(label)")
                            if ties > 0 { tied.append("\(label): \(ties)") }
                            compared += 1
                            if alignment != .leading, a != apple.placeGlyphs(
                                string, font: appleFont, wrappingAt: width,
                                options: TextLayoutOptions(maxLines: maxLines, truncation: mode),
                                origin: (3.3, 7.6), scaleFactor: scale) { moved += 1 }
                            if alignment == .leading, a != plain { limited += 1 }
                        }
                    }
                }
            }
        }
    }
    try #require(compared == 2 * 3 * 4 * 4 * 3 * 3)
    #expect(tied.count == 1 && tied.first?.hasPrefix("\"The quick") == true
            && tied.first?.contains("middle") == true && tied.first?.hasSuffix("×1.0: 1") == true,
            "TE-U pins one variant tie; measured \(tied)")
    #expect(moved > compared / 3, "alignment moves glyphs: \(moved)")
    #expect(limited > compared / 10, "a limit changes glyphs: \(limited)")
}

/// **1.8.** `fontMetrics` answers the same metrics on both systems, and they
/// are the metrics the layout already uses: CoreText's `FontMetrics` for the
/// resolved face. Mutation **M1i** (portable `lineHeight` rounded to nearest)
/// reddens 11 pt and 17 pt.
@MainActor
@Test func theSeamsMetricsAgreeOnBothSystems() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    for size in [11.0, 13, 17, 26] {
        let (apple, appleFont, portable, portableFont) = try seamPair(size: size)
        let a = apple.fontMetrics(appleFont), p = portable.fontMetrics(portableFont)
        let direct = FontResolver.resolve(family: "Noto Sans", size: size).metrics
        #expect(a == TextFontMetrics(ascent: direct.ascent, descent: direct.descent, leading: direct.leading,
                                     lineHeight: direct.lineHeight), "\(size): CoreText's own metrics")
        #expect(p.lineHeight == a.lineHeight, "\(size) lineHeight")
        #expect(abs(p.ascent - a.ascent) < 1e-5 && abs(p.descent - a.descent) < 1e-5
                && abs(p.leading - a.leading) < 1e-5, "\(size): \(p) vs \(a)")
        #expect(p.ascent.rounded() == a.ascent.rounded(), "\(size): the baseline an element derives")
        try #require(a.lineHeight > size)
    }
}

/// **1.9** (L4). At an unspecified width there is nothing to fit a token to:
/// the kept lines are simply cut — the same glyphs as the text that ends
/// there, no `…` — and the ranges are the kept lines'. Mutation **M1j** (a
/// token at a `nil` width) reddens it.
@MainActor
@Test func anUnspecifiedWidthCutsKeptLinesWithoutAnEllipsis() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    let options = TextLayoutOptions(maxLines: 2)
    let a = apple.placeGlyphs("A\nB\nC", font: appleFont, wrappingAt: nil, options: options, origin: (0, 0), scaleFactor: 1)
    let cut = apple.placeGlyphs("A\nB\n", font: appleFont, wrappingAt: nil, origin: (0, 0), scaleFactor: 1)
    try #require(!cut.isEmpty)
    #expect(a == cut)
    #expect(!a.map(\.key.glyph).contains(try coreTextGlyphIDs("\u{2026}")[0]))
    #expect(portable.placeGlyphs("A\nB\nC", font: portableFont, wrappingAt: nil, options: options,
                                 origin: (0, 0), scaleFactor: 1) == a)
    #expect(apple.lineRanges("A\nB\nC", font: appleFont, wrappingAt: nil, options: options) == [0..<2, 2..<4])
    #expect(portable.lineRanges("A\nB\nC", font: portableFont, wrappingAt: nil, options: options) == [0..<2, 2..<4])
}

/// **1.10.** `measure` answers the widest KEPT line (the truncated one
/// included) and `kept × lineHeight` — not the widest of every line. Here the
/// dropped line is the widest. Mutation **M1k** (widest over every line)
/// reddens it.
@MainActor
@Test func measureAnswersTheWidestKeptLine() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    let lineHeight = apple.fontMetrics(appleFont).lineHeight
    try #require(lineHeight > 13)
    // Unwrapped: "Hi\n" is kept, the wide line dropped.
    let text = "Hi\nA much longer line than the first"
    let hi = apple.measure("Hi\n", font: appleFont, wrappingAt: nil)
    let wide = apple.measure(text, font: appleFont, wrappingAt: nil)
    try #require(wide.widestLine > hi.widestLine + 50)
    let one = TextLayoutOptions(maxLines: 1)
    #expect(apple.measure(text, font: appleFont, wrappingAt: nil, options: one)
            == TextMeasurement(widestLine: hi.widestLine, totalHeight: lineHeight))
    #expect(portable.measure(text, font: portableFont, wrappingAt: nil, options: one)
            == apple.measure(text, font: appleFont, wrappingAt: nil, options: one))
    // Wrapped at 80: two kept lines, the second truncated; it fits the width.
    let paragraph = "Alpha beta gamma delta epsilon zeta eta theta"
    let two = TextLayoutOptions(maxLines: 2)
    let a = apple.measure(paragraph, font: appleFont, wrappingAt: 80, options: two)
    #expect(a.totalHeight == 2 * lineHeight)
    #expect(a.widestLine <= 80 && a.widestLine > 60, "\(a)")
    #expect(portable.measure(paragraph, font: portableFont, wrappingAt: 80, options: two) == a)
    // The options are part of each system's measurement cache key: one
    // system asked for the same string and width under two sets of options,
    // in either order, answers each set's own measurement — never the
    // other's cached one.
    let unlimited = apple.measure(paragraph, font: appleFont, wrappingAt: 80)
    let limited = apple.measure(paragraph, font: appleFont, wrappingAt: 80, options: one)
    try #require(unlimited != limited)
    for limitedFirst in [false, true] {
        let fresh = try portableSystem()
        let font = fresh.resolveFont(family: nil, size: 13)
        let order: [TextLayoutOptions] = limitedFirst ? [one, TextLayoutOptions()] : [TextLayoutOptions(), one]
        for options in order {
            #expect(fresh.measure(paragraph, font: font, wrappingAt: 80, options: options)
                    == (options == one ? limited : unlimited), "portable, limited first: \(limitedFirst), \(options)")
        }
        let freshApple = CoreTextTextSystem()
        let appleKey = freshApple.resolveFont(family: "Noto Sans", size: 13)
        for options in order {
            #expect(freshApple.measure(paragraph, font: appleKey, wrappingAt: 80, options: options)
                    == (options == one ? limited : unlimited), "CoreText, limited first: \(limitedFirst), \(options)")
        }
    }
}

/// **1.7b** (TE-J, A5). Alignment against an instrument independent of both
/// systems: line 1 of "Alpha beta gamma …" at 100 is "Alpha beta ", ending in
/// a space; centred it moves by `(100 − (L − T)) / 2` and trailing by `100 −
/// (L − T)`, `L` and `T` read from a `CTLine` built here
/// (`CTLineGetTypographicBounds`, `CTLineGetTrailingWhitespaceWidth`), on the
/// 1/256 pt grid (TE-U item 6). At scale 64 a 1/256 pt step is exactly one
/// quarter-pixel variant, so the shift is read exactly off the placed glyphs.
/// Separated: counting the trailing space (`100 − L`) is a different number.
@MainActor
@Test func aLineIsAlignedByItsWidthWithoutItsTrailingWhitespace() throws {
    CTFontManagerRegisterFontsForURL(notoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(notoURL as CFURL, .process, nil) }
    let (apple, appleFont, portable, portableFont) = try seamPair()
    let text = "Alpha beta gamma delta epsilon zeta eta theta"
    let font = CTFontCreateWithName("NotoSans-Regular" as CFString, 13, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: "Alpha beta ", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
    let trailing = CTLineGetTrailingWhitespaceWidth(line)
    try #require(trailing > 1, "the line ends in whitespace")
    func quarters(_ points: Double) -> Int { Int((points * 256).rounded()) }
    try #require(apple.lineRanges(text, font: appleFont, wrappingAt: 100).first == 0..<11)
    for system in [(apple as any TextSystem, appleFont), (portable, portableFont)] {
        func firstGlyph(_ alignment: TextLineAlignment) -> Int {
            let placed = system.0.placeGlyphs(text, font: system.1, wrappingAt: 100,
                                              options: TextLayoutOptions(alignment: alignment),
                                              origin: (0, 0), scaleFactor: 64)
            return placed[0].pixelX * 4 + placed[0].key.subpixelVariant
        }
        let leading = firstGlyph(.leading)
        let name = system.0 is CoreTextTextSystem ? "CoreText" : "portable"
        #expect(firstGlyph(.trailing) - leading == quarters(100 - (advance - trailing)), "\(name) trailing")
        #expect(firstGlyph(.center) - leading == quarters((100 - (advance - trailing)) / 2), "\(name) centre")
        #expect(firstGlyph(.trailing) - leading != quarters(100 - advance), "\(name): the space is left out")
    }
}
