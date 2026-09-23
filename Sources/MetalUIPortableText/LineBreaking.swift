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

/// `init_linebreak` fills libunibreak's lookup state once. A `static let` is
/// initialised exactly once, thread-safely, on first use.
private let lineBreakerReady: Void = { init_linebreak() }()

extension PortableText {
    /// For each UTF-16 unit of `text`, whether a line may break after it
    /// (ruling LB-B). The last unit is always ``LineBreakOpportunity/mandatory``
    /// — UAX #14 LB3, the end of the text.
    public static func lineBreaks(in text: String) -> [LineBreakOpportunity] {
        _ = lineBreakerReady
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }
        var raw = [CChar](repeating: 0, count: units.count)
        units.withUnsafeBufferPointer { source in
            raw.withUnsafeMutableBufferPointer { breaks in
                set_linebreaks_utf16(source.baseAddress, units.count, nil, breaks.baseAddress)
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
        if let width {
            precondition(width > 0, "PortableText.lines was offered a wrapping width of \(width); "
                         + "a width must be positive (Shaper.shape's contract)")
        }
        let limit = width ?? .infinity
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [PortableLine(range: 0..<0, advance: 0)] }

        let breaks = lineBreaks(in: text)
        // Each glyph's advance is charged to the first unit of its cluster; a
        // cluster's later units (a ligature's second letter, a mark) carry 0.
        // Shaped from `from` to the end: the whole paragraph first, and again
        // from any line start that falls inside a cluster, because the rest of
        // a split ligature is not zero wide (measured, LB-E).
        var unitAdvance = [Double](repeating: 0, count: units.count)
        var clusterStart = [Bool](repeating: false, count: units.count + 1)
        clusterStart[units.count] = true
        func shape(from: Int) throws {
            let rest = String(decoding: units[from...], as: UTF16.self)
            for unit in from..<units.count { unitAdvance[unit] = 0; clusterStart[unit] = false }
            for glyph in try HarfBuzzShaper.shape(rest, font: font.shaping).glyphs {
                unitAdvance[from + glyph.cluster] += glyph.xAdvance
                clusterStart[from + glyph.cluster] = true
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

        var result: [PortableLine] = []
        var start = 0
        while start < units.count {
            if !clusterStart[start] { try shape(from: start) }
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
            if clusterStart[end] {
                advance = (start..<end).reduce(0) { advancing($0, over: units[$1], by: unitAdvance[$1]) }
            } else {
                advance = try shapedAdvance(units, start..<end, font: font)
            }
            result.append(PortableLine(range: start..<end, advance: advance))
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
        for glyph in try HarfBuzzShaper.shape(line, font: font.shaping).glyphs {
            perUnit[glyph.cluster] += glyph.xAdvance
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
