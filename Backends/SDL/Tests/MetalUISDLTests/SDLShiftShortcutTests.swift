import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
@testable import MetalUI
@_spi(Checks) @testable import MetalUISDL
import SDLBridge

// `KF-AL`: Alloy's palette #3 — ⇧⌘P / Ctrl+Shift+P as a command's shortcut
// confirmed on SDL. A real
// `SDLPlatform` window rendering offscreen (`@_spi(Checks)`
// `offscreenRenderers`, `TF-E`), so its frames build with no presented frame
// and these run in CI's Linux image too. Each key goes through SDL's own queue
// (`mui_push_event`, the `MUI_MOD_*` bits round-tripped through `SDL_KMOD_*`),
// then `translate`, `SDLWindow.handle` and the window's shortcut stage.

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

/// `SDLPlatform`, forwarded unchanged, remembering the windows `App` opens
/// through it — so a test can push SDL events at a window `App` owns.
@MainActor
private final class ShiftSDLPlatform: Platform {
    let base: SDLPlatform
    private(set) var opened: [SDLWindow] = []
    init(_ base: SDLPlatform) { self.base = base }
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = try base.openSDLWindow(title: title, size: size)
        opened.append(window)
        return window
    }
    func run() { base.run() }
    func setApplicationIcon(_ images: [ImageTexture]) { base.setApplicationIcon(images) }
    func setMenuBar(_ menuBar: PlatformMenuBar) -> Bool { base.setMenuBar(menuBar) }
    // The app-shell requirements (ruling `AS-H` item 4), forwarded unchanged.
    var onTerminateRequest: (() -> CloseRequestReply)? {
        get { base.onTerminateRequest }
        set { base.onTerminateRequest = newValue }
    }
    func replyToTerminateRequest(_ shouldTerminate: Bool) { base.replyToTerminateRequest(shouldTerminate) }
    func terminate() { base.terminate() }
    func activate() { base.activate() }
    var onOpenURLs: (([String]) -> Void)? {
        get { base.onOpenURLs }
        set { base.onOpenURLs = newValue }
    }
}


@MainActor
private final class Seen {
    var runs = 0
    var keys: [KeyEvent] = []
}

/// The host's primary modifier as SDL's bridge spells it: ⌘ on a Mac host, Ctrl elsewhere.
private let hostPrimary: UInt32 = {
    #if os(macOS)
    UInt32(MUI_MOD_COMMAND)
    #else
    UInt32(MUI_MOD_CONTROL)
    #endif
}()

/// An `App` with a `Palette` command-menu button on `shortcut`, and a window
/// holding a `TextField` (focused when `fieldFocused`) that records the keys
/// `onKey` sees.
@MainActor
private func paletteApp(_ seen: Seen, shortcut: KeyboardShortcut, fieldFocused: Bool)
    throws -> (ShiftSDLPlatform, App, Window, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = ShiftSDLPlatform(try SDLPlatform(hiddenWindows: true, offscreenRenderers: true))
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    app.commands {
        CommandMenu("Tools") {
            Button("Palette") { seen.runs += 1 }.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        }
    }
    let window = try app.openWindow(title: "KF-AL", size: Size(width: Pixels(300), height: Pixels(200))) {
        Box { TextField("Name", text: "") { _ in } }
            .onKey { seen.keys.append($0); return false }
    }
    let sdlWindow = try #require(platform.opened.first)
    platform.base.pumpEvents()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    if fieldFocused {
        let order = window.lastFocusRegistry.tabOrder
        try #require(order.count == 1)
        window.focus(order[0])
        window.drawFrameIfNeeded()
    }
    return (platform, app, window, sdlWindow)
}

@MainActor
private func pressP(_ platform: ShiftSDLPlatform, _ window: SDLWindow, modifiers: UInt32) {
    var event = MUIEvent()
    event.kind = UInt32(MUI_EVENT_KEY_DOWN)
    event.window_id = window.id
    event.keycode = 0x70   // SDLK_P
    event.modifiers = modifiers
    #expect(mui_push_event(&event))
    platform.base.pumpEvents()
}

/// **KF-AL.** A command button on `[.primary, .shift]` "p" runs once on the
/// host's primary + Shift + P through SDL's queue, and the key event reaching
/// the window carries "p" ignoring modifiers and "P" as its characters —
/// with no field and with a focused `TextField` (Ctrl/⌘ held, so the key is
/// not text). Mutation: `SDLKeys.characters` stops upper-casing, or `matches`
/// stops lower-casing — reddens.
@MainActor
@Test(arguments: [false, true])
func shiftPrimaryPRunsACommandShortcutOnce(fieldFocused: Bool) throws {
    let seen = Seen()
    let (platform, app, window, sdlWindow) = try paletteApp(
        seen, shortcut: KeyboardShortcut("p", modifiers: [.primary, .shift]), fieldFocused: fieldFocused)
    pressP(platform, sdlWindow, modifiers: hostPrimary | UInt32(MUI_MOD_SHIFT))
    #expect(seen.runs == 1, "the command ran once (field focused: \(fieldFocused))")
    // The key SDL translates for the press. With a field focused it also reaches `onKey` (the raw
    // bubble follows the focus chain, so with nothing focused only the translation is observable).
    let keys = SDLKeys.characters(forKeycode: 0x70, modifiers: [.shift])
    #expect(keys.ignoringModifiers == "p")
    #expect(keys.characters == "P")
    if fieldFocused {
        let key = try #require(seen.keys.last { $0.charactersIgnoringModifiers == "p" }, "the key reached the window")
        #expect(key.characters == "P")
        #expect(key.unshiftedKey == "p")
        #expect(key.modifiers.contains(.shift))
    }
    withExtendedLifetime((app, window)) {}
}

/// **KF-AL.** An explicit `[.control, .shift]` fires on Ctrl+Shift+P on every
/// host. Mutation: the bridge drops `MUI_MOD_CONTROL` — reddens.
@MainActor
@Test func explicitControlShiftPFiresOnEveryHost() throws {
    let seen = Seen()
    let (platform, app, window, sdlWindow) = try paletteApp(
        seen, shortcut: KeyboardShortcut("p", modifiers: [.control, .shift]), fieldFocused: false)
    pressP(platform, sdlWindow, modifiers: UInt32(MUI_MOD_CONTROL) | UInt32(MUI_MOD_SHIFT))
    #expect(seen.runs == 1)
    withExtendedLifetime((app, window)) {}
}

/// **KF-AL.** Without Shift (plain primary + P) and with an extra Alt
/// (primary + Alt + Shift + P) the shortcut does not fire. Mutation: match
/// modifiers with `isSuperset` — the second arm reddens.
@MainActor
@Test func plainPrimaryPAndPrimaryAltShiftPDoNotFire() throws {
    let seen = Seen()
    let (platform, app, window, sdlWindow) = try paletteApp(
        seen, shortcut: KeyboardShortcut("p", modifiers: [.primary, .shift]), fieldFocused: false)
    pressP(platform, sdlWindow, modifiers: hostPrimary)
    #expect(seen.runs == 0, "plain primary+P")
    pressP(platform, sdlWindow, modifiers: hostPrimary | UInt32(MUI_MOD_OPTION) | UInt32(MUI_MOD_SHIFT))
    #expect(seen.runs == 0, "primary+Alt+Shift+P")
    withExtendedLifetime((app, window)) {}
}
