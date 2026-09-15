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
        // SwiftUI's `ScrollView` content builder presents direct children in a
        // vertical variadic layout regardless of its scrolling axis. macOS
        // pixel probes with 20pt red and 30pt blue children observed an 8pt
        // gap (red, background, blue) for both axes. Horizontal content is an
        // explicit `HStack`, which remains a single transparent child here.
        let contentAxis: ProposalStackAxis = axis == .vertical ? .vertical : .horizontal
        let contentNode: ProposalNodeID
        if children.count == 1 {
            contentNode = children[0]
        } else {
            contentNode = pass.requestNativeLinearStack(children: children, axis: .vertical,
                                                         spacing: 8)
        }
        let node = pass.requestNativeScrollViewport(
            child: contentNode,
            axis: contentAxis
        )
        return (node, Layout(node: node.layoutNodeID, contentNode: contentNode.layoutNodeID,
                            content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        pass.registerScrollRegion(bounds, id: id, axis: axis)
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: delta(-offset),
                     cornerRadii: Corners(all: cornerRadius)) {
            result = content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        pass.clipped(to: bounds, offsetBy: delta(-offset),
                     cornerRadii: Corners(all: cornerRadius)) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
        paintIndicator(id, bounds: bounds, offset: offset, layout: layout, pass: &pass)
    }

    private func paintIndicator(_ id: GlobalElementID, bounds: Bounds<Pixels>, offset: Double,
                                layout: Layout, pass: inout PaintPass) {
        guard indicatorVisibility != .hidden else { return }
        let content = extent(pass.bounds(of: layout.contentNode).size)
        let viewport = extent(bounds.size)
        let scrollable = max(0, content - viewport)
        guard scrollable > 0 else { return }

        var lastScroll = -Double.infinity
        pass.withState(id, initial: ScrollState()) { lastScroll = $0.lastScrollTime }
        let age = pass.timestamp - lastScroll
        let alpha = age < 0.6 ? 1.0 : max(0, 1.0 - (age - 0.6) / 0.4)
        guard alpha > 0 else { return }
        pass.requestAnotherFrame()

        let thumb = max(20, viewport * (viewport / content))
        let travel = (offset / scrollable) * (viewport - thumb)
        var color = pass.theme[.scrollIndicator]
        color.a *= Float(alpha)
        pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                     cornerRadii: Corners(all: cornerRadius)) {
            pass.fill(indicatorBounds(bounds: bounds, thumb: thumb, travel: travel), color: color,
                      cornerRadii: Corners(all: Pixels(3)))
        }
    }

    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: Layout,
                                pass: PrepaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var resolved = 0.0
        pass.withState(id, initial: ScrollState()) {
            $0.offset = clamp($0.offset, content: content, viewport: viewport)
            $0.viewportExtent = viewport
            resolved = $0.offset
        }
        return resolved
    }

    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: Layout,
                                pass: PaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var stored = 0.0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return clamp(stored, content: content, viewport: viewport)
    }

    private func clamp(_ offset: Double, content: Double, viewport: Double) -> Double {
        min(max(0, offset), max(0, content - viewport))
    }

    private func indicatorBounds(bounds: Bounds<Pixels>, thumb: Double,
                                 travel: Double) -> Bounds<Pixels> {
        switch axis {
        case .vertical:
            Bounds(origin: Point(x: Pixels(bounds.origin.x.value + bounds.size.width.value - 5),
                                 y: Pixels(bounds.origin.y.value + Float(travel))),
                   size: Size(width: Pixels(3), height: Pixels(Float(thumb))))
        case .horizontal:
            Bounds(origin: Point(x: Pixels(bounds.origin.x.value + Float(travel)),
                                 y: Pixels(bounds.origin.y.value + bounds.size.height.value - 5)),
                   size: Size(width: Pixels(Float(thumb)), height: Pixels(3)))
        }
    }

    private func delta(_ value: Double) -> Point<Pixels> {
        axis == .vertical ? Point(x: Pixels(0), y: Pixels(Float(value)))
                          : Point(x: Pixels(Float(value)), y: Pixels(0))
    }

    private func extent(_ size: Size<Pixels>) -> Double {
        Double(axis == .vertical ? size.height.value : size.width.value)
    }
}

extension ProposalScrollView: ProposalElement {}
