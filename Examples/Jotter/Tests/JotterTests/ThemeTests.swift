import JotterKit
import MetalUI
import MetalUITesting
import Testing

/// The lightness of the sidebar's fill: the 260-wide rect drawn from the window's left edge.
@MainActor
private func sidebarLightness(_ window: TestWindow) throws -> Float {
    let rect = try #require(window.scene.rects.first {
        $0.bounds.origin.x == 0 && $0.bounds.size.width == 260 && $0.bounds.size.height >= 300 && $0.background.a == 1
    })
    return rect.background.l
}

@MainActor
@Test func darkSchemeChangesTheSidebarFill() throws {
    let light = try jotterWindow(seededModel(), colorScheme: .light)
    let dark = try jotterWindow(seededModel(), colorScheme: .dark)
    #expect(try sidebarLightness(light) > 0.8)
    #expect(try sidebarLightness(dark) < 0.3)
}

@MainActor
@Test func theThemeButtonAsksForTheOtherSchemeAndTheFillFollows() throws {
    let model = seededModel()
    let window = try jotterWindow(model, colorScheme: .light)
    let before = try sidebarLightness(window)
    try window.performToolbarItem("scheme")
    #expect(model.scheme == .dark)
    #expect(window.platformWindow.preferredColorSchemeRequests.last == .some(.dark))
    // AppKit answers the request by forcing the window's appearance and reporting it; the headless
    // platform records the request only, so the test reports the change as the platform would.
    window.setAppearance(.dark)
    #expect(try sidebarLightness(window) < before)
    try window.performToolbarItem("scheme")
    #expect(model.scheme == .light)
    window.setAppearance(.light)
    #expect(try sidebarLightness(window) == before)
}
