import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// SwiftUI's `SecureField` (rulings `SF-A`…`SF-H`): a one-line field for text that must not show — a password. It is
/// ``TextField``'s editor, chrome, binding and focus, with the text replaced by one bullet `•` (U+2022) per grapheme
/// wherever it would be drawn, measured or published.
///
/// ```swift
/// @State var password = ""
/// … SecureField("Password", text: $password, prompt: Text("Required"))
///     .onSubmit { connect() }
/// ```
///
/// - **Masking.** The field draws and measures bullets in its font, and the caret and the selection map onto them
///   one to one by grapheme. The real text reaches the binding and the edit state only: never the text system's
///   shaping and caches, the scene's glyph runs, or the accessibility tree.
/// - **Clipboard.** Copy and Cut do nothing (the shortcuts are claimed and write nothing, the macOS Edit menu's items
///   are disabled); Paste inserts; undo and redo work as in a `TextField`. Word movement and double-click see the text
///   as one word.
/// - **No input method.** Marked text and composition are ignored; committed text and dead keys type as characters.
///   There is no autocorrect, spell checking or text replacement (MetalUI has none in any field).
/// - **Secure keyboard entry (macOS).** While the field is focused in a key window the process has Carbon's secure
///   event input on; it is released when focus leaves, the window resigns key or closes, or the field is removed.
///   SDL has no equivalent and does nothing.
/// - **Accessibility.** AppKit publishes `AXTextField` with subrole `AXSecureTextField`, AccessKit `PASSWORD_INPUT`;
///   the value is the bullets, never the text.
///
/// The chrome, `.textFieldStyle(_:)`, `.disabled(_:)`, focus and `onSubmit` are the `TextField`'s. A `SecureField` has
/// no `axis:` and no selection binding.
public struct SecureField: Element, StyledElement {
    var field: TextField

    public var style: Style {
        get { field.style }
        set { field.style = newValue }
    }
    public var decoration: Decoration {
        get { field.decoration }
        set { field.decoration = newValue }
    }
    public var elementID: ElementID? {
        get { field.elementID }
        set { field.elementID = newValue }
    }
    public var handlers: Handlers {
        get { field.handlers }
        set { field.handlers = newValue }
    }

    /// Bound to `text` (SwiftUI's `SecureField(_:text:)`): shows a bullet per grapheme of `text.wrappedValue` and writes
    /// every edit, the real text, back through the binding. `title` is the placeholder, shown while the text is empty.
    ///
    /// ```swift
    /// SecureField("Password", text: $password)
    /// ```
    public init(_ title: String, text: Binding<String>) {
        field = TextField(title, text: text)
        field.isSecure = true
    }

    /// SwiftUI's `SecureField(_:text:prompt:)`: `prompt`'s plain string is the placeholder and its style its colour, as
    /// `TextField(_:text:prompt:)` does (`VT-J`); a `nil` prompt shows `title`.
    public init(_ title: String, text: Binding<String>, prompt: Text?) {
        field = TextField(title, text: text, prompt: prompt)
        field.isSecure = true
    }

    /// SwiftUI's `SecureField(text:prompt:label:)` with a `Text` label: the label's string is the title, shown as the
    /// placeholder when `prompt` is `nil` and the field's accessible name otherwise, as `SecureField(_:text:prompt:)`'s.
    public init(text: Binding<String>, prompt: Text? = nil, label: () -> Text) {
        self.init(label().string, text: text, prompt: prompt)
    }

    /// Sets the field's own font by family and size; `nil` family is the system font.
    public func font(family: String? = nil, size: Double) -> SecureField {
        var copy = self
        copy.field = field.font(family: family, size: size)
        return copy
    }

    /// This field's own bullet colour, `nil` to inherit — `TextField.foregroundColor(_:)`.
    public func foregroundColor(_ color: Color?) -> SecureField {
        var copy = self
        copy.field = field.foregroundColor(color)
        return copy
    }

    /// Sets the bullets' colour, the `ColorToken` spelling.
    @_disfavoredOverload
    public func foregroundColor(_ token: ColorToken) -> SecureField {
        foregroundColor(Color(token))
    }

    /// Draws this field in `style` — `TextField.textFieldStyle(_:)`.
    public func textFieldStyle(_ style: TextFieldStyle) -> SecureField {
        var copy = self
        copy.field = field.textFieldStyle(style)
        return copy
    }

    /// Runs on return; without it return is not claimed and keeps bubbling — `TextField.onSubmit(_:)`.
    public func onSubmit(_ action: @escaping @MainActor () -> Void) -> SecureField {
        var copy = self
        copy.field = field.onSubmit(action)
        return copy
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, TextField.Layout) {
        field.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout TextField.Layout, pass: inout PrepaintPass) {
        field.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout TextField.Layout, prepaint: inout Void,
                               pass: inout PaintPass) {
        field.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
