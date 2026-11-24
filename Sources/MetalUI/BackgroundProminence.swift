// `EnvironmentValues.backgroundProminence` (ruling `OG-Q`, record 408, probe
// `docs/probes/swiftui-background-prominence.swift`): Alloy's request, a selected file-tree row's label that switches
// colour without every label reading the whole selection.

/// The prominence of the background a view sits on — SwiftUI's `BackgroundProminence`.
///
/// A foreground that reads ``EnvironmentValues/backgroundProminence`` can pick a colour that stays legible on a vivid
/// fill. A selected row of a ``List`` or ``Table`` is `.increased` while an unselected one is `.standard`.
public enum BackgroundProminence: Sendable, Hashable {
    /// The standard prominence of a background.
    case standard
    /// A more prominent background, such as the accent fill of a selected row, that likely wants changes to the views above it.
    case increased
}
