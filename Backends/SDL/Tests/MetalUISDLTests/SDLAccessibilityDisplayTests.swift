import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// AD-F: SDL 3.4 has no accessibility-display query, so an SDL window answers the standard
// settings (Auto-Play Animated Images `true`) and never fires its callback -- divergence 1075.

/// **22.** An SDL window reports the standard display settings, before and after a pump, and
/// calls nothing. Mutation: answer `.init(colorSchemeContrast: .increased)`.
@MainActor
@Test func anSDLWindowReportsStandardAccessibilityDisplaySettings() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "accessibility display",
                                            size: Size(width: Pixels(120), height: Pixels(80)))
    var calls = 0
    window.onAccessibilityDisplaySettingsChange = { _ in calls += 1 }
    let standard = AccessibilityDisplaySettings(playAnimatedImages: true)
    #expect(window.accessibilityDisplaySettings == standard)
    #expect(window.accessibilityDisplaySettings.colorSchemeContrast == .standard)
    platform.pumpEvents()
    #expect(window.accessibilityDisplaySettings == standard)
    #expect(calls == 0, "SDL never reports a display-settings change")
}
