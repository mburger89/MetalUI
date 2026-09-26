import MetalUICore
import MetalUILayout

// SKELETON (lane 2 red-first): the public spelling over a 0×0 leaf.
struct ValueTrackTarget {}

public struct Slider: Element, StyledElement {
    public var style: Style = Style()
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()

    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1)
        where V.Stride: BinaryFloatingPoint {}

    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride)
        where V.Stride: BinaryFloatingPoint {}

    static func size(proposedWidth: Double?) -> SizeD { .zero }

    public struct Layout { public var node: LayoutNodeID }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .box) {
            pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: .zero) }
        }
        return (node, Layout(node: node))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) {
        pass.registerAndScope(handlers, decoration, at: bounds, for: id) { }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Void, pass: inout PaintPass) {
        pass.paintDecoration(decoration, in: bounds, for: id) { }
    }
}
