import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUITextSystem

// SMK port gaps, lane 2 — the drawn menu bar (rulings `SG-A`, `SG-H` items
// 1–4; spec `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §3.4).
// Where the platform declines the menu bar (`Platform.setMenuBar` answers
// `false`: SDL), every window of an app that declared `commands` draws it: a
// 25-point strip across its top — above the drawn toolbar strip — its titles
// ordinary elements in their own layout run under the named root `$menubar`,
// the root laid out below both. A title opens its menu through the window's
// in-window menu (`MenuSession`). Divergence 195.

/// The window's drawn menu bar, as `App` hands it to each window (`SG-A`
/// item 2): the titles for a build — `nil` when the window draws no bar — the
/// menus at an open, keeping the app's action table, and the callback a
/// chosen command item runs (`PlatformMenuBar.perform`'s, for the drawn
/// style).
struct DrawnMenuBarSource {
    /// The bar's titles now, or `nil` when no bar is drawn (the platform
    /// shows its own, or the app declared no `commands`). Evaluated for every
    /// build (`SG-A` item 9).
    let titles: @MainActor () -> [String]?
    /// The bar's menus now, in the drawn arrangement, and the ids of its
    /// `Toggle` items; keeps the command items' actions for `perform`.
    let menus: @MainActor () -> (menus: [PlatformMenu], toggles: Set<Int>)
    /// Runs the command item `id` from the last `menus()`, from input.
    let perform: @MainActor (_ id: Int) -> Void
}

/// One title of the drawn bar, keyed by its menu index and title (`SG-A`
/// item 6): a title keeps its identity while both do.
struct MenuBarTitle: Hashable {
    let index: Int
    let title: String
}

/// The drawn bar's geometry and element (`SG-A` items 5–7).
@MainActor
enum MenuBarStrip {
    /// The strip's height: the 24-point bar and the 1-point separator below
    /// (`SG-A` item 5). Part of `Window.drawnChromeHeight`.
    static let height: Float = 25
    /// The bar above the separator: the regular control height (`MD-K` item 1).
    static let barHeight: Float = 24
    /// Each title's horizontal padding.
    static let titlePadding: Float = 8
    /// The row's leading padding.
    static let leadingPadding: Float = 4
    /// The bar's root: a window-owned **named** root, `$menubar` — an element
    /// name, not a `StateTable` slot (the seven retention slots are unmoved).
    /// Its position is `(nil, 2)`, beside the window root's `(nil, 0)` and
    /// `$toolbar`'s `(nil, 1)` (`SG-A` item 6).
    static let rootID = GlobalElementID.child(of: nil, at: rootIndex, name: ElementID("$menubar"))
    /// The cursor index `rootID` is noted at.
    static let rootIndex = 2

    /// Each title's rect in window points: from x 4, each as wide as its text
    /// in the control font plus 8 a side (rounded up), 24 tall at y 0 — the
    /// rects the element lays its titles out at, recorded for the window's
    /// anchor and hover switching.
    static func titleFrames(_ titles: [String], textSystem: any TextSystem, font: FontKey) -> [Bounds<Pixels>] {
        var x = leadingPadding
        return titles.map { title in
            let text = Float(textSystem.measure(title, font: font, wrappingAt: nil).widestLine)
            let width = (text + 2 * titlePadding).rounded(.up)
            defer { x += width }
            return Bounds(origin: Point(x: Pixels(x), y: Pixels(0)),
                          size: Size(width: Pixels(width), height: Pixels(barHeight)))
        }
    }

    /// The bar for `titles` across a window `width` wide: an
    /// `HStack(spacing: 0)` of the titles, each at its `frames` width, padded
    /// 4 at the leading edge, then a `Spacer`; a 1-point `.separator` line
    /// below; filled `.surface`. The title at `openIndex` is filled with the
    /// drawn menu's highlight (`.accent`) and drawn in its highlighted text
    /// colour (`.background`), as `MenuPanel` draws a highlighted row. Keyed
    /// by `MenuBarTitle` (`ForEach(id:)`).
    static func element(titles: [String], frames: [Bounds<Pixels>], openIndex: Int?, width: Float,
                        open: @escaping @MainActor (Int) -> Void) -> AnyElement {
        let keyed = titles.enumerated().map { MenuBarTitle(index: $0.offset, title: $0.element) }
        return AnyElement(
            VStack(spacing: Pixels(0)) {
                HStack(spacing: Pixels(0)) {
                    ForEach(keyed, id: \.self) { item in
                        title(item, width: frames[item.index].size.width.value, isOpen: item.index == openIndex,
                              open: open)
                    }
                    Spacer()
                }
                .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(leadingPadding)))
                .frame(width: Pixels(width), height: Pixels(barHeight))
                Color(.separator).frame(width: Pixels(width), height: Pixels(1))
            }
            .background(.surface))
    }

    /// One title (`SG-A` item 7): `Text` in a frame its text's width plus 8 a
    /// side (the padding, centred) + `.background` + `.onClick` +
    /// `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)` — existing
    /// modifiers only, so no new handler-registering site and no
    /// new accessibility role. Its `onClick` opens the menu on the click's
    /// release (`SG-H` item 4); it takes no focus and is no Tab stop.
    private static func title(_ item: MenuBarTitle, width: Float, isOpen: Bool,
                              open: @escaping @MainActor (Int) -> Void) -> AnyElement {
        let index = item.index
        return AnyElement(
            Text(item.title)
                .foregroundColor(isOpen ? ColorToken.background : ColorToken.textPrimary)
                .frame(width: Pixels(width), height: Pixels(barHeight))
                .background(isOpen ? Color(.accent) : Color.clear)
                .onClick { open(index) }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(.isButton))
    }
}

extension Frame {
    /// Lays out the drawn menu bar for this build, when the window draws one
    /// (`SG-A` items 2, 6): the bar's element, requested under
    /// `MenuBarStrip.rootID` after the toolbar strip, its name noted (`ID-R`),
    /// each title's rect recorded. `nil` otherwise — the window's bar-less
    /// path, unchanged.
    func requestMenuBarStrip(pass: inout LayoutPass) -> (element: AnyElement, node: LayoutNodeID)? {
        guard let titles = menuBarTitles, !titles.isEmpty else { return nil }
        let font = textSystem.resolveFont(MenuPanel.fontDescriptor)
        let frames = MenuBarStrip.titleFrames(titles, textSystem: textSystem, font: font)
        menuBarTitleFrames = frames
        let open = menuBarOpen ?? { _ in }
        var element = MenuBarStrip.element(titles: titles, frames: frames, openIndex: menuBarOpenIndex,
                                           width: contentSize.width.value, open: open)
        stateTable.noteNamed(MenuBarStrip.rootID, at: MenuBarStrip.rootIndex)
        let node = element.requestLayout(MenuBarStrip.rootID, pass: &pass)
        return (element, node)
    }
}

extension Window {
    /// Opens the drawn bar's menu `index` (`SG-A` items 4, 8): evaluates the
    /// bar once — the app's action table kept, so ids match — gives each
    /// command item `PlatformMenuBar.perform`'s action and each standard Edit
    /// item its key (`deliverStandardEditKey`), enabled only while a text
    /// field holds focus (`SG-H` item 1, AppKit's `validateMenuItem`), and
    /// presents it at the title's bottom-leading corner — natively when the
    /// platform shows a menu, else in the window — remembering the bar index.
    /// `highlightFirst` highlights the first enabled row (F10, ← and →).
    func openMenuBarMenu(index: Int, highlightFirst: Bool) {
        guard let source = drawnMenuBarSource, lastMenuBarTitleFrames.indices.contains(index) else { return }
        let (menus, toggles) = source.menus()
        guard menus.indices.contains(index) else { return }
        let editEnabled = focusedElement.flatMap { lastFocusRegistry.textTarget(for: $0) } != nil
        var actions: [Int: MenuItemAction] = [:]
        func adapt(_ items: [PlatformMenuItem]) -> [PlatformMenuItem] {
            items.map { item in
                var item = item
                let id = item.id
                if let action = item.standardAction {
                    item.isEnabled = editEnabled
                    actions[id] = MenuItemAction(run: { [weak self] in self?.deliverStandardEditKey(action) },
                                                 declaringID: MenuBarStrip.rootID, isEnabled: editEnabled)
                    return item
                }
                switch item.kind {
                case .submenu(let children):
                    item.kind = .submenu(adapt(children))
                case .action where item.isEnabled:
                    actions[id] = MenuItemAction(run: { source.perform(id) }, declaringID: MenuBarStrip.rootID,
                                                 isEnabled: true)
                default:
                    break
                }
                return item
            }
        }
        let items = adapt(menus[index].items)
        let title = lastMenuBarTitleFrames[index]
        let corner = Point(x: title.origin.x, y: Pixels(MenuBarStrip.height))
        lastMenuToken += 1
        let menu = PlatformMenu(token: lastMenuToken, title: menus[index].title, items: items)
        menuSession = nil
        if presentMenuOnPlatform(menu, at: corner) {
            menuSession = MenuSession(token: menu.token, menu: menu, isNative: true, levels: [], actions: actions,
                                      toggles: toggles, openingPress: nil, barIndex: index)
            return
        }
        let layout = MenuPanel.layout(items: items, textSystem: menuTextSystem, font: menuFont)
        let clamped = MenuPanel.clampedHeight(layout.size, in: contentSizeForDrag)
        let size = Size(width: layout.size.width, height: Pixels(clamped ?? layout.size.height.value))
        let origin = MenuPanel.place(size: size, at: corner, in: contentSizeForDrag)
        var level = MenuSession.Level(items: items, layout: layout, origin: origin, clampedHeight: clamped)
        if highlightFirst { level.highlighted = items.indices.first { level.isSelectable($0) } }
        menuSession = MenuSession(token: menu.token, menu: menu, isNative: false, levels: [level],
                                  actions: actions, toggles: toggles, openingPress: nil, barIndex: index)
        setNeedsRedraw()
    }

    /// Moves an open bar menu to the adjacent one, wrapping (`SG-A` item 8:
    /// ← and → on a level with no submenu to enter or leave), its first
    /// enabled row highlighted.
    func switchMenuBarMenu(from index: Int, by delta: Int) {
        let count = lastMenuBarTitleFrames.count
        guard count > 0 else { return }
        openMenuBarMenu(index: ((index + delta) % count + count) % count, highlightFirst: true)
    }

    /// F10 with no modifiers, unclaimed by every earlier key stage, opens the
    /// first menu of a window drawing a bar, its first enabled row
    /// highlighted (`SG-A` item 8). Shift+F10 stays the context-menu key.
    func dispatchMenuBarKey(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event, key.charactersIgnoringModifiers == ContextMenuKeys.f10,
              key.modifiers.isEmpty, !lastMenuBarTitleFrames.isEmpty else { return false }
        openMenuBarMenu(index: 0, highlightFirst: true)
        return menuSession != nil
    }
}
