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

/// A `Button`'s look — SwiftUI's call-site spelling, `.buttonStyle(.plain)`,
/// over a **closed** set (ruling `IX-E` item 2; `PickerStyle`'s precedent,
/// `DD-V`).
///
/// - `.automatic` and `.bordered`: today's chrome (BT0) — the label padded by
///   `controlSize`, a strut height, a `.surfaceSecondary` fill, corner radius 5
///   and a 1-point `.separator` border.
/// - `.borderless` and `.plain`: the label alone, at the label's size (BT1: both
///   17×16 over a 17×16 `Text("Go")`). SwiftUI tints `.borderless` and not
///   `.plain`; that tint is unmeasured, so MetalUI draws the two identically.
///
/// **The name differs in kind from SwiftUI's, ruled** (`IX-O` correction 7):
/// SwiftUI's `ButtonStyle` is a protocol. Every `.buttonStyle(.plain)` call site
/// spells identically, but adding the protocols later is a source break for code
/// that names this type (`let s: ButtonStyle = .plain`); the statics would then
/// move to `PrimitiveButtonStyle where Self == PlainButtonStyle`, SwiftUI's own
/// shape. Not offered (owner none): `.borderedProminent`, `.link`, custom styles
/// and `configuration.isPressed`.
public struct ButtonStyle: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case bordered, borderless, plain, glass, glassProminent }
    let kind: Kind

    /// The platform's default: bordered on macOS.
    public static let automatic = ButtonStyle(kind: .bordered)
    /// The bordered chrome.
    public static let bordered = ButtonStyle(kind: .bordered)
    /// The label alone (SwiftUI tints it; MetalUI does not — unmeasured).
    public static let borderless = ButtonStyle(kind: .borderless)
    /// The label alone.
    public static let plain = ButtonStyle(kind: .plain)

    /// SwiftUI's `.glass`: the label padded as the bordered style is, in a capsule of regular interactive Liquid
    /// Glass (`LG-M`; `.regular.interactive()` through `Frame.fillGlass`, so it blurs the backdrop, lifts while
    /// pressed and follows Reduce Transparency). The look's metrics are MetalUI's (human check LG2).
    public static let glass = ButtonStyle(kind: .glass)
    /// SwiftUI's `.glassProminent`: `.glass` tinted with the accent (`.regular.tint(accent).interactive()`, `LG-M`).
    public static let glassProminent = ButtonStyle(kind: .glassProminent)

    /// Whether this style draws the bordered chrome.
    var isBordered: Bool { kind == .bordered }

    /// Whether this style draws a Liquid Glass capsule (`LG-M`).
    var isGlass: Bool { kind == .glass || kind == .glassProminent }

    /// The glass this style draws, or `nil`.
    var glass: Glass? {
        switch kind {
        case .glass: .regular.interactive()
        case .glassProminent: .regular.tint(Color.accent).interactive()
        default: nil
        }
    }
}
