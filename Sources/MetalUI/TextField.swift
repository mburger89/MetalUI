import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// A single line of editable text (roadmap item 14, rulings TI-B…TI-D).
///
/// **Controlled**: it shows `text` and calls `onChange` with every edit; the
/// caller stores the new value and passes it back. Selection, the input
/// method's marked text and the horizontal scroll are the field's own, in the
/// window's `StateTable` under its id.
///
/// ```swift
/// TextField("Name", text: model.name) { model.name = $0 }
///     .onSubmit { model.save() }
/// ```
///
/// Clicking focuses it (unlike every other element), typing goes through the
/// platform's text input — keyboard layouts, dead keys, input methods — and
/// the keys of TI-D's table edit. The caret does not blink.
public struct TextField: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    /// Shown, dimmed, while `text` is empty.
    public var placeholder: String
    /// The text shown; the field never changes it itself.
    public var text: String
    /// Called with the edited text after each edit.
    public var onChange: @MainActor (String) -> Void
    /// Called when Return is pressed in the field, if set.
    public var submit: (@MainActor () -> Void)?
    /// The text's own colour; `nil` inherits the foreground style.
    public var foregroundColor: ColorToken?
    /// The field's own font request (ruling TE-F item 2): inherit the
    /// environment's font, the default font, or an explicit one.
    var fontRequest: TextFontRequest = .inherit

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

    /// A controlled one-line field showing `text` and reporting each edit to
    /// `onChange` (`TI-B`).
    public init(_ placeholder: String, text: String, onChange: @escaping @MainActor (String) -> Void) {
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
    /// … TextField("Name", text: $name)
    /// ```
    public init(_ placeholder: String, text: Binding<String>) {
        self.init(placeholder, text: text.wrappedValue, onChange: { text.wrappedValue = $0 })
    }

    /// Sets the field's own font by family and size; `nil` family is the system
    /// font.
    public func font(family: String? = nil, size: Double) -> TextField {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        return copy
    }

    /// Sets the text's colour.
    public func foregroundColor(_ token: ColorToken) -> TextField {
        var copy = self
        copy.foregroundColor = token
        return copy
    }

    /// Runs on return; without it return is not claimed and keeps bubbling.
    public func onSubmit(_ action: @escaping @MainActor () -> Void) -> TextField {
        var copy = self
        copy.submit = action
        return copy
    }

    public struct Layout {
        /// The field's layout node.
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

    /// The width a field asks for when offered none: its text or its
    /// placeholder, whichever is wider, plus the caret.
    @MainActor
    static func naturalWidth(text: String, placeholder: String, font: FontKey, system: any TextSystem) -> Double {
        let widest = max(system.measure(text, font: font, wrappingAt: nil).widestLine,
                         system.measure(placeholder, font: font, wrappingAt: nil).widestLine)
        return widest + 1
    }

    /// One line's height in `font`.
    @MainActor
    static func lineHeight(font: FontKey, system: any TextSystem) -> Double {
        system.measure(" ", font: font, wrappingAt: nil).totalHeight
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let system = pass.textSystem
        let key = resolvedFont(in: pass.environment, system: system)
        let text = self.text, placeholder = self.placeholder
        // Greedy on the width, as SwiftUI's `TextField` is; one line tall.
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .textField) {
            pass.frame.requestNativeLeaf { proposal in
                MainActor.assumeIsolated {
                    let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
                    let width = offered
                        ?? Self.naturalWidth(text: text, placeholder: placeholder, font: key, system: system)
                    return LayoutMeasurement(size: SizeD(width: width,
                                                         height: Self.lineHeight(font: key, system: system)))
                }
            }
        }
        return (node, Layout(node: node))
    }

    /// Everything prepaint and paint both need, from one reading of the
    /// field's state.
    struct Geometry {
        var display: String
        var offsets: [Double]
        var caretIndex: Int
        var selection: Range<Int>
        var composition: Range<Int>?
        var lineY: Double
        var lineHeight: Double
        var contentX: Double
        var scrollX: Double
        var textOffsets: [Double]
    }

    @MainActor
    func geometry(bounds: Bounds<Pixels>, state: TextEditState, system: any TextSystem,
                  font: FontKey) -> Geometry {
        let state = state.clamped(to: text.count)
        let characters = Array(text)
        let lineHeight = Self.lineHeight(font: font, system: system)
        let textOffsets = system.caretOffsets(text, font: font)
        var display = text
        var offsets = textOffsets
        var caretIndex = state.head
        var selection = state.selection
        var composition: Range<Int>?
        if !state.composition.text.isEmpty {
            let marked = Array(state.composition.text)
            let start = state.selection.lowerBound
            display = String(characters[..<start]) + String(marked) + String(characters[state.selection.upperBound...])
            offsets = system.caretOffsets(display, font: font)
            composition = start..<(start + marked.count)
            caretIndex = start + min(state.composition.selection.upperBound, marked.count)
            selection = caretIndex..<caretIndex
        }
        let top = Double(bounds.origin.y.value)
        let height = Double(bounds.size.height.value)
        return Geometry(display: display, offsets: offsets, caretIndex: caretIndex, selection: selection,
                        composition: composition, lineY: top + max(0, (height - lineHeight) / 2),
                        lineHeight: lineHeight, contentX: Double(bounds.origin.x.value),
                        scrollX: TextEditing.scroll(keeping: offsets[caretIndex],
                                                    visibleIn: Double(bounds.size.width.value),
                                                    textWidth: offsets.last ?? 0, current: state.scrollX),
                        textOffsets: textOffsets)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        let system = pass.frame.textSystem
        var state = TextEditState()
        pass.withState(id, initial: TextEditState()) { state = $0 }
        let geometry = geometry(bounds: bounds, state: state, system: system,
                                font: resolvedFont(in: pass.environment, system: system))
        // The scroll follows the caret. Written here, in the phase, as
        // `ScrollChrome` writes its clamped offset back: it is a function of
        // the caret and the width, so it converges in one frame and writes
        // nothing after.
        if geometry.scrollX != state.scrollX {
            pass.withState(id, initial: TextEditState()) { $0.scrollX = geometry.scrollX }
        }
        let offset = pass.frame.activeOffset
        let originX = geometry.contentX - geometry.scrollX + Double(offset.x.value)
        let caretX = originX + geometry.offsets[geometry.caretIndex]
        var handlers = self.handlers
        handlers.isFocusable = true
        handlers.textInput = TextInputTarget(
            text: text, caretOffsets: geometry.textOffsets, originX: originX,
            caretRect: pass.frame.effectBoundingBox(   // under render effects (`GX-I`)
                of: Bounds(origin: Point(x: Pixels(Float(caretX)),
                                         y: Pixels(Float(geometry.lineY + Double(offset.y.value)))),
                           size: Size(width: Pixels(1), height: Pixels(Float(geometry.lineHeight)))),
                ownEffects: decoration.renderEffects, bounds: bounds),
            onChange: onChange, onSubmit: submit)
        if handlers.axNode.isEmpty {
            handlers.axNode = AXNode(role: .textField, label: placeholder.isEmpty ? nil : placeholder, value: text)
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
        let font = resolvedFont(in: pass.environment, system: system)
        var state = TextEditState()
        pass.withState(id, initial: TextEditState()) { state = $0 }
        let g = geometry(bounds: bounds, state: state, system: system, font: font)
        let focused = pass.isFocused(id)
        let textColor = pass.theme[foregroundColor ?? .textPrimary]
        let x0 = g.contentX - g.scrollX
        func rect(_ from: Double, _ to: Double, y: Double, height: Double) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(x0 + from)), y: Pixels(Float(y))),
                   size: Size(width: Pixels(Float(max(0, to - from))), height: Pixels(Float(height))))
        }
        pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            if !g.selection.isEmpty {
                var selectionColor = pass.theme[.accent]
                selectionColor.a *= 0.3
                pass.fill(rect(g.offsets[g.selection.lowerBound], g.offsets[g.selection.upperBound],
                               y: g.lineY, height: g.lineHeight), color: selectionColor)
            }
            let showsPlaceholder = g.display.isEmpty
            var color = textColor
            if showsPlaceholder { color.a *= 0.45 }
            for glyph in system.placeGlyphs(showsPlaceholder ? placeholder : g.display, font: font,
                                            wrappingAt: nil, origin: (x: x0, y: g.lineY),
                                            scaleFactor: pass.scaleFactor) {
                pass.draw(glyph, color: color)
            }
            if let marked = g.composition {
                pass.fill(rect(g.offsets[marked.lowerBound], g.offsets[marked.upperBound],
                               y: g.lineY + g.lineHeight - 1, height: 1), color: textColor)
            }
            if focused && g.selection.isEmpty {
                let caret = g.offsets[g.caretIndex]
                pass.fill(rect(caret, caret + 1, y: g.lineY, height: g.lineHeight), color: textColor)
            }
        }
    }
}
