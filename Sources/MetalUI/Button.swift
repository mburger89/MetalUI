import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// SwiftUI's `Button` (ruling `DD-R`; spec
/// `docs/superpowers/specs/2026-09-26-controls-and-selection-design.md` §3–§5):
/// an action and a label, drawn in the automatic (bordered) chrome.
///
/// **A `Button` is an `onClick` plus focusability, keyboard activation and the
/// chrome** (`DD-R` item 2). `onClick` on any `StyledElement` stays what it is
/// — the click primitive, with Button semantics (a press may leave and return;
/// SwiftUI's `onTapGesture`, which fails on a move, is `onTapGesture(count:perform:)`,
/// plan task 12 part 1, `IX-D` item 2) — and is not deprecated; a
/// plain-looking button today is `.onClick` on the label itself.
/// **A caller's `.onClick` on a `Button` replaces its action** (the one-field
/// rule, `Handlers.onClick`'s doc), and the activation keys run whatever the
/// click runs. **A caller's `.onKey` runs first** and can claim a key; the
/// button's activation runs only if it declined.
///
/// **Structure.** An internal legacy `Box` row — the label, then a zero-width
/// **strut** `Box` whose height is declared — built in `requestLayout` from the
/// caller's own style, decoration and handlers and forwarded through the other
/// two phases, as `List` does with its `box`. No item field (`minSize`,
/// `flexGrow`, …) is written on an internal node: under a proposal parent a
/// record of one would be reported `…unconsumed` and trap in production
/// (`LR-AQ`), so the height is the strut's declared size. The label numbers
/// from 0 under the button's own id; the strut follows it.
///
/// **Chrome** (BT0): the label centred, horizontal padding and strut height
/// from `controlSize` (`DD-R` item 4 — 8/13, 10/20, 12/24, 14/28, 18/36 for
/// mini…extraLarge, BT4 − BT5 halved), corner radius 5, `.surfaceSecondary`
/// fill, a 1-point `.separator` border. `Button("Go")` is `textW + 24` ×
/// `max(textH, 24)` at the default size. **The label's default font follows
/// `controlSize` too** — 9/11/13 pt, because the label is a `Text` and a
/// `Text`'s default font reads it (ruling TE-F item 3, withdrawing `DD-R` item
/// 4's "its label's font does not"; probe F8, Z3). No pressed, hover or focus
/// look (task 12).
///
/// **Accessibility needs no declaration**: a clickable generic node is already
/// a button that folds its label (`AB-G`; BA0, BA2).
public struct Button<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var action: @MainActor () -> Void
    private var box: Box<Pair<Label, Box<EmptyGroup>>>
    /// The role (`IX-E` item 1): stored and read by nothing.
    private(set) var role: ButtonRole?
    private var buttonStyleValue: ButtonStyle = .automatic
    private var shortcut: KeyboardShortcut?

    public init(action: @escaping @MainActor () -> Void, @ElementBuilder label: () -> Label) {
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.justifyContent = .center
        self.style = style
        self.decoration = Decoration(background: .surfaceSecondary, cornerRadius: Pixels(5),
                                     border: BorderStyle(.separator, width: Pixels(1)))
        self.action = action
        self.box = Box(style: style, decoration: decoration, content: Pair(label(), Box()))
    }

    /// The chrome's horizontal padding and strut height for `size` (`DD-R`
    /// item 4; BT4 − BT5, halved).
    static func metrics(_ size: ControlSize) -> (padding: Float, height: Float) {
        switch size {
        case .mini: (8, 13)
        case .small: (10, 20)
        case .regular: (12, 24)
        case .large: (14, 28)
        case .extraLarge: (18, 36)
        }
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Label, Box<EmptyGroup>>>.Layout) {
        let metrics = Self.metrics(pass.environment.controlSize)
        var chrome = style
        chrome.padding.left = .pixels(Pixels(metrics.padding))
        chrome.padding.right = .pixels(Pixels(metrics.padding))
        var strut = Style()
        strut.size = Size(width: .length(.pixels(Pixels(0))), height: .length(.pixels(Pixels(metrics.height))))
        box.style = chrome
        box.decoration = decoration
        box.content.second = Box(style: strut)
        return box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Label, Box<EmptyGroup>>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Label, Box<EmptyGroup>>.Prepaint {
        var composed = handlers
        let activate = composed.onClick ?? action
        composed.onClick = activate
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard ControlKeys.activatesButton(event) else { return false }
            activate()
            return true
        }
        box.handlers = composed
        return box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Label, Box<EmptyGroup>>>.Layout,
                               prepaint: inout Pair<Label, Box<EmptyGroup>>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Button {
    /// A button with a role (SwiftUI's `Button(role:action:label:)`, `IX-E`
    /// item 1). The role binds no key and changes nothing drawn (`B4c`, `B4d`,
    /// `B5`).
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void,
                @ElementBuilder label: () -> Label) {
        self.init(action: action, label: label)
        self.role = role
    }

    /// This button drawn in `style` — SwiftUI's `.buttonStyle(_:)` over a
    /// closed set (`IX-E` item 2). `.plain` and `.borderless` drop the chrome's
    /// fill, border and corner radius **where they are still the chrome's
    /// own**, so a caller's `.background` written before or after survives,
    /// and draw the label at its own size; `.bordered`/`.automatic` restore the
    /// chrome's fields the same way.
    public func buttonStyle(_ style: ButtonStyle) -> Self {
        var copy = self
        copy.buttonStyleValue = style
        return copy
    }

    /// Runs this button's action when `key` is pressed with exactly
    /// `modifiers` — SwiftUI's `.keyboardShortcut(_:modifiers:)` (`IX-F`).
    /// Focus is not needed; the first button in tree order wins a shared
    /// shortcut; a focused element's own key handler, a keymap binding and a
    /// focused field's editing keys claim the key first; a disabled button's is
    /// silent and a hit-testing-off or invisible one's still fires.
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> Self {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }

    /// `keyboardShortcut(_:modifiers:)` with a whole shortcut, such as
    /// `.defaultAction` (Return) or `.cancelAction` (Escape).
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> Self {
        var copy = self
        copy.shortcut = shortcut
        return copy
    }

    /// `keyboardShortcut(_:)` that removes the shortcut when `nil`.
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> Self {
        var copy = self
        copy.shortcut = shortcut
        return copy
    }
}

extension Button where Label == Text {
    /// A button labelled by `title` (SwiftUI's `Button(_:action:)`).
    public init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }

    /// A button labelled by `title` with a role (SwiftUI's
    /// `Button(_:role:action:)`, `IX-E` item 1).
    public init(_ title: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}
