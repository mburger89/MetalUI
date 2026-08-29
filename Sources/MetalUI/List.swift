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
/// rather than joining it. **It is also what makes windowing safe**: a row
/// built only while its index is inside the window still lands on the same
/// `GlobalElementID` every time it comes back into view, because its identity
/// never depended on the position windowing gives it among ITS built siblings
/// (that position varies frame to frame as the window slides) — only on its
/// name.
///
/// **That is about the NAME staying stable, not about the STATE surviving —
/// spec §7.5 is explicit that it does not.** A row outside the window is not
/// merely un-painted; it is not produced at all, so nothing marks its
/// `GlobalElementID` in the `StateTable` that frame, and `StateTable.sweep()`
/// reaps it exactly as it would an element removed from the tree for good
/// (§4.3). A row's own state — anything it keeps in the table, not the
/// framework's structural identity — is therefore reset, not preserved, the
/// next time that row scrolls back into the window.
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
/// rowHeight` by construction and the window is computed by division, with no
/// row laid out to find it. Variable heights need a prefix-sum index and are
/// out of scope.
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
/// **Windows against `LayoutPass.scrollContext`, published by the nearest
/// enclosing `ScrollView`.** `List` sizes itself to `data.count * rowHeight`
/// unconditionally — a fixed style property, not a sum over what is actually
/// built — so the scrollbar and the offset clamp see the full extent even
/// though only a slice of rows exists in the tree for any given frame. See
/// `visibleRange(count:pass:)` for the arithmetic and its escape hatches (no
/// context; a first-frame zero viewport; a zero or negative `rowHeight`).
///
/// **A leading spacer places the window, rather than an absolute inset per
/// row — chosen by reasoning about the two, not by measuring both; no
/// absolute-positioned version of this type was built to benchmark against.**
/// The alternative — `.position(.absolute).inset(top:)` on each row — is
/// available since the absolute-positioning milestone, and CLAUDE.md's
/// divergence 11 even names this exact composition (an absolute box inside a
/// `ScrollView` stays clipped and translated by it, which is what a windowed
/// row wants). It was set aside because it pulls every row out of flow, so
/// each row's position would have to be resolved against `List`'s own
/// containing block instead of falling out of ordinary flex placement — and a
/// spacer's height plus an ordinary flex column already places every built
/// row at exactly `index * rowHeight` with no absolute math at all. The
/// spacer costs one extra `Box` per frame, unconditionally, and buys not
/// having to reason about containing blocks inside a list. If a future
/// profile shows the spacer's flex participation costing more than an
/// absolute row would, that is the comparison this paragraph never ran.
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
    /// builds the row array, reading `data` fresh every frame so the window it
    /// builds always reflects the current scroll position.
    private var data: Data
    private var rowHeight: Pixels
    private var row: (Data.Element) -> Row

    /// Rows built beyond the exact window on each side, so a partially
    /// scrolled edge — the window's boundary landing mid-row rather than on a
    /// row edge — never shows a gap while a frame is in flight. Not exposed on
    /// `init`: a caller who needs a different value has no case yet, and a
    /// public knob nothing reads back would be exactly the shape CLAUDE.md's
    /// declared-but-inert table exists to keep out of this framework's API.
    private static var overscan: Int { 2 }

    /// The rows this frame actually built, threaded from `requestLayout`
    /// through `prepaint` and `paint` the same way `Column`/`Row` thread their
    /// own `box` — seeded with an empty placeholder here rather than left
    /// `Optional`, so a phase called out of order (a bug elsewhere) degrades
    /// to a stale empty frame instead of a force-unwrap trap. `requestLayout`
    /// always overwrites it before `prepaint`/`paint` read it on every
    /// correctly-ordered frame.
    private var box: Box<Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>>

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

        self.box = Box(style: style, decoration: decoration,
                       content: Pair(Box(style: Style()), ArrayGroup([])))
    }

    /// The half-open range of `data`'s indices to build this frame: the rows
    /// intersecting the viewport, widened by `overscan` on each side and
    /// clamped into `0..<count`.
    ///
    /// **Three escape hatches, all building everything.** No ambient context
    /// at all means this `List` is not inside a `ScrollView` — a list nobody
    /// scrolls must still render every row. A zero or negative `rowHeight` is
    /// otherwise legal, quiet input (`List` accepted it before windowing
    /// existed, sizing every row and the whole list to zero) and is the one
    /// value that can actually divide by zero below — `rowExtent` is the
    /// DIVISOR in both `offset / rowExtent` and `(offset + viewportExtent) /
    /// rowExtent`, so `rowExtent == 0` gives `.infinity` (or, at `offset ==
    /// 0`, `NaN`) and converting either to `Int` traps. Declining to window
    /// at all — rather than trying to divide by a height nothing can be
    /// windowed against — is what keeps that input as quiet as it always was.
    ///
    /// **A present context with `viewportExtent == 0` is a `ScrollView`'s
    /// first frame**, before its own `prepaint` has ever run to measure one.
    /// `viewportExtent` is only ever a NUMERATOR below, never a divisor, so
    /// this case does not risk dividing by zero at all — `0 / rowExtent` is
    /// simply `0`. What it risks instead: `offset` on that first frame is
    /// whatever was last scrolled to, so a naive window bounds almost nothing
    /// around it (a real first frame, measured with the guard removed, built
    /// exactly the two rows `overscan` allows around `offset == 0`) and the
    /// rest of the list fills in only once frame two has a real viewport —
    /// a visible one-frame flash. Building everything on that first frame
    /// costs one slow frame instead of a flash.
    private func visibleRange(count: Int, pass: LayoutPass) -> Range<Int> {
        guard let context = pass.scrollContext, context.viewportExtent > 0,
              rowHeight.value > 0 else {
            return 0..<count
        }
        let extent = Double(rowHeight.value) * Double(count)
        // The ambient offset is raw and unclamped (`ScrollContext`'s own doc);
        // this is the clamp `List` owns because it — unlike `LayoutPass` — knows
        // its own exact content extent without waiting on a resolved layout.
        let offset = min(max(0, context.offset), max(0, extent - context.viewportExtent))
        let rowExtent = Double(rowHeight.value)
        let rawFirst = Int((offset / rowExtent).rounded(.down)) - Self.overscan
        let rawLast = Int(((offset + context.viewportExtent) / rowExtent).rounded(.up)) + Self.overscan
        let first = min(max(0, rawFirst), count)
        let last = min(max(first, rawLast), count)
        return first..<last
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>>.Layout) {
        // Every row is wrapped in its own `Box` so its height can be pinned
        // independently of `Row`'s own type — `Row` need not be `StyledElement`
        // for `List` to control its size. See the type doc for why both
        // `minSize.height` and `flexShrink` are overridden here, not only
        // `size.height`.
        var rowStyle = Style()
        rowStyle.size.height = .length(.pixels(rowHeight))
        rowStyle.minSize.height = .length(.pixels(Pixels(0)))
        rowStyle.flexShrink = 0

        let count = data.count
        let window = visibleRange(count: count, pass: pass)

        let windowStart = data.index(data.startIndex, offsetBy: window.lowerBound)
        let windowEnd = data.index(data.startIndex, offsetBy: window.upperBound)

        let rows: [Box<Row>] = data[windowStart..<windowEnd].map { datum in
            // `String(describing:)` is the collision the type doc names —
            // distinct `datum.id`s that describe the same string land here as
            // the same `GlobalElementID`.
            Box(style: rowStyle, content: { row(datum) })
                .id(String(describing: datum.id))
        }

        // Places the window: a plain `Box` sized to exactly the rows skipped,
        // so the first built row lands at `window.lowerBound * rowHeight` —
        // its true absolute offset — rather than at the top of whatever the
        // window happens to be. `flexShrink = 0` is load-bearing here for the
        // same reason it is on a row: padding on `List` can shrink its
        // content box below the built children's combined height, and
        // without this the SPACER — not a row, since rows carry their own
        // pin — would absorb that deficit and pull every windowed row up by
        // however much it lost. (No `minSize.height` override: this `Box` is
        // childless, so its automatic minimum is already 0 — nothing to
        // remove, unlike a row, whose content can be taller than
        // `rowHeight`.)
        var spacerStyle = Style()
        let spacerHeight = Pixels(rowHeight.value * Float(window.lowerBound))
        spacerStyle.size.height = .length(.pixels(spacerHeight))
        spacerStyle.flexShrink = 0
        let spacer = Box(style: spacerStyle)

        var built = Box(style: style, decoration: decoration,
                        content: Pair(spacer, ArrayGroup(rows)))
        let result = built.requestLayout(id, pass: &pass)
        box = built
        return result
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>>.Layout,
                                  pass: inout PrepaintPass)
        -> Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>.GroupPrepaint {
        box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>>.Layout,
                               prepaint: inout Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>.GroupPrepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
