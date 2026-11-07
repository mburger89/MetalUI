import Foundation
import MetalUICore
import MetalUIPrimitives
import MetalUIScene
import MetalUITextSystem

// R4-5 PR E lane 2 (ruling prefix `TZ-`, record 222; probe `docs/probes/swiftui-text-under-transform.swift`, arms `Z0`..`Z7`):
// text under a flattening effect (`scaleEffect`, a uniform scale) is rasterized at the scale it is drawn at, not resampled from the
// device-scale bitmap (divergence 106 narrowed). Glyphs are emitted exactly as before, with the base key and slot; a glyph that reaches
// `Frame.insertIntoScene` with bounds scaled by `f` is re-keyed there, the way a path is rasterized there at its final scale (`GX-B`).

/// The raster scale ladder of re-keyed text (`TZ-A`, `TZ-C`).
enum TextZoom {
    /// Rungs per octave: raster scales are `2^(n/8)` (steps of 9.05 %, so a resample of at most 4.4 %).
    static let rungsPerOctave = 8.0
    /// The smallest raster scale: a glyph drawn smaller than a quarter of its device size rasterizes at a quarter. MetalUI's, not SwiftUI's.
    static let minimumScale = 0.25
    /// The largest em size, in raster pixels, a re-keyed glyph is rasterized at (about 360 such glyphs fit a 4096 square atlas).
    /// MetalUI's, not SwiftUI's (probe `Z7`: SwiftUI shows no cap).
    static let maximumEmPixels = 256.0

    /// The rung nearest `f` (the flattening scale already applied to a glyph's bounds), with no cap: `n` in `2^(n/8)`.
    /// Rungs within 1/16 of an octave of 1 are 1.
    static func rung(_ f: Double) -> Int {
        guard f.isFinite, f > 0 else { return 0 }
        return Int((log2(f) * rungsPerOctave).rounded())
    }

    /// The raster scale for a glyph drawn at `f` times its device size, `emPixels` being its em size in device pixels:
    /// the ladder rung, floored at a quarter and, when it enlarges, capped so the em stays within 256 pixels. 1 means
    /// "keep the base raster".
    static func rasterScale(_ f: Double, emPixels: Double) -> Double {
        var n = rung(f)
        if n > 0 {
            let room = emPixels > 0 ? Int((log2(maximumEmPixels / emPixels) * rungsPerOctave).rounded(.down)) : n
            n = max(0, min(n, room))
        } else if n < 0 {
            n = max(n, Int((log2(minimumScale) * rungsPerOctave).rounded()))
        }
        return n == 0 ? 1 : pow(2, Double(n) / rungsPerOctave)
    }
}

extension Frame {
    /// `glyph` rasterized at the scale it is drawn at (`TZ-A`), or `nil` for "draw it as emitted": at its device scale (the
    /// common case, which costs one logarithm and reads no dictionary), or a fallback that `glyphRekeyFallbacks` counts.
    func rekeyedGlyph(_ glyph: MUIGlyph) -> MUIGlyph? {
        let aw = Double(glyph.atlasBounds.size.width)
        guard aw > 0 else { return nil }
        let f = Double(glyph.bounds.size.width) / aw
        guard TextZoom.rung(f) != 0 else { return nil }
        glyphRekeyLookups += 1
        guard let base = glyphAtlas.key(forAtlasX: glyph.atlasBounds.origin.x, y: glyph.atlasBounds.origin.y,
                                         width: glyph.atlasBounds.size.width, height: glyph.atlasBounds.size.height), let basePacked = glyphAtlas.packedGlyph(for: base) else {
            glyphRekeyFallbacks += 1
            return nil
        }
        let k = TextZoom.rasterScale(f, emPixels: base.size * Double(base.scaleFactor))
        guard k != 1 else { return nil }
        let r = k / f
        let penX = Double(glyph.bounds.origin.x) + f * (Double(-basePacked.left) + GlyphImage.subpixelOffset(variant: base.subpixelVariant))
        let baseY = Double(glyph.bounds.origin.y) + f * Double(basePacked.top)
        let split = GlyphImage.subpixelPlacement(forDeviceX: penX * r)
        let key = GlyphKey(font: base.font, glyph: base.glyph, size: base.size, subpixelVariant: split.variant,
                           scaleFactor: base.scaleFactor * Float(k))
        let system = textSystem
        guard let packed = glyphAtlas.packed(for: key, rasterize: { system.rasterize(key) }),
              packed.slot.width > 0, packed.slot.height > 0 else {
            glyphRekeyFallbacks += 1
            return nil
        }
        var out = glyph
        out.bounds = MUIBounds(
            origin: MUIPoint(x: Float(Double(split.pixelX + packed.left) / r),
                             y: Float((((baseY * r).rounded()) - Double(packed.top)) / r)),
            size: MUISize(width: Float(Double(packed.slot.width) / r), height: Float(Double(packed.slot.height) / r)))
        out.atlasBounds = MUIBounds(origin: MUIPoint(x: Float(packed.slot.x), y: Float(packed.slot.y)),
                                    size: MUISize(width: Float(packed.slot.width), height: Float(packed.slot.height)))
        glyphsRekeyed += 1
        return out
    }
}
