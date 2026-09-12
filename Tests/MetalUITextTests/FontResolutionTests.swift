import Foundation
import Testing
import CoreText
@testable import MetalUIText

/// **§6.1's measured trap.** Requesting `"SFMono-Regular"` by name on the target
/// machine returned a font whose PostScript name is `Helvetica`. A key built
/// from the requested name would serve one font's glyphs for another's.
@Test func theKeyComesFromTheRESOLVEDFontNotTheRequestedName() {
    let mono = FontResolver.resolve(family: "SFMono-Regular", size: 13)
    let helv = FontResolver.resolve(family: "Helvetica", size: 13)
    let resolvedMonoName = CTFontCopyPostScriptName(mono.ctFont) as String
    let resolvedHelvName = CTFontCopyPostScriptName(helv.ctFont) as String

    // Whatever the platform resolved these to, the KEY must follow the
    // resolution, not the request: same resolved font ⇒ same key, and a
    // different resolved font ⇒ a different key.
    if resolvedMonoName == resolvedHelvName {
        #expect(mono.key == helv.key)
    } else {
        #expect(mono.key != helv.key)
    }
}

/// Two sizes of one face must not share a key — glyph images are rasterized at
/// the size, so a shared key serves 13pt images for 26pt text.
///
/// **The non-variable face leads because the system font stopped being able to
/// pin `size`, and that is a consequence of ruling TX-C worth recording.** With
/// no axis pinned, the system font resolves with `opsz` = `clamp(size, 17, 96)`
/// — 17 at 13pt, 26 at 26pt — so its two keys differ in ``FontKey/variations``
/// *as well as* in ``FontKey/size``, and the size component is no longer what
/// separates them. Measured under TX-C, with the system font as the only case
/// here: `self.size = 0` in `FontKey.init(resolved:)` left the **whole suite
/// green**. Helvetica carries no variation axes, so name, variations and matrix
/// are equal across the two and `size` is the only component left that can
/// separate them — which is what makes the mutation redden again.
@Test func theKeyDistinguishesSizes() {
    let small = FontResolver.resolve(family: "Helvetica", size: 13).key
    let large = FontResolver.resolve(family: "Helvetica", size: 26).key
    #expect(small.postScriptName == large.postScriptName)   // same face …
    #expect(small.variations == large.variations)           // … no axes to move …
    #expect(small.matrix == large.matrix)                   // … same matrix …
    #expect(small.size != large.size)                       // … only the size …
    #expect(small != large)                                 // … so different keys.

    // And the production case, which no longer isolates `size` but is what the
    // shaping and atlas caches will actually be handed.
    #expect(FontResolver.resolve(family: nil, size: 13).key
            != FontResolver.resolve(family: nil, size: 26).key)
}

/// The two ``FontKey`` components that neither of the tests above can see.
///
/// ``FontKey/postScriptName`` is pinned by
/// `theKeyComesFromTheRESOLVEDFontNotTheRequestedName` and ``FontKey/size`` by
/// `theKeyDistinguishesSizes`; without this test ``FontKey/variations`` and
/// ``FontKey/matrix`` could both be deleted with the suite green, which is
/// taxonomy shape 4 — a field that is live but unread.
///
/// **Both differentials are real on this machine, not hypothetical.** A `wght`
/// 400 and a `wght` 700 instance of the system font report the *same*
/// PostScript name (`.SFNS-Regular`), the same size and the same identity
/// matrix, so `variations` is the only component that can tell them apart. The
/// skewed font likewise differs from its upright original in nothing but the
/// matrix. Each half asserts the components that are equal as well as the key
/// that differs, so it cannot pass through the wrong component.
@Test func everyComponentOfTheFontKeyDiscriminates() {
    let base = CTFontCreateUIFontForLanguage(.system, 13, nil)!

    func varying(_ axis: Int, _ value: Double) -> CTFont {
        var coordinates = (CTFontCopyVariation(base) as? [NSNumber: NSNumber]) ?? [:]
        coordinates[NSNumber(value: axis)] = NSNumber(value: value)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontVariationAttribute: coordinates] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, 13, nil)
    }

    let wght = 0x7767_6874  // 'wght'
    let regular = FontKey(resolved: varying(wght, 400))
    let bold = FontKey(resolved: varying(wght, 700))
    #expect(regular.postScriptName == bold.postScriptName)   // same name …
    #expect(regular.size == bold.size)                       // … same size …
    #expect(regular.matrix == bold.matrix)                   // … same matrix …
    #expect(regular.variations != bold.variations)           // … different axes …
    #expect(regular != bold)                                 // … so different keys.

    var skew = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
    let upright = FontKey(resolved: base)
    let oblique = FontKey(resolved: CTFontCreateCopyWithAttributes(base, 13, &skew, nil))
    #expect(upright.postScriptName == oblique.postScriptName)
    #expect(upright.size == oblique.size)
    #expect(upright.variations == oblique.variations)
    #expect(upright.matrix != oblique.matrix)
    #expect(upright != oblique)
}

/// Metrics come from CoreText, not from us. This asserts we report what it says.
///
/// **The `lineHeight` expectation needs an oracle that is not `lineHeight`, and
/// the version added by M2 Task 2 did not have one.** Both shaping tests spell
/// their assertion `abs(shaped.totalHeight - font.metrics.lineHeight) < 0.001`,
/// which puts the property on **both sides**: any change to its formula moves
/// the expectation along with the implementation. Measured —
/// `public var lineHeight: Double { ascent }` left the **whole suite green at
/// 371 tests**. The three stored properties above are each pinned individually,
/// but nothing pinned their *sum*, which is the composition every measured text
/// height is built from. The line below is the independent oracle: CoreText's
/// three numbers, added up here rather than in the property under test.
///
/// **`lineHeight` rounds up to a whole point (line-height rounding), so the
/// oracle rounds too — computed from CoreText directly, never from `metrics`,
/// or this would be shape 12 (the oracle is the code under test) by
/// construction.** Ascent/descent/leading stay unrounded, exactly as
/// `FontMetrics` reports them; only the summed line height is `ceil`'d, here
/// with `Foundation.ceil` rather than `.rounded(.up)` on the property, so a
/// mutation to *either* implementation of the rounding is still caught by an
/// independently-computed value.
@Test func metricsMatchCoreText() {
    let f = FontResolver.resolve(family: nil, size: 13)
    #expect(abs(f.metrics.ascent - CTFontGetAscent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.descent - CTFontGetDescent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.leading - CTFontGetLeading(f.ctFont)) < 0.001)
    let oracleLineHeight = ceil(Double(CTFontGetAscent(f.ctFont) + CTFontGetDescent(f.ctFont)
                                       + CTFontGetLeading(f.ctFont)))
    #expect(abs(f.metrics.lineHeight - oracleLineHeight) < 0.001)
}

// **`pinningOpszRemovesTheOpticalSizeAxisFromAdvanceScaling` was DELETED here,
// not rewritten (ruling TX-C), and a deletion is unusual enough in this repo to
// owe a reason.** The test asserted that pinning the `opsz` axis moves the
// 13pt→26pt advance ratio most of the way to 2.0. That was true — and it pinned
// a property M2 neither uses nor obtains. Does not use: every M2 surface is
// 8–17pt, where the unpinned axis is already constant at 17 by CoreText's own
// `clamp(size, 17, 96)`, so nothing on those surfaces scales between two optical
// sizes. Does not obtain: even pinned, advances are not proportional to point
// size, because a hinting-driven adjustment quantized in design units remains.
// Rewriting it would have kept a green assertion about a mechanism no longer in
// the code. The requirement it was reaching for is M5's, and it now lives as a
// requirement — with its measurements — at `FontResolver.resolve`.

// MARK: - The precomputed hash

/// **Hashing a `FontKey` feeds one `Int`.** Every `GlyphAtlas` lookup hashes a
/// `GlyphKey`, which hashes its `FontKey`; a synthesized `hash(into:)` walks the
/// PostScript name, the variation array and six matrix `Double`s on every one of
/// them. The key's components are fixed at `init(resolved:)`, its only
/// initialiser, so the hash is computed there once and `hash(into:)` combines
/// only that.
///
/// The oracle is a `Hasher` fed the stored `Int` by this test, not the key's
/// own `hash(into:)`: a `hash(into:)` that combined anything besides the stored
/// value — the components as well, say — would disagree with it.
@Test func aFontKeyHashesOnlyItsPrecomputedHash() throws {
    for size in [13.0, 26.0] {
        let key = FontResolver.resolve(family: nil, size: size).key
        let stored = Mirror(reflecting: key).children
            .first { $0.label == "precomputedHash" }?.value as? Int
        let precomputed = try #require(stored,
            "FontKey stores no precomputed hash, so every lookup re-hashes its components")
        var oracle = Hasher()
        oracle.combine(precomputed)
        #expect(key.hashValue == oracle.finalize())
    }
}

/// **The precomputed hash still sees every component.** `==` settles a
/// collision correctly whatever the hash does, so a hash that dropped a
/// component would redden no equality test anywhere — it would silently put
/// every `wght` instance of the system font, or every oblique of a face, in one
/// bucket. This pins the hash itself, on the same two differentials
/// `everyComponentOfTheFontKeyDiscriminates` uses, plus size and name.
@Test func theFontKeyHashItselfDistinguishesEveryComponent() {
    let base = CTFontCreateUIFontForLanguage(.system, 13, nil)!
    func varying(_ axis: Int, _ value: Double) -> CTFont {
        var coordinates = (CTFontCopyVariation(base) as? [NSNumber: NSNumber]) ?? [:]
        coordinates[NSNumber(value: axis)] = NSNumber(value: value)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontVariationAttribute: coordinates] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, 13, nil)
    }
    let wght = 0x7767_6874  // 'wght'
    var skew = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)

    let regular = FontKey(resolved: varying(wght, 400))
    let bold = FontKey(resolved: varying(wght, 700))
    let upright = FontKey(resolved: base)
    let oblique = FontKey(resolved: CTFontCreateCopyWithAttributes(base, 13, &skew, nil))
    let helvetica13 = FontResolver.resolve(family: "Helvetica", size: 13).key
    let helvetica26 = FontResolver.resolve(family: "Helvetica", size: 26).key
    let courier13 = FontResolver.resolve(family: "Courier", size: 13).key

    #expect(regular.hashValue != bold.hashValue)            // variations
    #expect(upright.hashValue != oblique.hashValue)         // matrix
    #expect(helvetica13.hashValue != helvetica26.hashValue) // size
    #expect(helvetica13.postScriptName != courier13.postScriptName)
    #expect(helvetica13.hashValue != courier13.hashValue)   // name

    // And equal keys resolved separately hash equally — `Hashable`'s contract,
    // which a hash seeded from anything per-instance would break.
    #expect(FontResolver.resolve(family: nil, size: 13).key.hashValue
            == FontResolver.resolve(family: nil, size: 13).key.hashValue)
}

/// **`==` settles a hash collision on the components, never on the hash** —
/// the half of the precomputed hash that no ordinary test can reach.
///
/// `FontKey` stores its hash and `==` uses it as an early reject. That pair is
/// `GlobalElementID`'s, and CLAUDE.md records it as safe alone and unsafe
/// together. Measured on this change, whole suite: with a real hash, an `==`
/// that answered with the stored hash alone, or that skipped any one of the four
/// component comparisons, reddened this test and no other — including
/// `everyComponentOfTheFontKeyDiscriminates` and
/// `everyComponentOfTheGlyphKeyDiscriminates`, which stayed green. Keys that
/// differ already hash differently, so the early reject gives the right answer
/// for the wrong reason. `GlobalElementID` records that spelling as
/// unguardable, because `Hasher` is seeded per process and a collision cannot be
/// written down.
///
/// A `FontKey` collision can be forged instead of found. The stored hash is a
/// trivial `Int` at a fixed offset, so for each component this takes a pair of
/// keys that differ in that component alone and copies the first key's hash
/// into the second. The pair then collides by construction, and only the
/// component comparison can tell them apart. The `#require`s make each pair
/// differ, and prove the collision real, before anything is asserted about it.
@Test func aForgedHashCollisionIsSettledByTheComponents() throws {
    let base = CTFontCreateUIFontForLanguage(.system, 13, nil)!
    func varying(_ axis: Int, _ value: Double) -> CTFont {
        var coordinates = (CTFontCopyVariation(base) as? [NSNumber: NSNumber]) ?? [:]
        coordinates[NSNumber(value: axis)] = NSNumber(value: value)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontVariationAttribute: coordinates] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, 13, nil)
    }
    let wght = 0x7767_6874  // 'wght'
    var skew = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
    let helvetica13 = FontResolver.resolve(family: "Helvetica", size: 13).key

    // Each pair differs in exactly the named component.
    let pairs: [(component: String, first: FontKey, second: FontKey)] = [
        ("variations", FontKey(resolved: varying(wght, 400)), FontKey(resolved: varying(wght, 700))),
        ("matrix", FontKey(resolved: base),
         FontKey(resolved: CTFontCreateCopyWithAttributes(base, 13, &skew, nil))),
        ("size", helvetica13, FontResolver.resolve(family: "Helvetica", size: 26).key),
        ("postScriptName", helvetica13, FontResolver.resolve(family: "Courier", size: 13).key),
    ]
    let offset = try #require(MemoryLayout<FontKey>.offset(of: \FontKey.precomputedHash))

    for (component, first, second) in pairs {
        try #require(first.postScriptName != second.postScriptName
                     || first.size != second.size
                     || first.variations != second.variations
                     || first.matrix != second.matrix,
                     "\(component): the pair does not differ")
        try #require(first.hashValue != second.hashValue, "\(component): already collides")

        var forged = second
        withUnsafeMutableBytes(of: &forged) {
            $0.storeBytes(of: first.precomputedHash, toByteOffset: offset, as: Int.self)
        }
        try #require(forged.hashValue == first.hashValue, "\(component): the forgery did not collide")

        #expect(forged != first, "\(component): == answered from the hash")
        #expect(Set([first, forged]).count == 2, "\(component): one Set entry for two keys")

        // And through `GlyphKey`, which is what the atlas is keyed on.
        let a = GlyphKey(font: first, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
        let b = GlyphKey(font: forged, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
        #expect(a != b, "\(component): GlyphKey == answered from the font's hash")
    }
}
