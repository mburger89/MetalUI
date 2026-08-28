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

    /// Reads the identity **out of** a resolved `CTFont`.
    public init(resolved font: CTFont) {
        self.postScriptName = CTFontCopyPostScriptName(font) as String
        self.size = Double(CTFontGetSize(font))

        let coordinates = (CTFontCopyVariation(font) as? [NSNumber: NSNumber]) ?? [:]
        self.variations = coordinates
            .map { VariationCoordinate(axis: $0.key.intValue, value: $0.value.doubleValue) }
            .sorted { $0.axis < $1.axis }

        let m = CTFontGetMatrix(font)
        self.matrix = Matrix(a: Double(m.a), b: Double(m.b), c: Double(m.c),
                             d: Double(m.d), tx: Double(m.tx), ty: Double(m.ty))
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
    /// numbers up itself rather than asking this property to. Task 4's
    /// `MeasureFunction` is a second consumer, not the first.
    public var lineHeight: Double { ascent + descent + leading }

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
