import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// MT-E: SDL3 has no accessibility-display query, so an SDL window answers `false`
// and never fires its Reduce Transparency callback -- a documented platform
// constraint, as for Reduce Motion (`AN-AD`). The OS settings (GNOME, the Windows
// transparency effect) are reachable only through a new dependency or a per-OS
// shell-out; neither is taken.

/// **14.** An SDL window reports no Reduce Transparency, before and after a pump,
/// and calls nothing. Mutation: answer `true`.
@MainActor
@Test func anSDLWindowReportsNoReduceTransparency() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "reduce transparency",
                                            size: Size(width: Pixels(120), height: Pixels(80)))
    var calls = 0
    window.onAccessibilityReduceTransparencyChange = { _ in calls += 1 }
    #expect(window.accessibilityReduceTransparency == false)
    platform.pumpEvents()
    #expect(window.accessibilityReduceTransparency == false)
    #expect(calls == 0, "SDL never reports a Reduce Transparency change")
}
