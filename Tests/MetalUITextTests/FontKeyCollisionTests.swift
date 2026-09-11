import CoreText
import Foundation
import Testing
@testable import MetalUIText

/// **Pinned wrong on purpose: `FontKey` does not identify a font's shaping
/// behaviour, so `ShapingCache` serves one request's shape to another.**
///
/// `FontKey` reads four components back off the resolved `CTFont` —
/// PostScript name, size, variation coordinates, matrix. Two public requests
/// agree on all four and still disagree on how text shapes:
/// `resolve(family: nil, size: 13)` (the UI font, whose descriptor carries
/// CoreText's UI-usage attribute) and `resolve(family: "System Font", size: 13)`
/// (a named font, whose descriptor carries a font name instead) both read back
/// as `.SFNS-Regular` at 13pt with `opsz` 17 and an identity matrix, are not
/// `CFEqual`, and shape Latin identically but Arabic, Devanagari, CJK and emoji
/// to different widths (all five probed standalone; this test measures the
/// Arabic arm in-tree). `Text(s)` and `Text(s).font(family: "System Font",
/// size: 13)` reach exactly these two requests.
///
/// So under one key the **first** `shaped` call's `CTLine` is served to both,
/// and `font(for:)` returns the **last** registration. Nothing in `Sources/`
/// spells `"System Font"`, so no production path collides today; the scope is
/// one requestable name, and only characters outside the resolved face. The
/// comments this pins are `ShapingCache.fonts`'s and `registerFont(_:)`'s.
///
/// **What reddening means, by assertion.** The two `#require`s are the
/// premise: if either fails, CoreText on this OS no longer produces the
/// collision and the comments above overclaim in the other direction — revisit
/// them rather than re-pick a string. The `// PINNED WRONG` expectation is the
/// defect: it reddens when the cache stops sharing one entry between the two
/// fonts, which is the fix, and whoever lands it inverts that line.
@MainActor
@Test func twoRequestsWithEqualFontKeysShareOneShapeThoughTheyShapeDifferently() throws {
    let arabic = "مرحبا بالعالم"
    let uiFont = FontResolver.resolve(family: nil, size: 13)
    let named = FontResolver.resolve(family: "System Font", size: 13)

    try #require(uiFont.key == named.key,
                 "the UI font and \"System Font\" no longer share a FontKey on this OS")
    #expect(!CFEqual(uiFont.ctFont, named.ctFont))

    // The oracle is the uncached shaper, and its two arms must DISAGREE, or the
    // shared-entry assertion below could not tell one font's shape from the other's.
    let uncachedUI = Shaper.shape(arabic, font: uiFont, wrappingAt: nil).widestLine
    let uncachedNamed = Shaper.shape(arabic, font: named, wrappingAt: nil).widestLine
    try #require(uncachedUI != uncachedNamed,
                 "the two fonts now shape Arabic identically: \(uncachedUI)")

    let cache = ShapingCache()
    cache.beginFrame()
    let first = cache.shaped(arabic, font: uiFont, wrappingAt: nil).widestLine
    let second = cache.shaped(arabic, font: named, wrappingAt: nil).widestLine
    cache.endFrame()

    #expect(first == uncachedUI)
    // PINNED WRONG: the correct answer is `uncachedNamed`. The second request
    // is handed the first request's shape.
    #expect(second == uncachedUI)
    #expect(cache.misses == 1)
    #expect(cache.hits == 1)

    // Last registration wins `fonts`: a lookup by the shared key now returns the
    // named font, including to a caller that registered the UI font.
    let served = try #require(cache.font(for: uiFont.key))
    #expect(CFEqual(served.ctFont, named.ctFont))
}
