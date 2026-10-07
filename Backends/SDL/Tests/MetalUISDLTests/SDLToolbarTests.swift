import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL

// Port gaps (medium), lane 2 — test 3.15 (rulings `MD-J` item 5, `MD-N`): SDL3
// has no native toolbar, so an `SDLWindow` records the toolbar it is handed
// and answers `false` — `Window` draws the strip itself (`MD-K`, lane 3). No
// presented frame is needed, so this is not gated on the offscreen driver.

/// **3.15.** `setToolbar` answers `false` and records its argument; `nil`
/// clears the record. Mutation **M3.15**: answer `true`.
@MainActor
@Test func theSDLWindowAsksTheFrameworkToDrawItsToolbar() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "toolbar", size: Size(width: Pixels(120), height: Pixels(80)))
    #expect(window.toolbar == nil)
    let toolbar = PlatformToolbar(items: [
        PlatformToolbarItem(id: "b", placement: .primaryAction, control: .button(title: "Go", image: nil)),
        PlatformToolbarItem(id: "search", placement: .search, control: .search(prompt: "Search", text: "")),
    ])
    #expect(window.setToolbar(toolbar) == false, "SDL draws its toolbar in the window")
    #expect(window.toolbar == toolbar)
    #expect(window.setToolbar(nil) == false)
    #expect(window.toolbar == nil, "nil clears the record")
}
