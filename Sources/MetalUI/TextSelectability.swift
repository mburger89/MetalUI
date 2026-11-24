import MetalUICore

// `textSelection(_:)` on `Text` (ruling `TXS-A`, decisions `docs/superpowers/2026-11-23-text-selectability-decisions.md`,
// probe `docs/probes/swiftui-text-selection-enabled.swift`): Alloy's request for a read-only log a user can drag-select and
// copy. The API, the environment field and the container spelling; the session, geometry and window stage are in
// `SelectableText.swift`.

/// Whether the text below can be selected by the user — SwiftUI's `TextSelectability`.
///
/// SwiftUI's protocol is open, with one requirement; MetalUI's is the same shape. The two conformers are
/// ``EnabledTextSelectability`` (spelled `.enabled`) and ``DisabledTextSelectability`` (`.disabled`), the same pair
/// SwiftUI offers.
public protocol TextSelectability {
    /// Whether text below a `textSelection(_:)` of this selectability can be selected.
    static var allowsSelection: Bool { get }
}

/// The selectability that lets the user select text: spell it `.enabled`.
public struct EnabledTextSelectability: TextSelectability {
    /// `true`.
    public static var allowsSelection: Bool { true }
}

/// The selectability that does not: spell it `.disabled`.
public struct DisabledTextSelectability: TextSelectability {
    /// `false`.
    public static var allowsSelection: Bool { false }
}

extension TextSelectability where Self == EnabledTextSelectability {
    /// Lets the user select text with the pointer and copy it.
    public static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}

extension TextSelectability where Self == DisabledTextSelectability {
    /// Text is not selectable (the default).
    public static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}

extension ElementGroup {
    /// Controls whether the user can select the text below — SwiftUI's `textSelection(_:)` (ruling `TXS-A`).
    ///
    /// With `.enabled`, a primary press on a `Text` places a selection session there, a drag selects, a double click
    /// selects a word, a triple click a line, ⌘C (the primary modifier) copies the selection and ⌘A selects the whole
    /// `Text`; the right button offers Copy and Select All. The selection is the string's, whole, even for a `Text`
    /// truncated by a line limit. It is inherited by every `Text` below, and the nearest writer wins (`.disabled` under an
    /// `.enabled` removes it). **A frame with no `textSelection` does identical work** (the cost contract, `TXS-H`).
    ///
    /// Divergences from SwiftUI are in `docs/divergences.md`: the right-click menu is `[Copy, Select All]` and a declared
    /// `.contextMenu` wins; a string change drops the selection; an accessibility client cannot set it; AccessKit
    /// publishes none.
    public func textSelection<S: TextSelectability>(_ selectability: S) -> EnvironmentScope<Self> {
        environment(\.textSelectionEnabled, S.allowsSelection)
    }
}
