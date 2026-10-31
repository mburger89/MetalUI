import MetalUICore

/// A toggle's look as SwiftUI's open protocol (ruling `BY-H`): `makeBody` turns the ``ToggleStyleConfiguration`` —
/// the label and the binding — into the toggle's body. **Applied with `.toggleStyle(_:)` and inherited through the
/// environment**, the nearest writer winning, on any content or on a `Toggle` itself.
///
/// The `Toggle` keeps the interaction (`BY-C`): a click, a focused Space and an accessibility press each write
/// `!isOn` once, the node is published as a check box, and the focus ring and disabled look surround the body. A
/// style that wants its own tap target may also write `configuration.isOn` from an `onClick` of its own.
///
/// ```swift
/// struct Tick: ToggleStyle {
///     func makeBody(configuration: Configuration) -> some ElementGroup {
///         configuration.label.padding(6).background(configuration.isOn ? Color.accent : Color.gray)
///     }
/// }
/// ```
@MainActor
public protocol ToggleStyle {
    /// The body's type, any element or group.
    associatedtype Body: ElementGroup

    /// The configuration `makeBody` receives.
    typealias Configuration = ToggleStyleConfiguration

    /// The toggle's body for `configuration`. Built at layout, every frame the toggle is laid out.
    @ElementBuilder func makeBody(configuration: Configuration) -> Body
}

/// What a ``ToggleStyle`` receives (ruling `BY-H`): the label and the bound state. Constructed by `Toggle` only.
/// As in SwiftUI, `isOn` and `isMixed` are `@Binding`s, so `configuration.isOn` reads the value,
/// `configuration.isOn = x` and `configuration.isOn.toggle()` write it, and `configuration.$isOn` is the binding.
public struct ToggleStyleConfiguration {
    /// SwiftUI's nested `Label`.
    public typealias Label = StyleLabel

    /// The toggle's label content.
    public let label: Label
    /// Whether the toggle is on.
    @Binding public var isOn: Bool
    /// Whether the toggle is in the mixed state. **Always `false`** (`BY-F`): a `Toggle` here has no mixed source
    /// (`Toggle(sources:isOn:)` is not built), so the binding is a constant.
    @Binding public var isMixed: Bool

    @MainActor init(label: Label, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
        self._isMixed = .constant(false)
    }
}

/// The chrome a built-in toggle style draws (internal).
enum ToggleLook: Equatable, Sendable {
    case checkbox, `switch`, button
}

/// A built-in toggle style, which `Toggle` draws itself (internal).
@MainActor protocol BuiltInToggleStyle {
    var look: ToggleLook { get }
}

/// The platform's default toggle style (SwiftUI's `DefaultToggleStyle`): the checkbox on macOS.
public struct DefaultToggleStyle: ToggleStyle, BuiltInToggleStyle, Hashable, Sendable {
    /// The default style.
    public init() {}
    var look: ToggleLook { .checkbox }
    /// The bare label: `Toggle` draws the checkbox itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// A 14-point box and the label (SwiftUI's `CheckboxToggleStyle`, probe TG0 = TG1; `DD-S`).
public struct CheckboxToggleStyle: ToggleStyle, BuiltInToggleStyle, Hashable, Sendable {
    /// The checkbox style.
    public init() {}
    var look: ToggleLook { .checkbox }
    /// The bare label: `Toggle` draws the checkbox itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// A capsule track with a knob and the label (SwiftUI's `SwitchToggleStyle`, `BY-I`): 38×22, the knob an 18-point
/// circle inset 2. The metrics are MetalUI's (unmeasured, human check BY); the knob does not slide (divergence 885).
public struct SwitchToggleStyle: ToggleStyle, BuiltInToggleStyle, Hashable, Sendable {
    /// The switch style.
    public init() {}
    var look: ToggleLook { .switch }
    /// The bare label: `Toggle` draws the switch itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// The toggle drawn as a bordered button that fills with the accent colour while on (SwiftUI's
/// `ButtonToggleStyle`, `BY-I`): the bordered metrics; the looks are MetalUI's.
public struct ButtonToggleStyle: ToggleStyle, BuiltInToggleStyle, Hashable, Sendable {
    /// The button style.
    public init() {}
    var look: ToggleLook { .button }
    /// The bare label: `Toggle` draws the button itself.
    public func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    /// The platform's default: the checkbox on macOS.
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    /// A box and the label.
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    /// A track, a knob and the label.
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

extension ToggleStyle where Self == ButtonToggleStyle {
    /// A bordered button that fills while on.
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

// MARK: - The environment

/// A toggle style resolved for the environment (internal): a built-in look, or a custom style kept as itself.
struct ResolvedToggleStyle {
    enum Storage {
        case look(ToggleLook)
        case custom(any ToggleStyle)
    }

    var storage: Storage
    /// What a retained subtree compares (`EE-F`): the built-in look, a custom style by `==` when `Equatable`.
    var reading: EnvironmentReading

    static var automatic: ResolvedToggleStyle {
        ResolvedToggleStyle(storage: .look(.checkbox), reading: .value(ToggleLook.checkbox))
    }

    @MainActor init<S: ToggleStyle>(_ style: S) {
        if let builtIn = style as? any BuiltInToggleStyle {
            storage = .look(builtIn.look)
            reading = .value(builtIn.look)
        } else {
            storage = .custom(style)
            reading = .of(style)
        }
    }

    private init(storage: Storage, reading: EnvironmentReading) {
        self.storage = storage
        self.reading = reading
    }
}

struct ToggleStyleKey: EnvironmentKey {
    static var defaultValue: ResolvedToggleStyle { .automatic }
}

extension EnvironmentValues {
    /// The toggle style below (internal; written by `.toggleStyle(_:)`).
    var toggleStyle: ResolvedToggleStyle {
        get { self[ToggleStyleKey.self] }
        set { setCustom(ToggleStyleKey.self, newValue, reading: newValue.reading) }
    }
}

extension ElementGroup {
    /// Sets the style of every `Toggle` below — SwiftUI's `.toggleStyle(_:)` (ruling `BY-H`). Inherited through the
    /// environment, the nearest writer winning; a `Toggle`'s own `.toggleStyle` is nearest.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> EnvironmentScope<Self> {
        let resolved = ResolvedToggleStyle(style)
        return transformEnvironment(\.toggleStyle) { $0 = resolved }
    }
}
