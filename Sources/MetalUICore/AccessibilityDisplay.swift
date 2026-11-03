/// How much contrast the user asked the system for (SwiftUI's `ColorSchemeContrast`,
/// ruling `AD-B`). Carried in `EnvironmentValues.colorSchemeContrast`; **no built-in view
/// reacts to it** (divergence 1076).
public enum ColorSchemeContrast: Sendable, Hashable, CaseIterable {
    /// The system default.
    case standard
    /// The user turned on Increase Contrast.
    case increased
}

/// A bolder or regular weight for text the user asked for (SwiftUI's `LegibilityWeight`,
/// ruling `AD-B`). Not `CaseIterable`, as SwiftUI's is not (probe
/// `swiftui-accessibility-display.swift` A). Carried in `EnvironmentValues.legibilityWeight`;
/// **`Text` does not read it** (divergence 1079).
public enum LegibilityWeight: Sendable, Hashable {
    /// Regular-weight text.
    case regular
    /// Bolder text.
    case bold
}

/// The display-accessibility settings a platform window reports (ruling `AD-B`, `AD-C`):
/// everything SwiftUI's `EnvironmentValues` reads from the system beside Reduce Motion and Reduce
/// Transparency (`MT-D`, which keep their own seam pairs).
///
/// ``PlatformWindow/accessibilityDisplaySettings`` answers one; `Window` stamps its six values
/// over the root environment at every draw. A default-constructed value is a bare SwiftUI `EnvironmentValues()`'s reading (probe `swiftui-accessibility-display.swift`
/// V0), **including `playAnimatedImages == false`**, which a running SwiftUI app does not see
/// (H0 reads `true`): a platform with no such setting answers `true` explicitly.
public struct AccessibilityDisplaySettings: Sendable, Hashable {
    /// Increase Contrast (`EnvironmentValues.colorSchemeContrast`).
    public var colorSchemeContrast: ColorSchemeContrast
    /// Differentiate Without Colour (`EnvironmentValues.accessibilityDifferentiateWithoutColor`).
    public var differentiateWithoutColor: Bool
    /// Invert Colours (`EnvironmentValues.accessibilityInvertColors`).
    public var invertColors: Bool
    /// Show Borders / Button Shapes (`EnvironmentValues.accessibilityShowBorders`).
    public var showBorders: Bool
    /// Dim Flashing Lights (`EnvironmentValues.accessibilityDimFlashingLights`).
    public var dimFlashingLights: Bool
    /// Auto-Play Animated Images (`EnvironmentValues.accessibilityPlayAnimatedImages`).
    public var playAnimatedImages: Bool

    /// A reading; every argument defaults to a bare SwiftUI `EnvironmentValues()`'s.
    public init(
        colorSchemeContrast: ColorSchemeContrast = .standard,
        differentiateWithoutColor: Bool = false,
        invertColors: Bool = false,
        showBorders: Bool = false,
        dimFlashingLights: Bool = false,
        playAnimatedImages: Bool = false
    ) {
        self.colorSchemeContrast = colorSchemeContrast
        self.differentiateWithoutColor = differentiateWithoutColor
        self.invertColors = invertColors
        self.showBorders = showBorders
        self.dimFlashingLights = dimFlashingLights
        self.playAnimatedImages = playAnimatedImages
    }
}
