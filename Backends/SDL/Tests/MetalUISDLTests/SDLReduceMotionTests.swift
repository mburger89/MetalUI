import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// AN-AD: SDL3 has no Reduce Motion query, so an SDL window answers `false`
// and never fires its change callback — documented at the conformer. A
// per-OS read (GNOME's `enable-animations`, Windows'
// `SPI_GETCLIENTAREAANIMATION`) is a cross-platform roadmap item, not built.

/// **1.18.** An SDL window reports no Reduce Motion, before and after a pump,
/// and calls nothing. Mutation **M1.18**: answer `true`.
@MainActor
@Test func anSDLWindowReportsNoReduceMotion() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "reduce motion",
                                            size: Size(width: Pixels(120), height: Pixels(80)))
    var calls = 0
    window.onAccessibilityReduceMotionChange = { _ in calls += 1 }
    #expect(window.accessibilityReduceMotion == false)
    platform.pumpEvents()
    #expect(window.accessibilityReduceMotion == false)
    #expect(calls == 0, "SDL never reports a Reduce Motion change")
}
