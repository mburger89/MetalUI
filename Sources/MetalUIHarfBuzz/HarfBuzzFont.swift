import CHarfBuzz

/// A HarfBuzz call that failed.
public struct HarfBuzzError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public var description: String { "\(operation) failed" }
}

/// One face of a font file, opened with HarfBuzz at one point size — the
/// shaping counterpart of `MetalUIFreeType`'s `FreeTypeFont` (ruling SH-C).
///
/// HarfBuzz reads the face's own tables (`hb-ot`); no FreeType, ICU or
/// platform backend is compiled in (SH-A), so the glyph ids it returns are
/// the font's, the same ones `FreeTypeRaster` rasterizes.
///
/// Not `Sendable`: `hb_font_t` is reference-counted without synchronisation.
public final class HarfBuzzFont {
    let blob: OpaquePointer
    let face: OpaquePointer
    let font: OpaquePointer

    /// Points per em — the size shaping answers in.
    public let size: Double
    /// The face's design units per em, the unit HarfBuzz works in (SH-D).
    public let unitsPerEm: Int

    public init(data: [UInt8], faceIndex: Int = 0, size: Double) throws {
        precondition(size.isFinite && size > 0, "a font size must be positive and finite")
        // hb_blob_create copies with HB_MEMORY_MODE_DUPLICATE, so `data` need
        // not outlive this call.
        let blob: OpaquePointer? = data.withUnsafeBytes { raw in
            hb_blob_create(raw.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(raw.count),
                           HB_MEMORY_MODE_DUPLICATE, nil, nil)
        }
        guard let blob, hb_blob_get_length(blob) == UInt32(data.count) else {
            if let blob { hb_blob_destroy(blob) }
            throw HarfBuzzError(operation: "hb_blob_create")
        }
        guard let face = hb_face_create(blob, UInt32(faceIndex)), hb_face_get_glyph_count(face) > 0 else {
            hb_face_destroy(hb_face_create(blob, UInt32(faceIndex)))
            hb_blob_destroy(blob)
            throw HarfBuzzError(operation: "hb_face_create")
        }
        guard let font = hb_font_create(face) else {
            hb_face_destroy(face); hb_blob_destroy(blob)
            throw HarfBuzzError(operation: "hb_font_create")
        }
        let upem = Int(hb_face_get_upem(face))
        // SH-D: shape in design units and convert in Double. Scaling here to
        // 26.6 device pixels would quantize every advance to 1/64 px, the
        // rounding FT-D measured changing answers.
        hb_font_set_scale(font, Int32(upem), Int32(upem))

        self.blob = blob
        self.face = face
        self.font = font
        self.size = size
        self.unitsPerEm = upem
    }

    deinit {
        hb_font_destroy(font)
        hb_face_destroy(face)
        hb_blob_destroy(blob)
    }

    /// The face's glyph for a Unicode scalar, or 0 (`.notdef`) — the cmap
    /// lookup alone, with no shaping. For `PT-B`'s cross-engine check; shaped
    /// text takes its ids from ``HarfBuzzShaper``.
    public func glyph(for scalar: Unicode.Scalar) -> UInt16 {
        var id: hb_codepoint_t = 0
        guard hb_font_get_nominal_glyph(font, scalar.value, &id) != 0 else { return 0 }
        return UInt16(truncatingIfNeeded: id)
    }

    /// `glyph`'s advance before any shaping — the face's `hmtx` advance, with
    /// no kerning or other positioning applied — in points (ruling TI-E: a
    /// caret between a kerned pair sits halfway through the kern).
    public func nominalAdvance(of glyph: UInt16) -> Double {
        points(hb_font_get_glyph_h_advance(font, hb_codepoint_t(glyph)))
    }

    /// The caret positions the face's `GDEF` ligature caret list gives
    /// `glyph`, in points from the glyph's origin, left to right — empty when
    /// the face has none for it (ruling TI-E: CoreText puts a caret inside a
    /// ligature here when the face says where).
    public func ligatureCarets(of glyph: UInt16) -> [Double] {
        var count = hb_ot_layout_get_ligature_carets(font, HB_DIRECTION_LTR, hb_codepoint_t(glyph), 0, nil, nil)
        guard count > 0 else { return [] }
        var carets = [hb_position_t](repeating: 0, count: Int(count))
        _ = hb_ot_layout_get_ligature_carets(font, HB_DIRECTION_LTR, hb_codepoint_t(glyph), 0, &count, &carets)
        return carets.prefix(Int(count)).map(points)
    }

    /// Design units to points at this font's size (SH-D), as CoreText scales
    /// them: `units × (size / unitsPerEm)`, the ratio taken first. The other
    /// association (`units × size / unitsPerEm`) differs in the last bit, and
    /// a pen summed from those advances lands on the other side of a subpixel
    /// boundary from CoreText's (measured, LB-I, record §31).
    func points(_ units: Int32) -> Double { Double(units) * (size / Double(unitsPerEm)) }
}
