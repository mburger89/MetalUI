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

// Plan task 12 part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §4;
// rulings `IX-V`…`IX-Y`): SwiftUI's remaining accessibility modifiers. Each
// writes `Handlers.axNode`'s declaration box or `Handlers.actions` through
// `handling`, so a `StyledElement` gains **no layer and no identity level** and
// `Handlers` no member; on one element the later-written declaration wins (H4).
// The same eleven exist on `ProposalElementGroup`, through
// `AccessibilityModifier` (`ProposalAccessibility.swift`).
extension StyledElement {
    /// How a client sees this element's accessibility content — SwiftUI's
    /// `accessibilityElement(children:)`, `.ignore` by default (`IX-V`):
    /// `.ignore` one node with no children, `.combine` one node reading its
    /// children's text, `.contain` a group keeping them.
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> Self {
        handling { $0.axNode.declarations.childBehavior = children }
    }

    /// Removes this element and everything inside it from what a client reads
    /// (`IX-W` item 1; SwiftUI H1–H5). An inner `(false)` cannot un-hide an
    /// outer `(true)`. **Accessibility only**: a hidden button is still
    /// clickable and focusable, as SwiftUI's is.
    public func accessibilityHidden(_ hidden: Bool) -> Self {
        handling { $0.axNode.declarations.isHidden = hidden }
    }

    /// What a client reads as this element's hint (AppKit `AXHelp`, AccessKit
    /// `description`), distributed from a plain container as a label is (`IX-W`
    /// item 2; N1–N5).
    public func accessibilityHint(_ hint: String) -> Self {
        handling { $0.axNode.declarations.hint = hint }
    }

    /// This element's accessibility identifier (AppKit `AXIdentifier`, AccessKit
    /// `author_id`), distributed as a label is (`IX-W` item 2; N2, N5).
    public func accessibilityIdentifier(_ identifier: String) -> Self {
        handling { $0.axNode.declarations.identifier = identifier }
    }

    /// Adds descriptive traits; each sets the role only (`IX-X`; T1–T11).
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self {
        handling { $0.addAccessibilityTraits(traits) }
    }

    /// Removes descriptive traits: `.isButton` off a clickable element makes it
    /// a group that keeps its folded label and its press (`IX-X` item 2; T3p).
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> Self {
        handling { $0.removeAccessibilityTraits(traits) }
    }

    /// Makes an accessibility press run `handler` (`IX-Y` item 1; SwiftUI A1,
    /// A4, A5). **On an element with its own click, a press runs this instead**
    /// (A4); a mouse click still runs the click. Registers no hitbox and does
    /// not make the element focusable; disabled, it is refused (A7).
    ///
    /// **What `handler` captures outlives the frame that built it**, as
    /// `onClick(_:)`'s does.
    public func accessibilityAction(_ handler: @escaping @MainActor () -> Void) -> Self {
        handling { $0.declareDefaultAction(handler) }
    }

    /// Publishes a custom action named `name` that runs `handler` (`IX-Y` item
    /// 2; SwiftUI A2, A3, A6). Named actions chain: the later-written one is
    /// listed first, and a button's own press is untouched.
    public func accessibilityAction(named name: String, _ handler: @escaping @MainActor () -> Void) -> Self {
        handling { $0.declareNamedAccessibilityAction(name, handler) }
    }
}

extension Handlers {
    /// `accessibilityAction(named:_:)`'s one write, shared by both
    /// vocabularies: prepend the name, and chain the handler in front of any
    /// earlier one, dispatching by name (`IX-Y` item 2).
    mutating func declareNamedAccessibilityAction(_ name: String, _ handler: @escaping @MainActor () -> Void) {
        axNode.declarations.actionNames.insert(name, at: 0)
        let key = ObjectIdentifier(AccessibilityNamedAction.self)
        let earlier = actions[key]
        actions[key] = { action in
            if let named = action as? AccessibilityNamedAction, named.name == name {
                handler()
            } else {
                earlier?(action)
            }
        }
    }
}
