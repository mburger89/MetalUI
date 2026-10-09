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
    /// How far the pen moves right after this glyph, in points.
    public let xAdvance: Double
    /// How far the pen moves up after this glyph, in points.
    public let yAdvance: Double
    /// The glyph's horizontal offset from the pen, in points.
    public let xOffset: Double
    /// The glyph's vertical offset from the pen, in points.
    public let yOffset: Double

    /// A shaped glyph from its values — for the portable text system, which
    /// adds a run's kerning and tracking to `xAdvance` (ruling RT-H item 3).
    package init(id: UInt16, cluster: Int, xAdvance: Double, yAdvance: Double, xOffset: Double, yOffset: Double) {
        self.id = id
        self.cluster = cluster
        self.xAdvance = xAdvance
        self.yAdvance = yAdvance
        self.xOffset = xOffset
        self.yOffset = yOffset
    }
}

/// An OpenType feature setting for one shaping call (ruling RT-H item 3): a
/// four-letter tag and its value — 0 turns the feature off — over the whole
/// run or a range of its UTF-16 units (ruling RT-P item 3).
package struct ShapingFeature: Hashable, Sendable {
    /// The feature's tag, e.g. `"liga"`.
    package let tag: String
    /// The feature's value; 0 is off, 1 on.
    package let value: UInt32
    /// The UTF-16 units of the shaped text it applies to (cluster values,
    /// SH-C); `nil` is the whole run.
    package let range: Range<Int>?

    /// A feature setting over `range` of the run's UTF-16 units, or the whole
    /// run.
    package init(_ tag: String, _ value: UInt32, range: Range<Int>? = nil) {
        precondition(tag.utf8.count == 4, "an OpenType feature tag is four ASCII letters")
        self.tag = tag
        self.value = value
        self.range = range
    }

    /// The optional ligatures off over `range` of the run's UTF-16 units.
    package static func ligaturesOff(over range: Range<Int>) -> [ShapingFeature] {
        ["liga", "clig", "dlig", "hlig"].map { ShapingFeature($0, 0, range: range) }
    }

    /// The optional ligatures — `liga`, `clig`, `dlig`, `hlig` — off: what
    /// tracking shapes with (CoreText's `kCTTrackingAttributeName` breaks
    /// them, `C8e`).
    package static let ligaturesOff: [ShapingFeature] = ["liga", "clig", "dlig", "hlig"].map { ShapingFeature($0, 0) }
}

/// One run's shaped glyphs, in **visual order**: left to right, as a
/// renderer places them, for a right-to-left run too.
public struct ShapedRun: Equatable, Sendable {
    /// The glyphs, left to right.
    public let glyphs: [ShapedGlyph]
    /// The run's total advance, in points.
    public let advance: Double
    /// Whether the run was shaped right to left.
    public let isRightToLeft: Bool
}

/// The direction a run is shaped in.
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
    /// Shapes `text` as one run in `font`, in visual order; throws if HarfBuzz
    /// fails.
    public static func shape(_ text: String, font: HarfBuzzFont,
                             direction: ShapingDirection = .auto) throws -> ShapedRun {
        try shape(text, font: font, direction: direction, features: [])
    }

    /// ``shape(_:font:direction:)`` with `features` applied, each over its
    /// range or the whole run (rulings RT-H item 3, RT-P item 3); `[]` is
    /// exactly ``shape(_:font:direction:)``.
    package static func shape(_ text: String, font: HarfBuzzFont, direction: ShapingDirection,
                              features: [ShapingFeature]) throws -> ShapedRun {
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
        // which is what CoreText applies to an OpenType font. A feature list
        // (RT-H item 3: tracking turns the optional ligatures off) applies
        // each setting over its range; an empty one is exactly the call SH-E
        // makes.
        if features.isEmpty {
            hb_shape(font.font, buffer, nil, 0)
        } else {
            let settings = features.map { feature in
                hb_feature_t(tag: feature.tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) },
                             value: feature.value,
                             start: feature.range.map { UInt32($0.lowerBound) } ?? 0,
                             end: feature.range.map { UInt32($0.upperBound) } ?? UInt32.max)
            }
            settings.withUnsafeBufferPointer { hb_shape(font.font, buffer, $0.baseAddress, UInt32($0.count)) }
        }

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
