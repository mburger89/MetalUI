import MetalUICore
import MetalUILayout

/// A typed outer layout wrapper, analogous to SwiftUI's `ModifiedContent`.
///
/// It owns its content directly rather than erasing it or mutating the
/// content's style. Chained frames therefore remain a concrete structural tree:
/// each wrapper receives its own child identity through `ElementGroup` and
/// contributes its own layout node.
public struct FrameModifier<Content: ElementGroup>: Element, StyledElement {
    public var content: Content
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers

    public init(content: Content, width: Pixels? = nil, height: Pixels? = nil) {
        self.content = content
        var style = Style()
        style.alignItems = .center
        style.justifyContent = .center
        if let width { style.size.width = .length(.pixels(width)) }
        if let height { style.size.height = .length(.pixels(height)) }
        self.style = style
        self.decoration = Decoration()
        self.elementID = nil
        self.handlers = Handlers()
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
        (style, decoration) = animated(style, decoration, for: id, pass: &pass)
        let node = pass.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        pass.registerHandlers(handlers, at: bounds, id: id)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        if let color = animatedBackground(decoration, for: id, pass: &pass) {
            pass.fill(bounds, color: color, cornerRadii: Corners(all: decoration.cornerRadius))
        }
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
