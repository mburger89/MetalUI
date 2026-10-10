import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
@testable import MetalUI
@_spi(Checks) @testable import MetalUISDL
import SDLBridge

// SMK port gaps, lane 1 — tests 1.3 and 1.4 (ruling `SG-B` items 3–4; spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §5). A real
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
private final class ShortcutSDLPlatform: Platform {
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
}

@MainActor
private final class Presses {
    var count = 0
}

/// An `App` over a hidden, offscreen-rendering `SDLPlatform` with one window
/// holding a `Save` button with `.keyboardShortcut("s")` — or, with
/// `explicitCommand`, `.keyboardShortcut("s", modifiers: .command)`.
@MainActor
private func shortcutApp(_ presses: Presses, explicitCommand: Bool)
    throws -> (ShortcutSDLPlatform, App, Window, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = ShortcutSDLPlatform(try SDLPlatform(hiddenWindows: true, offscreenRenderers: true))
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    let window = try app.openWindow(title: "SG-B", size: Size(width: Pixels(200), height: Pixels(120))) {
        Column {
            if explicitCommand {
                Button("Save") { presses.count += 1 }.keyboardShortcut("s", modifiers: .command)
            } else {
                Button("Save") { presses.count += 1 }.keyboardShortcut("s")
            }
        }
    }
    let sdlWindow = try #require(platform.opened.first)
    platform.base.pumpEvents()   // drain whatever opening the window queued
    return (platform, app, window, sdlWindow)
}

/// Pushes a key-down S (`SDLK_S`, `0x73`) with `modifiers` (`MUI_MOD_*`) at
/// `window` through SDL's queue and dispatches it.
@MainActor
private func pressS(_ platform: ShortcutSDLPlatform, _ window: SDLWindow, modifiers: UInt32) {
    var event = MUIEvent()
    event.kind = UInt32(MUI_EVENT_KEY_DOWN)
    event.window_id = window.id
    event.keycode = 0x73
    event.modifiers = modifiers
    #expect(mui_push_event(&event))
    platform.base.pumpEvents()
}

/// **1.3** (`SG-B` item 3). A `.keyboardShortcut("s")` written without
/// modifiers runs on Ctrl+S off Apple and not on Super+S; on macOS the
/// reverse (⌘ is the primary modifier there). Red before: the Linux arm fails
/// at `0b400b4` (Super runs it). Mutation **M1.3**: M1.1 (`primary =
/// .command` everywhere) — reddens in the Linux image.
@MainActor
@Test func ctrlSRunsADefaultShortcutOffAppleAndSuperSDoesNot() throws {
    let presses = Presses()
    let (platform, app, window, sdlWindow) = try shortcutApp(presses, explicitCommand: false)
    pressS(platform, sdlWindow, modifiers: UInt32(MUI_MOD_CONTROL))
    #if os(macOS)
    #expect(presses.count == 0, "on macOS Ctrl+S is not the primary shortcut")
    #else
    #expect(presses.count == 1, "off Apple Ctrl+S runs a default shortcut once")
    #endif
    pressS(platform, sdlWindow, modifiers: UInt32(MUI_MOD_COMMAND))
    #if os(macOS)
    #expect(presses.count == 1, "on macOS ⌘S runs a default shortcut once")
    #else
    #expect(presses.count == 1, "off Apple Super+S does not run a default shortcut")
    #endif
    withExtendedLifetime((app, window)) {}
}

/// **1.4** (`SG-B` item 4). An explicit `.command` stays the Super/Windows
/// key off Apple (⌘ on macOS): Super+S runs it and Ctrl+S does not, on every
/// platform. Green at the base — a pin of item 4. Mutation **M1.4**: the
/// bridge maps `SDL_KMOD_CTRL` to `MUI_MOD_COMMAND` — reddens.
@MainActor
@Test func anExplicitCommandStaysTheSuperKeyOffApple() throws {
    let presses = Presses()
    let (platform, app, window, sdlWindow) = try shortcutApp(presses, explicitCommand: true)
    pressS(platform, sdlWindow, modifiers: UInt32(MUI_MOD_CONTROL))
    #expect(presses.count == 0, "Ctrl+S does not run a .command shortcut")
    pressS(platform, sdlWindow, modifiers: UInt32(MUI_MOD_COMMAND))
    #expect(presses.count == 1, "Super+S (⌘S on macOS) runs a .command shortcut once")
    withExtendedLifetime((app, window)) {}
}
