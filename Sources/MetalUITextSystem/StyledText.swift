// The styled-text seam (ruling RT-F): a string in runs of layout attributes,
// what both text systems measure, wrap, truncate, shape and place. Paint-only
// attributes (colours, underline, strikethrough, background, link) never
// cross it — they are MetalUI's, applied to the layout's run indices.
// Foundation-free, like the rest of this module (TS-A).

/// The layout attributes of one run of a ``StyledText`` (ruling RT-F item 1):
/// the attributes that change where glyphs go.
public struct TextRunStyle: Hashable, Sendable {
    /// The run's resolved face (`TextSystem.resolveFont`).
    public var font: FontKey
    /// Points added after every glyph of the run, the last included; a
    /// ligature counts once and is kept (ruling RT-H item 3). `0` is no extra
    /// space — the face's own pair kerning stays (`RT-O` item 7).
    public var kerning: Double
    /// Points added after every glyph of the run, the last included, with the
    /// face's optional ligatures off (ruling RT-H item 3). `0` is no extra
    /// space.
    public var tracking: Double
    /// Points the run's glyphs are raised (negative lowers); the line grows to
    /// hold them (rulings RT-G item 1, RT-H item 4).
    public var baselineOffset: Double

    /// A run style; only the face is required.
    public init(font: FontKey, kerning: Double = 0, tracking: Double = 0, baselineOffset: Double = 0) {
        self.font = font
        self.kerning = kerning
        self.tracking = tracking
        self.baselineOffset = baselineOffset
    }
}

/// One run of a ``StyledText``: `length` UTF-16 units in `style`.
public struct StyledTextRun: Hashable, Sendable {
    /// The run's length in UTF-16 units — the unit of every range at the seam
    /// (`TI-H`).
    public var length: Int
    /// The run's layout attributes.
    public var style: TextRunStyle

    /// A run of `length` UTF-16 units.
    public init(length: Int, style: TextRunStyle) {
        self.length = length
        self.style = style
    }
}

/// A string in styled runs (ruling RT-F item 1), normalized: no zero-length
/// run (an empty string keeps exactly one, its first run's style, for its one
/// empty line — `C17`) and no two equal neighbours.
public struct StyledText: Hashable, Sendable {
    /// The whole string.
    public let string: String
    /// The runs, in order, covering ``string``'s UTF-16 units exactly.
    public let runs: [StyledTextRun]

    /// `string` in `runs`. Traps unless `runs` is non-empty and its lengths
    /// (each non-negative) sum to `string.utf16.count`; drops zero-length runs
    /// and merges equal neighbours.
    public init(_ string: String, runs: [StyledTextRun]) {
        precondition(!runs.isEmpty, "StyledText needs at least one run, even for an empty string")
        precondition(runs.allSatisfy { $0.length >= 0 }, "StyledText: a run's length cannot be negative")
        let total = runs.reduce(0) { $0 + $1.length }
        let count = string.utf16.count
        precondition(total == count, """
            StyledText: the runs' lengths sum to \(total) UTF-16 units, but the string has \(count). \
            Every unit belongs to exactly one run (ruling RT-F item 1).
            """)
        self.string = string
        guard count > 0 else {
            self.runs = [StyledTextRun(length: 0, style: runs[0].style)]
            return
        }
        var normalized: [StyledTextRun] = []
        for run in runs where run.length > 0 {
            if let last = normalized.last, last.style == run.style {
                normalized[normalized.count - 1].length += run.length
            } else {
                normalized.append(run)
            }
        }
        self.runs = normalized
    }

    /// `string` as one run in `style`.
    public init(_ string: String, style: TextRunStyle) {
        self.init(string, runs: [StyledTextRun(length: string.utf16.count, style: style)])
    }

    /// Each run's first UTF-16 unit, and the string's length last
    /// (`runs.count + 1` values).
    package var runBoundaries: [Int] {
        var boundaries = [0]
        boundaries.reserveCapacity(runs.count + 1)
        for run in runs { boundaries.append(boundaries[boundaries.count - 1] + run.length) }
        return boundaries
    }

    /// The run index of every UTF-16 unit.
    package var runOfUnit: [Int] {
        var result: [Int] = []
        result.reserveCapacity(string.utf16.count)
        for (index, run) in runs.enumerated() {
            result.append(contentsOf: repeatElement(index, count: run.length))
        }
        return result
    }
}

/// One laid-out line of a ``StyledText`` (ruling RT-G).
public struct TextLineBox: Hashable, Sendable {
    /// The line's UTF-16 units, its trailing whitespace and hard break
    /// included — `CTLineGetStringRange`'s range; a truncated last line runs
    /// to the string's end (`TI-H`).
    public let range: Range<Int>
    /// The line's top, from the text box's top, in points.
    public let top: Double
    /// `ceil(ascent + descent + leading)` over the line's runs, each run's
    /// ascent raised and descent lowered by its baseline offset (ruling RT-G
    /// item 1).
    public let height: Double
    /// The line's baseline, from the text box's top, unrounded:
    /// `top + ascent` (ruling RT-G item 2).
    public let baseline: Double
    /// The line's advance in points, its trailing whitespace included.
    public let width: Double
    /// The pen x of the line's first glyph that is not whitespace, in points
    /// from the line's aligned start (`offsetX` not included); 0 for a line
    /// of only whitespace.
    public let visibleMinX: Double
    /// The end of the line's last glyph that is not whitespace (its advance
    /// and kerning included, its tracking not — `CTLineGetTrailingWhitespaceWidth`'s
    /// rule), in points from the line's aligned start; 0 for a line of only
    /// whitespace.
    public let visibleMaxX: Double
    /// The alignment offset applied to this line, in points (ruling TE-J).
    public let offsetX: Double

    /// A line box from its values.
    public init(range: Range<Int>, top: Double, height: Double, baseline: Double, width: Double,
                visibleMinX: Double, visibleMaxX: Double, offsetX: Double) {
        self.range = range
        self.top = top
        self.height = height
        self.baseline = baseline
        self.width = width
        self.visibleMinX = visibleMinX
        self.visibleMaxX = visibleMaxX
        self.offsetX = offsetX
    }
}

/// A measured ``StyledText`` (ruling RT-F item 2): the widest kept line, the
/// total height and each kept line's box.
public struct StyledTextMeasurement: Hashable, Sendable {
    /// The widest kept (or truncated) line's advance, in points.
    public let widestLine: Double
    /// The sum of the kept lines' heights, in points.
    public let totalHeight: Double
    /// Each kept line, in order.
    public let lines: [TextLineBox]

    /// A measurement from its values.
    public init(widestLine: Double, totalHeight: Double, lines: [TextLineBox]) {
        self.widestLine = widestLine
        self.totalHeight = totalHeight
        self.lines = lines
    }
}

/// One placed glyph of a ``StyledText`` and the run it belongs to.
public struct StyledGlyph: Hashable, Sendable {
    /// The glyph, placed as `TextSystem.placeGlyphs` places one.
    public let glyph: TextGlyph
    /// Its run's index into ``StyledText/runs``; a truncation's ellipsis takes
    /// the run of the first character the truncation removed (ruling RT-I).
    public let run: Int

    /// A styled glyph.
    public init(glyph: TextGlyph, run: Int) {
        self.glyph = glyph
        self.run = run
    }

    /// Hashes the glyph's key, pixel, baseline and run.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(glyph.key)
        hasher.combine(glyph.pixelX)
        hasher.combine(glyph.baselineY)
        hasher.combine(run)
    }
}

/// One visual piece of one run on one line (ruling RT-F item 2): what a
/// background, underline or strikethrough spans.
public struct TextRunSegment: Hashable, Sendable {
    /// The run's index into ``StyledText/runs``.
    public let run: Int
    /// The line's index into ``StyledTextMeasurement/lines``.
    public let line: Int
    /// The piece's left edge, in window points (the layout's origin applied).
    public let minX: Double
    /// The piece's right edge — its last glyph's advance, kerning and
    /// tracking included — in window points.
    public let maxX: Double
    /// The run's baseline, in window points: the line's baseline less the
    /// run's baseline offset (y down).
    public let baseline: Double

    /// A segment from its values.
    public init(run: Int, line: Int, minX: Double, maxX: Double, baseline: Double) {
        self.run = run
        self.line = line
        self.minX = minX
        self.maxX = maxX
        self.baseline = baseline
    }
}

/// A placed ``StyledText``: its measurement, every glyph with its run, and
/// every run segment (ruling RT-F item 2).
public struct StyledTextLayout: Hashable, Sendable {
    /// The lines, as ``TextSystem/measure(_:wrappingAt:options:)`` measures
    /// them.
    public let measurement: StyledTextMeasurement
    /// Every glyph, line by line, in visual order.
    public let glyphs: [StyledGlyph]
    /// One per (run, line, visual piece), line by line, in visual order.
    public let segments: [TextRunSegment]

    /// A layout from its values.
    public init(measurement: StyledTextMeasurement, glyphs: [StyledGlyph], segments: [TextRunSegment]) {
        self.measurement = measurement
        self.glyphs = glyphs
        self.segments = segments
    }
}

/// A face's decoration metrics at its size, in points (ruling RT-J item 2).
public struct TextDecorationMetrics: Hashable, Sendable {
    /// The underline's centre, from the baseline, negative below it —
    /// `CTFontGetUnderlinePosition`, the `post` table's `underlinePosition`.
    public let underlinePosition: Double
    /// The underline's thickness — the `post` table's `underlineThickness`.
    public let underlineThickness: Double
    /// The strikethrough's centre above the baseline: half the face's
    /// x-height (ruling RT-J item 2).
    public let strikethroughPosition: Double

    /// Decoration metrics from their values.
    public init(underlinePosition: Double, underlineThickness: Double, strikethroughPosition: Double) {
        self.underlinePosition = underlinePosition
        self.underlineThickness = underlineThickness
        self.strikethroughPosition = strikethroughPosition
    }
}

/// Arithmetic both text systems share for a styled layout, so it exists once
/// (ruling RT-G).
package enum StyledTextLines {
    /// Whitespace that hangs at a line's end and is outside its visible extent:
    /// spaces, tabs, the hard breaks and the ideographic space — the portable
    /// line breaker's `isBreakingWhitespace` set.
    package static func isLineWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029, 0x3000: return true
        default: return false
        }
    }

    /// One line's ascent, descent and leading over the runs on it (ruling
    /// RT-G item 1): each run's face metrics, its ascent raised by a positive
    /// baseline offset and its descent lowered by a negative one.
    package static func lineMetrics(runs: some Sequence<Int>, styles: [TextRunStyle],
                                    metrics: (FontKey) -> TextFontMetrics)
        -> (ascent: Double, descent: Double, leading: Double) {
        var ascent = -Double.infinity, descent = -Double.infinity, leading = -Double.infinity
        for run in runs {
            let style = styles[run]
            let face = metrics(style.font)
            ascent = max(ascent, face.ascent + max(0, style.baselineOffset))
            descent = max(descent, face.descent + max(0, -style.baselineOffset))
            leading = max(leading, face.leading)
        }
        return ascent.isFinite ? (ascent, descent, leading) : (0, 0, 0)
    }

    /// The runs a line's units belong to, in first-seen order; a line with no
    /// unit takes the run at its start (an empty string's one empty line).
    package static func runs(in ranges: [Range<Int>], runOfUnit: [Int], fallback: Int) -> [Int] {
        var seen: [Int] = []
        for range in ranges {
            for unit in range where !seen.contains(runOfUnit[unit]) { seen.append(runOfUnit[unit]) }
        }
        return seen.isEmpty ? [fallback] : seen
    }
}
