import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// Multi-line editable text (ruling TI-H): `TextField`'s editing — caret,
/// selection, input methods, the clipboard, undo — over wrapped lines, with
/// return inserting a line break, up and down moving between display lines,
/// and a vertical scroll that follows the caret and the mouse wheel.
///
/// **Controlled**, like `TextField`: it shows `text` and calls `onChange`
/// with every edit.
///
/// ```swift
/// TextEditor(text: model.notes) { model.notes = $0 }
///     .frame(height: Pixels(200))
/// ```
///
/// It draws line by line from `TextSystem.lineRanges` — the lines `Text`
/// wraps into — so the caret, a press and the glyphs read one line model.
public struct TextEditor: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    public var placeholder: String
    public var text: String
    public var onChange: @MainActor (String) -> Void
    public var fontFamily: String?
    public var fontSize: Double
    public var foregroundColor: ColorToken?

    public init(_ placeholder: String = "", text: String, onChange: @escaping @MainActor (String) -> Void) {
        self.style = Style()
        self.decoration = Decoration()
        self.placeholder = placeholder
        self.text = text
        self.onChange = onChange
        self.fontSize = 13
    }

    public func font(family: String? = nil, size: Double) -> TextEditor {
        var copy = self
        copy.fontFamily = family
        copy.fontSize = size
        return copy
    }

    public func foregroundColor(_ token: ColorToken) -> TextEditor {
        var copy = self
        copy.foregroundColor = token
        return copy
    }

    public struct Layout {
        public var node: LayoutNodeID
    }

    // MARK: Layout

    /// The height `text` needs wrapped at `width`: one line height per
    /// display line, a trailing line break opening one more.
    @MainActor
    static func contentHeight(_ text: String, width: Double?, font: FontKey, system: any TextSystem) -> Double {
        let lineHeight = TextField.lineHeight(font: font, system: system)
        var count = system.lineRanges(text, font: font, wrappingAt: width.map { max($0, smallestWrapWidth) }).count
        if text.last?.isNewline == true { count += 1 }
        return Double(max(count, 1)) * lineHeight
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let system = pass.textSystem
        let key = system.resolveFont(family: fontFamily, size: fontSize)
        let text = self.text, placeholder = self.placeholder
        // Greedy on both axes, as SwiftUI's `TextEditor` is.
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .textEditor) {
            pass.frame.requestNativeLeaf { proposal in
                MainActor.assumeIsolated {
                    let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
                        ?? TextField.naturalWidth(text: text, placeholder: placeholder, font: key, system: system)
                    let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
                        ?? Self.contentHeight(text, width: width, font: key, system: system)
                    return LayoutMeasurement(size: SizeD(width: width, height: height))
                }
            }
        }
        return (node, Layout(node: node))
    }

    // MARK: Geometry

    /// `string`'s display lines at `width`, in graphemes.
    @MainActor
    static func lineModel(_ string: String, width: Double, font: FontKey, system: any TextSystem) -> TextLineModel {
        let characters = Array(string)
        // The UTF-16 offset of every grapheme boundary, to map the text
        // system's ranges onto graphemes.
        var boundaries = [0]
        for character in characters { boundaries.append(boundaries.last! + character.utf16.count) }
        func grapheme(atUTF16 unit: Int) -> Int {
            var index = 0
            while index + 1 < boundaries.count && boundaries[index + 1] <= unit { index += 1 }
            return index
        }
        var lines: [TextLineModel.Line] = []
        for range in system.lineRanges(string, font: font, wrappingAt: max(width, smallestWrapWidth)) {
            let lower = grapheme(atUTF16: range.lowerBound), upper = grapheme(atUTF16: range.upperBound)
            let hardBreak = upper > lower && characters[upper - 1].isNewline
            let content = lower..<(hardBreak ? upper - 1 : upper)
            lines.append(.init(range: content,
                               offsets: system.caretOffsets(String(characters[content]), font: font),
                               endsInHardBreak: hardBreak))
        }
        // A trailing line break opens an empty last line, where the caret goes.
        if lines.isEmpty || characters.last?.isNewline == true {
            lines.append(.init(range: characters.count..<characters.count, offsets: [0], endsInHardBreak: false))
        }
        return TextLineModel(lines: lines)
    }

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

    @MainActor
    func geometry(bounds: Bounds<Pixels>, state: TextEditState, system: any TextSystem) -> Geometry {
        let font = system.resolveFont(family: fontFamily, size: fontSize)
        let state = state.clamped(to: text.count)
        let characters = Array(text)
        let width = Double(bounds.size.width.value), height = Double(bounds.size.height.value)
        let lineHeight = TextField.lineHeight(font: font, system: system)
        let textLines = Self.lineModel(text, width: width, font: font, system: system)
        var display = text, displayLines = textLines
        var caretIndex = state.head, selection = state.selection
        var composition: Range<Int>?
        if !state.composition.text.isEmpty {
            let marked = Array(state.composition.text)
            let start = state.selection.lowerBound
            display = String(characters[..<start]) + String(marked) + String(characters[state.selection.upperBound...])
            displayLines = Self.lineModel(display, width: width, font: font, system: system)
            composition = start..<(start + marked.count)
            caretIndex = start + min(state.composition.selection.upperBound, marked.count)
            selection = caretIndex..<caretIndex
        }
        let contentHeight = Double(displayLines.lines.count) * lineHeight
        let maxScrollY = max(0, contentHeight - height)
        var scrollY = min(max(state.scrollY, 0), maxScrollY)
        if state.revealsCaret {
            let top = Double(displayLines.lineIndex(of: caretIndex)) * lineHeight
            if top < scrollY { scrollY = top }
            if top + lineHeight > scrollY + height { scrollY = top + lineHeight - height }
            scrollY = min(max(scrollY, 0), maxScrollY)
        }
        return Geometry(display: display, displayLines: displayLines, textLines: textLines,
                        caretIndex: caretIndex, selection: selection, composition: composition,
                        lineHeight: lineHeight, contentX: Double(bounds.origin.x.value),
                        contentY: Double(bounds.origin.y.value), scrollY: scrollY, maxScrollY: maxScrollY,
                        revealed: state.revealsCaret)
    }

    // MARK: Phases

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        let system = pass.frame.textSystem
        var state = TextEditState()
        pass.withState(id, initial: TextEditState()) { state = $0 }
        let g = geometry(bounds: bounds, state: state, system: system)
        // The caret reveal and the clamp are written back in the phase, as
        // `TextField`'s scroll is: a function of the caret and the size, so
        // it converges in one frame and writes nothing after.
        if g.scrollY != state.scrollY || g.revealed {
            pass.withState(id, initial: TextEditState()) {
                $0.scrollY = g.scrollY
                $0.revealsCaret = false
            }
        }
        let offset = pass.frame.activeOffset
        let originX = g.contentX + Double(offset.x.value)
        let originY = g.contentY - g.scrollY + Double(offset.y.value)
        let caretLine = g.displayLines.lineIndex(of: g.caretIndex)
        let caretRect = Bounds(origin: Point(x: Pixels(Float(originX + g.displayLines.x(of: g.caretIndex))),
                                             y: Pixels(Float(originY + Double(caretLine) * g.lineHeight))),
                               size: Size(width: Pixels(1), height: Pixels(Float(g.lineHeight))))
        var handlers = self.handlers
        handlers.isFocusable = true
        handlers.textInput = TextInputTarget(
            text: text, caretOffsets: [], originX: originX, caretRect: caretRect,
            onChange: onChange, onSubmit: nil, lines: g.textLines, originY: originY,
            lineHeight: g.lineHeight, maxScrollY: g.maxScrollY)
        if handlers.axNode.isEmpty {
            handlers.axNode = AXNode(role: .textArea, label: placeholder.isEmpty ? nil : placeholder, value: text)
        }
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        pass.paintDecoration(decoration, in: bounds, for: id) {
            paintContent(id, bounds: bounds, pass: &pass)
        }
    }

    private func paintContent(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PaintPass) {
        let system = pass.textSystem
        let font = system.resolveFont(family: fontFamily, size: fontSize)
        var state = TextEditState()
        pass.withState(id, initial: TextEditState()) { state = $0 }
        let g = geometry(bounds: bounds, state: state, system: system)
        let focused = pass.isFocused(id)
        let textColor = pass.theme[foregroundColor ?? .textPrimary]
        let characters = Array(g.display)
        let top = g.contentY - g.scrollY, bottom = Double(bounds.origin.y.value + bounds.size.height.value)
        func rect(_ x0: Double, _ x1: Double, y: Double, height: Double) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(g.contentX + x0)), y: Pixels(Float(y))),
                   size: Size(width: Pixels(Float(max(0, x1 - x0))), height: Pixels(Float(height))))
        }
        pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            if g.display.isEmpty {
                var color = textColor
                color.a *= 0.45
                for glyph in system.placeGlyphs(placeholder, font: font, wrappingAt: max(Double(bounds.size.width.value), smallestWrapWidth),
                                                origin: (x: g.contentX, y: top), scaleFactor: pass.scaleFactor) {
                    pass.draw(glyph, color: color)
                }
            }
            var selectionColor = pass.theme[.accent]
            selectionColor.a *= 0.3
            for (index, line) in g.displayLines.lines.enumerated() {
                let y = top + Double(index) * g.lineHeight
                guard y + g.lineHeight > Double(bounds.origin.y.value), y < bottom else { continue }
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
                for glyph in system.placeGlyphs(String(characters[line.range]), font: font, wrappingAt: nil,
                                                origin: (x: g.contentX, y: y), scaleFactor: pass.scaleFactor) {
                    pass.draw(glyph, color: textColor)
                }
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
