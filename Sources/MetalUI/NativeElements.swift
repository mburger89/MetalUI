import MetalUICore
import MetalUILayout

/// A native proposal-layout horizontal stack.
///
/// Its content must resolve exclusively to native layout nodes such as
/// ``NativeRectangle`` and ``NativeSpacer``. The boundary is intentionally
/// structural: attempting to place a legacy element here traps when the layout
/// pass registers the stack, instead of silently handing a CSS child to the
/// native algorithm.
public struct NativeRow<Content: ElementGroup>: Element {
    public var content: Content
    public var spacing: Pixels
    public var alignment: NativeAlignment

    public init(spacing: Pixels = Pixels(0), alignment: NativeAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
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
        let node = pass.requestNativeLinearStack(children: children, axis: .horizontal,
                                                 spacing: Double(spacing.value),
                                                 alignment: alignment)
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

/// A native proposal-layout vertical stack.
public struct NativeColumn<Content: ElementGroup>: Element {
    public var content: Content
    public var spacing: Pixels
    public var alignment: NativeAlignment

    public init(spacing: Pixels = Pixels(0), alignment: NativeAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.spacing = spacing
        self.alignment = alignment
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
        let node = pass.requestNativeLinearStack(children: children, axis: .vertical,
                                                 spacing: Double(spacing.value),
                                                 alignment: alignment)
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

/// A native proposal-layout overlay, analogous to SwiftUI's `ZStack`.
public struct NativeOverlay<Content: ElementGroup>: Element {
    public var content: Content
    public var alignment: NativeAlignment

    public init(alignment: NativeAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.alignment = alignment
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
        let node = pass.requestNativeOverlay(children: children, alignment: alignment)
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

/// A native outer frame. Its content must contribute exactly one native node.
public struct NativeFrame<Content: ElementGroup>: Element {
    public var content: Content
    public var width: Pixels?
    public var height: Pixels?
    public var minWidth: Pixels?
    public var idealWidth: Pixels?
    public var maxWidth: Pixels?
    public var minHeight: Pixels?
    public var idealHeight: Pixels?
    public var maxHeight: Pixels?
    public var alignment: NativeAlignment

    public init(width: Pixels? = nil, height: Pixels? = nil,
                minWidth: Pixels? = nil, idealWidth: Pixels? = nil, maxWidth: Pixels? = nil,
                minHeight: Pixels? = nil, idealHeight: Pixels? = nil, maxHeight: Pixels? = nil,
                alignment: NativeAlignment = .center,
                @ElementBuilder content: () -> Content) {
        self.content = content()
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
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
        precondition(children.count == 1, "NativeFrame content must contribute one native node")
        let node = pass.requestNativeFrame(
            child: children[0], width: width.map { Double($0.value) },
            height: height.map { Double($0.value) }, minWidth: minWidth.map { Double($0.value) },
            idealWidth: idealWidth.map { Double($0.value) }, maxWidth: maxWidth.map { Double($0.value) },
            minHeight: minHeight.map { Double($0.value) }, idealHeight: idealHeight.map { Double($0.value) },
            maxHeight: maxHeight.map { Double($0.value) }, alignment: alignment
        )
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

/// Native outer padding around one native child.
public struct NativePadding<Content: ElementGroup>: Element {
    public var content: Content
    public var insets: Edges<Pixels>

    public init(_ insets: Edges<Pixels>, @ElementBuilder content: () -> Content) {
        self.content = content()
        self.insets = insets
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
        precondition(children.count == 1, "NativePadding content must contribute one native node")
        let insets = Edges<Double>(top: Double(insets.top.value), right: Double(insets.right.value),
                                   bottom: Double(insets.bottom.value), left: Double(insets.left.value))
        let node = pass.requestNativePadding(child: children[0], insets: insets)
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

/// A flexible native-layout spacer for use inside ``NativeRow``.
public struct NativeSpacer: Element {
    public var minLength: Pixels?

    public init(minLength: Pixels? = nil) {
        self.minLength = minLength
    }

    public struct Layout { var node: LayoutNodeID }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let node = pass.requestNativeSpacer(minLength: minLength.map { Double($0.value) })
        return (node, Layout(node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {}
}

/// A fixed-size painted leaf for the native-layout migration path.
///
/// It is deliberately small: fixed dimensions and a semantic fill are enough
/// to exercise native measurement, placement, and paint in a real frame while
/// Text and the existing styled-element surface migrate separately.
public struct NativeRectangle: Element {
    public var width: Pixels
    public var height: Pixels
    public var color: ColorToken

    public init(width: Pixels, height: Pixels, color: ColorToken = .surface) {
        self.width = width
        self.height = height
        self.color = color
    }

    public struct Layout { var node: LayoutNodeID }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let size = SizeD(width: Double(width.value), height: Double(height.value))
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }
        return (node, Layout(node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.theme[color], cornerRadii: Corners(all: Pixels(0)))
    }
}

/// A semantic colour field that accepts every concrete proposal it receives.
///
/// This is the native equivalent of a SwiftUI `Color` used as a background:
/// an overlay can offer it the window's current size and it responds with that
/// size, rather than retaining an initial fixed canvas. Unspecified axes stay
/// zero so the fill does not manufacture intrinsic size in a stack.
public struct NativeColorFill: Element {
    public var color: ColorToken

    public init(_ color: ColorToken) {
        self.color = color
    }

    public struct Layout { var node: LayoutNodeID }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let node = pass.requestNativeLeaf { Self.measurement(for: $0) }
        return (node, Layout(node: node))
    }

    nonisolated static func measurement(for proposal: ProposedSize) -> LayoutMeasurement {
        LayoutMeasurement(size: proposal.replacingUnspecifiedDimensions(by: .zero))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.theme[color], cornerRadii: Corners(all: Pixels(0)))
    }
}
