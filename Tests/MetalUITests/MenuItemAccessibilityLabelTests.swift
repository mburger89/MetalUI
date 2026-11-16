import Testing
import Foundation
import Metal
import MetalUICore
import MetalUITesting
import MetalUIPlatform
@testable import MetalUI

// `MN-AQ` (Alloy request; probe `docs/probes/swiftui-menu-item-accessibility.swift`; record 328): an item's
// `.accessibilityLabel` is what an accessibility client reads instead of its title, and the title is unchanged. The probe
// found SwiftUI's own `NSMenuItem` ignores the modifier, so this is MetalUI-only (class `M`), as `MN-AL`'s identifier.
// The lowering to `PlatformMenuItem`, `NSMenuItem`, the drawn menu's accessibility node, and the steady-frame cost.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

@MainActor private func evaluate<C: MenuContent>(_ content: C) -> [PlatformMenuItem] {
    content.testingEvaluateMenu(isEnabled: true).items
}

/// The session items Alloy builds: a title with a tinted dot and the label "<name>, <status>".
@MenuContentBuilder @MainActor
private func sessionMenu() -> MenuItems {
    Button { } label: { Label("Fix login", systemImage: "circle.fill") }
        .tint(.green).accessibilityLabel("Fix login, running")
    Button("Plain") {}
    Toggle("Pinned", isOn: .constant(true)).accessibilityLabel("Pinned session")
    Button("Blank") {}.accessibilityLabel("")
}

/// **MN-AQ 1** (probe A1, A1b, A4, A11, A14). The label reaches the item on a `Button` with a `Label`, a tint written
/// either side of it, a `Toggle`, a `Menu`, and a `Button(_:systemImage:)`; the title is unchanged; an item with no
/// label, or an empty one, has none. Mutation: drop `accessibilityLabel:` from `Button._menuNodes` (the first, tint and
/// systemImage rows redden), from `Toggle._menuNodes` (the toggle), from `Menu._menuNodes` (the submenu), or read the
/// label without the empty check (the blank row).
@Test @MainActor func anItemsAccessibilityLabelReachesThePlatformMenuItemAndTheTitleIsUnchanged() {
    let items = evaluate(MenuItems([
        Button { } label: { Label("Fix login", systemImage: "circle.fill") }.tint(.green).accessibilityLabel("Fix login, running"),
        Button { } label: { Label("Early", systemImage: "circle.fill") }.accessibilityLabel("Early, idle").tint(.green),
        Button("Plain") {},
        Toggle("Pinned", isOn: .constant(true)).accessibilityLabel("Pinned session"),
        Button("Blank") {}.accessibilityLabel(""),
        Button("Direct", systemImage: "star") {}.accessibilityLabel("Direct, starred"),
        Menu("More") { Button("Inner") {}.accessibilityLabel("Inner, nested") }.accessibilityLabel("More, submenu"),
    ]))
    #expect(items.map(\.title) == ["Fix login", "Early", "Plain", "Pinned", "Blank", "Direct", "More"])
    #expect(items.map(\.accessibilityLabel) == ["Fix login, running", "Early, idle", nil, "Pinned session", nil,
                                                "Direct, starred", "More, submenu"])
    #expect(items[0].image?.tint != nil, "the dot is still tinted")
    guard case .submenu(let children) = items[6].kind else { Issue.record("not a submenu"); return }
    #expect(children.first?.accessibilityLabel == "Inner, nested")
}

/// **MN-AQ 2.** A label written on the `Text` inside the button's label is not the item's (the probe's A3, A5: SwiftUI
/// reads none of them either; `Label` has no such modifier): the item has none, and the title is the string shown.
/// Mutation: read the label from `Text`'s own `axNode` in `Text._menuItemLabel()` (the item then has "inside").
@Test @MainActor func aLabelOnTheTextInsideIsNotTheItemsLabel() {
    let items = evaluate(MenuItems([
        Button { } label: { Text("B").accessibilityLabel("inside") },
    ]))
    #expect(items.map(\.title) == ["B"])
    #expect(items.map(\.accessibilityLabel) == [nil])
}

// MARK: - The drawn menu

@MainActor private func menuWindow(native: Bool) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        Box().frame(width: px(400), height: px(400)).contextMenu { sessionMenu() }
    }
    platform.presentsMenusNatively = native
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **MN-AQ 4.** The native record carries the label (`PlatformMenuItem`), and a drawn menu's row node publishes it as
/// the node's label, the visible title staying on the item; a row with none publishes its title. Mutation: publish
/// `item.title` in `appendMenuPanel` (the "Fix login, running" row is missing).
@MainActor
@Test func aDrawnMenuRowPublishesTheAccessibilityLabelAsItsNodeLabel() throws {
    let (native, nativePlatform) = try menuWindow(native: true)
    nativePlatform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    let items = try #require(nativePlatform.presentedMenus.last?.menu.items)
    #expect(items.map(\.title) == ["Fix login", "Plain", "Pinned", "Blank"])
    #expect(items.map(\.accessibilityLabel) == ["Fix login, running", nil, "Pinned session", nil])
    withExtendedLifetime(native) {}

    let (window, platform) = try menuWindow(native: false)
    platform.simulateAccessibilityRequest(.activate)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let rows = tree.nodes.values.filter { $0.role == .menuItem || $0.role == .menuItemCheckBox }
    #expect(rows.compactMap(\.label).sorted() == ["Fix login, running", "Blank", "Pinned session", "Plain"].sorted())
    #expect(rows.first { $0.label == "Pinned session" }?.role == .menuItemCheckBox)
    withExtendedLifetime(window) {}
}

// MARK: - Steady-frame cost

/// Element requests of a steady frame: three redraws, then the last one's count.
@MainActor private func steadyRequests<R: Element>(_ content: @escaping @MainActor () -> R) throws -> Int {
    let w = try TestWindow(size: Size(width: Pixels(600), height: Pixels(400))) { content() }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    return w.lastFrameWork.elementRequests
}

/// **MN-AQ 5.** A view that declares a menu whose items carry labels costs the same steady-frame element requests as
/// one whose items carry none: the menu is built when it opens, so the labels ride nothing a steady frame touches.
/// Literal: 1 request for both (the `contextMenu` element: its closure runs only at open). Mutation: declare the label
/// on the host element as well (`Color.red.accessibilityLabel("x").contextMenu { … }`): the count rises past the literal.
@MainActor @Test func aMenuWhoseItemsCarryLabelsCostsNoExtraRequestInASteadyFrame() throws {
    let plain = try steadyRequests {
        Color.red.contextMenu { Button("Fix login") {}; Button("Plain") {} }
    }
    let labelled = try steadyRequests {
        Color.red.contextMenu {
            Button("Fix login") {}.accessibilityLabel("Fix login, running")
            Button("Plain") {}.accessibilityLabel("Plain, idle")
        }
    }
    #expect(plain == labelled)
    #expect(labelled == 1)
}
