import MetalUICore
import MetalUILayout

// `Column` and `Row` are `Box` with a `flexDirection` chosen for you.
//
// They **wrap** a `Box` rather than duplicating it, so there is one
// implementation of the three phases in the module and the two names cannot
// drift apart. They are distinct types rather than typealiases so that
// `type(of:)` reads `Column<Pair<…>>` — the spelling §4.6 uses, and the one the
// builder's type-level guard reads back.
//
// Direction is set at construction rather than exposed as a modifier on these
// two: `Column(...).flexDirection(.row)` would be a `Column` that is a row, and
// the type would then be lying. `Box` carries `flexDirection(_:)` for callers
// who want to choose, and `.rowReverse` / `.columnReverse` are reached that way.

/// A vertical flex container: `flex-direction: column`.
public struct Column<Content: ElementGroup>: Element, StyledElement {
    var box: Box<Content>

    public init(gap: Pixels = Pixels(0), @ElementBuilder content: () -> Content) {
        var style = Style()
        style.flexDirection = .column
        style.gap = Axes(both: .pixels(gap))
        box = Box(style: style, content: content())
    }

    public var style: Style {
        get { box.style }
        set { box.style = newValue }
    }

    public var elementID: ElementID? {
        get { box.elementID }
        set { box.elementID = newValue }
    }

    public mutating func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Content>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                  layout: inout Box<Content>.Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                               layout: inout Box<Content>.Layout,
                               prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// A horizontal flex container: `flex-direction: row`.
public struct Row<Content: ElementGroup>: Element, StyledElement {
    var box: Box<Content>

    public init(gap: Pixels = Pixels(0), @ElementBuilder content: () -> Content) {
        var style = Style()
        style.flexDirection = .row
        style.gap = Axes(both: .pixels(gap))
        box = Box(style: style, content: content())
    }

    public var style: Style {
        get { box.style }
        set { box.style = newValue }
    }

    public var elementID: ElementID? {
        get { box.elementID }
        set { box.elementID = newValue }
    }

    public mutating func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Content>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                  layout: inout Box<Content>.Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                               layout: inout Box<Content>.Layout,
                               prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
