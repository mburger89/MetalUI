import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Menus, popovers and tooltips, lane 2, tests 2.6–2.8, 2.10–2.12 and 2.17
// (rulings `MN-I`, `MN-J`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §3.6, §6.2).
// An `App` over `FakePlatform` — its windows `FakePlatformWindow`s, its
// `setMenuBar` calls recorded — so the commands model and the command stage are
// pinned headless. The standard menus are the commands probe's PLAIN arm minus
// what MetalUI has no machinery for (`MN-I` item 2); `CommandMenu` and
// `CommandGroup` placement is its FULL arm's.

@MainActor private final class CLog {
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}

private let appName = ProcessInfo.processInfo.processName

/// An app over a fake platform, and the fake.
@MainActor private func fakeApp() throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    return (App(platform: platform), platform)
}

/// `app`'s window over `content`, and its fake platform window.
@MainActor private func open<Root: Element>(_ app: App, _ platform: FakePlatform,
                                            _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let window = try app.openWindow(title: "Commands", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false, content: content)
    return (window, try #require(platform.openedWindows.last))
}

/// A menu bar as strings: one line per menu, `Title: item, item …`, an item
/// as its title, `---` for a separator, `[std]` for a standard action and
/// `⌘k`/`⇧⌘z`/`⌥⌘h` for its shortcut.
private func describe(_ menus: [PlatformMenu]) -> [String] {
    func item(_ item: PlatformMenuItem) -> String {
        if case .separator = item.kind { return "---" }
        var s = item.title
        if let k = item.shortcut {
            var mods = ""
            if k.modifiers.contains(.option) { mods += "⌥" }
            if k.modifiers.contains(.shift) { mods += "⇧" }
            if k.modifiers.contains(.command) { mods += "⌘" }
            s += " \(mods)\(k.key)"
        }
        if let action = item.standardAction { s += " [\(action)]" }
        if !item.isEnabled { s += " (disabled)" }
        return s
    }
    return menus.map { "\($0.title): " + $0.items.map(item).joined(separator: ", ") }
}

/// The default bar (`MN-I` item 2), menu by menu.
private let defaultApp = "\(appName): About \(appName) [about], ---, Hide \(appName) ⌘h [hide], "
    + "Hide Others ⌥⌘h [hideOthers], Show All [showAll], ---, Quit \(appName) ⌘q [quit]"
private let defaultFile = "File: Close ⌘w [close]"
private let defaultEdit = "Edit: Undo ⌘z [undo], Redo ⇧⌘z [redo], ---, Cut ⌘x [cut], Copy ⌘c [copy], "
    + "Paste ⌘v [paste], Delete [delete], Select All ⌘a [selectAll]"
private let defaultWindow = "Window: Minimize ⌘m [minimize], Zoom [zoom], ---, Bring All to Front [bringAllToFront]"

// MARK: - 2.6–2.8: the command stage (`MN-J`)

/// **2.6** (`MN-J` items 1–2). A `Button` in the window and a command bound to
/// the same ⌘R: the button runs and the command does not — one keystroke, one
/// action, the window first. Mutation: put the command stage before
/// `dispatchShortcut`.
@MainActor
@Test func aButtonsShortcutWinsOverACommandsAndFiresOnce() throws {
    let (app, platform) = try fakeApp()
    let log = CLog()
    app.commands {
        CommandMenu("Tools") { Button("Reload") { log.entries.append("command") }.keyboardShortcut("r") }
    }
    let (window, fake) = try open(app, platform) {
        Button("B") { log.entries.append("button") }.keyboardShortcut("r")
    }
    #expect(fake.simulateInput(key("r", .command)), "claimed")
    #expect(log.entries == ["button"], "the button ran and the command did not")
    withExtendedLifetime(window) {}
}

/// **2.7** (`MN-J` item 1). With nothing in the window claiming ⌘J, the
/// command bound to it runs once and the key is claimed. Mutation: drop the
/// command stage.
@MainActor
@Test func aCommandsShortcutFiresWhenNothingInTheWindowClaimsIt() throws {
    let (app, platform) = try fakeApp()
    let log = CLog()
    app.commands {
        CommandMenu("Tools") {
            Button("Jump") { log.entries.append("jump") }.keyboardShortcut("j")
            Button("Other") { log.entries.append("other") }.keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }
    let (window, fake) = try open(app, platform) { Box().frame(width: px(10), height: px(10)) }
    #expect(fake.simulateInput(key("j", .command)))
    #expect(log.entries == ["jump"], "the matching command, once; the ⇧⌘J one did not run")
    #expect(!fake.simulateInput(key("k", .command)), "an unbound key is not claimed")
    withExtendedLifetime(window) {}
}

/// **2.8** (`MN-J` item 1). A `.disabled(true)` command does nothing and its
/// key is not claimed. Mutation: skip `isEnabled`.
@MainActor
@Test func aDisabledCommandsShortcutDoesNothing() throws {
    let (app, platform) = try fakeApp()
    let log = CLog()
    app.commands {
        CommandMenu("Tools") { Button("Jump") { log.entries.append("jump") }.keyboardShortcut("j").disabled(true) }
    }
    let (window, fake) = try open(app, platform) { Box().frame(width: px(10), height: px(10)) }
    #expect(!fake.simulateInput(key("j", .command)), "not claimed")
    #expect(log.entries.isEmpty)
    withExtendedLifetime(window) {}
}

// MARK: - 2.10–2.12: the bar's content (`MN-I` item 2)

/// **2.10** (`MN-I` item 2; PLAIN). With no commands the bar is the
/// application menu, File, Edit and Window, with PLAIN's items, shortcuts and
/// standard actions; Help is absent while its group is empty.
/// Mutation: drop `.appTermination`.
@MainActor
@Test func theDefaultMenuBarHasTheStandardMenus() throws {
    let (app, _) = try fakeApp()
    #expect(describe(app.menuBarContent()) == [defaultApp, defaultFile, defaultEdit, defaultWindow])
}

/// **2.11** (`MN-I` item 2; FULL's "Tools"). A `CommandMenu` is inserted
/// before Window, in declaration order. Mutation: append after Window.
@MainActor
@Test func aCommandMenuIsInsertedBeforeTheWindowMenu() throws {
    let (app, _) = try fakeApp()
    app.commands {
        CommandMenu("Tools") { Button("Run") {}.keyboardShortcut("r"); Divider(); Button("Off") {}.disabled(true) }
        CommandMenu("More") { Button("M") {} }
    }
    let menus = app.menuBarContent()
    try #require(menus.map(\.title) == [appName, "File", "Edit", "Tools", "More", "Window"])
    #expect(describe(menus)[3] == "Tools: Run ⌘r, ---, Off (disabled)")
}

/// **2.12** (`MN-I` items 1–2; FULL's "After New" and `replacing: .help`).
/// `CommandGroup` places its items after, before or instead of a standard
/// group's, a separator between non-empty groups; replacing `.help` with items
/// shows the Help menu. Mutation: treat `replacing` as `after`.
@MainActor
@Test func commandGroupsPlaceTheirItemsBeforeAfterAndReplacing() throws {
    let (app, _) = try fakeApp()
    app.commands {
        CommandGroup(after: .newItem) { Button("New Note") {}.keyboardShortcut("n") }
        CommandGroup(before: .appTermination) { Button("Prefs") {} }
        CommandGroup(replacing: .pasteboard) { Button("Only Paste") {} }
        CommandGroup(replacing: .help) { Button("Guide") {} }
    }
    #expect(describe(app.menuBarContent()) == [
        "\(appName): About \(appName) [about], ---, Hide \(appName) ⌘h [hide], Hide Others ⌥⌘h [hideOthers], "
            + "Show All [showAll], ---, Prefs, Quit \(appName) ⌘q [quit]",
        "File: New Note ⌘n, ---, Close ⌘w [close]",
        "Edit: Undo ⌘z [undo], Redo ⇧⌘z [redo], ---, Only Paste",
        defaultWindow,
        "Help: Guide",
    ])
}

// MARK: - 2.17: installation (`MN-I` items 3–4)

/// **2.17** (`MN-I` item 4). Every `App` installs the default bar once at
/// init, commands or not; `commands(content:)` installs again; the installed
/// bar's `perform` runs a command item's action. Mutation: install only from
/// `commands`.
@MainActor
@Test func everyAppInstallsTheDefaultMenuBar() throws {
    let (app, platform) = try fakeApp()
    try #require(platform.menuBars.count == 1, "installed once at init")
    #expect(describe(platform.menuBars[0].content()) == [defaultApp, defaultFile, defaultEdit, defaultWindow])
    let log = CLog()
    app.commands { CommandMenu("Tools") { Button("Run") { log.entries.append("run") } } }
    try #require(platform.menuBars.count == 2, "commands(content:) installs again")
    let menus = platform.menuBars[1].content()
    let tools = try #require(menus.first { $0.title == "Tools" })
    let run = try #require(tools.items.first)
    platform.menuBars[1].perform(run.id)
    #expect(log.entries == ["run"])
}

// MARK: - SMK port gaps, lane 2, test 2.6: the drawn style (`SG-A` item 3, `SG-H` item 3)

/// The drawn style's menus for `app`'s commands, as strings.
@MainActor private func drawn(_ app: App) -> [String] {
    describe(app.evaluateMenuBar(style: .drawn).menus)
}

/// **2.6** (`SG-A` item 3, `SG-H` item 3). The drawn bar follows the desktop
/// arrangement: no application menu; File = the new-item group, then the
/// additions at `.appVisibility` and `.appTermination` (their standard items
/// dropped); Edit with the standard items; the `CommandMenu`s; Window only
/// with additions; Help = the help group, then the additions at `.appInfo`;
/// an empty menu dropped. A `CommandGroup(replacing: .pasteboard)` replaces
/// the drawn Edit's Cut/Copy/Paste/Delete/Select All as it replaces AppKit's.
/// The AppKit style's strings are unchanged (`defaultApp`…`defaultWindow`).
/// Mutations: keep the application menu in the drawn style; keep the standard
/// items under a replacement — each reddens.
@MainActor
@Test func theDrawnBarFollowsTheDesktopArrangement() throws {
    let (app, _) = try fakeApp()
    #expect(drawn(app) == [String(defaultEdit)], "no commands: Edit alone: \(drawn(app))")
    app.commands {
        CommandGroup(after: .newItem) { Button("New Note") {}.keyboardShortcut("n") }
        CommandGroup(after: .appVisibility) { Button("Vis") {} }
        CommandGroup(before: .appTermination) { Button("Prefs") {} }
        CommandMenu("Tools") { Button("Go") {} }
        CommandMenu("Empty") {}
        CommandGroup(after: .windowSize) { Button("Tile") {} }
        CommandGroup(after: .help) { Button("Docs") {} }
        CommandGroup(after: .appInfo) { Button("About Me") {} }
    }
    #expect(drawn(app) == [
        "File: New Note ⌘n, ---, Vis, ---, Prefs",
        String(defaultEdit),
        "Tools: Go",
        "Window: Tile",
        "Help: Docs, ---, About Me",
    ], "\(drawn(app))")
    app.commands {
        CommandGroup(replacing: .pasteboard) { Button("Paste Plain") {} }
    }
    #expect(drawn(app) == ["Edit: Undo ⌘z [undo], Redo ⇧⌘z [redo], ---, Paste Plain"], "\(drawn(app))")
    app.commands {}
    #expect(describe(app.menuBarContent()) == [defaultApp, defaultFile, defaultEdit, defaultWindow],
            "the AppKit style is unchanged")
}
