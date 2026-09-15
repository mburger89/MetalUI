import MetalUICore
import MetalUILayout

// SKELETON (lane 2 of docs/superpowers/specs/2026-09-15-modifier-composition-design.md):
// storage, accessors, `_wrap` and the return types only. Its phases register
// ONLY the outermost layer, around the content, under the outermost id — the
// shape the lane's red runs are taken on. Replaced by the real phases in the
// implementation commit.

/// One legacy wrapper modifier's worth of state: exactly what one `Box` around
/// one child carries (ruling MC-A).
///
/// A public type so `ElementGroup._wrap(_:)` can name it; its members and its
/// initializer are internal, so tasks 4 and 5 can add layer kinds without a
/// public break, and no module outside `MetalUI` can build one.
public struct ModifierLayer {
    var style: Style
    var decoration: Decoration
    var handlers: Handlers
    var elementID: ElementID?

    init(style: Style) {
        self.style = style
        self.decoration = Decoration()
        self.handlers = Handlers()
        self.elementID = nil
    }
}

/// One flat wrapper for the legacy path's outer modifiers, `.padding` and
/// `.frame` (ruling MC-A).
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public typealias LayerBase = Content

    public var content: Content
    /// The layer the element's `StyledElement` accessors read and write.
    var outermost: ModifierLayer
    /// Every other layer, innermost first. Empty for a one-layer chain, and an
    /// empty array owns no buffer (ruling MC-K).
    var inner: [ModifierLayer]

    init(content: Content, layer: ModifierLayer) {
        self.content = content
        self.outermost = layer
        self.inner = []
    }

    /// How many layers the chain holds.
    var layerCount: Int { inner.count + 1 }

    public var style: Style {
        get { outermost.style }
        set { outermost.style = newValue }
    }

    public var decoration: Decoration {
        get { outermost.decoration }
        set { outermost.decoration = newValue }
    }

    public var handlers: Handlers {
        get { outermost.handlers }
        set { outermost.handlers = newValue }
    }

    public var elementID: ElementID? {
        get { outermost.elementID }
        set { outermost.elementID = newValue }
    }

    /// Adds `layer` outside every existing one; the old outermost layer moves
    /// in, keeping its values and its name.
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Content> {
        var copy = self
        copy.inner.append(copy.outermost)
        copy.outermost = layer
        return copy
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
        (outermost.style, outermost.decoration) = animated(outermost.style, outermost.decoration,
                                                           for: id, pass: &pass)
        let node = pass.requestNode(style: outermost.style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        pass.registerHandlers(outermost.handlers, at: bounds, id: id)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        if let color = animatedBackground(outermost.decoration, for: id, pass: &pass) {
            pass.fill(bounds, color: color,
                      cornerRadii: Corners(all: outermost.decoration.cornerRadius))
        }
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ElementGroup where LayerBase == Self {
    /// Every conformer but `ModifiedElement`: the first wrapper modifier wraps.
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Self> {
        ModifiedElement(content: self, layer: layer)
    }
}

extension ElementGroup {
    /// Applies a SwiftUI-style outer frame without overwriting the content's
    /// own declared size. Passing `nil` leaves that axis unconstrained.
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<LayerBase> {
        var style = Style()
        style.alignItems = .center
        style.justifyContent = .center
        if let width { style.size.width = .length(.pixels(width)) }
        if let height { style.size.height = .length(.pixels(height)) }
        return _wrap(ModifierLayer(style: style))
    }
}
