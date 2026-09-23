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

    /// Design units to points at this font's size (SH-D).
    func points(_ units: Int32) -> Double { Double(units) * size / Double(unitsPerEm) }
}
