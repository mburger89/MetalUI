import CoreText
import Foundation
import Testing
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 fix round (spec rows 3.13b, 3.13c, 3.17b;
// rulings TE-H item 2, TE-I, TE-AA item 4): what a `ProposalText` DRAWS under
// a line limit, a truncation mode and a height cap, and what a `Text` draws
// under a height cap — on both text systems. `ProposalText.paint` is a copy of
// `Text.paintGlyphs`' option derivation; before this file only the `Text` copy
// was pinned by a drawing test (M3p2, X2 and X1 reddened nothing but the
// demo-frame hash).

private let fox = "The quick brown fox jumps over the lazy dog, twice over and once more."

/// Every glyph sprite `root` draws through `system`, at scale 2, in a 420 × 300
/// frame.
@MainActor
private func sprites<E: Element>(_ system: any TextSystem, _ root: E) -> [[Float]] {
    let frame = Frame(contentSize: Size(width: Pixels(420), height: Pixels(300)), scaleFactor: 2,
                      textSystem: system)
    var root = root
    frame.render(&root)
    return teSprites(frame)
}

/// Runs `body` with Noto Sans registered with CoreText, so both systems draw
/// the same face.
@MainActor
private func withNoto(_ body: @MainActor () throws -> Void) rethrows {
    CTFontManagerRegisterFontsForURL(teNotoURL as CFURL, .process, nil)
    defer { CTFontManagerUnregisterFontsForURL(teNotoURL as CFURL, .process, nil) }
    try body()
}

@MainActor
private func bothSystems() throws -> [(String, any TextSystem)] {
    [("CoreText", CoreTextTextSystem()), ("portable", try tePortableSystem())]
}

/// **3.17b.** 3.17's arm for `ProposalText`: `lineLimit(1)` and `(2)` in every
/// mode draw the same sprites through either system, and fewer glyphs than the
/// same tree unlimited (`#require`d on both systems).
///
/// Mutation **M3p2**: `ProposalText.paint` passes `TextLayoutOptions()`.
@MainActor
@Test func aTruncatedProposalTextDrawsTheSameSpritesThroughEitherSystem() throws {
    try withNoto {
        @MainActor func tree(limit: Int?, mode: Text.TruncationMode) -> some Element {
            Column {
                VStack(alignment: .leading) {
                    ProposalText(fox).font(family: "Noto Sans", size: 15)
                }
                .lineLimit(limit)
                .truncationMode(mode)
                .frame(width: Pixels(150), alignment: .leading)
            }.alignItems(.flexStart)
        }
        let untruncated = sprites(CoreTextTextSystem(), tree(limit: nil, mode: .tail))
        let untruncatedPortable = sprites(try tePortableSystem(), tree(limit: nil, mode: .tail))
        try #require(untruncated.count > 50)
        try #require(untruncatedPortable == untruncated, "the unlimited tree agrees across systems")
        for limit in [1, 2] {
            for mode in [Text.TruncationMode.tail, .head, .middle] {
                let apple = sprites(CoreTextTextSystem(), tree(limit: limit, mode: mode))
                let portable = sprites(try tePortableSystem(), tree(limit: limit, mode: mode))
                try #require(apple.count < untruncated.count - 10, "\(limit) \(mode): CoreText truncated")
                try #require(portable.count < untruncated.count - 10, "\(limit) \(mode): portable truncated")
                #expect(portable == apple, "\(limit) \(mode): \(portable.count) portable sprites vs \(apple.count)")
            }
        }
    }
}

/// **3.13b.** A `Text` placed in a box shorter than its natural height draws
/// the capped lines (`TE-AA` item 4: paint re-derives the cap from the placed
/// box), on both systems: its sprites equal the same tree's under an explicit
/// `lineLimit` of `max(1, ⌊h / lineHeight⌋)`, and are fewer than the uncapped
/// tree's.
///
/// Mutation **X1**: `Text.paint`'s `textLines` given `height: nil`.
@MainActor
@Test func aHeightCappedTextDrawsOnlyTheLinesItsBoxHolds() throws {
    try withNoto {
        for (name, system) in try bothSystems() {
            let lh = system.fontMetrics(system.resolveFont(family: "Noto Sans", size: 13)).lineHeight
            let height = Float(2.5 * lh)
            @MainActor func tree(_ h: Float, limit: Int?) -> some Element {
                Column {
                    Text(fox).font(family: "Noto Sans", size: 13).lineLimit(limit)
                        .frame(width: Pixels(100), height: Pixels(h), alignment: .top)
                }.alignItems(.flexStart)
            }
            let capped = sprites(system, tree(height, limit: nil))
            let limited = sprites(system, tree(height, limit: 2))
            let uncapped = sprites(system, tree(290, limit: nil))
            try #require(uncapped.count > capped.count + 10, "\(name): the paragraph is taller than 2.5 lines")
            #expect(capped == limited, "\(name): \(capped.count) capped sprites vs \(limited.count) at lineLimit(2)")
        }
    }
}

/// **3.13c.** The same for `ProposalText`, in 3.23's K2 tree
/// (`VStack(spacing: 0) { ProposalText; 40-tall block }` 100 wide), where the
/// stack serves the text a share shorter than its natural height: it draws
/// what the same tree under `lineLimit(n)` draws, n its placed lines, on both
/// systems, and fewer than the stack given room.
///
/// Mutation **X2**: `ProposalText.paint`'s `textLines` given `height: nil`.
@MainActor
@Test func aHeightCappedProposalTextDrawsOnlyTheLinesItsBoxHolds() throws {
    try withNoto {
        for (name, system) in try bothSystems() {
            let lh = system.fontMetrics(system.resolveFont(family: "Noto Sans", size: 13)).lineHeight
            let height = Float(40 + 2.5 * lh)
            @MainActor func tree(_ h: Float, limit: Int?) -> some Element {
                Column {
                    VStack(spacing: Pixels(0)) {
                        ProposalText(fox).font(family: "Noto Sans", size: 13)
                        Rectangle(width: Pixels(100), height: Pixels(40), color: .accent)
                    }
                    .lineLimit(limit)
                    .frame(width: Pixels(100), height: Pixels(h), alignment: .top)
                }.alignItems(.flexStart)
            }
            let capped = sprites(system, tree(height, limit: nil))
            let limited = sprites(system, tree(height, limit: 2))
            let roomy = sprites(system, tree(290, limit: nil))
            try #require(roomy.count > capped.count + 10, "\(name): the stack caps the text")
            #expect(capped == limited, "\(name): \(capped.count) capped sprites vs \(limited.count) at lineLimit(2)")
        }
    }
}
