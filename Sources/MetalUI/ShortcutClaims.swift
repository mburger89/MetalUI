import MetalUICore
import MetalUIPlatform

// Ruling `KF-AI` — which keys are already taken. An app that lets its user bind
// shortcuts needs to know what a candidate would collide with: the desktop's own
// keys, the standard menu items, the app's command items. MetalUI-only (class M);
// SwiftUI has no way to ask.

/// A key that something already owns, and who owns it (`KF-AI`).
///
/// MetalUI-only (class M). Compare a candidate with
/// ``KeyboardShortcut/conflicts(with:)``:
///
///     let claims = KeyboardShortcut.systemReserved() + app.standardMenuShortcuts() + app.commandShortcuts()
///     claims.first { $0.shortcut.conflicts(with: candidate) }
///
/// There is deliberately no combined helper: the caller picks the sources and can drop
/// its own items by `identifier`. Titles are English and not localised.
public struct ClaimedShortcut: Hashable, Sendable {
    /// Who owns a claimed shortcut.
    public enum Source: Hashable, Sendable {
        /// The desktop: ``KeyboardShortcut/systemReserved(on:)``.
        case system
        /// A standard menu item (Quit, Copy, Minimize, ...) or the drawn bar's own key:
        /// ``App/standardMenuShortcuts()``.
        case standardMenu
        /// An item of the app's `commands`: ``App/commandShortcuts()``.
        case command
        /// A code view's built-in key binding.
        case codeView
    }

    /// What the key does, in English: the menu item's title, or the system action's name.
    public var title: String
    /// The key and its modifiers.
    public var shortcut: KeyboardShortcut
    /// Who owns it.
    public var source: Source
    /// A command item's `.accessibilityIdentifier`, for a caller to tell its own items from
    /// the rest; `nil` for every other claim and for a command item with none.
    public var identifier: String?
    /// Whether the owner takes the key only sometimes: ``condition`` says when. A conditional
    /// claim is still reported, because a key that is free now may not be later.
    public var isConditional: Bool
    /// When a conditional claim applies (`"only with find matches"`); `nil` when it always does.
    public var condition: String?

    /// A claim; unconditional and with no identifier unless given.
    public init(title: String, shortcut: KeyboardShortcut, source: Source, identifier: String? = nil,
                isConditional: Bool = false, condition: String? = nil) {
        self.title = title
        self.shortcut = shortcut
        self.source = source
        self.identifier = identifier
        self.isConditional = isConditional
        self.condition = condition
    }
}

extension KeyboardShortcut {
    /// The keys `platform`'s desktop takes before an app sees them, at the desktop's **default**
    /// settings (`KF-AI`): a fixed list per platform, in the order it is written, each with
    /// source `.system`. MetalUI does not read the user's own settings (the macOS symbolic hotkeys,
    /// gsettings, the registry); a later release can, without changing this API.
    ///
    /// - macOS: ⌘Tab, ⇧⌘Tab, ⌘`, ⌘Space, ⌥⌘Space, ⌃Space, ⌃⌥Space, ⌃↑ ⌃↓ ⌃← ⌃→, ⇧⌘3 ⇧⌘4 ⇧⌘5, ⌃⇧⌘3 ⌃⇧⌘4,
    ///   ⌃⌘Q, ⌥⌘Esc, ⌥⌘D, ⌃⌘Space, ⌃F2 to ⌃F8, F11.
    /// - Windows: Alt+Tab and its relatives, Alt+F4, Alt+Space, Ctrl+Esc, Ctrl+Shift+Esc, Ctrl+Alt+Delete,
    ///   Win+D/E/L/R/I/A/N/S/V/Tab/./Space, Win+Shift+S, Win+arrows, Win+Shift+←/→, Win+Ctrl+D/←/→/F4.
    /// - Linux (GNOME defaults): Alt+Tab and Super+Tab with and without Shift, Alt+`, Alt+F2/F4/F7/F8/F10,
    ///   Alt+Space, Super+L/A/V, Super+arrows, Super+Page Up/Down, Super+Shift+Page Up/Down, Super+Space,
    ///   Super+Shift+Space, Ctrl+Alt+Delete, Ctrl+Alt+T.
    ///
    /// The list is for `platform` whatever the host is: a shortcut names its modifiers outright
    /// (⌘ is `.command`, the Win/Super key is `.command` too), not `.primary`. No two entries
    /// conflict. Fn chords and Print Screen cannot be written as a `KeyboardShortcut` and are
    /// left out; on Windows the window is closed by SDL after Alt+F4.
    public static func systemReserved(on platform: Platform = .current) -> [ClaimedShortcut] {
        let claims: [(String, KeyEquivalent, EventModifiers)]
        switch platform {
        case .macOS: claims = macOSReserved
        case .windows: claims = windowsReserved
        case .linux: claims = linuxReserved
        }
        return claims.map { title, key, modifiers in
            ClaimedShortcut(title: title, shortcut: KeyboardShortcut(key, modifiers: modifiers), source: .system)
        }
    }

    /// Function key `n` (1...35) as a key equivalent, AppKit's `NSF1FunctionKey` + n - 1.
    fileprivate static func functionKey(_ n: Int) -> KeyEquivalent {
        KeyEquivalent(Character(Unicode.Scalar(UInt32(0xF704 + n - 1))!))
    }

    private static var macOSReserved: [(String, KeyEquivalent, EventModifiers)] {
        let cmd: EventModifiers = .command, ctrl: EventModifiers = .control
        var list: [(String, KeyEquivalent, EventModifiers)] = [
            ("Switch Application", .tab, cmd),
            ("Switch Application Backwards", .tab, [.command, .shift]),
            ("Switch Window of Application", "`", cmd),
            ("Spotlight Search", .space, cmd),
            ("Finder Search", .space, [.command, .option]),
            ("Next Input Source", .space, ctrl),
            ("Previous Input Source", .space, [.control, .option]),
            ("Mission Control", .upArrow, ctrl),
            ("Application Windows", .downArrow, ctrl),
            ("Move Left a Space", .leftArrow, ctrl),
            ("Move Right a Space", .rightArrow, ctrl),
            ("Screenshot of Entire Screen", "3", [.command, .shift]),
            ("Screenshot of Selection", "4", [.command, .shift]),
            ("Screenshot and Recording Options", "5", [.command, .shift]),
            ("Screenshot of Entire Screen to Clipboard", "3", [.control, .command, .shift]),
            ("Screenshot of Selection to Clipboard", "4", [.control, .command, .shift]),
            ("Lock Screen", "q", [.control, .command]),
            ("Force Quit", .escape, [.option, .command]),
            ("Show or Hide the Dock", "d", [.option, .command]),
            ("Character Viewer", .space, [.control, .command]),
        ]
        for n in 2...8 { list.append(("Move Focus (Full Keyboard Access)", functionKey(n), ctrl)) }
        list.append(("Show Desktop", functionKey(11), []))
        return list
    }

    private static var windowsReserved: [(String, KeyEquivalent, EventModifiers)] {
        let alt: EventModifiers = .option, win: EventModifiers = .command, ctrl: EventModifiers = .control
        return [
            ("Switch Windows", .tab, alt),
            ("Switch Windows Backwards", .tab, [.option, .shift]),
            ("Switch Windows (Stays Open)", .tab, [.control, .option]),
            ("Cycle Through Windows", .escape, alt),
            ("Close Window", functionKey(4), alt),
            ("Window Menu", .space, alt),
            ("Start Menu", .escape, ctrl),
            ("Task Manager", .escape, [.control, .shift]),
            ("Security Options", .deleteForward, [.control, .option]),
            ("Show Desktop", "d", win),
            ("File Explorer", "e", win),
            ("Lock", "l", win),
            ("Run", "r", win),
            ("Settings", "i", win),
            ("Quick Settings", "a", win),
            ("Notifications", "n", win),
            ("Search", "s", win),
            ("Clipboard History", "v", win),
            ("Task View", .tab, win),
            ("Emoji Panel", ".", win),
            ("Switch Input Method", .space, win),
            ("Screenshot Selection", "s", [.command, .shift]),
            ("Maximize Window", .upArrow, win),
            ("Restore or Minimize Window", .downArrow, win),
            ("Snap Window Left", .leftArrow, win),
            ("Snap Window Right", .rightArrow, win),
            ("Move Window to Left Monitor", .leftArrow, [.command, .shift]),
            ("Move Window to Right Monitor", .rightArrow, [.command, .shift]),
            ("New Virtual Desktop", "d", [.command, .control]),
            ("Previous Virtual Desktop", .leftArrow, [.command, .control]),
            ("Next Virtual Desktop", .rightArrow, [.command, .control]),
            ("Close Virtual Desktop", functionKey(4), [.command, .control]),
        ]
    }

    private static var linuxReserved: [(String, KeyEquivalent, EventModifiers)] {
        let alt: EventModifiers = .option, sup: EventModifiers = .command
        return [
            ("Switch Windows", .tab, alt),
            ("Switch Windows Backwards", .tab, [.option, .shift]),
            ("Switch Applications", .tab, sup),
            ("Switch Applications Backwards", .tab, [.command, .shift]),
            ("Switch Windows of Application", "`", alt),
            ("Run Command", functionKey(2), alt),
            ("Close Window", functionKey(4), alt),
            ("Move Window", functionKey(7), alt),
            ("Resize Window", functionKey(8), alt),
            ("Toggle Maximize Window", functionKey(10), alt),
            ("Window Menu", .space, alt),
            ("Lock Screen", "l", sup),
            ("Show Applications", "a", sup),
            ("Show Notification List", "v", sup),
            ("Maximize Window", .upArrow, sup),
            ("Restore Window", .downArrow, sup),
            ("Tile Window Left", .leftArrow, sup),
            ("Tile Window Right", .rightArrow, sup),
            ("Switch to Next Workspace", .pageDown, sup),
            ("Switch to Previous Workspace", .pageUp, sup),
            ("Move Window to Next Workspace", .pageDown, [.command, .shift]),
            ("Move Window to Previous Workspace", .pageUp, [.command, .shift]),
            ("Next Input Source", .space, sup),
            ("Previous Input Source", .space, [.command, .shift]),
            ("Log Out", .deleteForward, [.control, .option]),
            ("Open Terminal", "t", [.control, .option]),
        ]
    }
}

extension App {
    /// The standard menu items' keys, in menu order (`KF-AI`): what the platform's own items claim,
    /// each with source `.standardMenu` and its title (`"Quit <app name>"`).
    ///
    /// **The list follows the bar this platform and app have.** On AppKit (the Mac) it is Hide, Hide
    /// Others, Quit, Close, Undo, Redo, Cut, Copy, Paste, Select All, Minimize. Where the platform
    /// declines a menu bar and the window draws it (SDL: Linux, Windows) it is Undo, Redo, Cut, Copy,
    /// Paste and Select All (Close and Quit show no shortcut there), then the drawn bar's own keys: F10 "Open
    /// Menu Bar", Shift-F10 and the Menu key "Show Context Menu" — the same before and after `commands`
    /// is called. A `CommandGroup(replacing:)` removes its group's standard keys, so the list
    /// reflects it. The keys AppKit adds itself (Full Screen, Emoji & Symbols) are not listed:
    /// they cannot be observed from MetalUI's menu model (probe `P2`, record 363).
    ///
    /// A method, not a property: it evaluates the `commands` content once. **Calling it from inside
    /// the `commands` content recurses without end.**
    public func standardMenuShortcuts() -> [ClaimedShortcut] {
        var claims = menuItemClaims(standard: true)
        if menuBarIsDrawn {
            let f10 = KeyEquivalent(Character(ContextMenuKeys.f10))
            let menuKey = KeyEquivalent(Character(ContextMenuKeys.menuKey))
            claims.append(ClaimedShortcut(title: "Open Menu Bar", shortcut: KeyboardShortcut(f10, modifiers: []),
                                          source: .standardMenu))
            claims.append(ClaimedShortcut(title: "Show Context Menu", shortcut: KeyboardShortcut(f10, modifiers: .shift),
                                          source: .standardMenu))
            claims.append(ClaimedShortcut(title: "Show Context Menu", shortcut: KeyboardShortcut(menuKey, modifiers: []),
                                          source: .standardMenu))
        }
        return claims
    }

    /// Every key the app's `commands` items bind, in menu order (`KF-AI`), each with source `.command`,
    /// the item's title and its `.accessibilityIdentifier`.
    ///
    /// **Disabled items are included**, and so are items in submenus and `Toggle`s: the item owns
    /// its key either way, and the answer does not change from one call to the next. Items with
    /// no shortcut are left out. The key is the lower-cased spelling the menu shows (`"P"` is `"p"`).
    ///
    /// A method, not a property: it evaluates the `commands` content once. **Calling it from inside
    /// the `commands` content recurses without end.**
    public func commandShortcuts() -> [ClaimedShortcut] {
        menuItemClaims(standard: false)
    }

    /// The bar as it evaluates now, in this platform's arrangement, walked in menu order for the
    /// items with a shortcut: the standard ones, or the command ones.
    private func menuItemClaims(standard: Bool) -> [ClaimedShortcut] {
        let model = evaluateMenuBar(style: menuBarIsDrawn ? .drawn : .appKit)
        var claims: [ClaimedShortcut] = []
        func walk(_ items: [PlatformMenuItem]) {
            for item in items {
                switch item.kind {
                case .separator: break
                case .submenu(let children): walk(children)
                case .action:
                    guard (item.standardAction != nil) == standard, let key = item.shortcut,
                          key.key.count == 1, let character = key.key.first else { continue }
                    claims.append(ClaimedShortcut(title: item.title,
                                                  shortcut: KeyboardShortcut(KeyEquivalent(character), modifiers: key.modifiers),
                                                  source: standard ? .standardMenu : .command,
                                                  identifier: standard ? nil : item.accessibilityIdentifier))
                }
            }
        }
        for menu in model.menus { walk(menu.items) }
        return claims
    }
}
