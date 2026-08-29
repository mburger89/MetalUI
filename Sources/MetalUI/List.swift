import MetalUICore
import MetalUILayout

/// A vertically stacked, uniformly sized sequence of rows built from data.
///
/// **Rows take identity from the data, and that is forced rather than
/// preferred.** Identity in this framework is structural: `.positional(Int)`
/// components are assigned by the cursor walking the built children. Once
/// Task 6 builds only the visible window, a row that scrolls out and back
/// lands on a different position — so a positionally-identified row would
/// adopt a neighbour's state, which is the vanishing-`if` hazard made routine.
/// `Data.Element: Identifiable` is what stops that: each row is wrapped under
/// `.named(ElementID(String(describing: datum.id)))`, which survives a reorder
/// because a name replaces a position rather than joining it.
///
/// **A uniform `rowHeight` is what makes windowing O(visible).** Every row's
/// own height is pinned to `rowHeight`, so a row's position is `index *
/// rowHeight` by construction and the eventual visible window is computed by
/// division, with no row laid out to find it. Variable heights need a
/// prefix-sum index and are out of scope.
///
/// **This type does not window — every row is built, every frame.** `List`
/// sizes itself to `data.count * rowHeight` regardless of what any row
/// measures; the offset plumbing that builds only the visible slice is a
/// later task's addition, not this one's.
public struct List<Data: RandomAccessCollection, Row: Element>: Element, StyledElement
where Data.Element: Identifiable {
    var box: Box<ArrayGroup<Box<Row>>>

    public init(_ data: Data, rowHeight: Pixels,
                @ElementBuilder row: @escaping (Data.Element) -> Row) {
        // Every row is wrapped in its own `Box` so its height can be pinned
        // independently of `Row`'s own type — `Row` need not be `StyledElement`
        // for `List` to control its size.
        var rowStyle = Style()
        rowStyle.size.height = .length(.pixels(rowHeight))

        let rows: [Box<Row>] = data.map { datum in
            Box(style: rowStyle, content: { row(datum) })
                .id(String(describing: datum.id))
        }

        var style = Style()
        style.flexDirection = .column
        style.size.height = .length(.pixels(rowHeight * Float(data.count)))

        box = Box(style: style, content: ArrayGroup(rows))
    }

    public var style: Style {
        get { box.style }
        set { box.style = newValue }
    }

    public var decoration: Decoration {
        get { box.decoration }
        set { box.decoration = newValue }
    }

    public var elementID: ElementID? {
        get { box.elementID }
        set { box.elementID = newValue }
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<ArrayGroup<Box<Row>>>.Layout) {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<ArrayGroup<Box<Row>>>.Layout,
                                  pass: inout PrepaintPass) -> ArrayGroup<Box<Row>>.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<ArrayGroup<Box<Row>>>.Layout,
                               prepaint: inout ArrayGroup<Box<Row>>.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
