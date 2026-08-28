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
@Test func metricsMatchCoreText() {
    let f = FontResolver.resolve(family: nil, size: 13)
    #expect(abs(f.metrics.ascent - CTFontGetAscent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.descent - CTFontGetDescent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.leading - CTFontGetLeading(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.lineHeight
                - Double(CTFontGetAscent(f.ctFont) + CTFontGetDescent(f.ctFont)
                         + CTFontGetLeading(f.ctFont))) < 0.001)
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
