import CoreText
import MetalUITextSystem

/// The Apple path behind the ``TextSystem`` seam (ruling TS-B): CoreText
/// resolves, shapes and wraps through a ``ShapingCache``, and
/// ``GlyphRaster`` rasterizes. Behaviour is exactly what `Text` did before
/// the seam existed; the cache is the one a `Frame` is handed, so every test
/// that inspects it still sees the same entries.
@MainActor
public final class CoreTextTextSystem: TextSystem {
    /// The shaping cache this system measures and places through.
    public let cache: ShapingCache
    /// The fonts glyphs were placed in, by key — the requested fonts and any
    /// fallback font CoreText ran a glyph in — so ``rasterize(_:)`` can draw
    /// a key it placed.
    private var placedFonts: [FontKey: ResolvedFont] = [:]

    /// The CoreText text system over `cache`, the default on Apple platforms
    /// (`TS-B`).
    public init(cache: ShapingCache = ShapingCache()) {
        self.cache = cache
    }

    /// Resolves `descriptor` through CoreText and returns its key.
    public func resolveFont(_ descriptor: FontDescriptor) -> FontKey {
        let font = cache.resolveFont(descriptor)
        cache.registerFont(font)
        return font.key
    }

    /// The resolved font's metrics.
    public func fontMetrics(_ font: FontKey) -> TextFontMetrics {
        let metrics = registered(font).metrics
        return TextFontMetrics(ascent: metrics.ascent, descent: metrics.descent, leading: metrics.leading,
                               lineHeight: metrics.lineHeight)
    }

    /// Measures `string` wrapped at `width` (`nil` is one line per hard break)
    /// under `options`.
    public func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                        options: TextLayoutOptions) -> TextMeasurement {
        let shaped = cache.shaped(string, font: registered(font), wrappingAt: width, options: options)
        return TextMeasurement(widestLine: shaped.widestLine, totalHeight: shaped.totalHeight)
    }

    /// The caret's x offset before each character and after the last, from
    /// CoreText (`TI-E`).
    public func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        Shaper.caretOffsets(string, font: registered(font))
    }

    /// Each display line's character range when `string` is wrapped at `width`.
    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                           options: TextLayoutOptions) -> [Range<Int>] {
        cache.shaped(string, font: registered(font), wrappingAt: width, options: options).lines.map(\.sourceRange)
    }

    /// The glyphs of `string` laid out at `width`, placed on the device pixel
    /// grid.
    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            options: TextLayoutOptions,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        let requested = registered(font)
        return cache.shaped(string, font: requested, wrappingAt: width, options: options)
            .placedGlyphs(at: origin, font: requested, scaleFactor: scaleFactor)
            .map { placed in
                if placedFonts[placed.font.key] == nil { placedFonts[placed.font.key] = placed.font }
                return TextGlyph(key: placed.key, pixelX: placed.pixelX, baselineY: placed.baselineY)
            }
    }

    // MARK: Styled text (ruling RT-F) — lane 1 red stub

    /// Measures a styled text (stub).
    public func measure(_ text: StyledText, wrappingAt width: Double?,
                        options: TextLayoutOptions) -> StyledTextMeasurement {
        StyledTextMeasurement(widestLine: 0, totalHeight: 0, lines: [])
    }

    /// Lays out a styled text (stub).
    public func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                       origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        StyledTextLayout(measurement: StyledTextMeasurement(widestLine: 0, totalHeight: 0, lines: []),
                         glyphs: [], segments: [])
    }

    /// A face's decoration metrics (stub).
    public func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics {
        TextDecorationMetrics(underlinePosition: 0, underlineThickness: 0, strikethroughPosition: 0)
    }

    /// Rasterizes the glyph `key` names into a coverage image.
    public func rasterize(_ key: GlyphKey) -> GlyphImage {
        guard let font = placedFonts[key.font] ?? cache.font(for: key.font) else {
            preconditionFailure("CoreTextTextSystem.rasterize: \(key.font) was never placed by this system")
        }
        return GlyphRaster.rasterize(glyph: key.glyph, font: font,
                                     subpixelVariant: key.subpixelVariant, scaleFactor: key.scaleFactor)
    }

    /// Starts a frame for the cache's sweep bookkeeping.
    public func beginFrame() { cache.beginFrame() }
    /// Ends a frame, sweeping cache entries unused for long enough.
    public func endFrame() { cache.endFrame() }

    /// The font `key` names, which ``resolveFont(_:)`` registered.
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
