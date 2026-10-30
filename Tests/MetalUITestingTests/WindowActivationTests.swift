import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Window and application activation (rulings `WA-A`, `WA-C`; decisions
// `docs/superpowers/2026-10-30-window-activation-decisions.md`). Plain imports, portable.

@MainActor private func activationWindow(_ app: TestApp) throws -> TestWindow {
    try app.openWindow(size: sz(200, 100)) { Color.clear.frame(width: Pixels(200), height: Pixels(100)) }
}

/// **WA-1** (`WA-A`). `Window.makeKeyAndOrderFront()` reaches that window's platform window, and only that one.
/// Mutation: `Window.makeKeyAndOrderFront()`'s body emptied.
@Test @MainActor func makeKeyAndOrderFrontReachesThePlatformWindow() throws {
    let app = try TestApp(textSystem: harnessTextSystem)
    let first = try activationWindow(app)
    let second = try activationWindow(app)
    #expect(first.platformWindow.orderFrontCalls == 0)
    second.window.makeKeyAndOrderFront()
    #expect(second.platformWindow.orderFrontCalls == 1)
    #expect(second.platformWindow.isFrontmost && second.platformWindow.isKey)
    #expect(first.platformWindow.orderFrontCalls == 0 && !first.platformWindow.isFrontmost)
}

/// **WA-2** (`WA-A`). A minimised window is restored. Mutation: the headless `orderFrontAndMakeKey()` stops
/// clearing `isMiniaturized`, or `Window.minimize()` stops reaching the platform (the control arm reddens).
@Test @MainActor func makeKeyAndOrderFrontRestoresAMinimisedWindow() throws {
    let app = try TestApp(textSystem: harnessTextSystem)
    let window = try activationWindow(app)
    window.window.minimize()
    try #require(window.platformWindow.isMiniaturized, "control: the minimise took effect")
    window.window.makeKeyAndOrderFront()
    #expect(!window.platformWindow.isMiniaturized)
}

/// **WA-3** (`WA-A`). `App.activate()` reaches the platform, once per call. Mutation: `App.activate()`'s body
/// emptied.
@Test @MainActor func appActivateReachesThePlatform() throws {
    let app = try TestApp(textSystem: harnessTextSystem)
    #expect(app.platform.activateCalls == 0)
    app.app.activate()
    #expect(app.platform.activateCalls == 1)
    app.app.activate()
    #expect(app.platform.activateCalls == 2)
}
