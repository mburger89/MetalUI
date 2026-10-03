#if os(macOS)
import AppKit
import MetalUICore
import MetalUIPlatform

// Menus, popovers and tooltips, lane 2 — AppKit's native menus (rulings `MN-C`,
// `MN-I`, `MN-J`, `MN-K`, `MN-AA`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §3.5). A
// `PlatformMenu` becomes an `NSMenu` — a context menu popped up by
// `AppKitWindow.presentMenu`, or one of the main menu's menus installed by
// `AppKitPlatform.setMenuBar`. SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift` (C1: the `NSMenu` SwiftUI builds)
// and `docs/probes/swiftui-commands.swift` (PLAIN: the main menu's selectors).

/// Where a native context menu's chosen item lands (`MN-C` item 4): every
/// action item targets one of these, its `tag` the item's id.
@MainActor
final class AppKitMenuTarget: NSObject {
    /// The chosen item's id, `nil` until one is chosen.
    private(set) var chosen: Int?

    /// The action of every action item.
    @objc func choose(_ sender: NSMenuItem) { chosen = sender.tag }
}

/// Builds `NSMenu`s from `PlatformMenu`s (`MN-C` item 2, `MN-I` item 3):
/// titles, separators, submenus, on states, disabled items and key equivalents
/// with their modifier mask, `autoenablesItems = false` on every level (C1 reads
/// `autoenables=false`), so an item's enabled state is the model's alone.
@MainActor
enum AppKitMenuBuilder {
    /// A context menu: every action item targets `target`'s `choose(_:)`.
    static func menu(from menu: PlatformMenu, target: AppKitMenuTarget) -> NSMenu {
        let built = NSMenu(title: menu.title)
        fill(built, with: menu.items) { item, _ in
            item.target = target
            item.action = #selector(AppKitMenuTarget.choose(_:))
        }
        return built
    }

    /// Replaces `menu`'s items with `items`; `configure` sets each action
    /// item's target and action.
    static func fill(_ menu: NSMenu, with items: [PlatformMenuItem],
                     configure: (NSMenuItem, PlatformMenuItem) -> Void) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let children):
                let built = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: item.title)
                fill(submenu, with: children, configure: configure)
                built.submenu = submenu
                built.isEnabled = item.isEnabled
                menu.addItem(built)
            case .action:
                let built = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.shortcut?.key ?? "")
                if let shortcut = item.shortcut { built.keyEquivalentModifierMask = mask(shortcut.modifiers) }
                built.tag = item.id
                built.isEnabled = item.isEnabled
                built.state = item.isOn ? .on : .off
                configure(built, item)
                menu.addItem(built)
            }
        }
    }

    /// AppKit's modifier mask for `modifiers`.
    static func mask(_ modifiers: Modifiers) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.control) { mask.insert(.control) }
        return mask
    }

    /// AppKit's own action for a standard item (`MN-I` item 3; the commands
    /// probe's PLAIN arm), and whether it targets `NSApp` rather than the
    /// responder chain.
    static func selector(for action: StandardMenuAction) -> (selector: Selector, targetsApplication: Bool) {
        switch action {
        case .about: (#selector(NSApplication.orderFrontStandardAboutPanel(_:)), true)
        case .hide: (#selector(NSApplication.hide(_:)), true)
        case .hideOthers: (#selector(NSApplication.hideOtherApplications(_:)), true)
        case .showAll: (#selector(NSApplication.unhideAllApplications(_:)), true)
        case .quit: (#selector(NSApplication.terminate(_:)), true)
        case .close: (#selector(NSWindow.performClose(_:)), false)
        case .undo: (#selector(MetalHostView.undo(_:)), false)
        case .redo: (#selector(MetalHostView.redo(_:)), false)
        case .cut: (#selector(MetalHostView.cut(_:)), false)
        case .copy: (#selector(MetalHostView.copy(_:)), false)
        case .paste: (#selector(MetalHostView.paste(_:)), false)
        case .delete: (#selector(MetalHostView.delete(_:)), false)
        case .selectAll: (#selector(NSResponder.selectAll(_:)), false)
        case .minimize: (#selector(NSWindow.performMiniaturize(_:)), false)
        case .zoom: (#selector(NSWindow.performZoom(_:)), false)
        case .bringAllToFront: (#selector(NSApplication.arrangeInFront(_:)), true)
        }
    }
}

/// The installed menu bar's AppKit half (`MN-I` item 3): one `NSMenu` per
/// top-level menu, each rebuilt from a fresh `content()` when it opens
/// (`menuNeedsUpdate`), standard items mapped to AppKit's selectors and
/// command items to `perform`.
@MainActor
final class AppKitMenuBar: NSObject, NSMenuDelegate {
    private let bar: PlatformMenuBar

    init(_ bar: PlatformMenuBar) { self.bar = bar }

    /// The main menu, built from `content()` now.
    func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "Main")
        for menu in bar.content() {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: menu.title)
            submenu.delegate = self
            fill(submenu, with: menu.items)
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    /// Rebuilds `menu` from the bar's content as it is now — a toggle's state
    /// and a disabled item stay live (`MN-I` item 1). Matched by title, a
    /// top-level menu's only identity across evaluations.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let fresh = bar.content().first(where: { $0.title == menu.title }) else { return }
        fill(menu, with: fresh.items)
    }

    private func fill(_ menu: NSMenu, with items: [PlatformMenuItem]) {
        AppKitMenuBuilder.fill(menu, with: items) { built, item in
            if let standard = item.standardAction {
                let (selector, targetsApplication) = AppKitMenuBuilder.selector(for: standard)
                built.action = selector
                built.target = targetsApplication ? NSApplication.shared : nil
            } else {
                built.action = #selector(performCommand(_:))
                built.target = self
            }
        }
    }

    /// A command item's action: the bar's `perform` with its id.
    @objc func performCommand(_ sender: NSMenuItem) { bar.perform(sender.tag) }
}

// MARK: - The host view's Edit actions (`MN-K`, `MN-AA`)

extension MetalHostView {
    /// The Edit menu's Cut: ⌘X to the window (`MN-K`).
    @objc func cut(_ sender: Any?) { deliverEditKey("x", .command) }
    /// The Edit menu's Copy: ⌘C to the window.
    @objc func copy(_ sender: Any?) { deliverEditKey("c", .command) }
    /// The Edit menu's Paste: ⌘V to the window.
    @objc func paste(_ sender: Any?) { deliverEditKey("v", .command) }
    /// The Edit menu's Undo: ⌘Z to the window.
    @objc func undo(_ sender: Any?) { deliverEditKey("z", .command) }
    /// The Edit menu's Redo: ⇧⌘Z to the window.
    @objc func redo(_ sender: Any?) { deliverEditKey("z", [.command, .shift]) }
    /// The Edit menu's Select All: ⌘A to the window.
    override func selectAll(_ sender: Any?) { deliverEditKey("a", .command) }
    /// The Edit menu's Delete: the Delete key to the window.
    @objc func delete(_ sender: Any?) { deliverEditKey("\u{7f}", []) }

    /// Delivers the key an Edit item names to the window as a `.keyDown` — one
    /// path with the keystroke into a focused field's editing keys (`MN-K`) —
    /// **unless the event AppKit is dispatching is the key equivalent the
    /// window already declined** (`MN-AA`): the menu then matched a key the
    /// window has seen once, and it is not delivered a second time. A menu
    /// click (a mouse event current) delivers.
    private func deliverEditKey(_ key: String, _ modifiers: Modifiers) {
        if let current = currentEvent(), let offered = lastOfferedKeyEquivalent, current === offered { return }
        _ = onInput?(.keyDown(KeyEvent(charactersIgnoringModifiers: key, characters: key, modifiers: modifiers,
                                                       timestamp: currentEvent()?.timestamp ?? 0)))
    }

    /// The selectors `deliverEditKey` answers for.
    static let editActions: Set<Selector> = [
        #selector(cut(_:)), #selector(copy(_:)), #selector(paste(_:)), #selector(undo(_:)),
        #selector(redo(_:)), #selector(selectAll(_:)), #selector(delete(_:)),
    ]
}

extension MetalHostView: NSMenuItemValidation {
    /// The Edit items are enabled only while a text field is focused — a caret
    /// is set (`MN-K`); any other item is not the host view's to disable.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action, Self.editActions.contains(action) else { return true }
        return textInputCaret != nil
    }
}
#endif
