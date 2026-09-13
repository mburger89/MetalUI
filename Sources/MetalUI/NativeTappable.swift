import MetalUICore
import MetalUILayout

/// A native-layout wrapper that makes its resolved bounds tappable.
///
/// It contributes no layout node: hit testing is registered in prepaint after
/// native layout has resolved, matching the framework's three-phase contract.
public struct NativeTappable<Content: ElementGroup>: Element {
    public var content: Content
    public var action: @MainActor () -> Void

    public init(content: Content, action: @escaping @MainActor () -> Void) {
        self.content = content
        self.action = action
    }

    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                   pass: &pass)
        precondition(children.count == 1, "a native tappable wrapper requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.onClick = action
        pass.registerHandlers(handlers, at: bounds, id: id)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ElementGroup {
    /// Registers `action` when this native subtree is clicked.
    public func nativeOnTap(_ action: @escaping @MainActor () -> Void) -> NativeTappable<Self> {
        NativeTappable(content: self, action: action)
    }
}
