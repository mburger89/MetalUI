import MetalUICore
import MetalUIPlatform

// Menus, popovers and tooltips, lane 2 — the menu bar's commands (rulings
// `MN-I`, `MN-J`, `MN-X`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §2.5, §3.6).
// SwiftUI's side is `docs/probes/swiftui-commands.swift` (PLAIN and FULL).
// MetalUI's `App` is a class, not a `Scene`, so SwiftUI's `.commands { }` scene
// modifier is a method on it; the builders, `CommandMenu`, `CommandGroup` and
// `CommandGroupPlacement` are SwiftUI's spellings.

/// One declaration a `Commands` value makes (`MN-I` item 1).
enum CommandEntry {
    /// Where a `CommandGroup` puts its items relative to its placement's.
    enum Position { case before, after, replacing }

    /// A `CommandMenu`: a top-level menu of its own, inserted before Window.
    case menu(name: String, content: @MainActor () -> MenuItems)
    /// A `CommandGroup`: items before, after or instead of a standard group.
    case group(placement: CommandGroupPlacement, position: Position, content: @MainActor () -> MenuItems)
}

/// What a `Commands` value declares. SPI, with an internal initialiser, so only
/// this module can make one (`MN-I` item 1).
@_spi(MenuInternals) public struct _CommandEntries {
    let entries: [CommandEntry]
    init(_ entries: [CommandEntry]) { self.entries = entries }
}

/// The menu bar's commands — SwiftUI's `Commands`: `CommandMenu`,
/// `CommandGroup`, and `if`/`switch` through `@CommandsBuilder`, handed to
/// `App.commands(content:)` (ruling `MN-I`).
///
/// **Closed**: its one requirement is SPI, so a type outside MetalUI cannot
/// conform (`MN-I` item 1) — SwiftUI's `body`-composed custom `Commands` are
/// not offered, owner none.
public protocol Commands {
    /// The declarations this value makes. SPI: see the protocol's doc.
    @_spi(MenuInternals) @MainActor func _commandEntries() -> _CommandEntries
}

/// What a `@CommandsBuilder` block builds: its commands, in order.
public struct CommandItems: Commands {
    let children: [any Commands]

    init(_ children: [any Commands]) { self.children = children }

    /// These commands' declarations. SPI: see `Commands`.
    @_spi(MenuInternals) public func _commandEntries() -> _CommandEntries {
        _CommandEntries(children.flatMap { $0._commandEntries().entries })
    }
}

/// The result builder for `App.commands(content:)` (ruling `MN-I` item 1): a
/// block, `if`, `if`/`else` and `switch`, each element a `CommandMenu` or a
/// `CommandGroup`.
@resultBuilder
public enum CommandsBuilder {
    /// One command.
    public static func buildExpression<C: Commands>(_ command: C) -> CommandItems { CommandItems([command]) }
    /// A block of commands, in order.
    public static func buildBlock(_ commands: CommandItems...) -> CommandItems { CommandItems(commands) }
    /// An `if` with no `else`: its commands, or none.
    public static func buildOptional(_ commands: CommandItems?) -> CommandItems { commands ?? CommandItems([]) }
    /// The first branch of an `if`/`else` or `switch`.
    public static func buildEither(first commands: CommandItems) -> CommandItems { commands }
    /// The second branch of an `if`/`else` or `switch`.
    public static func buildEither(second commands: CommandItems) -> CommandItems { commands }
}

/// A top-level menu of commands — SwiftUI's `CommandMenu` (FULL arm's
/// "Tools"). MetalUI inserts it **before the Window menu** (SwiftUI inserts it
/// after View, which MetalUI does not build; `MN-I` item 2), in declaration
/// order. Its items are menu content (`Button`, `Toggle`, `Menu`, `Divider`,
/// `Text`), evaluated afresh whenever the bar is shown or a key reaches the
/// command stage, so state and `.disabled` stay live; an item's
/// `.keyboardShortcut` fires when no element in the key window claims the key
/// first (`MN-J`).
public struct CommandMenu<Content: MenuContent>: Commands {
    let name: String
    let content: @MainActor () -> Content

    /// A menu titled `name` holding `content`'s items. `@escaping` where
    /// SwiftUI's is not — it is evaluated later (`MN-X` item 3).
    public init(_ name: String, @MenuContentBuilder content: @escaping @MainActor () -> Content) {
        self.name = name
        self.content = content
    }

    /// This menu's declaration. SPI: see `Commands`.
    @_spi(MenuInternals) public func _commandEntries() -> _CommandEntries {
        let content = content
        return _CommandEntries([.menu(name: name, content: { MenuItems([content()]) })])
    }
}

/// Items placed relative to a standard group of the menu bar — SwiftUI's
/// `CommandGroup` (FULL arm: "After New" after the new-item group; Help emptied
/// by `replacing: .help`). Several groups at one placement and position apply
/// in declaration order.
public struct CommandGroup<Content: MenuContent>: Commands {
    let placement: CommandGroupPlacement
    let position: CommandEntry.Position
    let addition: @MainActor () -> Content

    /// `addition`'s items placed before `group`'s.
    public init(before group: CommandGroupPlacement,
                @MenuContentBuilder addition: @escaping @MainActor () -> Content) {
        self.placement = group
        self.position = .before
        self.addition = addition
    }

    /// `addition`'s items placed after `group`'s.
    public init(after group: CommandGroupPlacement,
                @MenuContentBuilder addition: @escaping @MainActor () -> Content) {
        self.placement = group
        self.position = .after
        self.addition = addition
    }

    /// `addition`'s items in place of `group`'s (an empty addition removes the
    /// group).
    public init(replacing group: CommandGroupPlacement,
                @MenuContentBuilder addition: @escaping @MainActor () -> Content) {
        self.placement = group
        self.position = .replacing
        self.addition = addition
    }

    /// This group's declaration. SPI: see `Commands`.
    @_spi(MenuInternals) public func _commandEntries() -> _CommandEntries {
        let addition = addition
        return _CommandEntries([.group(placement: placement, position: position,
                                       content: { MenuItems([addition()]) })])
    }
}

/// A standard group of the menu bar a `CommandGroup` places its items against —
/// SwiftUI's `CommandGroupPlacement`, the nine groups MetalUI builds (`MN-I`
/// item 2). `Hashable` where SwiftUI's is only `Sendable` — additive (`MN-X`
/// item 3). Not offered, owner none: `.saveItem`, `.printItem`,
/// `.textFormatting`, `.toolbar`, `.sidebar`, `.importExport`,
/// `.systemServices`, `.singleWindowList`.
public struct CommandGroupPlacement: Sendable, Hashable {
    let name: String

    private init(_ name: String) { self.name = name }

    /// The application menu's About item.
    public static let appInfo = CommandGroupPlacement("appInfo")
    /// The application menu's Hide, Hide Others and Show All.
    public static let appVisibility = CommandGroupPlacement("appVisibility")
    /// The application menu's Quit.
    public static let appTermination = CommandGroupPlacement("appTermination")
    /// The File menu's new-item group, empty by default (MetalUI has no scene
    /// to make a new window of).
    public static let newItem = CommandGroupPlacement("newItem")
    /// The Edit menu's Undo and Redo.
    public static let undoRedo = CommandGroupPlacement("undoRedo")
    /// The Edit menu's Cut, Copy, Paste, Delete and Select All.
    public static let pasteboard = CommandGroupPlacement("pasteboard")
    /// The Window menu's Minimize and Zoom.
    public static let windowSize = CommandGroupPlacement("windowSize")
    /// The Window menu's Bring All to Front.
    public static let windowArrangement = CommandGroupPlacement("windowArrangement")
    /// The Help menu's group, empty by default; the Help menu shows only when
    /// something is placed here.
    public static let help = CommandGroupPlacement("help")
}

// MARK: - The menu bar's model (spec §3.6) — lane 2 red stubs

extension App {
    /// The menu bar's commands — SwiftUI's `.commands { }` scene modifier as a
    /// method on MetalUI's `App` (ruling `MN-I` item 1, `MN-X` item 2). A second
    /// call replaces the first.
    public func commands<C: Commands>(@CommandsBuilder content: @escaping @MainActor () -> C) {
        commandsContent = { content() }
    }

    /// The bar's menus (stub).
    func menuBarContent() -> [PlatformMenu] { [] }

    /// The enabled command shortcuts (stub).
    func enabledCommandShortcuts() -> [(KeyboardShortcut, @MainActor () -> Void)] { [] }
}
