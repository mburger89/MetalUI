import CoreText
import Foundation

/// A font as CoreText actually resolved it, paired with the identity
/// (``FontKey``) and the metrics that were read back off it.
///
/// Deliberately **not** `Sendable`: `CTFont` is a CoreFoundation class and
/// carries no such guarantee. ``key`` and ``metrics`` are `Sendable` on their
/// own and are what crosses a boundary; the `CTFont` stays where it was made.
public struct ResolvedFont {
    public let ctFont: CTFont
    public let key: FontKey
    public let metrics: FontMetrics

    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.key = FontKey(resolved: ctFont)
        self.metrics = FontMetrics(of: ctFont)
    }
}

/// Turns a *request* — an optional family name and a point size — into a
/// ``ResolvedFont``.
public enum FontResolver {
    /// The `'opsz'` four-character axis tag, as `CTFontCopyVariationAxes`
    /// reports axis identifiers.
    static let opticalSizeAxis: Int = 0x6F70_737A  // 'o','p','s','z'

    /// Resolves `family` at `size`, pinning the optical-size axis (§6.2).
    ///
    /// `family: nil` means the platform UI font.
    ///
    /// **The returned font's identity may not be the requested one, and that is
    /// the point.** `CTFontCreateWithName` substitutes rather than failing, so
    /// callers must key caches on ``ResolvedFont/key`` and never on `family` —
    /// see ``FontKey`` for §6.1's measurement.
    public static func resolve(family: String?, size: Double) -> ResolvedFont {
        let requested: CTFont
        if let family {
            requested = CTFontCreateWithName(family as CFString, CGFloat(size), nil)
        } else {
            // `CTFontCreateUIFontForLanguage` is documented to return nil for an
            // unsupported ui-font/language pair. `.system` with a nil language
            // is the one pair the system font is defined for, so the fallback
            // below is unreachable in the sense that no argument this function
            // can construct reaches it — it exists because the API is optional,
            // not because a case is expected.
            requested = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
        }
        return ResolvedFont(ctFont: pinningOpticalSize(requested, size: size))
    }

    /// Pins `'opsz'` to the axis's **default** value via a `CTFontDescriptor`
    /// variation attribute, so that advances scale linearly with point size
    /// (spec §6.2).
    ///
    /// **Measured, not assumed.** `CTFontCreateUIFontForLanguage(.system, …)`
    /// returns a variable font whose optical-size axis *tracks* the point size
    /// (13pt → 17, 26pt → 26, 52pt → 52). Different optical sizes are different
    /// outlines with different sidebearings, so advances stop scaling linearly:
    /// §6.2 measured a 28-character label at 13pt = 164.804 and 26pt = 301.703,
    /// which is −8.5% against 13pt × 2 = 329.608. Anything that computes
    /// positions from base-size advances and then applies a scale — §7.1's zoom
    /// matrix — drifts progressively, ~28px accumulated at 2× on one label.
    ///
    /// With the axis pinned, one point size is a uniform scale of another, so
    /// zoom folds into the atlas key's `size` component and no re-shaping is
    /// needed. That matters most at M5's canvas; it is cheapest to get right
    /// here, because every advance computed before it would otherwise have to be
    /// invalidated.
    ///
    /// A face with no variation axes at all (Menlo, Helvetica — §6.2 verified
    /// both are already exactly linear) is returned untouched.
    private static func pinningOpticalSize(_ font: CTFont, size: Double) -> CTFont {
        guard let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]],
              let opsz = axes.first(where: {
                  ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue == opticalSizeAxis
              }),
              let pinned = (opsz[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue
        else { return font }

        // Keep every other axis where it resolved; move only `opsz`.
        var coordinates = (CTFontCopyVariation(font) as? [NSNumber: NSNumber]) ?? [:]
        coordinates[NSNumber(value: opticalSizeAxis)] = NSNumber(value: pinned)

        // Copy the resolved font's own descriptor rather than building one from
        // the variation alone: a bare variation attribute names no family, and
        // the font created from it would be a different face.
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(font),
            [kCTFontVariationAttribute: coordinates] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
    }
}
