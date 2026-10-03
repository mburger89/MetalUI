import MetalUICore
import MetalUIPlatform
import MetalUITextSystem

// Menus, popovers and tooltips, lane 1 — an open menu (rulings `MN-C` item 4,
// `MN-F`; spec §3.2–§3.3). One per window, owned by `Window` — never an element
// in the app's tree, so it has no id, no `StateTable` entry and no identity
// level anywhere (`MN-F`). A native menu (AppKit) keeps only its token table
// until its `.menuAction` arrives; an in-window menu also keeps its levels,
// which the window paints after everything else and publishes as a `.menu`.

/// What choosing a menu item runs (`MN-C` item 4): its action, under the
/// declaring element's dispatch (`ID-F`), if it is enabled.
struct MenuItemAction {
    let run: @MainActor () -> Void
    let declaringID: GlobalElementID
    let isEnabled: Bool
}

/// A context menu an element declared, as the last frame recorded it (spec
/// §3.1): the attachment, whether the element was enabled, and its bounds in
/// window points — the keyboard and accessibility openers' anchor.
struct ContextMenuRecord {
    let attachment: ContextualAttachment
    let isEnabled: Bool
    let bounds: Bounds<Pixels>
}

/// The window's open menu (`MN-C`, `MN-F`).
struct MenuSession {
    /// One open level of an in-window menu: the root, then each open submenu.
    struct Level {
        var items: [PlatformMenuItem]
        var layout: MenuPanel.Layout
        var origin: Point<Pixels>
        /// The highlighted row — an enabled, non-separator item — if any.
        var highlighted: Int?

        /// The panel's rect in window points.
        var frame: Bounds<Pixels> { Bounds(origin: origin, size: layout.size) }

        /// Row `index`'s rect in window points.
        func rowFrame(_ index: Int) -> Bounds<Pixels> {
            let row = layout.rows[index]
            return Bounds(origin: Point(x: Pixels(origin.x.value + row.origin.x.value),
                                        y: Pixels(origin.y.value + row.origin.y.value)),
                          size: row.size)
        }

        /// The row under `point`, if any.
        func row(at point: Point<Pixels>) -> Int? {
            layout.rows.indices.first { rowFrame($0).contains(point) }
        }

        /// Whether row `index` can be highlighted: enabled and not a separator.
        func isSelectable(_ index: Int) -> Bool {
            guard items.indices.contains(index), items[index].isEnabled else { return false }
            if case .separator = items[index].kind { return false }
            return true
        }
    }

    /// Echoed by the platform's `.menuAction` (`MN-C` item 4).
    let token: Int
    /// The menu presented.
    let menu: PlatformMenu
    /// Whether the platform showed it (`presentMenu` answered `true`): then
    /// there are no levels and the window draws nothing.
    let isNative: Bool
    /// The open levels of an in-window menu, root first; empty when native.
    var levels: [Level]
    /// Every item id's action (`MN-C` item 4).
    let actions: [Int: MenuItemAction]
    /// The press that opened the menu, until its release: where it was and
    /// whether the pointer has moved since (`MN-F` item 3's press-drag-release).
    var openingPress: (point: Point<Pixels>, moved: Bool)?

    /// The numbered items of `nodes` (`MN-C`): ids depth-first from `next`,
    /// every item disabled when `enabled` is false (C9), each action recorded
    /// against `declaringID`.
    static func number(_ nodes: [MenuNode], declaringID: GlobalElementID, enabled: Bool, next: inout Int,
                       actions: inout [Int: MenuItemAction]) -> [PlatformMenuItem] {
        nodes.map { node in
            let id = next
            next += 1
            let isEnabled = enabled && node.isEnabled
            let shortcut = node.shortcut.map {
                PlatformKeyEquivalent(key: String($0.key.character).lowercased(), modifiers: $0.modifiers)
            }
            switch node.kind {
            case .separator:
                return PlatformMenuItem(id: id, kind: .separator, title: "", isEnabled: false)
            case .submenu(let children):
                let items = number(children, declaringID: declaringID, enabled: isEnabled, next: &next,
                                   actions: &actions)
                return PlatformMenuItem(id: id, kind: .submenu(items), title: node.title, isEnabled: isEnabled)
            case .text:
                return PlatformMenuItem(id: id, kind: .action, title: node.title, isEnabled: false)
            case .action, .toggle:
                if let run = node.run {
                    actions[id] = MenuItemAction(run: run, declaringID: declaringID, isEnabled: isEnabled)
                }
                return PlatformMenuItem(id: id, kind: .action, title: node.title, isEnabled: isEnabled,
                                        isOn: node.isOn, shortcut: shortcut)
            }
        }
    }

    /// The deepest level's index.
    var deepest: Int { levels.count - 1 }

    /// The deepest level containing `point`, if any.
    func level(at point: Point<Pixels>) -> Int? {
        levels.indices.last { levels[$0].frame.contains(point) }
    }
}

/// The context-menu keys (ruling `MN-G` item 1): Shift-F10 and the Menu key
/// off Apple; never on a Mac, which has no context-menu key.
enum ContextMenuKeys {
    /// AppKit's `NSF10FunctionKey`, which SDL's F10 maps to.
    static let f10 = "\u{f70d}"
    /// AppKit's `NSMenuFunctionKey`, which SDL's `SDLK_APPLICATION` maps to.
    static let menuKey = "\u{f735}"

    /// Whether `key` opens the focused element's context menu on `platform`.
    static func opens(_ key: KeyEvent, platform: TextEditing.Platform) -> Bool {
        false  // STUB (red first)
    }
}
