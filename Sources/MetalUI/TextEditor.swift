import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// Multi-line editable text (ruling TI-H): `TextField`'s editing — caret,
/// selection, input methods, the clipboard, undo — over wrapped lines, with
/// return inserting a line break, up and down moving between display lines,
/// and a vertical scroll that follows the caret and the mouse wheel.
///
/// **⌘↩ (⌃↩ off macOS) is not an editing key** (ruling `KF-Z` item 2): it
/// passes on to `onKey`, a `Button`'s shortcut, the app's commands and the
/// window. To commit on it, test the platform's shortcut modifier — `.command`
/// on macOS, `.control` on Linux and Windows (MetalUI exposes no constant for
/// it) — in an `onKeyPress`, which runs before the editor's own keys:
///
/// ```swift
/// #if os(macOS)
/// let commitModifier: Modifiers = .command
/// #else
/// let commitModifier: Modifiers = .control
/// #endif
/// TextEditor(text: model.notes) { model.notes = $0 }
///     .onKeyPress(keys: [.return]) { press in
///         press.modifiers.contains(commitModifier) ? commit() : .ignored
///     }
/// ```
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
///
/// **Draws SwiftUI's opaque text background by default** (ruling `MD-F`): a
/// square `.surface` fill over its bounds and the control focus ring while
/// focused; `.textEditorStyle(.plain)` draws neither. Its size and text
/// placement are unchanged (divergence 133).
public struct TextEditor: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    /// Shown, dimmed, while `text` is empty.
    public var placeholder: String
    /// The text shown; the editor never changes it itself.
    public var text: String
    /// Called with the edited text after each edit.
    public var onChange: @MainActor (String) -> Void
    /// The selection the caller wants applied (`SL-B`); `nil` is the field's own.
    var selection: AnyHashable?
    /// Writes the field's selection, given as a range and its text, to the caller
    /// after each input that moved it and returns the value written (`SL-B`); `nil`
    /// when the field has no selection binding. Type-erased: `TextSelection` is
    /// macOS 15 (`SL-L`).
    var selectionWriter: (@MainActor (Range<Int>, String) -> AnyHashable)?
    /// The text's own colour; `nil` inherits the foreground style.
    public var foregroundColor: Color?
    /// The field's own font request (ruling TE-F item 2): inherit the
    /// environment's font, the default font, or an explicit one.
    var fontRequest: TextFontRequest = .inherit
    /// The editor's own style (ruling `MD-F`); `nil` reads the environment's,
    /// `.automatic` by default.
    var editorStyle: TextEditorStyle?

    /// The explicit font's family; computed over the request (TE-F item 2).
    public var fontFamily: String? {
        get { fontRequest.familyAndSize.family }
        set { fontRequest = .legacy(family: newValue, size: fontSize) }
    }
    /// The explicit font's size, 13 without one; computed (TE-F item 2).
    public var fontSize: Double {
        get { fontRequest.familyAndSize.size }
        set { fontRequest = .legacy(family: fontFamily, size: newValue) }
    }

    /// A controlled multi-line editor showing `text` and reporting each edit to
    /// `onChange` (`TI-H`).
    public init(_ placeholder: String = "", text: String, onChange: @escaping @MainActor (String) -> Void) {
        self.style = Style()
        self.decoration = Decoration()
        self.placeholder = placeholder
        self.text = text
        self.onChange = onChange
    }

    /// Bound to `text` (ruling `DD-E`): shows `text.wrappedValue` and writes
    /// every edit back through the binding. Builds exactly the element the
    /// controlled initialiser builds; bound to `.constant`, it shows the text
    /// and drops every edit. The write happens in the edit dispatch — input —
    /// as a `Binding` write must (`DD-D` item 7).
    ///
    /// ```swift
    /// @State var name = ""
    /// … TextEditor(text: $name)
    /// ```
    public init(_ placeholder: String = "", text: Binding<String>) {
        self.init(placeholder, text: text.wrappedValue, onChange: { text.wrappedValue = $0 })
    }

    /// Bound to `text` and to a `TextSelection` (SwiftUI's
    /// `TextEditor(_:text:selection:)`, rulings `SL-A`, `SL-B`): the field writes the
    /// selection to `selection` after each input that moved it, and applies a value
    /// written there on the next frame. A `nil` binding is the field's own
    /// selection. Both writes happen in input, never in a phase.
    @available(macOS 15, *)
    public init(_ placeholder: String = "", text: Binding<String>, selection: Binding<TextSelection?>) {
        self.init(placeholder, text: text.wrappedValue, selection: selection.wrappedValue,
                  onChange: { text.wrappedValue = $0 },
                  onSelectionChange: { selection.wrappedValue = $0 })
    }

    /// Bound to `text` and to the selection as Character offsets into it — MetalUI-only
    /// (ruling `SL-Q`), and **not** macOS 15: `TextSelection` is `RangeSet`'s, which the
    /// standard library has from macOS 15, while this spelling is plain `Range<Int>` and
    /// runs on macOS 14. The offsets are `Character` (grapheme) positions in the current
    /// `text`; empty is the caret. It behaves as the `TextSelection` binding does
    /// (`SL-B`..`SL-J`): the editor writes it after each input that moved the selection and
    /// applies a value written there on the next frame, a `nil` is the editor's own
    /// selection, a stale range clamps into the text. Both writes happen in input, never in
    /// a phase. Insert at the caret by editing `text` and writing the caret after the
    /// insertion: `text.insert(contentsOf: s, at: i); caret = (i + s.count)..<(i + s.count)`.
    public init(_ placeholder: String = "", text: Binding<String>, selectedOffsets: Binding<Range<Int>?>) {
        self.init(placeholder, text: text.wrappedValue, onChange: { text.wrappedValue = $0 })
        self.selection = selectedOffsets.wrappedValue.map { AnyHashable($0) }
        self.selectionWriter = { range, _ in
            selectedOffsets.wrappedValue = range
            return AnyHashable(range)
        }
    }

    /// The controlled spelling of the selection binding (`SL-A`): shows `text` and
    /// `selection` and reports each edit to `onChange` and each selection the
    /// field makes to `onSelectionChange`.
    @available(macOS 15, *)
    public init(_ placeholder: String, text: String, selection: TextSelection?,
                onChange: @escaping @MainActor (String) -> Void,
                onSelectionChange: @escaping @MainActor (TextSelection) -> Void) {
        self.init(placeholder, text: text, onChange: onChange)
        self.selection = selection.map { AnyHashable($0) }
        self.selectionWriter = { range, text in
            let written = TextSelection(offsets: range, in: text)
            onSelectionChange(written)
            return AnyHashable(written)
        }
    }

    /// Sets the editor's own font by family and size; `nil` family is the
    /// system font.
    public func font(family: String? = nil, size: Double) -> TextEditor {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        return copy
    }

    /// This text's own colour, `nil` to inherit — SwiftUI's
    /// `foregroundColor(_:)` with its optional (`CR-E` item 4).
    public func foregroundColor(_ color: Color?) -> TextEditor {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// Sets the text's colour.
    /// The `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundColor(_ token: ColorToken) -> TextEditor {
        foregroundColor(Color(token))
    }

    /// Draws this editor in `style` — SwiftUI's `textEditorStyle(_:)` written
    /// on the editor (ruling `MD-F` item 1). It wins over a container's style
    /// and returns a `TextEditor`, so its modifiers still chain.
    public func textEditorStyle(_ style: TextEditorStyle) -> TextEditor {
        var copy = self
        copy.editorStyle = style
        return copy
    }

    public struct Layout {
        /// The editor's layout node.
        public var node: LayoutNodeID
    }

    /// The face this field draws in (ruling TE-F item 2): its own font, else
    /// the environment's, else the default font by `controlSize` — `Text`'s
    /// resolution, so `.font(_:)` on a container and `.controlSize(_:)` reach
    /// it. Its colour and chrome are its own, unchanged.
    @MainActor
    func resolvedFont(in environment: EnvironmentValues, system: any TextSystem) -> FontKey {
        system.resolveFont(resolveTextStyle(TextStyleRequest(font: fontRequest), in: environment).descriptor)
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
        let key = resolvedFont(in: pass.environment, system: system)
        let text = self.text, placeholder = self.placeholder
        // Greedy on both axes, as SwiftUI's `TextEditor` is: any offered
        // width or height is taken whole — an infinite one answers infinity
        // (ruling `PE-D`, probe FL5 `inf -> infxinf`); `nil` asks for the
        // ideal (the text's natural width, and its height wrapped at the
        // answered width — unwrapped when that width is infinite).
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .textEditor) {
            pass.frame.requestNativeLeaf { proposal in
                MainActor.assumeIsolated {
                    let width = proposal.width
                        ?? TextField.naturalWidth(text: text, placeholder: placeholder, font: key, system: system)
                    let height = proposal.height
                        ?? Self.contentHeight(text, width: width.isFinite ? width : nil, font: key, system: system)
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

    typealias Geometry = MultilineText.Geometry

    @MainActor
    func geometry(bounds: Bounds<Pixels>, state: TextEditState, system: any TextSystem,
                  font: FontKey) -> Geometry {
        MultilineText.geometry(text: text, bounds: bounds, state: state, system: system, font: font)
    }

    // MARK: Phases

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        let system = pass.frame.textSystem
        var state = pass.readState(id, initial: TextEditState())   // a read, not a write (`RW-J`)
        // A bound selection (`SL-B`, `SL-D`): a value the field did not publish is
        // applied before the geometry reads the state; the baseline lets the first
        // input publish only a real change. Same phase-time write as the scroll's.
        // A text replaced from outside moves the caret to the end when there is no
        // selection binding (`SL-P`; with one the binding wins). The same compared write.
        let bound = selectionWriter != nil
        let focused = pass.frame.focusedElement == id   // the pre-clearing answer is enough here (`SL-P`)
        do {
            let selection = self.selection, text = self.text
            pass.withState(id, initial: TextEditState(), unchanged: ==) { stored in   // compared (`RW-J`)
                if bound {
                    TextEditing.reconcile(binding: selection, text: text, state: &stored)
                    if stored.reported == nil { stored.reported = stored.clamped(to: text.count).selection }
                } else {
                    TextEditing.followExternalText(text: text, focused: focused, state: &stored)
                }
                state = stored
            }
        }
        let g = geometry(bounds: bounds, state: state, system: system,
                                font: resolvedFont(in: pass.environment, system: system))
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
        let caretArea = pass.frame.effectBoundingBox(of: caretRect, ownEffects: decoration.renderEffects,
                                                     bounds: bounds)   // under render effects (`GX-I`)
        var handlers = self.handlers
        handlers.isFocusable = true
        var textLines = g.textLines
        textLines.lineHeight = g.lineHeight
        textLines.visibleHeight = Double(bounds.size.height.value)
        handlers.textInput = TextInputTarget(
            text: text, caretOffsets: [], originX: originX, caretRect: caretArea,
            onChange: onChange, onSubmit: nil, selectionSink: selectionWriter, lines: textLines, originY: originY,
            lineHeight: g.lineHeight, maxScrollY: g.maxScrollY)
        // `DA-C`: fills what was not declared, so an identifier or hint written on the field
        // does not cost it its role and text.
        handlers.axNode.fillControl(role: .textArea, label: placeholder.isEmpty ? nil : placeholder, value: text)
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        pass.paintDecoration(decoration, in: bounds, for: id) {
            // `.automatic` (`MD-F` item 2): a square `.surface` fill, no border,
            // the ring at radius 0 while focused; `.plain`: neither.
            guard (editorStyle ?? pass.environment.textEditorStyle) == .automatic else {
                paintContent(id, bounds: bounds, pass: &pass)
                return
            }
            pass.paintFieldChrome(bounds: bounds, bordered: false, radius: Pixels(0),
                                  focused: pass.isFocused(id), callerRing: decoration.focusBorder != nil) {
                paintContent(id, bounds: bounds, pass: &pass)
            }
        }
    }

    private func paintContent(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: inout PaintPass) {
        let system = pass.textSystem
        let font = resolvedFont(in: pass.environment, system: system)
        let state = pass.readState(id, initial: TextEditState())   // a read, not a write (`RW-J`)
        let g = geometry(bounds: bounds, state: state, system: system, font: font)
        let focused = pass.isFocused(id)
        let textColor = pass.resolve(foregroundColor ?? .textPrimary)
        MultilineText.paintLines(g, placeholder: placeholder, font: font, system: system, textColor: textColor,
                                 wrapWidth: Double(bounds.size.width.value), clip: bounds, cull: bounds,
                                 focused: focused, pass: &pass)
    }
}
