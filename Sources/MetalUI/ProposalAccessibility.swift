import MetalUICore
import MetalUILayout

// Plan task 12, part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §4,
// §5; ruling `IX-AB` item 2): the accessibility modifiers on the proposal path.

/// A proposal-layout wrapper carrying accessibility declarations over its one
/// child — `GestureModifier`'s shape (`IX-AB` item 2). It contributes no layout
/// node; its one child numbers from 0 under its id, so the wrapper is **one
/// identity level**, gained only by a caller who writes it. A chain of these
/// modifiers merges into one wrapper (the overloads below return `Self`), so
/// `.accessibilityLabel("L").accessibilityHint("H")` is one level, and on one
/// wrapper the later-written declaration wins, as on a `StyledElement`.
///
/// **Requires exactly one child node** (`SA-G`, as every single-child proposal
/// wrapper does): over zero or several it traps naming the count.
public struct AccessibilityModifier<Content: ProposalElementGroup>: Element {
    public var content: Content
    /// The declarations, as a `StyledElement` carries them in `Handlers`.
    var handlers = Handlers()

    init(content: Content) {
        self.content = content
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1,
                     "an accessibility modifier requires exactly one native child, got \(children.count) (SA-G)")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // RED STUB: records nothing.
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }

    func declaring(_ change: (inout Handlers) -> Void) -> Self {
        var copy = self
        change(&copy.handlers)
        return copy
    }
}

extension AccessibilityModifier: ProposalElement {}

extension ProposalElementGroup {
    func accessibilityWrapper(_ change: (inout Handlers) -> Void) -> AccessibilityModifier<Self> {
        AccessibilityModifier(content: self).declaring(change)
    }

    public func accessibilityLabel(_ label: String) -> AccessibilityModifier<Self> { accessibilityWrapper { _ in } }
    public func accessibilityValue(_ value: String) -> AccessibilityModifier<Self> { accessibilityWrapper { _ in } }
    public func accessibilityAdjustableAction(
        _ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityHidden(_ hidden: Bool) -> AccessibilityModifier<Self> { accessibilityWrapper { _ in } }
    public func accessibilityHint(_ hint: String) -> AccessibilityModifier<Self> { accessibilityWrapper { _ in } }
    public func accessibilityIdentifier(_ identifier: String) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityAction(_ handler: @escaping @MainActor () -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
    public func accessibilityAction(named name: String,
                                    _ handler: @escaping @MainActor () -> Void) -> AccessibilityModifier<Self> {
        accessibilityWrapper { _ in }
    }
}
