import CUnibreak
import MetalUIHarfBuzz

/// What UAX #14 allows after one UTF-16 unit (ruling LB-B).
public enum LineBreakOpportunity: Sendable, Equatable {
    /// A hard break — after a newline, a paragraph separator, or the end of
    /// the text.
    case mandatory
    /// A soft break a wrapping line may take.
    case allowed
    /// No break: inside a word, before a closing punctuation mark, or after
    /// the high half of a surrogate pair.
    case none
}

/// One display line of a wrapped string (ruling LB-C).
public struct PortableLine: Sendable, Equatable {
    /// The line's UTF-16 units in the source string, its trailing whitespace
    /// and hard break included — the range `CTLineGetStringRange` reports.
    public let range: Range<Int>
    /// The line's advance in points, as the shaper measures the line alone.
    public let advance: Double
}

/// One glyph of a laid-out line, with its pen in points from the line's start
/// (tabs at their stops); its own `xOffset`/`yOffset` still to be added.
struct LinePlacedGlyph {
    /// The glyph drawn — the shaper's, or the space glyph for a control
    /// character.
    let id: UInt16
    let glyph: ShapedGlyph
    /// The face it is drawn in — the requested one or a fallback (FB-A).
    let font: PortableFont
    let penX: Double
}

/// A display line and the glyphs that draw it.
struct LaidOutLine {
    let line: PortableLine
    let glyphs: [LinePlacedGlyph]
}

/// `init_linebreak` fills libunibreak's lookup state once. A `static let` is
/// initialised exactly once, thread-safely, on first use.
private let lineBreakerReady: Void = { init_linebreak() }()

extension PortableText {
    /// For each UTF-16 unit of `text`, whether a line may break after it
    /// (ruling LB-B). The last unit is always ``LineBreakOpportunity/mandatory``
    /// — UAX #14 LB3, the end of the text.
    ///
    /// Asked of libunibreak as `"en-strict"` (ruling LB-L), CoreText's
    /// behaviour: its English tailoring makes U+2018/U+201C opening and U+201D
    /// closing punctuation, and `-strict` keeps small kana (CJ) as
    /// non-starters. Measured over every ordered pair of 47 class samples:
    /// 347 of 4,418 differ from `CFStringTokenizer` with no language, 123
    /// with `"en"`, 0 with `"en-strict"`. Thai still differs (no dictionary,
    /// LB-M).
    public static func lineBreaks(in text: String) -> [LineBreakOpportunity] {
        _ = lineBreakerReady
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }
        var raw = [CChar](repeating: 0, count: units.count)
        units.withUnsafeBufferPointer { source in
            raw.withUnsafeMutableBufferPointer { breaks in
                set_linebreaks_utf16(source.baseAddress, units.count, "en-strict", breaks.baseAddress)
            }
        }
        return raw.map { value in
            switch Int32(value) {
            case LINEBREAK_MUSTBREAK, LINEBREAK_INDETERMINATE: return .mandatory
            case LINEBREAK_ALLOWBREAK: return .allowed
            default: return .none   // NOBREAK, and INSIDEACHAR after a high surrogate
            }
        }
    }
}

extension PortableText {
    /// `text` split into display lines at `width` points (ruling LB-C), with
    /// `Shaper.shape(_:font:wrappingAt:)`'s contract: `nil` is an infinite
    /// width, so one line per hard break; a trailing hard break opens no empty
    /// line; an empty string is one empty line; a non-positive width traps.
    ///
    /// Greedy (ruling LB-D): each line ends at the last break opportunity at
    /// which the line, **without its trailing whitespace**, still fits. A line
    /// with no such opportunity — one word wider than `width` — breaks at the
    /// last cluster boundary that fits, and always keeps at least one cluster.
    public static func lines(_ text: String, font: PortableFont,
                             wrappingAt width: Double?) throws -> [PortableLine] {
        try layOut(text, font: font, wrappingAt: width).map(\.line)
    }

    /// `lines`, with each line's glyphs kept: the glyphs `emitLines` draws
    /// (ruling LB-H) are the ones this measured, so the two cannot drift.
    static func layOut(_ text: String, font: PortableFont,
                       wrappingAt width: Double?) throws -> [LaidOutLine] {
        if let width {
            precondition(width > 0, "PortableText.lines was offered a wrapping width of \(width); "
                         + "a width must be positive (Shaper.shape's contract)")
        }
        let limit = width ?? .infinity
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [LaidOutLine(line: PortableLine(range: 0..<0, advance: 0), glyphs: [])] }

        let breaks = lineBreaks(in: text)
        // UAX #9 over the whole paragraph (ruling BD-A): the levels and scripts
        // shaping itemizes by, and each line's visual order.
        let bidi = BidiParagraph(units)
        // Each glyph's advance is charged to the first unit of its cluster; a
        // cluster's later units (a ligature's second letter, a mark) carry 0.
        // Shaped from `from` to the end: the whole paragraph first, and again
        // from any line start that falls inside a cluster, because the rest of
        // a split ligature is not zero wide (measured, LB-E).
        var unitAdvance = [Double](repeating: 0, count: units.count)
        var clusterStart = [Bool](repeating: false, count: units.count + 1)
        clusterStart[units.count] = true
        // The current shaping's glyphs, and the unit its clusters count from.
        var shaped: [RunGlyph] = []
        var shapedFrom = 0
        func shape(from: Int) throws {
            let rest = String(decoding: units[from...], as: UTF16.self)
            for unit in from..<units.count { unitAdvance[unit] = 0; clusterStart[unit] = false }
            shaped = try shapeCascading(rest, font: font, levels: bidi.levels[from...],
                                        scripts: bidi.scripts[from...])
            shapedFrom = from
            for run in shaped {
                unitAdvance[from + run.cluster] += run.glyph.xAdvance
                clusterStart[from + run.cluster] = true
            }
        }
        try shape(from: 0)

        // Grapheme boundaries, for a cluster too wide for any line: CoreText
        // then breaks it between graphemes — inside a ligature too (measured,
        // LB-E). Swift's `Character` is UAX #29's extended grapheme cluster on
        // every platform.
        var graphemeStart = [Bool](repeating: false, count: units.count + 1)
        var offset = 0
        for character in text {
            graphemeStart[offset] = true
            offset += character.utf16.count
        }
        graphemeStart[units.count] = true

        let ignorable = ignorableUnits(of: text, count: units.count)

        var result: [LaidOutLine] = []
        var start = 0
        while start < units.count {
            // Re-shape from a line start inside a cluster (LB-D), or one that
            // splits lam-alef, Arabic's mandatory ligature (ruling BD-C). Noto
            // Sans Arabic draws lam-alef as two glyphs in two clusters, so the
            // cluster test cannot see it; CoreText still treats the split as a
            // split ligature and re-shapes the new line, leaving its alef
            // unjoined — while at any other break between joined letters it
            // keeps the paragraph's joined forms (measured both ways: an alef
            // and a mim, each the first letter of a line).
            if !clusterStart[start] || splitsLamAlef(units, at: start) { try shape(from: start) }
            var end = units.count
            var lastAllowed: Int?
            var running = 0.0
            var index = start
            while index < units.count {
                running = advancing(running, over: units[index], by: unitAdvance[index])
                // Whitespace hangs: it never makes a line overflow, so a line
                // ends after its trailing spaces, never before them (LB-D).
                if running > limit, index > start, !isBreakingWhitespace(units[index]) {
                    if let lastAllowed {
                        end = lastAllowed
                    } else if let cluster = (start + 1...index).last(where: { clusterStart[$0] }),
                              clusterStart[cluster] {
                        // No opportunity fits: break before the overflowing
                        // cluster (everything before `index` fit).
                        end = cluster
                    } else {
                        end = try graphemeBreak(units: units, from: start, limit: limit, font: font,
                                                graphemeStart: graphemeStart, clusterStart: clusterStart)
                    }
                    break
                }
                if breaks[index] == .mandatory { end = index + 1; break }
                if breaks[index] == .allowed { lastAllowed = index + 1 }
                index += 1
            }
            precondition(end > start, "PortableText.lines made no progress at unit \(start)")
            // The line's advance is its share of the shaping, not the line
            // re-shaped alone: CoreText's line keeps the kerning its last glyph
            // had against the next line's first (measured, LB-E), and a hard
            // break is zero wide there where HarfBuzz gives it a glyph advance.
            // A line that ends inside a cluster cannot take a share of it, and
            // is re-shaped.
            let advance: Double
            let lineGlyphs: [(run: RunGlyph, unit: Int)]
            if clusterStart[end] {
                advance = (start..<end).reduce(0) { advancing($0, over: units[$1], by: unitAdvance[$1]) }
                lineGlyphs = shaped.lazy.map { ($0, shapedFrom + $0.cluster) }
                    .filter { (start..<end).contains($0.1) }
            } else {
                advance = try shapedAdvance(units, start..<end, font: font)
                let alone = String(decoding: units[start..<end], as: UTF16.self)
                lineGlyphs = try shapeCascading(alone, font: font, levels: bidi.levels[start..<end],
                                                scripts: bidi.scripts[start..<end])
                    .map { ($0, start + $0.cluster) }
            }
            // Each glyph's pen from the line's start, walked as the advance was,
            // drawn as CoreText draws it (`drawnGlyph`).
            var pen = 0.0
            // Trailing whitespace hangs outside the line (LB-D). In a
            // right-to-left paragraph UAX #9's L1 puts it at the visual LEFT,
            // and CoreText hangs it off that edge: the line's text starts at
            // the origin and the whitespace sits at negative x (ruling BD-C,
            // measured: every placement difference of the first oracle run).
            if bidi.isRightToLeftParagraph(at: start) {
                var trailing = end
                while trailing > start, isBreakingWhitespace(units[trailing - 1]) { trailing -= 1 }
                pen = -(trailing..<end).reduce(0) { advancing($0, over: units[$1], by: unitAdvance[$1]) }
            }
            var placed: [LinePlacedGlyph] = []
            placed.reserveCapacity(lineGlyphs.count)
            let visual = visualOrder(lineGlyphs.map { (run: $0.run, payload: $0.unit) },
                                     line: start..<end, bidi: bidi, unitOf: { $0 })
            for (run, unit) in visual {
                if let id = drawnGlyph(run.glyph.id, at: units[unit], ignorable: ignorable[unit],
                                       space: run.font.spaceGlyph) {
                    placed.append(LinePlacedGlyph(id: id, glyph: run.glyph, font: run.font, penX: pen))
                }
                pen = advancing(pen, over: units[unit], by: run.glyph.xAdvance)
            }
            result.append(LaidOutLine(line: PortableLine(range: start..<end, advance: advance),
                                      glyphs: placed))
            start = end
        }
        return result
    }

    /// Where a line ends whose first cluster alone is wider than `limit`:
    /// after the longest run of whole graphemes inside that cluster whose
    /// re-shaped advance fits, and never before the first grapheme.
    static func graphemeBreak(units: [UInt16], from start: Int, limit: Double, font: PortableFont,
                              graphemeStart: [Bool], clusterStart: [Bool]) throws -> Int {
        var clusterEnd = start + 1
        while !clusterStart[clusterEnd] { clusterEnd += 1 }
        var best = start + 1
        while !graphemeStart[best] { best += 1 }
        var candidate = best + 1
        while candidate < clusterEnd {
            if graphemeStart[candidate] {
                guard try shapedAdvance(units, start..<candidate, font: font) <= limit else { break }
                best = candidate
            }
            candidate += 1
        }
        return min(best, clusterEnd)
    }

    /// `units[range]` shaped on its own, walked as a line (tabs to their
    /// stops, hard breaks zero wide).
    static func shapedAdvance(_ units: [UInt16], _ range: Range<Int>, font: PortableFont) throws -> Double {
        let line = String(decoding: units[range], as: UTF16.self)
        var perUnit = [Double](repeating: 0, count: range.count)
        for run in try shapeCascading(line, font: font) {
            perUnit[run.cluster] += run.glyph.xAdvance
        }
        return zip(units[range], perUnit).reduce(0) { advancing($0, over: $1.0, by: $1.1) }
    }

    /// CoreText's default tab interval: a tab advances the pen to the next
    /// multiple of 28 points from the line's start, at every font size
    /// (measured at 11, 13, 17 and 26 pt — stops at 28, 56, 84, 112; LB-E).
    static let defaultTabInterval = 28.0

    /// The pen after `unit`, which the shaper measured `advance` wide: a tab
    /// goes to the next stop, a hard break is zero wide (CoreText's line
    /// measures it so, where HarfBuzz gives it a glyph advance), anything
    /// else adds its advance.
    static func advancing(_ pen: Double, over unit: UInt16, by advance: Double) -> Double {
        if unit == 0x09 { return ((pen / defaultTabInterval).rounded(.down) + 1) * defaultTabInterval }
        if isHardBreak(unit) { return pen }
        return pen + advance
    }

    /// The glyph CoreText draws for the glyph HarfBuzz shaped as `id` at
    /// `unit`, or `nil` for none (measured, LB-I):
    ///
    /// - a **default ignorable** (a soft hyphen, a zero-width joiner) draws
    ///   nothing, where HarfBuzz gives it a zero-width space glyph. (CoreText
    ///   reports glyph 0xFFFF for a line that is nothing but one, and draws
    ///   nothing for it either.)
    /// - a **control or hard-break character** the face has no glyph for (a
    ///   newline, a tab, U+2028) draws the space glyph, where HarfBuzz gives it
    ///   `.notdef` — which in most faces is a visible box.
    static func drawnGlyph(_ id: UInt16, at unit: UInt16, ignorable: Bool, space: UInt16) -> UInt16? {
        if ignorable { return nil }
        if id == 0 && (isControl(unit) || isHardBreak(unit)) { return space }
        return id
    }

    /// For each UTF-16 unit of `text`, whether it begins a default-ignorable
    /// scalar. Swift's `Unicode.Scalar.Properties` is the standard library's
    /// own table on every platform.
    static func ignorableUnits(of text: String, count: Int) -> [Bool] {
        var ignorable = [Bool](repeating: false, count: count)
        var offset = 0
        for scalar in text.unicodeScalars {
            ignorable[offset] = scalar.properties.isDefaultIgnorableCodePoint
            offset += scalar.utf16.count
        }
        return ignorable
    }

    /// Whether a line starting at `start` splits lam from a following alef
    /// (U+0644 then U+0622, U+0623, U+0625 or U+0627) — the pair Arabic's
    /// mandatory `rlig` ligature joins.
    static func splitsLamAlef(_ units: [UInt16], at start: Int) -> Bool {
        start > 0 && start < units.count && units[start - 1] == 0x0644
            && [0x0622, 0x0623, 0x0625, 0x0627].contains(units[start])
    }

    /// A C0 or C1 control character — general category Cc.
    static func isControl(_ unit: UInt16) -> Bool {
        unit < 0x20 || (0x7F...0x9F).contains(unit)
    }

    /// UAX #14's hard-break characters (BK, CR, LF, NL).
    static func isHardBreak(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }

    /// Whitespace that hangs past the line's end when fitting: spaces, tabs
    /// and the hard-break characters.
    static func isBreakingWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029, 0x3000: return true
        default: return false
        }
    }
}
