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
