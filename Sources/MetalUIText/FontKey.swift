import CoreText
import Foundation

/// The identity of a **resolved** font: what an atlas, a shaping cache or a
/// metrics cache may safely be keyed on (spec §6.1).
///
/// **Every component is read back off the `CTFont` CoreText handed us, never
/// off the request, and §6.1 measured why.** `CTFontCreateWithName` does not
/// fail on a name it cannot find — it *substitutes*. Requesting
/// `"SFMono-Regular"` by name on the target machine returned a font whose
/// PostScript name is `Helvetica`. A key built from the requested family would
/// therefore hand out one font's glyph images for another font's outlines, and
/// nothing above it could notice: both fonts measure, shape and lay out
/// perfectly well, so no layout assertion and no golden can see it. The only
/// place the substitution is visible is the resolved `CTFont` itself.
///
/// The four components, and what each one alone would let collide:
///
/// - ``postScriptName`` — *which face* was actually resolved. This is the
///   component §6.1 is about.
/// - ``size`` — a `CTFont` carries its point size, and glyph images are
///   rasterized at it. Without this, 13pt and 26pt of one face share a key.
/// - ``variations`` — the resolved variation coordinates
///   (`CTFontCopyVariation`). Two `CTFont`s can share a PostScript name and a
///   size and differ on every axis. §6.2's `opsz` pin *is* such a coordinate,
///   so without this component a pinned and an unpinned system font are
///   indistinguishable.
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
