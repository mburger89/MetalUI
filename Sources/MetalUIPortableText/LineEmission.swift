import MetalUIScene
import MetalUIShaderTypes

/// What `PortableText.emitLines` drew (ruling LB-H).
public struct PortableParagraph: Sendable, Equatable {
    /// The display lines, as `PortableText.lines` returns them.
    public let lines: [PortableLine]
    /// `lines.count × lineHeight` — `ShapedText.totalHeight`'s rule.
    public let height: Double
}

extension PortableText {
    /// Emits `text` wrapped at `width` points (`nil` is one line per hard
    /// break) inside a text box whose **top-left** is `origin` — as
    /// `ShapedText.placedGlyphs(at:)` takes it, not a baseline as ``emit``
    /// does (ruling LB-H).
    ///
    /// Line *i*'s baseline is `origin.y + i × lineHeight + ascent`, rounded
    /// once at device scale. Each line's glyphs are the ones ``lines``
    /// measured — the paragraph's shaping sliced by the line's range, pen
    /// restarting at `origin.x` — and each glyph goes through ``emit``'s
    /// arithmetic. `contentMask`, `maskCornerRadii`, `order` and `layer` are
    /// ``emit``'s.
    @discardableResult
    public static func emitLines(_ text: String, font: PortableFont,
                                 origin: (x: Double, y: Double), wrappingAt width: Double?,
                                 scaleFactor: Float, color: MUIHsla, contentMask: MUIBounds,
                                 maskCornerRadii: MUICorners = MUICorners(topLeft: 0, topRight: 0,
                                                                          bottomRight: 0, bottomLeft: 0),
                                 order: UInt32 = 0, layer: Int = 0,
                                 into scene: inout Scene, atlas: GlyphAtlas) throws -> PortableParagraph {
        let (laidOut, placements) = try placements(text, font: font, origin: origin,
                                                   wrappingAt: width, scaleFactor: scaleFactor)
        for placement in placements {
            try emitGlyph(placement.id, deviceX: placement.deviceX, baselineY: placement.baselineY,
                          font: font, scaleFactor: scaleFactor, color: color,
                          contentMask: contentMask, maskCornerRadii: maskCornerRadii,
                          order: order, layer: layer, into: &scene, atlas: atlas)
        }
        return PortableParagraph(lines: laidOut.map(\.line),
                                 height: Double(laidOut.count) * font.metrics.lineHeight)
    }

    /// Where `emitLines` puts each glyph, before the atlas: the pen's device
    /// x and the device baseline row. Separate so the oracle (LB-I) can
    /// compare placement against `placedGlyphs` without rasterizing.
    static func placements(_ text: String, font: PortableFont, origin: (x: Double, y: Double),
                           wrappingAt width: Double?, scaleFactor: Float) throws
        -> (lines: [LaidOutLine], placements: [GlyphPlacement]) {
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let scale = Double(scaleFactor)
        let metrics = font.metrics
        let laidOut = try layOut(text, font: font, wrappingAt: width)
        var result: [GlyphPlacement] = []
        for (index, line) in laidOut.enumerated() {
            let baseline = origin.y + Double(index) * metrics.lineHeight + metrics.ascent
            let baselineY = Int((baseline * scale).rounded())
            for placed in line.glyphs {
                // A shaping offset is y-up from the baseline; the device is
                // y-down. Rounded on its own, as `placedGlyphs` rounds a run
                // position's y.
                result.append(GlyphPlacement(
                    id: placed.id,
                    deviceX: (origin.x + (placed.penX + placed.glyph.xOffset)) * scale,
                    baselineY: baselineY - Int((placed.glyph.yOffset * scale).rounded())))
            }
        }
        return (laidOut, result)
    }
}

/// One glyph's pen at device scale: x before the subpixel split, and the
/// device row of its baseline.
struct GlyphPlacement: Equatable {
    let id: UInt16
    let deviceX: Double
    let baselineY: Int
}
