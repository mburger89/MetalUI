import CoreText
import Foundation
import Testing
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 (spec rows 3.16, 3.17; rulings TE-I, TE-C
// item 3): `.truncationMode` reaches the seam through the element, on both
// text systems.

/// **3.16. PINNED — divergence 87** (ruling TE-I). "Hello, wonderful world" at
/// 13 pt, one line, width 100, middle: the `Text` keeps what CoreText's
/// `CTLineCreateTruncatedLine(.middle)` keeps (85.12 wide, X5), where SwiftUI
/// keeps more (97.5). The CoreText line is built in the test, outside the seam.
///
/// Mutation **M3o**: the middle split widened.
@MainActor
@Test func aMiddleTruncationKeepsCoreTextsStringWhereSwiftUIKeepsMore() throws {
    let s = "Hello, wonderful world"
    let ctFont = FontResolver.resolve(family: nil, size: 13).ctFont
    func line(_ string: String) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(
            string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]))
    }
    let token = line("\u{2026}")
    let truncated = try #require(CTLineCreateTruncatedLine(line(s), 100, .middle, token))
    let coreText = CTLineGetTypographicBounds(truncated, nil, nil, nil)
    try #require(abs(coreText - 85.12) < 0.5, "X5's CoreText width: \(coreText)")
    try #require(abs(coreText - 97.5) > 5, "separates from SwiftUI's 97.5")
    let b = try teBounds([0, 0, 0]) {
        Text(s).lineLimit(1).truncationMode(.middle).frame(width: Pixels(100), alignment: .leading)
    }
    #expect(b.size.width.value == Float(coreText.rounded()), "kept CoreText's \(coreText), drew \(b.size.width.value)")
    #expect(b.size.height.value == teLineHeight())
}

/// The tree 3.17 renders: Noto Sans 15 in a 150-wide frame.
@MainActor
private func truncatedTree(limit: Int?, mode: Text.TruncationMode) -> some Element {
    Column {
        Text("The quick brown fox jumps over the lazy dog, twice over and once more.")
            .font(family: "Noto Sans", size: 15)
            .lineLimit(limit)
            .truncationMode(mode)
            .frame(width: Pixels(150), alignment: .leading)
    }.alignItems(.flexStart)
}

/// **3.17.** A truncated `Text` draws the same sprites through either text
/// system — `lineLimit(1)` and `(2)` in every mode, on Noto Sans registered
/// with CoreText and given to the portable resolver — and draws fewer glyphs
/// than untruncated (`#require`d, so an instrument that dropped the options
/// could not pass).
///
/// Mutation **M3p**: the options not passed at paint.
@MainActor
@Test func aTruncatedTextDrawsTheSameSpritesThroughEitherSystem() throws {
    CTFontManagerRegisterFontsForURL(teNotoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(teNotoURL as CFURL, .process, nil) }
    func sprites(_ system: any TextSystem, limit: Int?, mode: Text.TruncationMode) -> [[Float]] {
        let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(300)), scaleFactor: 2,
                          textSystem: system)
        var root = truncatedTree(limit: limit, mode: mode)
        frame.render(&root)
        return teSprites(frame)
    }
    let untruncated = sprites(CoreTextTextSystem(), limit: nil, mode: .tail)
    try #require(untruncated.count > 50)
    for limit in [1, 2] {
        for mode in [Text.TruncationMode.tail, .head, .middle] {
            let apple = sprites(CoreTextTextSystem(), limit: limit, mode: mode)
            let portable = sprites(try tePortableSystem(), limit: limit, mode: mode)
            try #require(apple.count < untruncated.count - 10, "\(limit) \(mode): the text is truncated")
            #expect(portable == apple, "\(limit) \(mode): \(portable.count) portable sprites vs \(apple.count)")
        }
    }
}
