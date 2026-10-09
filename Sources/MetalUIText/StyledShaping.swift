import CoreText
import Foundation
import MetalUITextSystem

/// A ``StyledText`` laid out in display lines by CoreText (ruling RT-F): the
/// `CTLine`s, each line's box (RT-G) and where its glyphs' string indices
/// count from.
///
/// **Not `Sendable`**, for ``ShapedLine``'s reason (it holds `CTLine`s).
struct StyledShapedText {
    /// The display lines, as ``Shaper`` makes them for a plain string.
    let lines: [ShapedLine]
    /// Each line's box.
    let measurement: StyledTextMeasurement
    /// What a line's glyph string indices count from: 0 for a line the
    /// typesetter cut from the whole string, the paragraph's start for a
    /// truncated last line (built from its paragraph alone).
    let indexBases: [Int]
    /// The run of a truncated line's ellipsis (ruling RT-I), per line.
    let tokenRuns: [Int?]
    /// Each line's ascent (RT-G item 1), so its baseline is placed as the
    /// plain path places one: `(origin.y + top) + ascent`.
    let ascents: [Double]
}

/// The attribute that marks an ellipsis token's glyphs inside a truncated
/// line, so their run is the token's (RT-I), not a character's.
private let tokenMarker = NSAttributedString.Key("MetalUI.truncationToken")

/// CoreText's styled path (rulings RT-F, RT-G, RT-H, RT-I).
enum StyledShaper {
    /// The attributes of run `index` (ruling RT-H): its font, and its kerning
    /// and tracking **only when not 0** — CoreText's kern attribute of 0
    /// turns the face's pair kerning off (`K2`), where MetalUI's 0 is "no
    /// extra space" (`RT-O` item 7). A baseline offset is MetalUI's to apply
    /// (`kCTBaselineOffsetAttributeName`'s bounds rule is not RT-G's).
    static func attributes(_ style: TextRunStyle, font: ResolvedFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont]
        if style.kerning != 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = style.kerning }
        if style.tracking != 0 { attributes[NSAttributedString.Key(kCTTrackingAttributeName as String)] = style.tracking }
        return attributes
    }

    /// `text` as one attributed string, each run carrying its attributes.
    static func attributedString(_ text: StyledText, fonts: [ResolvedFont]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text.string)
        var location = 0
        for (index, run) in text.runs.enumerated() where run.length > 0 {
            result.setAttributes(attributes(run.style, font: fonts[index]),
                                 range: NSRange(location: location, length: run.length))
            location += run.length
        }
        if text.string.isEmpty { return NSAttributedString(string: "", attributes: attributes(text.runs[0].style, font: fonts[0])) }
        return result
    }

    /// `text` in `fonts` (one per run) wrapped at `width` under `options` —
    /// ``Shaper/shape(_:font:wrappingAt:options:)``'s algorithm over one
    /// `CTTypesetter` for the whole attributed string, so a run boundary is
    /// never a break opportunity (RT-H item 1), with RT-G's line boxes and
    /// RT-I's ellipsis.
    static func shape(_ text: StyledText, fonts: [ResolvedFont], wrappingAt width: Double?,
                      options: TextLayoutOptions) -> StyledShapedText {
        if let width {
            precondition(width > 0, "StyledShaper.shape was offered a wrapping width of \(width); a width must be "
                         + "positive (Shaper.shape's contract)")
        }
        let attributed = attributedString(text, fonts: fonts)
        let runOfUnit = text.runOfUnit
        var lines: [ShapedLine] = []
        if attributed.length > 0 {
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start: CFIndex = 0
            while start < attributed.length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, width ?? .infinity)
                precondition(count > 0, "CTTypesetterSuggestLineBreak returned a zero-length break")
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                lines.append(ShapedLine(line: line, advance: CTLineGetTypographicBounds(line, nil, nil, nil)))
                start += count
            }
        } else {
            let line = CTLineCreateWithAttributedString(attributed)
            lines.append(ShapedLine(line: line, advance: CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        var indexBases = [Int](repeating: 0, count: lines.count)
        var tokenRuns = [Int?](repeating: nil, count: lines.count)
        var kept: [[Range<Int>]] = lines.map { [$0.sourceRange] }
        if let maxLines = options.maxLines.map({ max(1, $0) }), lines.count > maxLines {
            if let width {
                let last = lines[maxLines - 1].sourceRange
                let truncated = truncatedLine(text, attributed: attributed, runOfUnit: runOfUnit, fonts: fonts,
                                              from: last.lowerBound,
                                              wraps: !Shaper.endsParagraph(text.string, last),
                                              width: width, mode: options.truncation)
                lines = Array(lines.prefix(maxLines - 1)) + [truncated.line]
                indexBases = Array(indexBases.prefix(maxLines - 1)) + [last.lowerBound]
                tokenRuns = Array(tokenRuns.prefix(maxLines - 1)) + [truncated.tokenRun]
                kept = Array(kept.prefix(maxLines - 1)) + [truncated.kept]
            } else {
                lines = Array(lines.prefix(maxLines))
                indexBases = Array(indexBases.prefix(maxLines))
                tokenRuns = Array(tokenRuns.prefix(maxLines))
                kept = Array(kept.prefix(maxLines))
            }
        }
        let widest = lines.map(\.advance).max() ?? 0
        let factor: Double = switch options.alignment {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let box = width ?? widest
        let styles = text.runs.map(\.style)
        let metricsByKey = Dictionary(fonts.map { ($0.key, $0.metrics) }, uniquingKeysWith: { first, _ in first })
        var boxes: [TextLineBox] = []
        var ascents: [Double] = []
        var top = 0.0
        for (index, line) in lines.enumerated() {
            var runs = StyledTextLines.runs(in: kept[index], runOfUnit: runOfUnit,
                                            fallback: runOfUnit.isEmpty ? 0 : runOfUnit[min(line.sourceRange.lowerBound, runOfUnit.count - 1)])
            if let token = tokenRuns[index], !runs.contains(token) {
                runs = (kept[index].allSatisfy(\.isEmpty) ? [] : runs) + [token]
            }
            let metrics = StyledTextLines.lineMetrics(runs: runs, styles: styles) { key in
                let font = metricsByKey[key]!
                return TextFontMetrics(ascent: font.ascent, descent: font.descent, leading: font.leading,
                                       lineHeight: font.lineHeight)
            }
            let height = ceil(metrics.ascent + metrics.descent + metrics.leading)
            let offset = factor == 0 ? 0 : Shaper.alignmentOffset(box - (line.advance - line.trailingWhitespace), factor)
            let extent = visibleExtent(line, base: indexBases[index], tokenRun: tokenRuns[index], text: text,
                                       runOfUnit: runOfUnit)
            boxes.append(TextLineBox(range: line.sourceRange, top: top, height: height, baseline: top + metrics.ascent,
                                     width: line.advance, visibleMinX: extent.min, visibleMaxX: extent.max,
                                     offsetX: offset))
            ascents.append(metrics.ascent)
            top += height
        }
        return StyledShapedText(lines: lines,
                                measurement: StyledTextMeasurement(widestLine: widest, totalHeight: top, lines: boxes),
                                indexBases: indexBases, tokenRuns: tokenRuns, ascents: ascents)
    }

    /// One glyph of a line: its font, id, pen (points from the line's start),
    /// advance, and the run and UTF-16 unit it belongs to.
    struct LineGlyph {
        let font: CTFont
        let glyph: CGGlyph
        let x: Double
        let y: Double
        let advance: Double
        let run: Int
        let unit: Int?
    }

    /// Every glyph of `line`, in CoreText's run order.
    static func glyphs(of line: ShapedLine, base: Int, tokenRun: Int?, runOfUnit: [Int]) -> [LineGlyph] {
        guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { return [] }
        var result: [LineGlyph] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let isToken = attributes[tokenMarker] != nil
            let font = attributes[kCTFontAttributeName as String] as! CTFont
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for index in 0..<count {
                let unit = isToken ? nil : base + indices[index]
                let styleRun = isToken ? tokenRun ?? 0 : runOfUnit[min(max(unit!, 0), runOfUnit.count - 1)]
                result.append(LineGlyph(font: font, glyph: ids[index], x: Double(positions[index].x),
                                        y: Double(positions[index].y), advance: Double(advances[index].width),
                                        run: styleRun, unit: unit))
            }
        }
        return result
    }

    /// `line`'s visible extent (ruling RT-J item 3).
    static func visibleExtent(_ line: ShapedLine, base: Int, tokenRun: Int?, text: StyledText,
                              runOfUnit: [Int]) -> (min: Double, max: Double) {
        guard !runOfUnit.isEmpty else { return (0, 0) }
        let units = Array(text.string.utf16)
        let pieces = glyphs(of: line, base: base, tokenRun: tokenRun, runOfUnit: runOfUnit)
            .filter { $0.glyph != 0xFFFF }
            .map { glyph in
                StyledTextLines.Pen(x: glyph.x, advance: glyph.advance, run: glyph.run,
                                    isWhitespace: glyph.unit.map { StyledTextLines.isLineWhitespace(units[$0]) } ?? false)
            }
        return StyledTextLines.visibleExtent(pieces, tracking: text.runs.map(\.style.tracking))
    }

    /// The last line a limit keeps (ruling RT-I): ``Shaper/truncatedLine(_:from:wraps:font:width:mode:)``
    /// over the attributed paragraph, with the ellipsis attributed as the run
    /// of the first character the truncation removes. The token is first made
    /// in the run of the paragraph's first unit; when the truncation removes
    /// from another run, it is made again in that run and the line rebuilt
    /// (ruling RT-P item 1). Returns the line, the token's run (`nil` when no
    /// token is drawn) and the source ranges it keeps.
    static func truncatedLine(_ text: StyledText, attributed: NSAttributedString, runOfUnit: [Int],
                              fonts: [ResolvedFont], from start: Int, wraps: Bool, width: Double,
                              mode: TextTruncation) -> (line: ShapedLine, tokenRun: Int?, kept: [Range<Int>]) {
        let source = attributed.string as NSString
        var end = start
        while end < source.length, !Shaper.hardBreaks.contains(source.character(at: end)) { end += 1 }
        let paragraph = attributed.attributedSubstring(from: NSRange(location: start, length: end - start))
        let whole = CTLineCreateWithAttributedString(paragraph)
        let range = start..<source.length
        func shaped(_ line: CTLine) -> ShapedLine {
            ShapedLine(line: line, advance: CTLineGetTypographicBounds(line, nil, nil, nil), sourceRange: range)
        }
        func token(_ run: Int) -> CTLine {
            var attributes = attributes(text.runs[run].style, font: fonts[run])
            attributes[tokenMarker] = true
            return CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attributes))
        }
        let type: CTLineTruncationType = switch mode {
        case .tail: .end
        case .head: .start
        case .middle: .middle
        }
        // The removed range a truncated line reports through its token run's
        // string range (paragraph-relative), or nil when it drew no token.
        func removed(_ line: CTLine) -> Range<Int>? {
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard attributes[tokenMarker] != nil else { continue }
                let r = CTRunGetStringRange(run)
                return r.location..<(r.location + r.length)
            }
            return nil
        }
        func result(_ line: CTLine, tokenRun: Int) -> (line: ShapedLine, tokenRun: Int?, kept: [Range<Int>]) {
            guard let cut = removed(line) else {
                let r = CTLineGetStringRange(line)
                return (shaped(line), nil, [(start + r.location)..<(start + r.location + r.length)])
            }
            let length = end - start
            return (shaped(line), tokenRun, [start..<(start + min(cut.lowerBound, length)),
                                             (start + min(cut.upperBound, length))..<end])
        }
        // One attempt with the token in `run`; also returns the run of the
        // first unit it removed.
        func attempt(_ run: Int) -> (line: CTLine, firstRemoved: Int?, wide: Bool) {
            let tokenLine = token(run)
            if CTLineGetTypographicBounds(tokenLine, nil, nil, nil) > width {
                guard paragraph.length > 0 else { return (whole, nil, true) }
                let typesetter = CTTypesetterCreateWithAttributedString(paragraph)
                let count = max(1, CTTypesetterSuggestClusterBreak(typesetter, 0, width))
                return (CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: count)), nil, true)
            }
            var line = whole
            if wraps {
                line = CTLineCreateTruncatedLine(whole, width, type, tokenLine) ?? whole
            } else if mode == .tail, paragraph.length > 0 {
                let forced = NSMutableAttributedString(attributedString: paragraph)
                forced.append(NSAttributedString(string: "M", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String):
                        CTFontCreateCopyWithAttributes(fonts[run].ctFont, 1e6, nil, nil)]))
                line = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(forced), width, .end, tokenLine) ?? whole
            }
            return (line, removed(line).map { start + $0.lowerBound }, false)
        }
        let guess = runOfUnit.isEmpty ? 0 : runOfUnit[min(start, runOfUnit.count - 1)]
        let first = attempt(guess)
        if first.wide { return result(first.line, tokenRun: guess) }
        guard let firstRemoved = first.firstRemoved else { return result(first.line, tokenRun: guess) }
        let removedRun = runOfUnit[min(firstRemoved, runOfUnit.count - 1)]
        if removedRun == guess { return result(first.line, tokenRun: guess) }
        let second = attempt(removedRun)
        return result(second.line, tokenRun: removedRun)
    }

    /// Every glyph of `shaped` placed on the device pixel grid, with its run,
    /// and every run segment (ruling RT-F item 2) — ``ShapedText/placedGlyphs(at:font:scaleFactor:)``'s
    /// arithmetic per line, the line's baseline from its box and each run's
    /// glyphs raised by its baseline offset.
    static func placed(_ shaped: StyledShapedText, text: StyledText, fonts: [ResolvedFont],
                       origin: (x: Double, y: Double), scaleFactor: Float)
        -> (glyphs: [(PlacedGlyph, Int)], segments: [TextRunSegment]) {
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let scale = Double(scaleFactor)
        let runOfUnit = text.runOfUnit
        let styles = text.runs.map(\.style)
        var placed: [(PlacedGlyph, Int)] = []
        var segments: [TextRunSegment] = []
        var resolved: [ObjectIdentifier: ResolvedFont] = [:]
        func resolvedFont(_ font: CTFont, run: Int) -> ResolvedFont {
            if CFEqual(font, fonts[run].ctFont) { return fonts[run] }
            for candidate in fonts where CFEqual(font, candidate.ctFont) { return candidate }
            let id = ObjectIdentifier(font)
            if let hit = resolved[id] { return hit }
            let made = ResolvedFont(ctFont: font)
            resolved[id] = made
            return made
        }
        for (index, line) in shaped.lines.enumerated() {
            let box = shaped.measurement.lines[index]
            let baseline = origin.y + box.top + shaped.ascents[index]
            let baselineY = Int((baseline * scale).rounded())
            let lineX = origin.x + box.offsetX
            let glyphs = runOfUnit.isEmpty ? [] : glyphs(of: line, base: shaped.indexBases[index],
                                                          tokenRun: shaped.tokenRuns[index], runOfUnit: runOfUnit)
            var pens: [StyledTextLines.Pen] = []
            for glyph in glyphs {
                let font = resolvedFont(glyph.font, run: glyph.run)
                let placement = GlyphRaster.subpixelPlacement(forDeviceX: (lineX + glyph.x) * scale)
                let y = baselineY - Int((styles[glyph.run].baselineOffset * scale).rounded())
                    - Int((glyph.y * scale).rounded())
                placed.append((PlacedGlyph(key: GlyphKey(font: font.key, glyph: glyph.glyph,
                                                         size: Double(CTFontGetSize(font.ctFont)),
                                                         subpixelVariant: placement.variant, scaleFactor: scaleFactor),
                                           font: font, pixelX: placement.pixelX, baselineY: y), glyph.run))
                if glyph.glyph != 0xFFFF {
                    pens.append(StyledTextLines.Pen(x: glyph.x, advance: glyph.advance, run: glyph.run, isWhitespace: false))
                }
            }
            segments += StyledTextLines.segments(pens, line: index, originX: lineX,
                                                 baseline: { origin.y + box.baseline - styles[$0].baselineOffset })
        }
        return (placed, segments)
    }
}
