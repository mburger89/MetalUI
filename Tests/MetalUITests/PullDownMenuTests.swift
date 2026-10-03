import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Menus, popovers and tooltips, lane 2, tests 1.31–1.32 (rulings `MN-H`,
// `MN-AD`; spec `docs/superpowers/specs/2026-10-02-menus-popovers-design.md`
// §3.4, §6.1). `Menu("Title") { … }` as a pull-down button in a real `Window`
// on a 400 × 400 `FakePlatformWindow`; SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift`, arm M1 (`AXMenuButton`).

@MainActor private final class PLog {
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

/// A 400 × 400 window over `content`, presenting menus natively, accessibility
/// active, two frames drawn (the anchor map is the last frame's).
@MainActor private func pullDownWindow<Root: Element>(native: Bool = true,
                                                      _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, content: content)
    platform.presentsMenusNatively = native
    platform.simulateAccessibilityRequest(.activate)
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **1.31** (M1, `MN-H` items 1–2). `Menu("Actions")` publishes as a
/// `.menuButton` labelled by its title (the `⌄` indicator is not read); a
/// click presents its items to the platform at the button's **bottom-leading**
/// corner, and a chosen item runs. Mutation: present at the pointer.
@MainActor
@Test func aPullDownMenuPublishesAsAMenuButtonAndOpensBelowItself() throws {
    let log = PLog()
    let (window, platform) = try pullDownWindow {
        Menu("Actions") {
            Button("A") { log.entries.append("a") }
            Divider()
            Button("B") { log.entries.append("b") }
        }
    }
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let buttons = tree.nodes.filter { $0.value.role == .menuButton }
    try #require(buttons.count == 1, "one menu button: \(tree.nodes.values.map(\.role))")
    let (node, published) = try #require(buttons.first)
    #expect(published.label == "Actions", "labelled by the title alone: \(String(describing: published.label))")
    #expect(published.actions.contains(.press))
    let frame = try #require(tree.geometry[node]?.frame)
    let press = centre(frame)
    // Pressed and released away from the corner, so the pointer and the corner differ.
    platform.simulateInput(.mouseDown(MouseEvent(position: press)))
    platform.simulateInput(.mouseUp(MouseEvent(position: press)))
    try #require(platform.presentedMenus.count == 1, "the click presents the menu once")
    let presented = platform.presentedMenus[0]
    #expect(presented.at == pt(frame.origin.x.value, frame.origin.y.value + frame.size.height.value),
            "at the button's bottom-leading corner, not the pointer \(press)")
    #expect(presented.menu.items.map(\.title) == ["A", "", "B"])
    let a = try #require(presented.menu.items.first)
    platform.simulateInput(.menuAction(MenuActionEvent(menu: presented.menu.token, item: a.id)))
    #expect(log.entries == ["a"])
    withExtendedLifetime(window) {}
}

/// **1.32** (`MN-H` item 1 as amended by `MN-AF`, `DD-R`). A focused `Menu`
/// opens from `Button`'s activation keys — Space on a Mac, not Return
/// (`ControlKeys.activatesButton`; Return too off Apple); a `.disabled(true)`
/// one is not focusable, and neither a click, Tab then Space, nor an
/// accessibility press opens it. The gate is `Button`'s own (the disabled gate
/// in `Frame.registerHandlers` drops the hitbox, the focus entry and the
/// press), so the mutation is "skip that gate", not the `isEnabled` `Menu`
/// forwards to `openPullDown` — that forward is redundant (`MN-AF` item 9).
@MainActor
@Test func aPullDownMenuOpensFromButtonsActivationKeysAndNotWhenDisabled() throws {
    let (window, platform) = try pullDownWindow { Menu("Actions") { Button("A") {} } }
    platform.simulateInput(key("\t"))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.focusedElement != nil, "Tab focused the menu button")
    platform.simulateInput(key(" "))
    #expect(platform.presentedMenus.count == 1, "Space opens the menu")
    platform.simulateInput(key("\r"))
    #expect(platform.presentedMenus.count == (TextEditing.platform == .mac ? 1 : 2),
            "Return opens it only where it presses a Button (off Apple)")

    let (disabled, disabledPlatform) = try pullDownWindow {
        Box { Menu("Actions") { Button("A") {} }.disabled(true) }.frame(width: px(400), height: px(400))
    }
    let tree = try #require(disabledPlatform.publishedAccessibilityTrees.last)
    let (node, published) = try #require(tree.nodes.first { $0.value.role == .menuButton },
                                         "a disabled menu button still publishes")
    #expect(!published.isEnabled && !published.actions.contains(.press))
    let frame = try #require(tree.geometry[node]?.frame)
    disabledPlatform.simulateInput(.mouseDown(MouseEvent(position: centre(frame))))
    disabledPlatform.simulateInput(.mouseUp(MouseEvent(position: centre(frame))))
    disabledPlatform.simulateInput(key("\t"))
    disabled.setNeedsRedraw()
    disabled.drawFrameIfNeeded()
    #expect(disabled.focusedElement == nil, "a disabled menu is not focusable")
    disabledPlatform.simulateInput(key(" "))
    #expect(!disabledPlatform.simulateAccessibilityRequest(.press(node)), "a disabled press is refused")
    #expect(disabledPlatform.presentedMenus.isEmpty, "nothing opened a disabled menu")
    withExtendedLifetime(window) {}
    withExtendedLifetime(disabled) {}
}

/// **1.31b** (`MN-AF` item 6: the anchor is recorded in window points). A
/// `Menu` 100 pt down a 200 × 200 scroller, wheel-scrolled by 37: its published
/// frame moves up 37, and a click presents the menu at the **scrolled** frame's
/// bottom-leading corner, not the unscrolled one. Mutation MANCH (drop
/// `activeOffset` from `Frame.recordPresentationAnchor`) must redden it.
@MainActor
@Test func aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame() throws {
    let (window, platform) = try pullDownWindow {
        ScrollView(.vertical) {
            Column {
                Box().frame(width: px(200), height: px(100))
                Menu("Actions") { Button("A") {} }
                Box().frame(width: px(200), height: px(400))
            }
        }.frame(width: px(200), height: px(200))
    }
    func menuFrame() throws -> Bounds<Pixels> {
        let tree = try #require(platform.publishedAccessibilityTrees.last)
        let (node, _) = try #require(tree.nodes.first { $0.value.role == .menuButton })
        return try #require(tree.geometry[node]?.frame)
    }
    let unscrolled = try menuFrame()
    let region = try #require(window.lastScrollRegions.first, "the scroller registers a region")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: centre(region.bounds),
                                                    delta: Point(x: px(0), y: px(-37)))))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.stateTable.peek(region.id, as: ScrollState.self)?.offset == 37, "scrolled by 37")
    let frame = try menuFrame()
    try #require(frame.origin.y.value == unscrolled.origin.y.value - 37
                 && frame.origin.x.value == unscrolled.origin.x.value,
                 "the published frame moved up by the scroll: \(unscrolled) -> \(frame)")
    platform.simulateInput(.mouseDown(MouseEvent(position: centre(frame))))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre(frame))))
    try #require(platform.presentedMenus.count == 1, "the click presents the menu once")
    #expect(platform.presentedMenus[0].at
            == pt(frame.origin.x.value, frame.origin.y.value + frame.size.height.value),
            "at the scrolled frame's bottom-leading corner")
    withExtendedLifetime(window) {}
}

/// **1.31c** (`MN-AF` item 5, the `selectionHint` pin's shape, 1.23). The
/// `.menuButton` role rides a hint, not a declaration: with a client active or
/// not, a `Menu` writes no `Frame.axNodes` entry and no `$ax` slot in the
/// `StateTable`. The separating arm — the same `Menu` with a declared trait —
/// writes both. The hidden `⌄` text's own node is not the menu's and is not
/// counted. Mutation M1.31c (the hint not stripped in
/// `Frame.registerHandlers`) must redden it.
@MainActor
@Test func aPullDownMenuWritesNoAXNodeAndNoAXSlot() throws {
    func run(collects: Bool, declared: Bool) throws -> (axNodes: Int, axSlots: Int) {
        var menu = Menu("Actions") { Button("A") {} }
        if declared { menu.handlers.axNode.traits = [.selected] }
        var root = Box { menu }.frame(width: px(400), height: px(400))
        let table = StateTable()
        let frame = Frame(contentSize: Size(width: px(400), height: px(400)), scaleFactor: 1,
                          stateTable: table, collectsAccessibility: collects)
        frame.render(&root)
        try #require(frame.hitboxes.count == 1, "one hitbox, the menu's: \(frame.hitboxes.map(\.id))")
        // The menu's id is its one pointer hitbox's owner (the hidden `⌄`
        // text declares a node of its own, under another id).
        let ids = Set(frame.hitboxes.map(\.id))
        let slots = ids.filter { table.ids.contains(.child(of: $0, at: 0, name: ElementID("$ax"))) }
        return (ids.filter { frame.axNodes[$0] != nil }.count, slots.count)
    }
    for collects in [true, false] {
        let plain = try run(collects: collects, declared: false)
        #expect(plain.axNodes == 0, "no axNodes entry (client \(collects)): \(plain)")
        #expect(plain.axSlots == 0, "no $ax slot (client \(collects)): \(plain)")
        // The separating arm: a declaration does write both, so the probe sees them.
        let traited = try run(collects: collects, declared: true)
        #expect(traited.axNodes == 1 && traited.axSlots == 1, "a declared trait emits (client \(collects))")
    }
}
