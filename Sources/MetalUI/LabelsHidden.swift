import MetalUICore
import MetalUILayout

/// The environment key behind `.labelsHidden()` (ruling `LB-A`). An internal custom key: SwiftUI's is private too
/// (`View.labelsHidden()` is the only public spelling). A `Bool` compares, so a retained subtree's key sees a
/// change (`EE-F`).
struct LabelsHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Whether the controls below show no separate label, written by `.labelsHidden()`. `false` in a bare value.
    var labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }
}

extension ElementGroup {
    /// Hides the labels of the controls in this content — SwiftUI's `labelsHidden()` (ruling `LB-A`; probe
    /// `swiftui-labels-hidden.swift`). A hidden label is **removed from layout**, not shrunk: the control's own
    /// view starts at the container's leading edge with no gap (`Picker("", …)` without it keeps the 8-point
    /// gap, `P2`/`P4`). The label stays the control's accessibility label. Covers `Picker` (every style),
    /// `Toggle` (checkbox and switch), `Stepper`, `ColorPicker` and `ProgressView`'s title; an environment
    /// write, so it reaches every control below and the nearest writer wins.
    public func labelsHidden() -> EnvironmentScope<Self> {
        environment(\.labelsHidden, true)
    }
}

/// A hidden label's text, when it is a `Text` (`LB-A` item 3): what keeps a closure-labelled control's
/// accessibility label once the label is not laid out. Any other label content has none (divergence 1025).
@MainActor func labelPlainText<Label>(_ label: Label) -> String? {
    (label as? Text)?.string
}
