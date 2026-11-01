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
/// 4's "its label's font does not"; probe F8, Z3).
///
/// **Plan task 12 part 1, lane 2** (`IX-E`–`IX-H`): a role (stored, read by
/// nothing), `.buttonStyle(_:)` (`.plain`/`.borderless` are the label alone; any ``ButtonStyle`` or
/// ``PrimitiveButtonStyle``, inherited through the environment, `BY-A`),
/// a pressed look (`isActive && isHovered`), `.keyboardShortcut`, the disabled
/// look (one 0.5 opacity scope) and a 2-point focus ring in the key accent. No
/// hover look.
///
/// **Accessibility needs no declaration**: a clickable generic node is already
/// a button that folds its label (`AB-G`; BA0, BA2).
public struct Button<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    var action: @MainActor () -> Void
    var box: Box<Pair<Label, Box<EmptyGroup>>>
    /// The label, which a custom style takes into its body (`BY-A`).
    var label: Label { box.content.first }
    /// The role (`IX-E` item 1): stored, and handed to a style's configuration.
    private(set) var role: ButtonRole?
    /// This button's own style (`.buttonStyle(_:)` directly on a `Button`), nearer than the environment's.
    var ownStyle: ResolvedButtonStyle?
    var shortcut: KeyboardShortcut?

    /// A button that runs `action` when pressed (a click, Space or Return when
    /// focused, or an accessibility press), drawn around `label` with the
    /// automatic chrome. SwiftUI's `Button(action:label:)` (`DD-R`).
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

    /// The bordered chrome's decoration fields, which `.plain`/`.borderless`
    /// drop where they are still the chrome's own (`IX-E` item 2).
    static var chromeBackground: ColorToken { .surfaceSecondary }
    static var chromeCornerRadius: Pixels { Pixels(5) }
    static var chromeBorder: BorderStyle { BorderStyle(.separator, width: Pixels(1)) }

    /// What `requestLayout` hands the later phases: the built-in chrome's box layout, or a custom style's erased
    /// body (`BY-A`).
    public struct Layout {
        enum Inner {
            /// The built-in chrome, with the environment its label is drawn in (`BY-G`: white or accent), if any.
            case chrome(Box<Pair<Label, Box<EmptyGroup>>>.Layout, EnvironmentValues?, ButtonLook)
            /// A custom style's body: the erased element, its node, whether `isPressed` was true at layout, and
            /// whether the style reads `isPressed` at all.
            case custom(AnyElement, LayoutNodeID, pressed: Bool, readsPressed: Bool)
        }
        var inner: Inner
    }

    /// What `prepaint` hands `paint`.
    public struct PrepaintState {
        enum Inner {
            case chrome(Pair<Label, Box<EmptyGroup>>.Prepaint)
            case custom
        }
        var inner: Inner
    }

    /// The handlers a button registers: the caller's, with the click, the activation keys and the shortcut the
    /// button adds (`DD-R` item 2, `IX-F`). A primitive style registers its own click (`BY-B`).
    func composedHandlers(primitive: Bool) -> Handlers {
        var composed = handlers
        let activate = composed.onClick ?? action
        if !primitive { composed.onClick = activate }
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard ControlKeys.activatesButton(event) else { return false }
            activate()
            return true
        }
        // The shortcut runs whatever a click runs (`IX-F`); it rides the focus
        // registry, behind the one disabled gate.
        composed.keyboardShortcut = shortcut.map { ShortcutTarget($0, action: activate) }
        return composed
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        let environment = pass.environment
        let resolved = ownStyle ?? environment.buttonStyle
        switch resolved.storage {
        case .look(let look):
            return requestChromeLayout(id, look: look, environment: environment, pass: &pass)
        case .button(let custom):
            return requestCustomLayout(id, style: custom, environment: environment, pass: &pass)
        case .primitive(let custom):
            return requestCustomLayout(id, primitive: custom, environment: environment, pass: &pass)
        }
    }

    private mutating func requestChromeLayout(_ id: GlobalElementID, look: ButtonLook,
                                              environment: EnvironmentValues, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        let bordered = look.isBordered
        let glassStyle = look.glass
        let metrics = Self.metrics(environment.controlSize)
        var chrome = style
        var decorated = decoration
        var strut = Style()
        if bordered || glassStyle != nil {
            chrome.padding.left = .pixels(Pixels(metrics.padding))
            chrome.padding.right = .pixels(Pixels(metrics.padding))
            strut.size = Size(width: .length(.pixels(Pixels(0))), height: .length(.pixels(Pixels(metrics.height))))
        } else {
            // `.plain`/`.borderless` (BT1): the label alone at its own size. The
            // strut stays, zero by zero, so the label keeps index 0 and the
            // strut 1 in every style. A chrome field a caller has not replaced
            // is dropped; a caller's own fill or border survives.
            strut.size = Size(width: .length(.pixels(Pixels(0))), height: .length(.pixels(Pixels(0))))
            dropChrome(&decorated)
        }
        if look == .borderedProminent {
            // The accent fill and no border (`BY-G`); a caller's own fill survives.
            if decorated.background == Color(Self.chromeBackground) { decorated.background = Color(controlAccent(environment)) }
            if decorated.border == Self.chromeBorder { decorated.border = nil }
        }
        if let glassStyle {
            // `.glass` / `.glassProminent` (`LG-M`): the bordered metrics with the chrome's fill, border and radius
            // swapped for a capsule glass, unless the caller wrote a glass or fill of their own.
            if decorated.background == Color(Self.chromeBackground) { decorated.background = nil }
            if decorated.border == Self.chromeBorder { decorated.border = nil }
            decorated.cornerRadius = Pixels(metrics.height / 2)
            if decorated.backgroundGlass == nil { decorated.backgroundGlass = GlassBox(glassStyle, Capsule()) }
        }
        // The focus ring (`IX-H` item 2), unless the caller declared one.
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(environment) }
        box.style = chrome
        box.decoration = decorated
        box.content.second = Box(style: strut)
        // The label's forced colour (`.borderedProminent` white, `.link` accent), unless a Text names its own.
        var labelEnvironment: EnvironmentValues?
        if let color = look.labelColor {
            var values = pass.frame.environmentSnapshot()
            values.foregroundStyle = color
            labelEnvironment = values
        }
        let (node, layout) = Self.enteringLabel(labelEnvironment, pass.frame) { box.requestLayout(id, pass: &pass) }
        return (node, Layout(inner: .chrome(layout, labelEnvironment, look)))
    }

    /// Drops the chrome fields a caller has not replaced (`IX-E` item 2).
    private func dropChrome(_ decorated: inout Decoration) {
        if decorated.background == Color(Self.chromeBackground) { decorated.background = nil }
        if decorated.cornerRadius == Self.chromeCornerRadius { decorated.cornerRadius = Pixels(0) }
        if decorated.border == Self.chromeBorder { decorated.border = nil }
    }

    static func enteringLabel<R>(_ values: EnvironmentValues?, _ frame: Frame, _ body: () -> R) -> R {
        guard let values else { return body() }
        return frame.withEnvironment(values, body)
    }

    private mutating func requestCustomLayout<S: ButtonStyle>(_ id: GlobalElementID, style custom: S,
                                                             environment: EnvironmentValues,
                                                             pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let pressed = pass.frame.activeElement == id && pass.frame.pointerOwner == id   // `BY-D`
        StateBinder.bind(custom, in: pass.frame, id: id)   // `@State`/`@Environment` on the style struct (`BY-K`)
        let configuration = ButtonStyleConfiguration(role: role, label: StyleLabel(label), isPressed: pressed)
        return layOutCustom(id, body: custom.makeBody(configuration: configuration), primitive: false,
                            pressed: pressed, environment: environment, pass: &pass)
    }

    private mutating func requestCustomLayout<S: PrimitiveButtonStyle>(_ id: GlobalElementID, primitive custom: S,
                                                                      environment: EnvironmentValues,
                                                                      pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let trigger = handlers.onClick ?? action
        StateBinder.bind(custom, in: pass.frame, id: id)   // `BY-K`
        let configuration = PrimitiveButtonStyleConfiguration(role: role, label: StyleLabel(label), action: trigger)
        return layOutCustom(id, body: custom.makeBody(configuration: configuration), primitive: true,
                            pressed: false, environment: environment, pass: &pass)
    }

    /// The custom path (`BY-A`): the style's body inside one `Box` that carries the button's handlers, focus ring
    /// and decoration, erased and laid out under the button's own id.
    private func layOutCustom<Body: ElementGroup>(_ id: GlobalElementID, body: Body, primitive: Bool, pressed: Bool,
                                                  environment: EnvironmentValues, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        var decorated = decoration
        dropChrome(&decorated)
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(environment) }
        var outer = Box(style: style, decoration: decorated, content: body)
        outer.handlers = composedHandlers(primitive: primitive)
        var element = AnyElement(outer)
        let node = element.requestLayout(id, pass: &pass)
        return (node, Layout(inner: .custom(element, node, pressed: pressed, readsPressed: !primitive)))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) -> PrepaintState {
        switch layout.inner {
        case .chrome(var chromeLayout, let labelEnvironment, let look):
            box.handlers = composedHandlers(primitive: false)
            let result = Self.enteringLabel(labelEnvironment, pass.frame) {
                box.prepaint(id, bounds: bounds, layout: &chromeLayout, pass: &pass)
            }
            layout.inner = .chrome(chromeLayout, labelEnvironment, look)
            return PrepaintState(inner: .chrome(result))
        case .custom(var element, let node, let pressed, let readsPressed):
            element.prepaint(id, bounds: bounds, pass: &pass)
            layout.inner = .custom(element, node, pressed: pressed, readsPressed: readsPressed)
            return PrepaintState(inner: .custom)
        }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout PrepaintState,
                               pass: inout PaintPass) {
        // Pressed is SwiftUI's rule (B0–B3): pressed and over the button —
        // `isActive && isHovered`, both paint-only (`IX-E` item 3). The looks
        // are MetalUI's (PX21/PX22 blind): a `.textPrimary` wash at 12 % over
        // the bordered chrome; the label at 60 % for `.plain`/`.borderless`.
        let pressed = pass.isActive(id) && pass.isHovered(id)
        switch layout.inner {
        case .chrome(var chromeLayout, let labelEnvironment, let look):
            guard case .chrome(var chromePrepaint) = prepaint.inner else { return }
            let bordered = look.isBordered
            // A glass button lifts its own tint while pressed (`LG-J`) and neither dims nor washes.
            let isGlass = look.isGlass
            let radius = box.decoration.cornerRadius
            pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
                if pressed && !bordered && !isGlass {
                    pass.opacity(0.6) {
                        Self.enteringLabel(labelEnvironment, pass.frame) {
                            box.paint(id, bounds: bounds, layout: &chromeLayout, prepaint: &chromePrepaint, pass: &pass)
                        }
                    }
                } else {
                    Self.enteringLabel(labelEnvironment, pass.frame) {
                        box.paint(id, bounds: bounds, layout: &chromeLayout, prepaint: &chromePrepaint, pass: &pass)
                    }
                }
                if pressed && bordered {
                    pass.opacity(0.12) {
                        pass.fill(bounds, color: pass.theme[.textPrimary], cornerRadii: Corners(all: radius))
                    }
                }
            }
            layout.inner = .chrome(chromeLayout, labelEnvironment, look)
        case .custom(var element, let node, let atLayout, let readsPressed):
            pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
                element.paint(id, bounds: bounds, pass: &pass)
            }
            layout.inner = .custom(element, node, pressed: atLayout, readsPressed: readsPressed)
            // The body read `isPressed` from the previous frame's hitboxes (`BY-D`); when paint's resolved answer
            // differs (the layout under the pointer moved), one more frame brings the body up to date.
            if readsPressed && pressed != atLayout { pass.requestAnotherFrame() }
        }
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

    /// This button drawn in `style` — SwiftUI's `.buttonStyle(_:)` (`IX-E` item 2, opened by `BY-A`). The nearest
    /// writer: it outranks a style inherited through the environment. `.plain` and `.borderless` draw the label at
    /// its own size (BT1) and drop the chrome's fill, border and corner radius **where they are still the chrome's
    /// own** — decided at layout, so a caller's `.background` written before or after `.buttonStyle` survives (a
    /// caller who writes the chrome's own `.surfaceSecondary` explicitly cannot be told from the chrome, and loses
    /// it under `.plain`).
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> Self {
        var copy = self
        copy.ownStyle = ResolvedButtonStyle(style)
        return copy
    }

    /// `buttonStyle(_:)` for a custom ``ButtonStyle``.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> Self {
        var copy = self
        copy.ownStyle = ResolvedButtonStyle(style)
        return copy
    }

    /// Runs this button's action when `key` is pressed with exactly
    /// `modifiers` — SwiftUI's `.keyboardShortcut(_:modifiers:)` (`IX-F`).
    /// Focus is not needed; the first button in tree order wins a shared
    /// shortcut; a focused element's own key handler, a keymap binding and a
    /// focused field's editing keys claim the key first; a disabled button's is
    /// silent and a hit-testing-off or invisible one's still fires. `modifiers`
    /// defaults to `.primary` — ⌘ on macOS (SwiftUI's `.command`), Ctrl on
    /// Linux and Windows (ruling `SG-B` item 3).
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .primary) -> Self {
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
