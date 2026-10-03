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
        /// The row whose submenu is the next level, if one is open.
        var openSubmenu: Int?

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
    /// The ids of `Toggle` items, which publish as `.menuItemCheckBox` (`MN-R`).
    var toggles: Set<Int> = []
    /// The press that opened the menu, until its release: where it was and
    /// whether the pointer has moved since (`MN-F` item 3's press-drag-release).
    var openingPress: (point: Point<Pixels>, moved: Bool)?

    /// The numbered items of `nodes` (`MN-C`): ids depth-first from `next`,
    /// every item disabled when `enabled` is false (C9), each action recorded
    /// against `declaringID`.
    static func number(_ nodes: [MenuNode], declaringID: GlobalElementID, enabled: Bool, next: inout Int,
                       actions: inout [Int: MenuItemAction], toggles: inout Set<Int>) -> [PlatformMenuItem] {
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
                                   actions: &actions, toggles: &toggles)
                return PlatformMenuItem(id: id, kind: .submenu(items), title: node.title, isEnabled: isEnabled)
            case .text:
                return PlatformMenuItem(id: id, kind: .action, title: node.title, isEnabled: false)
            case .action, .toggle:
                if case .toggle = node.kind { toggles.insert(id) }
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
        guard platform == .other else { return false }
        switch key.charactersIgnoringModifiers {
        case f10: return key.modifiers == .shift
        case menuKey: return key.modifiers.isEmpty
        default: return false
        }
    }
}

// MARK: - Window's menu stages (spec §3.2–§3.3)

extension Window {
    /// The context-menu region a press at `point` reaches (ruling `MN-V`):
    /// the one ranking over opaque pointer hitboxes and the contextual regions
    /// `wanted` accepts, together. A region on top is the target; an opaque
    /// hitbox on top yields the region of its element or its nearest ancestor
    /// with one **on its own layer** containing the point (`IX-Q`'s rule, so a
    /// presentation's hitbox never reaches its declarer's menu); an unrelated
    /// cover blocks (C14). Shared with lane 3's tooltips (`MN-V` item 3).
    func contextualTarget(at point: Point<Pixels>, where wanted: (ContextualAttachment) -> Bool) -> Int? {
        func isRegion(_ box: Hitbox) -> Bool {
            guard !box.opaque, let attachment = box.handlers.contextual else { return false }
            return wanted(attachment)
        }
        guard let top = topmostHitbox(in: lastHitboxes, at: point, where: { $0.opaque || isRegion($0) }) else {
            return nil
        }
        let hit = lastHitboxes[top]
        if isRegion(hit) { return top }
        var cursor: GlobalElementID? = hit.id
        while let id = cursor {
            if let index = lastHitboxes.lastIndex(where: {
                $0.id == id && $0.layer == hit.layer && isRegion($0) && $0.contains(point)
            }) {
                return index
            }
            cursor = id.parent
        }
        return nil
    }

    /// Evaluates `attachment`'s menu — under the declaring element's dispatch
    /// (`ID-F`), with its `isEnabled` (`MN-D` item 4) — numbers it and
    /// presents it at `point`: natively when the platform shows it, else in
    /// the window (`MN-C`, `MN-F`). A new menu replaces an open one. `false`,
    /// and nothing opened, for an empty menu (C10).
    func openContextMenu(_ attachment: ContextualAttachment, isEnabled: Bool, declaringID: GlobalElementID,
                         at point: Point<Pixels>, openingPress: Bool) -> Bool {
        guard let content = attachment.menu else { return false }
        let nodes = StateDispatch.dispatching(to: declaringID) { content().menuNodes(isEnabled: isEnabled) }
        guard !nodes.isEmpty else { return false }
        var next = 1
        var actions: [Int: MenuItemAction] = [:]
        var toggles = Set<Int>()
        let items = MenuSession.number(nodes, declaringID: declaringID, enabled: isEnabled, next: &next,
                                       actions: &actions, toggles: &toggles)
        lastMenuToken += 1
        let menu = PlatformMenu(token: lastMenuToken, items: items)
        menuSession = nil
        if presentMenuOnPlatform(menu, at: point) {
            menuSession = MenuSession(token: menu.token, menu: menu, isNative: true, levels: [], actions: actions,
                                      toggles: toggles, openingPress: nil)
            return true
        }
        let layout = MenuPanel.layout(items: items, textSystem: menuTextSystem, font: menuFont)
        let origin = MenuPanel.place(size: layout.size, at: point, in: contentSizeForDrag)
        menuSession = MenuSession(token: menu.token, menu: menu, isNative: false,
                                  levels: [MenuSession.Level(items: items, layout: layout, origin: origin)],
                                  actions: actions, toggles: toggles,
                                  openingPress: openingPress ? (point, false) : nil)
        return true
    }

    /// Opens a recorded element's menu at its bottom-leading corner — the
    /// keyboard and accessibility openers (`MN-G`).
    func openContextMenu(of id: GlobalElementID, _ record: ContextMenuRecord) -> Bool {
        let corner = Point(x: record.bounds.origin.x,
                           y: Pixels(record.bounds.origin.y.value + record.bounds.size.height.value))
        return openContextMenu(record.attachment, isEnabled: record.isEnabled, declaringID: id, at: corner,
                               openingPress: false)
    }

    /// Dismisses an open in-window menu — a resize, the window losing key
    /// (`MN-F` item 3). A native menu is the platform's to close.
    func dismissInWindowMenu() {
        guard let session = menuSession, !session.isNative else { return }
        menuSession = nil
        setNeedsRedraw()
    }

    /// The context-menu stage (`MN-E`, `MN-C` item 4): a secondary press over
    /// a menu opens it; a native menu's outcome runs its item.
    func dispatchContextMenu(_ event: InputEvent) -> Bool {
        switch event {
        case .rightMouseDown(let mouse):
            guard let index = contextualTarget(at: mouse.position, where: { $0.menu != nil }),
                  let attachment = lastHitboxes[index].handlers.contextual else { return false }
            let region = lastHitboxes[index]
            guard openContextMenu(attachment, isEnabled: region.contextualEnabled, declaringID: region.id,
                                  at: mouse.position, openingPress: true) else { return false }
            if menuSession?.isNative == true { menuClaimsRelease = true }
            return true
        case .menuAction(let outcome):
            // Only the open menu's token; a stale one, a dismissal, a disabled
            // or unknown id runs nothing (`MN-C` item 4).
            guard let session = menuSession, session.token == outcome.menu else { return false }
            menuSession = nil
            if let item = outcome.item, let action = session.actions[item], action.isEnabled {
                runMenuAction(action)
            }
            return true
        default:
            return false
        }
    }

    /// The keyboard opener (`MN-G` item 1): Shift-F10 or the Menu key off
    /// Apple opens the focused element's, or its nearest ancestor's, menu.
    func dispatchContextMenuKey(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event, ContextMenuKeys.opens(key, platform: TextEditing.platform) else {
            return false
        }
        for id in focusChain {
            if let record = lastContextMenus[id] { return openContextMenu(of: id, record) }
        }
        return false
    }

    /// Runs a chosen item from input, under its declaring element's dispatch
    /// (`MN-C` item 4, `ID-F`).
    func runMenuAction(_ action: MenuItemAction) {
        StateDispatch.dispatching(to: action.declaringID) { action.run() }
    }

    /// The open in-window menu's stage (`MN-F` item 3): first after a drag
    /// session, it takes every pointer, wheel and key event while open.
    func dispatchMenuSession(_ event: InputEvent) -> Bool {
        // The release of a press a menu stage claimed.
        switch event {
        case .mouseUp where menuClaimsRelease == false, .rightMouseUp where menuClaimsRelease == true:
            if menuSession == nil || menuSession?.isNative == true {
                menuClaimsRelease = nil
                return true
            }
        default:
            break
        }
        guard var session = menuSession, !session.isNative else { return false }
        switch event {
        case .mouseMoved(let mouse), .mouseDragged(let mouse):
            session.openingPress?.moved = true
            hoverMenu(&session, at: mouse.position)
            menuSession = session
            return true
        case .mouseDown(let mouse), .rightMouseDown(let mouse):
            releasePressForMenu()
            if case .rightMouseDown = event { menuClaimsRelease = true } else { menuClaimsRelease = false }
            guard session.level(at: mouse.position) != nil else {
                menuSession = nil   // an outside press dismisses, consumed with its release
                return true
            }
            session.openingPress = nil
            menuSession = session
            return true
        case .mouseUp(let mouse), .rightMouseUp(let mouse):
            menuClaimsRelease = nil
            let opening = session.openingPress
            session.openingPress = nil
            menuSession = session
            // The opening press's release with no move between chooses nothing.
            if let opening, !opening.moved { return true }
            if let levelIndex = session.level(at: mouse.position),
               let row = session.levels[levelIndex].row(at: mouse.position) {
                activateMenuRow(&session, level: levelIndex, row: row)
            }
            return true
        case .scrollWheel:
            return true
        case .keyDown(let key):
            menuKey(&session, key)
            return true
        case .keyUp, .textComposition:
            return true
        case .textInput(let text):
            // A focused field turns Space into text: it still chooses.
            if text == " " { activateMenuRow(&session, level: session.deepest,
                                             row: session.levels[session.deepest].highlighted) }
            return true
        default:
            return false
        }
    }

    /// Highlights the enabled row under the pointer; hovering a submenu row
    /// opens its submenu, hovering any other row closes deeper levels.
    private func hoverMenu(_ session: inout MenuSession, at point: Point<Pixels>) {
        guard let levelIndex = session.level(at: point),
              let row = session.levels[levelIndex].row(at: point) else { return }
        if session.levels[levelIndex].openSubmenu != row { closeMenuLevels(&session, deeperThan: levelIndex) }
        let level = session.levels[levelIndex]
        session.levels[levelIndex].highlighted = level.isSelectable(row) ? row : nil
        if level.isSelectable(row), case .submenu = level.items[row].kind, level.openSubmenu != row {
            openSubmenu(&session, level: levelIndex, row: row, highlightFirst: false)
        }
    }

    private func closeMenuLevels(_ session: inout MenuSession, deeperThan levelIndex: Int) {
        guard session.levels.count > levelIndex + 1 else { return }
        session.levels.removeSubrange((levelIndex + 1)...)
        session.levels[levelIndex].openSubmenu = nil
    }

    private func openSubmenu(_ session: inout MenuSession, level levelIndex: Int, row: Int, highlightFirst: Bool) {
        guard case .submenu(let children) = session.levels[levelIndex].items[row].kind else { return }
        closeMenuLevels(&session, deeperThan: levelIndex)
        let parent = session.levels[levelIndex]
        let layout = MenuPanel.layout(items: children, textSystem: menuTextSystem, font: menuFont)
        let origin = MenuPanel.placeSubmenu(size: layout.size, row: parent.rowFrame(row), parent: parent.frame,
                                            in: contentSizeForDrag)
        var level = MenuSession.Level(items: children, layout: layout, origin: origin)
        if highlightFirst { level.highlighted = children.indices.first { level.isSelectable($0) } }
        session.levels[levelIndex].openSubmenu = row
        session.levels.append(level)
    }

    /// Chooses an action row (dismissing the menu, then running it) or opens a
    /// submenu row at its first enabled row; a disabled row or separator does
    /// nothing.
    private func activateMenuRow(_ session: inout MenuSession, level levelIndex: Int, row: Int?) {
        guard let row, session.levels[levelIndex].isSelectable(row) else {
            menuSession = session
            return
        }
        let item = session.levels[levelIndex].items[row]
        if case .submenu = item.kind {
            openSubmenu(&session, level: levelIndex, row: row, highlightFirst: true)
            menuSession = session
            return
        }
        menuSession = nil
        if let action = session.actions[item.id], action.isEnabled { runMenuAction(action) }
    }

    /// ↓/↑ over enabled rows without wrapping, → into a submenu, ← out of one,
    /// Return or Space chooses, Escape closes the deepest level; every other
    /// key is swallowed while the menu is open.
    private func menuKey(_ session: inout MenuSession, _ key: KeyEvent) {
        let deepest = session.deepest
        let level = session.levels[deepest]
        switch key.charactersIgnoringModifiers {
        case "\u{f701}", "\u{f700}":
            let down = key.charactersIgnoringModifiers == "\u{f701}"
            let selectable = level.items.indices.filter { level.isSelectable($0) }
            guard let first = selectable.first, let last = selectable.last else { break }
            if let current = level.highlighted, let position = selectable.firstIndex(of: current) {
                session.levels[deepest].highlighted = down ? selectable[min(position + 1, selectable.count - 1)]
                                                           : selectable[max(position - 1, 0)]
            } else {
                session.levels[deepest].highlighted = down ? first : last
            }
        case "\u{f703}":
            if let row = level.highlighted, case .submenu = level.items[row].kind {
                openSubmenu(&session, level: deepest, row: row, highlightFirst: true)
            }
        case "\u{f702}":
            if deepest > 0 { closeMenuLevels(&session, deeperThan: deepest - 1) }
        case "\r", "\u{3}", " ":
            activateMenuRow(&session, level: deepest, row: level.highlighted)
            return
        case "\u{1b}":
            if deepest > 0 {
                closeMenuLevels(&session, deeperThan: deepest - 1)
            } else {
                menuSession = nil
                return
            }
        default:
            break
        }
        menuSession = session
    }

    // MARK: Accessibility (`MN-F` item 4, `MN-AB`)

    /// The window-reserved root every menu node id descends from — never
    /// written to `StateTable` (`theSevenRetentionSlotsAreMutuallyDistinct`
    /// is unmoved).
    static let menuPanelRoot = GlobalElementID(component: .named(ElementID("$menu-panel")), parent: nil)

    static func menuPanelID(level: Int) -> GlobalElementID {
        GlobalElementID.child(of: menuPanelRoot, at: level, name: nil)
    }

    static func menuPanelID(level: Int, row: Int) -> GlobalElementID {
        GlobalElementID.child(of: menuPanelID(level: level), at: row, name: nil)
    }

    /// The `(level, row)` a menu row's node names, if it is one.
    static func menuPanelRow(_ id: GlobalElementID) -> (level: Int, row: Int)? {
        guard let levelID = id.parent, levelID.parent == menuPanelRoot,
              case .positional(let level) = levelID.component, case .positional(let row) = id.component
        else { return nil }
        return (level, row)
    }

    /// Appends the open in-window menu to `build`: one `.menu` node per open
    /// level (a submenu the child of its row), its rows `.menuItem` or
    /// `.menuItemCheckBox`, focus on the deepest highlighted row — a root
    /// after the content's, **after** any modal isolation, so it is published
    /// and pressable inside a modal (`MN-AB`).
    func appendMenuPanel(to build: inout AccessibilityBuild) {
        guard let session = menuSession, !session.isNative else { return }
        var tree = build.tree
        var focused: AccessibilityNodeID?
        for (levelIndex, level) in session.levels.enumerated() {
            let levelID = AccessibilityNodeID(Self.menuPanelID(level: levelIndex))
            var rows: [AccessibilityNodeID] = []
            for (row, item) in level.items.enumerated() {
                if case .separator = item.kind { continue }
                let rowID = AccessibilityNodeID(Self.menuPanelID(level: levelIndex, row: row))
                rows.append(rowID)
                let isToggle = session.toggles.contains(item.id)
                var children: [AccessibilityNodeID] = []
                if level.openSubmenu == row, session.levels.count > levelIndex + 1 {
                    children = [AccessibilityNodeID(Self.menuPanelID(level: levelIndex + 1))]
                }
                tree.nodes[rowID] = AccessibilityNode(
                    role: isToggle ? .menuItemCheckBox : .menuItem, label: item.title,
                    value: isToggle ? (item.isOn ? "1" : "0") : nil, isEnabled: item.isEnabled,
                    actions: item.isEnabled ? .press : [], children: children)
                let frame = level.rowFrame(row)
                tree.geometry[rowID] = AccessibilityGeometry(frame: frame, visibleFrame: frame,
                                                             layer: Int.max, order: Int.max)
                if level.highlighted == row { focused = rowID }
            }
            tree.nodes[levelID] = AccessibilityNode(role: .menu, children: rows)
            tree.geometry[levelID] = AccessibilityGeometry(frame: level.frame, visibleFrame: level.frame,
                                                           layer: Int.max, order: Int.max)
            if levelIndex == 0 { tree.roots.append(levelID) }
        }
        if let focused { tree.focused = focused }
        build.tree = tree
    }

    /// An accessibility press on a menu row (`MN-F` item 4): chooses it, or
    /// opens its submenu. `nil` when `id` is not a row of the open menu.
    func pressMenuRow(_ id: GlobalElementID) -> Bool? {
        guard let (levelIndex, row) = Self.menuPanelRow(id) else { return nil }
        guard var session = menuSession, !session.isNative, session.levels.indices.contains(levelIndex),
              session.levels[levelIndex].isSelectable(row) else { return false }
        activateMenuRow(&session, level: levelIndex, row: row)
        setNeedsRedraw()
        return true
    }
}
