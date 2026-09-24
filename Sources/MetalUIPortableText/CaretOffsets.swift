extension PortableText {
    /// The x offset of every grapheme boundary of `text` in `font`, laid out
    /// as one unwrapped line (ruling TI-E): `text.count + 1` values, the first
    /// 0, in logical order — `CTLineGetOffsetForStringIndex`'s answers on the
    /// Apple path, measured equal by the caret oracle
    /// (`everyCaretOffsetIsCoreTexts`).
    ///
    /// The whole string is shaped once, as ``lines(_:font:wrappingAt:)``
    /// shapes a paragraph (the cascade, bidi levels and scripts), and each
    /// glyph's advance is charged to the first unit of its cluster; the pen is
    /// walked as a line walks it (tabs to their stops, hard breaks zero wide),
    /// so the last offset is `lines`' advance. Three rules on top, each
    /// measured against CoreText:
    ///
    /// - **A caret between two clusters sits halfway through the kern**: at
    ///   the pen, less half of what shaping moved the previous cluster's last
    ///   glyph's advance off its nominal one. CoreText's caret between `A` and
    ///   `V` in Noto Sans at 1000 pt is 619, with `A` kerned from 639 to 599.
    ///   Not after a default ignorable, whose advance HarfBuzz zeroes: a soft
    ///   hyphen's caret stays at the pen.
    /// - **A caret inside a ligature** — one glyph for several graphemes —
    ///   sits where the face's `GDEF` ligature caret list puts it, from the
    ///   ligature's pen (Noto Sans' `ff` at 301 of 688, not 344).
    /// - **With no caret list, the ligature's advance splits evenly** among the
    ///   graphemes it covers: the `k`th of `n` sits `k/n` of the way across
    ///   (Source Sans 3's `ff` at 288.5 of 577, unrounded). A cluster of more
    ///   than one glyph splits the same way.
    ///
    /// Right-to-left text is summed in logical order: its offsets are not the
    /// visual caret positions, which are out of scope (TI-E).
    public static func caretOffsets(_ text: String, font: PortableFont) throws -> [Double] {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [0] }
        let bidi = BidiParagraph(units)
        var clusterGlyphs = [[RunGlyph]](repeating: [], count: units.count)
        var clusterStart = [Bool](repeating: false, count: units.count + 1)
        clusterStart[0] = true
        clusterStart[units.count] = true
        for run in try shapeCascading(text, font: font, levels: bidi.levels[...], scripts: bidi.scripts[...]) {
            clusterGlyphs[run.cluster].append(run)
            clusterStart[run.cluster] = true
        }
        // The pen before each unit, walked in logical order.
        var pen = [Double](repeating: 0, count: units.count + 1)
        for unit in 0..<units.count {
            let advance = clusterGlyphs[unit].reduce(0) { $0 + $1.glyph.xAdvance }
            pen[unit + 1] = advancing(pen[unit], over: units[unit], by: advance)
        }

        var isBoundary = [Bool](repeating: false, count: units.count + 1)
        var boundaries: [Int] = [0]
        boundaries.reserveCapacity(text.count + 1)
        for character in text { boundaries.append(boundaries.last! + character.utf16.count) }
        for boundary in boundaries { isBoundary[boundary] = true }

        let ignorable = ignorableUnits(of: text, count: units.count)
        return boundaries.map { boundary in
            if boundary == 0 || boundary == units.count { return pen[boundary] }
            if clusterStart[boundary] {
                var previous = boundary - 1
                while !clusterStart[previous] { previous -= 1 }
                // HarfBuzz zeroes a default ignorable's advance (a soft
                // hyphen's, measured) — that is not a kern.
                guard !ignorable[previous], let last = clusterGlyphs[previous].last else { return pen[boundary] }
                let kern = last.glyph.xAdvance - last.font.shaping.nominalAdvance(of: last.glyph.id)
                return pen[boundary] - kern / 2
            }
            // Inside the cluster `start..<end`: the `k`th of the boundaries
            // strictly inside it, which split it into `inside.count + 1`.
            var start = boundary - 1
            while !clusterStart[start] { start -= 1 }
            var end = boundary + 1
            while !clusterStart[end] { end += 1 }
            let inside = (start + 1..<end).filter { isBoundary[$0] }
            let k = inside.firstIndex(of: boundary)! + 1
            if clusterGlyphs[start].count == 1, let ligature = clusterGlyphs[start].first {
                let carets = ligature.font.shaping.ligatureCarets(of: ligature.glyph.id)
                if carets.count >= inside.count { return pen[start] + carets[k - 1] }
            }
            return pen[start] + (pen[end] - pen[start]) * Double(k) / Double(inside.count + 1)
        }
    }
}
