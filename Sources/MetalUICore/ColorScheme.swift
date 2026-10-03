/// Which of the two colour environments a window presents — SwiftUI's
/// `ColorScheme` (ruling `CR-J` item 1; `.light` then `.dark`, probe
/// `swiftui-colour.swift` Q6). Renamed from `Appearance`, which stays as a
/// typealias.
///
/// It lives in `MetalUICore` rather than in `MetalUIPlatform` or `MetalUI`
/// because both of those need to name it and the dependency edge runs one way:
/// `MetalUIPlatform` *reports* it (`PlatformWindow.appearance`) and `MetalUI`
/// *consumes* it (`Theme.forAppearance(_:)`, `EnvironmentValues.colorScheme`).
/// A copy in each would be two types that have to be kept in step by hand.
///
/// **Two cases and no `system` case.** "Follow the system" is not a third
/// scheme an element could paint — it is the *absence* of an override, and
/// it resolves to one of these two before any colour is chosen.
public enum ColorScheme: Sendable, Hashable, CaseIterable {
    /// The light scheme: dark content on light backgrounds.
    case light
    /// The dark scheme: light content on dark backgrounds.
    case dark
}

/// `ColorScheme`'s name before the colour work (ruling `CR-J` item 1). Kept,
/// **not deprecated**: every platform conformer, `Theme.forAppearance(_:)`
/// and test fake spells it, and the platform layer's "appearance" is the
/// right word for what a window reports.
public typealias Appearance = ColorScheme
