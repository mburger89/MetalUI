import MetalUICore
import MetalUIPrimitives
import MetalUIScene
import MetalUIShaderTypes
import MetalUITerminal

/// Records one terminal row into the frame's grid sink (`TRM-AU`, `TRM-AZ`): the row's opaque backgrounds, then
/// its glyphs, then its underlines and strikethroughs, in call order, so a row redrawn over a retained target
/// replaces exactly its own pixels (`TRM-AV`).
///
/// **Backgrounds** are runs of equal background merged into one rect each and always cover the whole grid
/// width: stored cells first, then the default background to the right edge, so a row of default blanks is one
/// rect. **Glyphs** are the cache's placements (shaped through the text system's fallback) or its synthesised
/// glyphs, masked to the row so ink never leaves the row's pixels. **Decorations** (underline in its five
/// styles, strikethrough) draw over the glyphs in the underline colour (SGR 58, else the glyph colour).
/// Colours come from the scheme: bold-as-bright, inverse, dim and hidden are applied there. Cursor, selection
/// and blink are the view's (Phase 5.3).
///
/// A painter owns scratch arrays it reuses, so drawing rows after warm-up allocates nothing of its own.
@MainActor
package final class TerminalRowPainter {
    /// The glyph and metrics cache.
    package let cache: TerminalGlyphCache
    /// How cells become colours.
    package var scheme: TerminalColorScheme

    private var lastAttributes = TerminalAttributes()
    private var lastResolved: TerminalColorScheme.Resolved
    private var lastValid = false
    private var colorCache: [TerminalRGB: MUIHsla] = [:]

    package init(cache: TerminalGlyphCache, scheme: TerminalColorScheme) {
        self.cache = cache
        self.scheme = scheme
        lastResolved = scheme.resolve(TerminalAttributes())
    }

    private func resolved(_ attributes: TerminalAttributes) -> TerminalColorScheme.Resolved {
        if lastValid, attributes == lastAttributes { return lastResolved }
        lastAttributes = attributes
        lastResolved = scheme.resolve(attributes)
        lastValid = true
        return lastResolved
    }

    private func color(_ rgb: TerminalRGB, alpha: Float = 1) -> MUIHsla {
        var hsla: MUIHsla
        if let found = colorCache[rgb] { hsla = found } else {
            hsla = MUIHsla(rgb.hsla())
            colorCache[rgb] = hsla
        }
        hsla.a = alpha
        return hsla
    }

    private func bounds(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> MUIBounds {
        MUIBounds(origin: MUIPoint(x: Float(x), y: Float(y)), size: MUISize(width: Float(w), height: Float(h)))
    }

    private func sprite(_ box: MUIBounds, _ slot: AtlasSlot, mask: MUIBounds, color: MUIHsla) -> MUIGlyph {
        MUIGlyph(bounds: box,
                 atlasBounds: bounds(slot.x, slot.y, slot.width, slot.height),
                 contentMask: mask,
                 maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                 color: color, order: 0, transform: 0)
    }

    /// Records `row` as grid row `rowIndex` of a grid `columns` wide whose top-left is `origin` in the surface's
    /// device pixels. The sink must be in a surface (`beginSurface`).
    package func draw(_ row: TerminalRow, at rowIndex: Int, columns: Int, origin: (x: Int, y: Int), into sink: SurfaceTextSink) {
        cache.prepare(for: sink.atlas)
        // A new scheme or a rebuilt atlas must not serve a stale resolution.
        lastValid = false
        let m = cache.metrics
        let cw = m.cellWidth, ch = m.cellHeight
        let top = origin.y + rowIndex * ch
        let rowBox = bounds(origin.x, top, columns * cw, ch)

        // Backgrounds: runs of equal colour over the whole width.
        var runStart = 0
        var runColor = scheme.background
        var end = 0
        func flush(to column: Int) {
            guard column > runStart else { return }
            sink.fillRect(bounds(origin.x + runStart * cw, top, (column - runStart) * cw, ch), color: color(runColor))
        }
        row.forEachCell { column, width, _, attributes in
            guard column < columns else { return }
            let bg = resolved(attributes).background
            if bg != runColor {
                flush(to: column)
                runStart = column
                runColor = bg
            }
            end = min(columns, column + width)
        }
        if scheme.background != runColor {
            flush(to: end)
            runStart = end
            runColor = scheme.background
        }
        flush(to: columns)

        // Glyphs.
        let atlas = sink.atlas
        let system = cache.system
        row.forEachCell { column, width, bytes, attributes in
            guard column < columns else { return }
            let colors = resolved(attributes)
            guard !colors.hidden else { return }
            let cellX = origin.x + column * cw
            switch cache.drawing(for: bytes, bold: attributes.bold, italic: attributes.italic) {
            case .blank:
                break
            case .glyphs(let index):
                let tint = color(colors.foreground)
                for placed in cache.glyphs(at: index) {
                    guard let packed = atlas.packed(for: placed.key, rasterize: { system.rasterize(placed.key) }),
                          packed.slot.width > 0, packed.slot.height > 0 else { continue }
                    sink.append(sprite(bounds(cellX + placed.pixelX + packed.left, top + placed.baselineY - packed.top,
                                              packed.slot.width, packed.slot.height),
                                       packed.slot, mask: rowBox, color: tint))
                }
            case .synthetic(let index):
                let entry = cache.synthetic(at: index)
                if let rects = entry.rects {
                    for r in rects {
                        sink.fillRect(bounds(cellX + r.x0, top + r.y0, r.x1 - r.x0, r.y1 - r.y0),
                                      color: color(colors.foreground, alpha: Float(r.coverage) / 255))
                    }
                } else if let key = entry.key {
                    let image = SyntheticGlyphs.raster(for: entry.scalar, cellWidth: cw, cellHeight: ch)
                    if let packed = atlas.packed(for: key, rasterize: { image ?? .empty }),
                       packed.slot.width > 0, packed.slot.height > 0 {
                        sink.append(sprite(bounds(cellX, top, cw, ch), packed.slot, mask: rowBox,
                                           color: color(colors.foreground)))
                    }
                }
            }
            _ = width
        }

        // Decorations, merged across neighbouring cells of one style and colour.
        var underline: (start: Int, end: Int, style: TerminalUnderlineStyle, color: TerminalRGB)?
        func flushUnderline() {
            if let u = underline { drawUnderline(u.style, from: u.start, to: u.end, color: u.color, top: top, origin: origin.x, sink: sink) }
            underline = nil
        }
        var strike: (start: Int, end: Int, color: TerminalRGB)?
        func flushStrike() {
            if let s = strike {
                sink.fillRect(bounds(origin.x + s.start * cw, top + m.strikeTop, (s.end - s.start) * cw, m.underlineThickness),
                              color: color(s.color))
            }
            strike = nil
        }
        row.forEachCell { column, width, _, attributes in
            guard column < columns else { return }
            let stop = min(columns, column + width)
            if attributes.underlineStyle != .none {
                let c = resolved(attributes).underline
                if let u = underline, u.end == column, u.style == attributes.underlineStyle, u.color == c {
                    underline?.end = stop
                } else {
                    flushUnderline()
                    underline = (column, stop, attributes.underlineStyle, c)
                }
            } else { flushUnderline() }
            if attributes.strikethrough {
                let c = resolved(attributes).foreground
                if let s = strike, s.end == column, s.color == c { strike?.end = stop } else {
                    flushStrike()
                    strike = (column, stop, c)
                }
            } else { flushStrike() }
        }
        flushUnderline()
        flushStrike()
    }

    /// One underline of `style` over columns `start..<end`. Dotted, dashed and curly patterns are keyed on the
    /// pixel column from the grid's left edge, so a run split across cells draws as the whole run would.
    private func drawUnderline(_ style: TerminalUnderlineStyle, from start: Int, to end: Int, color rgb: TerminalRGB,
                               top: Int, origin: Int, sink: SurfaceTextSink) {
        let m = cache.metrics
        let th = m.underlineThickness
        let x0 = origin + start * m.cellWidth, width = (end - start) * m.cellWidth
        let tint = color(rgb)
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { sink.fillRect(bounds(x, top + y, w, h), color: tint) }
        switch style {
        case .none:
            break
        case .single:
            rect(x0, m.underlineTop, width, th)
        case .double:
            let first = max(0, min(m.underlineTop, m.cellHeight - 3 * th))
            rect(x0, first, width, th)
            rect(x0, first + 2 * th, width, th)
        case .dotted, .dashed:
            let on = style == .dotted ? th : 3 * th, period = style == .dotted ? 2 * th : 5 * th
            var x = 0
            while x < width {
                let phase = ((x0 - origin + x) % period + period) % period
                let run = phase < on ? min(on - phase, width - x) : min(period - phase, width - x)
                if phase < on { rect(x0 + x, m.underlineTop, run, th) }
                x += max(1, run)
            }
        case .curly:
            let amplitude = max(1, th)
            let period = m.cellWidth
            for x in 0..<width {
                let phase = ((x0 - origin + x) % period + period) % period
                let tri = Double(abs(2 * phase - period)) / Double(period)      // 1 at the cell edge, 0 in the middle
                let y = min(m.underlineTop + Int((tri * Double(amplitude)).rounded()), m.cellHeight - th)
                rect(x0 + x, max(0, y), 1, th)
            }
        }
    }
}
