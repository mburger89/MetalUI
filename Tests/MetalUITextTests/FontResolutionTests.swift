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

@Test func theKeyDistinguishesSizes() {
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
@Test func metricsMatchCoreText() {
    let f = FontResolver.resolve(family: nil, size: 13)
    #expect(abs(f.metrics.ascent - CTFontGetAscent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.descent - CTFontGetDescent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.leading - CTFontGetLeading(f.ctFont)) < 0.001)
}

/// **§6.2's `opsz` pinning — and the residual §6.2 did not measure.**
///
/// Unpinned, `CTFontCreateUIFontForLanguage(.system, …)` returns a variable font
/// whose optical-size axis *tracks* the point size, so advances stop scaling
/// linearly: §6.2 measured a 28-character label at 13pt = 164.804 and 26pt =
/// 301.703, a ratio of **1.8307** where 2.0 was wanted (−8.5%). This machine
/// reproduces that ratio to four figures — 180.254 and 329.926 → **1.8303** —
/// which is why the string below is §6.2's own 28 characters.
///
/// **The plan's draft asserted `abs(ratio - 2.0) < 0.01` after the pin, and that
/// is not reachable by this mechanism (ruling TX-A).** Measured with the axis
/// pinned: 159.415 and 329.139 → **2.0653**. The pin does what §6.2 says it does
/// — it fixes the *outline instance*, so the optical-size axis stops varying
/// with point size — but a **second, independent mechanism** that §6.2 never
/// measured remains: CoreText grid-fits advances to the pixel grid at small
/// ppem. Three measurements identify it and rule the axis out:
///
/// 1. With `opsz` pinned, advance-per-point converges to the *unhinted* value
///    `CGFont` reports (12.4268) at ≥96pt and wobbles below it — 12.263 at 13pt,
///    11.743 at 18pt, 12.782 at 32pt.
/// 2. Helvetica, which carries no such hinting, is **exactly** linear at 13, 26
///    and 52pt — with no variation axes to pin.
/// 3. Resolving at one reference size and carrying the target size in the font
///    *matrix* — which is what fixes the ppem — is exactly linear (176.122 /
///    352.244 = 2.000000). That is a different font model from the one §6.2
///    decided on and from the one the rest of M2 is written against, so it is
///    reported rather than taken.
///
/// So the test asserts what the pin actually buys, and the first expectation is
/// a **positive control**: if Apple ever ships a system font that is already
/// linear, the trap this whole mechanism exists for is gone and this test says
/// so, rather than passing for a reason that no longer exists.
@Test func pinningOpszRemovesTheOpticalSizeAxisFromAdvanceScaling() {
    let text = "The quick brown fox jumps ov"   // 28 characters, per §6.2
    func advance(_ f: CTFont) -> Double {
        let attr = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: f]
        )
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attr),
                                          nil, nil, nil)
    }

    let unpinned = advance(CTFontCreateUIFontForLanguage(.system, 26, nil)!)
                 / advance(CTFontCreateUIFontForLanguage(.system, 13, nil)!)
    let pinned = advance(FontResolver.resolve(family: nil, size: 26).ctFont)
               / advance(FontResolver.resolve(family: nil, size: 13).ctFont)

    // The trap is still here (measured 1.8303, error 0.1697).
    #expect(abs(unpinned - 2.0) > 0.15)
    // The pin more than halves the error (measured 2.0653, error 0.0653). This
    // is the scale-free half: it fails the moment the resolver stops pinning,
    // because then `pinned` and `unpinned` are the same number.
    #expect(abs(pinned - 2.0) < abs(unpinned - 2.0) / 2)
    // …and bounds the residual, so a regression that pins the wrong axis or the
    // wrong value cannot hide behind the comparison above.
    #expect(abs(pinned - 2.0) < 0.10)
}
