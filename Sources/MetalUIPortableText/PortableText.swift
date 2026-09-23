import MetalUIFreeType
import MetalUIHarfBuzz
import MetalUIScene
import MetalUIShaderTypes

/// One font file, at one size, opened in both portable engines (ruling PT-B):
/// HarfBuzz shapes with it, FreeType rasterizes with it, and both read the
/// same bytes, so the glyph ids one produces are the ids the other draws.
public final class PortableFont {
    let shaping: HarfBuzzFont
    let raster: FreeTypeFont

    /// Points per em.
    public let size: Double
    /// The identity the atlas keys on — FreeType's (`FT-F`), which was
    /// measured equal to CoreText's for the same file and size.
    public var key: FontKey { raster.key }
    /// The face's line metrics at `size` (ruling LB-F).
    public let metrics: PortableFontMetrics

    /// Opens `data` in both engines.
    ///
    /// **The two engines are checked against each other here**, so a caller
    /// that hands the halves different files fails at construction rather than
    /// silently drawing one font's outlines for another font's ids — the same
    /// hazard `FontKey` exists to prevent inside one engine.
    public convenience init(data: [UInt8], faceIndex: Int = 0, size: Double) throws {
        try self.init(shapingData: data, rasterData: data, faceIndex: faceIndex, size: size)
    }

    /// Opens a **separate** byte array in each engine.
    ///
    /// Internal, and the only way to make the two halves disagree: the public
    /// initializer takes one `data` precisely so a caller cannot. It exists so
    /// that the cross-engine check below can be exercised at all — a test hands
    /// the halves two different font files and watches the check throw — which
    /// the public spelling makes impossible by construction.
    init(shapingData: [UInt8], rasterData: [UInt8], faceIndex: Int, size: Double) throws {
        shaping = try HarfBuzzFont(data: shapingData, faceIndex: faceIndex, size: size)
        raster = try FreeTypeFont(data: rasterData, faceIndex: faceIndex, size: size)
        self.size = size
        let hhea = raster.horizontalHeader
        let unitsPerEm = Double(raster.unitsPerEm)
        // CoreText rounds a TrueType face's metric to a 16.16 fixed-point
        // fraction of the em, back in design units, then scales it as it
        // scales an advance — `units × (size / unitsPerEm)` (measured exact,
        // LB-F). A CFF face's it scales unrounded.
        let fixedPoint = raster.format == "TrueType"
        func points(_ units: Int) -> Double {
            let rounded = fixedPoint ? (Double(units) * 65536 / unitsPerEm).rounded() * unitsPerEm / 65536
                                     : Double(units)
            return rounded * (size / unitsPerEm)
        }
        metrics = PortableFontMetrics(ascent: points(hhea.ascender), descent: points(-hhea.descender),
                                      leading: points(hhea.lineGap))
        guard shaping.unitsPerEm == raster.unitsPerEm else {
            throw PortableTextError("the shaping and raster faces disagree on unitsPerEm: "
                                    + "\(shaping.unitsPerEm) vs \(raster.unitsPerEm)")
        }
        // A probe both engines must map the same way. Not proof of one file,
        // but it catches a swapped pair, which is the mistake worth catching.
        for probe: Unicode.Scalar in ["A", "م", "0"] where raster.glyph(for: probe) != 0 {
            guard shaping.glyph(for: probe) == raster.glyph(for: probe) else {
                throw PortableTextError("the shaping and raster faces disagree on the glyph for "
                                        + "U+\(String(probe.value, radix: 16, uppercase: true))")
            }
        }
    }
}

/// A face's vertical metrics at one size, in points (ruling LB-F) — the
/// portable counterpart of `MetalUIText`'s `FontMetrics`, with the same
/// `lineHeight` formula.
///
/// Read from the face's own `hhea` table through FreeType (ascender,
/// descender and line gap, scaled by `size / unitsPerEm`) — not OS/2's
/// typographic metrics, even when the face asks for them, because CoreText
/// does not use them either (measured on patched faces, record §31). CoreText's
/// `CTFontGetAscent`/`Descent`/`Leading` for the same file and size agree to
/// within a few millionths of a point, not exactly (measured, record §31), and
/// `lineHeight` agrees exactly.
public struct PortableFontMetrics: Hashable, Sendable {
    public let ascent: Double
    public let descent: Double
    public let leading: Double

    /// The distance from one baseline to the next: `ceil(ascent + descent +
    /// leading)`, `FontMetrics.lineHeight`'s whole-point rule, so every
    /// baseline after the first stays pixel-aligned.
    public var lineHeight: Double { (ascent + descent + leading).rounded(.up) }

    public init(ascent: Double, descent: Double, leading: Double) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }
}

public struct PortableTextError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// String → `MUIGlyph`s in a `Scene`, with their coverage in a `GlyphAtlas`,
/// using no Apple framework: HarfBuzz shapes, FreeType rasterizes, and the
/// arithmetic between them is `Frame.draw`'s (rulings PT-D, PT-E).
///
/// `emit` is one run on one line; `lines` wraps a paragraph (`LB-C`) and
/// `emitLines` draws it (`LB-H`). Bidi across runs, script itemization and
/// font fallback are not here; on Apple platforms `MetalUIText`'s `Shaper`
/// still does all of it (`PT-I`).
public enum PortableText {
    /// Emits `text` with its baseline starting at `origin` (points), and
    /// returns the run's advance in points.
    ///
    /// `contentMask` and `maskCornerRadii` are in device pixels, as
    /// `Frame.draw` stamps `activeClip`/`activeClipRadii` scaled. `order` and
    /// `layer` go to every glyph of the run, as `Frame.draw` passes `order: 0`
    /// and `activeLayer`: within a layer, equal orders paint in emission
    /// sequence; a higher layer paints after every lower one. The defaults — a
    /// square mask, `order: 0`, layer 0 — are `Frame.draw`'s outside any
    /// rounded clip or lifted layer.
    @discardableResult
    public static func emit(_ text: String, font: PortableFont,
                            origin: (x: Double, y: Double), scaleFactor: Float,
                            color: MUIHsla, contentMask: MUIBounds,
                            maskCornerRadii: MUICorners = MUICorners(topLeft: 0, topRight: 0,
                                                                     bottomRight: 0, bottomLeft: 0),
                            order: UInt32 = 0, layer: Int = 0,
                            into scene: inout Scene, atlas: GlyphAtlas) throws -> Double {
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let scale = Double(scaleFactor)
        let run = try HarfBuzzShaper.shape(text, font: font.shaping)

        let units = Array(text.utf16)
        let ignorable = ignorableUnits(of: text, count: units.count)
        let space = font.shaping.glyph(for: " ")
        var pen = origin.x
        for glyph in run.glyphs {
            defer { pen += glyph.xAdvance }
            guard let id = drawnGlyph(glyph.id, at: units[glyph.cluster],
                                      ignorable: ignorable[glyph.cluster], space: space) else { continue }
            try emitGlyph(id, deviceX: (pen + glyph.xOffset) * scale,
                          baselineY: Int(((origin.y - glyph.yOffset) * scale).rounded()),
                          font: font, scaleFactor: scaleFactor, color: color,
                          contentMask: contentMask, maskCornerRadii: maskCornerRadii,
                          order: order, layer: layer, into: &scene, atlas: atlas)
        }
        return run.advance
    }

    /// One glyph with its pen at device x `deviceX` and its baseline on device
    /// row `baselineY`: the subpixel split, the atlas lookup (a miss rasterizes
    /// through FreeType) and the sprite — `Frame.draw`'s arithmetic (PT-D).
    /// `emit` and `emitLines` both come through here, so the arithmetic exists
    /// once on the portable side.
    static func emitGlyph(_ id: UInt16, deviceX: Double, baselineY: Int, font: PortableFont,
                          scaleFactor: Float, color: MUIHsla, contentMask: MUIBounds,
                          maskCornerRadii: MUICorners, order: UInt32, layer: Int,
                          into scene: inout Scene, atlas: GlyphAtlas) throws {
        let placement = GlyphImage.subpixelPlacement(forDeviceX: deviceX)
        let key = GlyphKey(font: font.key, glyph: id, size: font.size,
                           subpixelVariant: placement.variant, scaleFactor: scaleFactor)
        // The atlas records a space too, so its miss is paid once.
        guard let packed = atlas.packed(for: key, rasterize: {
            (try? FreeTypeRaster.rasterize(glyph: id, font: font.raster,
                                           subpixelVariant: placement.variant,
                                           scaleFactor: scaleFactor)) ?? .empty
        }) else { throw PortableTextError("the glyph atlas is full") }
        guard packed.slot.width > 0, packed.slot.height > 0 else { return }

        let bounds = MUIBounds(
            origin: MUIPoint(x: Float(placement.pixelX + packed.left),
                             y: Float(baselineY - packed.top)),
            size: MUISize(width: Float(packed.slot.width), height: Float(packed.slot.height)))
        let slot = MUIBounds(
            origin: MUIPoint(x: Float(packed.slot.x), y: Float(packed.slot.y)),
            size: MUISize(width: Float(packed.slot.width), height: Float(packed.slot.height)))
        scene.insert(MUIGlyph(bounds: bounds, atlasBounds: slot, contentMask: contentMask,
                              maskCornerRadii: maskCornerRadii,
                              color: color, order: order, _reserved: 0), layer: layer)
    }
}
