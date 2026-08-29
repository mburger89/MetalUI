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
/// FEW rows (overscan dropped) and one that builds too MANY (e.g. everything)
/// would each redden this differently — see the overscan mutation below.
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

    let region = try #require(frame.scrollRegions.first { $0.bounds.origin.y == px(1400) },
                              "row 50 must be registered at y == 1400, its absolute offset")
    #expect(region.bounds.origin.y != px(0),
            "a windowed row must not fall back to the window's own top")
}
