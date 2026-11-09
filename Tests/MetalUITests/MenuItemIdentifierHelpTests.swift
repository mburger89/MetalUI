import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `MN-AL` (Alloy gap G24): `.accessibilityIdentifier` and `.help` on a `Button`
// or `Toggle` inside menu content reach the menu item. The lowering to
// `PlatformMenuItem`, the drawn menu's accessibility nodes and its tooltip are
// here; the headless record is in `HarnessMenuTests`, AppKit's `NSMenuItem` in
// `AppKitMenuTests`. Nothing sleeps: the display link is ticked by hand.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    pt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

/// Fork (enabled, id + help), Rename (disabled, id + help), Plain (neither),
/// a Flag toggle (id + help).
@MenuContentBuilder @MainActor
private func sidebarMenu() -> MenuItems {
    Button("Fork") {}.accessibilityIdentifier("fork-1234").help("Fork this branch")
    Button("Rename") {}.accessibilityIdentifier("rename-1234").help("Nothing to rename yet").disabled(true)
    Button("Plain") {}
    Toggle("Flag", isOn: .constant(true)).accessibilityIdentifier("flag-1234").help("Flags it")
}

@MainActor private func menuWindow(native: Bool) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        Box().frame(width: px(400), height: px(400)).contextMenu { sidebarMenu() }
    }
    platform.presentsMenusNatively = native
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **MN-AL 1.** The item model carries both. Mutation: drop
/// `accessibilityIdentifier:`/`help:` from `Button._menuNodes` (the Fork and
/// Rename expectations redden); from `Toggle._menuNodes` (the Flag ones).
@MainActor
@Test func aMenuButtonsIdentifierAndHelpReachThePlatformMenuItem() throws {
    let (window, platform) = try menuWindow(native: true)
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    let menu = try #require(platform.presentedMenus.last?.menu)
    let items = menu.items
    #expect(items.map(\.accessibilityIdentifier) == ["fork-1234", "rename-1234", nil, "flag-1234"])
    #expect(items.map(\.help) == ["Fork this branch", "Nothing to rename yet", nil, "Flags it"])
    #expect(menu.item(accessibilityIdentifier: "fork-1234")?.title == "Fork")
    #expect(menu.item(accessibilityIdentifier: "nope") == nil)
    withExtendedLifetime(window) {}
}

/// **MN-AL 2.** A disabled item keeps its help (a disabled item explains
/// itself). Mutation: `help: isEnabled ? node.help : nil` in `number`.
@MainActor
@Test func aDisabledMenuItemKeepsItsHelp() throws {
    let (window, platform) = try menuWindow(native: true)
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    let rename = try #require(platform.presentedMenus.last?.menu.item(accessibilityIdentifier: "rename-1234"))
    #expect(!rename.isEnabled)
    #expect(rename.help == "Nothing to rename yet")
    withExtendedLifetime(window) {}
}

/// **MN-AL 3.** The drawn menu's row nodes carry the identifier (`identifier`,
/// AccessKit `author_id`) and the help (`hint`). Mutation: drop the two lines
/// in `appendMenuPanel`.
@MainActor
@Test func aDrawnMenuRowPublishesItsIdentifierAndHelp() throws {
    let (window, platform) = try menuWindow(native: false)
    platform.simulateAccessibilityRequest(.activate)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let rows = tree.nodes.values.filter { $0.role == .menuItem || $0.role == .menuItemCheckBox }
    let fork = try #require(rows.first { $0.identifier == "fork-1234" })
    #expect(fork.label == "Fork" && fork.hint == "Fork this branch")
    let rename = try #require(rows.first { $0.identifier == "rename-1234" })
    #expect(!rename.isEnabled && rename.hint == "Nothing to rename yet")
    #expect(rows.first { $0.label == "Plain" }?.identifier == nil)
    #expect(rows.first { $0.identifier == "flag-1234" }?.role == .menuItemCheckBox)
    withExtendedLifetime(window) {}
}

/// **MN-AL 4.** Resting on a drawn menu row with help shows the usual tooltip
/// after 1.0 s, a disabled row's too; moving to a row with none hides it.
/// Mutation: `trackTooltip`'s menu branch back to `tooltipTracker.hide()`.
@MainActor
@Test func aDrawnMenuRowShowsItsHelpAsATooltip() throws {
    let (window, platform) = try menuWindow(native: false)
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    let level = try #require(window.menuSession?.levels.first)
    platform.simulateInput(.mouseMoved(MouseEvent(position: centre(level.rowFrame(1)))))
    platform.simulateTick(timestamp: 10)
    #expect(window.visibleTooltip == nil, "stamped, not shown")
    platform.simulateTick(timestamp: 11)
    #expect(window.visibleTooltip?.text == "Nothing to rename yet", "the disabled row explains itself")
    platform.simulateInput(.mouseMoved(MouseEvent(position: centre(level.rowFrame(2)))))
    #expect(window.visibleTooltip == nil, "a row with no help shows none")
    platform.simulateTick(timestamp: 12)
    platform.simulateTick(timestamp: 13)
    #expect(window.visibleTooltip == nil)
    platform.simulateInput(.mouseMoved(MouseEvent(position: centre(level.rowFrame(0)))))
    platform.simulateTick(timestamp: 14)
    platform.simulateTick(timestamp: 15)
    #expect(window.visibleTooltip?.text == "Fork this branch")
    withExtendedLifetime(window) {}
}
