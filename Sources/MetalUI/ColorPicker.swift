import MetalUICore
import MetalUILayout

// RED STUB (C10 lane 1): the public surface only — a row holding the label,
// no well, no panel.
public struct ColorPicker<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    var box: Box<Label>

    public init(selection: Binding<Color>, supportsOpacity: Bool = true, @ElementBuilder label: () -> Label) {
        var style = Style()
        style.flexDirection = .row
        self.style = style
        self.box = Box(style: style, content: label())
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Box<Label>.Layout) {
        box.style = style
        box.decoration = decoration
        return box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<Label>.Layout,
                                  pass: inout PrepaintPass) -> Label.GroupPrepaint {
        box.handlers = handlers
        return box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Box<Label>.Layout,
                               prepaint: inout Label.GroupPrepaint, pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension ColorPicker where Label == Text {
    public init(_ titleKey: String, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(titleKey) }
    }
}
