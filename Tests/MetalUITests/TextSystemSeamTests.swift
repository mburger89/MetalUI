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
