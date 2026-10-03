import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Menus, popovers and tooltips, lane 2, tests 2.1–2.5, 2.9, 2.13–2.16 and 2.18
// (rulings `MN-C`, `MN-I`, `MN-J`, `MN-K`, `MN-AA`, `MN-AC`; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §3.5, §6.2). A
// real `AppKitPlatform` window and its own `MetalHostView`, driven with real
// `NSEvent`s and AppKit's own menu objects. **The main menu is process-wide
// state**: every test that installs a bar saves `NSApp.mainMenu` first and
// restores it (`MN-AC` item 3). Nothing sleeps: a native menu's tracking loop
// is replaced by an injected presenter, and its queued outcome by an injected
// scheduler the test drains after `presentMenu` returns.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class Log {
    var entries: [String] = []
    var flag = false
}

/// An input event as a short string: `rdown(x,y)^` (a `^` for control),
/// `key[⌘c]`, `menu(token,item)`.
private func describe(_ event: InputEvent) -> String {
    func at(_ m: MouseEvent) -> String {
        "(\(Int(m.position.x.value)),\(Int(m.position.y.value)))\(m.modifiers.contains(.control) ? "^" : "")"
    }
    switch event {
    case .mouseDown(let m): return "down\(at(m))"
    case .mouseUp(let m): return "up\(at(m))"
    case .mouseDragged(let m): return "drag\(at(m))"
    case .rightMouseDown(let m): return "rdown\(at(m))"
    case .rightMouseUp(let m): return "rup\(at(m))"
    case .keyDown(let k):
        var mods = ""
        if k.modifiers.contains(.shift) { mods += "⇧" }
        if k.modifiers.contains(.command) { mods += "⌘" }
        let name = k.charactersIgnoringModifiers == "\u{7f}" ? "⌫" : k.charactersIgnoringModifiers
        return "key[\(mods)\(name)]"
    case .menuAction(let e): return "menu(\(e.menu),\(e.item.map(String.init) ?? "nil"))"
    default: return "other"
    }
}

/// A real 400 × 200 AppKit window with nothing drawn, its `onInput` logging.
@MainActor private func hostWindow(answer: @escaping (InputEvent) -> Bool = { _ in true })
    throws -> (AppKitPlatform, AppKitWindow, NSWindow, Log) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Menus \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let log = Log()
    appKit.onInput = { event in
        log.entries.append(describe(event))
        return answer(event)
    }
    return (platform, appKit, nsWindow, log)
}

/// A mouse event at MetalUI's top-left point `(x, y)` in a 200-point-high
/// window (AppKit's window coordinates have a bottom-left origin).
@MainActor private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat,
                              _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 200 - y), modifierFlags: flags,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    eventNumber: 0, clickCount: 1, pressure: 1))
}

/// A key-down of `characters` with `flags`.
@MainActor private func keyDown(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags,
                                in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
}

/// The probe's C1 shape as a `PlatformMenu`: Copy, a separator, More ▸ [A],
/// Flag (on), Off (disabled), Shift (⇧⌘S).
private let c1Menu = PlatformMenu(token: 7, items: [
    PlatformMenuItem(id: 1, kind: .action, title: "Copy"),
    PlatformMenuItem(id: 2, kind: .separator, title: "", isEnabled: false),
    PlatformMenuItem(id: 3, kind: .submenu([PlatformMenuItem(id: 4, kind: .action, title: "A")]), title: "More"),
    PlatformMenuItem(id: 5, kind: .action, title: "Flag", isOn: true),
    PlatformMenuItem(id: 6, kind: .action, title: "Off", isEnabled: false),
    PlatformMenuItem(id: 7, kind: .action, title: "Shift",
                     shortcut: PlatformKeyEquivalent(key: "s", modifiers: [.command, .shift])),
])

/// Every item of `menu`, submenus flattened depth-first.
@MainActor private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
}

/// Runs `body` with `NSApp.mainMenu` restored afterwards (`MN-AC` item 3).
@MainActor private func preservingMainMenu(_ body: () throws -> Void) rethrows {
    let saved = NSApplication.shared.mainMenu
    defer { NSApplication.shared.mainMenu = saved }
    try body()
}

/// The top-level menu titled `title` in the installed main menu.
@MainActor private func mainMenu(_ title: String, sourceLocation: SourceLocation = #_sourceLocation) throws
    -> NSMenu {
    let bar = try #require(NSApplication.shared.mainMenu, "a main menu is installed", sourceLocation: sourceLocation)
    let item = try #require(bar.items.first { $0.title == title }, "a \(title) menu: \(bar.items.map(\.title))",
                            sourceLocation: sourceLocation)
    return try #require(item.submenu, "\(title) has a submenu", sourceLocation: sourceLocation)
}

private let appName = ProcessInfo.processInfo.processName

// MARK: - 2.1–2.4: native context menus

/// **2.1** (C1, `MN-C` item 2). The `NSMenu` built from a `PlatformMenu`:
/// titles, a separator, a submenu, an on state, a disabled item, a key
/// equivalent with its modifier mask, each action item's tag its id and its
/// target the window's, and `autoenablesItems == false` on every level (C1
/// reads `autoenables=false`). Mutation: `autoenablesItems = true`.
@MainActor
@Test func anAppKitMenuIsBuiltFromThePlatformMenu() throws {
    let target = AppKitMenuTarget()
    let menu = AppKitMenuBuilder.menu(from: c1Menu, target: target)
    try #require(menu.items.count == 6, "one NSMenuItem per item: \(menu.items.map(\.title))")
    #expect(menu.items.map(\.title) == ["Copy", "", "More", "Flag", "Off", "Shift"])
    #expect(!menu.autoenablesItems, "C1: autoenables=false")
    #expect(menu.items[1].isSeparatorItem)
    let more = try #require(menu.items[2].submenu, "More is a submenu")
    #expect(!more.autoenablesItems, "a submenu does not autoenable either")
    #expect(more.items.map(\.title) == ["A"] && more.items.first?.tag == 4)
    #expect(menu.items[3].state == .on && menu.items[0].state == .off)
    #expect(!menu.items[4].isEnabled && menu.items[0].isEnabled)
    #expect(menu.items[5].keyEquivalent == "s")
    #expect(menu.items[5].keyEquivalentModifierMask == [.command, .shift])
    #expect(menu.items[0].keyEquivalent == "")
    #expect(menu.items[0].tag == 1 && menu.items[0].target === target
            && menu.items[0].action == #selector(AppKitMenuTarget.choose(_:)))
}

/// **2.2** (`MN-C` item 4). `presentMenu` answers `true`, pops the menu up at
/// the point in the host view (flipped, so MetalUI's point unchanged), and the
/// item the user chose arrives as `.menuAction(token, item)` **only after
/// `presentMenu` returned** — never inside AppKit's tracking loop, which runs
/// inside `onInput`. Mutation: deliver inside the presenter.
@MainActor
@Test func aChosenNativeItemArrivesAsAMenuActionAfterThePopUpReturns() throws {
    let (_, appKit, _, log) = try hostWindow()
    var pending: [@MainActor () -> Void] = []
    var presented: [(NSPoint, Bool)] = []
    appKit.scheduleMenuOutcome = { pending.append($0) }
    appKit.menuPresenter = { menu, point, view in
        presented.append((point, view === appKit.hostView))
        guard let item = allItems(menu).first(where: { $0.tag == 4 }), let owner = item.menu else { return }
        owner.performActionForItem(at: owner.index(of: item))
    }
    var returned = false
    let previous = appKit.onInput
    appKit.onInput = { event in
        log.entries.append(returned ? "after" : "inside")
        return previous?(event) ?? false
    }
    let shown = appKit.presentMenu(c1Menu, at: pt(30, 40))
    returned = true
    #expect(shown, "AppKit shows the menu itself")
    try #require(presented.count == 1, "popped up once")
    #expect(presented[0].0 == NSPoint(x: 30, y: 40) && presented[0].1, "at the point, in the host view")
    #expect(log.entries.isEmpty, "nothing is delivered before presentMenu returns: \(log.entries)")
    pending.forEach { $0() }
    #expect(log.entries == ["after", "menu(7,4)"], "the chosen item, after the call returned")
}

/// **2.3** (`MN-C` item 4). A menu dismissed with no choice still reports, as
/// `.menuAction(token, nil)`, so the window's session closes. Mutation: send
/// nothing on dismissal.
@MainActor
@Test func aDismissedNativeMenuArrivesAsANilMenuAction() throws {
    let (_, appKit, _, log) = try hostWindow()
    var pending: [@MainActor () -> Void] = []
    appKit.scheduleMenuOutcome = { pending.append($0) }
    appKit.menuPresenter = { _, _, _ in }
    #expect(appKit.presentMenu(c1Menu, at: pt(10, 10)))
    pending.forEach { $0() }
    #expect(log.entries == ["menu(7,nil)"])
}

/// **2.4** (`MN-B`, `MN-AC` item 1). Real `NSEvent`s to the host view: the
/// right button arrives as `.rightMouseDown`/`.rightMouseUp`; a control-click
/// is a secondary press too — its drag dropped, its release `.rightMouseUp` —
/// and a plain click after it is primary again. Mutation: drop the control
/// mapping.
@MainActor
@Test func aRightMouseDownAndAControlClickReachOnInputAsRightMouseDown() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    let view = appKit.hostView
    view.rightMouseDown(with: try mouse(.rightMouseDown, 30, 40, in: nsWindow))
    view.rightMouseUp(with: try mouse(.rightMouseUp, 30, 40, in: nsWindow))
    view.mouseDown(with: try mouse(.leftMouseDown, 50, 60, .control, in: nsWindow))
    view.mouseDragged(with: try mouse(.leftMouseDragged, 55, 65, .control, in: nsWindow))
    view.mouseUp(with: try mouse(.leftMouseUp, 55, 65, .control, in: nsWindow))
    view.mouseDown(with: try mouse(.leftMouseDown, 70, 80, in: nsWindow))
    view.mouseUp(with: try mouse(.leftMouseUp, 70, 80, in: nsWindow))
    #expect(log.entries == ["rdown(30,40)", "rup(30,40)", "rdown(50,60)^", "rup(55,65)^", "down(70,80)", "up(70,80)"])
}

// MARK: - 2.5, 2.9: key equivalents

/// **2.5** (`MN-J` item 3). While the host view is first responder, a ⌘-key
/// reaches the window through `performKeyEquivalent` — before AppKit offers it
/// to the main menu — and the method answers the window's claim: `true` for a
/// claimed ⌘K, `false` for an unclaimed ⌘J. A key without ⌘ is not a key
/// equivalent here. Mutation: return `false` always.
@MainActor
@Test func theHostViewOffersACommandKeyToTheWindowBeforeTheMainMenu() throws {
    let (_, appKit, nsWindow, log) = try hostWindow { event in
        if case .keyDown(let key) = event { return key.charactersIgnoringModifiers == "k" }
        return false
    }
    try #require(nsWindow.makeFirstResponder(appKit.hostView), "the host view is first responder")
    let view = appKit.hostView
    #expect(view.performKeyEquivalent(with: try keyDown("k", keyCode: 40, .command, in: nsWindow)))
    #expect(!view.performKeyEquivalent(with: try keyDown("j", keyCode: 38, .command, in: nsWindow)))
    #expect(!view.performKeyEquivalent(with: try keyDown("k", keyCode: 40, [], in: nsWindow)))
    #expect(log.entries == ["key[⌘k]", "key[⌘j]"], "both ⌘-keys reached the window; the plain one did not")
}

/// **2.9** (`MN-J` item 3). A key equivalent the window declined goes on to
/// the main menu and then to `keyDown(with:)` as the same event: it is not
/// delivered a second time — nor when `performKeyEquivalent` is offered the
/// same event again (M2.9b: remove that method's own repeat guard). Another
/// event through `keyDown` still is (the positive control). Mutation: remove
/// the identity check.
@MainActor
@Test func aKeyEquivalentDeclinedByTheWindowIsNotDeliveredAgainAsAKeyDown() throws {
    let (_, appKit, nsWindow, log) = try hostWindow { _ in false }
    try #require(nsWindow.makeFirstResponder(appKit.hostView))
    let view = appKit.hostView
    let event = try keyDown("j", keyCode: 38, .command, in: nsWindow)
    #expect(!view.performKeyEquivalent(with: event))
    #expect(!view.performKeyEquivalent(with: event), "a repeat offer is declined")
    view.keyDown(with: event)
    #expect(log.entries == ["key[⌘j]"], "one delivery for one event")
    view.keyDown(with: try keyDown("j", keyCode: 38, .command, in: nsWindow))
    #expect(log.entries == ["key[⌘j]", "key[⌘j]"], "a different event is delivered")
}

// MARK: - 2.13–2.16, 2.18: the main menu

/// **2.13** (`MN-I` items 2–3; the commands probe's PLAIN arm). The installed
/// `NSApp.mainMenu` maps every standard item to AppKit's own selector and
/// target — the application menu's to `NSApp`, the rest through the responder
/// chain — with the PLAIN arm's key equivalents.
/// Mutation: map `.quit` to `performClose:`.
@MainActor
@Test func theMainMenuMapsStandardActionsToAppKitSelectors() throws {
    try preservingMainMenu {
        let (platform, _, _, _) = try hostWindow()
        let app = App(platform: platform)
        let expected: [(menu: String, title: String, action: String, key: String, toApp: Bool)] = [
            (appName, "About \(appName)", "orderFrontStandardAboutPanel:", "", true),
            (appName, "Hide \(appName)", "hide:", "h", true),
            (appName, "Hide Others", "hideOtherApplications:", "h", true),
            (appName, "Show All", "unhideAllApplications:", "", true),
            (appName, "Quit \(appName)", "terminate:", "q", true),
            ("File", "Close", "performClose:", "w", false),
            ("Edit", "Undo", "undo:", "z", false),
            ("Edit", "Redo", "redo:", "z", false),
            ("Edit", "Cut", "cut:", "x", false),
            ("Edit", "Copy", "copy:", "c", false),
            ("Edit", "Paste", "paste:", "v", false),
            ("Edit", "Delete", "delete:", "", false),
            ("Edit", "Select All", "selectAll:", "a", false),
            ("Window", "Minimize", "performMiniaturize:", "m", false),
            ("Window", "Zoom", "performZoom:", "", false),
            ("Window", "Bring All to Front", "arrangeInFront:", "", true),
        ]
        for row in expected {
            let menu = try mainMenu(row.menu)
            let item = try #require(menu.items.first { $0.title == row.title }, "\(row.title) in \(row.menu)")
            #expect(item.action.map(NSStringFromSelector) == row.action, "\(row.title)")
            #expect(item.keyEquivalent == row.key, "\(row.title)'s key")
            #expect((item.target === NSApplication.shared) == row.toApp, "\(row.title)'s target")
            #expect(row.toApp || item.target == nil, "\(row.title) goes through the responder chain")
        }
        let modifiers = try #require(mainMenu(appName).items.first { $0.title == "Hide Others" })
        #expect(modifiers.keyEquivalentModifierMask == [.command, .option])
        let redo = try #require(mainMenu("Edit").items.first { $0.title == "Redo" })
        #expect(redo.keyEquivalentModifierMask == [.command, .shift])
        withExtendedLifetime(app) {}
    }
}

/// **2.14** (`MN-K`). The Edit items' actions on the host view deliver the
/// key each item names to the window — one path into a focused field's
/// existing editing keys — and `validateMenuItem` enables them only while a
/// field is focused (a caret is set). Mutation: validate `true` always.
@MainActor
@Test func theEditMenuReachesTheFocusedFieldAsItsKeys() throws {
    let (_, appKit, _, log) = try hostWindow()
    let view = appKit.hostView
    view.currentEvent = { nil }   // a menu click, not a key equivalent
    view.cut(nil); view.copy(nil); view.paste(nil); view.undo(nil); view.redo(nil); view.selectAll(nil)
    view.delete(nil)
    #expect(log.entries == ["key[⌘x]", "key[⌘c]", "key[⌘v]", "key[⌘z]", "key[⇧⌘z]", "key[⌘a]", "key[⌫]"])
    let copy = NSMenuItem(title: "Copy", action: #selector(MetalHostView.copy(_:)), keyEquivalent: "c")
    let other = NSMenuItem(title: "Other", action: #selector(AppKitMenuTarget.choose(_:)), keyEquivalent: "")
    #expect(!view.validateMenuItem(copy), "no field focused: Copy is disabled")
    appKit.setTextInputArea(Bounds(origin: pt(10, 10), size: Size(width: px(1), height: px(16))))
    #expect(view.validateMenuItem(copy), "a focused field enables Copy")
    appKit.setTextInputArea(nil)
    #expect(!view.validateMenuItem(copy))
    #expect(view.validateMenuItem(other), "an item that is not an Edit action is not the host view's to disable")
}

/// **2.15** (`MN-I` item 3). Performing a command item of the installed main
/// menu runs its action once. Mutation: target nothing.
@MainActor
@Test func aMenuBarItemRunsItsCommand() throws {
    try preservingMainMenu {
        let (platform, _, _, _) = try hostWindow()
        let log = Log()
        let app = App(platform: platform)
        app.commands { CommandMenu("Tools") { Button("Run") { log.entries.append("run") } } }
        let tools = try mainMenu("Tools")
        let index = try #require(tools.items.firstIndex { $0.title == "Run" }, "\(tools.items.map(\.title))")
        tools.performActionForItem(at: index)
        #expect(log.entries == ["run"])
        withExtendedLifetime(app) {}
    }
}

/// **2.16** (`MN-I` items 1, 3). A menu is rebuilt from fresh content when it
/// opens (`menuNeedsUpdate`): a `Toggle` item shows its binding's state as it
/// is then. Mutation: build the items once, at install.
@MainActor
@Test func theMenuBarIsRefreshedWhenAMenuOpens() throws {
    try preservingMainMenu {
        let (platform, _, _, _) = try hostWindow()
        let log = Log()
        let app = App(platform: platform)
        app.commands {
            CommandMenu("Tools") { Toggle("Pinned", isOn: Binding(get: { log.flag }, set: { log.flag = $0 })) }
        }
        let tools = try mainMenu("Tools")
        #expect(tools.items.first?.state == .off)
        log.flag = true
        let delegate = try #require(tools.delegate, "the menu has a delegate that rebuilds it")
        delegate.menuNeedsUpdate?(tools)
        #expect(tools.items.map(\.title) == ["Pinned"])
        #expect(tools.items.first?.state == .on, "the state as it is when the menu opens")
        withExtendedLifetime(app) {}
    }
}

/// **2.18** (`MN-AA`). ⌘Z declined by the window goes on to the main menu,
/// whose Undo item runs `undo:` with that event current: the key is not
/// delivered a second time. `undo:` from a menu click (a mouse event current)
/// delivers it. Mutation: drop the identity check in the action.
@MainActor
@Test func anEditKeyTheWindowDeclinedIsNotDeliveredAgainByTheEditMenu() throws {
    let (_, appKit, nsWindow, log) = try hostWindow { _ in false }
    try #require(nsWindow.makeFirstResponder(appKit.hostView))
    let view = appKit.hostView
    let event = try keyDown("z", keyCode: 6, .command, in: nsWindow)
    #expect(!view.performKeyEquivalent(with: event))
    view.currentEvent = { event }
    view.undo(nil)
    #expect(log.entries == ["key[⌘z]"], "the declined key is not delivered again by the Edit menu")
    let click = try mouse(.leftMouseUp, 5, 5, in: nsWindow)
    view.currentEvent = { click }
    view.undo(nil)
    #expect(log.entries == ["key[⌘z]", "key[⌘z]"], "a menu click delivers the key")
}
