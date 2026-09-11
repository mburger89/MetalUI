import CoreText
import Foundation

/// The identity of a **resolved** font: what an atlas, a shaping cache or a
/// metrics cache may safely be keyed on (spec §6.1).
///
/// **Every component is read back off the `CTFont` CoreText handed us, never
/// off the request, and §6.1 measured why.** `CTFontCreateWithName` does not
/// fail on a name it cannot find — it *substitutes*. Requesting
/// `"SFMono-Regular"` by name on this machine returns a font whose PostScript
/// name is `Helvetica` — as does `"NoSuchFontXYZ"`. A key built from the
/// requested family would therefore hand out one font's glyph images for
/// another font's outlines.
///
/// **What would and would not catch that, by mechanism.** The substituted font
/// measures, shapes and lays out perfectly well, so the wrongness is confined to
/// *which glyph image* is served — and no test in this repo renders a glyph and
/// compares it: the layout corpus contains no text fixture, its WebKit oracle
/// covers boxes rather than glyphs, and the ABI probe skips without a Metal
/// device. So no *rendered* evidence exists. The key itself is a different
/// matter and is directly testable:
/// `theKeyComesFromTheRESOLVEDFontNotTheRequestedName` reddens when the key is
/// built from the request, which was measured by mutation rather than assumed.
///
/// The four components, and what each one alone would let collide:
///
/// - ``postScriptName`` — *which face* was actually resolved. This is the
///   component §6.1 is about.
/// - ``size`` — a `CTFont` carries its point size, and glyph images are
///   rasterized at it. Without this, 13pt and 26pt of one face share a key.
/// - ``variations`` — the resolved variation coordinates
///   (`CTFontCopyVariation`). Two `CTFont`s can share a PostScript name *and* a
///   size *and* a matrix and differ on every axis: a `wght` 400 and a `wght` 700
///   instance of the system font do exactly that, which is the differential
///   `everyComponentOfTheFontKeyDiscriminates` pins. This component is live in
///   production, and it is live **because** `FontResolver` pins no axis
///   (ruling TX-C): the system font resolves with `opsz` = `clamp(size, 17, 96)`
///   in its variation dictionary, so 13pt and 26pt differ here as well as in
///   ``size``. Pinning an axis to its *default* would empty this dictionary —
///   `CTFontCopyVariation` omits any axis sitting at its default — and quietly
///   make the component production-inert.
/// - ``matrix`` — `CTFontGetMatrix`. A synthesised oblique, or a flipped font,
///   is the same face and size producing different outlines.
///
/// Construct one only via ``init(resolved:)``; there is deliberately no
/// memberwise initialiser, because a caller that can spell the components by
/// hand can spell a *requested* name into ``postScriptName`` and reintroduce
/// exactly the bug this type exists to prevent.
public struct FontKey: Hashable, Sendable {
    /// One axis of a variable font, as resolved.
    public struct VariationCoordinate: Hashable, Sendable {
        /// The four-character axis tag as an integer, e.g. `'opsz'`.
        public let axis: Int
        public let value: Double
    }

    /// `CTFontGetMatrix`'s six components. `CGAffineTransform` is neither
    /// `Hashable` nor `Sendable`, so it is destructured rather than stored.
    public struct Matrix: Hashable, Sendable {
        public let a, b, c, d, tx, ty: Double
    }

    public let postScriptName: String
    public let size: Double
    /// Sorted by ``VariationCoordinate/axis`` so that two fonts with the same
    /// coordinates in a different dictionary order compare equal.
    public let variations: [VariationCoordinate]
    public let matrix: Matrix

    /// The four components above, hashed once, at the only initialiser.
    ///
    /// **Why it is stored.** A `GlyphKey` is hashed for every glyph of every
    /// visible `Text` on every built frame, and it hashes this key; a
    /// synthesized `hash(into:)` would walk the PostScript name, the variation
    /// array and the six matrix `Double`s each time. The components are fixed
    /// by ``init(resolved:)``, so this cannot fall out of step with them.
    ///
    /// **A fast reject for `==`, never a proof of equality** — the same
    /// contract as `GlobalElementID.cachedHash`, and see `==` for why it is a
    /// combination to keep. `Hasher` is seeded per process, so the value is
    /// meaningful within one run only; nothing persists it.
    ///
    /// Internal rather than private so that
    /// `aForgedHashCollisionIsSettledByTheComponents` can take its offset.
    let precomputedHash: Int

    /// Reads the identity **out of** a resolved `CTFont`.
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

        var hasher = Hasher()
        hasher.combine(postScriptName)
        hasher.combine(size)
        hasher.combine(variations)
        hasher.combine(matrix)

        self.postScriptName = postScriptName
        self.size = size
        self.variations = variations
        self.matrix = matrix
        self.precomputedHash = hasher.finalize()
    }

    /// **All four components decide; ``precomputedHash`` only rejects early.**
    ///
    /// Keys that are equal component by component hashed the same values in
    /// the same order, so they agree on the hash and the early reject never
    /// refuses an equal pair. The converse does not hold: two different keys
    /// can collide, and then only the component comparison gives the right
    /// answer.
    ///
    /// **Safe alone and unsafe together**, as with `GlobalElementID`: an `==`
    /// that answered with the hash alone, or that skipped any one component, is
    /// wrong only on a collision. Measured, whole suite: each of those five
    /// spellings reddened `aForgedHashCollisionIsSettledByTheComponents` and no
    /// other test — the keys every other test compares already hash
    /// differently, so the early reject gives the right answer for the wrong
    /// reason. That test can see it because it writes a collision into a key
    /// instead of searching for one. A hash that dropped a component is the
    /// other half, a silent performance defect that
    /// `theFontKeyHashItselfDistinguishesEveryComponent` pins.
    ///
    /// **To force collisions under mutation, make the STORED hash constant**
    /// (`self.precomputedHash = 0`), not `hash(into:)`. This `==` reads
    /// ``precomputedHash`` directly, so a constant `hash(into:)` leaves the early
    /// reject fully working and proves nothing about the component comparison —
    /// measured: it left dropping `variations` or `matrix` from this body
    /// invisible to `everyComponentOfTheFontKeyDiscriminates`. With the stored
    /// hash constant, that test and `everyComponentOfTheGlyphKeyDiscriminates`
    /// both pass on the component comparison alone. Then dropping `variations`
    /// or `matrix` here reddens `everyComponentOfTheFontKeyDiscriminates`,
    /// dropping `size` reddens `theKeyDistinguishesSizes`, and answering with the
    /// hash alone reddens both discrimination tests. The `GlyphKey` test's two
    /// fonts differ in size and `opsz` at once, so no single dropped component
    /// reaches it.
    ///
    /// The comparison is **IEEE on `size`** exactly as the synthesized one was,
    /// so a NaN size is still unequal to itself.
    public static func == (lhs: FontKey, rhs: FontKey) -> Bool {
        lhs.precomputedHash == rhs.precomputedHash
            && lhs.size == rhs.size
            && lhs.matrix == rhs.matrix
            && lhs.postScriptName == rhs.postScriptName
            && lhs.variations == rhs.variations
    }

    /// Feeds ``precomputedHash`` alone. Pinned by
    /// `aFontKeyHashesOnlyItsPrecomputedHash`.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(precomputedHash)
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
    /// property to. Task 4's `MeasureFunction` is a second consumer, not the
    /// first.
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
