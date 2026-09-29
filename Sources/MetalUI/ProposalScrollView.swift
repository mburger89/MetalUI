import MetalUICore
import MetalUILayout

/// A SwiftUI-style scrolling viewport for proposal-layout content.
///
/// `ProposalScrollView` keeps the existing ``ScrollView`` source-compatible
/// while providing a fully native migration path: its content must be a
/// ``ProposalElementGroup``, and its viewport/content relationship is solved
/// by `LayoutTree`'s proposal engine rather than the CSS flex engine.
public struct ProposalScrollView<Content: ProposalElementGroup>: Element {
    public var axis: ScrollAxis
    public var elementID: ElementID?
    public var content: Content
    public var cornerRadius: Pixels = Pixels(0)
    public var indicatorVisibility: ScrollIndicatorVisibility = .automatic

    public init(_ axis: ScrollAxis = .vertical, elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        self.axis = axis
        self.elementID = elementID
        self.content = content()
    }

    /// Rounds the clips applied to both scrolling content and its indicator.
    public func cornerRadius(_ points: Pixels) -> Self {
        var copy = self
        copy.cornerRadius = points
        return copy
    }

    /// Sets whether the fading overlay scroll indicator is painted.
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> Self {
        var copy = self
        copy.indicatorVisibility = visibility
        return copy
    }

    public struct Layout {
        var node: LayoutNodeID
        var contentNode: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        // SwiftUI's `ScrollView` lays several direct children out as a
        // centred, default-spacing `VStack` whatever its scrolling axis (probe
        // SC3: b at (10, 38) under a 50×30 a on `.vertical`, `.horizontal` and
        // both). Horizontal content is an explicit `HStack`, which remains a
        // single transparent child here. Default spacing is the platform
        // default per pair — 8 between views, none at a spacer's edge (ruling
        // CN-H, SC5) — rather than an explicit 8. The viewport answers this
        // content's size on its non-scrolling axis (ruling CN-M).
        let contentAxis: ProposalStackAxis = axis == .vertical ? .vertical : .horizontal
        let contentNode: ProposalNodeID
        if children.count == 1 {
            contentNode = children[0]
        } else {
            contentNode = pass.requestNativeLinearStack(children: children, axis: .vertical,
                                                         spacing: nil)
        }
        let node = pass.requestNativeScrollViewport(
            child: contentNode,
            axis: contentAxis
        )
        return (node, Layout(node: node.layoutNodeID, contentNode: contentNode.layoutNodeID,
                            content: contentLayout))
    }

    /// The clamp, the offset resolution and the fading overlay indicator, all
    /// of which this element shares with ``ScrollView`` (ruling `LR-BD`).
    /// **Computed, not stored** — see `ScrollChrome`'s own doc for why, and for
    /// what the fold deliberately left alone. Until stage 3 these seven members
    /// lived here as private copies, untested and already drifting.
    var chrome: ScrollChrome {
        ScrollChrome(axis: axis, cornerRadius: cornerRadius,
                     indicatorVisibility: indicatorVisibility)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let chrome = self.chrome
        let offset = chrome.resolvedOffset(id, bounds: bounds, contentNode: layout.contentNode,
                                           pass: pass)
        pass.registerScrollRegion(bounds, id: id, axis: axis)
        // `DD-F` item 2: the content prepaints inside this scroller's frame.
        let scroller = ScrollerFrame(scrollerID: id, axis: axis,
                                     contentOrigin: pass.bounds(of: layout.contentNode).origin,
                                     viewport: bounds, offset: offset,
                                     contentExtent: chrome.extent(pass.bounds(of: layout.contentNode).size))
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: chrome.delta(-offset),
                     cornerRadii: Corners(all: cornerRadius)) {
            pass.inScroller(scroller) {
                result = content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let chrome = self.chrome
        let offset = chrome.resolvedOffset(id, bounds: bounds, contentNode: layout.contentNode,
                                           pass: pass)
        pass.clipped(to: bounds, offsetBy: chrome.delta(-offset),
                     cornerRadii: Corners(all: cornerRadius)) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
        // Outside the block above and emitted after it, for the reason
        // `ScrollView.paint` spells out: inside it the thumb would inherit the
        // `-offset` translation and scroll away with the content.
        // `ScrollChrome.paintIndicator` pushes its own clip at the same bounds
        // and radii with a ZERO offset.
        chrome.paintIndicator(id, bounds: bounds, offset: offset,
                              contentNode: layout.contentNode, pass: &pass)
    }
}

extension ProposalScrollView: ProposalElement {}
