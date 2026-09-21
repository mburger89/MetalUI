import MetalUICore

// The public accessibility modifiers (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, lane 3).
//
// Each writes one field of `Handlers` through `handling`, exactly as `onClick`
// and `focusable` do, so `Handlers` gains no member and `HandlerShape` needs no
// field. What a client reads is decided later, by `AccessibilityTreeBuilder`,
// which is what lets one spelling mean the right thing wherever it lands:
//
// - **On a leaf** (`Text`, a sized `Box`) the declaration is the node's own.
// - **On a plain container or a wrapper** (`Column { … }`, `.padding`,
//   `.frame`) the declaration is **distributed** to its children, and the outer
//   declaration wins (ruling AB-T; SwiftUI arms R3, R4, R8, R10, R15, R18). So
//   `Text("Go").padding(4).accessibilityLabel("X")` labels the text, as SwiftUI
//   does, whatever `.padding` is built from.
// - **On a clickable, focusable or adjustable container** it stays on that
//   container's node. For a focusable or adjustable one that is a recorded
//   divergence from SwiftUI (AB-T, arms C1, C5).
//
// **Not offered on `Component`**, on `onClick`'s footing: a caller's modifier
// distributes to each top-level node (CO-U), so one label would become several.

extension StyledElement {
    /// Replaces what an accessibility client reads as this element's label.
    ///
    /// On a `Text` with no declared value, the label is published **as the
    /// value** and the text has no label, as SwiftUI publishes
    /// `Text("Hello").accessibilityLabel("Greeting")` (AB-F, arm 10a). On a
    /// clickable element it is the button's label, and it stops the button
    /// combining its texts into one (AB-G). Inert while no client is active:
    /// the declaration costs one `$ax` slot per frame, as any declared `AXNode`
    /// does (AB-U), and nothing else.
    public func accessibilityLabel(_ label: String) -> Self {
        handling { $0.axNode.label = label }
    }

    /// Replaces what an accessibility client reads as this element's value.
    ///
    /// On a `Text`, the text's own string becomes its label
    /// (`Text("vol").accessibilityValue("5")` reads `vol`, `5`: AB-F, arms R1,
    /// R12). Inside a button, a descendant carrying both a label and a value
    /// contributes that value to the button's (AB-G, arms C3, C6, C7).
    public func accessibilityValue(_ value: String) -> Self {
        handling { $0.axNode.value = value }
    }

    /// Makes this element adjustable by an accessibility client: an increment
    /// or decrement request runs `handler` with its direction (AB-I).
    ///
    /// **It is `onAction(AccessibilityAdjustment.self)`**, SwiftUI's modifier
    /// name over this framework's action dispatch, so it replaces an earlier
    /// `AccessibilityAdjustment` handler on the same element, registers no
    /// hitbox and does not make the element focusable. A client reaches only
    /// the element's **own** handler, never an ancestor's.
    ///
    /// **What `handler` captures outlives the frame that built it** — the
    /// retain-cycle hazard `onClick(_:)` states in full, through
    /// `Window.lastFocusRegistry`.
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> Self {
        onAction(AccessibilityAdjustment.self) { handler($0.direction) }
    }
}
