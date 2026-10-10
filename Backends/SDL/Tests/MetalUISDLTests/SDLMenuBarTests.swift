import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
@testable import MetalUI
@_spi(Checks) @testable import MetalUISDL
import SDLBridge

// SDL's menu bar. Test S2.1 of menus, popovers and tooltips (ruling `MN-I`
// item 3), rewritten as SMK port gaps' 2.17 by `SG-A` item 1: SDL3 has no
// menu-bar API, so `SDLPlatform.setMenuBar` answers `false` — MetalUI draws
// the bar in every window of an app declaring `commands` — and still records
// it, never asking it for its content. 2.18 drives that drawn bar end to end
// through SDL's own queue (spec
// `docs/superpowers/specs/2026-10-09-smk-gaps-design.md` §5).

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

/// **2.17** (`SG-A` item 1; formerly S2.1 `sdlRecordsTheMenuBarAndDrawsNothing`).
/// SDL declines the bar (`false`), records it (its `perform` reaches the
/// caller's callback) and never evaluates it. Mutation: answer `true` —
/// reddens.
@MainActor
@Test func sdlDeclinesTheMenuBarAndRecordsIt() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    var contentCalls = 0
    var performed: [Int] = []
    let shown = platform.setMenuBar(PlatformMenuBar(content: {
        contentCalls += 1
        return [PlatformMenu(token: 0, title: "Demo", items: [PlatformMenuItem(id: 1, kind: .action, title: "Go")])]
    }, perform: { performed.append($0) }))
    #expect(!shown, "SDL has no menu bar of its own: MetalUI draws it")
    let recorded = try #require(platform.menuBar, "the bar is recorded")
    #expect(contentCalls == 0, "SDL never asks the bar for its content")
    recorded.perform(1)
    #expect(performed == [1], "the recorded bar is the one installed")
    #expect(contentCalls == 0)
}

/// `SDLPlatform`, forwarded unchanged, remembering the windows `App` opens
/// through it — so a test can push SDL events at a window `App` owns.
@MainActor
private final class BarSDLPlatform: Platform {
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
private final class Pinned {
    var isOn = false
}

/// Pushes a primary press and release at `point` in `window` through SDL's
/// queue and dispatches them.
@MainActor
private func click(_ platform: BarSDLPlatform, _ window: SDLWindow, at point: Point<Pixels>) {
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_down, window.id, mui_sdl_button_left, 0,
                                     point.x.value, point.y.value))
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_up, window.id, mui_sdl_button_left, 0,
                                     point.x.value, point.y.value))
    platform.base.pumpEvents()
}

private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: Pixels(b.origin.x.value + b.size.width.value / 2), y: Pixels(b.origin.y.value + b.size.height.value / 2))
}

/// **2.18** (`SG-A` items 2, 8). A real hidden, offscreen-rendering
/// `SDLPlatform` window of an app whose commands hold a shortcut-less
/// `Toggle`: the window draws the bar; a click on the menu's title opens it
/// in the window and a click on the toggle's row flips its binding — SDL's
/// mouse events through `translate`, `SDLWindow.handle` and the window's menu
/// stages. Mutation: SDL answers `true` — reddens (no bar is drawn). Not gated
/// on `windowsPresentFrames`: offscreen renderers build frames (`TF-C`).
@MainActor
@Test func anSDLWindowDrawsTheCommandsAndAClickRunsOne() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = BarSDLPlatform(try SDLPlatform(hiddenWindows: true, offscreenRenderers: true))
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    let pinned = Pinned()
    app.commands {
        CommandMenu("Demo") { Toggle("Pinned", isOn: Binding(get: { pinned.isOn }, set: { pinned.isOn = $0 })) }
    }
    let window = try app.openWindow(title: "SG-A", size: Size(width: Pixels(300), height: Pixels(200))) {
        Text("Body")
    }
    let sdlWindow = try #require(platform.opened.first)
    platform.base.pumpEvents()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    try #require(window.lastMenuBarTitles == ["Edit", "Demo"], "the bar is drawn: \(window.lastMenuBarTitles)")
    click(platform, sdlWindow, at: centre(window.lastMenuBarTitleFrames[1]))
    let level = try #require(window.menuSession?.levels.first, "the click opened Demo")
    let row = try #require(level.items.firstIndex { $0.title == "Pinned" })
    click(platform, sdlWindow, at: centre(level.rowFrame(row)))
    #expect(pinned.isOn, "the toggle's row flipped its binding")
    #expect(window.menuSession == nil)
    withExtendedLifetime(app) {}
}
