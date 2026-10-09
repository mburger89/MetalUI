import MetalUITextSystem

/// A ``StyledText`` laid out by the portable pipeline (ruling RT-F): the
/// lines `layOut` made, their boxes (RT-G) and their ascents.
struct PortableStyledLines {
    let lines: [LaidOutLine]
    let measurement: StyledTextMeasurement
    /// Each line's ascent, so its baseline is placed as the plain path places
    /// one: `(origin.y + top) + ascent`.
    let ascents: [Double]
}

extension PortableText {
    /// `fonts` (one per run) as the runs ``layOut(_:runs:wrappingAt:options:)``
    /// reads.
    static func runs(of text: StyledText, fonts: [PortableFont]) -> PortableRuns {
        PortableRuns(fonts: fonts, kerning: text.runs.map(\.style.kerning), tracking: text.runs.map(\.style.tracking),
                     runOfUnit: text.runs.count == 1 ? nil : text.runOfUnit, fixedRun: nil)
    }

    /// `text` in `fonts` wrapped at `width` under `options` (rulings RT-F,
    /// RT-G, RT-H, RT-I): the lines the plain path's ``layOut(_:font:wrappingAt:options:)``
    /// makes, over styled runs, with each line's box — ascent, descent and
    /// leading the largest over the runs it draws (a truncated line's ellipsis
    /// run among them), raised and lowered by their baseline offsets, its
    /// height `ceil` of their sum, lines stacked from the top.
    static func styledLines(_ text: StyledText, fonts: [PortableFont], wrappingAt width: Double?,
                            options: TextLayoutOptions) throws -> PortableStyledLines {
        let runs = runs(of: text, fonts: fonts)
        let laidOut = try layOut(text.string, runs: runs, wrappingAt: width, options: options)
        let units = Array(text.string.utf16)
        let runOfUnit = text.runOfUnit
        let styles = text.runs.map(\.style)
        let metricsByKey = Dictionary(fonts.map { ($0.key, $0.metrics) }, uniquingKeysWith: { first, _ in first })
        let widest = laidOut.map(\.line.advance).max() ?? 0
        let factor: Double = switch options.alignment {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let box = width ?? widest
        var boxes: [TextLineBox] = []
        var ascents: [Double] = []
        var top = 0.0
        for line in laidOut {
            var lineRuns = StyledTextLines.runs(
                in: line.kept, runOfUnit: runOfUnit,
                fallback: runOfUnit.isEmpty ? 0 : runOfUnit[min(line.line.range.lowerBound, runOfUnit.count - 1)])
            if let token = line.tokenRun, !lineRuns.contains(token) {
                lineRuns = (line.kept.allSatisfy(\.isEmpty) ? [] : lineRuns) + [token]
            }
            let metrics = StyledTextLines.lineMetrics(runs: lineRuns, styles: styles) { key in
                let face = metricsByKey[key]!
                return TextFontMetrics(ascent: face.ascent, descent: face.descent, leading: face.leading,
                                       lineHeight: face.lineHeight)
            }
            let height = (metrics.ascent + metrics.descent + metrics.leading).rounded(.up)
            let offset = factor == 0 ? 0
                : alignmentOffset(box - (line.line.advance - line.trailingWhitespace), factor)
            let extent = StyledTextLines.visibleExtent(pens(line, units: units), tracking: styles.map(\.tracking))
            boxes.append(TextLineBox(range: line.line.range, top: top, height: height, baseline: top + metrics.ascent,
                                     width: line.line.advance, visibleMinX: extent.min, visibleMaxX: extent.max,
                                     offsetX: offset))
            ascents.append(metrics.ascent)
            top += height
        }
        return PortableStyledLines(lines: laidOut,
                                   measurement: StyledTextMeasurement(widestLine: widest, totalHeight: top, lines: boxes),
                                   ascents: ascents)
    }

    /// A line's glyphs as pens: where each is drawn (its pen plus its own
    /// x offset), how far it walks the pen, its run, and whether its unit is
    /// line whitespace (an ellipsis is not).
    static func pens(_ line: LaidOutLine, units: [UInt16]) -> [StyledTextLines.Pen] {
        line.glyphs.map { glyph in
            StyledTextLines.Pen(x: glyph.penX + glyph.glyph.xOffset, advance: glyph.walked, run: glyph.style,
                                isWhitespace: glyph.unit.map { StyledTextLines.isLineWhitespace(units[$0]) } ?? false)
        }
    }

    /// Every glyph of `text` placed on the device pixel grid with its run, and
    /// every run segment (ruling RT-F item 2): ``placements(_:font:origin:wrappingAt:options:scaleFactor:)``'s
    /// arithmetic per line, the baseline from the line's box, each run's
    /// glyphs raised by its baseline offset.
    static func styledLayout(_ text: StyledText, fonts: [PortableFont], wrappingAt width: Double?,
                             options: TextLayoutOptions, origin: (x: Double, y: Double),
                             scaleFactor: Float) throws -> StyledTextLayout {
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let scale = Double(scaleFactor)
        let laid = try styledLines(text, fonts: fonts, wrappingAt: width, options: options)
        let units = Array(text.string.utf16)
        let styles = text.runs.map(\.style)
        var glyphs: [StyledGlyph] = []
        var segments: [TextRunSegment] = []
        for (index, line) in laid.lines.enumerated() {
            let box = laid.measurement.lines[index]
            let baseline = origin.y + box.top + laid.ascents[index]
            let baselineY = Int((baseline * scale).rounded())
            let lineX = origin.x + box.offsetX
            for placed in line.glyphs {
                let split = GlyphImage.subpixelPlacement(forDeviceX: (lineX + (placed.penX + placed.glyph.xOffset)) * scale)
                let row = baselineY - Int((styles[placed.style].baselineOffset * scale).rounded())
                    - Int((placed.glyph.yOffset * scale).rounded())
                glyphs.append(StyledGlyph(
                    glyph: TextGlyph(key: GlyphKey(font: placed.font.key, glyph: placed.id, size: placed.font.size,
                                                   subpixelVariant: split.variant, scaleFactor: scaleFactor),
                                     pixelX: split.pixelX, baselineY: row),
                    run: placed.style))
            }
            segments += StyledTextLines.segments(pens(line, units: units), line: index, originX: lineX,
                                                 baseline: { origin.y + box.baseline - styles[$0].baselineOffset })
        }
        return StyledTextLayout(measurement: laid.measurement, glyphs: glyphs, segments: segments)
    }
}
