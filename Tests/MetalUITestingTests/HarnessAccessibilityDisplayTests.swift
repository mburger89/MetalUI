import MetalUI
import MetalUICore
import MetalUIScene
import MetalUITesting
import Testing

// R3-10 item 7 -- the display-accessibility settings through the real `Window` over the headless
// platform (rulings `AD-E`, `AD-H`, `HT-X` 1): plain imports, what an app's test target writes. The
// observable is a label the tree builds from `@Environment` reads of the seven keys.

private struct ADReader: Component {
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiate
    @Environment(\.accessibilityInvertColors) var invert
    @Environment(\.accessibilityShowBorders) var borders
    @Environment(\.accessibilityDimFlashingLights) var flashing
    @Environment(\.accessibilityPlayAnimatedImages) var animated
    @Environment(\.legibilityWeight) var weight
    var content: some ElementGroup {
        let c = contrast == .increased ? "increased" : "standard"
        let w = weight.map { $0 == .bold ? "bold" : "regular" } ?? "nil"
        Text("c=\(c) d=\(differentiate) i=\(invert) b=\(borders) f=\(flashing) a=\(animated) w=\(w)")
    }
}

private let everyOn = AccessibilityDisplaySettings(
    colorSchemeContrast: .increased, differentiateWithoutColor: true, invertColors: true,
    showBorders: true, dimFlashingLights: true, playAnimatedImages: true)

/// **18** (`AD-E`, `AD-H`). The window reads the platform window's settings at construction (the
/// option; default AppKit's answer with nothing on) and again on every change
/// `setAccessibilityDisplaySettings` reports. Mutations: the headless init ignores the option
/// (opened-on arm); drop `Window`'s stamp (every arm but the bare); drop the callback install
/// (run-time arm).
@Test @MainActor func theWindowStampsAccessibilityDisplaySettingsFromTheHeadlessPlatform() throws {
    let normal = try harnessWindow { VStack { ADReader() } }
    _ = try normal.element(label: "c=standard d=false i=false b=false f=false a=true w=nil")

    let opened = try harnessWindow(options: .init(accessibilityDisplaySettings: everyOn)) { VStack { ADReader() } }
    #expect(opened.platformWindow.accessibilityDisplaySettings == everyOn, "the option reaches the platform window")
    _ = try opened.element(label: "c=increased d=true i=true b=true f=true a=true w=nil")

    normal.setAccessibilityDisplaySettings(everyOn)
    _ = try normal.element(label: "c=increased d=true i=true b=true f=true a=true w=nil")
    normal.setAccessibilityDisplaySettings(AccessibilityDisplaySettings())
    _ = try normal.element(label: "c=standard d=false i=false b=false f=false a=false w=nil")
}

/// **19** (`AD-E`). A report of the settings the window already has does not repaint; a change
/// does. Mutation: drop `Window.accessibilityDisplaySettings`'s `didSet` guard.
@Test @MainActor func aDisplaySettingsReportRedrawsOnlyWhenItChanges() throws {
    let window = try harnessWindow { VStack { ADReader() } }
    window.tick()
    try #require(!window.window.needsRedraw, "settled")
    window.platformWindow.simulateAccessibilityDisplaySettingsChange(to: window.platformWindow.accessibilityDisplaySettings)
    #expect(!window.window.needsRedraw, "a repeat of the current settings must not repaint")
    window.platformWindow.simulateAccessibilityDisplaySettingsChange(to: everyOn)
    #expect(window.window.needsRedraw, "a change repaints")
    window.tick()
    window.platformWindow.simulateAccessibilityDisplaySettingsChange(to: everyOn)
    #expect(!window.window.needsRedraw, "and a repeat of the new settings does not")
}
