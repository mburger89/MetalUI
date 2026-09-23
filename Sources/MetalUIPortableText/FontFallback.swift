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
        func flush() throws {
            guard let key = runKey, !runText.isEmpty else { return }
            let start = runStart, index = runIndex
            let direction: ShapingDirection = key.level % 2 == 1 ? .rightToLeft : .leftToRight
            result += try HarfBuzzShaper.shape(runText, font: key.font.shaping, direction: direction).glyphs
                .map { RunGlyph(glyph: $0, font: key.font, cluster: start + $0.cluster, run: index, level: key.level) }
            runIndex += 1
        }
        for character in string {
            let face = font.fallbacks.isEmpty ? font : coveringFace(character, font: font)
            let level = offset < levels.count ? levels[offset] : 0
            let script = offset < scripts.count ? scripts[offset] : 0
            if runKey == nil || face !== runKey!.font || level != runKey!.level || script != runKey!.script {
                try flush()
                runKey = (face, level, script)
                runStart = offset
                runText = ""
            }
            runText.append(character)
            offset += character.utf16.count
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
