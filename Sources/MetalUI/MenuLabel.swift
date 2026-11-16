import MetalUICore

// Image and `Label` menu items (ruling `MN-AP`; probe `docs/probes/swiftui-menu-label-items.swift`, record 322).
// `Label(_:systemImage:)` as a type, the closed protocol a menu item's label conforms to, and the
// `systemImage:` spellings of `Button`, `Toggle` and `Menu`. `MenuContent` itself stays closed (`MN-D` item 1).

/// A title with an icon — SwiftUI's `Label`: a row of the icon, 8 points of space and the title (the gap and the
/// baseline probe `S11` read). As a menu item's label (`Button { … } label: { Label(…) }`) it is the item's title
/// and its symbol; **no `labelStyle`**, so a `Label` is always icon and title (divergence 242).
public struct Label<Title: ElementGroup, Icon: ElementGroup>: Component {
    let title: Title
    let icon: Icon

    /// A label of `title` and `icon` — SwiftUI's `Label(title:icon:)`.
    public init(@ElementBuilder title: () -> Title, @ElementBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    /// The icon, then the title, in a row.
    public var content: some ElementGroup {
        HStack { icon; title }
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label of the SF Symbols symbol `name` and the title `titleKey` — SwiftUI's `Label(_:systemImage:)`. A
    /// string literal is parsed as inline Markdown, as `Text`'s is (`SR-C`).
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(systemName: name) })
    }

    /// A label of the symbol `name` and the `StringProtocol` value `title`, shown verbatim (`SR-C`).
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String) {
        self.init(title: { Text(verbatim: String(title)) }, icon: { Image(systemName: name) })
    }
}

/// What a menu item's label evaluates to: its title and, for a `Label`, its symbol. SPI, with an internal
/// initialiser, so only this module makes one (`MN-AP`).
@_spi(MenuInternals) public struct _MenuItemLabelParts {
    let title: String
    let symbol: String?
    init(title: String, symbol: String?) {
        self.title = title
        self.symbol = symbol
    }
}

/// A label a menu item can have: `Text`, and `Label` of a `Text` and an `Image` (`MN-AP`). **Closed**, as
/// `MenuContent` is: its one requirement is SPI, so a type outside MetalUI cannot conform — a `Button` whose label
/// is anything else is still not a menu item (`MN-D` item 5).
public protocol MenuItemLabel: ElementGroup {
    /// The title and symbol the item shows. SPI: see the protocol's doc.
    @_spi(MenuInternals) @MainActor func _menuItemLabel() -> _MenuItemLabelParts
}

extension Text: MenuItemLabel {
    /// This label's parts. SPI: see `MenuItemLabel`.
    @_spi(MenuInternals) public func _menuItemLabel() -> _MenuItemLabelParts {
        _MenuItemLabelParts(title: string, symbol: nil)
    }
}

extension Label: MenuItemLabel where Title == Text, Icon == Image {
    /// This label's parts: the title's string and the icon's symbol name; an icon that is not a symbol (a bitmap)
    /// shows no image. SPI: see `MenuItemLabel`.
    @_spi(MenuInternals) public func _menuItemLabel() -> _MenuItemLabelParts {
        var symbol: String?
        if case .symbol(let name) = icon.content { symbol = name }
        return _MenuItemLabelParts(title: title.string, symbol: symbol)
    }
}

/// A label under an environment write — `Label(…).foregroundStyle(.green)`, `Text("T").font(…)` — is the label's
/// own title and symbol: **the write is not read** (SwiftUI's menu ignores a `foregroundStyle` on the image, probe L3,
/// L5; only `.tint` on the item colours it, `MN-AP`).
extension EnvironmentScope: MenuItemLabel where Content: MenuItemLabel {
    /// The wrapped label's parts. SPI: see `MenuItemLabel`.
    @_spi(MenuInternals) public func _menuItemLabel() -> _MenuItemLabelParts { content._menuItemLabel() }
}

extension Button where Label == MetalUI.Label<Text, Image> {
    /// A button labelled by the symbol `name` and `titleKey` — SwiftUI's `Button(_:systemImage:action:)`.
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { MetalUI.Label(titleKey, systemImage: name) }
    }

    /// A button labelled by the symbol `name` and the `StringProtocol` value `title`, shown verbatim.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { MetalUI.Label(title, systemImage: name) }
    }

    /// As `init(_:systemImage:action:)` with a `role` (SwiftUI's `Button(_:systemImage:role:action:)`).
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, role: ButtonRole?,
                action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { MetalUI.Label(titleKey, systemImage: name) }
    }

    /// As `init(_:systemImage:action:)` with a `role`, the title shown verbatim.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, role: ButtonRole?,
                                   action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { MetalUI.Label(title, systemImage: name) }
    }
}

extension Toggle where Label == MetalUI.Label<Text, Image> {
    /// A toggle labelled by the symbol `name` and `titleKey` — SwiftUI's `Toggle(_:systemImage:isOn:)`.
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { MetalUI.Label(titleKey, systemImage: name) }
    }

    /// A toggle labelled by the symbol `name` and the `StringProtocol` value `title`, shown verbatim.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { MetalUI.Label(title, systemImage: name) }
    }
}

extension Menu where Label == MetalUI.Label<Text, Image> {
    /// A menu labelled by the symbol `name` and `titleKey` — as a button, or a submenu inside another menu with
    /// its symbol beside the title; SwiftUI's `Menu(_:systemImage:content:)`.
    @MainActor
    public init(_ titleKey: LocalizedStringKey, systemImage name: String,
                @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.init(content: content) { MetalUI.Label(titleKey, systemImage: name) }
    }

    /// A menu labelled by the symbol `name` and the `StringProtocol` value `title`, shown verbatim.
    @_disfavoredOverload
    @MainActor
    public init<S: StringProtocol>(_ title: S, systemImage name: String,
                                   @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.init(content: content) { MetalUI.Label(title, systemImage: name) }
    }
}
