import MetalUICore
import MetalUILayout

/// An element that lays its proposal content out with a custom `ProposalLayout`.
///
/// The ready-made carrier for a layout value, so a `ProposalLayout` author does
/// not also have to write an `Element` (ruling SA-F). Usually spelled through
/// `callAsFunction`: `MyLayout() { A(); B() }` or `MyLayout { A(); B() }`.
///
/// Content must be a `ProposalElementGroup`, so a legacy subtree is rejected
/// at compile time, as it is for `HStack`. The container contributes one
/// native node and paints nothing of its own.
public struct ProposalLayoutContainer<L: ProposalLayout, Content: ProposalElementGroup>: Element {
    public var layout: L
    public var content: Content

    public init(_ layout: L, @ElementBuilder content: () -> Content) {
        self.layout = layout
        self.content = content()
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                   pass: &pass)
        let node = pass.requestNativeLayout(layout, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ProposalLayoutContainer: ProposalElementGroup {}

extension ProposalLayout {
    /// `MyLayout() { A(); B() }`, as SwiftUI's `Layout.callAsFunction`.
    ///
    /// The explicit `Content: ProposalElementGroup` constraint is redundant with
    /// the return type's, and dropping it alone changes nothing (measured on
    /// the design skeleton, ruling SA-F); relaxing both is what admits legacy
    /// content.
    @MainActor
    public func callAsFunction<Content: ProposalElementGroup>(
        @ElementBuilder _ content: () -> Content) -> ProposalLayoutContainer<Self, Content> {
        ProposalLayoutContainer(self, content: content)
    }
}
