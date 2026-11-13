import MetalUICore

// The menu model at the platform seam (rulings `MN-C`, `MN-D`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §2.1). A value:
// `MetalUI` evaluates a `.contextMenu`'s content into one of these at each open
// and hands it to `PlatformWindow.presentMenu(_:at:)`; the platform builds its
// native menu from it (AppKit's `NSMenu`) or declines, and `Window` draws it.
// No closure crosses the seam — a choice comes back as an item id
// (`InputEvent.menuAction`).

/// A key equivalent shown on a menu item (ruling `MN-D` item 3): `key` is the
/// character AppKit's `keyEquivalent` takes (lowercase for a letter),
/// `modifiers` the keys held.
public struct PlatformKeyEquivalent: Sendable, Equatable {
    /// The key, as a one-character string.
    public var key: String
    /// The modifier keys.
    public var modifiers: Modifiers

    /// A key equivalent of `key` with `modifiers`.
    public init(key: String, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// A standard application command a platform implements itself — About,
/// Quit, the Edit menu's pasteboard commands (ruling `MN-I` item 2). A menu
/// item carrying one runs the platform's action, not a MetalUI closure.
public enum StandardMenuAction: Sendable, Equatable, CaseIterable {
    case about, hide, hideOthers, showAll, quit, close,
         undo, redo, cut, copy, paste, delete, selectAll,
         minimize, zoom, bringAllToFront
    /// The application menu's Services submenu (`MN-AO`), carried by an empty
    /// `.submenu` item: the platform fills it with the system's services
    /// (AppKit's `NSApp.servicesMenu`). Not a command; no portable platform
    /// shows it.
    case services
}

/// One item of a `PlatformMenu` (ruling `MN-D`).
public struct PlatformMenuItem: Sendable, Equatable {
    /// What the item is.
    public enum Kind: Sendable, Equatable {
        /// A command: choosing it reports this item's `id`.
        case action
        /// A separator line.
        case separator
        /// A submenu holding these items.
        case submenu([PlatformMenuItem])
    }

    /// The item's id within its menu, reported by `InputEvent.menuAction`.
    /// Unique across the whole menu, submenus included (numbered depth-first).
    public var id: Int
    /// What the item is.
    public var kind: Kind
    /// The title shown.
    public var title: String
    /// Whether the item can be chosen; a disabled item is shown dimmed.
    public var isEnabled: Bool
    /// Whether the item shows an on (checked) state — a `Toggle` item.
    public var isOn: Bool
    /// The key equivalent shown beside the title.
    public var shortcut: PlatformKeyEquivalent?
    /// The standard command the platform runs for this item, if any.
    public var standardAction: StandardMenuAction?
    /// The `.accessibilityIdentifier` the item's `Button` declared, for a test
    /// or automation client to find it by (`MN-AL`); `nil` when none.
    public var accessibilityIdentifier: String?
    /// The `.help` text the item's `Button` declared (`MN-AL`): a tooltip,
    /// kept when the item is disabled; `nil` when none.
    public var help: String?

    /// An item; enabled, off, with no shortcut, standard action, identifier or
    /// help unless given.
    public init(id: Int, kind: Kind, title: String, isEnabled: Bool = true, isOn: Bool = false,
                shortcut: PlatformKeyEquivalent? = nil, standardAction: StandardMenuAction? = nil,
                accessibilityIdentifier: String? = nil, help: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.isOn = isOn
        self.shortcut = shortcut
        self.standardAction = standardAction
        self.accessibilityIdentifier = accessibilityIdentifier
        self.help = help
    }
}

/// A menu to present (ruling `MN-C`): its items and the token its outcome
/// (`InputEvent.menuAction`) names, so a stale choice is told from a current
/// one.
public struct PlatformMenu: Sendable, Equatable {
    /// Identifies this presentation; echoed by `MenuActionEvent.menu`.
    public var token: Int
    /// The menu's title (empty for a context menu).
    public var title: String
    /// The items, in order.
    public var items: [PlatformMenuItem]

    /// A menu of `items` under `token`.
    public init(token: Int, title: String = "", items: [PlatformMenuItem]) {
        self.token = token
        self.title = title
        self.items = items
    }

    /// The item whose `accessibilityIdentifier` is `identifier`, searched
    /// depth-first through submenus (`MN-AL`); `nil` when none.
    public func item(accessibilityIdentifier identifier: String) -> PlatformMenuItem? {
        func search(_ items: [PlatformMenuItem]) -> PlatformMenuItem? {
            for item in items {
                if item.accessibilityIdentifier == identifier { return item }
                if case .submenu(let children) = item.kind, let found = search(children) { return found }
            }
            return nil
        }
        return search(items)
    }
}

/// The application's menu bar (ruling `MN-I`): the content, asked for whenever
/// the platform needs it — at install and each time one of its menus opens, so
/// a toggle's state and a disabled item stay live — and the callback a chosen
/// command item runs. Handed to `Platform.setMenuBar(_:)`.
///
/// Every item's `id` is unique across the whole bar; a `standardAction` item is
/// the platform's own command (Quit, Copy …) and never reaches `perform`.
public struct PlatformMenuBar {
    /// The bar's top-level menus, left to right, evaluated afresh at each call.
    public var content: @MainActor () -> [PlatformMenu]
    /// Runs the command item `item` (an id from the last `content()`), from
    /// input.
    public var perform: @MainActor (_ item: Int) -> Void

    /// A menu bar whose menus are `content()` and whose command items run
    /// through `perform`.
    public init(content: @escaping @MainActor () -> [PlatformMenu],
                perform: @escaping @MainActor (_ item: Int) -> Void) {
        self.content = content
        self.perform = perform
    }
}
