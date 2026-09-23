import MetalUIHarfBuzz

/// One shaped glyph and the face it was shaped in (ruling FB-A): the
/// requested face, or the first fallback that covers its grapheme.
struct RunGlyph {
    let glyph: ShapedGlyph
    let font: PortableFont
    /// The glyph's cluster in UTF-16 units of the whole string shaped.
    let cluster: Int
}

extension PortableText {
    /// `text` shaped with `font`'s cascade (ruling FB-A): each grapheme goes to
    /// the first face — `font`, then `font.fallbacks` in order — that has a
    /// glyph for every scalar of it that draws (default ignorables, controls
    /// and whitespace need none), or to `font` when none does; consecutive
    /// graphemes in one face are shaped as one HarfBuzz run.
    static func shapeCascading(_ text: some StringProtocol, font: PortableFont) throws -> [RunGlyph] {
        let string = String(text)
        if font.fallbacks.isEmpty {
            return try HarfBuzzShaper.shape(string, font: font.shaping).glyphs
                .map { RunGlyph(glyph: $0, font: font, cluster: $0.cluster) }
        }
        var result: [RunGlyph] = []
        var runStart = 0, offset = 0
        var runFont: PortableFont?
        var runText = ""
        func flush() throws {
            guard let face = runFont, !runText.isEmpty else { return }
            let start = runStart
            result += try HarfBuzzShaper.shape(runText, font: face.shaping).glyphs
                .map { RunGlyph(glyph: $0, font: face, cluster: start + $0.cluster) }
        }
        for character in string {
            let face = coveringFace(character, font: font)
            if face !== runFont {
                try flush()
                runFont = face
                runStart = offset
                runText = ""
            }
            runText.append(character)
            offset += character.utf16.count
        }
        try flush()
        return result
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
