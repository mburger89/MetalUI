import MetalUICore
import MetalUILayout

/// SKELETON (lane 1 red-first).
public struct PickerStyle: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case segmented, radioGroup }
    let kind: Kind
    public static let automatic = PickerStyle(kind: .segmented)
    public static let segmented = PickerStyle(kind: .segmented)
    public static let radioGroup = PickerStyle(kind: .radioGroup)
}

/// SKELETON (lane 1 red-first).
public struct Picker<SelectionValue: Hashable, Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var selection: Binding<SelectionValue>
    private var pickerStyle: PickerStyle = .automatic
    private var box: Box<Pair<Text, Box<Content>>>

    public init(_ title: String, selection: Binding<SelectionValue>,
                @ElementBuilder content: () -> Content) {
        self.style = Style()
        self.decoration = Decoration()
        self.selection = selection
        self.box = Box(content: Pair(Text(title), Box(content: content())))
    }

    public func pickerStyle(_ style: PickerStyle) -> Picker {
        var copy = self
        copy.pickerStyle = style
        return copy
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Text, Box<Content>>>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Text, Box<Content>>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Text, Box<Content>>.Prepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Text, Box<Content>>>.Layout,
                               prepaint: inout Pair<Text, Box<Content>>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// SKELETON (lane 1 red-first): transparent everywhere.
public struct TaggedElement<Content: Element>: Element {
    var content: Content
    var tag: AnyHashable

    init(content: Content, tag: AnyHashable) {
        self.content = content
        self.tag = tag
    }

    public var elementID: ElementID? { content.elementID }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    public mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.LayoutState) {
        content.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Content.LayoutState,
                                  pass: inout PrepaintPass) -> Content.PrepaintState {
        content.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Content.LayoutState, prepaint: inout Content.PrepaintState,
                               pass: inout PaintPass) {
        content.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension Element {
    public func tag<V: Hashable>(_ value: V) -> TaggedElement<Self> {
        TaggedElement(content: self, tag: AnyHashable(value))
    }
}
