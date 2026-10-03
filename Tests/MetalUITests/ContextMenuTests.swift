import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Menus, popovers and tooltips, lane 1, tests 1.1–1.30 and 1.33–1.37 (rulings
// `MN-B`…`MN-H`, `MN-Q`, `MN-R`, `MN-U`, `MN-V`, `MN-AB`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §6.1). Every
// SwiftUI answer is an arm of `docs/probes/swiftui-menus-popovers.swift`
// (named per test); the rest is MetalUI's own, ruled.
//
// Everything runs through a real `Window` on a 400 × 400 `FakePlatformWindow`
// — nothing sleeps. `presentsMenusNatively` picks the platform's answer to
// `presentMenu`: `true` stands for AppKit's native `NSMenu` (a choice then
// arrives as `.menuAction`), `false` for SDL (the window draws the menu).

// MARK: - Fixtures

@MainActor
private final class MLog {
    var entries: [String] = []
    var flag = true
    var text = "abc"
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func rdown(_ x: Float, _ y: Float, _ mods: Modifiers = []) -> InputEvent {
    .rightMouseDown(MouseEvent(position: pt(x, y), modifiers: mods))
}
private func rup(_ x: Float, _ y: Float) -> InputEvent { .rightMouseUp(MouseEvent(position: pt(x, y))) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func dragged(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}
private let downArrow = "\u{f701}", upArrow = "\u{f700}", leftArrow = "\u{f702}", rightArrow = "\u{f703}"
private let returnKey = "\r", escapeKey = "\u{1b}"
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}
private func r(_ p: Point<Pixels>) -> InputEvent { .rightMouseDown(MouseEvent(position: p)) }
private func ru(_ p: Point<Pixels>) -> InputEvent { .rightMouseUp(MouseEvent(position: p)) }
private func l(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func lu(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }
private func mv(_ p: Point<Pixels>) -> InputEvent { .mouseMoved(MouseEvent(position: p)) }

/// A 400 × 400 window over `content`, one frame drawn. **A `Window` is held
/// only weakly by its platform window**, so every test keeps the window to its
/// end (`withExtendedLifetime`).
@MainActor
private func menuWindow<Root: Element>(native: Bool = true,
                                       _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, content: content)
    platform.presentsMenusNatively = native
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// The non-opaque contextual regions carrying a menu.
@MainActor private func regions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { !$0.opaque && $0.handlers.contextual?.menu != nil }
}

/// A menu's items as strings: `id title`, `▸[children]` for a submenu, `✓`
/// for on, `(disabled)`, `⌘k` for a shortcut.
private func describe(_ items: [PlatformMenuItem]) -> [String] {
    items.map { item in
        var s = "\(item.id) "
        switch item.kind {
        case .separator: return "\(item.id) ---"
        case .submenu(let children): s += "\(item.title)▸[\(describe(children).joined(separator: ", "))]"
        case .action: s += item.title
        }
        if item.isOn { s += " ✓" }
        if !item.isEnabled { s += " (disabled)" }
        if let k = item.shortcut { s += " \(k.modifiers == .command ? "⌘" : "?")\(k.key)" }
        return s
    }
}

/// Every item, submenus flattened depth-first.
private func flatten(_ items: [PlatformMenuItem]) -> [PlatformMenuItem] {
    items.flatMap { item -> [PlatformMenuItem] in
        if case .submenu(let children) = item.kind { return [item] + flatten(children) }
        return [item]
    }
}

/// The probe's C1 shape in MetalUI's vocabulary: Copy, Delete, a separator,
/// More ▸ [A, B], Flag (a toggle over `log.flag`), Off (disabled), Short (⌘K),
/// a disabled text item.
@MenuContentBuilder @MainActor
private func fullMenuContent(_ log: MLog) -> MenuItems {
    Button("Copy") { log.entries.append("copy") }
    Button("Delete") { log.entries.append("delete") }
    Divider()
    Menu("More") {
        Button("A") { log.entries.append("a") }
        Button("B") { log.entries.append("b") }
    }
    Toggle("Flag", isOn: Binding(get: { log.flag }, set: { log.flag = $0; log.entries.append("flag=\($0)") }))
    Button("Off") { log.entries.append("off") }.disabled(true)
    Button("Short") { log.entries.append("short") }.keyboardShortcut("k")
    Text("Plain")
}

private let fullMenuDescription = ["1 Copy", "2 Delete", "3 ---", "4 More▸[5 A, 6 B]", "7 Flag ✓",
                                   "8 Off (disabled)", "9 Short ⌘k", "10 Plain (disabled)"]

/// A 400 × 400 card filling the window, carrying `fullMenu`.
@MainActor private func card(_ log: MLog) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(400), height: px(400)).contextMenu { fullMenuContent(log) }
}

/// The open in-window menu, required.
@MainActor private func panel(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws
    -> MenuSession {
    let session = try #require(window.menuSession, "an in-window menu is open", sourceLocation: sourceLocation)
    try #require(!session.isNative && !session.levels.isEmpty, "drawn, not native", sourceLocation: sourceLocation)
    return session
}

// MARK: - 1.1–1.15: opening and choosing (native presentation)

/// **1.1** (C1, C5r). A right press over an element with a context menu
/// presents its items to the platform once, at the press point: titles, a
/// separator, a submenu, an on toggle, a disabled item, a shown ⌘K and a
/// disabled text item, numbered depth-first. Mutation: `Divider` emits nothing.
@MainActor
@Test func aRightPressOverAContextMenuPresentsItsItemsToThePlatform() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    try #require(regions(window).count == 1, "the card registers one contextual region")
    #expect(platform.simulateInput(rdown(120, 80)), "the press is claimed")
    try #require(platform.presentedMenus.count == 1, "one presentMenu call")
    #expect(platform.presentedMenus[0].at == pt(120, 80), "at the press point")
    #expect(describe(platform.presentedMenus[0].menu.items) == fullMenuDescription)
    #expect(platform.simulateInput(rup(120, 80)), "the release of a press that opened a menu is claimed")
    #expect(log.entries.isEmpty, "opening runs nothing")
    withExtendedLifetime(window) {}
}

/// A `Component` whose context menu writes its own `@State`.
private struct MenuCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        Box().frame(width: px(200), height: px(400)).contextMenu { Button("Inc") { count += 1 } }
    }
}

/// **1.2** (`MN-C` item 4, `ID-F`). One component VALUE placed twice: choosing
/// the first occurrence's item writes the first occurrence's `@State` — the
/// action runs from input under `StateDispatch` for the declaring element.
/// Without it the write reaches the last-bound occurrence, the second.
/// Mutation: the action run outside `StateDispatch.dispatching`.
@MainActor
@Test func aChosenItemRunsItsActionFromInputUnderStateDispatch() throws {
    let (window, platform) = try menuWindow {
        let counter = MenuCounter()
        return controlRoot(width: 400, height: 400) { counter; counter }
    }
    let components = [controlID([0, 0]), controlID([0, 1])]
    func counts() -> [Int] {
        components.map {
            window.stateTable.peek(GlobalElementID.child(of: $0, at: 0, name: ElementID("$state0")), as: Int.self) ?? 0
        }
    }
    try #require(regions(window).count == 2, "each occurrence registers a region")
    platform.simulateInput(rdown(100, 200))
    platform.simulateInput(rup(100, 200))
    let menu = try #require(platform.presentedMenus.last?.menu)
    #expect(platform.simulateInput(.menuAction(MenuActionEvent(menu: menu.token, item: 1))))
    #expect(counts() == [1, 0], "the first occurrence's slot; last-bound dispatch reads [0, 1]")
    withExtendedLifetime(window) {}
}

/// **1.3** (`MN-C` item 4). A `.menuAction` naming an earlier menu's token runs
/// nothing; the current token's runs. Mutation: skip the token comparison.
@MainActor
@Test func aMenuActionWithAStaleTokenRunsNothing() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    platform.simulateInput(rdown(20, 20))
    platform.simulateInput(rup(20, 20))
    try #require(platform.presentedMenus.count == 2)
    let (old, current) = (platform.presentedMenus[0].menu.token, platform.presentedMenus[1].menu.token)
    try #require(old != current, "each presentation has its own token")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: old, item: 1)))
    #expect(log.entries.isEmpty, "a stale token runs nothing")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: current, item: 2)))
    #expect(log.entries == ["delete"], "the current token runs its item")
    withExtendedLifetime(window) {}
}

/// **1.4** (C4c). The content is evaluated at each open: after Flag is
/// chosen (it writes `false`), the reopened menu shows it off — after a
/// redraw, and again (back on) with no frame between two opens. Mutations:
/// cache the evaluated items for good; cache them in the frame's attachment.
@MainActor
@Test func theMenuIsEvaluatedAtEachOpen() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    let first = try #require(platform.presentedMenus.last?.menu)
    #expect(flatten(first.items).first { $0.title == "Flag" }?.isOn == true)
    platform.simulateInput(.menuAction(MenuActionEvent(menu: first.token, item: 7)))
    try #require(log.flag == false, "choosing Flag wrote false")
    redraw(window)
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    let second = try #require(platform.presentedMenus.last?.menu)
    try #require(second.token != first.token)
    #expect(flatten(second.items).first { $0.title == "Flag" }?.isOn == false, "the reopened menu shows it off")
    // Two opens with NO frame between: the first open's choice writes the
    // model, and the second open, with the same frame's registration, still
    // shows the new value — evaluation is per open, not per frame.
    platform.simulateInput(.menuAction(MenuActionEvent(menu: second.token, item: 7)))
    try #require(log.flag == true, "choosing Flag again wrote true")
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    let third = try #require(platform.presentedMenus.last?.menu)
    try #require(third.token != second.token)
    #expect(flatten(third.items).first { $0.title == "Flag" }?.isOn == true,
            "reopened with no frame between, the menu shows it on again")
    withExtendedLifetime(window) {}

    // A toggle reads its binding when the platform items are built, so the
    // arm above cannot see a cache of the evaluated `MenuItems`; a title read
    // from the model when the content closure runs can. Two opens, no frame
    // between, the first open's item renaming the second's.
    let model = MLog()
    let (window2, platform2) = try menuWindow {
        Box().frame(width: px(400), height: px(400)).contextMenu {
            Button(model.entries.isEmpty ? "Before" : "After") { model.entries.append("renamed") }
        }
    }
    platform2.simulateInput(rdown(10, 10))
    platform2.simulateInput(rup(10, 10))
    let before = try #require(platform2.presentedMenus.last?.menu)
    try #require(before.items.map(\.title) == ["Before"])
    platform2.simulateInput(.menuAction(MenuActionEvent(menu: before.token, item: 1)))
    try #require(model.entries == ["renamed"])
    platform2.simulateInput(rdown(10, 10))
    platform2.simulateInput(rup(10, 10))
    let after = try #require(platform2.presentedMenus.last?.menu)
    try #require(after.token != before.token)
    #expect(after.items.map(\.title) == ["After"], "the content closure ran again at the second open")
    withExtendedLifetime(window2) {}
}

/// **1.5** (C8). Nested context menus: the inner one opens over the inner
/// view, the outer one elsewhere. Mutation: rank the outermost region first.
@MainActor
@Test func theInnermostContextMenuOpens() throws {
    let (window, platform) = try menuWindow {
        Row {
            Box().frame(width: px(100), height: px(100)).contextMenu { Button("Inner") {} }
        }
        .frame(width: px(400), height: px(400))
        .contextMenu { Button("Outer") {} }
    }
    let found = regions(window).sorted { $0.bounds.size.width.value < $1.bounds.size.width.value }
    try #require(found.count == 2, "two regions: \(found.map(\.bounds))")
    platform.simulateInput(r(centre(found[0].bounds)))
    platform.simulateInput(ru(centre(found[0].bounds)))
    platform.simulateInput(rdown(5, 5))
    platform.simulateInput(rup(5, 5))
    #expect(platform.presentedMenus.map { $0.menu.items.map(\.title) } == [["Inner"], ["Outer"]])
    withExtendedLifetime(window) {}
}

/// **1.6** (C9). A disabled element's menu still opens, with every item
/// disabled; a `.menuAction` for one runs nothing. Mutation: register the
/// region after the disabled gate's exit.
@MainActor
@Test func aDisabledElementsMenuOpensWithEveryItemDisabled() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { controlRoot(width: 400, height: 400) { card(log).disabled(true) } }
    platform.simulateInput(rdown(50, 50))
    platform.simulateInput(rup(50, 50))
    let menu = try #require(platform.presentedMenus.last?.menu, "the disabled element's menu opens (C9)")
    #expect(flatten(menu.items).allSatisfy { !$0.isEnabled }, "every item disabled: \(describe(menu.items))")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: menu.token, item: 1)))
    #expect(log.entries.isEmpty, "a disabled item runs nothing")
    withExtendedLifetime(window) {}
}

/// **1.7** (C10). An empty menu presents nothing and does not claim the press.
/// Mutation: present an empty menu.
@MainActor
@Test func anEmptyContextMenuPresentsNothingAndDoesNotClaimThePress() throws {
    let show = false
    let (window, platform) = try menuWindow {
        Box().frame(width: px(400), height: px(400)).contextMenu {
            if show { Button("Hidden") {} }
        }
    }
    try #require(regions(window).count == 1, "the region exists; its menu is empty")
    #expect(!platform.simulateInput(rdown(50, 50)), "the press is not claimed")
    #expect(platform.presentedMenus.isEmpty)
    #expect(window.menuSession == nil)
    withExtendedLifetime(window) {}
}

/// **1.8** (divergence 110, `MN-B` item 4). A secondary press and release over
/// a `Button`, an `.onTapGesture`, a `.draggable` and a `TextField` runs,
/// opens or focuses nothing — SwiftUI's right click presses a `Button` (C6).
/// Mutation: let `.rightMouseDown` fall through to the arena as a `.mouseDown`.
@MainActor
@Test func aSecondaryPressNeverRunsOnClickOrATap() throws {
    let log = MLog()
    var text = "abc"
    let (window, platform) = try menuWindow {
        controlRoot(width: 400, height: 400) {
            Button("B") { log.entries.append("button") }.frame(width: px(100), height: px(100))
            Box().frame(width: px(100), height: px(100)).onTapGesture { log.entries.append("tap") }
            Box().frame(width: px(100), height: px(100)).draggable("s")
            TextField("f", text: Binding(get: { text }, set: { text = $0 })).frame(width: px(100), height: px(30))
        }
    }
    let targets = window.lastHitboxes.filter { $0.scroll == nil && ($0.opaque || $0.handlers.hasDraggable) }
    try #require(targets.count >= 4, "four targets: \(targets.map(\.bounds))")
    for target in targets {
        let c = centre(target.bounds)
        platform.simulateInput(r(c))
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(c.x.value + 20, c.y.value))))
        platform.simulateInput(ru(pt(c.x.value + 20, c.y.value)))
        platform.simulateInput(r(c))
        platform.simulateInput(ru(c))
        redraw(window)
    }
    #expect(log.entries.isEmpty, "nothing ran: \(log.entries)")
    #expect(window.dragSession == nil, "no drag began")
    #expect(window.focusedElement == nil, "nothing was focused")
    #expect(window.active == nil, "nothing is pressed")
    // The control: a primary click on the button does press it.
    let button = try #require(targets.first { $0.handlers.onClick != nil })
    controlClick(platform, at: centre(button.bounds))
    #expect(log.entries == ["button"], "control: a primary click presses the button")
    withExtendedLifetime(window) {}
}

/// **1.9** (`MN-V`, `IX-Q`'s layer rule). A `Deferred` presentation declared
/// inside the menu's element, hoisted over it, blocks the menu beneath its own
/// rect; elsewhere the menu opens. Mutation: drop the layer rule.
@MainActor
@Test func aPresentationOnAHigherLayerBlocksAContextMenuBeneath() throws {
    let log = MLog()
    let (window, platform) = try menuWindow {
        Column {
            Deferred {
                Box().frame(width: px(40), height: px(40)).onClick { log.entries.append("modal") }
                    .position(.absolute)
                    .inset(Edges(top: .length(.pixels(px(100))), right: .auto,
                                 bottom: .auto, left: .length(.pixels(px(100)))))
            }
        }
        .frame(width: px(400), height: px(400))
        .contextMenu { Button("Under") {} }
    }
    try #require(regions(window).count == 1)
    try #require(window.lastHitboxes.contains { $0.opaque && $0.layer > 0 }, "the presentation's hitbox is hoisted")
    #expect(!platform.simulateInput(rdown(120, 120)), "over the presentation: not claimed")
    #expect(platform.presentedMenus.isEmpty, "no menu under the presentation")
    platform.simulateInput(rdown(300, 300))
    #expect(platform.presentedMenus.count == 1, "control: elsewhere the menu opens")
    withExtendedLifetime(window) {}
}

/// **1.10** (C14, `MN-V`). A same-layer `onClick` cover with no menu blocks the
/// menu beneath it; a `Button` inside `Box { … }.contextMenu` opens its
/// ancestor's menu and is not pressed. Mutation: rank the regions alone.
@MainActor
@Test func aCoveringPointerTargetWithoutAMenuBlocksTheMenuBeneath() throws {
    let log = MLog()
    let (window, platform) = try menuWindow {
        Stack {
            Box().frame(width: px(400), height: px(400)).contextMenu { Button("Under") {} }
            Box().frame(width: px(100), height: px(100)).onClick { log.entries.append("cover") }
        }
        .frame(width: px(400), height: px(400))
    }
    let cover = try #require(window.lastHitboxes.first { $0.opaque && $0.handlers.onClick != nil })
    try #require(regions(window).count == 1)
    platform.simulateInput(r(centre(cover.bounds)))
    #expect(platform.presentedMenus.isEmpty, "the cover blocks the menu beneath (C14)")
    platform.simulateInput(rdown(5, 5))
    #expect(platform.presentedMenus.count == 1, "control: beside the cover the menu opens")
    withExtendedLifetime(window) {}

    let (window2, platform2) = try menuWindow {
        Box { Button("B") { log.entries.append("button") }.frame(width: px(100), height: px(100)) }
            .frame(width: px(400), height: px(400))
            .contextMenu { Button("Ancestor") {} }
    }
    let button = try #require(window2.lastHitboxes.first { $0.opaque && $0.handlers.onClick != nil })
    platform2.simulateInput(r(centre(button.bounds)))
    platform2.simulateInput(ru(centre(button.bounds)))
    #expect(platform2.presentedMenus.map { $0.menu.items.map(\.title) } == [["Ancestor"]],
            "a pointer target inside the menu's element opens its ancestor's menu")
    #expect(log.entries.isEmpty, "and is not pressed")
    withExtendedLifetime(window2) {}
}

/// **1.11** (C12). A context item's ⌘K does nothing while the menu is
/// closed. Mutation: register item shortcuts in `FocusRegistry`.
@MainActor
@Test func aContextMenuItemsShortcutDoesNotFireWhileClosed() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    try #require(regions(window).count == 1)
    platform.simulateInput(key("k", .command))
    #expect(log.entries.isEmpty, "⌘K ran nothing")
    withExtendedLifetime(window) {}
}

/// **1.12**. A `.menuAction` naming a disabled item's id runs nothing.
/// Mutation: skip the item's `isEnabled` check.
@MainActor
@Test func aDisabledItemCannotBeChosen() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    platform.simulateInput(rdown(10, 10))
    let menu = try #require(platform.presentedMenus.last?.menu)
    try #require(flatten(menu.items).first { $0.id == 8 }?.title == "Off")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: menu.token, item: 8)))
    #expect(log.entries.isEmpty, "Off is disabled")
    withExtendedLifetime(window) {}
}

/// **1.13** (C4). Choosing a toggle item writes `!isOn` through its binding,
/// from input. Mutation: write `isOn` unchanged.
@MainActor
@Test func aToggleItemWritesItsBinding() throws {
    let log = MLog()
    let (window, platform) = try menuWindow { card(log) }
    platform.simulateInput(rdown(10, 10))
    let menu = try #require(platform.presentedMenus.last?.menu)
    platform.simulateInput(.menuAction(MenuActionEvent(menu: menu.token, item: 7)))
    #expect(log.entries == ["flag=false"])
    #expect(log.flag == false)
    withExtendedLifetime(window) {}
}

/// **1.14** (`MN-D` item 2). An item's `.disabled(true)` disables it; a
/// `.disabled(false)` inside a `.disabled(true)` stays disabled (`EV-D`'s AND);
/// a `.disabled(false)` alone leaves it enabled. Mutation: read the scope's own
/// flag instead of applying its write.
@MainActor
@Test func menuItemsResolveDisabledThroughTheEnvironmentScope() throws {
    let (window, platform) = try menuWindow {
        Box().frame(width: px(400), height: px(400)).contextMenu {
            Button("Off") {}.disabled(true)
            Button("Both") {}.disabled(false).disabled(true)
            Button("On") {}.disabled(false)
        }
    }
    platform.simulateInput(rdown(10, 10))
    let menu = try #require(platform.presentedMenus.last?.menu)
    #expect(describe(menu.items) == ["1 Off (disabled)", "2 Both (disabled)", "3 On"])
    withExtendedLifetime(window) {}
}

/// **1.15** (`MN-E` item 4, `MN-Q`). `.contextMenu` on a `StyledElement`
/// moves no element's id and writes no `StateTable` entry; on proposal content
/// it adds one level for its caller: the content numbers from 0 under the
/// wrapper. Mutation: wrap the `StyledElement` spelling in `ContextualModifier`.
@MainActor
@Test func aContextMenuMovesNoIDAndWritesNoStateTableEntry() throws {
    func targets(_ menu: Bool) throws -> (ids: [GlobalElementID], table: Int, regions: Int) {
        let (window, _) = try menuWindow {
            controlRoot(width: 400, height: 400) {
                let box = Box().frame(width: px(200), height: px(200)).onClick {}
                menu ? box.contextMenu { Button("X") {} } : box
                Box().frame(width: px(200), height: px(200)).onClick {}
            }
        }
        redraw(window)
        let ids = window.lastHitboxes.filter(\.opaque).map(\.id)
        let result = (ids, window.stateTable.count, regions(window).count)
        withExtendedLifetime(window) {}
        return result
    }
    let plain = try targets(false)
    let withMenu = try targets(true)
    try #require(withMenu.regions == 1 && plain.regions == 0, "only the menu arm registers a region")
    #expect(withMenu.ids == plain.ids, "no id moves")
    #expect(withMenu.table == plain.table, "no StateTable entry")

    let (window, _) = try menuWindow {
        Rectangle().onTapGesture {}.contextMenu { Button("X") {} }
    }
    let region = try #require(regions(window).first, "the wrapper registers its region")
    let tap = try #require(window.lastHitboxes.first { $0.opaque })
    #expect(tap.id == GlobalElementID.child(of: region.id, at: 0, name: nil),
            "the content numbers from 0 under the wrapper")
    withExtendedLifetime(window) {}
}

// MARK: - 1.16–1.28: the in-window menu (`MN-F`)

/// **1.16** (`MN-C` item 3, `MN-F` item 1). When the platform declines, the
/// window opens its own menu at the pointer, its rows from `MenuPanel.layout`.
/// Mutation: open the panel only when `presentMenu` answered `true`.
@MainActor
@Test func aDeclinedNativeMenuOpensInWindowAtThePointer() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(100, 60))
    #expect(platform.presentedMenus.count == 1, "the platform was asked first")
    let session = try panel(window)
    #expect(session.levels[0].origin == pt(100, 60), "at the pointer")
    let expected = MenuPanel.layout(items: session.menu.items, textSystem: window.menuTextSystem,
                                    font: window.menuFont)
    #expect(session.levels[0].layout == expected)
    #expect(expected.rows.count == 8 && expected.rows[2].size.height == px(MenuPanel.separatorHeight))
    withExtendedLifetime(window) {}
}

/// **1.17** (`MN-F` item 1). Near the window's right and bottom edges the
/// panel flips to end at the pointer; at the top-left corner it is clamped 4
/// pt inside. Mutation: drop the flip (clamp only).
@MainActor
@Test func theInWindowMenuFlipsAndClampsInsideTheWindow() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(390, 390))
    let size = try panel(window).levels[0].layout.size
    #expect(try panel(window).levels[0].origin == pt(390 - size.width.value, 390 - size.height.value),
            "flipped to end at the pointer")
    platform.simulateInput(key(escapeKey))
    try #require(window.menuSession == nil)
    platform.simulateInput(rdown(1, 2))
    #expect(try panel(window).levels[0].origin == pt(4, 4), "clamped 4 pt inside")
    withExtendedLifetime(window) {}
}

/// **1.18** (`MN-F` item 3). ↓ moves the highlight over enabled rows — over
/// the separator and the disabled Off — and stays at the last; ↑ goes back.
/// Mutation: allow disabled rows.
@MainActor
@Test func arrowKeysMoveTheHighlightOverEnabledRowsWithoutWrapping() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    var seen: [Int?] = []
    for _ in 0..<7 {
        platform.simulateInput(key(downArrow))
        seen.append(try panel(window).levels[0].highlighted)
    }
    #expect(seen == [0, 1, 3, 4, 6, 6, 6], "Copy, Delete, More, Flag, Short, then stays")
    platform.simulateInput(key(upArrow))
    #expect(try panel(window).levels[0].highlighted == 4, "↑ skips Off back to Flag")
    withExtendedLifetime(window) {}
}

/// **1.19** (`MN-F` item 3). Return chooses the highlighted item once and
/// closes the menu. Mutation: leave the session open after choosing.
@MainActor
@Test func returnChoosesTheHighlightedItemAndClosesTheMenu() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    platform.simulateInput(key(downArrow))
    platform.simulateInput(key(downArrow))
    #expect(platform.simulateInput(key(returnKey)), "Return is claimed")
    #expect(log.entries == ["delete"], "Delete ran once")
    #expect(window.menuSession == nil, "the menu closed")
    platform.simulateInput(key(returnKey))
    #expect(log.entries == ["delete"], "a second Return reaches no menu")
    withExtendedLifetime(window) {}
}

/// **1.20** (`MN-F` items 1, 3). → opens the highlighted submenu beside its
/// row, top-aligned, at its first enabled row; ← closes it. Mutation: open the
/// submenu at the pointer.
@MainActor
@Test func rightArrowOpensASubmenuAndLeftArrowClosesIt() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    for _ in 0..<3 { platform.simulateInput(key(downArrow)) }
    try #require(try panel(window).levels[0].highlighted == 3, "More is highlighted")
    platform.simulateInput(key(rightArrow))
    let open = try panel(window)
    try #require(open.levels.count == 2, "the submenu opened")
    let root = open.levels[0], sub = open.levels[1]
    #expect(sub.items.map(\.title) == ["A", "B"])
    #expect(sub.highlighted == 0, "at its first enabled row")
    #expect(sub.origin.x == px(root.frame.origin.x.value + root.frame.size.width.value), "beside the root")
    #expect(sub.origin.y == px(root.rowFrame(3).origin.y.value - MenuPanel.verticalPadding),
            "its first row top-aligned with More")
    platform.simulateInput(key(leftArrow))
    #expect(try panel(window).levels.count == 1, "← closed it")
    withExtendedLifetime(window) {}
}

/// **1.21** (`MN-F` item 3). Hovering a submenu row opens it at once; hovering
/// a shallower row closes it. Mutation: never close deeper levels on hover.
@MainActor
@Test func hoveringASubmenuRowOpensItAndAShallowerRowClosesIt() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    let root = try panel(window).levels[0]
    platform.simulateInput(mv(centre(root.rowFrame(3))))
    #expect(try panel(window).levels.count == 2, "hovering More opened its submenu")
    #expect(try panel(window).levels[0].highlighted == 3)
    platform.simulateInput(mv(centre(root.rowFrame(0))))
    #expect(try panel(window).levels.count == 1, "hovering Copy closed it")
    #expect(try panel(window).levels[0].highlighted == 0)
    withExtendedLifetime(window) {}
}

/// **1.22** (`MN-F` item 3). Escape closes the deepest level first, then the
/// menu. Mutation: close every level on the first Escape.
@MainActor
@Test func escapeClosesTheDeepestLevelFirst() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    platform.simulateInput(mv(centre(try panel(window).levels[0].rowFrame(3))))
    try #require(try panel(window).levels.count == 2)
    #expect(platform.simulateInput(key(escapeKey)))
    #expect(try panel(window).levels.count == 1, "the first Escape closed the submenu")
    platform.simulateInput(key(escapeKey))
    #expect(window.menuSession == nil, "the second closed the menu")
    withExtendedLifetime(window) {}
}

/// **1.23** (`MN-F` item 3). A press outside every level dismisses the menu
/// and is consumed with its release: the click target beneath does not run.
/// Mutation: return `false` after dismissing.
@MainActor
@Test func aPressOutsideTheMenuDismissesItAndReachesNothingBeneath() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) {
        controlRoot(width: 400, height: 400) {
            Box().frame(width: px(200), height: px(400)).contextMenu { fullMenuContent(log) }
            Box().frame(width: px(200), height: px(400)).onClick { log.entries.append("under") }
        }
    }
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    _ = try panel(window)
    #expect(platform.simulateInput(ldown(300, 300)), "the press is claimed")
    #expect(window.menuSession == nil, "and dismissed the menu")
    platform.simulateInput(lup(300, 300))
    redraw(window)
    #expect(log.entries.isEmpty, "the target beneath did not run: \(log.entries)")
    controlClick(platform, at: pt(300, 300))
    #expect(log.entries == ["under"], "control: with no menu open the target runs")
    withExtendedLifetime(window) {}
}

/// **1.24** (`MN-F` item 3). A click on an item chooses it; a right press, a
/// move and a right release over an item chooses it; the opening press's
/// release with no move between does not. Mutation: choose on the opening
/// press's release without a move.
@MainActor
@Test func aClickOrAPressDragReleaseOnAnItemChoosesIt() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    let rows = try panel(window).levels[0]
    platform.simulateInput(ru(centre(rows.rowFrame(0))))
    #expect(window.menuSession != nil && log.entries.isEmpty, "the opening release with no move chose nothing")
    platform.simulateInput(l(centre(rows.rowFrame(0))))
    platform.simulateInput(lu(centre(rows.rowFrame(0))))
    #expect(log.entries == ["copy"], "a click chose Copy")
    #expect(window.menuSession == nil)

    platform.simulateInput(rdown(10, 10))
    let again = try panel(window).levels[0]
    platform.simulateInput(mv(centre(again.rowFrame(1))))
    platform.simulateInput(ru(centre(again.rowFrame(1))))
    #expect(log.entries == ["copy", "delete"], "press, move, release chose Delete")
    #expect(window.menuSession == nil)
    withExtendedLifetime(window) {}
}

/// **1.25** (`MN-F` item 2). The open menu paints above everything — above a
/// drag preview: its panel is the highest-layer primitive. Mutation: emit
/// before `paintDragPreview()`.
@MainActor
@Test func theOpenMenuIsPaintedAboveEverything() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) {
        controlRoot(width: 400, height: 400) {
            Box().frame(width: px(200), height: px(400)).background(.accent).draggable("s")
            Box().frame(width: px(200), height: px(400)).contextMenu { fullMenuContent(log) }
        }
    }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(dragged(150, 100))
    try #require(window.dragSession != nil, "a drag is open")
    platform.simulateInput(rdown(250, 20))
    let frame = try panel(window).levels[0].frame
    redraw(window)
    let scene = window.lastScene
    let panelIndex = try #require(scene.rects.firstIndex {
        Float($0.bounds.origin.x) == frame.origin.x.value && Float($0.bounds.origin.y) == frame.origin.y.value
            && Float($0.bounds.size.width) == frame.size.width.value
    }, "the panel's rect is in the scene")
    let previewIndex = try #require(scene.rects.firstIndex { $0.background.a > 0 && $0.background.a < 0.75 },
                                    "the drag preview's translucent copy is in the scene")
    let panelLayer = scene.layer(of: .rect, at: panelIndex)
    #expect(panelLayer > scene.layer(of: .rect, at: previewIndex), "above the drag preview")
    #expect(panelLayer == scene.highestLayer, "the highest layer")
    withExtendedLifetime(window) {}
}

/// **1.26** (`MN-F` item 4, `MN-R`). While a client is active the in-window
/// menu publishes a `.menu` root of `.menuItem`/`.menuItemCheckBox` nodes —
/// titles, the toggle's value, the disabled flag, focus on the highlighted
/// row — and a press on an item chooses it. Mutation: publish the rows as
/// `.button`.
@MainActor
@Test func theInWindowMenuPublishesAMenuOfMenuItems() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(rup(10, 10))
    platform.simulateInput(key(downArrow))
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let rootID = try #require(tree.roots.last)
    let root = try #require(tree.nodes[rootID])
    try #require(root.role == .menu, "the last root is the menu: \(root.role)")
    let rows = root.children.compactMap { tree.nodes[$0] }
    #expect(rows.map(\.label) == ["Copy", "Delete", "More", "Flag", "Off", "Short", "Plain"])
    #expect(rows.map(\.role) == [.menuItem, .menuItem, .menuItem, .menuItemCheckBox, .menuItem, .menuItem, .menuItem])
    #expect(rows[3].value == "1", "Flag is on")
    #expect(rows.map(\.isEnabled) == [true, true, true, true, false, true, false])
    #expect(tree.focused == root.children.first, "focus is on the highlighted Copy")
    #expect(platform.simulateAccessibilityRequest(.press(root.children[1])), "pressing Delete is handled")
    #expect(log.entries == ["delete"])
    #expect(window.menuSession == nil)
    withExtendedLifetime(window) {}
}

/// **1.27** (`MN-F`). The open in-window menu writes no `StateTable` entry.
/// Mutation: store the session under `StateTable`.
@MainActor
@Test func theInWindowMenuWritesNoStateTableEntry() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    redraw(window)
    let closed = window.stateTable.count
    platform.simulateInput(rdown(10, 10))
    platform.simulateInput(key(downArrow))
    _ = try panel(window)
    redraw(window)
    #expect(window.stateTable.count == closed)
    withExtendedLifetime(window) {}
}

/// **1.28** (`MN-F` item 3). A resize, and the window losing key, each dismiss
/// the in-window menu. Mutation: ignore `controlActiveState`.
@MainActor
@Test func aResizeOrLosingKeyDismissesTheInWindowMenu() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) { card(log) }
    platform.simulateInput(rdown(10, 10))
    _ = try panel(window)
    platform.simulateResize(to: Size(width: px(390), height: px(390)))
    #expect(window.menuSession == nil, "a resize dismissed it")
    platform.simulateInput(rdown(10, 10))
    _ = try panel(window)
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(window.menuSession == nil, "losing key dismissed it")
    withExtendedLifetime(window) {}
}

// MARK: - 1.29–1.30: keyboard and accessibility openers (`MN-G`)

/// **1.29** (`MN-G` item 1). Shift-F10 and the Menu key open a context menu
/// off Apple only; on this platform (macOS) Shift-F10 on a focused element
/// opens nothing. Mutation: answer `true` on `.mac`.
@MainActor
@Test func theContextMenuKeysAreShiftF10AndTheMenuKeyOffAppleOnly() throws {
    func k(_ c: String, _ m: Modifiers) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: m, timestamp: 0)
    }
    #expect(ContextMenuKeys.opens(k("\u{f70d}", .shift), platform: .other), "Shift-F10 off Apple")
    #expect(ContextMenuKeys.opens(k("\u{f735}", []), platform: .other), "the Menu key off Apple")
    #expect(!ContextMenuKeys.opens(k("\u{f70d}", []), platform: .other), "plain F10 is not")
    #expect(!ContextMenuKeys.opens(k("\u{f735}", .shift), platform: .other), "Shift-Menu is not")
    #expect(!ContextMenuKeys.opens(k("\u{f70d}", .shift), platform: .mac), "never on a Mac")
    #expect(!ContextMenuKeys.opens(k("\u{f735}", []), platform: .mac), "never on a Mac")

    let (window, platform) = try menuWindow {
        Box().frame(width: px(400), height: px(400)).focusable().contextMenu { Button("X") {} }
    }
    window.focus(controlID([0]))
    redraw(window)
    try #require(window.focusedElement == controlID([0]))
    platform.simulateInput(key("\u{f70d}", .shift))
    platform.simulateInput(key("\u{f735}"))
    #expect(platform.presentedMenus.isEmpty, "on macOS neither key opens a menu")
    withExtendedLifetime(window) {}
}

/// **1.30** (C11, C11n, `MN-W`). Only a menu-bearing node advertises
/// `.showMenu`; the request presents its menu at the element's bottom-leading
/// corner, and a node without one refuses. Mutation: advertise `.showMenu` on
/// every node.
@MainActor
@Test func aShowMenuRequestOpensTheElementsMenu() throws {
    let (window, platform) = try menuWindow {
        controlRoot(width: 400, height: 400) {
            Text("Menu").frame(width: px(200), height: px(100)).contextMenu { Button("X") {} }
            Text("Plain").frame(width: px(200), height: px(100)).onClick {}
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let showing = tree.nodes.filter { $0.value.actions.contains(.showMenu) }
    try #require(showing.count == 1, "exactly one node advertises show-menu: \(showing.map(\.value.label))")
    let menuNode = try #require(showing.first?.key)
    let plainNode = try #require(tree.nodes.first { $0.value.actions.contains(.press) }?.key)
    #expect(!platform.simulateAccessibilityRequest(.showMenu(plainNode)), "a node without a menu refuses (C11n)")
    #expect(platform.presentedMenus.isEmpty)
    #expect(platform.simulateAccessibilityRequest(.showMenu(menuNode)), "the menu node's request is handled")
    try #require(platform.presentedMenus.count == 1)
    let frame = try #require(tree.geometry[menuNode]?.frame)
    #expect(platform.presentedMenus[0].at
            == pt(frame.origin.x.value, frame.origin.y.value + frame.size.height.value),
            "at the element's bottom-leading corner")
    #expect(platform.presentedMenus[0].menu.items.map(\.title) == ["X"])
    withExtendedLifetime(window) {}
}

/// **1.29b** (`MN-G` item 1, `MN-AE` item 4). Off Apple — the window's
/// `contextMenuKeyPlatform` seam set to `.other`, as `TextEditing.platform`
/// reads on Linux and Windows — Shift-F10 and the Menu key each open the menu
/// of the focused element's nearest **ancestor** carrying one, at that
/// ancestor's bottom-leading corner, not the focused element's. Mutations:
/// look only at the focused element itself (`focusChain.first`); anchor at the
/// focused element's corner.
@MainActor
@Test func shiftF10AndTheMenuKeyOpenTheFocusedElementsAncestorsMenuOffApple() throws {
    let (window, platform) = try menuWindow {
        Row {
            Box().frame(width: px(100), height: px(60)).focusable()
        }
        .frame(width: px(300), height: px(200))
        .contextMenu { Button("Outer") {} }
    }
    window.contextMenuKeyPlatform = .other
    let found = regions(window)
    try #require(found.count == 1, "only the ancestor carries a menu: \(found.map(\.bounds))")
    let outer = found[0].bounds
    try #require(outer.size.width == px(300) && outer.size.height == px(200), "the ancestor's frame: \(outer)")
    platform.simulateInput(key("\t"))
    redraw(window)
    let focused = try #require(window.focusedElement, "Tab focused the inner box")
    try #require(focused != found[0].id, "the focused element is the inner box, not the menu-bearing ancestor")
    let corner = pt(outer.origin.x.value, outer.origin.y.value + outer.size.height.value)
    #expect(platform.simulateInput(key("\u{f70d}", .shift)), "Shift-F10 is claimed")
    try #require(platform.presentedMenus.count == 1, "Shift-F10 opened a menu")
    #expect(platform.presentedMenus[0].menu.items.map(\.title) == ["Outer"])
    #expect(platform.presentedMenus[0].at == corner, "at the ancestor's bottom-leading corner")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: platform.presentedMenus[0].menu.token, item: nil)))
    #expect(platform.simulateInput(key("\u{f735}")), "the Menu key is claimed")
    try #require(platform.presentedMenus.count == 2, "the Menu key opened a menu")
    #expect(platform.presentedMenus[1].menu.items.map(\.title) == ["Outer"])
    #expect(platform.presentedMenus[1].at == corner, "at the ancestor's bottom-leading corner")
    platform.simulateInput(.menuAction(MenuActionEvent(menu: platform.presentedMenus[1].menu.token, item: nil)))
    #expect(!platform.simulateInput(key("\u{f70d}")), "plain F10 opens nothing")
    #expect(platform.presentedMenus.count == 2)
    withExtendedLifetime(window) {}
}

/// **1.30b** (`MN-AE` item 3, C9). A disabled element with a context menu,
/// a client active: its published node advertises no `.showMenu` (`AB-H`),
/// yet a `.showMenu` request naming it still opens its menu, every item
/// disabled. Mutations: advertise `.showMenu` regardless of `isEnabled`;
/// refuse the request for a disabled record.
@MainActor
@Test func aDisabledElementAdvertisesNoShowMenuButTheRequestOpensItsMenuDisabled() throws {
    let log = MLog()
    let (window, platform) = try menuWindow {
        controlRoot(width: 400, height: 400) {
            Text("Menu").frame(width: px(200), height: px(100)).contextMenu { fullMenuContent(log) }.disabled(true)
        }
    }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    try #require(window.lastContextMenus.count == 1, "the disabled element recorded its menu")
    let menuNode = try #require(tree.nodes.keys.first { key in
        (key.base as? GlobalElementID).map { window.lastContextMenus[$0] != nil } ?? false
    }, "the menu-bearing element is published: \(tree.nodes.values.map { "\($0.role) \($0.isEnabled)" })")
    let node = try #require(tree.nodes[menuNode])
    #expect(!node.isEnabled, "published disabled")
    #expect(!node.actions.contains(.showMenu), "a disabled node advertises no show-menu: \(node.actions)")
    #expect(platform.simulateAccessibilityRequest(.showMenu(menuNode)), "the request is still handled (C9)")
    let menu = try #require(platform.presentedMenus.last?.menu, "the disabled element's menu opened")
    #expect(!menu.items.isEmpty)
    #expect(flatten(menu.items).allSatisfy { !$0.isEnabled }, "every item disabled: \(describe(menu.items))")
    withExtendedLifetime(window) {}
}

/// **1.38** (`MN-AE` item 6). With a `TextField` focused and the in-window
/// menu open, the field's Space — `.textInput(" ")` — chooses the highlighted
/// item and the field's text is unchanged; once the menu is closed the same
/// event types into the field (the positive control: the field holds focus).
/// Mutation: never treat `.textInput(" ")` as a choice.
@MainActor
@Test func aFocusedFieldsSpaceChoosesTheHighlightedInWindowItem() throws {
    let log = MLog()
    let binding = Binding(get: { log.text }, set: { log.text = $0 })
    let (window, platform) = try menuWindow(native: false) {
        Column {
            TextField("F", text: binding).frame(width: px(400), height: px(30))
            Box().frame(width: px(400), height: px(300)).contextMenu { fullMenuContent(log) }
        }
        .frame(width: px(400), height: px(400))
    }
    platform.simulateInput(key("\t"))
    redraw(window)
    try #require(window.focusedElement != nil, "Tab focused the field")
    let menuRegion = try #require(regions(window).first?.bounds)
    let p = centre(menuRegion)
    platform.simulateInput(r(p))
    platform.simulateInput(ru(p))
    _ = try panel(window)
    platform.simulateInput(key(downArrow))
    platform.simulateInput(key(downArrow))
    try #require(try panel(window).levels[0].highlighted == 1, "Delete highlighted")
    #expect(platform.simulateInput(.textInput(" ")), "the menu claims the field's Space")
    #expect(log.entries == ["delete"], "Space chose Delete")
    #expect(window.menuSession == nil, "the menu closed")
    redraw(window)
    #expect(log.text == "abc", "the field's text is unchanged")
    platform.simulateInput(.textInput(" "))
    redraw(window)
    try #require(window.focusedElement != nil)
    #expect(log.text != "abc", "with the menu closed the field takes the Space: \(log.text)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.33, 1.35–1.37

/// **1.33** (`MN-Q`). `Handlers` gains exactly one reference: 464 bytes.
/// Mutation: store the closure and help string inline.
@Test func handlersGainsOneReferenceMember() {
    #expect(MemoryLayout<Handlers>.size == 464, "Handlers: \(MemoryLayout<Handlers>.size)")
}

/// **1.35** (C13c/C13, `MN-U`). Under `.allowsHitTesting(false)` a right press
/// opens no menu and is not claimed; the show-menu action is still advertised
/// (not a hitbox query). Mutation: register the region outside the gate.
@MainActor
@Test func aContextMenuUnderAllowsHitTestingFalseDoesNotOpen() throws {
    let (window, platform) = try menuWindow {
        Box().frame(width: px(400), height: px(400)).contextMenu { Button("X") {} }.allowsHitTesting(false)
    }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    #expect(regions(window).isEmpty, "no region under the gate")
    #expect(!platform.simulateInput(rdown(50, 50)), "the press is not claimed")
    #expect(platform.presentedMenus.isEmpty, "no menu (C13)")
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    #expect(tree.nodes.values.contains { $0.actions.contains(.showMenu) },
            "show-menu is still advertised")
    withExtendedLifetime(window) {}
}

/// **1.36** (divergence 114, `MN-V` item 2). A background-only `Box` covering
/// the region registers no hitbox, so the menu beneath opens — SwiftUI's
/// opaque cover blocks (C14). Mutation: require a hitbox owned by the region's
/// element or a descendant.
@MainActor
@Test func aPaintedCoverWithNoHitboxDoesNotBlockTheMenuBeneath() throws {
    let (window, platform) = try menuWindow {
        Stack {
            Box().frame(width: px(400), height: px(400)).contextMenu { Button("Under") {} }
            Box().frame(width: px(100), height: px(100)).background(.accent)
        }
        .frame(width: px(400), height: px(400))
    }
    try #require(!window.lastHitboxes.contains { $0.opaque }, "the cover registers no hitbox")
    try #require(regions(window).count == 1)
    platform.simulateInput(rdown(200, 200))
    #expect(platform.presentedMenus.map { $0.menu.items.map(\.title) } == [["Under"]],
            "the menu beneath a painted cover opens")
    withExtendedLifetime(window) {}
}

/// **1.37** (`MN-AB`). Inside an `.isModal` presentation the in-window menu's
/// `.menu` root is still published and a press on its item runs. Mutation:
/// build the panel's root inside the isolation filter.
@MainActor
@Test func theInWindowMenuIsPublishedAndPressableUnderModalIsolation() throws {
    let log = MLog()
    let (window, platform) = try menuWindow(native: false) {
        Column {
            Deferred {
                Box().frame(width: px(200), height: px(200))
                    .contextMenu { Button("Inside") { log.entries.append("inside") } }
                    .accessibilityAddTraits(.isModal)
                    .position(.absolute)
                    .inset(Edges(top: .length(.pixels(px(50))), right: .auto,
                                 bottom: .auto, left: .length(.pixels(px(50)))))
            }
        }
        .frame(width: px(400), height: px(400))
    }
    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    platform.simulateInput(rdown(100, 100))
    platform.simulateInput(rup(100, 100))
    _ = try panel(window)
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let menuRoot = try #require(tree.roots.first { tree.nodes[$0]?.role == .menu }, "the menu root is published")
    let item = try #require(tree.nodes[menuRoot]?.children.first)
    #expect(platform.simulateAccessibilityRequest(.press(item)), "its item is pressable under isolation")
    #expect(log.entries == ["inside"])
    withExtendedLifetime(window) {}
}
