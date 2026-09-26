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
/// **That is about the NAME staying stable. The STATE now survives too — but
/// only for a BOUNDED window, and this paragraph said the opposite until the
/// tombstones milestone (2026-09-01).** What it used to say, and what spec
/// §7.5 was written against: a row outside the window is not merely
/// un-painted, it is not produced at all, so nothing marks its
/// `GlobalElementID` in the `StateTable` that frame, and `StateTable.sweep()`
/// reaped it exactly as it would an element removed from the tree for good
/// (§4.3) — so a row's own state was reset, not preserved, the next time it
/// scrolled back in. That was CLAUDE.md's divergence 12, and it is retired.
///
/// **What is true now.** `sweep()` retains an unmarked entry *with its value*
/// and only clears its `isLive` flag; a separate **reap** removes an entry
/// that has been unmarked for more than `StateTable.staleAfterGenerations`
/// (**2**) generations, and only on a sweep where `storage.count` exceeds
/// `StateTable.sweepThreshold` (**256**). So a row scrolled out and back
/// within two generations finds its `@State` intact; a row gone for three
/// generations, on a table over threshold, comes back holding a fresh
/// `initial()` under the same identity. **A focused row rides the identical
/// bound** through a dedicated `$focus` retention slot (that was divergence
/// 17, also retired).
///
/// **The threshold clause is not a technicality here, and a SHORT list is the
/// case it changes.** The reap runs only above 256 entries, so a list reaches
/// it only once enough rows have been built to put the table over — the cold
/// frame builds every row (ruling MP-I).
///
/// **Corrected 2026-09-10: crossing no longer requires a row to carry `@State`
/// at all, and the row count that crosses is much lower than this comment
/// said.** The animation milestone's `animated(_:_:for:pass:)` mints a `$anim`
/// entry on first sight of every registering element, unconditionally
/// (`AnimatedStyle.swift:309` — the `withState` call is not gated on anything
/// being in flight), so a `List` row that is a plain `Box` costs a `StateTable`
/// entry whether or not it declares state. Measured on the committed
/// `demoLikeRows(_:)` fixture, whose rows carry **no `@State` whatsoever**:
/// `storage.count` is exactly `2n + 6`, so 40 rows read 86, **126 rows read 258
/// and cross**, and 500 rows read 1006.
///
/// **`2n + 6` and 126, not `2n + 7` and 125, since plan task 7's stage 4 lane 1**
/// (`LR-BS`): the windowing spacer stopped being a `Box` element, taking its
/// unconditional `$anim` entry with it, so the fixed overhead fell by one and
/// the crossing moved by one row. The reap gate is `storage.count >
/// sweepThreshold` with `sweepThreshold == 256`, so crossing needs **257**;
/// `2n + 6 ≥ 257` first holds at *n* = 126, and *n* = 125 now reads 256, which
/// does not cross. Re-measured by rendering 124, 125, 126, 127 and 500 rows and
/// watching whether a three-generation excursion was actually reaped — 125
/// retains, 126 reaps — rather than by adjusting the old arithmetic. The demo's own list is 500 rows
/// (`demoRowCount`, `Sources/MetalUIDemoContent/DemoContent.swift`), so the demo crosses the gate on its cold frame. Read the
/// old claim — "a 500-row list crosses it and a 40-row one never does" — as
/// accidentally still true at those two endpoints and wrong about the reason
/// and about everything between 125 and 500. **Below the threshold
/// nothing is ever reaped and a row's `@State` survives any excursion, of any
/// length.** That is not specific to `List`: it is CLAUDE.md's divergence 18,
/// which records the same retention for every conditional subtree in the
/// framework and notes that it disagrees with SwiftUI. Read "two generations"
/// as the ceiling a large table imposes rather than as what a small one does.
///
/// **So the old advice survives for long excursions and only for those**: a
/// value a long scroll must not lose belongs in the **data**, which is where
/// a windowed list wants it anyway — `List` re-reads `data` every frame, so a
/// value derived from a datum is stable by construction and one a row stores
/// privately is stable only inside the window above. Pinned by
/// `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`
/// (`TombstoneTests.swift`) and
/// `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`
/// (`FocusTests.swift`), each of which asserts both halves.
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
/// by `SizingFixtureTests`' two `sizing_specified_suggestion*` cases until
/// stage 7a retired the goldens and 7b the file); and
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
/// **A `List` windows against its OWN origin within its scroller's content**
/// (ruling `DD-F`, plan task 10; divergence 14 retired). Until then it read the
/// ambient `ScrollContext` — which describes the SCROLLER — as though row 0 sat
/// at the scroller's content origin, so anything in flow above the list (a
/// header, a spacer, a second `List`) slid the window off the rows on screen and
/// rendered it **blank**: a 300pt header above a 40-row list at `rowHeight` 28,
/// viewport 112, scrolled to 300, built rows 8…16 where 0…3 were visible
/// (`MP-L` called it unfixable because `requestLayout` has no position). The
/// fix meets that blocker the way `ScrollState.viewportExtent` meets the
/// viewport's: **last frame's measurement**. In `prepaint`, inside a vertical
/// scroller (`Frame.activeScrollerFrame`, pushed by `ScrollView` and
/// `ProposalScrollView`; reset by `Deferred`), the list stores its origin at its
/// own id (`ListOrigin`, through `withState` — never `write`), and
/// `requestLayout` windows against it. Pinned by
/// `aListBelowAHeaderWindowsTheRowsOnScreen`.
///
/// **One more frame when the window went stale, and only then** (`DD-F` item
/// 3). The first frame after a resize, or after something above the list
/// changed height, still windows against last frame's measurements — the two
/// rows of overscan are the only cover for that frame (divergence 13, amended)
/// — but `prepaint` sees the fresh window is not contained in the one it built
/// and calls `requestAnotherFrame()`, so the next frame is drawn, and correct,
/// with no input. Pinned by `aGrownViewportIsFilledOnTheNextFrameWithoutInput`
/// and `aListWhoseOriginChangesIsReWindowedOnTheNextFrame`;
/// `anUnboundedListFrameAsksForNoExtraFrame` pins that a frame that built
/// every row asks for nothing.
///
/// **`ListRows`' `WindowedRowsLayout` places the window**: built row *i* at
/// `(firstIndex + i) × rowHeight`, directly (`LR-BQ`, `LR-BR`). Until stage 9 the
/// legacy authority used a leading spacer sized `firstIndex × rowHeight` and an
/// ordinary flex column instead (a `Box` element until stage 4, a bare node
/// after, `LR-BS`); it went with the legacy engine (`LR-FC`).
///
/// **Stretches its rows on the cross axis, where `Column` would centre them**
/// (ruling EP-8's split): the outer container is a raw `Box`, whose `Style`
/// leaves `alignItems` at its `nil` default — CSS's `stretch` — rather than
/// the `.center` `Column`/`Row` set for themselves. A row with no explicit
/// width therefore fills `List`'s own width, which is the shape a list's rows
/// are expected to have.
///
/// **Exposes its full logical count to accessibility (design spec §9), and,
/// to an active client only, its realized rows with their indices.** Every
/// `List` emits its own `AXNode` (`role: .container` by default)
/// unconditionally, carrying `logicalCount = data.count` regardless of how
/// many rows this frame actually built (Task 7, `AXNodeTests.swift`).
/// `Frame.axNodes` still holds exactly **one** entry for a production list —
/// its own — and `AXNode.children` is still `[]` (see its own doc).
///
/// **The "3" half reaches a client another way** (rulings AB-C, AB-L, AB-X).
/// While a client is active and the window is bounded, each realized row `Box`
/// carries the internal `AXNode.logicalIndex`, a hint `Frame.registerHandlers`
/// strips before it decides whether to emit, so it records for the client and
/// writes neither `axNodes` nor a `$ax` slot. `AccessibilityTreeBuilder`
/// publishes the list as a table whose row count is `data.count`, **whatever
/// role or label a caller declared**, and each row as a `.row` child with its
/// index, hierarchy coming from record order rather than from `children`.
/// While the window is **unbounded** (no vertical scroll context, or the
/// scroller's first frame), the list publishes its table and **no rows**, and
/// on that first frame asks for exactly one more frame so the realized window
/// follows; see `prepaint`. Rows outside the window are not elements, so a
/// client cannot move to them (AB-Q item 2).
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

    /// The rows this frame actually built — the outer `Box` over `ListRows`,
    /// which holds each realized row — threaded
    /// from `requestLayout`
    /// through `prepaint` and `paint` the same way `Column`/`Row` thread their
    /// own `box` — seeded with an empty placeholder here rather than left
    /// `Optional`, so a phase called out of order (a bug elsewhere) degrades
    /// to a stale empty frame instead of a force-unwrap trap. `requestLayout`
    /// always overwrites it before `prepaint`/`paint` read it on every
    /// correctly-ordered frame.
    private var box: Box<ListRows<Row>>

    /// Whether this frame's window came from the viewport rather than from one
    /// of `visibleRange`'s escape hatches, which build every row. Threaded from
    /// `requestLayout` to `prepaint` like `box` (ruling AB-X rule 1).
    private var windowIsBounded = false

    /// Whether the window is unbounded only because the enclosing vertical
    /// scroller has not measured a viewport yet — every `ScrollView`'s first
    /// frame (MP-I). The one unbounded case the next frame can fix (AB-X rule 3).
    private var windowAwaitsViewport = false

    /// The window `requestLayout` built this frame, threaded to `prepaint`
    /// like `box`, which compares it with the window this frame's fresh
    /// measurements would give (ruling `DD-F` item 3).
    private var builtWindow: Range<Int> = 0..<0

    /// `List`'s layout state, as a **public wrapper around an internal one**.
    ///
    /// `Element.LayoutState` is inferred from `requestLayout`'s return, and
    /// what `requestLayout` really carries is `Box<ListRows<Row>>.Layout` —
    /// generic over `ListRows`, which is `internal` (ruling `LR-BS`: the row
    /// arrangement is a framework detail, and stage 4's whole API surface is
    /// internal). An internal type in a public method's signature does not
    /// compile, so the witness is wrapped rather than the arrangement made
    /// public. `PrepaintState` below is the same shape for the same reason;
    /// **both** are needed, and the design named only the first (`LR-BZ`).
    public struct Layout {
        var inner: Box<ListRows<Row>>.Layout
    }

    /// `List`'s prepaint state, wrapped for the reason `Layout` is: `prepaint`
    /// returns it and `paint` takes it `inout`, so an internal
    /// `ListRows<Row>.GroupPrepaint` would sit in two public signatures.
    public struct PrepaintState {
        var inner: ListRows<Row>.GroupPrepaint
    }

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
                       content: ListRows(rows: [],
                                         rowHeight: Double(rowHeight.value),
                                         logicalCount: data.count, firstIndex: 0,
                                         listStyle: style))
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
    ///
    /// **Against this list's own origin within the scroller's content** (ruling
    /// `DD-F` item 1; divergence 14 retired). `requestLayout` has no position,
    /// so the origin is **last frame's measurement**, stored by `prepaint` at
    /// this list's id — the way `ScrollState.viewportExtent` already carries
    /// the viewport. With none stored (the list's first frame inside its
    /// scroller) it is 0, today's answer. See `window(count:rowExtent:offset:viewport:origin:)`.
    private func visibleRange(count: Int, origin: Double, pass: LayoutPass) -> Range<Int> {
        guard let context = pass.scrollContext, context.axis == .vertical,
              context.viewportExtent > 0, rowHeight.value > 0 else {
            return 0..<count
        }
        return Self.window(count: count, rowExtent: Double(rowHeight.value),
                           offset: context.offset, viewport: context.viewportExtent,
                           origin: origin)
    }

    /// The rows intersecting the viewport — the scroller's `offset` and
    /// `viewport`, seen from a list whose row 0 sits `origin` down the
    /// scroller's content — widened by `overscan` and clamped into `0..<count`.
    /// Needs `rowExtent > 0` and `viewport > 0` (the callers' guards).
    ///
    /// **The list-local top is clamped into `0...max(0, extent − viewport)`**,
    /// the clamp this type has always applied to the raw offset (the ambient
    /// offset is raw and unclamped, `ScrollContext`'s own doc). At `origin` 0
    /// that is exactly the pre-`DD-F` window; with an origin it keeps the
    /// window a **superset** of the rows actually on screen when the list is
    /// partly above or below the viewport (a band that starts above row 0, or
    /// runs past the last row, is served by the nearest full viewport of rows),
    /// so a list scrolled past never windows to nothing.
    static func window(count: Int, rowExtent: Double, offset: Double, viewport: Double,
                       origin: Double) -> Range<Int> {
        let extent = rowExtent * Double(count)
        let top = min(max(0, offset - origin), max(0, extent - viewport))
        let rawFirst = Int((top / rowExtent).rounded(.down)) - Self.overscan
        let rawLast = Int(((top + viewport) / rowExtent).rounded(.up)) + Self.overscan
        let first = min(max(0, rawFirst), count)
        let last = min(max(first, rawLast), count)
        return first..<last
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        // **There is no site check here since plan task 7's stage 4** (`LR-BQ`).
        // It read `noteUnlowerable(.list, "noLowering")` before any row was
        // built, because a `List` registers no node of its own and would
        // otherwise have lowered silently through the `Box` below. `ListRows`
        // now registers a `WindowedRowsLayout` — see that type's doc — and this
        // type's own code has no layout branch: the window, the row ids, the
        // handlers and the accessibility records are built here once.

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
        // `DD-F` item 1: last frame's measured origin, read with `peek` so a
        // list outside every scroller mints no entry. `prepaint` stores it.
        let origin = pass.frame.stateTable.peek(id, as: ListOrigin.self)?.offset ?? 0
        let window = visibleRange(count: count, origin: origin, pass: pass)
        builtWindow = window
        // The same test `visibleRange`'s guard makes, kept rather than inferred
        // from `window`: a short list's real window can equal `0..<count`.
        let context = pass.scrollContext
        windowIsBounded = context.map { $0.axis == .vertical && $0.viewportExtent > 0 } == true
            && rowHeight.value > 0
        windowAwaitsViewport = context.map { $0.axis == .vertical && !($0.viewportExtent > 0) } == true
        // A row's logical index, for an accessibility client, only while one is
        // active and only for a bounded window (AB-L, AB-X): an unbounded window
        // publishes no rows at all, so indices there would be written for nothing.
        //
        // **The `windowIsBounded` conjunct is belt-and-braces and NOTHING can
        // pin it** — measured, plan task 7 stage 4 lane 4's mutation M4b
        // (`LR-CF`). Dropping it and running the whole suite unfiltered reddens
        // not one test, because the two things a hint could reach are both shut
        // on an unbounded window anyway: `prepaint` below wraps the rows in
        // `withAccessibilitySuppressed(except: id)`, which is what
        // `Frame.registerHandlers`' record branch checks, and that method strips
        // `logicalIndex` before its `declaration.isEmpty` test, so a hint alone
        // emits no `AXNode` and writes no `$ax` slot either (AB-L, AB-U). The
        // line stays because it says what this value means; the measurement is
        // recorded here so a later reader does not mistake it for a tested
        // guard. `AB-X` rule 1 is pinned through the suppression instead, by
        // `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`
        // and `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`'
        // zero-`rowHeight` arm, both on both layout authorities (mutation M4b').
        let indexesRows = windowIsBounded && pass.collectsAccessibility

        let windowStart = data.index(data.startIndex, offsetBy: window.lowerBound)
        let windowEnd = data.index(data.startIndex, offsetBy: window.upperBound)

        let rows: [Box<Row>] = data[windowStart..<windowEnd].enumerated().map { offset, datum in
            // `String(describing:)` is the collision the type doc names —
            // distinct `datum.id`s that describe the same string land here as
            // the same `GlobalElementID`.
            var rowBox = Box(style: rowStyle, content: { row(datum) })
                .id(String(describing: datum.id))
            if indexesRows { rowBox.handlers.axNode.logicalIndex = window.lowerBound + offset }
            return rowBox
        }

        // The window is placed by `ListRows`' `WindowedRowsLayout`, which puts
        // built row *i* at `(window.lowerBound + i) × rowHeight` directly
        // (`LR-BQ`); until stage 9 a leading spacer node did it for the legacy
        // flex column (`LR-FC`).
        var built = Box(style: style, decoration: decoration,
                        content: ListRows(rows: rows,
                                          rowHeight: Double(rowHeight.value),
                                          logicalCount: count,
                                          firstIndex: window.lowerBound,
                                          listStyle: style))
        // Carried onto the freshly-built box so `Box.prepaint` registers the
        // click target — this type has no `prepaint` of its own to do it in.
        // `.axNode` rides the same trip: design spec §9's virtualization
        // requirement is that a `List` exposes its FULL logical count
        // (`count`, `data.count` above) regardless of how many rows this
        // frame actually realized (`rows.count`, always <= `count` once
        // windowing is active) — the two are asserted as different numbers
        // by `AXNodeTests.swift`'s `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`.
        // Unconditional, unlike every other declared `AXNode` field: nothing
        // gates this behind a caller opting in (no public modifier sets a
        // count or a role; `accessibilityLabel`/`accessibilityValue` set only
        // their own field), because the exit criterion is that a `List`
        // always exposes this, not that one CAN. A role is set only when the
        // caller declared nothing, so `List(…).accessibilityLabel("Contacts")`
        // keeps its label and a `generic` role — which is why the accessibility
        // builder makes any node with a `logicalCount` a table whatever its
        // role (ruling AB-L, arm R16).
        var listHandlers = handlers
        if listHandlers.axNode.isEmpty {
            listHandlers.axNode = AXNode(role: .container)
        }
        listHandlers.axNode.logicalCount = count
        built.handlers = listHandlers
        let (node, inner) = built.requestLayout(id, pass: &pass)
        box = built
        return (node, Layout(inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> PrepaintState {
        noteOriginAndStaleness(id, bounds: bounds, pass: pass)
        // **An unbounded window publishes the table and no rows** (ruling AB-X
        // rule 1): it built every row, and a client active at frame 0 would
        // otherwise be handed a row and a text per datum, then see them all
        // destroyed on the next frame. The list's own node is the scope's
        // exception, so the row count still publishes. Records only — the rows
        // still register hitboxes, focus and declared nodes as always.
        guard pass.collectsAccessibility, !windowIsBounded else {
            return PrepaintState(inner: box.prepaint(id, bounds: bounds,
                                                     layout: &layout.inner, pass: &pass))
        }
        // Nothing else would draw the frame that bounds the window: `ScrollView`
        // stores its measured viewport through `withState`, which fires no
        // `onWrite` (AB-X rule 3). A list with no scroll context never asks.
        if windowAwaitsViewport { pass.frame.requestAccessibilityRetry() }
        let frame = pass.frame
        return PrepaintState(inner: frame.withAccessibilitySuppressed(except: id) {
            box.prepaint(id, bounds: bounds, layout: &layout.inner, pass: &pass)
        })
    }

    /// Ruling `DD-F` items 1 and 3, inside a vertical scroller
    /// (`Frame.activeScrollerFrame`; none inside a `Deferred`):
    ///
    /// 1. **Stores this list's origin** within the scroller's content — its
    ///    own bounds' origin minus the content node's, both layout space — at
    ///    its own id through `withState`, **never `write`**: `withState` raises
    ///    no `isDirty` and fires no `onWrite` (`ScrollChrome.resolvedOffset`'s
    ///    prepaint write-back is the precedent), so this cannot keep the
    ///    display link awake. The subtraction is pinned by
    ///    `aListInAScrollerBelowTheWindowOriginWindowsTheRowsOnScreen` (a
    ///    scroller 88pt below the window origin; V3, the bounds alone, builds
    ///    rows 5…13 where 10…14 are on screen). No new reserved name
    ///    (`theSevenRetentionSlotsAreMutuallyDistinct` unmoved). Pinned by
    ///    `anUnboundedListFrameAsksForNoExtraFrame`.
    /// 2. **Asks for one more frame when the window it built is stale**: the
    ///    window this frame's fresh inputs (the measured origin, this frame's
    ///    viewport, the resolved offset) give is not contained in `builtWindow`
    ///    — a grown viewport (divergence 13's effect, amended) or a list that
    ///    moved within its content. A frame that built every row contains any
    ///    window, so the unbounded first frame (`MP-I`) asks for nothing, and
    ///    the next frame builds exactly the fresh window, so the request
    ///    cannot repeat. `requestAnotherFrame()`, never `noteActiveAnimation()`.
    private func noteOriginAndStaleness(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                        pass: PrepaintPass) {
        guard let scroller = pass.frame.activeScrollerFrame, scroller.axis == .vertical else {
            return
        }
        let origin = Double(bounds.origin.y.value - scroller.contentOrigin.y.value)
        pass.withState(id, initial: ListOrigin()) { $0.offset = origin }

        let count = data.count
        let fresh: Range<Int>
        if scroller.viewportExtent > 0, rowHeight.value > 0 {
            fresh = Self.window(count: count, rowExtent: Double(rowHeight.value),
                                offset: scroller.offset, viewport: scroller.viewportExtent,
                                origin: origin)
        } else {
            fresh = 0..<count
        }
        let contained = fresh.isEmpty
            || (builtWindow.lowerBound <= fresh.lowerBound && fresh.upperBound <= builtWindow.upperBound)
        if !contained { pass.frame.requestAnotherFrame() }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout PrepaintState,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout.inner, prepaint: &prepaint.inner, pass: &pass)
    }
}

/// A `List`'s origin within its scroller's content, in points down the
/// scrolling axis — last frame's measurement, stored at the list's own id
/// (ruling `DD-F` item 1).
struct ListOrigin: Sendable {
    var offset: Double = 0
}
