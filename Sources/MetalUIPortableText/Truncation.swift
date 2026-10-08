import MetalUIHarfBuzz
import MetalUITextSystem

extension PortableText {
    /// The last line a limit keeps (rulings TE-C item 3, TE-T), from UTF-16
    /// unit `start` of `text`: built from the rest's first paragraph `P` — to
    /// the first hard break, excluded, or the end — laid out as one line of
    /// `P` alone, as the Apple path builds a `CTLine` of it. The Apple path's
    /// answer is CoreText's `CTLineCreateTruncatedLine`; this is that rule,
    /// measured (`TruncationOracleTests`, ruling TE-U):
    ///
    /// - **The token** is `…` (U+2026) shaped in `font` through
    ///   ``shapeCascading(_:font:levels:scripts:)`` (`FB-A`), so a face without
    ///   it draws its cascade's.
    /// - **Narrower than the token**: the longest prefix of whole graphemes
    ///   that fits the width, at least one, no token — a prefix ending inside a
    ///   ligature measured and drawn re-shaped (`CTTypesetterSuggestClusterBreak`).
    /// - **`P` wraps**: truncated in `mode`, removing whole clusters that are
    ///   whole graphemes (a ligature, a base with its marks). With `L`
    ///   the line's advance, `T` its trailing whitespace and `t` the token's
    ///   advance: tail keeps the longest prefix with `prefix + t ≤ width + T`;
    ///   head the longest suffix with `suffix − T + t ≤ width`; middle a prefix
    ///   and a suffix each within `(width + T − t) / 2`, the suffix measured
    ///   without `T`. A kept prefix drops its trailing whitespace, a kept
    ///   suffix its leading whitespace. Every kept glyph keeps its advance in
    ///   `P`'s shaping — its share, kerning into a dropped neighbour included
    ///   — and nothing is re-shaped (CoreText keeps a joined Arabic letter's
    ///   form when its neighbour is dropped).
    /// - **`P` fits** (so text follows it): tail mode appends the token by the
    ///   tail rule with `T` taken as 0; head and middle draw `P` whole.
    ///
    /// **Not matched** (ruling TE-U, pinned as `LB-M` pins Thai): in a right-to-left
    /// paragraph, head and middle mode keep a suffix by the share rule above,
    /// where CoreText sometimes keeps one more cluster at the suffix's edge.
    ///
    /// The token sits where the kept text ends logically: after the prefix's
    /// last cluster on its own side — to its right when that cluster runs left
    /// to right, to its left when it runs right to left — or before the
    /// suffix's first.
    static func truncatedLine(_ text: String, units: [UInt16], from start: Int, wraps: Bool,
                              font: PortableFont, width: Double, mode: TextTruncation) throws -> LaidOutLine {
        try truncatedLine(text, units: units, from: start, wraps: wraps, runs: .single(font), width: width,
                          mode: mode)
    }

    /// ``truncatedLine(_:units:from:wraps:font:width:mode:)`` over styled runs
    /// (ruling RT-I): the token is shaped in the run of the first character
    /// the truncation removes. It is first shaped in the run of the
    /// paragraph's first unit; when the truncation removes from another run,
    /// the line is built again with the token in that run (ruling RT-P item
    /// 1) — the CoreText path's two attempts, step for step.
    static func truncatedLine(_ text: String, units: [UInt16], from start: Int, wraps: Bool,
                              runs: PortableRuns, width: Double, mode: TextTruncation) throws -> LaidOutLine {
        let guess = runs.run(at: start)
        let first = try truncatedLine(text, units: units, from: start, wraps: wraps, runs: runs, tokenRun: guess,
                                      width: width, mode: mode)
        guard let removed = first.firstRemoved else { return first.line }
        let removedRun = runs.run(at: removed)
        if removedRun == guess { return first.line }
        return try truncatedLine(text, units: units, from: start, wraps: wraps, runs: runs, tokenRun: removedRun,
                                 width: width, mode: mode).line
    }

    /// One attempt, the token in run `tokenRun`; also the first unit it
    /// removed (`nil` when it draws no token).
    private static func truncatedLine(_ text: String, units: [UInt16], from start: Int, wraps: Bool,
                                      runs: PortableRuns, tokenRun: Int, width: Double,
                                      mode: TextTruncation) throws -> (line: LaidOutLine, firstRemoved: Int?) {
        var end = start
        while end < units.count, !isHardBreak(units[end]) { end += 1 }
        let paragraph = Array(units[start..<end])
        let count = paragraph.count
        let range = start..<units.count

        let token = try shapeCascading("\u{2026}", runs: runs.fixed(tokenRun), base: 0)
        let tokenAdvance = token.reduce(0) { $0 + $1.glyph.xAdvance }

        guard count > 0 else {
            return (LaidOutLine(line: PortableLine(range: range, advance: 0), glyphs: [], trailingWhitespace: 0,
                                kept: [start..<start]), nil)
        }
        let string = String(decoding: paragraph, as: UTF16.self)
        let bidi = BidiParagraph(paragraph)
        let shaped = try shapeCascading(string, runs: runs, base: start, levels: bidi.levels[...],
                                        scripts: bidi.scripts[...])
        var unitAdvance = [Double](repeating: 0, count: count)
        var clusterStart = [Bool](repeating: false, count: count + 1)
        clusterStart[count] = true
        clusterStart[0] = true
        for run in shaped {
            unitAdvance[run.cluster] += run.glyph.xAdvance
            clusterStart[run.cluster] = true
        }
        // `cumulative[k]`: the advance of units 0..<k, walked as a line.
        var cumulative = [0.0]
        cumulative.reserveCapacity(count + 1)
        for unit in 0..<count { cumulative.append(advancing(cumulative[unit], over: paragraph[unit], by: unitAdvance[unit])) }
        let lineAdvance = cumulative[count]
        var trimmedEnd = count
        while trimmedEnd > 0, isBreakingWhitespace(paragraph[trimmedEnd - 1]) { trimmedEnd -= 1 }
        let trailing = lineAdvance - cumulative[trimmedEnd]
        // Truncation removes whole clusters that are whole graphemes: a
        // ligature goes as one (its cluster spans graphemes), and so does a
        // base with its marks (HarfBuzz may give each mark a cluster of its
        // own) — measured, TE-U.
        var graphemeStart = [Bool](repeating: false, count: count + 1)
        var graphemeOffset = 0
        for character in string { graphemeStart[graphemeOffset] = true; graphemeOffset += character.utf16.count }
        graphemeStart[count] = true
        let boundaries = (0...count).filter { clusterStart[$0] && graphemeStart[$0] }
        let isBoundary = (0...count).map { clusterStart[$0] && graphemeStart[$0] }
        // `fromEnd[j]`: the advance of units j..<count, summed from the end, so
        // a suffix's width is not a difference of two long sums.
        var fromEnd = [Double](repeating: 0, count: count + 1)
        for unit in stride(from: count - 1, through: 0, by: -1) { fromEnd[unit] = fromEnd[unit + 1] + unitAdvance[unit] }

        // What is kept: units 0..<prefixEnd and suffixStart..<count, and
        // whether the token is drawn between them.
        var prefixEnd = count, suffixStart = count, drawsToken = false
        func stripPrefix() { while prefixEnd > 0, isBreakingWhitespace(paragraph[prefixEnd - 1]) { prefixEnd -= 1 } }
        func stripSuffix() { while suffixStart < count, isBreakingWhitespace(paragraph[suffixStart]) { suffixStart += 1 } }
        if tokenAdvance > width {
            // `CTTypesetterSuggestClusterBreak`: the longest run of whole
            // graphemes that fits, at least one — a prefix that ends inside a
            // cluster (a ligature split) measured, and drawn, re-shaped.
            let graphemes = (1...count).filter { graphemeStart[$0] }
            var end = graphemes[0]
            for candidate in graphemes {
                let advance = clusterStart[candidate] ? cumulative[candidate]
                    : try shapedAdvance(paragraph, 0..<candidate, runs: runs, base: start)
                guard advance <= width else { break }
                end = candidate
            }
            if !clusterStart[end] {
                return (try reshapedLine(Array(paragraph[0..<end]), runs: runs, base: start, range: range), nil)
            }
            prefixEnd = end
            suffixStart = count
        } else if wraps || mode == .tail {
            let allowance = wraps ? trailing : 0
            if wraps, lineAdvance - trailing <= width {
                // It fits after all: CoreText hands the line back untruncated.
            } else {
                drawsToken = true
                switch mode {
                case .tail:
                    prefixEnd = boundaries.last { cumulative[$0] + tokenAdvance <= width + allowance } ?? 0
                    stripPrefix()
                case .head:
                    prefixEnd = 0
                    suffixStart = boundaries.first { fromEnd[$0] - allowance + tokenAdvance <= width }
                        ?? count
                    stripSuffix()
                case .middle:
                    let half = (width + allowance - tokenAdvance) / 2
                    prefixEnd = boundaries.last { cumulative[$0] <= half } ?? 0
                    suffixStart = boundaries.first { $0 >= prefixEnd && fromEnd[$0] - allowance <= half }
                        ?? count
                    stripPrefix()
                    stripSuffix()
                }
            }
        }

        // The kept glyphs in visual order, and where the token goes among them.
        let ignorable = ignorableUnits(of: string, count: count)
        let visual = visualOrder(shaped.map { (run: $0, payload: $0.cluster) }, line: 0..<count,
                                 bidi: bidi, unitOf: { $0 })
        let kept = visual.filter { $0.payload < prefixEnd || $0.payload >= suffixStart }
        var tokenIndex = kept.count
        if drawsToken {
            if prefixEnd > 0 {
                let anchor = clusterOf(prefixEnd - 1, isBoundary: isBoundary)
                let rightToLeft = bidi.levels[anchor] % 2 == 1
                let positions = kept.indices.filter { clusterOf(kept[$0].payload, isBoundary: isBoundary) == anchor }
                tokenIndex = rightToLeft ? positions.first ?? kept.count : (positions.last.map { $0 + 1 } ?? kept.count)
            } else if suffixStart < count {
                let anchor = suffixStart
                let rightToLeft = bidi.levels[anchor] % 2 == 1
                let positions = kept.indices.filter { clusterOf(kept[$0].payload, isBoundary: isBoundary) == anchor }
                tokenIndex = rightToLeft ? (positions.last.map { $0 + 1 } ?? 0) : positions.first ?? 0
            } else {
                tokenIndex = 0
            }
        }

        // Walk the pen, token included; right to left, the kept text's
        // trailing whitespace hangs off the left edge (ruling BD-C).
        var pen = 0.0
        // The whitespace at the kept text's logical end — none when the token
        // ends it.
        var keptTrailing = 0.0
        if let keptEnd = suffixStart < count ? count : (drawsToken ? nil : prefixEnd) {
            var visibleEnd = keptEnd
            while visibleEnd > 0, isBreakingWhitespace(paragraph[visibleEnd - 1]) { visibleEnd -= 1 }
            keptTrailing = cumulative[keptEnd] - cumulative[visibleEnd]
        }
        if bidi.isRightToLeftParagraph(at: 0) { pen = -keptTrailing }
        let startPen = pen
        var placed: [LinePlacedGlyph] = []
        func place(_ run: RunGlyph, unit: UInt16, ignorable: Bool, source: Int?) {
            let next = advancing(pen, over: unit, by: run.glyph.xAdvance)
            if let id = drawnGlyph(run.glyph.id, at: unit, ignorable: ignorable, space: run.font.spaceGlyph) {
                placed.append(LinePlacedGlyph(id: id, glyph: run.glyph, font: run.font, penX: pen, unit: source,
                                              style: run.style, walked: next - pen))
            }
            pen = next
        }
        func placeToken() { for run in token { place(run, unit: 0x2026, ignorable: false, source: nil) } }
        for (index, entry) in kept.enumerated() {
            if drawsToken, index == tokenIndex { placeToken() }
            place(entry.run, unit: paragraph[entry.payload], ignorable: ignorable[entry.payload],
                  source: start + entry.payload)
        }
        if drawsToken, tokenIndex == kept.count { placeToken() }
        let keptRanges = suffixStart < count ? [start..<(start + prefixEnd), (start + suffixStart)..<end]
                                             : [start..<(start + prefixEnd)]
        let firstRemoved: Int? = drawsToken ? (prefixEnd < suffixStart && prefixEnd < count ? start + prefixEnd : end)
                                            : nil
        return (LaidOutLine(line: PortableLine(range: range, advance: pen - startPen), glyphs: placed,
                            trailingWhitespace: keptTrailing, kept: keptRanges,
                            tokenRun: drawsToken ? tokenRun : nil), firstRemoved)
    }

    /// `units` — a prefix of a paragraph that ends inside a cluster — shaped
    /// and laid out alone, as `CTTypesetterCreateLine` builds a line that
    /// splits a cluster.
    private static func reshapedLine(_ units: [UInt16], runs: PortableRuns, base: Int,
                                     range: Range<Int>) throws -> LaidOutLine {
        let string = String(decoding: units, as: UTF16.self)
        let bidi = BidiParagraph(units)
        let shaped = try shapeCascading(string, runs: runs, base: base, levels: bidi.levels[...],
                                        scripts: bidi.scripts[...])
        let ignorable = ignorableUnits(of: string, count: units.count)
        var pen = 0.0
        var placed: [LinePlacedGlyph] = []
        for (run, unit) in visualOrder(shaped.map { (run: $0, payload: $0.cluster) }, line: 0..<units.count,
                                       bidi: bidi, unitOf: { $0 }) {
            let next = advancing(pen, over: units[unit], by: run.glyph.xAdvance)
            if let id = drawnGlyph(run.glyph.id, at: units[unit], ignorable: ignorable[unit], space: run.font.spaceGlyph) {
                placed.append(LinePlacedGlyph(id: id, glyph: run.glyph, font: run.font, penX: pen, unit: base + unit,
                                              style: run.style, walked: next - pen))
            }
            pen = next
        }
        return LaidOutLine(line: PortableLine(range: range, advance: pen), glyphs: placed, trailingWhitespace: 0,
                           kept: [base..<(base + units.count)])
    }

    /// The first unit of the cluster holding `unit`.
    private static func clusterOf(_ unit: Int, isBoundary: [Bool]) -> Int {
        var first = unit
        while first > 0, !isBoundary[first] { first -= 1 }
        return first
    }
}
