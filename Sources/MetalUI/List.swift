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
/// **`rowStyle.minSize.height = 0` is kept as a statement of intent, and its
/// documented mechanism NO LONGER FIRES.** Read this before deciding either
/// line below is load-bearing.
///
/// This paragraph used to say that a row `Box`'s `min-height: auto` default
/// floors its used height at its own content's size — "CSS Sizing §4.5's
/// content suggestion, **the half this engine implements** — CLAUDE.md
/// divergence 5" — so that content taller than `rowHeight` would grow the row
/// past it. **Every clause of that is now wrong**, and it went wrong in a file
/// the sizing milestone never touched, which is why nothing prompted a
/// re-read. Divergence 5 is retired and its label is never reused; both halves
/// of §4.5 are implemented as of that milestone's Task 6 (ruling FS-3, pinned
/// by `SizingFixtureTests`' two `sizing_specified_suggestion*` cases); and
/// the automatic minimum is therefore `min(specified suggestion, content
/// suggestion)`. A row declares `height: rowHeight` two lines below, so its
/// specified suggestion **is** `rowHeight`, the `min` can never exceed
/// `rowHeight`, and the floor this line removes cannot raise a row above the
/// pin it is protecting.
///
/// Measured rather than argued (throwaway probe, the sizing milestone's fix
/// wave): two 28pt rows each holding a 50pt child, in a 56pt column, with the
/// floor removed and with it left at `auto`, crossed with `flexShrink` 0 and
/// 1 — **all four arms give `r1.height = 28` and `r2.y = 28`.**
///
/// It is kept anyway, and not because it might come back: it says what this
/// type means, it is the identical pair `ScrollView.requestLayout` sets for
/// its own reason (below), and it is the general remover of the floor for any
/// future row style that does *not* declare a height, where the `min` would
/// again be the content size. Do not delete it on the strength of the
/// measurement above; do not cite the old mechanism either.
///
/// **The `flexShrink` half is untouched by all of the above and was NOT
/// re-measured**, so it is carried forward as written rather than vouched for:
/// a row's default `flexShrink: 1` lets negative free space (padding on
/// `List` shrinking its own content box below `data.count * rowHeight`) pull
/// every row back down, and `rowStyle.flexShrink = 0` removes the shrink. That
/// is a §9.7 fact rather than a §4.5 one, so nothing FS-3 changed reaches it.
/// The two lines together are the identical pair `ScrollView.requestLayout`
/// sets on its content node (ruling CL-C) — read that comment before touching
/// either line here.
///
/// **Windows against `LayoutPass.scrollContext`, published by the nearest
/// enclosing `ScrollView`.** `List` sizes itself to `data.count * rowHeight`
/// unconditionally — a fixed style property, not a sum over what is actually
/// built — so the scrollbar and the offset clamp see the full extent even
/// though only a slice of rows exists in the tree for any given frame. See
/// `visibleRange(count:pass:)` for the arithmetic and its escape hatches (no
/// context; a non-vertical one; a first-frame zero viewport; a zero or negative
/// `rowHeight`).
///
/// **A `List` must be its enclosing `ScrollView`'s only layout-contributing
/// child, and violating that renders it BLANK rather than merely imprecise.**
/// This is a requirement of the same rank as `Identifiable` and a uniform
/// `rowHeight`, and unlike those two nothing enforces it: `ScrollView { Text(...);
/// List(...) }` compiles, lays out, and paints nothing where the list should be.
/// The ambient `ScrollContext` describes the SCROLLER — how far the scroller's
/// content has moved under its viewport — and `visibleRange` reads it as though
/// it described this `List`, i.e. as though row 0 sat exactly at the scroller's
/// content origin. Put anything that occupies FLOW above the list — a header, a
/// spacer, a second `List` — and the two differ by that thing's height, so the
/// window slides off the rows actually on screen. Measured, with a 300pt header
/// above a 40-row list at `rowHeight` 28, viewport 112, scrolled to 300: the
/// rows visible are 0 through 3 and the rows built are **8 through 16**, every
/// one of them painted below the viewport under a mask that shows none of them.
///
/// **Two measured refinements of that rule, in opposite directions.** An
/// out-of-flow sibling costs nothing — a `.position(.absolute)` box declared
/// before the list, which is what the demo's own `Deferred` modal is, leaves the
/// rows at y = 0 — so the requirement is about flow rather than about sibling
/// count. And making the `List` itself absolute does not save it: at
/// `.position(.absolute)` with `inset(top: 300)` it builds the identical wrong
/// rows, because the window comes from the ambient offset either way.
///
/// **Not fixable from inside this type, which is why it is a documented
/// requirement rather than a bug with a fix pending** (ruling MP-L, CLAUDE.md
/// divergence 14). Correcting the window needs this `List`'s own offset within
/// the scroller's content, and `requestLayout` has no position — that is the
/// phase's contract, not an oversight. Supplying one means either laying the
/// scroller out twice or threading resolved geometry into a phase defined to run
/// before geometry exists. Pinned by
/// `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, so the fix,
/// when it comes, arrives as a red test rather than as a surprise.
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
///
/// **Exposes its full logical count to accessibility (design spec §9), but
/// not its realized children — read this before wondering why VoiceOver
/// finds no rows.** Every `List` emits its own `AXNode` (`role: .container`
/// by default) unconditionally, carrying `logicalCount = data.count`
/// regardless of how many rows this frame actually built — that half of §9's
/// "3 of 500" is real (Task 7, `AXNodeTests.swift`). **The "3" half is not**:
/// `AXNode.children` is always `[]` in production (see its own doc for why —
/// `ElementGroup` hands a container a flat `[LayoutNodeID]`, not per-child
/// ids, and reconstructing order from `Frame.axNodes`' own keys is provably
/// ambiguous), and `List`'s row-wrapping `Box`es carry no `AXNode` of their
/// own unless a caller's row element sets one. Measured on a production
/// 500-row `List` (rows built as ordinary `Box { Text(...) }`, with or
/// without `.onClick`): `Frame.axNodes` holds exactly **one** entry — the
/// `List`'s own container — with **zero** row nodes. An M4 accessibility
/// bridge reading a `List` today gets the 500 and nothing to attach it to;
/// closing that needs the same `ElementGroup` change named above and is
/// deferred outside this milestone.
public struct List<Data: RandomAccessCollection, Row: Element>: Element, StyledElement
where Data.Element: Identifiable {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?

    /// Stored here and copied onto the `Box` `requestLayout` builds, because
    /// that box is rebuilt from scratch on every frame — a `handlers` computed
    /// through to `box` would be written before the box it wrote to was
    /// replaced.
    public var handlers: Handlers = Handlers()

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
    /// **Four escape hatches, all building everything.** No ambient context
    /// at all means this `List` is not inside a `ScrollView` — a list nobody
    /// scrolls must still render every row. A context whose `axis` is
    /// `.horizontal` describes a scroller moving across an axis this `List`
    /// does not stack on: its `offset` is a horizontal distance and its
    /// `viewportExtent` is a WIDTH, and windowing a column of rows against
    /// either is not an approximation but a category error. Measured before
    /// this clause existed, on a 40-row list at `rowHeight` 28 under
    /// `ScrollContext(offset: 240, viewportExtent: 300, axis: .horizontal)`:
    /// rows 6 through 21 were built while rows 0 onward were the ones on
    /// screen. A vertical `List` inside a horizontal `ScrollView` is a real
    /// composition — a row of columns — and the honest answer for it is the
    /// one a `List` outside every scroller gets. (There is no windowing
    /// *for* a horizontal scroller to be had here either way: `List` stacks
    /// on the block axis by construction, so a horizontal offset selects no
    /// subset of its rows.) A zero or negative `rowHeight` is
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
        guard let context = pass.scrollContext, context.axis == .vertical,
              context.viewportExtent > 0, rowHeight.value > 0 else {
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
        // Carried onto the freshly-built box so `Box.prepaint` registers the
        // click target — this type has no `prepaint` of its own to do it in.
        // `.axNode` rides the same trip: design spec §9's virtualization
        // requirement is that a `List` exposes its FULL logical count
        // (`count`, `data.count` above) regardless of how many rows this
        // frame actually realized (`rows.count`, always <= `count` once
        // windowing is active) — the two are asserted as different numbers
        // by `AXNodeTests.swift`'s `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`.
        // Unconditional, unlike every other declared `AXNode` field: nothing
        // gates this behind a caller opting in (there is no public modifier
        // for `.axNode` at all yet — see `AXNode.swift`'s own doc), because
        // the exit criterion is that a `List` always exposes this, not that
        // one CAN. A role is set only when the caller declared none, so a
        // future `.axNode(_:)` modifier's own `role`/`label` are not
        // silently overwritten here.
        var listHandlers = handlers
        if listHandlers.axNode.isEmpty {
            listHandlers.axNode = AXNode(role: .container)
        }
        listHandlers.axNode.logicalCount = count
        built.handlers = listHandlers
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
