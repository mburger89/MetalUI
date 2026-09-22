import CFreeType
import MetalUIScene

/// Turns a glyph into a coverage bitmap with FreeType, under exactly
/// `GlyphRaster`'s contract (rulings FT-C…FT-E), so the atlas and every
/// backend take either rasterizer's output unchanged.
public enum FreeTypeRaster {
    /// Rasterizes `glyph` from `font` at `scaleFactor` device pixels per point,
    /// shifted right by `subpixelVariant / GlyphImage.subpixelVariants` of a
    /// device pixel. Same preconditions as `GlyphRaster.rasterize`.
    ///
    /// **The bitmap's size and bearings come from the outline, not from
    /// FreeType's renderer** (FT-D): the ink box is the outline's exact
    /// bounding box, floored/ceiled and grown by `GlyphImage.inkPadding`, the
    /// same arithmetic as `GlyphRaster`; the outline is then rendered into a
    /// buffer of exactly that size. Letting `FT_Render_Glyph` pick its own
    /// rectangle would make the two rasterizers disagree on size for reasons
    /// neither test could name.
    ///
    /// **Unhinted, grayscale** (FT-E): CoreText on macOS applies no hinting and
    /// (spec §6.1) only grayscale antialiasing.
    public static func rasterize(glyph: UInt16, font: FreeTypeFont,
                                 subpixelVariant: Int, scaleFactor: Float) throws -> GlyphImage {
        precondition(subpixelVariant >= 0 && subpixelVariant < GlyphImage.subpixelVariants,
                     "subpixel variant \(subpixelVariant) is outside 0..<\(GlyphImage.subpixelVariants)")
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let face = font.face

        // 72 dpi: one point is one device pixel at scale 1, as in CoreText.
        let pixels = font.size * Double(scaleFactor)
        try check(FT_Set_Char_Size(face, 0, FT_F26Dot6((pixels * 64).rounded()), 72, 72), "FT_Set_Char_Size")
        try check(FT_Load_Glyph(face, FT_UInt(glyph), Int32(FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)), "FT_Load_Glyph")
        guard let slot = face.pointee.glyph, slot.pointee.format == FT_GLYPH_FORMAT_OUTLINE else {
            throw FreeTypeError(operation: "an outline glyph", code: -1)
        }
        var outline = slot.pointee.outline
        guard outline.n_points > 0 else { return .empty }

        // The subpixel shift, in 26.6: a quarter pixel is exactly 16 units.
        let dx = GlyphImage.subpixelOffset(variant: subpixelVariant)
        FT_Outline_Translate(&outline, FT_Pos((dx * 64).rounded()), 0)

        var box = FT_BBox()
        try check(FT_Outline_Get_BBox(&outline, &box), "FT_Outline_Get_BBox")
        guard box.xMin < box.xMax, box.yMin < box.yMax else { return .empty }

        let pad = GlyphImage.inkPadding
        let x0 = Int(floorDiv64(box.xMin)) - pad
        let y0 = Int(floorDiv64(box.yMin)) - pad
        let x1 = Int(ceilDiv64(box.xMax)) + pad
        let y1 = Int(ceilDiv64(box.yMax)) + pad
        let width = x1 - x0, height = y1 - y0
        guard width > 0, height > 0 else { return .empty }

        // Move the box's bottom-left to the bitmap origin. With a positive
        // pitch FreeType fills rows top-down, so row 0 is the top row — the
        // same memory order as GlyphRaster's CGBitmapContext.
        FT_Outline_Translate(&outline, FT_Pos(-x0 * 64), FT_Pos(-y0 * 64))
        var bytes = [UInt8](repeating: 0, count: width * height)
        try bytes.withUnsafeMutableBufferPointer { buffer in
            var bitmap = FT_Bitmap()
            bitmap.rows = UInt32(height)
            bitmap.width = UInt32(width)
            bitmap.pitch = Int32(width)
            bitmap.buffer = buffer.baseAddress
            bitmap.num_grays = 256
            bitmap.pixel_mode = UInt8(FT_PIXEL_MODE_GRAY.rawValue)
            try check(FT_Outline_Get_Bitmap(font.library, &outline, &bitmap), "FT_Outline_Get_Bitmap")
        }
        return GlyphImage(width: width, height: height, bytes: bytes, left: x0, top: y1)
    }

    private static func check(_ error: FT_Error, _ operation: String) throws {
        if error != 0 { throw FreeTypeError(operation: operation, code: error) }
    }

    /// Floor and ceiling of a 26.6 value in whole pixels, exactly (no Double).
    private static func floorDiv64(_ v: FT_Pos) -> FT_Pos { v >> 6 }
    private static func ceilDiv64(_ v: FT_Pos) -> FT_Pos { (v + 63) >> 6 }
}
