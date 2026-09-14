import MetalUICore
import MetalUILayout

/// A native SwiftUI-style overlay attachment.
///
/// Its overlay is measured against the primary content's resolved size and
/// does not change the primary content's reported size.
public struct NativeOverlayModifier<Content: ElementGroup, Overlay: ElementGroup>: Element {
    public var content: Content
    public var overlay: Overlay
    public var alignment: NativeAlignment

    public init(content: Content, alignment: NativeAlignment = .center,
                @ElementBuilder overlay: () -> Overlay) {
        self.content = content
        self.overlay = overlay()
        self.alignment = alignment
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
        var overlay: Overlay.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var contentCursor = 0
        let (contentNodes, contentLayout) = content.requestGroupLayout(under: id, at: &contentCursor,
                                                                        pass: &pass)
        var overlayCursor = 0
        let (overlayNodes, overlayLayout) = overlay.requestGroupLayout(under: id, at: &overlayCursor,
                                                                        pass: &pass)
        precondition(contentNodes.count == 1 && overlayNodes.count == 1,
                     "a native overlay modifier requires one primary and one overlay node")
        let node = pass.requestNativeOverlayAttachment(child: contentNodes[0], overlay: overlayNodes[0],
                                                       alignment: alignment)
        return (node, Layout(node: node, content: contentLayout, overlay: overlayLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> (Content.GroupPrepaint, Overlay.GroupPrepaint) {
        (content.prepaintGroup(layout: &layout.content, pass: &pass),
         overlay.prepaintGroup(layout: &layout.overlay, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout (Content.GroupPrepaint, Overlay.GroupPrepaint),
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint.0, pass: &pass)
        overlay.paintGroup(layout: &layout.overlay, prepaint: &prepaint.1, pass: &pass)
    }
}

extension ElementGroup {
    public func overlay<Overlay: ElementGroup>(alignment: NativeAlignment = .center,
                                               @ElementBuilder content: () -> Overlay)
        -> NativeOverlayModifier<Self, Overlay> {
        NativeOverlayModifier(content: self, alignment: alignment, overlay: content)
    }

    /// Temporary source-compatible spelling for the native migration surface.
    @available(*, deprecated, renamed: "overlay")
    public func nativeOverlay<Overlay: ElementGroup>(alignment: NativeAlignment = .center,
                                                      @ElementBuilder content: () -> Overlay)
        -> NativeOverlayModifier<Self, Overlay> {
        overlay(alignment: alignment, content: content)
    }
}
