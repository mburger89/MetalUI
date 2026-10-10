import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// SMK port gaps, lane 2 — the drawn menu bar: tests 2.3–2.5, 2.7–2.12 and
// 2.14–2.16 (ruling `SG-A`, amended by `SG-H` items 1–4; spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §3.4, §5). 2.6 is in
// `CommandsTests.swift` (the model's `describe` strings), 2.13 an arm of
// `everyNamingSiteStartsAReturningNameFresh`, 2.19's bar arms in
// `WindowSizingTests.swift`.
//
// An `App` over `FakePlatform` with `menuBarIsNative = false` stands for SDL:
// `setMenuBar` answers `false`, so every window of an app that declared
// `commands` draws the bar — a 25-point strip across its top under the named
// root `$menubar`, the root laid out below it. Red before: the file does not
// compile at `980663e` (no `menuBarIsNative`, `MenuBarStrip`, `barIndex`).

@MainActor private final class BarLog {
    var entries: [String] = []
}

@Observable @MainActor private final class BarModel {
    var text = "abc"
    var extra = false
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}

private let f10 = "\u{f70d}"

/// An app over a fake platform answering `native` to `setMenuBar`, its
/// windows 400 × 400.
@MainActor private func barApp(native: Bool = false) throws -> (App, FakePlatform) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    platform.menuBarIsNative = native
    platform.windowSize = 400
    return (App(platform: platform), platform)
}

/// `app`'s 400 × 400 window over `content`, recording element bounds, drawn
/// once more so the record is complete; and its fake platform window.
@MainActor private func open<Root: Element>(_ app: App, _ platform: FakePlatform,
                                            resizability: WindowResizability = .automatic,
                                            _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let window = try app.openWindow(title: "Bar", size: Size(width: px(400), height: px(400)),
                                    windowResizability: resizability, startsDisplayLink: false,
                                    content: content)
    window.recordsElementBounds = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    return (window, try #require(platform.openedWindows.last))
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: Pixels(b.origin.x.value + b.size.width.value / 2), y: Pixels(b.origin.y.value + b.size.height.value / 2))
}

@MainActor private func click(_ fake: FakePlatformWindow, at point: Point<Pixels>) {
    fake.simulateInput(.mouseDown(MouseEvent(position: point)))
    fake.simulateInput(.mouseUp(MouseEvent(position: point)))
}

/// Clicks the bar's title `index` (its recorded frame's centre).
@MainActor private func clickTitle(_ window: Window, _ fake: FakePlatformWindow, _ index: Int) throws {
    let frames = window.lastMenuBarTitleFrames
    try #require(frames.indices.contains(index), "title \(index) recorded: \(frames)")
    click(fake, at: centre(frames[index]))
}

/// Clicks the open menu's root-level row titled `title`.
@MainActor private func clickRow(_ window: Window, _ fake: FakePlatformWindow, _ title: String) throws {
    let level = try #require(window.menuSession?.levels.first, "a menu is open")
    let row = try #require(level.items.firstIndex { $0.title == title }, "\(title) in \(level.items.map(\.title))")
    click(fake, at: centre(level.rowFrame(row)))
}

/// The bounds of every id the last frame recorded under the bar's root.
@MainActor private func barBounds(_ window: Window) -> [GlobalElementID: Bounds<Pixels>] {
    window.lastElementBounds.filter { entry in
        var cursor: GlobalElementID? = entry.key
        while let current = cursor {
            if current == MenuBarStrip.rootID { return true }
            cursor = current.parent
        }
        return false
    }
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func rect(_ b: Bounds<Pixels>) -> [Float] {
    [b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value]
}

/// A `Tools` menu holding `Go`.
@MainActor private func tools(_ log: BarLog) -> some Commands {
    CommandMenu("Tools") { Button("Go") { log.entries.append("go") } }
}

// MARK: - 2.3–2.5: when the bar is drawn (`SG-A` items 1–2)

/// **2.3** (`SG-A` items 2, 5–6). A platform declining the bar and an app
/// declaring commands: each of two 400 × 400 windows records `$menubar` at
/// (0, 0, 400, 25), its root below y 25, titles Edit and Tools.
/// Mutations **M2.3a** (the bar's height 0) and **M2.3b** (only the first
/// window draws it) each redden.
@MainActor
@Test func aDeclinedMenuBarIsDrawnAboveTheRootInEveryWindow() throws {
    let (app, platform) = try barApp()
    let log = BarLog()
    app.commands { tools(log) }
    let (first, _) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    let (second, _) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    for (name, window) in [("first", first), ("second", second)] {
        let bar = try #require(window.lastElementBounds[MenuBarStrip.rootID], "\(name): $menubar recorded")
        #expect(rect(bar) == [0, 0, 400, 25], "\(name): the bar \(bar)")
        let root = try #require(window.lastElementBounds[rootID])
        #expect(root.origin.y.value >= 25, "\(name): the root below the bar \(root)")
        #expect(window.lastMenuBarTitles == ["Edit", "Tools"], "\(name): \(window.lastMenuBarTitles)")
        for (id, b) in barBounds(window) {
            #expect(b.origin.y.value >= 0 && b.origin.y.value + b.size.height.value <= 25,
                    "\(name): a bar element within y 0…25: \(id) \(b)")
        }
    }
}

/// **2.4** (`SG-A` item 2). An app that never calls `.commands` draws no bar
/// although the platform declined it: no `$menubar`, no drawn chrome, and the
/// bar was handed to the platform once, at init. Mutation: drop
/// `commandsContent != nil` — reddens.
@MainActor
@Test func anAppWithoutCommandsDrawsNoMenuBar() throws {
    let (app, platform) = try barApp()
    let (window, _) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    #expect(window.lastElementBounds[MenuBarStrip.rootID] == nil, "no bar")
    #expect(window.drawnChromeHeight == Pixels(0))
    #expect(window.lastMenuBarTitles.isEmpty)
    #expect(platform.menuBars.count == 1, "installed once, answered false")
}

/// **2.5** (`SG-A` item 1). A platform that shows the bar itself (AppKit's
/// `true`, the fake's default): no `$menubar` with commands declared.
/// Mutation: ignore the answer — reddens.
@MainActor
@Test func aMenuBarThePlatformShowsIsNotDrawn() throws {
    let (app, platform) = try barApp(native: true)
    app.commands { tools(BarLog()) }
    let (window, _) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    #expect(window.lastElementBounds[MenuBarStrip.rootID] == nil, "the platform shows it")
    #expect(window.drawnChromeHeight == Pixels(0))
}

// MARK: - 2.7–2.10: opening, switching, closing (`SG-A` item 8, `SG-H` item 4)

/// **2.7** (`SG-A` items 5, 8). A click on Tools opens its menu in the window
/// at the title's bottom-leading corner (Tools.minX, 25), remembering bar
/// index 1; a click on Go runs it once through the app's action table and
/// closes the menu. Mutations: anchor at y 0; `performMenuBarItem` not called
/// — each reddens.
@MainActor
@Test func clickingATitleOpensItsMenuBelowItAndAChoiceRunsTheCommand() throws {
    let (app, platform) = try barApp()
    let log = BarLog()
    app.commands { tools(log) }
    let (window, fake) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    try clickTitle(window, fake, 1)
    let session = try #require(window.menuSession, "the click opened a menu")
    #expect(!session.isNative && session.barIndex == 1, "in-window, bar menu 1")
    let toolsFrame = window.lastMenuBarTitleFrames[1]
    #expect(session.levels[0].origin == Point(x: toolsFrame.origin.x, y: px(25)),
            "below the title: \(session.levels[0].origin) vs \(toolsFrame)")
    #expect(session.levels[0].items.map(\.title) == ["Go"])
    try clickRow(window, fake, "Go")
    #expect(log.entries == ["go"], "the command ran once")
    #expect(window.menuSession == nil, "and the menu closed")
}

/// **2.8** (`SG-A` item 8). With Edit open, the pointer moving onto Tools
/// opens Tools; Right from Tools wraps to Edit and Left goes back to Tools,
/// the first enabled row highlighted. Mutations: no hover switch; no wrap —
/// each reddens.
@MainActor
@Test func hoveringAnotherTitleWhileOpenSwitchesAndArrowsWrap() throws {
    let (app, platform) = try barApp()
    let log = BarLog()
    app.commands { tools(log) }
    let (window, fake) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    try clickTitle(window, fake, 0)
    #expect(window.menuSession?.barIndex == 0, "Edit open")
    fake.simulateInput(.mouseMoved(MouseEvent(position: centre(window.lastMenuBarTitleFrames[1]))))
    #expect(window.menuSession?.barIndex == 1, "the pointer on Tools switched to it")
    #expect(window.menuSession?.levels.first?.items.map(\.title) == ["Go"])
    fake.simulateInput(key("\u{f703}"))
    #expect(window.menuSession?.barIndex == 0, "Right from the last menu wraps to the first")
    #expect(window.menuSession?.levels.first?.items.first?.title == "Undo")
    fake.simulateInput(key("\u{f702}"))
    #expect(window.menuSession?.barIndex == 1, "Left from the first wraps to the last")
    #expect(window.menuSession?.levels.first?.highlighted == 0, "Go highlighted")
}

/// **2.9** (`SG-A` item 8). A press on the open menu's own title closes it
/// (its release opens nothing), and Escape closes it. Mutation: a press on
/// the open title reopens it — reddens.
@MainActor
@Test func thePressedOpenTitleAndEscapeCloseTheMenu() throws {
    let (app, platform) = try barApp()
    app.commands { tools(BarLog()) }
    let (window, fake) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    try clickTitle(window, fake, 1)
    try #require(window.menuSession?.barIndex == 1)
    try clickTitle(window, fake, 1)
    #expect(window.menuSession == nil, "a press on the open title closes it")
    try clickTitle(window, fake, 1)
    try #require(window.menuSession?.barIndex == 1, "a later click opens it again")
    fake.simulateInput(key("\u{1b}"))
    #expect(window.menuSession == nil, "Escape closes it")
}

/// The id of the window's first text field, from the last frame's hitboxes.
@MainActor private func fieldHitbox(_ window: Window) throws -> Hitbox {
    try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "a text field registered")
}

/// **2.10** (`SG-A` item 8). F10 with nothing claiming it opens the first
/// menu, Edit, its first enabled row (Undo, a field focused) highlighted; an
/// `onKey` that claims F10 keeps it shut; Shift+F10 over a focused element
/// with a context menu still opens that menu (the keyboard opener off Apple);
/// F10 in a window drawing no bar opens nothing. Mutation: the F10 stage
/// before the `onKey` bubble — the second arm reddens.
@MainActor
@Test func f10OpensTheFirstMenuOnlyWhenNothingClaimsIt() throws {
    let (app, platform) = try barApp()
    app.commands { tools(BarLog()) }
    let model = BarModel()
    let text = Binding(get: { model.text }, set: { model.text = $0 })

    let (plain, plainFake) = try open(app, platform) { TextField("f", text: text).frame(width: px(200)) }
    plain.focus(try fieldHitbox(plain).id)
    redraw(plain)
    plainFake.simulateInput(key(f10))
    let session = try #require(plain.menuSession, "F10 opened a menu")
    #expect(session.barIndex == 0 && session.levels[0].items.first?.title == "Undo")
    #expect(session.levels[0].highlighted == 0, "Undo highlighted")

    let (claimed, claimedFake) = try open(app, platform) {
        Column { TextField("f", text: text).frame(width: px(200)) }
            .onKey { $0.charactersIgnoringModifiers == f10 }
    }
    claimed.focus(try fieldHitbox(claimed).id)
    redraw(claimed)
    claimedFake.simulateInput(key(f10))
    #expect(claimed.menuSession == nil, "an onKey that claims F10 keeps the bar shut")

    let (context, contextFake) = try open(app, platform) {
        TextField("f", text: text).frame(width: px(200)).contextMenu { Button("Inspect") {} }
    }
    context.contextMenuKeyPlatform = .other
    context.focus(try fieldHitbox(context).id)
    redraw(context)
    contextFake.simulateInput(key(f10, .shift))
    let contextSession = try #require(context.menuSession, "Shift+F10 opened the context menu")
    #expect(contextSession.barIndex == nil && contextSession.levels[0].items.map(\.title) == ["Inspect"])

    let (nativeApp, nativePlatform) = try barApp(native: true)
    nativeApp.commands { tools(BarLog()) }
    let (native, nativeFake) = try open(nativeApp, nativePlatform) { TextField("f", text: text) }
    nativeFake.simulateInput(key(f10))
    #expect(native.menuSession == nil, "no drawn bar, nothing to open")
}

// MARK: - 2.11, 2.12: Edit items and shortcuts (`SG-A` items 4, 10; `SG-H` items 1–2)

/// **2.11** (`SG-A` item 4, `SG-H` item 1). With a field focused holding
/// "abc", Edit ▸ Select All then Edit ▸ Copy puts "abc" on the clipboard and
/// Edit ▸ Paste with "Z" there replaces the selection — the items arrive as
/// their keys through the window's key pipeline. With nothing focused the
/// seven Edit rows are disabled and a press on Select All runs nothing, so a
/// `Button`'s ⌘A (primary + A) shortcut stays unrun. Mutations: deliver
/// nothing; deliver Copy as X; enable the rows always — each reddens.
@MainActor
@Test func aDrawnEditItemReachesTheFocusedField() throws {
    let (app, platform) = try barApp()
    app.commands { tools(BarLog()) }
    let model = BarModel()
    let log = BarLog()
    let (window, fake) = try open(app, platform) {
        Column {
            TextField("f", text: Binding(get: { model.text }, set: { model.text = $0 })).frame(width: px(200))
            Button("A") { log.entries.append("a") }.keyboardShortcut("a")
        }
    }

    try clickTitle(window, fake, 0)
    let disabled = try #require(window.menuSession?.levels.first?.items)
    let edit = disabled.filter { $0.standardAction != nil }
    #expect(edit.count == 7 && edit.allSatisfy { !$0.isEnabled },
            "nothing focused: the seven Edit rows disabled: \(edit.map { ($0.title, $0.isEnabled) })")
    try clickRow(window, fake, "Select All")
    #expect(log.entries.isEmpty, "a disabled Select All delivers no primary + A")
    window.menuSession = nil

    window.focus(try fieldHitbox(window).id)
    redraw(window)
    try clickTitle(window, fake, 0)
    let enabled = try #require(window.menuSession?.levels.first?.items).filter { $0.standardAction != nil }
    #expect(enabled.count == 7 && enabled.allSatisfy(\.isEnabled), "a field focused: the rows enabled")
    try clickRow(window, fake, "Select All")
    redraw(window)
    try clickTitle(window, fake, 0)
    try clickRow(window, fake, "Copy")
    #expect(fake.clipboard == "abc", "Select All then Copy reached the field: \(String(describing: fake.clipboard))")
    redraw(window)
    fake.clipboard = "Z"
    try clickTitle(window, fake, 0)
    try clickRow(window, fake, "Paste")
    #expect(model.text == "Z", "Paste replaced the selection: \(model.text)")
    #expect(log.entries.isEmpty, "the field claimed primary + A, not the button")
}

/// **2.12** (`SG-A` item 10, `MN-J`). A command bound to primary + G runs
/// once on that key in a window drawing the bar — the bar adds no shortcut
/// path. Mutation: also perform from the bar on a matching key — reddens
/// (twice).
@MainActor
@Test func aCommandShortcutStillRunsOnceWithADrawnBar() throws {
    let (app, platform) = try barApp()
    let log = BarLog()
    app.commands { CommandMenu("Tools") { Button("Go") { log.entries.append("go") }.keyboardShortcut("g") } }
    let (window, fake) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    try #require(window.lastElementBounds[MenuBarStrip.rootID] != nil, "the bar is drawn")
    #expect(fake.simulateInput(key("g", .primary)))
    #expect(log.entries == ["go"], "once: \(log.entries)")
}

// MARK: - 2.14–2.16

/// **2.14** (`SG-A` item 5, `SG-F`). Commands and a declined toolbar: the bar
/// at y 0…25, the strip at 25…64, the root from 64; under `.contentMinSize`
/// the platform's minimum height is the root's 50 plus 64. Mutation: the
/// strip at y 0 — reddens.
@MainActor
@Test func theMenuBarAndTheToolbarStripStackAboveTheRoot() throws {
    let (app, platform) = try barApp()
    app.commands { tools(BarLog()) }
    let window = try app.openWindow(title: "Bar", size: Size(width: px(400), height: px(400)),
                                    windowResizability: .contentMinSize, startsDisplayLink: false) {
        Column {
            Text("Body").frame(width: px(100), height: px(50)).toolbar { ToolbarItem { Button("Back") {} } }
        }
    }
    let fake = try #require(platform.openedWindows.last)
    fake.toolbarIsNative = false
    window.recordsElementBounds = true
    redraw(window)
    redraw(window)
    let bar = try #require(window.lastElementBounds[MenuBarStrip.rootID])
    let strip = try #require(window.lastElementBounds[ToolbarStrip.rootID])
    let root = try #require(window.lastElementBounds[rootID])
    #expect(rect(bar) == [0, 0, 400, 25], "the bar on top: \(bar)")
    #expect(rect(strip) == [0, 25, 400, 39], "the strip below it: \(strip)")
    #expect(root.origin.y.value >= 64, "the root below both: \(root)")
    #expect(window.drawnChromeHeight == Pixels(64))
    let minimum = try #require(fake.contentSizeLimitCalls.last?.minimum)
    #expect(minimum.height == px(114), "the root's 50 plus the chrome's 64: \(minimum)")
}

/// **2.15** (`SG-A` item 7). Once a client activated the window, each title
/// publishes as a button labelled with its title — no new role. Mutation:
/// drop `.accessibilityAddTraits(.isButton)` — reddens.
@MainActor
@Test func aMenuBarTitleIsAnAccessibleButton() throws {
    let (app, platform) = try barApp()
    app.commands { tools(BarLog()) }
    let (window, fake) = try open(app, platform) { Text("Body").frame(width: px(100), height: px(50)) }
    let tree = try controlTree(window, fake)
    for title in ["Edit", "Tools"] {
        let nodes = tree.nodes.values.filter { $0.label == title }
        #expect(nodes.count == 1 && nodes.first?.role == .button,
                "\(title): \(nodes.map { "\($0.role) \($0.label ?? "-")" })")
    }
}

/// **2.16** (`SG-A` item 9). A `CommandMenu` under `if model.extra` joins the
/// bar on the frame after the flag is written from input. Mutation: evaluate
/// the titles once at install — reddens.
@MainActor
@Test func theDrawnBarsTitlesFollowTheCommandsLive() throws {
    let (app, platform) = try barApp()
    let model = BarModel()
    app.commands {
        tools(BarLog())
        if model.extra {
            CommandMenu("Extra") { Button("More") {} }
        }
    }
    let (window, fake) = try open(app, platform) {
        Button("Toggle") { model.extra = true }.keyboardShortcut("t")
    }
    #expect(window.lastMenuBarTitles == ["Edit", "Tools"])
    #expect(fake.simulateInput(key("t", .primary)))
    window.drawFrameIfNeeded()
    #expect(window.lastMenuBarTitles == ["Edit", "Tools", "Extra"], "\(window.lastMenuBarTitles)")
}
