import MetalUIHarfBuzz

/// One shaped glyph, the face it was shaped in (ruling FB-A) and the run it
/// came from (ruling BD-B).
struct RunGlyph {
    let glyph: ShapedGlyph
    let font: PortableFont
    /// The glyph's cluster in UTF-16 units of the whole string shaped.
    let cluster: Int
    /// Which shaping run, in logical order — what visual ordering reverses.
    let run: Int
    /// The run's bidi level; odd is right to left.
    let level: UInt8
    /// The styled run it belongs to (ruling RT-F) — 0 for a plain string.
    var style: Int = 0
}

/// The runs of a text being laid out, as the portable pipeline reads them
/// (rulings RT-F, RT-H item 2): one face, kerning and tracking per run, and
/// each UTF-16 unit's run. A plain string is one run (``single(_:)``), and
/// every portable function that took one font takes this — one shaping entry
/// point (`FB-A`).
struct PortableRuns {
    let fonts: [PortableFont]
    let kerning: [Double]
    let tracking: [Double]
    /// Each UTF-16 unit's run, over the whole styled string; `nil` is one run.
    let runOfUnit: [Int]?
    /// Every unit's run is this one (an ellipsis token's, RT-I).
    let fixedRun: Int?

    /// A plain string's: one run in `font`, no kerning or tracking.
    static func single(_ font: PortableFont) -> PortableRuns {
        PortableRuns(fonts: [font], kerning: [0], tracking: [0], runOfUnit: nil, fixedRun: nil)
    }

    /// The run of unit `unit` of the styled string.
    func run(at unit: Int) -> Int {
        if let fixedRun { return fixedRun }
        guard let runOfUnit, !runOfUnit.isEmpty else { return 0 }
        return runOfUnit[min(max(unit, 0), runOfUnit.count - 1)]
    }

    /// These runs with every unit in run `run`.
    func fixed(_ run: Int) -> PortableRuns {
        PortableRuns(fonts: fonts, kerning: kerning, tracking: tracking, runOfUnit: runOfUnit, fixedRun: run)
    }

    /// Whether this is one run with no kerning or tracking — the plain path.
    var isPlain: Bool { fonts.count == 1 && kerning[0] == 0 && tracking[0] == 0 }
}

extension PortableText {
    /// `text` itemized and shaped (rulings FB-A, BD-B): runs split wherever the
    /// face (the cascade's first covering face per grapheme), the bidi level
    /// or the script changes, each shaped in its level's direction, in logical
    /// order. `levels` and `scripts` are the text's own, per UTF-16 unit — a
    /// slice of the paragraph's when this is part of one; `nil` runs the bidi
    /// algorithm on `text` alone.
    static func shapeCascading(_ text: some StringProtocol, font: PortableFont,
                               levels: ArraySlice<UInt8>? = nil,
                               scripts: ArraySlice<UInt8>? = nil) throws -> [RunGlyph] {
        try shapeCascading(text, runs: .single(font), base: 0, levels: levels, scripts: scripts)
    }

    /// ``shapeCascading(_:font:levels:scripts:)`` over styled runs (ruling
    /// RT-H item 2): `text` is the styled string's units from `base` on, each
    /// unit's covering face is chosen from **its run's** font and that font's
    /// fallbacks, and a shaping run does **not** split at a style change that
    /// keeps the face: CoreText keeps a face's pair kerning across a boundary
    /// where only the kerning, tracking or baseline offset changes (measured,
    /// ruling RT-P item 3), so tracking turns the optional ligatures off
    /// (RT-H item 3) by a feature range over its units instead. Each
    /// grapheme's kerning and tracking — its first unit's run's — are added
    /// once, to the advance of its last glyph, after HarfBuzz (ruling RT-P
    /// item 4).
    static func shapeCascading(_ text: some StringProtocol, runs: PortableRuns, base: Int,
                               levels: ArraySlice<UInt8>? = nil,
                               scripts: ArraySlice<UInt8>? = nil) throws -> [RunGlyph] {
        let string = String(text)
        let units = Array(string.utf16)
        let (levels, scripts): ([UInt8], [UInt8]) = {
            if let levels, let scripts { return (Array(levels), Array(scripts)) }
            let bidi = BidiParagraph(units)
            return (bidi.levels, bidi.scripts)
        }()
        var result: [RunGlyph] = []
        var runStart = 0, offset = 0, runIndex = 0
        var runKey: (font: PortableFont, level: UInt8, script: UInt8)?
        var runText = ""
        // The run's tracked units (relative to its start), whose optional
        // ligatures are off; a plain run has none, and shapes with no feature
        // list (SH-E).
        var tracked: [Range<Int>] = []
        func flush() throws {
            guard let key = runKey, !runText.isEmpty else { return }
            let start = runStart, index = runIndex
            let direction: ShapingDirection = key.level % 2 == 1 ? .rightToLeft : .leftToRight
            let glyphs = try HarfBuzzShaper.shape(runText, font: key.font.shaping, direction: direction,
                                                  features: tracked.flatMap { ShapingFeature.ligaturesOff(over: $0) }).glyphs
            // Each unit's grapheme's first unit: kerning and tracking are added
            // once per grapheme (a ligature of several counting once), on its
            // last glyph in HarfBuzz's (visual) order — CoreText's rule,
            // measured on combining marks, Arabic and ligatures (ruling RT-P
            // item 4). Only computed when the run has spacing.
            var grapheme: [Int] = []
            if !runs.isPlain {
                grapheme.reserveCapacity(runText.utf16.count)
                var unit = 0
                for character in runText {
                    let width = character.utf16.count
                    grapheme.append(contentsOf: repeatElement(unit, count: width))
                    unit += width
                }
            }
            result += glyphs.indices.map { position in
                let glyph = glyphs[position]
                let style = runs.run(at: base + start + glyph.cluster)
                let spacingRun = grapheme.isEmpty ? style : runs.run(at: base + start + grapheme[glyph.cluster])
                let spacing = runs.kerning[spacingRun] + runs.tracking[spacingRun]
                let endsGrapheme = spacing == 0 || position == glyphs.count - 1
                    || grapheme[glyphs[position + 1].cluster] != grapheme[glyph.cluster]
                let extra = endsGrapheme ? spacing : 0
                let spaced = extra == 0 ? glyph
                    : ShapedGlyph(id: glyph.id, cluster: glyph.cluster, xAdvance: glyph.xAdvance + extra,
                                  yAdvance: glyph.yAdvance, xOffset: glyph.xOffset, yOffset: glyph.yOffset)
                return RunGlyph(glyph: spaced, font: key.font, cluster: start + glyph.cluster, run: index,
                                level: key.level, style: style)
            }
            runIndex += 1
        }
        for character in string {
            let style = runs.run(at: base + offset)
            let font = runs.fonts[style]
            let face = font.fallbacks.isEmpty ? font : coveringFace(character, font: font)
            let level = offset < levels.count ? levels[offset] : 0
            let script = offset < scripts.count ? scripts[offset] : 0
            if runKey == nil || face !== runKey!.font || level != runKey!.level || script != runKey!.script {
                try flush()
                runKey = (face, level, script)
                runStart = offset
                runText = ""
                tracked = []
            }
            let width = character.utf16.count
            if runs.tracking[style] != 0 {
                let local = offset - runStart
                if let last = tracked.last, last.upperBound == local {
                    tracked[tracked.count - 1] = last.lowerBound..<(local + width)
                } else {
                    tracked.append(local..<(local + width))
                }
            }
            runText.append(character)
            offset += width
        }
        try flush()
        return result
    }

    /// `glyphs` — one line's, in logical order — in visual order, left to
    /// right (ruling BD-C): the line's bidi runs as UAX #9 orders them, a
    /// right-to-left run's shaping runs reversed, and each shaping run's glyphs
    /// in HarfBuzz's order, which is already visual.
    static func visualOrder<Payload>(_ glyphs: [(run: RunGlyph, payload: Payload)], line: Range<Int>,
                                     bidi: BidiParagraph?, unitOf: (Payload) -> Int)
        -> [(run: RunGlyph, payload: Payload)] {
        guard let bidi, bidi.isMixed else { return glyphs }
        var ordered: [(run: RunGlyph, payload: Payload)] = []
        ordered.reserveCapacity(glyphs.count)
        for visual in bidi.visualRuns(line) {
            let inside = glyphs.filter { visual.range.contains(unitOf($0.payload)) }
            var runs: [Int] = []
            for glyph in inside where runs.last != glyph.run.run { runs.append(glyph.run.run) }
            if visual.level % 2 == 1 { runs.reverse() }
            for run in runs { ordered += inside.filter { $0.run.run == run } }
        }
        return ordered
    }

    /// The face that draws `character`: the first in the cascade covering every
    /// scalar that needs a glyph.
    static func coveringFace(_ character: Character, font: PortableFont) -> PortableFont {
        let needed = character.unicodeScalars.filter { scalar in
            !(scalar.properties.isDefaultIgnorableCodePoint || scalar.properties.isWhitespace
              || scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value))
        }
        if needed.isEmpty { return font }
        for face in [font] + font.fallbacks where needed.allSatisfy({ face.raster.glyph(for: $0) != 0 }) {
            return face
        }
        return font
    }
}
