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
    public let resolver: PortableFontResolver
    private var fonts: [FontKey: PortableFont] = [:]

    private struct MeasureKey: Hashable {
        let string: String
        let font: FontKey
        let width: Double?
    }
    private struct Entry<Value> {
        var value: Value
        var generation: Int
    }
    private var measurements: [MeasureKey: Entry<TextMeasurement>] = [:]
    private var generation = 0

    public init(resolver: PortableFontResolver) {
        self.resolver = resolver
    }

    public func resolveFont(family: String?, size: Double) -> FontKey {
        let font = trapping { try resolver.resolve(family: family, size: size) }
        fonts[font.key] = font
        // A fallback's glyphs are keyed on the fallback's own face (FB-A).
        for fallback in font.fallbacks where fonts[fallback.key] == nil { fonts[fallback.key] = fallback }
        return font.key
    }

    public func measure(_ string: String, font: FontKey, wrappingAt width: Double?) -> TextMeasurement {
        let key = MeasureKey(string: string, font: font, width: width)
        if let hit = measurements[key] {
            measurements[key]?.generation = generation
            return hit.value
        }
        let portable = registered(font)
        let lines = trapping { try PortableText.lines(string, font: portable, wrappingAt: width) }
        let value = TextMeasurement(widestLine: lines.reduce(0) { max($0, $1.advance) },
                                    totalHeight: Double(lines.count) * portable.metrics.lineHeight)
        measurements[key] = Entry(value: value, generation: generation)
        return value
    }

    public func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        trapping { try PortableText.caretOffsets(string, font: registered(font)) }
    }

    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?) -> [Range<Int>] {
        trapping { try PortableText.lines(string, font: registered(font), wrappingAt: width).map(\.range) }
    }

    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        let portable = registered(font)
        let placements = trapping {
            try PortableText.placements(string, font: portable, origin: origin, wrappingAt: width,
                                        scaleFactor: scaleFactor).placements
        }
        return placements.map { placement in
            let split = GlyphImage.subpixelPlacement(forDeviceX: placement.deviceX)
            return TextGlyph(key: GlyphKey(font: placement.font.key, glyph: placement.id, size: placement.font.size,
                                           subpixelVariant: split.variant, scaleFactor: scaleFactor),
                             pixelX: split.pixelX, baselineY: placement.baselineY)
        }
    }

    public func rasterize(_ key: GlyphKey) -> GlyphImage {
        (try? FreeTypeRaster.rasterize(glyph: key.glyph, font: registered(key.font).raster,
                                       subpixelVariant: key.subpixelVariant,
                                       scaleFactor: key.scaleFactor)) ?? .empty
    }

    public func beginFrame() { generation += 1 }

    /// Drops measurements no frame has asked for since the previous one — the
    /// same two-frame lifetime `ShapingCache` gives its entries.
    public func endFrame() {
        measurements = measurements.filter { generation - $0.value.generation <= 1 }
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
