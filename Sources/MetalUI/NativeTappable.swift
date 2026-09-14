import MetalUICore
import MetalUILayout

/// A proposal-layout wrapper that makes its resolved bounds tappable.
///
/// It contributes no layout node: hit testing is registered in prepaint after
/// native layout has resolved, matching the framework's three-phase contract.
public struct OnTapModifier<Content: ProposalElementGroup>: Element {
    public var content: Content
    public var action: @MainActor () -> Void
    public var hoverColor: ColorToken?

    public init(content: Content, hoverColor: ColorToken? = nil,
                action: @escaping @MainActor () -> Void) {
        self.content = content
        self.action = action
        self.hoverColor = hoverColor
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
        if let hoverColor, pass.isHovered(id) {
            pass.opacity(0.22) {
                pass.fill(bounds, color: pass.theme[hoverColor])
            }
        }
    }
}

extension ProposalElementGroup {
    /// Registers `action` when this proposal-layout subtree is clicked.
    ///
    /// This is the canonical public spelling for the replacement layout path.
    /// The proposal-only receiver keeps CSS-layout elements from entering a
    /// mixed tree that would otherwise trap during layout registration.
    public func onTap(hoverColor: ColorToken? = nil,
                      _ action: @escaping @MainActor () -> Void) -> OnTapModifier<Self> {
        OnTapModifier(content: self, hoverColor: hoverColor, action: action)
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "onTap")
    public func nativeOnTap(hoverColor: ColorToken? = nil,
                            _ action: @escaping @MainActor () -> Void) -> OnTapModifier<Self> {
        onTap(hoverColor: hoverColor, action)
    }
}

/// Temporary source-compatible name for ``OnTapModifier``.
@available(*, deprecated, renamed: "OnTapModifier")
public typealias NativeTappable<Content: ProposalElementGroup> = OnTapModifier<Content>
