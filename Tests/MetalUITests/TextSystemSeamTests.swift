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
private func render<E: Element>(_ make: () -> E, system: any TextSystem, scale: Float,
                                authority: LayoutAuthority = Frame.defaultLayoutAuthority) -> Frame {
    let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: scale,
                      textSystem: system, layoutAuthority: authority)
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
            .font(family: "Noto Sans", size: 17).width(Pixels(150))
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
/// phase or either authority: the CoreText cache it also holds stays empty.
/// Equal sprites alone could not show this — with Noto Sans registered in
/// both engines, a `Text` that measured through one and drew through the
/// other would look the same.
@MainActor
@Test func aPortableFrameNeverShapesThroughCoreText() throws {
    for authority in [LayoutAuthority.legacy, .proposal] {
        let cache = ShapingCache()
        let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(600)), scaleFactor: 2,
                          shapingCache: cache, textSystem: try portableSystem(),
                          layoutAuthority: authority)
        var root = legacyTree()
        frame.render(&root)
        try #require(frame.finalizedScene().glyphs.count > 60)
        #expect(cache.storageCount == 0, "\(authority)")
        #expect(cache.minContentCount == 0, "\(authority)")
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
