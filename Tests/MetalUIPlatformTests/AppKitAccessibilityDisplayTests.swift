import Testing
import Foundation
import Metal
import AppKit
import Accessibility
import MediaAccessibility
import ObjectiveC
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
import MetalUIRender

// AD-G: an AppKit window's display-accessibility settings are a live read -- Increase Contrast,
// Differentiate Without Colour and Invert Colours from `NSWorkspace`, the others from
// `MediaAccessibility` / `Accessibility` -- re-read on the workspace's display-options
// notification, the Media Accessibility and Accessibility notifications, and application
// activation. The system settings are protected user preferences and are NOT written: the three
// `NSWorkspace` getters are swizzled in-process and restored in a `defer`; the other readers cannot
// be swizzled (human checks AD4-AD6), so a test injects `readAccessibilityDisplaySettings`.

@MainActor private var swizzledContrast = false
@MainActor private var swizzledDifferentiate = false
@MainActor private var swizzledInvert = false

private final class DisplaySwizzle: NSObject {
    @objc dynamic var fakeContrast: Bool { MainActor.assumeIsolated { swizzledContrast } }
    @objc dynamic var fakeDifferentiate: Bool { MainActor.assumeIsolated { swizzledDifferentiate } }
    @objc dynamic var fakeInvert: Bool { MainActor.assumeIsolated { swizzledInvert } }
}

@MainActor
private func swizzleDisplayOptions() throws -> () -> Void {
    var restores: [() -> Void] = []
    let pairs: [(Selector, Selector)] = [
        (#selector(getter: NSWorkspace.accessibilityDisplayShouldIncreaseContrast), #selector(getter: DisplaySwizzle.fakeContrast)),
        (#selector(getter: NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor), #selector(getter: DisplaySwizzle.fakeDifferentiate)),
        (#selector(getter: NSWorkspace.accessibilityDisplayShouldInvertColors), #selector(getter: DisplaySwizzle.fakeInvert)),
    ]
    for (original, replacement) in pairs {
        let method = try #require(class_getInstanceMethod(NSWorkspace.self, original))
        let fake = try #require(class_getInstanceMethod(DisplaySwizzle.self, replacement))
        let originalIMP = method_getImplementation(method)
        method_setImplementation(method, method_getImplementation(fake))
        restores.append { method_setImplementation(method, originalIMP) }
    }
    return { restores.forEach { $0() } }
}

@MainActor
private func openAppKitWindow(_ label: String) throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let signal = ScriptedAccessibilitySignal(false)
    let platform = AppKitPlatform(device: device, accessibilitySignal: { signal })
    let window = try platform.openWindow(title: "\(label) \(UUID().uuidString)",
                                         size: Size(width: Pixels(160), height: Pixels(120)))
    let appKit = try #require(window as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    return (appKit, nsWindow)
}

/// A window whose reader answers `script.value`, settled on the starting value before a callback is
/// installed (the live state at construction is the machine's). Returns the log of reports.
@MainActor
private final class DisplayScript {
    var value = AccessibilitySettingsForTest.base
    var fired: [AccessibilityDisplaySettings] = []
}
private enum AccessibilitySettingsForTest { static let base = AccessibilityDisplaySettings(playAnimatedImages: true) }

@MainActor
private func scriptedWindow(_ window: AppKitWindow) -> DisplayScript {
    let script = DisplayScript()
    window.readAccessibilityDisplaySettings = { script.value }
    window.refreshAccessibilityDisplaySettings()
    window.onAccessibilityDisplaySettingsChange = { script.fired.append($0) }
    return script
}

/// **14.** The reader reads Increase Contrast, Differentiate Without Colour and Invert Colours
/// from `NSWorkspace` (the swizzled answers, each on its own). Mutations: invert reads the
/// differentiate getter; contrast hard-coded `.standard`.
@MainActor
@Test func theAppKitReaderReadsContrastDifferentiateAndInvertFromNSWorkspace() throws {
    let restore = try swizzleDisplayOptions()
    defer { restore(); swizzledContrast = false; swizzledDifferentiate = false; swizzledInvert = false }

    let off = AppKitWindow.systemAccessibilityDisplaySettings()
    #expect(off.colorSchemeContrast == .standard && !off.differentiateWithoutColor && !off.invertColors)
    swizzledContrast = true
    let contrast = AppKitWindow.systemAccessibilityDisplaySettings()
    #expect(contrast.colorSchemeContrast == .increased && !contrast.differentiateWithoutColor && !contrast.invertColors)
    swizzledContrast = false; swizzledDifferentiate = true
    let differentiate = AppKitWindow.systemAccessibilityDisplaySettings()
    #expect(differentiate.colorSchemeContrast == .standard && differentiate.differentiateWithoutColor && !differentiate.invertColors)
    swizzledDifferentiate = false; swizzledInvert = true
    let invert = AppKitWindow.systemAccessibilityDisplaySettings()
    #expect(invert.colorSchemeContrast == .standard && !invert.differentiateWithoutColor && invert.invertColors)
    // The window's own getter is that live read, never a cache.
    let (window, nsWindow) = try openAppKitWindow("Display settings read")
    defer { nsWindow.close() }
    #expect(window.accessibilityDisplaySettings.invertColors == true)
}

/// **15.** The workspace's display-options notification re-reads and reports a change once per
/// change and never for an unchanged reading; a window on the default center hears the workspace's
/// own post. Mutations: the workspace handler stops calling `refreshAccessibilityDisplaySettings`;
/// drop the `!=` guard.
@MainActor
@Test func theDisplayOptionsNotificationReportsADisplaySettingsChangeOnce() throws {
    let (window, nsWindow) = try openAppKitWindow("Display options")
    defer { nsWindow.close() }
    let center = NotificationCenter()
    window.workspaceNotificationCenter = center
    let script = scriptedWindow(window)

    var changed = AccessibilitySettingsForTest.base
    changed.colorSchemeContrast = .increased
    script.value = changed
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(script.fired == [changed], "the display-options notification re-reads and reports the change")
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(script.fired == [changed], "an unchanged reading calls nothing")
    script.value = AccessibilitySettingsForTest.base
    center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(script.fired == [changed, AccessibilitySettingsForTest.base])

    let (wired, wiredNSWindow) = try openAppKitWindow("Display options wiring")
    defer { wiredNSWindow.close() }
    let wiredScript = scriptedWindow(wired)
    wiredScript.value = changed
    NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    #expect(wiredScript.fired == [changed], "production observes NSWorkspace.shared.notificationCenter")
}

/// **16.** The Media Accessibility (Dim Flashing Lights) and Accessibility (animated images)
/// notifications re-read the settings, one report each. Mutations: drop the Media Accessibility
/// registration; drop the re-registration in `notificationCenter.didSet` (the private center hears
/// neither).
@MainActor
@Test func theFlashingLightsAndAnimatedImagesNotificationsReReadTheSettings() throws {
    let (window, nsWindow) = try openAppKitWindow("Flashing lights")
    defer { nsWindow.close() }
    let center = NotificationCenter()
    window.notificationCenter = center
    let script = scriptedWindow(window)

    var flashing = AccessibilitySettingsForTest.base
    flashing.dimFlashingLights = true
    script.value = flashing
    center.post(name: Notification.Name(kMADimFlashingLightsChangedNotification as String), object: nil)
    #expect(script.fired == [flashing], "the Media Accessibility notification re-reads")

    var stopped = flashing
    stopped.playAnimatedImages = false
    script.value = stopped
    center.post(name: Notification.Name.AXAnimatedImagesEnabledDidChange, object: nil)
    #expect(script.fired == [flashing, stopped], "the Accessibility animated-images notification re-reads")
}

/// **17.** Application activation re-reads the settings: a change made while the app was in the
/// background is reported when it comes back, whichever notification was missed. Mutation: drop the
/// backstop call in `controlActiveStateNotification`.
@MainActor
@Test func anApplicationActivationReReadsTheDisplaySettings() throws {
    let (window, nsWindow) = try openAppKitWindow("Activation backstop")
    defer { nsWindow.close() }
    let center = NotificationCenter()
    window.notificationCenter = center
    let script = scriptedWindow(window)

    var changed = AccessibilitySettingsForTest.base
    changed.showBorders = true
    script.value = changed
    center.post(name: NSApplication.didResignActiveNotification, object: nil)
    #expect(script.fired.isEmpty, "resigning does not re-read")
    center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    #expect(script.fired == [changed], "becoming active re-reads and reports")
}
