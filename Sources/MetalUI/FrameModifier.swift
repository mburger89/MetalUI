import MetalUICore
import MetalUILayout

/// A typed outer layout wrapper, analogous to SwiftUI's `ModifiedContent`.
///
/// It owns its content directly rather than erasing it or mutating the
/// content's style. Chained frames therefore remain a concrete structural tree:
/// each wrapper receives its own child identity through `ElementGroup` and
/// contributes its own layout node.
public struct FrameModifier<Content: ElementGroup>: Element {
    public var content: Content
    public var width: Pixels?
    public var height: Pixels?

    public init(content: Content, width: Pixels? = nil, height: Pixels? = nil) {
        self.content = content
        self.width = width
        self.height = height
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
        var style = Style()
        style.alignItems = .center
        style.justifyContent = .center
        if let width { style.size.width = .length(.pixels(width)) }
        if let height { style.size.height = .length(.pixels(height)) }
        let node = pass.requestNode(style: style, children: children)
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

extension ElementGroup {
    /// Applies a SwiftUI-style outer frame without overwriting the content's
    /// own declared size. Passing `nil` leaves that axis unconstrained.
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> FrameModifier<Self> {
        FrameModifier(content: self, width: width, height: height)
    }
}
