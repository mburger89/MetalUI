import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct Item: Identifiable {
    let id: String
}

private func items(_ n: Int) -> [Item] {
    (0..<n).map { Item(id: "item-\($0)") }
}

/// A minimal row: contributes one childless layout node and registers ITS OWN
/// `GlobalElementID` as a scroll region during prepaint. That registry is the
/// observable this file uses to recover a row's identity — the same technique
/// `DeferredTests` uses (a `ScrollView`'s registered region id), specialised
/// to register directly rather than through a full `ScrollView`, since a `Row`
/// needs no scrolling of its own.
private struct Row: Element {
    let item: Item
    /// When set, this row's own node asks for a fixed height — the "content
    /// taller than `rowHeight`" case the row-flooring tests need. `nil` keeps
    /// the original childless, zero-height node every other test in this file
    /// relies on.
    var contentHeight: Pixels?

    init(_ item: Item, contentHeight: Pixels? = nil) {
        self.item = item
        self.contentHeight = contentHeight
    }

    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        guard let contentHeight else {
            return (pass.requestNode(style: Style(), children: []), ())
        }
        // A LEAF whose measured content size is `contentHeight`, not a node
        // whose declared STYLE is — a declared `size.height` would set this
        // row's OWN box outright and bypass the automatic-minimum mechanism
        // the flooring tests exist to exercise. A leaf's reported content
        // size is what feeds `Box<Row>`'s content size suggestion instead.
        let h = Double(contentHeight.value)
        let node = pass.requestLeaf(style: Style()) { _, _ in SizeD(width: 0, height: h) }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        pass.registerScrollRegion(bounds, id: id, axis: .vertical)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Runs layout only — the idiom `ScrollViewTests.laidOut` and
/// `TextMeasureTests.laidOut` already use — and hands back the root node so a
/// caller can read its resolved bounds. `Frame.render` discards the root
/// `LayoutNodeID` it builds internally, so a test that needs the ROOT's own
/// bounds (rather than a descendant's, reachable through a registry) has no
/// other way back to it.
@MainActor
private func laidOut<E: Element>(_ element: inout E,
                                 width: Float = 400, height: Float = 600)
    -> (Frame, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (root, _) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                          pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame, root)
}

/// A row's `GlobalElementID`, recovered from `frame.scrollRegions` rather than
/// from any accessor `Frame` does not have. `data`'s declared order is known at
/// the call site, so the row named `name`'s expected `y` — `index * rowHeight`,
/// exactly the invariant a uniform `rowHeight` buys — locates its registered
/// region without reading any GlobalElementID directly.
@MainActor
private func idOfRow(named name: String, in data: [Item], rowHeight: Pixels,
                     frame: Frame) throws -> GlobalElementID {
    let index = try #require(data.firstIndex { $0.id == name })
    let expectedY = px(rowHeight.value * Float(index))
    let region = try #require(frame.scrollRegions.first { $0.bounds.origin.y == expectedY },
                              "no row registered at y == \(expectedY.value), the position '\(name)' should have under this list's declared order")
    return region.id
}

// 10 rows x 28 = 280, regardless of what any row measures.
@Test @MainActor func aListSizesItselfToCountTimesRowHeight() throws {
    var list = List(items(10), rowHeight: px(28)) { Row($0) }
    let (frame, root) = laidOut(&list)
    #expect(frame.bounds(of: root).size.height == px(280))
}

/// Identity comes from the DATA, not from position — the property windowing
/// depends on. A row that moves position keeps its state; under positional
/// identity it would adopt its new neighbour's.
@Test @MainActor func aRowKeepsItsIdentityWhenItsPositionChanges() throws {
    let dataA = items(3)
    var listA = List(dataA, rowHeight: px(28)) { Row($0) }
    let frameA = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frameA.render(&listA)

    let dataB = Array(items(3).reversed())
    var listB = List(dataB, rowHeight: px(28)) { Row($0) }
    let frameB = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frameB.render(&listB)

    let idA = try idOfRow(named: "item-0", in: dataA, rowHeight: px(28), frame: frameA)
    let idB = try idOfRow(named: "item-0", in: dataB, rowHeight: px(28), frame: frameB)
    #expect(idA == idB)
}

/// The automatic minimum's content half floors a row `Box` at its own
/// content's size (CLAUDE.md divergence 5) — measured at `contentHeight: 60`
/// against `rowHeight: 28` — UNLESS `minSize.height` is overridden to 0. Every
/// row still lands at `index * rowHeight` and keeps `rowHeight`'s own height,
/// with the taller content simply overflowing its row.
@Test @MainActor func aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent() throws {
    let data = items(3)
    var list = List(data, rowHeight: px(28)) { Row($0, contentHeight: px(60)) }
    let frame = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frame.render(&list)

    let regions = frame.scrollRegions
    try #require(regions.count == 3)
    let ys = regions.map(\.bounds.origin.y.value).sorted()
    #expect(ys == [0, 28, 56])
    for region in regions {
        #expect(region.bounds.size.height == px(28))
    }
}

/// A row's default `flexShrink: 1` would let padding on `List` itself shrink
/// its content box below `data.count * rowHeight` and pull every row down
/// with it — measured, that gives rows of 21/22/21 rather than three rows of
/// 28. `flexShrink = 0` on the row style is what this test guards: rows keep
/// `rowHeight` and overflow the padded content box instead of shrinking to
/// fit it.
@Test @MainActor func paddingOnAListDoesNotShrinkItsRowsBelowRowHeight() throws {
    let data = items(3)
    var list = List(data, rowHeight: px(28)) { Row($0) }.padding(px(10))
    let frame = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frame.render(&list)

    let regions = frame.scrollRegions
    try #require(regions.count == 3)
    let ys = regions.map(\.bounds.origin.y.value).sorted()
    #expect(ys == [10, 38, 66])
    for region in regions {
        #expect(region.bounds.size.height == px(28))
    }
}

/// Distinctness, not only stability — `aRowKeepsItsIdentityWhenItsPositionChanges`
/// only asserts that ONE row's id survives a reorder, which a mutation naming
/// every row the SAME constant string would also satisfy (every row would
/// then share one id, so any two "matches" trivially). This is the other
/// half: two DIFFERENT rows in the SAME list must get DIFFERENT ids.
@Test @MainActor func distinctRowsGetDistinctIdentities() throws {
    let data = items(3)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    let frame = Frame(contentSize: Size(width: px(400), height: px(600)), scaleFactor: 1)
    frame.render(&list)

    let idA = try idOfRow(named: "item-0", in: data, rowHeight: px(28), frame: frame)
    let idB = try idOfRow(named: "item-1", in: data, rowHeight: px(28), frame: frame)
    #expect(idA != idB)
}

// `List([])` — no rows, no trap, zero height. `data.count == 0` reaches
// `rowHeight * Float(0)` in `List.init` and an empty `data.map` in
// `requestLayout`; neither has a special case to fall through.
@Test @MainActor func anEmptyListHasZeroHeightAndTrapsNothing() throws {
    var list = List([Item](), rowHeight: px(28)) { Row($0) }
    let (frame, root) = laidOut(&list)
    #expect(frame.bounds(of: root).size.height == px(0))
    #expect(frame.scrollRegions.isEmpty)
}

/// `List` conforms to `StyledElement` for more than the type checker — a
/// modifier applied to it must reach the layout node `requestLayout` builds,
/// not sit inert the way CLAUDE.md's declared-but-inert table catalogues.
@Test @MainActor func aWidthModifierOnAListReachesItsLayoutNode() throws {
    var list = List(items(3), rowHeight: px(28)) { Row($0) }.width(px(123))
    let (frame, root) = laidOut(&list)
    #expect(frame.bounds(of: root).size.width == px(123))
}

/// Runs the full three-phase pipeline over `list` with `context` pushed onto
/// `frame`'s scroll-context stack before `requestLayout` runs — the same
/// value `ScrollView.requestLayout` would publish around a real `List` child,
/// reproduced directly so these tests do not need a real `ScrollView`,
/// `Window` or wheel event to control it. Popped again immediately after:
/// nothing here needs it during prepaint or paint, and leaving it pushed
/// would be a stray mutation on a `Frame` a caller might reuse.
@MainActor
private func renderWindowed<E: Element>(_ element: inout E, context: ScrollContext,
                                        frameHeight: Float = 600) -> (Frame, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: px(400), height: px(frameHeight)), scaleFactor: 1)
    frame.pushScrollContext(context)
    let rootID = GlobalElementID.child(of: nil, at: 0, name: element.elementID)
    var layoutPass = LayoutPass(frame: frame)
    let (root, layoutState) = element.requestLayout(rootID, pass: &layoutPass)
    frame.popScrollContext()
    var state = layoutState

    frame.computeRootLayout(root: root)
    let rootBounds = frame.bounds(of: root)

    var prepaintPass = PrepaintPass(frame: frame)
    var prepaintState = element.prepaint(rootID, bounds: rootBounds, layout: &state,
                                         pass: &prepaintPass)
    var paintPass = PaintPass(frame: frame)
    element.paint(rootID, bounds: rootBounds, layout: &state, prepaint: &prepaintState,
                 pass: &paintPass)
    return (frame, root)
}

/// The window is exact, not merely "at least the viewport": rows both inside
/// AND outside the widened window are checked, so a mutation that builds too
/// FEW rows (overscan removed) and one that builds too MANY (e.g. every row,
/// unconditionally) would each redden this test differently.
///
/// 40 rows at 28pt: offset 140 (row 5's top) and viewport 84 (3 rows) bound
/// rows 5..<8 exactly; widened by `overscan == 2` on each side that is
/// 3..<10 — rows 3 through 9.
@Test @MainActor func aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan() throws {
    let data = items(40)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 140, viewportExtent: 84, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((3...9).map { Float($0) * 28 })
    #expect(ys == expected, "expected rows 3 through 9 built, got y-offsets \(ys.sorted())")
}

/// The list's own height must stay count x rowHeight even though only a
/// window is built — otherwise the scrollbar and the offset clamp are wrong.
@Test @MainActor func aWindowedListStillReportsItsFullContentHeight() throws {
    let data = items(40)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 140, viewportExtent: 84, axis: .vertical)
    let (frame, root) = renderWindowed(&list, context: context)

    #expect(frame.scrollRegions.count < data.count, "the window must be a strict subset")
    #expect(frame.bounds(of: root).size.height == px(1120), "40 x 28, unaffected by windowing")
}

/// A row scrolled past keeps its position, so the window is placed rather
/// than merely sized: row 50 sits at 50 x rowHeight, not at the window's top.
@Test @MainActor func aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop() throws {
    let data = items(100)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    // Row 50's top is 50 x 28 = 1400; a 100pt viewport starting there keeps
    // it comfortably inside the window with room either side for overscan.
    let context = ScrollContext(offset: 1400, viewportExtent: 100, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context, frameHeight: 2000)

    // `try #require` above already establishes the position directly — a
    // separate `!= px(0)` check here could never fail once that has matched,
    // since 1400 and 0 cannot both be true of the same value.
    _ = try #require(frame.scrollRegions.first { $0.bounds.origin.y == px(1400) },
                     "row 50 must be registered at y == 1400, its absolute offset")
}

/// A zero `rowHeight` was legal, quiet input before windowing existed —
/// every row (and the list itself) simply measured zero. `rowExtent` is the
/// divisor in `visibleRange`'s arithmetic, so once a real scroll context is
/// present (this reproduces what a second frame looks like: the viewport has
/// already been measured), an unguarded `0 / 0` is `NaN` and `Int(NaN)`
/// traps — measured directly before the guard existed, with no summary line
/// from the surrounding suite. Declining to window at all is what keeps a
/// zero `rowHeight` as quiet as it always was.
@Test @MainActor func aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent() throws {
    let data = items(5)
    var list = List(data, rowHeight: px(0)) { Row($0) }
    let context = ScrollContext(offset: 0, viewportExtent: 100, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    #expect(frame.scrollRegions.count == 5, "a rowHeight nothing can be windowed against builds every row")
}

/// A present context whose `viewportExtent == 0` is exactly what a
/// `ScrollView`'s very first frame publishes (before its own `prepaint` has
/// measured a real viewport), and `List` must build every row on it rather
/// than windowing around whatever `offset` happens to be — the alternative is
/// a one-frame flash of only the rows near `offset` that survive overscan.
/// Removing the `viewportExtent > 0` guard leaves this arithmetic-correct but
/// wrong for that first frame: `offset == 0` and `viewportExtent == 0` bound
/// almost nothing, so only a handful of rows near the top would be built.
@Test @MainActor func aPresentContextWithZeroViewportExtentBuildsEveryRow() throws {
    let data = items(40)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 0, viewportExtent: 0, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    #expect(frame.scrollRegions.count == 40)
}

/// `ScrollContext.offset` is raw and unclamped by design (its own doc
/// comment) — events can accumulate between frames with no ceiling until a
/// `ScrollView`'s own `prepaint` next writes one back. `List` owns clamping
/// it against its own exact content extent before deriving a window; without
/// that clamp, an offset far past the end computes `first == last == count`
/// and the list renders NOTHING — the same shape as the clipping milestone's
/// dead-band defect, just at the opposite end of the same missing clamp.
@Test @MainActor func anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing() throws {
    let data = items(40)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    // 5000 is nowhere near 40 x 28 = 1120; clamped against `extent -
    // viewportExtent` = 1120 - 84 = 1036, which lands exactly on row 37's top.
    let context = ScrollContext(offset: 5000, viewportExtent: 84, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((35...39).map { Float($0) * 28 })
    #expect(ys == expected, "expected the clamped tail, rows 35 through 39, got \(ys.sorted())")
}

/// `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` pins the ROW pin but
/// cannot pin the SPACER's: with no scroll context its spacer is always
/// 0-height, and shrinking a 0-height item changes nothing observable. This
/// gives the spacer real height (a scrolled window) AND padding large enough
/// to force real negative free space, so an unpinned spacer would absorb the
/// deficit and pull every windowed row up from its true absolute offset.
@Test @MainActor func aScrolledListsSpacerDoesNotShrinkUnderPadding() throws {
    let data = items(10)
    var list = List(data, rowHeight: px(28)) { Row($0) }.padding(px(60))
    // window = 3..<9 (offset 140 / 28 = row 5, minus overscan 2 = row 3;
    // (140 + 56) / 28 = row 7, plus overscan 2 = row 9): spacer height is
    // exactly 3 x 28 = 84, and the padded content box (10 x 28 - 2 x 60 =
    // 160) is smaller than the spacer plus the six windowed rows
    // (84 + 6 x 28 = 252) — real negative free space, not a vacuous check.
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((3...8).map { 60 + Float($0) * 28 })
    #expect(ys == expected,
            "padding must not let the spacer shrink and pull windowed rows up; got \(ys.sorted())")
}

/// Every other windowing test uses an offset and a viewport extent that are
/// exact multiples of `rowHeight`, so `.rounded(.down)`/`.rounded(.up)` are
/// each a no-op there and swapping the two directions passes unnoticed. A
/// fractional offset forces both to matter: 150 / 28 = 5.357 must floor to
/// 5, and (150 + 90) / 28 = 8.571 must ceil to 9 — swapping either rounding
/// direction reads a different window under this fixture.
@Test @MainActor func aFractionalOffsetRoundsFirstDownAndLastUp() throws {
    let data = items(40)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 150, viewportExtent: 90, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((3...10).map { Float($0) * 28 })
    #expect(ys == expected, "expected rows 3 through 10, got \(ys.sorted())")
}

/// **The axis clause in `visibleRange`'s guard**, which was missing until the
/// whole-branch review measured it: `ScrollContext.axis` had no production
/// reader at all, so a vertical `List` inside a horizontal `ScrollView`
/// windowed itself against a HORIZONTAL offset and a viewport WIDTH.
///
/// Measured before the clause existed, on exactly this input: rows 6 through
/// 21 were built while rows 0 onward were the ones on screen. The right answer
/// is the one a `List` outside every scroller gets — a horizontal offset
/// selects no subset of a column of rows, so there is no window to compute.
///
/// **The differential is the second half**, without which this test would also
/// pass under a mutation that stopped windowing altogether: the identical list
/// under a `.vertical` context of the same numbers builds a strict subset.
@Test @MainActor func aVerticalListInsideAHorizontalScrollViewBuildsEveryRow() throws {
    let data = items(40)

    var horizontal = List(data, rowHeight: px(28)) { Row($0) }
    let (across, _) = renderWindowed(&horizontal,
                                     context: ScrollContext(offset: 240, viewportExtent: 300,
                                                            axis: .horizontal))
    #expect(across.scrollRegions.count == data.count,
            "a horizontal scroller says nothing about which rows of a vertical list are on screen")

    var vertical = List(data, rowHeight: px(28)) { Row($0) }
    let (down, _) = renderWindowed(&vertical,
                                   context: ScrollContext(offset: 240, viewportExtent: 300,
                                                          axis: .vertical))
    #expect(down.scrollRegions.count < data.count,
            "the same numbers on the axis this List stacks on DO window it")
}

/// **CLAUDE.md divergence 14, pinned so its fix arrives as a red test.**
///
/// `ScrollContext` describes the SCROLLER — how far the scroller's content has
/// moved under its viewport — and `visibleRange` reads it as though it
/// described this `List`, i.e. as though row 0 sat at the scroller's content
/// origin. A 300pt header above the list makes the two differ by exactly 300,
/// and the window slides off the rows actually on screen: at offset 300 with a
/// 112pt viewport the visible list-local band is 0...112, rows 0 through 3,
/// while the rows built are 8 through 16.
///
/// **This test asserts the WRONG answer on purpose**, which is why it names it
/// in its own message. Whoever gives `requestLayout` a position (or lays the
/// scroller out twice) must delete or invert it; a `List` that starts building
/// rows 0 through 5 here is correct, not regressed.
///
/// The consequence, measured through a real `ScrollView` rather than this
/// hand-pushed context: every one of those nine rows paints at y 224 through
/// 448 under a content mask of (0, 0) 100x112, so the list renders **blank**.
@Test @MainActor func aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows() throws {
    let data = items(40)
    var headerStyle = Style()
    headerStyle.size.height = .length(.pixels(px(300)))
    headerStyle.flexShrink = 0
    var columnStyle = Style()
    columnStyle.flexDirection = .column

    var tree = Box(style: columnStyle) {
        Box(style: headerStyle)
        List(data, rowHeight: px(28)) { Row($0) }
    }
    let (frame, _) = renderWindowed(&tree,
                                    context: ScrollContext(offset: 300, viewportExtent: 112,
                                                           axis: .vertical),
                                    frameHeight: 2000)

    // Row indices, recovered by subtracting the header the list sits below.
    let built = Set(frame.scrollRegions.map { Int(($0.bounds.origin.y.value - 300) / 28) })
    #expect(built == Set(8...16),
            "today's answer, and it is the wrong one: the rows visible at this offset are 0 through 3")
    #expect(built.isDisjoint(with: Set(0...5)),
            "not one visible row (0 through 3, plus overscan) is among them")
}

/// **`Deferred`'s layout-phase escape**, the half `pass.deferred` does not
/// cover: it resets the clip stack and the accumulated scroll translation for
/// prepaint and paint, and until the whole-branch review nothing reset the
/// ambient `LayoutPass.scrollContext`. A `List` inside a portal therefore
/// windowed against a scroller it does not move with — measured at offset 280:
/// the window slid to rows 8 through 15 while paint placed those rows at their
/// unscrolled positions, below the viewport, so the portal's list emptied out
/// as the list behind it scrolled.
///
/// **The differential is what makes this about `Deferred` rather than about
/// windowing**: the identical `List` under the identical context, unwrapped,
/// still windows.
@Test @MainActor func aListInsideADeferredIgnoresTheEscapedScrollersOffset() throws {
    let data = items(40)
    let context = ScrollContext(offset: 280, viewportExtent: 112, axis: .vertical)

    var portal = Deferred { List(data, rowHeight: px(28)) { Row($0) } }
    let (escaped, _) = renderWindowed(&portal, context: context)
    #expect(escaped.scrollRegions.count == data.count,
            "a subtree that escapes a scroller's clip and translation has escaped its windowing too")

    var plain = List(data, rowHeight: px(28)) { Row($0) }
    let (windowed, _) = renderWindowed(&plain, context: context)
    #expect(windowed.scrollRegions.count < data.count,
            "the same list and the same context, not wrapped, still windows")
}

// MARK: - Stage 4, lane 1 (`LR-BS`, `LR-BY`): the spacer, and the harness that
// could not window

/// **The windowing spacer is a bare legacy NODE, not a `Box` element**
/// (`LR-BS`, plan task 7 stage 4).
///
/// An element costs a `StateTable` entry it never reads: `Box.requestLayout`
/// calls `animated(_:_:for:pass:)`, which mints a `$anim` slot on first sight
/// of every registering element, unconditionally
/// (`AnimatedStyle.swift`) — so a spacer `Box` put one entry under
/// `child(of: listID, at: 0, name: nil)` on **every** `List`, on **every**
/// frame that built one. Under the proposal authority nothing will mint it
/// (the arrangement is a `ProposalLayout` over the rows, with no spacer at
/// all), so keeping the element would make the two authorities' `StateTable`
/// id sets differ for every `List` in the framework — which stage 1's §5.1
/// item 4 forbids and which `LayoutDifferential`'s `stateSlotsEqual` reports.
///
/// **Positional 0 is the exact slot to look at, and nothing else can land
/// there.** Every row carries `.id(String(describing: datum.id))`, so a row's
/// component is `.named`, never `.positional` — a name replaces a position
/// rather than joining it. So `child(of: listID, at: 0, name: nil)` addresses
/// the spacer and only the spacer, before and after this change.
///
/// The assertion walks the whole table rather than probing one id, because the
/// entry the spacer costs is not its own id but a `$anim` CHILD of it.
@Test @MainActor func theListsSpacerIsANodeNotAnElement() throws {
    let data = items(10)
    var list = List(data, rowHeight: px(28)) { Row($0) }
    // A scrolled window, so the spacer has real height (84pt) and is a real
    // participant rather than a zero-sized no-op.
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    let listID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let spacerID = GlobalElementID.child(of: listID, at: 0, name: nil)
    func descends(_ id: GlobalElementID, from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let current = cursor {
            if current == ancestor { return true }
            cursor = current.parent
        }
        return false
    }
    let spacerEntries = frame.stateTable.ids.filter { descends($0, from: spacerID) }

    // The window is real: rows 3..<9 of ten, so the spacer is 3 x 28 = 84 tall.
    try #require(frame.scrollRegions.count == 6,
                 "the fixture must actually window, or the spacer is 0-height and proves nothing")
    #expect(spacerEntries.isEmpty,
            "the spacer must cost no StateTable entry; got \(spacerEntries.map { "\($0)" }.sorted())")
    // And the rows around it still do cost one apiece, so the filter above is
    // looking at a table that holds entries at all.
    #expect(frame.stateTable.ids.count > 6)
}

/// **The differential harness can window a `List`, and before this lane it
/// could not** (`LR-BY`, critic round 1 defect D4).
///
/// `LayoutDifferential.render` used to build ONE frame with a fresh
/// `StateTable` of its own. `ScrollContext.viewportExtent` is one frame stale
/// by construction — only `ScrollChrome.resolvedOffset`'s `PrepaintPass`
/// overload ever writes it — so on frame 1 it is 0, `List.visibleRange` takes
/// its `context.viewportExtent > 0` guard and returns `0..<count`, and
/// `windowIsBounded` is false. Every `List` arm of every differential test was
/// therefore comparing an UNWINDOWED list, and its `accessibilityEqual` was
/// comparing one table record with one table record and passing vacuously —
/// "a harness that compares nothing agrees" (record §26 §2.4).
///
/// This is the anti-vacuity check itself, on the legacy authority alone: the
/// harness must reach a bounded window and a non-empty row-record set, or no
/// later lane's `List` arm means anything. Mutation **M1f** (`frames:` forced
/// back to 1) must redden it.
@Test @MainActor func aListInTheDifferentialHarnessReachesABoundedWindow() throws {
    let data = items(40)
    // The demo's own scroller shape, and it is load-bearing here: the harness
    // root is a `display: .stack` that offers its children fit-content, so a
    // bare `ScrollView` takes its content's full 1120pt as its viewport and
    // windows nothing. `flexGrow(1).flexBasis(0).minHeight(0)` inside a
    // container with a declared height is what bounds the viewport at 200 —
    // exactly what `DemoContent.swift`'s scroller `Box` writes, measured
    // against the two alternatives (a plain fixed-height `Box` around the
    // scroller, and a fixed-height `Box` with `minSize.height: 0` inside it),
    // which both read all 40 rows.
    var column = Style()
    column.flexDirection = .column
    column.size = Size(width: .length(.pixels(px(200))), height: .length(.pixels(px(200))))
    let frame = LayoutDifferential.render(authority: .legacy, width: 200, height: 200) {
        Box(style: column) {
            Box {
                ScrollView(.vertical) {
                    List(data, rowHeight: px(28)) { Row($0) }
                }
            }
            .flexGrow(1).flexBasis(px(0)).minHeight(px(0))
        }
    }

    let rows = frame.axEmissions.filter { $0.declared.logicalIndex != nil }
    let tables = frame.axEmissions.filter { $0.declared.logicalCount != nil }
    try #require(tables.count == 1, "exactly one AXTable record, the List's own")
    #expect(tables[0].declared.logicalCount == 40)
    // Bounded: fewer rows than the logical count, and not zero. An unbounded
    // window publishes the table and NO rows at all (`AB-X` rule 1), so both
    // halves are load-bearing.
    try #require(!rows.isEmpty, "an unbounded window publishes no rows — the harness never windowed")
    #expect(rows.count < data.count,
            "a bounded window realizes a slice; got all \(rows.count) of \(data.count)")
    // And the realized set is the window `visibleRange` computes for a 200pt
    // viewport over 28pt rows at offset 0: rows 0..<10, widened by overscan 2
    // on each side and clamped, so 0 through 9.
    #expect(rows.compactMap { $0.declared.logicalIndex }.sorted() == Array(0...9))
}

/// **The scene and the hitbox list are byte-for-byte what they were before the
/// spacer stopped being an element** (`LR-BS`).
///
/// A characterization test, green on both sides of the change, whose evidence
/// is its mutations rather than a red-before. Its literals were taken at
/// `f2e981f` — the commit this branch forked from — and the whole point of the
/// spacer's demotion is that they do not move: an empty `Decoration` emits
/// nothing and an empty `Handlers` registers nothing, so the element the
/// spacer was contributed a `StateTable` entry and a `Frame.elementBounds`
/// record and NOTHING else. If either literal moves, the demotion changed what
/// a `List` draws or what it can be clicked on, which is a finding and not a
/// number to update.
///
/// The fixture is deliberately a SCROLLED list with painted, clickable rows:
/// the spacer has real height (84pt), so a rect or a hitbox accidentally
/// emitted for it would land at a position nothing else occupies.
@Test @MainActor func aListsSceneAndHitboxesAreUnchangedByTheGroup() throws {
    let data = items(10)
    var list = List(data, rowHeight: px(28)) { _ in
        Box().background(.accent).onClick {}.width(px(100))
    }.width(px(120))
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(&list, context: context)

    func key(_ b: Bounds<Pixels>) -> String {
        "\(b.origin.x.value),\(b.origin.y.value) \(b.size.width.value)x\(b.size.height.value)"
    }
    let rects = frame.scene.rects.map {
        "\($0.bounds.origin.x),\($0.bounds.origin.y) \($0.bounds.size.width)x\($0.bounds.size.height)"
            + " a=\($0.background.a)"
    }
    let hitboxes = frame.hitboxes.map { "\(key($0.bounds))|\($0.layer)|\($0.opaque)" }

    // Taken at `f2e981f` by running this test with the two arrays printed. The
    // six windowed rows (3 through 8 of ten, a 140 offset over 28pt rows with
    // overscan 2) and nothing else: the spacer occupies y 0 through 84 and
    // emits no rect and registers no hitbox, before the change and after it.
    let expectedRects = ["0.0,84.0 100.0x28.0 a=1.0", "0.0,112.0 100.0x28.0 a=1.0",
                         "0.0,140.0 100.0x28.0 a=1.0", "0.0,168.0 100.0x28.0 a=1.0",
                         "0.0,196.0 100.0x28.0 a=1.0", "0.0,224.0 100.0x28.0 a=1.0"]
    let expectedHitboxes = ["0.0,84.0 100.0x28.0|0|true", "0.0,112.0 100.0x28.0|0|true",
                            "0.0,140.0 100.0x28.0|0|true", "0.0,168.0 100.0x28.0|0|true",
                            "0.0,196.0 100.0x28.0|0|true", "0.0,224.0 100.0x28.0|0|true"]
    #expect(rects == expectedRects, "\(rects)")
    #expect(hitboxes == expectedHitboxes, "\(hitboxes)")
}
