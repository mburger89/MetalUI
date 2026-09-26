import MetalUICore
import MetalUILayout

/// SKELETON (lane 1 red-first): the public spelling over a bare `Box`; no chrome,
/// no handlers.
public struct Button<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var action: @MainActor () -> Void
    private var box: Box<Pair<Label, Box<EmptyGroup>>>

    public init(action: @escaping @MainActor () -> Void, @ElementBuilder label: () -> Label) {
        self.style = Style()
        self.decoration = Decoration()
        self.action = action
        self.box = Box(content: Pair(label(), Box()))
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Label, Box<EmptyGroup>>>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Label, Box<EmptyGroup>>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Label, Box<EmptyGroup>>.Prepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Label, Box<EmptyGroup>>>.Layout,
                               prepaint: inout Pair<Label, Box<EmptyGroup>>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }
}
