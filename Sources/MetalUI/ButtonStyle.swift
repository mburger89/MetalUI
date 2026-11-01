import MetalUICore

/// SwiftUI's `ButtonRole` — the macOS 27 SDK's four (plan task 12 part 1,
/// ruling `IX-E` item 1).
///
/// **A role binds no key and changes nothing drawn** (probe
/// `swiftui-interaction.swift` `B4c`: a `.cancel` button alone ignores Escape;
/// `B4d`: a `.destructive` one ignores Return; `B5`: layout and clicks are the
/// role-less button's). SwiftUI's role *look* is unmeasured (the offscreen
/// capture draws no text) and MetalUI's theme has no destructive colour, so the
/// role is stored and read by nothing — a declared-but-inert row (its
/// accessibility reading is plan task 12 part 2's). A key is bound with
/// `.keyboardShortcut(.cancelAction)` / `.defaultAction`, as in SwiftUI.
public struct ButtonRole: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case destructive, cancel, confirm, close }
    let kind: Kind

    /// An action that deletes user data.
    public static let destructive = ButtonRole(kind: .destructive)
    /// An action that cancels an operation.
    public static let cancel = ButtonRole(kind: .cancel)
    /// An action that confirms an operation.
    public static let confirm = ButtonRole(kind: .confirm)
    /// An action that closes a presentation.
    public static let close = ButtonRole(kind: .close)
}

/// A button's look as SwiftUI's open protocol (ruling `BY-A`, superseding `IX-E` item 2's closed struct): `makeBody`
/// turns the ``ButtonStyleConfiguration`` — the label, whether the button is pressed, its role — into the button's
/// body. **Applied with `.buttonStyle(_:)` and inherited through the environment**, the nearest writer winning, on
/// any content (`Column { … }.buttonStyle(MyStyle())`) or on a `Button` itself.
///
/// The `Button` keeps the interaction: a click, a focused Space, an accessibility press and a keyboard shortcut run
/// its action once, the focus ring and the disabled look are drawn around the body, and `isPressed` follows the
/// pointer (`BY-C`, `BY-D`). A style that must own the interaction is a ``PrimitiveButtonStyle``.
///
/// ```swift
/// struct Capsule: ButtonStyle {
///     func makeBody(configuration: Configuration) -> some ElementGroup {
///         configuration.label.padding(8).background(configuration.isPressed ? Color.gray : Color.accent)
///     }
/// }
/// ```
///
/// **The built-ins are ``PrimitiveButtonStyle``s**, as SwiftUI's are (`.plain`, `.bordered`, …), so a custom
/// `ButtonStyle` cannot name them in its body; delegating to one draws the bare label.
@MainActor
public protocol ButtonStyle {
    /// The body's type, any element or group.
    associatedtype Body: ElementGroup

    /// The configuration `makeBody` receives.
    typealias Configuration = ButtonStyleConfiguration

    /// The button's body for `configuration`. Built at layout, every frame the button is laid out.
    @ElementBuilder func makeBody(configuration: Configuration) -> Body
}

/// A button style that owns the interaction (SwiftUI's `PrimitiveButtonStyle`, ruling `BY-B`): it receives
/// ``PrimitiveButtonStyleConfiguration/trigger()`` instead of an `isPressed` and decides what triggers the action
/// — typically `configuration.label.onClick { configuration.trigger() }`. The button's own click handler is **not**
/// registered, so a style that never calls `trigger()` runs nothing on a click; a focused Space and a keyboard
/// shortcut still run the action (`BY-C`).
@MainActor
public protocol PrimitiveButtonStyle {
    /// The body's type, any element or group.
    associatedtype Body: ElementGroup

    /// The configuration `makeBody` receives.
    typealias Configuration = PrimitiveButtonStyleConfiguration

    /// The button's body for `configuration`. Built at layout, every frame the button is laid out.
    @ElementBuilder func makeBody(configuration: Configuration) -> Body
}

/// The label a style's configuration hands its body: the button's or toggle's own label content, type-erased
/// (ruling `BY-E`; SwiftUI's is an opaque `Label`). It is a styled element, so `.padding`, `.background`,
/// `.onClick` and the other element modifiers apply to it. MetalUI-only name (SwiftUI nests an opaque `Label`).
public struct StyleLabel: Element, StyledElement {
    /// This label's own style, written by element modifiers.
    public var style: Style = Style()
    /// This label's own decoration, written by element modifiers.
    public var decoration: Decoration = Decoration()
    /// This label's local name among its siblings.
    public var elementID: ElementID?
    /// This label's own handlers, written by `.onClick` and the other handler modifiers.
    public var handlers: Handlers = Handlers()
    let make: @MainActor (Style, Decoration, Handlers) -> AnyElement

    init<L: ElementGroup>(_ label: L) {
        make = { style, decoration, handlers in
            var box = Box(style: style, decoration: decoration, content: label)
            box.handlers = handlers
            return AnyElement(box)
        }
    }

    /// What `requestLayout` hands the later phases: the erased element and its node.
    public struct Layout {
        var element: AnyElement
        var node: LayoutNodeID
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var element = make(style, decoration, handlers)
        let node = element.requestLayout(id, pass: &pass)
        return (node, Layout(element: element, node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) {
        layout.element.prepaint(id, bounds: bounds, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Void, pass: inout PaintPass) {
        layout.element.paint(id, bounds: bounds, pass: &pass)
    }
}

/// What a ``ButtonStyle`` receives (ruling `BY-A`): the label, whether the button is pressed and its role.
/// Constructed by `Button` only.
public struct ButtonStyleConfiguration {
    /// SwiftUI's nested `Label`.
    public typealias Label = StyleLabel

    /// The button's role, or `nil`. A role changes nothing drawn by itself (`IX-E` item 1); a style may read it.
    public let role: ButtonRole?
    /// The button's label content.
    public let label: Label
    /// Whether the pointer is pressed on the button **and** over it (SwiftUI's rule, probe `B0`–`B2`). Read at
    /// layout from the previous frame's hitboxes (`BY-D`).
    public let isPressed: Bool

    init(role: ButtonRole?, label: Label, isPressed: Bool) {
        self.role = role
        self.label = label
        self.isPressed = isPressed
    }
}

/// What a ``PrimitiveButtonStyle`` receives (ruling `BY-B`): the label, the role and `trigger()`.
/// Constructed by `Button` only.
public struct PrimitiveButtonStyleConfiguration {
    /// SwiftUI's nested `Label`.
    public typealias Label = StyleLabel

    /// The button's role, or `nil`.
    public let role: ButtonRole?
    /// The button's label content.
    public let label: Label
    let action: @MainActor () -> Void

    init(role: ButtonRole?, label: Label, action: @escaping @MainActor () -> Void) {
        self.role = role
        self.label = label
        self.action = action
    }

    /// Runs the button's action, as a click on a bordered button does.
    @MainActor public func trigger() { action() }
}

// MARK: - The built-in looks

/// The chrome a built-in style draws (internal): the old closed struct's `Kind`, plus `.borderedProminent` and
/// `.link` (`BY-G`).
enum ButtonLook: Equatable, Sendable {
    case bordered, borderless, plain, glass, glassProminent, borderedProminent, link

    /// Whether this look draws the bordered chrome (the pressed wash, the padded metrics).
    var isBordered: Bool { self == .bordered || self == .borderedProminent }

    /// Whether this look draws a Liquid Glass capsule (`LG-M`).
    var isGlass: Bool { self == .glass || self == .glassProminent }

    /// The glass this look draws, or `nil`.
    var glass: Glass? {
        switch self {
        case .glass: .regular.interactive()
        case .glassProminent: .regular.tint(Color.accentColor).interactive()
        default: nil
        }
    }

    /// The label colour this look forces on its content, or `nil` for the environment's.
    var labelColor: Color? {
        switch self {
        case .borderedProminent: .white
        case .link: .accentColor
        default: nil
        }
    }
}

/// A built-in style, which `Button` draws itself (internal): its `makeBody` is never called by `Button`.
@MainActor protocol BuiltInButtonStyle {
    var look: ButtonLook { get }
}

/// The platform's default button style (SwiftUI's `DefaultButtonStyle`): bordered on macOS.
public struct DefaultButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The default style.
    public init() {}
    var look: ButtonLook { .bordered }
    /// The bare label: `Button` draws the chrome itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// The bordered chrome (SwiftUI's `BorderedButtonStyle`, BT0): the label padded by `controlSize`, a strut height, a
/// `.surfaceSecondary` fill, corner radius 5 and a 1-point `.separator` border.
public struct BorderedButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The bordered style.
    public init() {}
    var look: ButtonLook { .bordered }
    /// The bare label: `Button` draws the chrome itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// The bordered chrome filled with the accent colour and a white label (SwiftUI's `BorderedProminentButtonStyle`,
/// `BY-G`): the bordered metrics, no border; pressed it takes the same wash. The looks are MetalUI's (unmeasured).
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The prominent style.
    public init() {}
    var look: ButtonLook { .borderedProminent }
    /// The bare label: `Button` draws the chrome itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// The label alone at its own size (SwiftUI's `BorderlessButtonStyle`, BT1). SwiftUI tints it and does not tint
/// `.plain`; that tint is unmeasured, so MetalUI draws the two identically.
public struct BorderlessButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The borderless style.
    public init() {}
    var look: ButtonLook { .borderless }
    /// The bare label: `Button` draws the label itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// The label alone (SwiftUI's `PlainButtonStyle`, BT1: 17×16 over a 17×16 `Text("Go")`); pressed it draws at 60 %.
public struct PlainButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The plain style.
    public init() {}
    var look: ButtonLook { .plain }
    /// The bare label: `Button` draws the label itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// A link: the label alone in the accent colour (SwiftUI's `LinkButtonStyle`, `BY-G`); pressed it draws at 60 %.
/// MetalUI changes no cursor on hover (`BY-G`, carried; `.pointerStyle(.link)` exists, `CI-J`).
public struct LinkButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The link style.
    public init() {}
    var look: ButtonLook { .link }
    /// The bare label: `Button` draws the label itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// SwiftUI's `.glass`: the label padded as the bordered style is, in a capsule of regular interactive Liquid Glass
/// (`LG-M`; `.regular.interactive()` through `Frame.fillGlass`, so it blurs the backdrop, lifts while pressed and
/// follows Reduce Transparency). The look's metrics are MetalUI's (human check LG2).
public struct GlassButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The glass style.
    public init() {}
    var look: ButtonLook { .glass }
    /// The bare label: `Button` draws the glass itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// SwiftUI's `.glassProminent`: `.glass` tinted with the accent (`.regular.tint(accent).interactive()`, `LG-M`).
public struct GlassProminentButtonStyle: PrimitiveButtonStyle, BuiltInButtonStyle, Hashable, Sendable {
    /// The prominent glass style.
    public init() {}
    var look: ButtonLook { .glassProminent }
    /// The bare label: `Button` draws the glass itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    /// The platform's default: bordered on macOS.
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    /// The bordered chrome.
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    /// The accent-filled chrome with a white label (`BY-G`).
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    /// The label alone (SwiftUI tints it; MetalUI does not — unmeasured).
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    /// The label alone.
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

extension PrimitiveButtonStyle where Self == LinkButtonStyle {
    /// The accent-coloured label alone (`BY-G`).
    public static var link: LinkButtonStyle { LinkButtonStyle() }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    /// Regular interactive Liquid Glass in a capsule (`LG-M`).
    public static var glass: GlassButtonStyle { GlassButtonStyle() }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    /// Accent-tinted interactive Liquid Glass in a capsule (`LG-M`).
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

// MARK: - The environment

/// A button style resolved for the environment (internal): a built-in look, or a custom style kept as itself.
struct ResolvedButtonStyle {
    enum Storage {
        case look(ButtonLook)
        case button(any ButtonStyle)
        case primitive(any PrimitiveButtonStyle)
    }

    var storage: Storage
    /// What a retained subtree compares (`EE-F`): the built-in look, a custom style by `==` when it is `Equatable`,
    /// else uncomparable.
    var reading: EnvironmentReading

    static var automatic: ResolvedButtonStyle {
        ResolvedButtonStyle(storage: .look(.bordered), reading: .value(ButtonLook.bordered))
    }

    @MainActor init<S: ButtonStyle>(_ style: S) {
        storage = .button(style)
        reading = .of(style)
    }

    @MainActor init<S: PrimitiveButtonStyle>(_ style: S) {
        if let builtIn = style as? any BuiltInButtonStyle {
            storage = .look(builtIn.look)
            reading = .value(builtIn.look)
        } else {
            storage = .primitive(style)
            reading = .of(style)
        }
    }

    private init(storage: Storage, reading: EnvironmentReading) {
        self.storage = storage
        self.reading = reading
    }
}

struct ButtonStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedButtonStyle { .automatic }
}

extension EnvironmentValues {
    /// The button style below (internal; written by `.buttonStyle(_:)`).
    var buttonStyle: ResolvedButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { setCustom(ButtonStyleKey.self, newValue, reading: newValue.reading) }
    }
}

extension ElementGroup {
    /// Sets the style of every `Button` below — SwiftUI's `.buttonStyle(_:)` over an open protocol (ruling `BY-A`).
    /// Inherited through the environment, the nearest writer winning; a `Button`'s own `.buttonStyle` is nearest.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> EnvironmentScope<Self> {
        let resolved = ResolvedButtonStyle(style)
        return transformEnvironment(\.buttonStyle) { $0 = resolved }
    }

    /// `buttonStyle(_:)` for a ``PrimitiveButtonStyle``, the built-ins among them (`.plain`, `.borderedProminent`).
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> EnvironmentScope<Self> {
        let resolved = ResolvedButtonStyle(style)
        return transformEnvironment(\.buttonStyle) { $0 = resolved }
    }
}
