import MetalUIFreeType
import MetalUITextSystem

/// The portable path behind the ``TextSystem`` seam (ruling TS-C): fonts
/// from a ``PortableFontResolver``, wrapping from ``PortableText/lines(_:font:wrappingAt:)``,
/// placement from ``PortableText/emitLines`` (the same arithmetic, without
/// the atlas), and rasterization by FreeType — each measured equal to the
/// Apple path by its own oracle (`LB-`, `PT-`, `FN-`).
///
/// A thrown error below means a font file that opened and then failed to
/// shape, which no oracle has produced; it traps with the reason rather than
/// drawing nothing.
@MainActor
public final class PortableTextSystem: TextSystem {
    /// The resolver fonts are opened through.
    public let resolver: PortableFontResolver
    private var fonts: [FontKey: PortableFont] = [:]

    /// `(string, font, width, options)` — the options are part of the key
    /// (ruling TE-C item 3): a line limit or truncation mode is a different
    /// layout of the same string.
    private struct MeasureKey: Hashable {
        let string: String
        let font: FontKey
        let width: Double?
        let options: TextLayoutOptions
    }
    private struct Entry<Value> {
        var value: Value
        var generation: Int
    }
    private var measurements: [MeasureKey: Entry<TextMeasurement>] = [:]
    /// A styled text's measurement key (ruling RT-F item 5): the whole value,
    /// so two run splits of one string are two entries.
    private struct StyledKey: Hashable {
        let text: StyledText
        let width: Double?
        let options: TextLayoutOptions
    }
    private var styledMeasurements: [StyledKey: Entry<StyledTextMeasurement>] = [:]
    /// Styled measurements answered from an entry, and computed (ruling
    /// RT-F item 5) — what a warm styled frame is counted by.
    private(set) var styledHits = 0
    private(set) var styledMisses = 0
    private var generation = 0

    /// The portable text system over `resolver`'s registered fonts — HarfBuzz,
    /// FreeType and libunibreak, no CoreText (`TS-C`).
    public init(resolver: PortableFontResolver) {
        self.resolver = resolver
    }

    /// Resolves `descriptor` against the registered fonts and returns its key.
    public func resolveFont(_ descriptor: FontDescriptor) -> FontKey {
        let font = trapping { try resolver.resolve(descriptor) }
        fonts[font.key] = font
        // A fallback's glyphs are keyed on the fallback's own face (FB-A).
        for fallback in font.fallbacks where fonts[fallback.key] == nil { fonts[fallback.key] = fallback }
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
        let key = MeasureKey(string: string, font: font, width: width, options: options)
        if let hit = measurements[key] {
            measurements[key]?.generation = generation
            return hit.value
        }
        let portable = registered(font)
        let lines = trapping {
            try PortableText.layOut(string, font: portable, wrappingAt: width, options: options).map(\.line)
        }
        let value = TextMeasurement(widestLine: lines.reduce(0) { max($0, $1.advance) },
                                    totalHeight: Double(lines.count) * portable.metrics.lineHeight)
        measurements[key] = Entry(value: value, generation: generation)
        return value
    }

    /// The caret's x offset before each character and after the last (`TI-E`).
    public func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        trapping { try PortableText.caretOffsets(string, font: registered(font)) }
    }

    /// Each display line's character range when `string` is wrapped at `width`.
    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                           options: TextLayoutOptions) -> [Range<Int>] {
        trapping {
            try PortableText.layOut(string, font: registered(font), wrappingAt: width, options: options).map(\.line.range)
        }
    }

    /// The glyphs of `string` laid out at `width`, placed on the device pixel
    /// grid.
    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            options: TextLayoutOptions,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        let portable = registered(font)
        let placements = trapping {
            try PortableText.placements(string, font: portable, origin: origin, wrappingAt: width,
                                        options: options, scaleFactor: scaleFactor).placements
        }
        return placements.map { placement in
            let split = GlyphImage.subpixelPlacement(forDeviceX: placement.deviceX)
            return TextGlyph(key: GlyphKey(font: placement.font.key, glyph: placement.id, size: placement.font.size,
                                           subpixelVariant: split.variant, scaleFactor: scaleFactor),
                             pixelX: split.pixelX, baselineY: placement.baselineY)
        }
    }

    // MARK: Styled text (ruling RT-F)

    /// Measures `text` (rulings RT-F, RT-G, RT-H, RT-I), cached by the whole
    /// value under the same two-frame lifetime as plain measurements.
    public func measure(_ text: StyledText, wrappingAt width: Double?,
                        options: TextLayoutOptions) -> StyledTextMeasurement {
        let key = StyledKey(text: text, width: width, options: options)
        if let hit = styledMeasurements[key] {
            styledHits += 1
            styledMeasurements[key]?.generation = generation
            return hit.value
        }
        styledMisses += 1
        let fonts = text.runs.map { registered($0.style.font) }
        let value = trapping {
            try PortableText.styledLines(text, fonts: fonts, wrappingAt: width, options: options).measurement
        }
        styledMeasurements[key] = Entry(value: value, generation: generation)
        return value
    }

    /// Lays `text` out as ``measure(_:wrappingAt:options:)`` does and places
    /// every glyph, with its run, and every run segment.
    public func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                       origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        let fonts = text.runs.map { registered($0.style.font) }
        return trapping {
            try PortableText.styledLayout(text, fonts: fonts, wrappingAt: width, options: options, origin: origin,
                                          scaleFactor: scaleFactor)
        }
    }

    /// `font`'s `post` underline position and thickness and half its
    /// x-height, scaled `units × (size / unitsPerEm)` — `CTFontGetUnderlinePosition`'s
    /// numbers (ruling RT-J item 2, measured equal on the three test faces).
    public func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics {
        let face = registered(font).raster
        let scale = face.size / Double(face.unitsPerEm)
        return TextDecorationMetrics(underlinePosition: Double(face.underlinePosition) * scale,
                                     underlineThickness: Double(face.underlineThickness) * scale,
                                     strikethroughPosition: Double(face.xHeight) * scale / 2)
    }

    /// Rasterizes the glyph `key` names with FreeType; an empty image if it
    /// cannot.
    public func rasterize(_ key: GlyphKey) -> GlyphImage {
        (try? FreeTypeRaster.rasterize(glyph: key.glyph, font: registered(key.font).raster,
                                       subpixelVariant: key.subpixelVariant,
                                       scaleFactor: key.scaleFactor)) ?? .empty
    }

    /// Starts a frame for the cache's sweep bookkeeping.
    public func beginFrame() { generation += 1 }

    /// Drops measurements no frame has asked for since the previous one — the
    /// same two-frame lifetime `ShapingCache` gives its entries.
    public func endFrame() {
        measurements = measurements.filter { generation - $0.value.generation <= 1 }
        styledMeasurements = styledMeasurements.filter { generation - $0.value.generation <= 1 }
    }

    private func registered(_ key: FontKey) -> PortableFont {
        guard let font = fonts[key] else {
            preconditionFailure("PortableTextSystem: \(key) was not resolved by this text system")
        }
        return font
    }

    private func trapping<T>(_ body: () throws -> T) -> T {
        do { return try body() } catch {
            preconditionFailure("PortableTextSystem: \(error)")
        }
    }
}
