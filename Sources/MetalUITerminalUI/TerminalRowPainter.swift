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
    /// The selection's colour and opacity (`TRM-BA`): composited over a selected cell's background.
    package var selectionColor = TerminalRGB(0x33, 0x66, 0xcc)
    /// The selection's opacity, 0...1.
    package var selectionAlpha: Float = 0.5

    private var colorCache: [TerminalRGB: MUIHsla] = [:]
    private var lastColorRGB = TerminalRGB(0, 0, 0)
    private var lastColor = MUIHsla(h: 0, s: 0, l: 0, a: 1)
    private var lastColorValid = false

    /// What one run of a row draws with, resolved once per run per draw instead of once per cell (`TRM-BL`).
    private struct RunInfo {
        var colors: TerminalColorScheme.Resolved
        var foreground: MUIHsla
        var bold: Bool
        var italic: Bool
        var underlineStyle: TerminalUnderlineStyle
        var strikethrough: Bool
    }
    /// Index 0 is the default rendition (run -1), index `n + 1` is run `n`; reused across draws.
    private var runInfo: [RunInfo] = []

    package init(cache: TerminalGlyphCache, scheme: TerminalColorScheme) {
        self.cache = cache
        self.scheme = scheme
    }

    private func color(_ rgb: TerminalRGB, alpha: Float = 1) -> MUIHsla {
        var hsla: MUIHsla
        if lastColorValid, rgb == lastColorRGB { hsla = lastColor } else {
            if let found = colorCache[rgb] { hsla = found } else {
                hsla = MUIHsla(rgb.hsla())
                colorCache[rgb] = hsla
            }
            lastColorRGB = rgb
            lastColor = hsla
            lastColorValid = true
        }
        hsla.a = alpha
        return hsla
    }

    private func info(_ attributes: TerminalAttributes) -> RunInfo {
        let colors = scheme.resolve(attributes)
        return RunInfo(colors: colors, foreground: color(colors.foreground), bold: attributes.bold, italic: attributes.italic,
                       underlineStyle: attributes.underlineStyle, strikethrough: attributes.strikethrough)
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
    ///
    /// `selection` is the half-open column range the selection covers on this row: after the backgrounds and
    /// before the glyphs the painter records one rect of ``selectionColor`` at ``selectionAlpha`` over it, so the
    /// glyphs stay legible whatever the alpha (`TRM-BA`). `link` is the half-open column range of the link under a
    /// ⌘-hovered pointer: one single underline in the default foreground over it, after the glyphs (`TRM-BD`).
    package func draw(_ row: TerminalRow, at rowIndex: Int, columns: Int, origin: (x: Int, y: Int), into sink: SurfaceTextSink,
                      selection: Range<Int>? = nil, link: Range<Int>? = nil) {
        cache.prepare(for: sink.atlas)
        // A new scheme or a rebuilt atlas must not serve a stale resolution.
        lastColorValid = false
        // One resolution per run, not per cell (`TRM-BL`).
        runInfo.removeAll(keepingCapacity: true)
        runInfo.append(info(TerminalAttributes()))
        for run in 0..<row.runCount { runInfo.append(info(row.attributes(ofRun: run))) }
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
        row.forEachCellByRun({ column, width, _, run in
            guard column < columns else { return }
            let bg = runInfo[run + 1].colors.background
            if bg != runColor {
                flush(to: column)
                runStart = column
                runColor = bg
            }
            end = min(columns, column + width)
        })
        if scheme.background != runColor {
            flush(to: end)
            runStart = end
            runColor = scheme.background
        }
        flush(to: columns)

        // The selection, over the backgrounds and under the glyphs.
        if let selection {
            let lo = max(0, selection.lowerBound), hi = min(columns, selection.upperBound)
            if hi > lo {
                sink.fillRect(bounds(origin.x + lo * cw, top, (hi - lo) * cw, ch),
                              color: color(selectionColor, alpha: selectionAlpha))
            }
        }

        // Glyphs.
        row.forEachCellByRun({ column, _, bytes, run in
            guard column < columns else { return }
            let info = runInfo[run + 1]
            guard !info.colors.hidden else { return }
            let cellX = origin.x + column * cw
            drawCellGlyphs(bytes, bold: info.bold, italic: info.italic, tint: info.colors.foreground, hsla: info.foreground,
                           cellX: cellX, top: top, rowBox: rowBox, into: sink)
        })

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
        row.forEachCellByRun({ column, width, _, run in
            guard column < columns else { return }
            let info = runInfo[run + 1]
            if info.underlineStyle == .none && !info.strikethrough {
                if underline != nil { flushUnderline() }
                if strike != nil { flushStrike() }
                return
            }
            let stop = min(columns, column + width)
            if info.underlineStyle != .none {
                let c = info.colors.underline
                if let u = underline, u.end == column, u.style == info.underlineStyle, u.color == c {
                    underline?.end = stop
                } else {
                    flushUnderline()
                    underline = (column, stop, info.underlineStyle, c)
                }
            } else { flushUnderline() }
            if info.strikethrough {
                let c = info.colors.foreground
                if let s = strike, s.end == column, s.color == c { strike?.end = stop } else {
                    flushStrike()
                    strike = (column, stop, c)
                }
            } else { flushStrike() }
        })
        flushUnderline()
        flushStrike()
        if let link {
            let lo = max(0, link.lowerBound), hi = min(columns, link.upperBound)
            if hi > lo { drawUnderline(.single, from: lo, to: hi, color: scheme.foreground, top: top, origin: origin.x, sink: sink) }
        }
    }

    /// The cursor's shapes (`TRM-BA`).
    package enum CursorShape: Equatable, Sendable {
        /// A filled cell with the glyph redrawn in the cursor-text colour.
        case block
        /// A one-eighth-cell bar at the cell's left edge (at least one pixel).
        case bar
        /// A line along the cell's bottom, as thick as an underline.
        case underline
        /// The block's outline, as thick as an underline: the unfocused block (Terminal.app's).
        case hollow
    }

    /// Records the cursor over column `column` of `row`, grid row `rowIndex`, after the row itself: in call order
    /// it lies over the row's own pixels, so redrawing a row and then its cursor replaces both. A pending-wrap
    /// column past the last clamps to the last. A wide cell takes both columns. `textColor` is the glyph colour
    /// of a filled block.
    package func drawCursor(_ shape: CursorShape, row: TerminalRow, column requested: Int, columns: Int, at rowIndex: Int,
                            origin: (x: Int, y: Int), color rgb: TerminalRGB, textColor: TerminalRGB,
                            into sink: SurfaceTextSink) {
        cache.prepare(for: sink.atlas)
        let m = cache.metrics
        let cw = m.cellWidth, ch = m.cellHeight
        let column = max(0, min(requested, columns - 1))
        let top = origin.y + rowIndex * ch
        var width = 1
        var found: (bytes: ArraySlice<UInt8>, attributes: TerminalAttributes)?
        var start = column
        row.forEachCell { c, w, bytes, attributes in
            if c <= column, column < c + w { width = w; start = c; found = (bytes, attributes) }
        }
        let x = origin.x + start * cw
        let box = bounds(x, top, width * cw, ch)
        let tint = color(rgb)
        let th = max(1, m.underlineThickness)
        switch shape {
        case .block:
            sink.fillRect(box, color: tint)
            if let found, !found.attributes.hidden {
                drawCellGlyphs(found.bytes, bold: found.attributes.bold, italic: found.attributes.italic, tint: textColor,
                               hsla: color(textColor), cellX: x, top: top,
                               rowBox: bounds(origin.x, top, columns * cw, ch), into: sink)
            }
        case .bar:
            sink.fillRect(bounds(x, top, max(1, cw / 8), ch), color: tint)
        case .underline:
            sink.fillRect(bounds(x, top + ch - th, width * cw, th), color: tint)
        case .hollow:
            let w = width * cw
            let t = min(th, max(1, min(w, ch) / 2))
            sink.fillRect(bounds(x, top, w, t), color: tint)
            sink.fillRect(bounds(x, top + ch - t, w, t), color: tint)
            sink.fillRect(bounds(x, top + t, t, ch - 2 * t), color: tint)
            sink.fillRect(bounds(x + w - t, top + t, t, ch - 2 * t), color: tint)
        }
    }

    /// The glyphs of one cell (shaped or synthesised) in `tint` (`hsla` is the same colour as the renderer's), masked to
    /// `rowBox`.
    private func drawCellGlyphs(_ bytes: ArraySlice<UInt8>, bold: Bool, italic: Bool, tint rgb: TerminalRGB, hsla tint: MUIHsla,
                                cellX: Int, top: Int, rowBox: MUIBounds, into sink: SurfaceTextSink) {
        let m = cache.metrics
        let cw = m.cellWidth, ch = m.cellHeight
        let atlas = sink.atlas
        switch cache.drawing(for: bytes, bold: bold, italic: italic) {
        case .blank:
            break
        case .glyphs(let index):
            for placed in cache.sprites(at: index, in: atlas) {
                let packed = placed.packed
                sink.append(sprite(bounds(cellX + placed.pixelX + packed.left, top + placed.baselineY - packed.top,
                                          packed.slot.width, packed.slot.height),
                                   packed.slot, mask: rowBox, color: tint))
            }
        case .synthetic(let index):
            let entry = cache.synthetic(at: index)
            if let rects = entry.rects {
                for r in rects {
                    sink.fillRect(bounds(cellX + r.x0, top + r.y0, r.x1 - r.x0, r.y1 - r.y0),
                                  color: color(rgb, alpha: Float(r.coverage) / 255))
                }
            } else if let key = entry.key {
                let image = SyntheticGlyphs.raster(for: entry.scalar, cellWidth: cw, cellHeight: ch)
                if let packed = atlas.packed(for: key, rasterize: { image ?? .empty }),
                   packed.slot.width > 0, packed.slot.height > 0 {
                    sink.append(sprite(bounds(cellX, top, cw, ch), packed.slot, mask: rowBox,
                                       color: color(rgb)))
                }
            }
        }
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
