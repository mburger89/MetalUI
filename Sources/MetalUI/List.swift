import MetalUICore
import MetalUILayout

/// A vertically stacked, uniformly sized sequence of rows built from data.
///
/// **Rows take identity from the data, and that is forced rather than
/// preferred.** Identity in this framework is structural: `.positional(Int)`
/// components are assigned by the cursor walking the built children, so a row
/// built only while visible lands on a different position when it returns —
/// the vanishing-`if` hazard made routine. `Data.Element: Identifiable` is
/// what stops that: each row is wrapped under `.named(ElementID(String(describing:
/// datum.id)))`, which survives a reorder because a name replaces a position
/// rather than joining it.
///
/// **`String(describing:)` is not injective, and this is a real, unguarded
/// gap.** Two distinct ids that happen to describe to the same string — e.g.
/// `AnyHashable("1")` and `AnyHashable(1)`, both `"1"` — collide into the SAME
/// `GlobalElementID`, so their rows silently share one `StateTable` entry.
/// Not fixed here: `ElementID` is `String`-backed, so `String(describing:)` is
/// the only bridge available, and changing that is a framework-wide job well
/// outside this milestone. A caller whose `Data.Element.ID` is not already
/// string-shaped (or is a wrapper like `AnyHashable`) must ensure distinct
/// ids describe distinctly.
///
/// **A uniform `rowHeight` is what makes windowing O(visible).** Every row's
/// own height is pinned to `rowHeight`, so a row's position is `index *
/// rowHeight` by construction and the eventual visible window is computed by
/// division, with no row laid out to find it. Variable heights need a
/// prefix-sum index and are out of scope.
///
/// **The pin is enforced by REMOVING the automatic minimum, not only by
/// setting a height.** A row `Box`'s `min-height: auto` default floors its
/// used height at its own content's size (CSS Sizing §4.5's content
/// suggestion, the half this engine implements — CLAUDE.md divergence 5), so
/// content taller than `rowHeight` would otherwise grow the row past it. And
/// a row's default `flexShrink: 1` lets negative free space (padding on
/// `List` shrinking its own content box below `data.count * rowHeight`) pull
/// every row back down. `rowStyle.minSize.height = 0` removes the floor;
/// `rowStyle.flexShrink = 0` removes the shrink — the identical pair
/// `ScrollView.requestLayout` sets on its content node for the same reason
/// (ruling CL-C), read that comment before touching either line here.
///
/// **This type does not window — every row is built, every frame.** `List`
/// sizes itself to `data.count * rowHeight` regardless of what any row
/// measures; the offset plumbing that builds only the visible slice reads
/// this type's own `data` and `row` builder, which is why both are stored
/// rather than consumed once in `init`.
///
/// **Stretches its rows on the cross axis, where `Column` would centre them**
/// (ruling EP-8's split): the outer container is a raw `Box`, whose `Style`
/// leaves `alignItems` at its `nil` default — CSS's `stretch` — rather than
/// the `.center` `Column`/`Row` set for themselves. A row with no explicit
/// width therefore fills `List`'s own width, which is the shape a list's rows
/// are expected to have.
public struct List<Data: RandomAccessCollection, Row: Element>: Element, StyledElement
where Data.Element: Identifiable {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?

    /// Retained rather than consumed in `init` — `requestLayout` is what
    /// builds the row array, so a later windowed implementation can build only
    /// the visible slice of `data` there instead of restructuring this type.
    private var data: Data
    private var rowHeight: Pixels
    private var row: (Data.Element) -> Row

    /// The rows this frame actually built, threaded from `requestLayout`
    /// through `prepaint` and `paint` the same way `Column`/`Row` thread their
    /// own `box` — `nil` only before `requestLayout` has run for this value.
    private var box: Box<ArrayGroup<Box<Row>>>?

    public init(_ data: Data, rowHeight: Pixels,
                @ElementBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.rowHeight = rowHeight
        self.row = row
        self.decoration = Decoration()
        self.elementID = nil

        var style = Style()
        style.flexDirection = .column
        style.size.height = .length(.pixels(rowHeight * Float(data.count)))
        self.style = style
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<ArrayGroup<Box<Row>>>.Layout) {
        // Every row is wrapped in its own `Box` so its height can be pinned
        // independently of `Row`'s own type — `Row` need not be `StyledElement`
        // for `List` to control its size. See the type doc for why both
        // `minSize.height` and `flexShrink` are overridden here, not only
        // `size.height`.
        var rowStyle = Style()
        rowStyle.size.height = .length(.pixels(rowHeight))
        rowStyle.minSize.height = .length(.pixels(Pixels(0)))
        rowStyle.flexShrink = 0

        let rows: [Box<Row>] = data.map { datum in
            // `String(describing:)` is the collision the type doc names —
            // distinct `datum.id`s that describe the same string land here as
            // the same `GlobalElementID`.
            Box(style: rowStyle, content: { row(datum) })
                .id(String(describing: datum.id))
        }

        var built = Box(style: style, decoration: decoration, content: ArrayGroup(rows))
        let result = built.requestLayout(id, pass: &pass)
        box = built
        return result
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<ArrayGroup<Box<Row>>>.Layout,
                                  pass: inout PrepaintPass) -> ArrayGroup<Box<Row>>.GroupPrepaint {
        box!.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<ArrayGroup<Box<Row>>>.Layout,
                               prepaint: inout ArrayGroup<Box<Row>>.GroupPrepaint,
                               pass: inout PaintPass) {
        box!.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
