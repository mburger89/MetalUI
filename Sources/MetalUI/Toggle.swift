import MetalUICore
import MetalUILayout

/// SKELETON (lane 1 red-first).
public struct Toggle<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var isOn: Binding<Bool>
    private var box: Box<Pair<Box<EmptyGroup>, Label>>

    public init(isOn: Binding<Bool>, @ElementBuilder label: () -> Label) {
        self.style = Style()
        self.decoration = Decoration()
        self.isOn = isOn
        self.box = Box(content: Pair(Box(), label()))
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Box<EmptyGroup>, Label>>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Box<EmptyGroup>, Label>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Box<EmptyGroup>, Label>.Prepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Box<EmptyGroup>, Label>>.Layout,
                               prepaint: inout Pair<Box<EmptyGroup>, Label>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}
