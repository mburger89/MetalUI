import MetalUICore
import MetalUILayout

// SKELETON (lane 2 red-first): the public spelling over a bare row.
public struct Stepper: Element, StyledElement {
    public var style: Style = Style()
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var box: Box<Pair<Text, Box<EmptyGroup>>>

    public init<V: Strideable>(_ title: String, value: Binding<V>, in bounds: ClosedRange<V>,
                               step: V.Stride = 1) {
        box = Box(content: Pair(Text(title), Box()))
    }

    public init<V: Strideable>(_ title: String, value: Binding<V>, step: V.Stride = 1) {
        box = Box(content: Pair(Text(title), Box()))
    }

    public init(_ title: String, onIncrement: (@MainActor () -> Void)?,
                onDecrement: (@MainActor () -> Void)?) {
        box = Box(content: Pair(Text(title), Box()))
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Text, Box<EmptyGroup>>>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Text, Box<EmptyGroup>>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Text, Box<EmptyGroup>>.Prepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Text, Box<EmptyGroup>>>.Layout,
                               prepaint: inout Pair<Text, Box<EmptyGroup>>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
