import MetalUICore
import MetalUIPlatform

// Menus, popovers and tooltips, lane 1 — the menu item vocabulary (ruling
// `MN-D`; spec `docs/superpowers/specs/2026-10-02-menus-popovers-design.md`
// §2.2). A menu's items are data, not views: a `@MenuContentBuilder` block is
// evaluated — at each open, never in layout or paint (`MN-D` item 4) — into
// `MenuNode`s, which `Window` numbers into a `PlatformMenu` for the platform
// (AppKit's `NSMenu`) or its own in-window panel (`MN-F`). SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift`, arms C1–C4c.

/// One evaluated menu item (`MN-D`): what the platform shows and what choosing
/// it runs.
struct MenuNode {
    enum Kind {
        /// A `Button`: choosing it runs `run`.
        case action
        /// A `Toggle`: shows `isOn`; choosing it runs `run`, which writes `!isOn`.
        case toggle
        /// A `Menu`: a submenu of these items.
        case submenu([MenuNode])
        /// A `Divider`.
        case separator
        /// A `Text`: a disabled item (C1's "Plain text item").
        case text
    }

    var kind: Kind
    var title: String
    var isEnabled: Bool
    var isOn = false
    var shortcut: KeyboardShortcut?
    var run: (@MainActor () -> Void)?
}

/// What a menu item is evaluated in: the menu's environment, of which only
/// `isEnabled` is read (`MN-D` item 2). SPI, with an internal initialiser.
@_spi(MenuInternals) public struct _MenuContext {
    var isEnabled: Bool
    init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

/// What a `MenuContent` evaluates to. SPI, with an internal initialiser, so
/// only this module can make one (`MN-D` item 1).
@_spi(MenuInternals) public struct _MenuNodes {
    let nodes: [MenuNode]
    init(_ nodes: [MenuNode]) { self.nodes = nodes }
}

/// Content a menu can show: `Button` and `Toggle` with a `Text` label,
/// `Menu("…") { … }` (a submenu), `Divider`, `Text` (a disabled item), any of
/// them under `.disabled(_:)`, and `if`/`switch`/`for` through
/// `@MenuContentBuilder` — SwiftUI's menu content (ruling `MN-D`; probe arm
/// C1).
///
/// **Closed**: its one requirement is SPI, so a type outside MetalUI cannot
/// conform (`MN-D` item 1; guard `anOutsideTypeCannotConformToMenuContent`) —
/// an item the platform cannot draw cannot be declared. Not offered, owner
/// none: `Picker`, `Section`, image and `Label` items, a `Button` whose label
/// is not a `Text` (`MN-D` item 5; guard `aPickerIsNotAMenuItem`).
public protocol MenuContent {
    /// The items this content evaluates to. SPI: see the protocol's doc.
    @_spi(MenuInternals) @MainActor func _menuNodes(in context: _MenuContext) -> _MenuNodes
}

extension MenuContent {
    @MainActor func menuNodes(isEnabled: Bool) -> [MenuNode] {
        _menuNodes(in: _MenuContext(isEnabled: isEnabled)).nodes
    }
}

/// What a `@MenuContentBuilder` block builds: its items, in order.
public struct MenuItems: MenuContent {
    let children: [any MenuContent]

    init(_ children: [any MenuContent]) { self.children = children }

    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes(children.flatMap { $0._menuNodes(in: context).nodes })
    }
}

/// The result builder for menu content (ruling `MN-D` item 1): a block, `if`,
/// `if`/`else`, `switch` and `for`, each element a `MenuContent`.
@resultBuilder
public enum MenuContentBuilder {
    /// One item.
    public static func buildExpression<C: MenuContent>(_ content: C) -> MenuItems { MenuItems([content]) }
    /// A block of items, in order.
    public static func buildBlock(_ items: MenuItems...) -> MenuItems { MenuItems(items) }
    /// An `if` with no `else`: its items, or none.
    public static func buildOptional(_ items: MenuItems?) -> MenuItems { items ?? MenuItems([]) }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first items: MenuItems) -> MenuItems { items }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second items: MenuItems) -> MenuItems { items }
    /// A `for` loop: every iteration's items, in order.
    public static func buildArray(_ items: [MenuItems]) -> MenuItems { MenuItems(items) }
}

/// A separator between menu items — SwiftUI's `Divider` inside a menu (C1).
///
/// **Menu-only** (ruling `MN-H` item 3): as a view in a stack it would need
/// the enclosing stack's axis, which MetalUI's environment does not carry, so
/// it is not an `Element`. Owner none.
public struct Divider: MenuContent {
    /// A separator.
    public init() {}

    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes([MenuNode(kind: .separator, title: "", isEnabled: false)])
    }
}

/// A button item: its label's string as the title, its action (or a caller's
/// `onClick`, which replaces it, as on the button itself) run when chosen, its
/// `.keyboardShortcut` shown — and **inactive while the menu is closed** (C12,
/// `MN-D` item 3). `role:` is accepted and drawn the same (C1).
extension Button: MenuContent where Label == Text {
    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes([MenuNode(kind: .action, title: box.content.first.string, isEnabled: context.isEnabled,
                             shortcut: shortcut, run: handlers.onClick ?? action)])
    }
}

/// A toggle item: an on/off state that choosing flips by writing `!isOn`
/// through its binding (C1, C4).
extension Toggle: MenuContent where Label == Text {
    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        let binding = isOn
        let on = binding.wrappedValue
        return _MenuNodes([MenuNode(kind: .toggle, title: box.content.second.string, isEnabled: context.isEnabled,
                                    isOn: on, run: { binding.wrappedValue = !on })])
    }
}

/// A disabled item showing the string (C1's "Plain text item").
extension Text: MenuContent {
    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes([MenuNode(kind: .text, title: string, isEnabled: false)])
    }
}

/// An item under an environment write: the write is applied to the menu's
/// environment and **only `isEnabled` is read** (`MN-D` item 2), so
/// `.disabled(true)` disables an item and `.disabled(false)` under a disabled
/// ancestor leaves it disabled (`EV-D`'s AND).
extension EnvironmentScope: MenuContent where Content: MenuContent {
    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        var values = EnvironmentValues()
        values.isEnabled = context.isEnabled
        if case .transform(let transform) = write { transform(&values) }
        return content._menuNodes(in: _MenuContext(isEnabled: values.isEnabled))
    }
}

/// A submenu item: its title and its items, evaluated with it (C1, C3).
extension Menu: MenuContent where Label == Text {
    /// This content\'s items. SPI: see `MenuContent`.
    @_spi(MenuInternals) public func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        let items = content()._menuNodes(in: context).nodes
        return _MenuNodes([MenuNode(kind: .submenu(items), title: label.string, isEnabled: context.isEnabled)])
    }
}

// MARK: - `Menu` (ruling `MN-AD`: the declaration here, the pull-down in lane 2)

/// A button that opens a menu — SwiftUI's `Menu` (ruling `MN-H`; arm M1). The
/// `Menu(_ title:content:)` spelling is also a submenu item inside another
/// menu (`MN-D`).
///
/// This file holds the declaration and its storage (`MN-AD`); its behaviour as
/// a pull-down button in a window is `PullDownMenu.swift`'s.
public struct Menu<Label: ElementGroup, Content: MenuContent> {
    /// The menu button's style (the `StyledElement` storage, `MN-AD`).
    public var style: Style
    /// The menu button's decoration.
    public var decoration: Decoration
    /// The menu button's explicit identity, if any.
    public var elementID: ElementID?
    /// The menu button's handlers.
    public var handlers: Handlers = Handlers()
    /// The menu's items, evaluated at each open (`MN-D` item 4).
    let content: @MainActor () -> Content
    /// The button's label.
    var label: Label

    /// A menu of `content`'s items behind a button showing `label`.
    @MainActor
    public init(@MenuContentBuilder content: @escaping @MainActor () -> Content,
                @ElementBuilder label: () -> Label) {
        // `Button`'s automatic chrome (lane 2, `MN-H` item 1): a caller's
        // `.background`/`.border` replaces it as it would on a `Button`.
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.justifyContent = .center
        self.style = style
        self.decoration = Decoration(background: .surfaceSecondary, cornerRadius: Pixels(5),
                                     border: BorderStyle(.separator, width: Pixels(1)))
        self.content = content
        self.label = label()
    }
}

extension Menu where Label == Text {
    /// A menu titled `title` — as a button, or as a submenu inside another
    /// menu (`MN-D`, `MN-H` item 1).
    @MainActor
    public init(_ title: String, @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.init(content: content) { Text(title) }
    }
}
