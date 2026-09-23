import CHarfBuzz

/// One shaped glyph (ruling SH-C). Positions are in **points**.
public struct ShapedGlyph: Equatable, Sendable {
    /// The face's glyph id — the same id `FreeTypeRaster` rasterizes (SH-H).
    public let id: UInt16
    /// Offset of the character this glyph came from, in **UTF-16 units** —
    /// the unit CoreText's string indices use, so the two are comparable.
    /// One glyph can cover several characters (a ligature), so clusters do not
    /// increase by one per glyph; a combining mark reports its own offset, not
    /// its base's (`MONOTONE_CHARACTERS`, matching CoreText's string indices).
    public let cluster: Int
    public let xAdvance: Double
    public let yAdvance: Double
    public let xOffset: Double
    public let yOffset: Double
}

/// One run's shaped glyphs, in **visual order**: left to right, as a
/// renderer places them, for a right-to-left run too.
public struct ShapedRun: Equatable, Sendable {
    public let glyphs: [ShapedGlyph]
    /// The run's total advance, in points.
    public let advance: Double
    public let isRightToLeft: Bool
}

public enum ShapingDirection: Sendable {
    /// Let HarfBuzz guess direction, script and language from the text.
    case auto
    case leftToRight
    case rightToLeft
}

/// Shapes one run — one font, one direction, one script, one line (SH-C).
///
/// Line breaking, bidi across runs, script itemization and font fallback are
/// **not** here; `MetalUIText`'s `Shaper` still does all of that with
/// CoreText on Apple platforms (SH-J).
public enum HarfBuzzShaper {
    public static func shape(_ text: String, font: HarfBuzzFont,
                             direction: ShapingDirection = .auto) throws -> ShapedRun {
        guard let buffer = hb_buffer_create(), hb_buffer_allocation_successful(buffer) != 0 else {
            throw HarfBuzzError(operation: "hb_buffer_create")
        }
        defer { hb_buffer_destroy(buffer) }

        // Clusters are UTF-16 offsets (SH-C): feed HarfBuzz UTF-16 so its
        // cluster values index the same units CoreText reports.
        //
        // MONOTONE_CHARACTERS, not HarfBuzz's default MONOTONE_GRAPHEMES: the
        // default merges a combining mark into its base's cluster, so a mark
        // reports its base's offset. Measured against CoreText's string
        // indices over the whole oracle corpus, this level makes the Arabic
        // harakat case agree exactly and changes nothing else — no id, no
        // other cluster, no position (record §26).
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { units in
            hb_buffer_add_utf16(buffer, units.baseAddress, Int32(units.count), 0, Int32(units.count))
        }
        hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS)
        switch direction {
        case .auto: hb_buffer_guess_segment_properties(buffer)
        case .leftToRight, .rightToLeft:
            hb_buffer_set_direction(buffer, direction == .leftToRight ? HB_DIRECTION_LTR : HB_DIRECTION_RTL)
            hb_buffer_guess_segment_properties(buffer)  // script and language only; direction is set
        }
        // SH-E: no feature list — each script's required and default features,
        // which is what CoreText applies to an OpenType font.
        hb_shape(font.font, buffer, nil, 0)

        let count = Int(hb_buffer_get_length(buffer))
        let infos = hb_buffer_get_glyph_infos(buffer, nil)
        let positions = hb_buffer_get_glyph_positions(buffer, nil)
        guard count == 0 || (infos != nil && positions != nil) else {
            throw HarfBuzzError(operation: "hb_buffer_get_glyph_infos")
        }
        var glyphs: [ShapedGlyph] = []
        glyphs.reserveCapacity(count)
        var advance = 0.0
        for index in 0..<count {
            let info = infos![index], position = positions![index]
            glyphs.append(ShapedGlyph(
                id: UInt16(truncatingIfNeeded: info.codepoint),
                cluster: Int(info.cluster),
                xAdvance: font.points(position.x_advance), yAdvance: font.points(position.y_advance),
                xOffset: font.points(position.x_offset), yOffset: font.points(position.y_offset)))
            advance += font.points(position.x_advance)
        }
        // HarfBuzz already returns a right-to-left run in visual order.
        // HB_DIRECTION_IS_BACKWARD is a C macro, so the cases are spelled out.
        let shapedDirection = hb_buffer_get_direction(buffer)
        return ShapedRun(glyphs: glyphs, advance: advance,
                         isRightToLeft: shapedDirection == HB_DIRECTION_RTL
                                     || shapedDirection == HB_DIRECTION_BTT)
    }
}
