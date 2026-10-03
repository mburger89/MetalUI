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

/// **1.32** (`MN-H` item 1, `DD-R`). A focused `Menu` opens from Space and
/// from Return (macOS's `Button` keys); a `.disabled(true)` one is not
/// focusable, and neither a click, Tab then Space, nor an accessibility press
/// opens it. Mutation: ignore the disabled gate.
@MainActor
@Test func aPullDownMenuOpensFromSpaceAndReturnAndNotWhenDisabled() throws {
    let (window, platform) = try pullDownWindow { Menu("Actions") { Button("A") {} } }
    platform.simulateInput(key("\t"))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.focusedElement != nil, "Tab focused the menu button")
    platform.simulateInput(key(" "))
    platform.simulateInput(key("\r"))
    #expect(platform.presentedMenus.count == 2, "Space and Return each open the menu")

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
