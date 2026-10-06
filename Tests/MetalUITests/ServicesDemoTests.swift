import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Platform services, lane 3 — the services demo (ruling `SV-T`; spec §7, §6.3
// tests 6.2–6.4). `METALUI_SERVICES_DEMO=1` opens `servicesDemoContent()`
// through `openServicesDemoWindow(_:title:)` in both demos (`MetalUIDemo`,
// `MetalUISDLDemo`); these pin what a human check (group U) then looks at.
// Red before: the demo does not exist at `be806c5` — every test here fails by
// not compiling.

/// A 960 × 960 window over the services demo, menus native, accessibility
/// active, two frames drawn; the shared model reset first.
@MainActor private func servicesWindow() throws -> (Window, FakePlatformWindow) {
    servicesDemoModel.reset()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 960) { servicesDemoContent() }
    platform.presentsMenusNatively = true
    platform.simulateAccessibilityRequest(.activate)
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **6.2** (`SV-T`). Two passes of the pointer over the first hover tile count
/// two enters: the model reads 2, the tile's counter text reads "Enters: 2",
/// and its bar is 8 points per enter — 16 wide.
@MainActor
@Test func servicesDemoHoverTileCountsEnters() throws {
    let (window, platform) = try servicesWindow()
    let tiles = window.lastHitboxes.filter { $0.handlers.hover != nil }
        .sorted { $0.bounds.origin.x.value < $1.bounds.origin.x.value }
    try #require(tiles.count >= 3, "three hover tiles: \(tiles.count)")
    let tile = tiles[0].bounds
    let inside = Point(x: Pixels(tile.origin.x.value + 5), y: Pixels(tile.origin.y.value + 5))
    let outside = Point(x: Pixels(tile.origin.x.value - 10), y: Pixels(tile.origin.y.value - 10))
    for _ in 0..<2 {
        platform.simulateInput(.mouseMoved(MouseEvent(position: inside)))
        platform.simulateInput(.mouseMoved(MouseEvent(position: outside)))
    }
    #expect(servicesDemoModel.hoverEnters[0] == 2, "\(servicesDemoModel.hoverEnters)")
    window.drawFrameIfNeeded()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    #expect(tree.nodes.values.contains { $0.label == "Enters: 2" }, "the counter text")
    let bar = try #require(servicesBarBounds(window), "the first tile's bar")
    #expect(bar.size.width.value == 16, "8 points per enter: \(bar)")
    withExtendedLifetime(window) {}
}

/// The first tile's bar through the scene: the only non-empty `.accent` rect
/// 8 tall (the other tiles' bars are empty).
@MainActor private func servicesBarBounds(_ window: Window) -> Bounds<Pixels>? {
    let accent = window.theme[.accent]
    return window.lastScene.rects.first {
        ixSame(ixHsla($0.background), accent) && $0.bounds.size.height == 8 && $0.bounds.size.width > 0
    }.map(ixBounds)
}

/// **6.3** (`SV-T`). The demo's menu picker has 300 options: a click on its
/// pop-up button presents 300 items.
@MainActor
@Test func servicesDemoMenuPickerHasThreeHundredOptions() throws {
    let (window, platform) = try servicesWindow()
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let (id, _) = try #require(tree.nodes.first { $0.value.role == .popUpButton }, "the menu picker")
    #expect(platform.simulateAccessibilityRequest(.press(id)))
    let presented = try #require(platform.presentedMenus.last)
    #expect(presented.menu.items.count == 300)
    withExtendedLifetime(window) {}
}

/// **6.4** (`SV-T`, `SV-L`). The demo window opens with its 900 × 600
/// minimum: the platform's first limits call, before the first present.
@MainActor
@Test func servicesDemoOpensWithItsMinimumSize() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    let app = App(platform: platform)
    let window = try openServicesDemoWindow(app, title: "Services", startsDisplayLink: false)
    let fake = try #require(platform.openedWindows.first)
    let first = try #require(fake.contentSizeLimitCalls.first)
    #expect(first.minimum == Size(width: Pixels(900), height: Pixels(600)))
    #expect(first.presentsBefore == 0)
    #expect(servicesDemoMinimumSize == Size(width: Pixels(900), height: Pixels(600)))
    withExtendedLifetime(window) {}
}
