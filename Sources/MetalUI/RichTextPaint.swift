import MetalUICore
import MetalUITextSystem

// Rich text, lane 2 — drawing a styled `Text` (ruling RT-J; spec §1.3
// "Styled paint"). Ordinary filled rects and glyph sprites: no new primitive,
// no shader change on either renderer (`TE-AD` satisfied by construction).

extension PaintPass {
    /// Draws `resolved` laid out at `width` from `origin` inside `height`
    /// (ruling RT-J): **inside one leaf group** (`GX-J`: a shadow treats the
    /// whole `Text` as one leaf) — (1) each run's background over its
    /// segments, by the line's full box; (2) every glyph in its run's
    /// foreground; (3) underlines, joined across neighbours of one colour on a
    /// line, then strikethroughs, each clipped to its line's visible extent.
    /// Every colour resolves through ``resolve(_:)`` — it snaps (`RT-L` item 2).
    /// Called inside `paintDecoration`'s content closure (clip, opacity,
    /// border order: `OM-V`).
    func drawStyledText(_ resolved: ResolvedRichText, origin: Point<Pixels>, width: Double, height: Double) {
        let system = textSystem
        let laid = styledTextLines(resolved, system: system, wrappingAt: width, height: height)
        let x = Double(origin.x.value), y = Double(origin.y.value)
        let layout = system.layOut(resolved.text, wrappingAt: width, options: laid.options, origin: (x: x, y: y),
                                   scaleFactor: scaleFactor)
        let lines = layout.measurement.lines
        let styles = resolved.text.runs.map(\.style)
        let paints = resolved.paints
        let foregrounds = paints.map { resolve($0.foreground) }

        frame.beginLeafGroup()
        defer { frame.endLeafGroup() }

        // (1) Backgrounds: the segment's extent, whitespace included (`F4e`),
        // by the line's box (`C11bg`, `C11bg2`).
        for segment in layout.segments {
            guard let background = paints[segment.run].background else { continue }
            let line = lines[segment.line]
            fill(rect(minX: segment.minX, maxX: segment.maxX, minY: y + line.top, height: line.height),
                 color: resolve(background))
        }

        // (2) Glyphs, each in its run's colour.
        for glyph in layout.glyphs { draw(glyph.glyph, color: foregrounds[glyph.run]) }

        // (3) Underlines, then strikethroughs (RT-J items 2–3a).
        var metrics: [FontKey: TextDecorationMetrics] = [:]
        func decoration(_ run: Int) -> TextDecorationMetrics {
            let key = styles[run].font
            if let known = metrics[key] { return known }
            let measured = system.decorationMetrics(key)
            metrics[key] = measured
            return measured
        }
        func visible(_ index: Int) -> (min: Double, max: Double) {
            let line = lines[index]
            let start = x + line.offsetX
            return (start + line.visibleMinX, start + line.visibleMaxX)
        }
        // A pending underline: its colour, x extent, centre and thickness.
        var pending: (line: Int, color: Color, pattern: Text.LineStyle.Pattern, minX: Double, maxX: Double,
                      centre: Double, thickness: Double)?
        /// One decoration band over `[low, high]`: a single rect for a solid line, the pattern's segments
        /// otherwise, their cycle starting at the line's own start (`TM-D`).
        func band(_ pattern: Text.LineStyle.Pattern, line: Int, from low: Double, to high: Double, centre: Double,
                  thickness: Double, color: Color) {
            let resolved = resolve(color)
            guard pattern != .solid else {
                fill(rect(minX: low, maxX: high, minY: centre - thickness / 2, height: thickness), color: resolved)
                return
            }
            for piece in linePatternSegments(pattern, unit: linePatternUnit(thickness: thickness),
                                             origin: x + lines[line].offsetX, from: low, to: high) {
                fill(rect(minX: piece.min, maxX: piece.max, minY: centre - thickness / 2, height: thickness),
                     color: resolved)
            }
        }
        func flushUnderline() {
            guard let line = pending else { return }
            pending = nil
            let extent = visible(line.line)
            let low = Swift.max(line.minX, extent.min), high = Swift.min(line.maxX, extent.max)
            guard high > low else { return }
            band(line.pattern, line: line.line, from: low, to: high, centre: line.centre,
                 thickness: line.thickness, color: line.color)
        }
        for segment in layout.segments {
            guard let color = paints[segment.run].underline else {
                flushUnderline()
                continue
            }
            let pattern = paints[segment.run].underlinePattern
            let face = decoration(segment.run)
            let centre = segment.baseline - face.underlinePosition
            if let current = pending, current.line == segment.line, current.color == color,
               current.pattern == pattern {
                // Joined at the lowest position and the greatest thickness (`C9m`).
                pending = (current.line, color, pattern, Swift.min(current.minX, segment.minX),
                           Swift.max(current.maxX, segment.maxX), Swift.max(current.centre, centre),
                           Swift.max(current.thickness, face.underlineThickness))
            } else {
                flushUnderline()
                pending = (segment.line, color, pattern, segment.minX, segment.maxX, centre,
                           face.underlineThickness)
            }
        }
        flushUnderline()
        for segment in layout.segments {
            guard let color = paints[segment.run].strikethrough else { continue }
            let face = decoration(segment.run)
            let extent = visible(segment.line)
            let low = Swift.max(segment.minX, extent.min), high = Swift.min(segment.maxX, extent.max)
            guard high > low else { continue }
            let centre = segment.baseline - face.strikethroughPosition
            band(paints[segment.run].strikethroughPattern, line: segment.line, from: low, to: high, centre: centre,
                 thickness: face.underlineThickness, color: color)
        }
    }
}

/// A rect in window points from its edges.
private func rect(minX: Double, maxX: Double, minY: Double, height: Double) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(Float(minX)), y: Pixels(Float(minY))),
           size: Size(width: Pixels(Float(maxX - minX)), height: Pixels(Float(height))))
}
