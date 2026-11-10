import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// A single line of editable text (roadmap item 14, rulings TI-B…TI-D), or with `axis: .vertical` a field that
/// grows with its text between the bounds `lineLimit` sets and scrolls inside itself past the upper one (`VT-`).
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
///
/// **Drawn as SwiftUI's bordered field by default** (rulings `MD-C`…`MD-E`):
/// 6/4 points of inset (3.5 vertically at `.small`), a `.surface` fill, a
/// `.separator` border, corner radius 6 and the control focus ring — 24 points
/// tall at 13 pt. `.textFieldStyle(.plain)` draws the bare field, one line
/// tall. Disabled, the chrome stays and the text dims to a third.
///
/// **Vertical (`init(_:text:axis:)`, SwiftUI's `TextField(_:text:axis:)`, `VT-A`..`VT-H`).** `.lineLimit(1...8)` makes it
/// one line tall to eight, `.lineLimit(3...)` at least three; with no limit it grows without bound. It wraps at
/// its width, answers the height its lines need (a smaller proposal is answered as asked down to the lower
/// bound's height), keeps its caret in view as it scrolls and takes the wheel while focused and with room.
/// Return submits (`onSubmit`) and ⌥↩ or ⌃↩ (Alt+Enter off a Mac) inserts a line break. A horizontal field ignores `lineLimit`.
public struct TextField: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    /// Shown, dimmed, while `text` is empty.
    public var placeholder: String
    /// The placeholder's own colour, from a `prompt:` `Text`'s style (`VT-J`); `nil` is ``Color/secondary``, never the
    /// field's `foregroundColor`.
    var placeholderColor: Color?
    /// The text shown; the field never changes it itself.
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
    /// Called when Return is pressed in the field, if set.
    public var submit: (@MainActor () -> Void)?
    /// The text's own colour; `nil` inherits the foreground style.
    public var foregroundColor: Color?
    /// The field's own font request (ruling TE-F item 2): inherit the
    /// environment's font, the default font, or an explicit one.
    var fontRequest: TextFontRequest = .inherit
    /// The field's own style (ruling `MD-B` item 2); `nil` reads the
    /// environment's, `.automatic` by default.
    var fieldStyle: TextFieldStyle?
    /// The axis the text grows along (`VT-A`); `.horizontal`, the default, is the one-line field.
    var axis: Axis = .horizontal
    /// The field's own `lineLimit`, which wins over the environment's (`VT-C`); `nil` reads the environment.
    var ownLineLimit: TextLineLimit?

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

    /// A controlled field that grows along `axis` (SwiftUI's `TextField(_:text:axis:)`, `VT-A`): `.vertical` wraps its
    /// text at its width and is as tall as its lines between the `lineLimit` bounds, scrolling inside past the upper one.
    public init(_ placeholder: String, text: String, axis: Axis,
                onChange: @escaping @MainActor (String) -> Void) {
        self.init(placeholder, text: text, onChange: onChange)
        self.axis = axis
    }

    /// Bound to `text`, growing along `axis` (SwiftUI's `TextField(_:text:axis:)`, `VT-A`): the vertical field a chat
    /// composer is, one line tall to the `lineLimit` upper bound and scrolling inside past it.
    ///
    /// ```swift
    /// TextField("Message", text: $draft, axis: .vertical).lineLimit(1...8)
    /// ```
    public init(_ placeholder: String, text: Binding<String>, axis: Axis) {
        self.init(placeholder, text: text)
        self.axis = axis
    }

    /// Bound to `text` and to a `TextSelection`, growing along `axis` (`VT-A`); the selection binding is
    /// `init(_:text:selection:)`'s.
    @available(macOS 15, *)
    public init(_ placeholder: String, text: Binding<String>, selection: Binding<TextSelection?>, axis: Axis) {
        self.init(placeholder, text: text, selection: selection)
        self.axis = axis
    }

    /// Bound to `text` and to the selection as Character offsets, growing along `axis` — MetalUI-only, as
    /// `init(_:text:selectedOffsets:)` is (`VT-A`, `SL-Q`).
    public init(_ placeholder: String, text: Binding<String>, selectedOffsets: Binding<Range<Int>?>, axis: Axis) {
        self.init(placeholder, text: text, selectedOffsets: selectedOffsets)
        self.axis = axis
    }

    /// SwiftUI's `TextField(_:text:prompt:)` (`VT-J`): `prompt`'s plain string is the placeholder and its style, a flat colour or a
    /// hierarchical level (a gradient lowers to its first stop), is the placeholder's colour; the field's text stays plain
    /// (`TM-H`). A `nil` prompt shows `title`, in the default placeholder colour.
    ///
    /// ```swift
    /// TextField("Name", text: $name, prompt: Text("Your name").foregroundStyle(.tertiary))
    /// ```
    public init(_ title: String, text: Binding<String>, prompt: Text?) {
        self.init(title, text: text)
        applyPrompt(prompt)
    }

    /// `TextField(_:text:prompt:axis:)` (`VT-J`): a growing field with a `prompt`.
    public init(_ title: String, text: Binding<String>, prompt: Text?, axis: Axis) {
        self.init(title, text: text, axis: axis)
        applyPrompt(prompt)
    }

    /// `TextField(_:text:selection:prompt:)` (`VT-J`): `init(_:text:selection:)` with a `prompt`.
    @available(macOS 15, *)
    public init(_ title: String, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text?) {
        self.init(title, text: text, selection: selection)
        applyPrompt(prompt)
    }

    /// `TextField(_:text:selection:prompt:axis:)` (`VT-J`): a growing field with a selection binding and a `prompt`.
    @available(macOS 15, *)
    public init(_ title: String, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text?, axis: Axis) {
        self.init(title, text: text, selection: selection, axis: axis)
        applyPrompt(prompt)
    }

    private mutating func applyPrompt(_ prompt: Text?) {
        guard let prompt else { return }
        placeholder = prompt.string
        placeholderColor = prompt.foregroundColor
    }

    /// Bound to `text` and to a `TextSelection` (SwiftUI's
    /// `TextField(_:text:selection:)`, rulings `SL-A`, `SL-B`): the field writes the
    /// selection to `selection` after each input that moved it, and applies a value
    /// written there on the next frame. A `nil` binding is the field's own
    /// selection. Both writes happen in input, never in a phase.
    @available(macOS 15, *)
    public init(_ placeholder: String, text: Binding<String>, selection: Binding<TextSelection?>) {
        self.init(placeholder, text: text.wrappedValue, selection: selection.wrappedValue,
                  onChange: { text.wrappedValue = $0 },
                  onSelectionChange: { selection.wrappedValue = $0 })
    }

    /// Bound to `text` and to the selection as Character offsets into it — MetalUI-only
    /// (ruling `SL-Q`), and **not** macOS 15: `TextSelection` is `RangeSet`'s, which the
    /// standard library has from macOS 15, while this spelling is plain `Range<Int>` and
    /// runs on macOS 14. The offsets are `Character` (grapheme) positions in the current
    /// `text`; empty is the caret. It behaves as the `TextSelection` binding does
    /// (`SL-B`..`SL-J`): the field writes it after each input that moved the selection and
    /// applies a value written there on the next frame, a `nil` is the field's own
    /// selection, a stale range clamps into the text. Both writes happen in input, never in
    /// a phase. Insert at the caret by editing `text` and writing the caret after the
    /// insertion: `text.insert(contentsOf: s, at: i); caret = (i + s.count)..<(i + s.count)`.
    public init(_ placeholder: String, text: Binding<String>, selectedOffsets: Binding<Range<Int>?>) {
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

    /// Sets the field's own font by family and size; `nil` family is the system
    /// font.
    public func font(family: String? = nil, size: Double) -> TextField {
        var copy = self
        copy.fontRequest = .legacy(family: family, size: size)
        return copy
    }

    /// This text's own colour, `nil` to inherit — SwiftUI's
    /// `foregroundColor(_:)` with its optional (`CR-E` item 4).
    public func foregroundColor(_ color: Color?) -> TextField {
        var copy = self
        copy.foregroundColor = color
        return copy
    }

    /// Sets the text's colour.
    /// The `ColorToken` spelling, kept (`CR-E` item 1).
    @_disfavoredOverload
    public func foregroundColor(_ token: ColorToken) -> TextField {
        foregroundColor(Color(token))
    }

    /// Draws this field in `style` — SwiftUI's `textFieldStyle(_:)` written on
    /// the field (ruling `MD-B` item 2). It wins over a container's style, and
    /// returns a `TextField`, so `.background`, `.frame` and `.onSubmit` still
    /// chain (`PE-R`).
    public func textFieldStyle(_ style: TextFieldStyle) -> TextField {
        var copy = self
        copy.fieldStyle = style
        return copy
    }

    /// At most `number` lines (`nil`: no limit) — `lineLimit(_:)` written on the field (`VT-C`), as
    /// `textFieldStyle(_:)` is: it wins over a container's and returns a `TextField`, so `.onSubmit` still
    /// chains. Only a vertical field reads it.
    public func lineLimit(_ number: Int?) -> TextField {
        var copy = self
        copy.ownLineLimit = TextLineLimit(min: nil, max: number)
        return copy
    }

    /// At most `limit` lines; with `reservesSpace`, always `limit` lines tall (`VT-C`).
    public func lineLimit(_ limit: Int, reservesSpace: Bool) -> TextField {
        var copy = self
        copy.ownLineLimit = TextLineLimit(min: reservesSpace ? limit : nil, max: limit)
        return copy
    }

    /// Between `limit`'s bounds: at least the lower bound's height, at most the upper's (`VT-C`).
    public func lineLimit(_ limit: ClosedRange<Int>) -> TextField {
        var copy = self
        copy.ownLineLimit = TextLineLimit(min: limit.lowerBound, max: limit.upperBound)
        return copy
    }

    /// At least `limit.lowerBound` lines tall, no upper bound (`VT-C`).
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> TextField {
        var copy = self
        copy.ownLineLimit = TextLineLimit(min: limit.lowerBound, max: nil)
        return copy
    }

    /// At most `limit.upperBound` lines (`VT-C`).
    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> TextField {
        var copy = self
        copy.ownLineLimit = TextLineLimit(min: nil, max: limit.upperBound)
        return copy
    }

    /// Whether this field grows along the vertical axis (`VT-A`).
    var isVertical: Bool { axis == .vertical }

    /// The style this field draws in: its own, else the environment's
    /// (`MD-B` item 2).
    func resolvedStyle(in environment: EnvironmentValues) -> TextFieldStyle {
        fieldStyle ?? environment.textFieldStyle
    }

    /// The chrome's content insets in `environment` (`MD-D`): 6 by 4 (3.5 at
    /// `.small`) for a bordered style, none for `.plain`.
    func chromeInsets(in environment: EnvironmentValues) -> (horizontal: Double, vertical: Double) {
        FieldChrome.insets(resolvedStyle(in: environment), environment.controlSize)
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
        let insets = chromeInsets(in: pass.environment)
        // Greedy on the width, as SwiftUI's `TextField` is; one line tall plus
        // the chrome's vertical insets (`MD-D`). Any offered width is taken
        // whole — the chrome is inside it — and an infinite one answers infinity
        // (ruling `PE-D`, probe FL3/FL4 `inf -> infx24`), so a stack, which
        // orders its children by their answer at ∞ (`CN-B`), serves the field
        // after its hugging siblings; `nil` asks for the ideal, the text's
        // natural width plus the chrome's horizontal insets (`SZ`: text + 12).
        let vertical = isVertical
        let limit = ownLineLimit ?? pass.environment.textLineLimit
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .textField) {
            pass.frame.requestNativeLeaf { proposal in
                MainActor.assumeIsolated {
                    let width = proposal.width
                        ?? Self.naturalWidth(text: text, placeholder: placeholder, font: key, system: system)
                            + 2 * insets.horizontal
                    let lineHeight = Self.lineHeight(font: key, system: system)
                    guard vertical else {
                        return LayoutMeasurement(size: SizeD(width: width, height: lineHeight + 2 * insets.vertical))
                    }
                    // A vertical field (`VT-B`): the lines it wraps into at the width it is given (unwrapped at nil or
                    // infinity), between the `lineLimit` bounds.
                    let lines = VerticalFieldMetrics.displayLines(text: text, placeholder: placeholder,
                                                                  width: proposal.width, horizontalInset: insets.horizontal,
                                                                  font: key, system: system)
                    return LayoutMeasurement(size: SizeD(width: width,
                                                         height: VerticalFieldMetrics.height(
                                                            displayLines: lines, lineHeight: lineHeight,
                                                            verticalInset: insets.vertical, limit: limit,
                                                            proposal: proposal.height)))
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
        if isVertical {
            prepaintVertical(id, bounds: bounds, state: state, focused: focused, pass: &pass)
            return
        }
        // Text, caret and scroll are laid out in the chrome's content rect
        // (`MD-D` item 3); the hitbox, focus and accessibility keep `bounds`.
        let geometry = geometry(bounds: FieldChrome.contentRect(bounds, chromeInsets(in: pass.environment)),
                                state: state, system: system,
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
            onChange: onChange, onSubmit: submit,
            selectionSink: selectionWriter)
        // `DA-C`: fills what was not declared, so an identifier or hint written on the field
        // does not cost it its role and text.
        handlers.axNode.fillControl(role: .textField, label: placeholder.isEmpty ? nil : placeholder, value: text)
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    /// A vertical field's prepaint (`VT-D`): the editor's line model in the chrome's content rect, the scroll that
    /// keeps the caret in view written back compared (an unfocused field reads 0 and writes nothing), and a target
    /// that carries the lines, so the line keys, a press and the wheel read what is drawn.
    private func prepaintVertical(_ id: GlobalElementID, bounds: Bounds<Pixels>, state: TextEditState,
                                  focused: Bool, pass: inout PrepaintPass) {
        let system = pass.frame.textSystem
        let content = FieldChrome.contentRect(bounds, chromeInsets(in: pass.environment))
        let g = MultilineText.geometry(text: text, bounds: content, state: state, system: system,
                                       font: resolvedFont(in: pass.environment, system: system), focused: focused)
        if focused && (g.scrollY != state.scrollY || g.revealed) {
            pass.withState(id, initial: TextEditState(), unchanged: ==) {   // compared (`RW-J`)
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
        textLines.visibleHeight = Double(content.size.height.value)
        handlers.textInput = TextInputTarget(
            text: text, caretOffsets: [], originX: originX, caretRect: caretArea,
            onChange: onChange, onSubmit: submit, selectionSink: selectionWriter, lines: textLines, originY: originY,
            lineHeight: g.lineHeight, maxScrollY: g.maxScrollY, verticalField: true)
        // The role stays a text field (`VT-D`); `DA-C` as above.
        handlers.axNode.fillControl(role: .textField, label: placeholder.isEmpty ? nil : placeholder, value: text)
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
        let focused = pass.isFocused(id)
        guard resolvedStyle(in: pass.environment).isBordered else {
            paintText(id, bounds: bounds, pass: &pass)
            return
        }
        // The bordered chrome (`MD-E`): fill, border, the text inside, the ring.
        pass.paintFieldChrome(bounds: bounds, bordered: true, radius: FieldChrome.cornerRadius,
                              focused: focused, callerRing: decoration.focusBorder != nil) {
            paintText(id, bounds: bounds, pass: &pass)
        }
    }

    /// The text, selection, marked-text underline and caret, in the chrome's
    /// content rect (`MD-D` item 3) — unchanged text-input drawing (`TI-`).
    private func paintText(_ id: GlobalElementID, bounds outer: Bounds<Pixels>, pass: inout PaintPass) {
        if isVertical {
            paintVerticalText(id, bounds: outer, pass: &pass)
            return
        }
        let system = pass.textSystem
        let font = resolvedFont(in: pass.environment, system: system)
        let state = pass.readState(id, initial: TextEditState())   // a read, not a write (`RW-J`)
        let bounds = FieldChrome.contentRect(outer, chromeInsets(in: pass.environment))
        let g = geometry(bounds: bounds, state: state, system: system, font: font)
        let focused = pass.isFocused(id)
        var textColor = pass.resolve(foregroundColor ?? .textPrimary)
        // Disabled: the chrome stays, the text dims to a third (`MD-E` item 3) —
        // a bordered field only; a `.plain` field is the previous field exactly,
        // which took no disabled look (`MD-W` item 1).
        if !pass.environment.isEnabled && resolvedStyle(in: pass.environment).isBordered {
            textColor.a *= FieldChrome.disabledTextFactor
        }
        let dim = (!pass.environment.isEnabled && resolvedStyle(in: pass.environment).isBordered) ? FieldChrome.disabledTextFactor : 1
        let x0 = g.contentX - g.scrollX
        func rect(_ from: Double, _ to: Double, y: Double, height: Double) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(Float(x0 + from)), y: Pixels(Float(y))),
                   size: Size(width: Pixels(Float(max(0, to - from))), height: Pixels(Float(height))))
        }
        // Clipped to the content rect across, the whole field down — so a
        // glyph's ink above or below its line is not cut at the inset (pinned by
        // `aBorderedFieldClipsItsTextToTheContentWidthAndTheWholeHeight`).
        let clip = Bounds(origin: Point(x: bounds.origin.x, y: outer.origin.y),
                          size: Size(width: bounds.size.width, height: outer.size.height))
        pass.clipped(to: clip, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            if !g.selection.isEmpty {
                var selectionColor = pass.resolve(.accentColor)
                selectionColor.a *= 0.3
                pass.fill(rect(g.offsets[g.selection.lowerBound], g.offsets[g.selection.upperBound],
                               y: g.lineY, height: g.lineHeight), color: selectionColor)
            }
            let showsPlaceholder = g.display.isEmpty
            let color = showsPlaceholder ? MultilineText.placeholderColor(placeholderColor, in: pass.environment, dim: dim) : textColor
            pass.drawGlyphs(system.placeGlyphs(showsPlaceholder ? placeholder : g.display, font: font,
                                               wrappingAt: nil, origin: (x: x0, y: g.lineY),
                                               scaleFactor: pass.scaleFactor), color: color)
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

    /// A vertical field's lines in the chrome's content rect (`VT-D`): the editor's line loop, clipped across to the
    /// content width and down to the bounds inset by 2 points (the clip AppKit's field editor sits in, probe R), with no
    /// scroll indicator. Unfocused it draws from the top and keeps its stored scroll.
    private func paintVerticalText(_ id: GlobalElementID, bounds outer: Bounds<Pixels>, pass: inout PaintPass) {
        let system = pass.textSystem
        let font = resolvedFont(in: pass.environment, system: system)
        let state = pass.readState(id, initial: TextEditState())   // a read, not a write (`RW-J`)
        let insets = chromeInsets(in: pass.environment)
        let content = FieldChrome.contentRect(outer, insets)
        let focused = pass.isFocused(id)
        let g = MultilineText.geometry(text: text, bounds: content, state: state, system: system, font: font,
                                       focused: focused)
        var textColor = pass.resolve(foregroundColor ?? .textPrimary)
        if !pass.environment.isEnabled && resolvedStyle(in: pass.environment).isBordered {
            textColor.a *= FieldChrome.disabledTextFactor
        }
        let inset = Float(min(2, insets.vertical))
        let clip = Bounds(origin: Point(x: content.origin.x, y: Pixels(outer.origin.y.value + inset)),
                          size: Size(width: content.size.width,
                                     height: Pixels(max(0, outer.size.height.value - 2 * inset))))
        let dim = (!pass.environment.isEnabled && resolvedStyle(in: pass.environment).isBordered) ? FieldChrome.disabledTextFactor : 1
        MultilineText.paintLines(g, placeholder: placeholder, font: font, system: system, textColor: textColor,
                                 placeholderColor: MultilineText.placeholderColor(placeholderColor, in: pass.environment, dim: dim),
                                 wrapWidth: Double(content.size.width.value), clip: clip, cull: clip,
                                 focused: focused, pass: &pass)
    }
}
