import Foundation
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

// MARK: - The menu bar's model (spec §3.6)

/// Which arrangement a `MenuBarModel` builds (ruling `SG-A` item 3).
enum MenuBarStyle {
    /// The Mac's: the application menu, File, Edit, the `CommandMenu`s,
    /// Window and Help — what AppKit shows (`MN-I` item 2), unchanged.
    case appKit
    /// The desktop convention a drawn bar follows (Windows, GNOME): no
    /// application menu; File holds the new-item group and the additions at
    /// `.appVisibility` and `.appTermination`; Edit; the `CommandMenu`s;
    /// Window only with additions; Help holds the help group and the additions
    /// at `.appInfo`; a menu left empty is not shown.
    case drawn
}

/// One evaluation of the menu bar (spec §3.6): its menus, every enabled command
/// item's action by id, and the enabled command shortcuts in menu order.
@MainActor
struct MenuBarModel {
    var menus: [PlatformMenu] = []
    var actions: [Int: @MainActor () -> Void] = [:]
    var shortcuts: [(KeyboardShortcut, @MainActor () -> Void)] = []
    /// The ids of `Toggle` items, which a drawn menu publishes as
    /// `.menuItemCheckBox` (`MN-R`).
    var toggles: Set<Int> = []
    private var next = 1

    /// The entries `commands(content:)` declared.
    private let entries: [CommandEntry]

    /// Evaluates `entries` against the standard menus (`MN-I` item 2) in
    /// `style`'s arrangement (`SG-A` item 3): ids depth-first in menu order,
    /// so an unchanged structure numbers the same at every evaluation.
    init(entries: [CommandEntry], appName: String, style: MenuBarStyle = .appKit) {
        self.entries = entries
        if style == .drawn {
            buildDrawn()
            return
        }
        // Each group's standard items are numbered before its additions, in
        // locals: a mutating call cannot take another mutating call's result
        // as an argument (overlapping access to `self`).
        let about = [standard("About \(appName)", .about)]
        let visibility = [standard("Hide \(appName)", .hide, "h"),
                          standard("Hide Others", .hideOthers, "h", [.command, .option]),
                          standard("Show All", .showAll)]
        let quit = [standard("Quit \(appName)", .quit, "q")]
        let appGroups = [group(.appInfo, about), group(.appVisibility, visibility), group(.appTermination, quit)]
        appendMenu(appName, groups: appGroups)
        let newItem = group(.newItem, [])
        let close = [standard("Close", .close, "w")]
        appendMenu("File", groups: [newItem, close])
        let undoRedo = [standard("Undo", .undo, "z"), standard("Redo", .redo, "z", [.primary, .shift])]
        let pasteboard = [standard("Cut", .cut, "x"), standard("Copy", .copy, "c"), standard("Paste", .paste, "v"),
                          standard("Delete", .delete), standard("Select All", .selectAll, "a")]
        let editGroups = [group(.undoRedo, undoRedo), group(.pasteboard, pasteboard)]
        appendMenu("Edit", groups: editGroups)
        for case .menu(let name, let content) in entries {   // before Window (MN-I item 2)
            let items = number(content().menuNodes(isEnabled: true), enabled: true)
            appendMenu(name, groups: [items])
        }
        let size = [standard("Minimize", .minimize, "m"), standard("Zoom", .zoom)]
        let arrangement = [standard("Bring All to Front", .bringAllToFront)]
        let windowGroups = [group(.windowSize, size), group(.windowArrangement, arrangement)]
        appendMenu("Window", groups: windowGroups)
        let help = group(.help, [])
        if !help.isEmpty { appendMenu("Help", groups: [help]) }   // shown only when something is placed
    }

    /// The drawn arrangement (`SG-A` item 3): the standard items of the
    /// application, File and Window menus dropped (no `PlatformWindow`
    /// minimise, zoom, close or quit exists — `SG-A` item 11), their
    /// placements' additions kept; the Edit menu as AppKit's, its standard
    /// items replaceable exactly as there (`SG-H` item 3); an empty menu
    /// dropped.
    private mutating func buildDrawn() {
        let newItem = group(.newItem, [])
        let visibility = group(.appVisibility, [])
        let termination = group(.appTermination, [])
        appendMenu("File", groups: [newItem, visibility, termination], dropsEmpty: true)
        let undoRedo = [standard("Undo", .undo, "z"), standard("Redo", .redo, "z", [.primary, .shift])]
        let pasteboard = [standard("Cut", .cut, "x"), standard("Copy", .copy, "c"), standard("Paste", .paste, "v"),
                          standard("Delete", .delete), standard("Select All", .selectAll, "a")]
        let editGroups = [group(.undoRedo, undoRedo), group(.pasteboard, pasteboard)]
        appendMenu("Edit", groups: editGroups, dropsEmpty: true)
        for case .menu(let name, let content) in entries {
            let items = number(content().menuNodes(isEnabled: true), enabled: true)
            appendMenu(name, groups: [items], dropsEmpty: true)
        }
        let size = group(.windowSize, [])
        let arrangement = group(.windowArrangement, [])
        appendMenu("Window", groups: [size, arrangement], dropsEmpty: true)
        let help = group(.help, [])
        let info = group(.appInfo, [])
        appendMenu("Help", groups: [help, info], dropsEmpty: true)
    }

    /// A standard item: the platform's own command, its shortcut shown — on
    /// `.primary` unless given (`SG-B` item 3: ⌘ on Apple, Ctrl elsewhere).
    private mutating func standard(_ title: String, _ action: StandardMenuAction, _ key: String? = nil,
                                   _ modifiers: Modifiers = .primary) -> PlatformMenuItem {
        defer { next += 1 }
        return PlatformMenuItem(id: next, kind: .action, title: title,
                                shortcut: key.map { PlatformKeyEquivalent(key: $0, modifiers: modifiers) },
                                standardAction: action)
    }

    /// A placement's items: every `before` addition, then the standard items
    /// (or every `replacing` addition instead), then every `after` addition,
    /// each in declaration order.
    private mutating func group(_ placement: CommandGroupPlacement,
                                _ standardItems: [PlatformMenuItem]) -> [PlatformMenuItem] {
        var before: [PlatformMenuItem] = [], after: [PlatformMenuItem] = []
        var replacement: [PlatformMenuItem]?
        for case .group(placement, let position, let content) in entries {
            let items = number(content().menuNodes(isEnabled: true), enabled: true)
            switch position {
            case .before: before += items
            case .after: after += items
            case .replacing: replacement = (replacement ?? []) + items
            }
        }
        return before + (replacement ?? standardItems) + after
    }

    /// A top-level menu of `groups`, a separator between each two non-empty
    /// ones (the PLAIN arm's separators); with `dropsEmpty`, not appended when
    /// it holds nothing (the drawn style, `SG-A` item 3).
    private mutating func appendMenu(_ title: String, groups: [[PlatformMenuItem]], dropsEmpty: Bool = false) {
        var items: [PlatformMenuItem] = []
        for group in groups where !group.isEmpty {
            if !items.isEmpty {
                items.append(PlatformMenuItem(id: next, kind: .separator, title: "", isEnabled: false))
                next += 1
            }
            items += group
        }
        if dropsEmpty && items.isEmpty { return }
        menus.append(PlatformMenu(token: 0, title: title, items: items))
    }

    /// Command items numbered from `next`, every enabled action recorded and
    /// every enabled shortcut listed (`MN-J` item 1: a disabled one does
    /// nothing).
    private mutating func number(_ nodes: [MenuNode], enabled: Bool) -> [PlatformMenuItem] {
        nodes.map { node in
            let id = next
            next += 1
            let isEnabled = enabled && node.isEnabled
            switch node.kind {
            case .separator:
                return PlatformMenuItem(id: id, kind: .separator, title: "", isEnabled: false)
            case .submenu(let children):
                return PlatformMenuItem(id: id, kind: .submenu(number(children, enabled: isEnabled)),
                                        title: node.title, isEnabled: isEnabled)
            case .text:
                return PlatformMenuItem(id: id, kind: .action, title: node.title, isEnabled: false)
            case .action, .toggle:
                if case .toggle = node.kind { toggles.insert(id) }
                if isEnabled, let run = node.run {
                    actions[id] = run
                    if let shortcut = node.shortcut { shortcuts.append((shortcut, run)) }
                }
                return PlatformMenuItem(id: id, kind: .action, title: node.title, isEnabled: isEnabled,
                                        isOn: node.isOn,
                                        shortcut: node.shortcut.map {
                                            PlatformKeyEquivalent(key: String($0.key.character).lowercased(),
                                                                  modifiers: $0.modifiers)
                                        })
            }
        }
    }
}

extension App {
    /// The menu bar's commands — SwiftUI's `.commands { }` scene modifier as a
    /// method on MetalUI's `App` (ruling `MN-I` item 1, `MN-X` item 2):
    /// `CommandMenu`s inserted before the Window menu, `CommandGroup`s placed
    /// against the standard groups. A second call replaces the first.
    ///
    /// `content` is stored and **re-evaluated** whenever the bar is needed — a
    /// menu opening on AppKit, a keystroke reaching a window's command stage —
    /// so a `Toggle` item's state and a `.disabled` item stay live. A command's
    /// `.keyboardShortcut` fires in every window of this app when nothing in
    /// the window claims the key first — its keymap, a focused field, a raw
    /// `onKey`, a `Button`'s shortcut (`MN-J`) — once either way. On AppKit the
    /// bar is `NSApp.mainMenu`. **Where the platform declines a menu bar** (SDL:
    /// Linux, Windows) every window of the app draws it — a 25-point strip
    /// across the window's top, above a drawn toolbar strip, in the desktop
    /// arrangement: no application menu, File only with additions, Edit, these
    /// `CommandMenu`s, Window only with additions, Help with the `.help` and
    /// `.appInfo` additions (ruling `SG-A`, divergence 195). A title opens its
    /// menu on a click, F10 opens the first; Edit's items reach the focused
    /// text field as their keys. An app that never calls `commands` draws no
    /// bar.
    public func commands<C: Commands>(@CommandsBuilder content: @escaping @MainActor () -> C) {
        commandsContent = { content() }
        installMenuBar()
        if menuBarIsDrawn { for window in windows { window.setNeedsRedraw() } }   // the bar on the next frame
    }

    /// Hands the platform the bar (`MN-I` items 3–4) and keeps its answer
    /// (`SG-A` item 2): called once by every initialiser and again by
    /// `commands(content:)`.
    func installMenuBar() {
        menuBarIsDrawn = !platform.setMenuBar(PlatformMenuBar(
            content: { [weak self] in self?.menuBarContent() ?? [] },
            perform: { [weak self] id in self?.menuBarActions[id]?() }))
    }

    /// One evaluation of the bar (spec §3.6) in `style`'s arrangement.
    func evaluateMenuBar(style: MenuBarStyle = .appKit) -> MenuBarModel {
        MenuBarModel(entries: commandsContent?()._commandEntries().entries ?? [],
                     appName: ProcessInfo.processInfo.processName, style: style)
    }

    /// What every window of this app draws its menu bar from (`SG-A` item 2):
    /// titles only while the platform declined the bar and commands are
    /// declared — read afresh at each build, so `commands(content:)` called
    /// after `openWindow` takes effect — and the drawn menus at an open, their
    /// command items' actions kept for `perform`.
    func drawnMenuBarSource() -> DrawnMenuBarSource {
        DrawnMenuBarSource(
            titles: { [weak self] in
                guard let self, self.menuBarIsDrawn, self.commandsContent != nil else { return nil }
                return self.evaluateMenuBar(style: .drawn).menus.map(\.title)
            },
            menus: { [weak self] in
                guard let self else { return ([], []) }
                let model = self.evaluateMenuBar(style: .drawn)
                self.drawnMenuBarActions = model.actions
                return (model.menus, model.toggles)
            },
            perform: { [weak self] id in self?.drawnMenuBarActions[id]?() })
    }

    /// The bar's menus as they are now, keeping their command items' actions
    /// for `PlatformMenuBar.perform` (spec §3.6).
    func menuBarContent() -> [PlatformMenu] {
        let model = evaluateMenuBar()
        menuBarActions = model.actions
        return model.menus
    }

    /// The enabled command shortcuts, in menu order (`MN-J` item 1), evaluated
    /// now: what every window of this app's command stage matches.
    func enabledCommandShortcuts() -> [(KeyboardShortcut, @MainActor () -> Void)] {
        evaluateMenuBar().shortcuts
    }
}
