#if os(macOS)
import AppKit
import Accessibility
import MediaAccessibility
import MetalUICore
import MetalUIPlatform

/// The display-accessibility readers (`AD-C`, `AD-G`). **The only file importing `Accessibility`
/// and `MediaAccessibility`**, so their names stay out of the rest of the module.
///
/// What MetalUI reads is stated, not what SwiftUI reads: record 315's probe arm `T0` found
/// SwiftUI's environment unmoved by a swizzled `NSWorkspace` getter, and probe
/// `swiftui-accessibility-display.swift` H1 found it moved for the first three below -- the
/// source of the others is unmeasured.
extension AppKitWindow {
    /// The system's settings now. Increase Contrast, Differentiate Without Colour and Invert
    /// Colours are `NSWorkspace`'s; Show Borders is `AccessibilitySettings.showBordersEnabled`
    /// (macOS 26.1 and later, `false` before); Dim Flashing Lights is `MADimFlashingLightsEnabled()`;
    /// Auto-Play Animated Images is `AccessibilitySettings.animatedImagesEnabled` (macOS 15 and
    /// later) or `AXAnimatedImagesEnabled()`.
    static func systemAccessibilityDisplaySettings() -> AccessibilityDisplaySettings {
        let workspace = NSWorkspace.shared
        var showBorders = false
        if #available(macOS 26.1, *) { showBorders = AccessibilitySettings.showBordersEnabled }
        let animatedImages: Bool
        if #available(macOS 15, *) {
            animatedImages = AccessibilitySettings.animatedImagesEnabled
        } else {
            animatedImages = AXAnimatedImagesEnabled()
        }
        return AccessibilityDisplaySettings(
            colorSchemeContrast: workspace.accessibilityDisplayShouldIncreaseContrast ? .increased : .standard,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
            invertColors: workspace.accessibilityDisplayShouldInvertColors,
            showBorders: showBorders,
            dimFlashingLights: MADimFlashingLightsEnabled(),
            playAnimatedImages: animatedImages)
    }

    /// Observes the two notifications the workspace's display-options one does not carry, on
    /// `notificationCenter` (`.default` in production; a test's private center). Show Borders'
    /// own notification is the display-options name itself (measured: its string value), already
    /// observed. Whether Media Accessibility posts on the default center is unmeasured --
    /// the activation backstop in `controlActiveStateNotification` covers a miss (human check AD5).
    func observeAccessibilityDisplaySettingsNotifications() {
        let center = notificationCenter
        let selector = #selector(accessibilityDisplaySettingsNotification(_:))
        center.addObserver(self, selector: selector,
                           name: Notification.Name(kMADimFlashingLightsChangedNotification as String), object: nil)
        let animatedImages: Notification.Name
        if #available(macOS 15, *) {
            animatedImages = AccessibilitySettings.animatedImagesEnabledDidChangeNotification
        } else {
            animatedImages = Notification.Name.AXAnimatedImagesEnabledDidChange
        }
        center.addObserver(self, selector: selector, name: animatedImages, object: nil)
    }

    @objc private func accessibilityDisplaySettingsNotification(_ notification: Notification) {
        refreshAccessibilityDisplaySettings()
    }
}
#endif
