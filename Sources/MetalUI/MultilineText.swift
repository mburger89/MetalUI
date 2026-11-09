import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// The geometry and the line-by-line drawing `TextEditor` and a vertical `TextField` share (`VT-A`): one
/// reading of the text's display lines, the caret's reveal and the clamped scroll, and one paint loop over
/// those lines, so the two draw, scroll and aim a press identically. Extracted from `TextEditor` without
/// changing its scene (record 255, the byte comparison of its scenes before and after).
enum MultilineText {
    struct Geometry {
        var display: String
        var displayLines: TextLineModel
        var textLines: TextLineModel
        var caretIndex: Int
        var selection: Range<Int>
        var composition: Range<Int>?
        var lineHeight: Double
        var contentX: Double
        var contentY: Double
        var scrollY: Double
        var maxScrollY: Double
        var revealed: Bool
    }

    /// `text` laid out in `bounds` (the text's own rect: a field's content rect inside its chrome).
    /// `focused: false` reads the scroll as 0 and reveals nothing: an unfocused vertical field draws from the
    /// top and keeps its stored scroll (`VT-D`); `maxScrollY` is the content's regardless.
    @MainActor
    static func geometry(text: String, bounds: Bounds<Pixels>, state: TextEditState, system: any TextSystem,
                         font: FontKey, focused: Bool = true) -> Geometry {
        let state = state.clamped(to: text.count)
        let characters = Array(text)
        let width = Double(bounds.size.width.value), height = Double(bounds.size.height.value)
        let lineHeight = TextField.lineHeight(font: font, system: system)
        let textLines = TextEditor.lineModel(text, width: width, font: font, system: system)
        var display = text, displayLines = textLines
        var caretIndex = state.head, selection = state.selection
        var composition: Range<Int>?
        if !state.composition.text.isEmpty {
            let marked = Array(state.composition.text)
            let start = state.selection.lowerBound
            display = String(characters[..<start]) + String(marked) + String(characters[state.selection.upperBound...])
            displayLines = TextEditor.lineModel(display, width: width, font: font, system: system)
            composition = start..<(start + marked.count)
            caretIndex = start + min(state.composition.selection.upperBound, marked.count)
            selection = caretIndex..<caretIndex
        }
        let contentHeight = Double(displayLines.lines.count) * lineHeight
        let maxScrollY = max(0, contentHeight - height)
        var scrollY = focused ? min(max(state.scrollY, 0), maxScrollY) : 0
        let reveals = focused && state.revealsCaret
        if reveals {
            let top = Double(displayLines.lineIndex(of: caretIndex)) * lineHeight
            if top < scrollY { scrollY = top }
            if top + lineHeight > scrollY + height { scrollY = top + lineHeight - height }
            scrollY = min(max(scrollY, 0), maxScrollY)
        }
        return Geometry(display: display, displayLines: displayLines, textLines: textLines,
                        caretIndex: caretIndex, selection: selection, composition: composition,
                        lineHeight: lineHeight, contentX: Double(bounds.origin.x.value),
                        contentY: Double(bounds.origin.y.value), scrollY: scrollY, maxScrollY: maxScrollY,
                        revealed: reveals)
    }

    /// The placeholder, the selection, the glyphs of each display line, the marked-text underline and the caret, clipped
    /// to `clip`; a line wholly outside `cull` is skipped. `wrapWidth` wraps the placeholder.
    @MainActor
    static func paintLines(_ g: Geometry, placeholder: String, font: FontKey, system: any TextSystem,
                           textColor: Hsla, wrapWidth: Double, clip: Bounds<Pixels>, cull: Bounds<Pixels>,
                           focused: Bool, pass: inout PaintPass) {
        let characters = Array(g.display)
        let top = g.contentY - g.scrollY, bottom = Double(cull.origin.y.value + cull.size.height.value)
        func rect(_ x0: Double, _ x1: Double, y: Double, height: Double) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(g.contentX + x0)), y: Pixels(Float(y))),
                   size: Size(width: Pixels(Float(max(0, x1 - x0))), height: Pixels(Float(height))))
        }
        pass.clipped(to: clip, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            if g.display.isEmpty {
                var color = textColor
                color.a *= 0.45
                pass.drawGlyphs(system.placeGlyphs(placeholder, font: font,
                                                   wrappingAt: max(wrapWidth, smallestWrapWidth),
                                                   origin: (x: g.contentX, y: top), scaleFactor: pass.scaleFactor),
                                color: color)
            }
            var selectionColor = pass.resolve(.accentColor)
            selectionColor.a *= 0.3
            for (index, line) in g.displayLines.lines.enumerated() {
                let y = top + Double(index) * g.lineHeight
                guard y + g.lineHeight > Double(cull.origin.y.value), y < bottom else { continue }
                // The selection on this line; a selected line break shows as a
                // short tail past the line's end, as AppKit's text views do.
                let lower = max(g.selection.lowerBound, line.range.lowerBound)
                let upper = min(g.selection.upperBound, line.range.upperBound)
                if lower < upper || (line.endsInHardBreak && g.selection.contains(line.range.upperBound)) {
                    let x0 = line.offsets[max(lower, line.range.lowerBound) - line.range.lowerBound]
                    var x1 = line.offsets[min(max(upper, lower), line.range.upperBound) - line.range.lowerBound]
                    if line.endsInHardBreak && g.selection.contains(line.range.upperBound) { x1 += 4 }
                    pass.fill(rect(x0, x1, y: y, height: g.lineHeight), color: selectionColor)
                }
                pass.drawGlyphs(system.placeGlyphs(String(characters[line.range]), font: font, wrappingAt: nil,
                                                   origin: (x: g.contentX, y: y), scaleFactor: pass.scaleFactor),
                                color: textColor)
                if let marked = g.composition {
                    let a = max(marked.lowerBound, line.range.lowerBound), b = min(marked.upperBound, line.range.upperBound)
                    if a < b {
                        pass.fill(rect(line.offsets[a - line.range.lowerBound], line.offsets[b - line.range.lowerBound],
                                       y: y + g.lineHeight - 1, height: 1), color: textColor)
                    }
                }
            }
            if focused && g.selection.isEmpty {
                let line = g.displayLines.lineIndex(of: g.caretIndex)
                let x = g.displayLines.x(of: g.caretIndex)
                pass.fill(rect(x, x + 1, y: top + Double(line) * g.lineHeight, height: g.lineHeight), color: textColor)
            }
        }
    }
}

/// A vertical `TextField`'s height, one pure function of what SwiftUI's answer depends on (`VT-B`, probe
/// `swiftui-vertical-text-field.swift` arm S): the display lines, the line height, the chrome's vertical inset,
/// the `lineLimit` bounds and the height proposal.
enum VerticalFieldMetrics {
    /// The number of display lines the field's text takes at `width` (the field's whole width; `nil` or
    /// infinite is unwrapped): the placeholder's lines while the text is empty, and one more after a trailing
    /// line break, counted by the same `lineRanges` a `TextEditor` wraps with.
    @MainActor
    static func displayLines(text: String, placeholder: String, width: Double?, horizontalInset: Double,
                             font: FontKey, system: any TextSystem) -> Int {
        let source = text.isEmpty ? placeholder : text
        let wrap = width.flatMap { $0.isFinite ? max($0 - 2 * horizontalInset, smallestWrapWidth) : nil }
        var count = system.lineRanges(source, font: font, wrappingAt: wrap).count
        if source.last?.isNewline == true { count += 1 }
        return max(count, 1)
    }

    /// The field's height. The content is the shown lines (`displayLines` held between the lower bound, 1 without one,
    /// and the upper bound) times the line height plus both vertical insets; a nil or infinite `proposal` is answered with
    /// it, any other with the proposal clamped to the content above and, only when there is a lower bound, to that bound's
    /// height below. A bound under 1 reads as 1.
    static func height(displayLines: Int, lineHeight: Double, verticalInset: Double, limit: TextLineLimit,
                       proposal: Double?) -> Double {
        let lower = limit.min.map { max($0, 1) }, upper = limit.max.map { max($0, 1) }
        var shown = max(displayLines, lower ?? 1)
        if let upper { shown = min(shown, upper) }
        let content = Double(shown) * lineHeight + 2 * verticalInset
        guard let proposal, proposal.isFinite else { return content }
        let floor = lower.map { Double(min($0, upper ?? $0)) * lineHeight + 2 * verticalInset } ?? 0
        return max(floor, min(proposal, content))
    }
}
