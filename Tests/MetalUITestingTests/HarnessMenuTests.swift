import MetalUI
import MetalUITesting
import Observation
import Testing

// Spec §4.2 tests 2.13–2.20 (lane 2): context and pull-down menus read at the
// seam and answered with `.menuAction` (ruling `HT-H` items 1–2), the drawn
// menu driven through the tree, the menu bar read and performed (`HT-H` item
// 3, TH-a) and menu content evaluated outside any window (`HT-H` item 4).
// PLAIN imports.

/// What a menu fixture toggles and logs.
@Observable @MainActor private final class MenuModel {
    var dark = false
    var log: [String] = []

    var darkBinding: Binding<Bool> {
        Binding(get: { self.dark }, set: { self.dark = $0 })
    }
}

/// A button with a context menu: Copy (⌘C), a Dark toggle, a More submenu
/// holding Deep, and a disabled Gone.
@MainActor private func contextTree(_ m: MenuModel) -> some Element {
    VStack(spacing: 0) {
        Button("Target") {}
            .contextMenu {
                Button("Copy") { m.log.append("copy") }.keyboardShortcut("c")
                Toggle("Dark", isOn: m.darkBinding)
                Menu("More") {
                    Button("Deep") { m.log.append("deep") }
                }
                Button("Gone") { m.log.append("gone") }.disabled(true)
            }
    }
}

/// 2.13 — a right click on an element presents its context menu natively;
/// the menu is read (titles, `isOn`, the shortcut) and an item chosen by
/// title runs. Mutation: `.menuAction` sent with `item: nil`.
@Test @MainActor func aContextMenuIsReadAndAnItemChosenByTitle() throws {
    let m = MenuModel()
    let window = try harnessWindow { contextTree(m) }
    #expect(window.presentedMenu == nil)
    try window.rightClick(window.element(label: "Target"))
    let menu = try #require(window.presentedMenu)
    #expect(menu.items.map(\.title) == ["Copy", "Dark", "More", "Gone"])
    #expect(menu.items.map(\.isOn) == [false, false, false, false])
    #expect(menu.items[0].shortcut == PlatformKeyEquivalent(key: "c", modifiers: .command))
    try window.chooseMenuItem("Dark")
    #expect(m.dark)
    #expect(window.presentedMenu == nil)
    try window.rightClick(window.element(label: "Target"))
    #expect(window.presentedMenu?.items[1].isOn == true, "re-evaluated at the next open")
    try window.dismissMenu()
    #expect(window.presentedMenu == nil)
    #expect(m.log.isEmpty)
}

/// 2.14 — a submenu item is chosen by its path of titles. Mutation: the path
/// walk stops at depth 1.
@Test @MainActor func aSubmenuItemIsChosenByPath() throws {
    let m = MenuModel()
    let window = try harnessWindow { contextTree(m) }
    try window.rightClick(window.element(label: "Target"))
    try window.chooseMenuItem("More", "Deep")
    #expect(m.log == ["deep"])
}

/// 2.15 — with `presentsMenusNatively` off (SDL's answer) the window draws the
/// menu: its items are `.menuItem` nodes and a click on one runs it;
/// `presentedMenu` stays `nil`. Mutation: `presentMenu` answers `true`
/// regardless of the option.
@Test @MainActor func aDrawnMenuIsDrivenThroughTheTree() throws {
    let m = MenuModel()
    let window = try harnessWindow(options: .init(presentsMenusNatively: false)) { contextTree(m) }
    try window.rightClick(window.element(label: "Target"))
    #expect(window.presentedMenu == nil, "a drawn menu is the window's, not the platform's")
    let items = try window.elements { $0.role == .menuItem || $0.role == .menuItemCheckBox }
    #expect(items.compactMap(\.label).prefix(2) == ["Copy", "Dark"])
    let copy = try #require(items.first { $0.label == "Copy" })
    try window.click(copy)
    #expect(m.log == ["copy"])
}

/// 2.16 — choosing a disabled item throws `.disabledMenuItem` and runs
/// nothing; a missing one throws `.noMenuItem`. Mutation: no enabled check.
@Test @MainActor func aDisabledMenuItemThrows() throws {
    let m = MenuModel()
    let window = try harnessWindow { contextTree(m) }
    try window.rightClick(window.element(label: "Target"))
    #expect(throws: TestHarnessError.disabledMenuItem(["Gone"])) { try window.chooseMenuItem("Gone") }
    #expect(throws: TestHarnessError.noMenuItem(["Nope"])) { try window.chooseMenuItem("Nope") }
    #expect(m.log.isEmpty)
    #expect(window.presentedMenu != nil, "a refused choice answers nothing")
}

/// 2.17 — a pull-down `Menu("Options")` clicked by label presents its items
/// the same way; once an item is chosen `presentedMenu` is `nil`. Mutation: a
/// token answered by `.menuAction` still counts as unanswered.
@Test @MainActor func aPullDownMenuIsReadTheSameWay() throws {
    let m = MenuModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Menu("Options") {
                Button("A") { m.log.append("a") }
                Button("B") { m.log.append("b") }
            }
        }
    }
    let options = try window.element(label: "Options")
    #expect(options.role == .menuButton)
    try window.click(options)
    #expect(window.presentedMenu?.items.map(\.title) == ["A", "B"])
    try window.chooseMenuItem("B")
    #expect(m.log == ["b"])
    #expect(window.presentedMenu == nil)
}

/// A test app whose menu bar has a Theme menu with a Dark toggle, and one
/// window.
@MainActor private func themedApp(_ m: MenuModel) throws -> (TestApp, TestWindow) {
    let app = try TestApp(textSystem: harnessTextSystem)
    app.app.commands {
        CommandMenu("Theme") {
            Toggle("Dark", isOn: m.darkBinding)
        }
    }
    let window = try app.openWindow(size: sz(400, 300)) { Text(m.dark ? "dark" : "light") }
    return (app, window)
}

/// 2.18 — the menu bar lists the app's commands (TH-a) and a command is
/// performed by path: the toggle flips the model and every window draws.
/// Mutation: `perform(id + 1)`.
@Test @MainActor func theMenuBarListsCommandsAndPerformsOne() throws {
    let m = MenuModel()
    let (app, window) = try themedApp(m)
    let theme = try #require(app.menuBar.first { $0.title == "Theme" })
    #expect(theme.items.map(\.title) == ["Dark"])
    let drawn = window.framesDrawn
    try app.performMenuBarItem("Theme", "Dark")
    #expect(m.dark)
    #expect(window.framesDrawn == drawn + 1)
    #expect(try window.element(label: "dark").role == .staticText)
    #expect(throws: TestHarnessError.noMenuItem(["Theme", "Light"])) { try app.performMenuBarItem("Theme", "Light") }
}

/// 2.19 — the menu bar is evaluated afresh at each read: after the perform,
/// the Dark item reads on. Mutation: the first evaluation cached.
@Test @MainActor func theMenuBarIsReEvaluatedAtEachRead() throws {
    let m = MenuModel()
    let (app, _) = try themedApp(m)
    func darkIsOn() -> Bool? { app.menuBar.first { $0.title == "Theme" }?.items.first?.isOn }
    #expect(darkIsOn() == false)
    try app.performMenuBarItem("Theme", "Dark")
    #expect(darkIsOn() == true)
}

/// 2.20 — menu content is evaluated outside any window (TH-a): kinds,
/// titles, `isOn` and the shortcut, ids numbered from 1 as a window numbers
/// them; `perform` runs a command. Mutation: `isEnabled: false` passed to the
/// evaluation.
@Test @MainActor func menuEvaluationReadsContentOutsideAnyWindow() throws {
    let m = MenuModel()
    m.dark = true
    let menu = MenuEvaluation {
        Button("Save") { m.log.append("save") }.keyboardShortcut("s")
        Divider()
        Toggle("Dark", isOn: m.darkBinding)
    }
    #expect(menu.items.map(\.title) == ["Save", "", "Dark"])
    #expect(menu.items.map(\.id) == [1, 2, 3])
    #expect(menu.items.map(\.kind) == [.action, .separator, .action])
    #expect(menu.items.map(\.isEnabled) == [true, false, true])
    #expect(menu.items.map(\.isOn) == [false, false, true])
    #expect(try menu.item("Save").shortcut == PlatformKeyEquivalent(key: "s", modifiers: .command))
    try menu.perform("Save")
    #expect(m.log == ["save"])
    try menu.perform("Dark")
    #expect(!m.dark)
    #expect(throws: TestHarnessError.noMenuItem(["Nope"])) { try menu.item("Nope") }
    let disabled = MenuEvaluation(isEnabled: false) { Button("Save") { m.log.append("again") } }
    #expect(throws: TestHarnessError.disabledMenuItem(["Save"])) { try disabled.perform("Save") }
    #expect(m.log == ["save"])
}
