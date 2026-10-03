import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Colour and colour scheme (ruling `CR-M`): SDL3 has no per-window
// appearance, so an `SDLWindow` records a preferred colour scheme and keeps
// reporting the system theme (`SDL_GetSystemTheme`). Content follows the
// preference through `Window`; native decorations follow the system — a
// documented platform constraint.

/// **2.21.** The stored preference follows the calls, and `appearance` still
/// reads the system theme. Mutation: store nothing.
@MainActor
@Test func setPreferredColorSchemeIsRecordedAndTheSystemThemeStillReports() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "colour scheme",
                                            size: Size(width: Pixels(120), height: Pixels(80)))
    let system: Appearance = mui_system_theme() == 1 ? .dark : .light
    #expect(window.preferredColorScheme == nil)

    window.setPreferredColorScheme(.dark)
    #expect(window.preferredColorScheme == .dark)
    #expect(window.appearance == system, "SDL keeps reporting the system theme")

    window.setPreferredColorScheme(.light)
    #expect(window.preferredColorScheme == .light)
    #expect(window.appearance == system)

    window.setPreferredColorScheme(nil)
    #expect(window.preferredColorScheme == nil)
    #expect(window.appearance == system)
}
