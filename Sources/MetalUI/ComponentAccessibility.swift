import MetalUICore

// `accessibilityLabel(_:)` and `accessibilityValue(_:)` on a `Component` (ruling
// `AB-AH`, Sift gap G18). A component is no `StyledElement`, so neither modifier
// compiled on one and an author set it on each `Text` branch of the body. SwiftUI
// has it on every view: the declaration goes to the accessibility element(s) the
// view produces, and no frame moves.
//
// **Mechanism.** `AccessibilityGroup` is `IdentifiedGroup`'s shape: a layout-transparent
// group (no node of its own, one identity level, its content numbered under it) that,
// in prepaint, registers the declaration at the union of the rects its content handed
// its parent, then prepaints the content inside it. The tree builder distributes a
// declaration on a plain container to its texts (AB-T, SwiftUI probe P3), so an
// `if`/`else` body labels whichever `Text` it drew and a two-text body labels both.

/// A component (or any group) with accessibility declarations, layout-transparent
/// (`AB-AH`): it adds no layout node, so a modified component's members sit where they
/// sat. One identity level, gained only by a caller who writes it; a chain of these
/// modifiers merges into one group, the later-written declaration winning.
public struct AccessibilityGroup<Content: ElementGroup>: ElementGroup {
    /// The group the declarations apply to.
    public var content: Content
    var handlers = Handlers()

    init(content: Content) { self.content = content }

    /// What the group hands the later phases.
    public struct Layout {
        var content: Content.GroupLayout
        var id: GlobalElementID
        var nodes: [LayoutNodeID]
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let id = GlobalElementID.child(of: parent, at: cursor, name: nil)
        cursor += 1
        var inner = 0
        let (nodes, layout) = content.requestGroupLayout(under: id, at: &inner, pass: &pass)
        return (nodes, Layout(content: layout, id: id, nodes: pass.frame.collectsAccessibility ? nodes : []))
    }

    public mutating func prepaintGroup(layout: inout Layout, pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let frame = pass.frame
        guard !layout.nodes.isEmpty, !frame.allElided(layout.nodes) else {
            return content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        let bounds = frame.union(of: layout.nodes)
        let id = layout.id
        let handlers = handlers
        return frame.sharingRegistrationsWithEffects(at: bounds, register: {
            pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil, synthesizesAccessibility: true)
        }, content: { content.prepaintGroup(layout: &layout.content, pass: &pass) })
    }

    public mutating func paintGroup(layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }

    func declaring(_ change: (inout Handlers) -> Void) -> Self {
        var copy = self
        change(&copy.handlers)
        return copy
    }

    /// Sets the accessible name; the later-written declaration wins.
    public func accessibilityLabel(_ label: String) -> Self { declaring { $0.declareAccessibilityLabel(label) } }
    /// Sets the accessible value; the later-written declaration wins.
    public func accessibilityValue(_ value: String) -> Self { declaring { $0.declareAccessibilityValue(value) } }
}

/// Proposal content stays proposal content, so an `HStack` or `Grid` parent takes the group.
extension AccessibilityGroup: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let id = GlobalElementID.child(of: parent, at: cursor, name: nil)
        cursor += 1
        var inner = 0
        let (nodes, layout) = content.requestProposalGroupLayout(under: id, at: &inner, pass: &pass)
        return (nodes, Layout(content: layout, id: id,
                              nodes: pass.frame.collectsAccessibility ? nodes.map(\.layoutNodeID) : []))
    }
}

extension Component {
    /// Replaces what an accessibility client reads as the label of the
    /// accessibility element(s) this component produces: SwiftUI's
    /// `accessibilityLabel(_:)`, distributed to the component's texts as on a
    /// stack (AB-T). Like `StyledElement.accessibilityLabel(_:)`, a `Text` with
    /// no declared value publishes the label as its value.
    ///
    /// Layout-transparent: no frame moves (`AB-AH`).
    public func accessibilityLabel(_ label: String) -> AccessibilityGroup<Self> {
        AccessibilityGroup(content: self).accessibilityLabel(label)
    }

    /// Replaces what an accessibility client reads as the value of the
    /// accessibility element(s) this component produces: SwiftUI's
    /// `accessibilityValue(_:)`, distributed to the component's texts as on a
    /// stack (AB-T). On a `Text`, the text's own string becomes its label.
    ///
    /// Layout-transparent: no frame moves (`AB-AH`).
    public func accessibilityValue(_ value: String) -> AccessibilityGroup<Self> {
        AccessibilityGroup(content: self).accessibilityValue(value)
    }
}

extension Component where Self: ProposalElementGroup {
    /// A `Component` over proposal content keeps `Component.accessibilityLabel(_:)`'s meaning, not
    /// `ProposalElementGroup`'s one-child wrapper: this overload settles the choice the compiler
    /// would otherwise call ambiguous, as `padding(_:)` does (`DX-B`).
    public func accessibilityLabel(_ label: String) -> AccessibilityGroup<Self> {
        AccessibilityGroup(content: self).accessibilityLabel(label)
    }

    /// The `accessibilityValue(_:)` twin of ``accessibilityLabel(_:)``.
    public func accessibilityValue(_ value: String) -> AccessibilityGroup<Self> {
        AccessibilityGroup(content: self).accessibilityValue(value)
    }
}
