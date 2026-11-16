import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `keyCapture(except:optionAsMeta:)` (rulings `TRM-U`..`TRM-Y`, `TRM-D`; record 338; spec
// `docs/superpowers/specs/2026-11-16-terminal-design.md` §3). One window over an `App` on `FakePlatform` that
// declares a command and draws the menu bar (as SDL), so every key stage the capture layer must precede is live:
// the keymap, the command table, a focused field, `onKey`, the clipboard handlers, a `Button` shortcut, a
// `CommandMenu` shortcut, F10 and Tab. Each stage is driven twice: the capture handler answers `.handled`
// (it alone hears the key) and `.ignored` (the stage hears it as before, and the handler was offered it once).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func key(_ c: String, _ mods: Modifiers = [], repeating: Bool = false) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, isRepeat: repeating, timestamp: 0))
}

private struct CapBump: Action {}

private let f10 = "\u{f70d}"

@MainActor private final class CapLog {
    var log: [String] = []
    var text = "abc"
    var claims = true
}

@MainActor private struct CapWindow {
    let app: App
    let window: Window
    let platform: FakePlatformWindow
    let fake: FakePlatform
    let claimsFlag: CapLog?
    var focusables: [GlobalElementID] { window.lastFocusRegistry.tabOrder }
    /// Sends `event` with the capture handler answering `.ignored` and clears the log: set-up through the pipeline.
    func sendIgnoring(_ event: InputEvent) {
        let was = claimsFlag?.claims
        claimsFlag?.claims = false
        platform.simulateInput(event)
        if let was { claimsFlag?.claims = was }
        claimsFlag?.log = []
    }
    func focus(_ index: Int) throws {
        try #require(focusables.count > index, "set up: \(focusables.count) focusable elements")
        window.focus(focusables[index])
        window.drawFrameIfNeeded()
    }
}

/// The window: a root `Box` holding a focusable leaf (`onKey`, `copyable`, `pasteDestination`), a `TextField` and a
/// `Button` with a plain-key shortcut, whose one keyboard layer carries a `keyCapture` (when `capture`) and an
/// `onKeyPress` that logs `cap <characters>` and answers by `claims`. The app declares a `Tools` command bound to
/// the platform's primary modifier + G.
@MainActor private func capWindow(_ m: CapLog, capture: Bool = true, except: [KeyboardShortcut] = [],
                                  optionAsMeta: Bool = false) throws -> CapWindow {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let fake = FakePlatform(device: device)
    fake.menuBarIsNative = false
    fake.windowSize = 300
    let app = App(platform: fake)
    app.commands { CommandMenu("Tools") { Button("Go") { m.log.append("menu go") }.keyboardShortcut("g") } }
    let window = try app.openWindow(title: "Cap", size: Size(width: px(300), height: px(300)),
                                    startsDisplayLink: false) {
        let layer = Row {
            Box().frame(width: px(20), height: px(20)).focusable()
                .onKey { e in
                    if e.charactersIgnoringModifiers == "o" { m.log.append("onKey"); return true }
                    if e.modifiers.contains(.control) { m.log.append("onKey control") }
                    return false
                }
                .copyable(["copied"])
                .pasteDestination(for: String.self) { items in m.log.append("paste \(items)") }
            TextField("t", text: m.text) { m.text = $0 }
            Button("K") { m.log.append("button") }.keyboardShortcut("k", modifiers: [])
        }
        .onAction(CapBump.self) { _ in m.log.append("action") }
        .onKeyPress { press in m.log.append("cap \(press.characters)"); return m.claims ? .handled : .ignored }
        // The focusable outside the layer (index 3): focus there leaves the capture layer.
        let marked = capture ? layer.keyCapture(except: except, optionAsMeta: optionAsMeta) : layer
        return Box {
            marked
            Box().frame(width: px(20), height: px(20)).focusable()
        }
    }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let platform = try #require(fake.openedWindows.last)
    return CapWindow(app: app, window: window, platform: platform, fake: fake, claimsFlag: m)
}

// MARK: - the ordering matrix: capture first, `.ignored` reaches the stage as before

/// One stage of the pipeline, how to arrange it, the key that reaches it and what shows it ran.
@MainActor private struct Stage {
    let name: String
    let focus: Int
    let event: InputEvent
    /// Called once the window is built and focused.
    var arrange: @MainActor (CapWindow) -> Void = { _ in }
    /// What the stage did, read after the key: a log entry the stage appends, or `nil` when it shows elsewhere.
    let observe: @MainActor (CapWindow, CapLog) -> Bool
}

@MainActor private func stages() -> [Stage] {
    [
        Stage(name: "keymap", focus: 0, event: key("x"),
              arrange: { $0.window.keymap = Keymap([KeyBinding("x", CapBump())]) },
              observe: { _, m in m.log.contains("action") }),
        Stage(name: "command table (the KF-X decline)", focus: 0, event: key("j", .primary),
              arrange: { w in
                  let go: @MainActor @Sendable () -> Void = {}
                  w.window.commandShortcuts = { [(KeyboardShortcut("j"), go)] }
              },
              observe: { _, m in m.log == ["cap j"] ? false : m.log.contains("cap j") }),
        Stage(name: "field editing keys", focus: 1, event: key("\u{7f}"),
              arrange: { w in w.sendIgnoring(key("a", .primary)) },
              observe: { _, m in m.text != "abc" }),
        Stage(name: "onKey", focus: 0, event: key("o"),
              observe: { _, m in m.log.contains("onKey") }),
        Stage(name: "clipboard copy", focus: 0, event: key("c", .primary),
              observe: { w, _ in !w.platform.clipboardItemStore.isEmpty }),
        Stage(name: "clipboard paste", focus: 0, event: key("v", .primary),
              arrange: { $0.sendIgnoring(key("c", .primary)) },
              observe: { _, m in m.log.contains { $0.hasPrefix("paste") } }),
        Stage(name: "Button shortcut", focus: 0, event: key("k"),
              observe: { _, m in m.log.contains("button") }),
        Stage(name: "CommandMenu shortcut", focus: 0, event: key("g", .primary),
              observe: { _, m in m.log.contains("menu go") }),
        Stage(name: "F10", focus: 0, event: key(f10),
              observe: { w, _ in w.window.menuSession != nil }),
        Stage(name: "Tab", focus: 0, event: key("\t"),
              observe: { w, _ in w.window.focusedElement == w.focusables[1] }),
    ]
}

/// **K1** A key a stage would take reaches the capture handler first, and a handler answering `.handled` ends the
/// event: the stage never runs. Mutation: move `dispatchKeyCapture` below `dispatchAction` (the keymap runs), or
/// below any stage; each case names its stage.
@MainActor @Test func aCapturedKeyReachesTheCaptureHandlerBeforeEveryStage() throws {
    for stage in stages() {
        let m = CapLog()
        let w = try capWindow(m)
        defer { withExtendedLifetime(w) {} }
        try w.focus(stage.focus)
        stage.arrange(w)
        w.platform.simulateInput(stage.event)
        let ran = stage.observe(w, m)
        #expect(m.log.first?.hasPrefix("cap") == true, "\(stage.name): the capture handler hears it first: \(m.log)")
        #expect(!ran || stage.name.hasPrefix("command table"), "\(stage.name): a handled key reaches no stage: \(m.log)")
        if stage.name.hasPrefix("command table") {
            #expect(m.log == ["cap j"], "\(stage.name): the command did not run either: \(m.log)")
        }
    }
}

/// **K2** `.ignored` hands the key to the unchanged pipeline from its first stage: the stage runs, and the capture
/// handler was offered the key exactly once (the layer's own `onKeyPress` stage does not offer it again).
/// Mutation: drop `skipping: keyCaptureOffered` (the handler hears every ignored key twice); make an ignored
/// capture return `true` (no stage runs).
@MainActor @Test func anIgnoredKeyReachesTheStageAsBefore() throws {
    for stage in stages() {
        let m = CapLog()
        m.claims = false
        let w = try capWindow(m)
        defer { withExtendedLifetime(w) {} }
        try w.focus(stage.focus)
        stage.arrange(w)
        w.platform.simulateInput(stage.event)
        let heard = m.log.filter { $0.hasPrefix("cap") }.count
        #expect(heard == 1, "\(stage.name): offered once, not again at onKeyPress's stage: \(m.log)")
        if stage.name.hasPrefix("command table") {
            #expect(m.log.contains("cap j"), "\(stage.name): \(m.log)")
        } else {
            #expect(stage.observe(w, m), "\(stage.name): the stage ran after .ignored: \(m.log)")
        }
    }
}

/// **K3** The `KF-X` decline: without capture an `onKeyPress` is never offered a key a command binds (the command
/// runs); with capture it hears the key first, and `.ignored` still runs the command. Mutation: skip capture for a
/// key `commandShortcuts` binds.
@MainActor @Test func captureHearsAKeyACommandBindsAndAnIgnoredOneRunsTheCommand() throws {
    for capture in [false, true] {
        let m = CapLog()
        m.claims = false
        let w = try capWindow(m, capture: capture)
        defer { withExtendedLifetime(w) {} }
        try w.focus(0)
        w.platform.simulateInput(key("g", .primary))
        #expect(m.log == (capture ? ["cap g", "menu go"] : ["menu go"]), "capture \(capture): \(m.log)")
    }
}

/// **K4** ⌃Tab (the key-view loop's key on AppKit) reaches the capture handler before a keymap binding of its own, and
/// ignored it goes on to that binding. Mutation: skip Tab keys in `dispatchKeyCapture` (the binding runs first, and
/// the layer's own `onKeyPress` hears the key later, so only the keymap tells the two orders apart).
@MainActor @Test func controlTabReachesCaptureFirst() throws {
    let m = CapLog()
    let w = try capWindow(m)
    defer { withExtendedLifetime(w) {} }
    w.window.keymap = Keymap([KeyBinding("ctrl-tab", CapBump())])
    try w.focus(0)
    #expect(w.platform.simulateInput(key("\t", .control)))
    #expect(m.log == ["cap \t"], "handled: \(m.log)")
    m.log = []
    m.claims = false
    w.platform.simulateInput(key("\t", .control))
    #expect(m.log == ["cap \t", "action"], "ignored: capture, then the unchanged pipeline: \(m.log)")
}

// MARK: - except, marked text, scope

/// **K5** A key matching `except` skips capture (`.primary` per platform): the layer's `onKeyPress` then hears it at
/// its ordinary stage, after the command (here the `CommandMenu` shortcut, which declines it from `onKeyPress`) and
/// ahead of the `Button`; a near-miss (the same key with a different modifier) is still captured, offered once.
/// Mutation: ignore `exceptions`; compare the key only.
@MainActor @Test func anExceptShortcutSkipsCapture() throws {
    let m = CapLog()
    m.claims = false
    let w = try capWindow(m, except: [KeyboardShortcut("g"), KeyboardShortcut("k", modifiers: [])])
    defer { withExtendedLifetime(w) {} }
    try w.focus(0)
    w.platform.simulateInput(key("g", .primary))
    #expect(m.log == ["menu go"], "excepted: the command runs, onKeyPress declines it (KF-X): \(m.log)")
    m.log = []
    w.platform.simulateInput(key("k"))
    #expect(m.log == ["cap k", "button"], "excepted: onKeyPress's own stage, then the button: \(m.log)")
    m.log = []
    w.platform.simulateInput(key("g", [.primary, .shift]))
    w.platform.simulateInput(key("g"))
    #expect(m.log == ["cap g", "cap g"], "near-misses are captured, once each: \(m.log)")
}

/// **K6** The platform's own modifier (`ControlKeys.selectionToggleModifier()`, not a hard-coded ⌘) as an `except`
/// modifier: the excepted key reaches the command stage (the `KF-X` decline keeps `onKeyPress` out), the same key
/// plain is captured. Mutation: compare modifiers loosely, or capture before the exception is read.
@MainActor @Test func anExceptShortcutUsesThePlatformsModifier() throws {
    let m = CapLog()
    let toggle = ControlKeys.selectionToggleModifier()
    let w = try capWindow(m, except: [KeyboardShortcut("q", modifiers: toggle)])
    defer { withExtendedLifetime(w) {} }
    try w.focus(0)
    let command: @MainActor @Sendable () -> Void = { m.log.append("command") }
    w.window.commandShortcuts = { [(KeyboardShortcut("q", modifiers: toggle), command)] }
    w.platform.simulateInput(key("q", toggle))
    #expect(m.log == ["command"], "skipped capture: \(m.log)")
    m.log = []
    w.platform.simulateInput(key("q"))
    #expect(m.log == ["cap q"], "plain q captured: \(m.log)")
}

/// **K7** Nothing is captured while marked text composes: a key a capture layer would take goes through the pipeline
/// as before (a key `onKeyPress` would decline for the command stage); after the commit, capture hears it again.
/// Mutation: drop the `isComposingMarkedText` guard.
@MainActor @Test func markedTextBlocksCapture() throws {
    let m = CapLog()
    let w = try capWindow(m)
    defer { withExtendedLifetime(w) {} }
    try w.focus(1)
    try #require(w.window.focusedElement.flatMap { w.window.lastFocusRegistry.textTarget(for: $0) } != nil,
                 "set up: the field holds focus")
    w.platform.simulateInput(.textComposition(TextComposition(text: "k", selection: 1..<1)))
    try #require(w.window.isComposingMarkedText, "set up: the field composes")
    w.platform.simulateInput(key("g", .primary))
    #expect(!m.log.contains("cap g"), "composing: no capture (the pipeline's own answer is not pinned here): \(m.log)")
    w.platform.simulateInput(.textInput("k"))
    m.log = []
    w.platform.simulateInput(key("g", .primary))
    #expect(m.log == ["cap g"], "after the commit capture hears again: \(m.log)")
}

/// **K8** Capture on a layer outside the focus chain does nothing: focus in a sibling subtree, or nothing focused.
/// Mutation: offer to every capture layer, not those on the focus chain.
@MainActor @Test func captureOutsideTheFocusChainDoesNothing() throws {
    let m = CapLog()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let fake = FakePlatform(device: device)
    fake.windowSize = 200
    let app = App(platform: fake)
    let window = try app.openWindow(title: "Out", size: Size(width: px(200), height: px(200)),
                                    startsDisplayLink: false) {
        Row {
            Box().frame(width: px(20), height: px(20)).focusable()
            Box { Box().frame(width: px(20), height: px(20)).focusable() }
                .onKeyPress { press in m.log.append("cap \(press.characters)"); return .handled }
                .keyCapture()
        }
    }
    defer { withExtendedLifetime(window) {} }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let platform = try #require(fake.openedWindows.last)
    platform.simulateInput(key("a"))
    #expect(m.log.isEmpty, "nothing focused: \(m.log)")
    window.focus(window.lastFocusRegistry.tabOrder[0])
    window.drawFrameIfNeeded()
    platform.simulateInput(key("a"))
    #expect(m.log.isEmpty, "a sibling focused: \(m.log)")
    window.focus(window.lastFocusRegistry.tabOrder[1])
    window.drawFrameIfNeeded()
    platform.simulateInput(key("a"))
    #expect(m.log == ["cap a"], "the layer's descendant focused: \(m.log)")
}

/// **K9** The layer's `onKeyPress` handlers hear the key last-written first, and the outermost capture layer
/// first (`KF-C`) when two nest. Mutation: walk the chain innermost first.
@MainActor @Test func nestedCaptureLayersHearOutermostFirst() throws {
    let m = CapLog()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let fake = FakePlatform(device: device)
    fake.windowSize = 200
    let app = App(platform: fake)
    let window = try app.openWindow(title: "Nest", size: Size(width: px(200), height: px(200)),
                                    startsDisplayLink: false) {
        Box { Box().frame(width: px(20), height: px(20)).focusable() }
            .onKeyPress { _ in m.log.append("inner-1"); return .ignored }
            .onKeyPress { _ in m.log.append("inner-2"); return .ignored }
            .keyCapture()
            .padding(2)
            .onKeyPress { _ in m.log.append("outer"); return .ignored }
            .keyCapture()
    }
    defer { withExtendedLifetime(window) {} }
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let platform = try #require(fake.openedWindows.last)
    window.focus(window.lastFocusRegistry.tabOrder[0])
    window.drawFrameIfNeeded()
    platform.simulateInput(key("a"))
    #expect(m.log == ["outer", "inner-2", "inner-1"], "\(m.log)")
}

// MARK: - the Option hint

/// **K10** `optionAsMeta: true` hints the platform when focus enters the capture layer and withdraws the hint when
/// it leaves; moving inside the layer sends nothing more; without `optionAsMeta` no hint is ever sent. Mutation: send
/// the hint at build time, never withdraw it, send it every frame, or send it for `optionAsMeta: false`.
@MainActor @Test func theOptionHintFollowsFocusIntoAndOutOfTheCaptureLayer() throws {
    let m = CapLog()
    let w = try capWindow(m, optionAsMeta: true)
    defer { withExtendedLifetime(w) {} }
    try w.focus(3)   // outside the layer
    let outside = w.platform.rawOptionKeyRequests
    #expect(outside.last != true, "outside the layer the hint is off: \(outside)")
    try w.focus(0)
    #expect(w.platform.rawOptionKeyRequests == outside + [true], "\(w.platform.rawOptionKeyRequests)")
    try w.focus(1)
    w.window.setNeedsRedraw(); w.window.drawFrameIfNeeded()
    #expect(w.platform.rawOptionKeyRequests == outside + [true], "inside the layer, steady: nothing more")
    try w.focus(3)
    #expect(w.platform.rawOptionKeyRequests == outside + [true, false], "\(w.platform.rawOptionKeyRequests)")
    let plain = CapLog()
    let p = try capWindow(plain, optionAsMeta: false)
    defer { withExtendedLifetime(p) {} }
    try p.focus(0)
    try p.focus(3)
    #expect(p.platform.rawOptionKeyRequests.isEmpty, "\(p.platform.rawOptionKeyRequests)")
}

/// **K11** The same ordering holds for `onKeyPress` handlers on the other conformer families: `keyCapture` on a
/// proposal chain (`KF-AD`) and on a plain `ElementGroup` (`KF-AC`/`KF-AE`) marks its layer.
@MainActor @Test func keyCaptureJoinsTheKeyboardLayerOnEveryConformerFamily() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    func run(_ make: @escaping @MainActor (CapLog) -> some ElementGroup) throws -> [String] {
        let m = CapLog()
        let fake = FakePlatform(device: device)
        fake.windowSize = 200
        let app = App(platform: fake)
        let window = try app.openWindow(title: "Fam", size: Size(width: px(200), height: px(200)),
                                        startsDisplayLink: false) {
            Box { make(m) }
        }
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let platform = try #require(fake.openedWindows.last)
        window.focus(window.lastFocusRegistry.tabOrder[0])
        window.drawFrameIfNeeded()
        platform.simulateInput(key("\t"))   // would move focus (one tab stop: stays) — only the handler matters
        platform.simulateInput(key("a"))
        withExtendedLifetime(window) {}
        return m.log
    }
    let chain = try run { m in
        VStack { Box().frame(width: px(20), height: px(20)).focusable() }.nativeFrame(width: px(50), height: px(50))
            .onKeyPress { press in m.log.append("cap \(press.characters)"); return .handled }.keyCapture()
    }
    #expect(chain == ["cap \t", "cap a"], "proposal chain: \(chain)")
    let group = try run { m in
        Pair(Box().frame(width: px(20), height: px(20)).focusable(), Box())
            .onKeyPress { press in m.log.append("cap \(press.characters)"); return .handled }.keyCapture()
    }
    #expect(group == ["cap \t", "cap a"], "plain group: \(group)")
}
