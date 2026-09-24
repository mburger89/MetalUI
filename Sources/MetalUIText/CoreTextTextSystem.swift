import CoreText
import MetalUITextSystem

/// The Apple path behind the ``TextSystem`` seam (ruling TS-B): CoreText
/// resolves, shapes and wraps through a ``ShapingCache``, and
/// ``GlyphRaster`` rasterizes. Behaviour is exactly what `Text` did before
/// the seam existed; the cache is the one a `Frame` is handed, so every test
/// that inspects it still sees the same entries.
@MainActor
public final class CoreTextTextSystem: TextSystem {
    public let cache: ShapingCache
    /// The fonts glyphs were placed in, by key — the requested fonts and any
    /// fallback font CoreText ran a glyph in — so ``rasterize(_:)`` can draw
    /// a key it placed.
    private var placedFonts: [FontKey: ResolvedFont] = [:]

    public init(cache: ShapingCache = ShapingCache()) {
        self.cache = cache
    }

    public func resolveFont(family: String?, size: Double) -> FontKey {
        let font = cache.resolveFont(family: family, size: size)
        cache.registerFont(font)
        return font.key
    }

    public func measure(_ string: String, font: FontKey, wrappingAt width: Double?) -> TextMeasurement {
        let shaped = cache.shaped(string, font: registered(font), wrappingAt: width)
        return TextMeasurement(widestLine: shaped.widestLine, totalHeight: shaped.totalHeight)
    }

    public func minContentWidth(_ string: String, font: FontKey) -> Double {
        cache.minContentWidth(string, font: registered(font))
    }

    public func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        Shaper.caretOffsets(string, font: registered(font))
    }

    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?) -> [Range<Int>] {
        cache.shaped(string, font: registered(font), wrappingAt: width).lines.map { shaped in
            let range = CTLineGetStringRange(shaped.line)
            return range.location..<(range.location + range.length)
        }
    }

    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        let requested = registered(font)
        return cache.shaped(string, font: requested, wrappingAt: width)
            .placedGlyphs(at: origin, font: requested, scaleFactor: scaleFactor)
            .map { placed in
                if placedFonts[placed.font.key] == nil { placedFonts[placed.font.key] = placed.font }
                return TextGlyph(key: placed.key, pixelX: placed.pixelX, baselineY: placed.baselineY)
            }
    }

    public func rasterize(_ key: GlyphKey) -> GlyphImage {
        guard let font = placedFonts[key.font] ?? cache.font(for: key.font) else {
            preconditionFailure("CoreTextTextSystem.rasterize: \(key.font) was never placed by this system")
        }
        return GlyphRaster.rasterize(glyph: key.glyph, font: font,
                                     subpixelVariant: key.subpixelVariant, scaleFactor: key.scaleFactor)
    }

    public func beginFrame() { cache.beginFrame() }
    public func endFrame() { cache.endFrame() }

    /// The font `key` names, which ``resolveFont(family:size:)`` registered.
    private func registered(_ key: FontKey) -> ResolvedFont {
        guard let font = cache.font(for: key) else {
            preconditionFailure("""
                No font registered for \(key) on this text system's shaping cache. \
                resolveFont registers every font it returns and ShapingCache never \
                removes one, so either the key is not equal to itself (a NaN \
                component) or it came from a different text system.
                """)
        }
        return font
    }
}
