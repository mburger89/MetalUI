import CoreText
import Foundation

extension FontKey {
    /// Reads the identity **out of** a resolved `CTFont` — the only way to make
    /// a key (see ``FontKey``). The struct lives in `MetalUIScene`, which
    /// imports no CoreText; reading the font stays here (ruling PS-D).
    public init(resolved font: CTFont) {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        let size = Double(CTFontGetSize(font))

        let coordinates = (CTFontCopyVariation(font) as? [NSNumber: NSNumber]) ?? [:]
        let variations = coordinates
            .map { VariationCoordinate(axis: $0.key.intValue, value: $0.value.doubleValue) }
            .sorted { $0.axis < $1.axis }

        let m = CTFontGetMatrix(font)
        let matrix = Matrix(a: Double(m.a), b: Double(m.b), c: Double(m.c),
                            d: Double(m.d), tx: Double(m.tx), ty: Double(m.ty))

        self.init(resolvedPostScriptName: postScriptName, size: size,
                  variations: variations, matrix: matrix)
    }
}

/// A font's vertical metrics, in points, exactly as CoreText reports them.
///
/// All three are positive magnitudes, matching `CTFontGetAscent` /
/// `CTFontGetDescent` / `CTFontGetLeading` — note that CoreText's descent is
/// already positive, unlike the negative descent some font formats store.
public struct FontMetrics: Hashable, Sendable {
    public let ascent: Double
    public let descent: Double
    public let leading: Double

    /// The distance from one baseline to the next.
    ///
    /// **Rounded up to a whole point** — `ceil(ascent + descent + leading)`,
    /// not the raw sum. A human looked at the M2 demo and reported the leading
    /// tight against typical Mac apps; measured against
    /// `NSLayoutManager.defaultLineHeight` on the **same font instance**
    /// (verified by PostScript name, so this is not a font-resolution
    /// difference), the platform lays text out taller than
    /// `ascent + descent + leading` says. `CTFontGetLeading` is **0.0000 at
    /// every size measured** below, so this is not about leading at all — it is
    /// that the platform does not lay out at exactly `ascent + descent`:
    ///
    /// | pt | `ascent+descent+leading` | `NSLayoutManager.defaultLineHeight` |
    /// |---|---|---|
    /// | 11 | 12.9551 | 13 |
    /// | 12 | 14.1328 | 15 |
    /// | 13 | 15.3105 | **16** |
    /// | 14 | 16.4883 | 17 |
    /// | 15 | 17.6660 | 18 |
    /// | 16 | 18.8438 | 18 |
    /// | 17 | 20.0215 | 20 |
    /// | 22 | 25.9102 | 26 |
    ///
    /// `ceil` matches the platform at 11, 12, 13, 14, 15 and 22, and **misses
    /// only 16 and 17** — the two sizes where `NSLayoutManager` returns *less*
    /// than the font's own ascent+descent. That is the platform's oddity rather
    /// than a rule to chase: `round` would fix 13 (15.3105 rounds to 15, not
    /// 16 — the wrong direction) while doing nothing for 16 or 17, so it is not
    /// a closer general answer, only a different accident.
    ///
    /// **The reason that matters more than matching a number: pixel alignment.**
    /// A fractional line height puts every line after the first on a fractional
    /// baseline, so each line's glyphs rasterize at a different subpixel phase
    /// — line 1 sharp, line 2 soft, cycling with no period any layout controls.
    /// A whole-point line height keeps every baseline pixel-aligned at 1x and
    /// even-pixel-aligned at 2x. This is very likely *why* the platform rounds,
    /// and it is a crispness argument that would hold even where the table
    /// above disagrees with `NSLayoutManager`.
    ///
    /// **Only the line-to-line advance is rounded — `ascent` and `descent`
    /// themselves are not.** Glyph placement *within* a line depends on the true
    /// ascent; rounding it would shift glyphs against their own baseline rather
    /// than only changing how far apart baselines are.
    ///
    /// **Task 1 said "no caller and no assertion"; Task 2 gave it a caller and
    /// then wrote a false claim about the assertion, which is worth keeping as
    /// the warning.** ``ShapedText/totalHeight`` is `lines.count ×` this, per
    /// spec §3.4, so the caller half is now true. The assertion half was not:
    /// Task 2's comment named the two shaping tests that compare `totalHeight`
    /// against `lineHeight` and said dropping a term here would redden them.
    /// **They cannot see it.** Both spell the expectation
    /// `abs(shaped.totalHeight - font.metrics.lineHeight) < 0.001` — this
    /// property is on *both* sides, so it moves the expectation and the
    /// implementation together. Measured: `{ ascent }` alone left the whole
    /// suite green at 371 tests. That is the same defect Task 2 had just fixed
    /// nine lines away in `noWrappedLineExceedsTheOfferedWidthUnlessItIsUnbreakable`
    /// — **an oracle that is the code under test** — reappearing in a doc
    /// comment written under a shape-10 banner.
    ///
    /// The pin is now `metricsMatchCoreText`, which adds CoreText's three
    /// numbers up itself and applies the same `ceil`, rather than asking this
    /// property to. Text measurement is a second consumer, not the first.
    public var lineHeight: Double { ceil(ascent + descent + leading) }

    public init(ascent: Double, descent: Double, leading: Double) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    public init(of font: CTFont) {
        self.init(ascent: Double(CTFontGetAscent(font)),
                  descent: Double(CTFontGetDescent(font)),
                  leading: Double(CTFontGetLeading(font)))
    }
}
