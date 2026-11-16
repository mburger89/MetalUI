import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// `TabStrip.tabContextMenu(_:)` (ruling `TBS-O`, record 323): PLAIN imports, headless `TestWindow`. A tab is 96..220 wide
// in a 32-point bar; a secondary press on it (title or close slot) opens the menu built for that tab and selects nothing.

@MainActor private final class MenuStripModel {
    var selected = "a"
    var log: [String] = []
    var builds: [String] = []
    var tabs: [TabStripItem<String>] = [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "b.swift"),
                                         TabStripItem(id: "c", title: "c.swift")]
    var binding: Binding<String> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
}

@MainActor private func menuStripWindow(_ m: MenuStripModel, native: Bool = true, noMenuFor: String? = nil,
                                        withMenu: Bool = true) throws -> TestWindow {
    let window = try harnessWindow(size: sz(500, 100), options: .init(presentsMenusNatively: native)) {
        VStack(spacing: 0) {
            if withMenu {
                TabStrip(selection: m.binding, tabs: m.tabs)
                    .onCloseTab { m.log.append("close \($0)") }
                    .tabContextMenu { id in
                        let _: Void = m.builds.append(id)
                        if id != noMenuFor {
                            Button("Split Right") { m.log.append("right \(id)") }
                            Button("Split Down") { m.log.append("down \(id)") }
                        }
                    }
            } else {
                TabStrip(selection: m.binding, tabs: m.tabs).onCloseTab { m.log.append("close \($0)") }
            }
            Spacer()
        }
    }
    window.tick()
    window.tick()
    return window
}

@MainActor private func titlePoint(_ window: TestWindow, _ title: String) throws -> Point<Pixels> {
    let f = try window.element(label: title).frame
    return pt(f.origin.x.value + 30, 16)
}
@MainActor private func closePoint(_ window: TestWindow, _ title: String) throws -> Point<Pixels> {
    let f = try window.element(label: title).frame
    return pt(f.origin.x.value + f.size.width.value + 9, 16)
}

/// 1 - a right click on tab b builds b's menu, opens it with b's items, leaves the selection alone, and an item's action
/// receives b. Mutation: hand the menu the strip's selection instead of the tab's id, or select on the press.
@Test @MainActor func aSecondaryClickOpensTheMenuOfThatTab() throws {
    let m = MenuStripModel()
    let window = try menuStripWindow(m)
    window.rightClick(at: try titlePoint(window, "b.swift"))
    #expect(window.presentedMenu?.items.map(\.title) == ["Split Right", "Split Down"])
    #expect(m.builds == ["b"], "built once, for b only: \(m.builds)")
    #expect(m.selected == "a", "a right click selects nothing")
    try window.chooseMenuItem("Split Down")
    #expect(m.log == ["down b"])
    #expect(m.selected == "a")
}

/// 2 - every tab gets its own: the last tab's menu hands c. Mutation: capture the first tab's id.
@Test @MainActor func eachTabsMenuHandsItsOwnId() throws {
    let m = MenuStripModel()
    let window = try menuStripWindow(m)
    for (title, id) in [("main.swift", "a"), ("c.swift", "c"), ("b.swift", "b")] {
        window.rightClick(at: try titlePoint(window, title))
        try window.chooseMenuItem("Split Right")
        #expect(m.log.last == "right \(id)")
    }
}

/// 3 - the close slot is part of the tab: a right click on it opens the tab's menu and does not close it. Mutation: attach
/// the menu to the title only.
@Test @MainActor func theCloseSlotOpensTheTabsMenuAndDoesNotClose() throws {
    let m = MenuStripModel(); m.selected = "c"
    let window = try menuStripWindow(m)
    let point = try closePoint(window, "c.swift")
    window.hover(at: point); window.tick()
    window.rightClick(at: point)
    #expect(window.presentedMenu?.items.map(\.title) == ["Split Right", "Split Down"])
    try window.chooseMenuItem("Split Right")
    #expect(m.log == ["right c"], "no close: \(m.log)")
}

/// 4 - empty bar space past the last tab opens nothing; a left click on a tab still selects; a tab whose menu is empty opens
/// nothing. Mutation: attach the menu to the whole strip.
@Test @MainActor func emptySpaceAndAnEmptyMenuOpenNothing() throws {
    let m = MenuStripModel()
    let window = try menuStripWindow(m, noMenuFor: "c")
    window.rightClick(at: pt(450, 16))
    #expect(window.presentedMenu == nil)
    window.rightClick(at: try titlePoint(window, "c.swift"))
    #expect(window.presentedMenu == nil, "an empty menu opens nothing")
    window.click(at: try titlePoint(window, "b.swift")); window.tick()
    #expect(m.selected == "b" && m.log.isEmpty)
}

/// 5 - without `tabContextMenu` a right click does nothing, and an outer `contextMenu` on the strip still opens (no empty
/// region shadows it). Mutation: always attach, with an empty menu.
@Test @MainActor func aStripWithoutAMenuLeavesAnOuterMenuAlone() throws {
    let m = MenuStripModel()
    let window = try harnessWindow(size: sz(500, 100)) {
        VStack(spacing: 0) {
            TabStrip(selection: m.binding, tabs: m.tabs)
            Spacer()
        }
        .contextMenu { Button("Outer") { m.log.append("outer") } }
    }
    window.tick(); window.tick()
    window.rightClick(at: try titlePoint(window, "b.swift"))
    #expect(window.presentedMenu?.items.map(\.title) == ["Outer"])
    let plain = try menuStripWindow(MenuStripModel(), withMenu: false)
    plain.rightClick(at: try titlePoint(plain, "b.swift"))
    #expect(plain.presentedMenu == nil)
}

/// 6 - SDL's answer: with `presentsMenusNatively` off the window draws the same items as `.menuItem` nodes. Mutation: none
/// needed beyond 1 (the same attachment); the item must run with the tab's id.
@Test @MainActor func aDrawnMenuGetsTheSameItems() throws {
    let m = MenuStripModel()
    let window = try menuStripWindow(m, native: false)
    window.rightClick(at: try titlePoint(window, "b.swift"))
    #expect(window.presentedMenu == nil)
    let items = try window.elements { $0.role == .menuItem }
    #expect(items.compactMap(\.label) == ["Split Right", "Split Down"])
    try window.click(#require(items.first { $0.label == "Split Down" }))
    #expect(m.log == ["down b"] && m.selected == "a")
}

/// 7 - an accessibility client's show-menu on a tab opens that tab's menu, and a tab advertises it only with a menu.
/// Mutation: attach the menu to the strip, not the tab.
@Test @MainActor func showMenuOnATabOpensItsMenu() throws {
    let m = MenuStripModel()
    let window = try menuStripWindow(m, noMenuFor: "c")
    let tab = try window.element(label: "b.swift")
    #expect(try window.performAccessibilityAction(.showMenu, on: tab))
    #expect(window.presentedMenu?.items.map(\.title) == ["Split Right", "Split Down"])
    #expect(m.builds.last == "b")
    try window.dismissMenu()
    let plain = try menuStripWindow(MenuStripModel(), withMenu: false)
    #expect(try !plain.performAccessibilityAction(.showMenu, on: plain.element(label: "b.swift")))
}
