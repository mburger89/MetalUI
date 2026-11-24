import MetalUICore

// `accessibilityLabel(_:)` and `accessibilityValue(_:)` on a `Component` (ruling
// `AB-AH`, Sift gap G18). A component is no `StyledElement`, so neither modifier
// compiled on one and an author set it on each `Text` branch of the body. SwiftUI
// has it on every view: the declaration goes to the accessibility element(s) the
// view produces.
//
// **Mechanism.** The component is wrapped in ONE `ModifierLayer` carrying the
// declaration in its `Handlers` — what `Component.frame(...)` already returns, so a
// further `StyledElement` modifier (`.accessibilityValue`, `.accessibilityIdentifier`)
// lands on the same layer. The tree builder then distributes a declaration on a
// plain container to its texts (AB-T, SwiftUI probe P3), so a component whose
// body is an `if`/`else` of two `Text`s labels whichever it drew, and a component
// of two texts labels both.
//
// **What it costs**, as `.frame` on a component does: the wrapper is a layout node
// (a default-style flex row over the members), not layout-transparent. Over one
// member this is the member's own size; over several it is a row, not each member
// on its own (`AB-AH` item 2).

extension Component {
    /// Replaces what an accessibility client reads as the label of the
    /// accessibility element(s) this component produces: SwiftUI's
    /// `accessibilityLabel(_:)`, distributed to the component's texts as on a
    /// stack (AB-T). Like `StyledElement.accessibilityLabel(_:)`, a `Text` with
    /// no declared value publishes the label as its value.
    ///
    /// The result wraps the component in one layout node (`AB-AH` item 2): over one
    /// member that is the member's own size, over several a row.
    public func accessibilityLabel(_ label: String) -> ModifiedElement<LayerBase> {
        accessibilityDeclaring { $0.declareAccessibilityLabel(label) }
    }

    /// Replaces what an accessibility client reads as the value of the
    /// accessibility element(s) this component produces: SwiftUI's
    /// `accessibilityValue(_:)`, distributed to the component's texts as on a
    /// stack (AB-T). On a `Text`, the text's own string becomes its label.
    ///
    /// The result wraps the component in one layout node (`AB-AH` item 2): over one
    /// member that is the member's own size, over several a row.
    public func accessibilityValue(_ value: String) -> ModifiedElement<LayerBase> {
        accessibilityDeclaring { $0.declareAccessibilityValue(value) }
    }

    private func accessibilityDeclaring(_ change: (inout Handlers) -> Void) -> ModifiedElement<LayerBase> {
        var layer = ModifierLayer(style: Style())
        change(&layer.handlers)
        return _wrap(layer)
    }
}

extension Component where Self: ProposalElementGroup {
    /// A `Component` over proposal content keeps `Component.accessibilityLabel(_:)`'s meaning, not
    /// `ProposalElementGroup`'s one-child wrapper: this overload settles the choice the compiler
    /// would otherwise call ambiguous, as `padding(_:)` does (`DX-B`).
    public func accessibilityLabel(_ label: String) -> ModifiedElement<LayerBase> {
        accessibilityDeclaring { $0.declareAccessibilityLabel(label) }
    }

    /// The `accessibilityValue(_:)` twin of ``accessibilityLabel(_:)``.
    public func accessibilityValue(_ value: String) -> ModifiedElement<LayerBase> {
        accessibilityDeclaring { $0.declareAccessibilityValue(value) }
    }
}
