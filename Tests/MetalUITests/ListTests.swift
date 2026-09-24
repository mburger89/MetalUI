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
///
/// **Spelled through the legacy lowering** (`LR-BW`, stage 4 lane 3, prototype
/// P3; on both authorities until stage 9, which deleted the legacy branch and
/// moved the site from `.customElement`, deleted with it, to `.box`). It
/// registered `pass.requestNode` / `pass.requestLeaf` outright until stage 4,
/// which under `.proposal` hit `Frame.requestNode`'s backstop and **aborted the
/// run** — `aLegacySpelledListRowAbortsAProductionProposalFrame` kept that abort
/// as an observable until stage 9 retired it with the registrars (record §51,
/// lane 1 row 10).
///
/// **Not `ProbeLeaf`'s spelling** (`LayoutDifferential.swift`), which stage 3's
/// lane 3 used for its nine custom nodes: `ProbeLeaf` registers a **native leaf
/// directly**, so it records no `LoweredItem`, `planLegacyItems` cannot plan it
/// and no lowered container ever stretches it — measured at 7×3 against the
/// legacy engine's 7×10 (record §27 §2.2, P1a2). Two tests here read a row's own
/// **height**, so a row needs the lowered spelling. Mutation **M3b** makes the
/// proposal branch a bare `requestNativeLeaf` and must redden
/// `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent`.
///
/// **How many registrations this is, counted rather than carried over.** §4.2's
/// census read 224 nodes and 3 leaves at `f2e981f`. At this HEAD, with every
/// scenario parameterised, one unfiltered run makes **289 legacy nodes, 3 legacy
/// leaves, 241 proposal nodes and 3 proposal leaves** (measured with a temporary
/// counter, reverted). Both deltas are attributable and neither is a surprise:
/// 289 − 224 = 65 is lane 1's four additions (`theListsSpacerIsANodeNotAnElement`
/// 6, `aListInTheDifferentialHarnessReachesABoundedWindow` 40 + 10 over its two
/// frames, and the `Style.padding` arm added to each of the two padding tests,
/// 3 + 6); 289 − 241 = 48 is exactly
/// `aListInsideADeferredIgnoresTheEscapedScrollersOffset`, the one scenario that
/// stayed legacy-only (40 escaped rows plus its 8-row windowed control). **Stage
/// 5's lane 2 parameterised it** (`LR-CN`), so it now registers under the proposal
/// authority too; these counts were taken before that and were not re-taken.
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
            // A childless node. `lowerLegacyNode` over no children forwards to
            // `lowerLegacyLeaf` over a 0×0 native leaf all by itself, which is
            // the lowering of a childless `Box` — so the two branches describe
            // the same box on both authorities.
            return (pass.lowerLegacyNode(Style(), declared: Style(), children: [],
                                         site: .box), ())
        }
        // A LEAF whose measured content size is `contentHeight`, not a node
        // whose declared STYLE is — a declared `size.height` would set this
        // row's OWN box outright and bypass the automatic-minimum mechanism
        // the flooring tests exist to exercise. A leaf's reported content
        // size is what feeds `Box<Row>`'s content size suggestion instead.
        let h = Double(contentHeight.value)
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { _ in
                LayoutMeasurement(size: SizeD(width: 0, height: h))
            }
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {
        pass.registerScrollRegion(bounds, id: id, axis: .vertical)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

// MARK: - The host shape, and the three helpers that build it (`LR-BY`)

/// **Every fixture in this file is laid out INSIDE a fixed-size `Box`, and that
/// is what makes the proposal arms readable at all** (stage 4 lane 3, `LR-BY`;
/// prototype P1a6's shape).
///
/// The three helpers below used to make the subject the frame's **root**. A
/// native root is stored at the full window — ruling `SA-G`'s
/// `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`, which
/// `Frame.computeRootLayout` implements by discarding the root's own
/// measurement — so `aListSizesItselfToCountTimesRowHeight` would read 600
/// instead of 280 under `.proposal` and every bounds assertion in the file would
/// be measuring the window.
///
/// Declared **width** so the column's cross axis is definite (P1a6's shape);
/// declared **height** so the subject is never a flex item with negative free
/// space to absorb — a list taller than the host would shrink under the legacy
/// engine and not under the kernel, a disagreement the HARNESS would have
/// introduced. The width is the frame's own, so every rect in this file reads
/// exactly what it read when the subject was the root and took the window's
/// full width.
@MainActor
private func hostStyle(width: Float, height: Float) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size = Size(width: .length(.pixels(px(width))),
                      height: .length(.pixels(px(height))))
    return style
}

private let hostID = GlobalElementID.child(of: nil, at: 0, name: nil)

/// The subject's own id inside the host: the host's single group member, at
/// cursor 0 under whatever name it declares (every subject here declares none).
private func subjectID(named name: ElementID?) -> GlobalElementID {
    GlobalElementID.child(of: hostID, at: 0, name: name)
}

/// Runs layout **and prepaint** over `element` inside the host box, and hands
/// back the element's own resolved bounds.
///
/// **Three changes from the "run layout only" idiom `ScrollViewTests.laidOut`
/// and `TextMeasureTests.laidOut` use**, all three forced by reading a
/// non-root's bounds (`LR-BY`; neither of those two files changes):
///
/// - the host box above, so the subject is not the root;
/// - `recordsElementBounds: true` — `Frame.elementBounds` is written only when
///   it is set, and `Frame(contentSize:scaleFactor:)` defaults it to `false`.
///   Mutation **M3c** drops it back and must redden the three tests that read a
///   bounds out of this helper — **and it reddened two**, which is why the
///   return is an `Optional` a caller `try #require`s rather than a
///   zero-substituting `??`. With the substitution,
///   `anEmptyListHasZeroHeightAndTrapsNothing` asserted 0 against a 0 the
///   mutation itself produced and stayed green: a pin that could not see its
///   own subject. Measured, then fixed, then M3c re-run (record §27 §8.4);
/// - a **prepaint pass**: `elementBounds` is written by `Element.prepaintGroup`,
///   which is prepaint-time, so a layout-only helper records nothing. That is a
///   behaviour change for every test using this helper — hitboxes, scroll
///   regions, focus entries and accessibility records all register in prepaint —
///   and the full unfiltered suite was run after it (record §27 §8).
@MainActor
private func laidOut<E: Element>(_ element: E,
                                 width: Float = 400, height: Float = 600)
    -> (Frame, Bounds<Pixels>?) {
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)),
                      scaleFactor: 1,
                      recordsElementBounds: true)
    let subject = subjectID(named: element.elementID)
    var host = Box(style: hostStyle(width: width, height: height), content: element)
    var pass = LayoutPass(frame: frame)
    let (root, layout) = host.requestLayout(hostID, pass: &pass)
    frame.computeRootLayout(root: root)
    var state = layout
    var prepaintPass = PrepaintPass(frame: frame)
    _ = host.prepaint(hostID, bounds: frame.bounds(of: root), layout: &state, pass: &prepaintPass)
    return (frame, frame.elementBounds[subject])
}

/// The full three-phase pipeline over `element` inside the host box, with no
/// scroll context — the shape the four identity and row-flooring tests need,
/// which read `frame.scrollRegions` rather than any bounds.
///
/// `Frame.render` would do this, but it makes its argument the root; this is
/// `Frame.render`'s body over the host instead.
@MainActor
private func renderedInHost<E: Element>(_ element: E,
                                        width: Float = 400, height: Float = 600) -> Frame {
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)),
                      scaleFactor: 1,
                      recordsElementBounds: true)
    var host = Box(style: hostStyle(width: width, height: height), content: element)
    frame.render(&host)
    return frame
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
@Test @MainActor
func aListSizesItselfToCountTimesRowHeight() throws {
    let list = List(items(10), rowHeight: px(28)) { Row($0) }
    let (_, listBounds) = laidOut(list)
    #expect(try #require(listBounds).size.height == px(280))
}

/// Identity comes from the DATA, not from position — the property windowing
/// depends on. A row that moves position keeps its state; under positional
/// identity it would adopt its new neighbour's.
@Test @MainActor
func aRowKeepsItsIdentityWhenItsPositionChanges() throws {
    let dataA = items(3)
    let frameA = renderedInHost(List(dataA, rowHeight: px(28)) { Row($0) })

    let dataB = Array(items(3).reversed())
    let frameB = renderedInHost(List(dataB, rowHeight: px(28)) { Row($0) })

    let idA = try idOfRow(named: "item-0", in: dataA, rowHeight: px(28), frame: frameA)
    let idB = try idOfRow(named: "item-0", in: dataB, rowHeight: px(28), frame: frameB)
    #expect(idA == idB)
}

/// The automatic minimum's content half floors a row `Box` at its own
/// content's size (CLAUDE.md divergence 5) — measured at `contentHeight: 60`
/// against `rowHeight: 28` — UNLESS `minSize.height` is overridden to 0. Every
/// row still lands at `index * rowHeight` and keeps `rowHeight`'s own height,
/// with the taller content simply overflowing its row.
@Test @MainActor
func aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent() throws {
    let data = items(3)
    let frame = renderedInHost(List(data, rowHeight: px(28)) { Row($0, contentHeight: px(60)) })

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
@Test @MainActor
func paddingOnAListDoesNotShrinkItsRowsBelowRowHeight() throws {
    let data = items(3)
    let frame = renderedInHost(List(data, rowHeight: px(28)) { Row($0) }.padding(px(10)))

    let regions = frame.scrollRegions
    try #require(regions.count == 3)
    let ys = regions.map(\.bounds.origin.y.value).sorted()
    #expect(ys == [10, 38, 66])
    for region in regions {
        #expect(region.bounds.size.height == px(28))
    }

    // **The arm above cannot see `rowStyle.flexShrink = 0` any more, and this
    // one can** — the same instrument defect
    // `aScrolledListsSpacerDoesNotShrinkUnderPadding` carries, found by the
    // same mutation round (stage 4 lane 1, `LR-CC`). `.padding(_:)` became a
    // WRAPPER at `f1944f8`, so the 10pt lands on an outer `ModifiedElement`
    // layer and the `List`'s own content box keeps its full `3 x 28`: there is
    // no negative free space for a row to absorb. Measured at `f2e981f`, before
    // this lane touched anything — deleting `rowStyle.flexShrink = 0` left the
    // whole 1580-test suite green.
    //
    // `Style.padding` written directly still shrinks the `List`'s own content
    // box (CLAUDE.md's declared-but-inert table draws exactly this
    // distinction), which is what the doc comment above describes: 3 x 28 - 2 x
    // 10 = 64 against three rows of 28, so without the pin the rows read
    // 21/22/21 and slide up.
    var padded = List(data, rowHeight: px(28)) { Row($0) }
    padded.style.padding = Edges(all: .pixels(px(10)))
    let paddedFrame = renderedInHost(padded)
    let paddedRegions = paddedFrame.scrollRegions
    try #require(paddedRegions.count == 3)
    #expect(paddedRegions.map(\.bounds.origin.y.value).sorted() == [10, 38, 66])
    for region in paddedRegions {
        #expect(region.bounds.size.height == px(28))
    }
}

/// Distinctness, not only stability — `aRowKeepsItsIdentityWhenItsPositionChanges`
/// only asserts that ONE row's id survives a reorder, which a mutation naming
/// every row the SAME constant string would also satisfy (every row would
/// then share one id, so any two "matches" trivially). This is the other
/// half: two DIFFERENT rows in the SAME list must get DIFFERENT ids.
@Test @MainActor
func distinctRowsGetDistinctIdentities() throws {
    let data = items(3)
    let frame = renderedInHost(List(data, rowHeight: px(28)) { Row($0) })

    let idA = try idOfRow(named: "item-0", in: data, rowHeight: px(28), frame: frame)
    let idB = try idOfRow(named: "item-1", in: data, rowHeight: px(28), frame: frame)
    #expect(idA != idB)
}

// `List([])` — no rows, no trap, zero height. `data.count == 0` reaches
// `rowHeight * Float(0)` in `List.init` and an empty `data.map` in
// `requestLayout`; neither has a special case to fall through.
@Test @MainActor
func anEmptyListHasZeroHeightAndTrapsNothing() throws {
    let list = List([Item](), rowHeight: px(28)) { Row($0) }
    let (frame, listBounds) = laidOut(list)
    // `try #require`, not `listBounds?.size.height == px(0)`: an unrecorded
    // bounds and a 0pt one are the same answer to `??`, so the substituting
    // spelling could not see mutation M3c at all (record §27 §8.4).
    #expect(try #require(listBounds).size.height == px(0))
    #expect(frame.scrollRegions.isEmpty)
}

/// `List` conforms to `StyledElement` for more than the type checker — a
/// modifier applied to it must reach the layout node `requestLayout` builds,
/// not sit inert the way CLAUDE.md's declared-but-inert table catalogues.
@Test @MainActor
func aWidthModifierOnAListReachesItsLayoutNode() throws {
    let list = List(items(3), rowHeight: px(28)) { Row($0) }.cssWidth(px(123))
    let (_, listBounds) = laidOut(list)
    #expect(try #require(listBounds).size.width == px(123))
}

/// Runs the full three-phase pipeline over `element` **inside the host box**,
/// with `context` pushed onto `frame`'s scroll-context stack before
/// `requestLayout` runs — the same value `ScrollView.requestLayout` would
/// publish around a real `List` child, reproduced directly so these tests do
/// not need a real `ScrollView`, `Window` or wheel event to control it. Popped
/// again immediately after: nothing here needs it during prepaint or paint, and
/// leaving it pushed would be a stray mutation on a `Frame` a caller might
/// reuse.
///
/// The host box and `recordsElementBounds: true` arrive for the reason
/// `laidOut`'s do (`LR-BY`); this helper already prepainted, so it needs no
/// third change. It returns the subject's own bounds, which one test reads.
@MainActor
private func renderWindowed<E: Element>(_ element: E, context: ScrollContext,
                                        frameHeight: Float = 600)
    -> (Frame, Bounds<Pixels>?) {
    let frame = Frame(contentSize: Size(width: px(400), height: px(frameHeight)),
                      scaleFactor: 1,
                      recordsElementBounds: true)
    let subject = subjectID(named: element.elementID)
    var host = Box(style: hostStyle(width: 400, height: frameHeight), content: element)
    frame.pushScrollContext(context)
    var layoutPass = LayoutPass(frame: frame)
    let (root, layoutState) = host.requestLayout(hostID, pass: &layoutPass)
    frame.popScrollContext()
    var state = layoutState

    frame.computeRootLayout(root: root)
    let rootBounds = frame.bounds(of: root)

    var prepaintPass = PrepaintPass(frame: frame)
    var prepaintState = host.prepaint(hostID, bounds: rootBounds, layout: &state,
                                      pass: &prepaintPass)
    var paintPass = PaintPass(frame: frame)
    host.paint(hostID, bounds: rootBounds, layout: &state, prepaint: &prepaintState,
               pass: &paintPass)
    return (frame, frame.elementBounds[subject])
}

/// The window is exact, not merely "at least the viewport": rows both inside
/// AND outside the widened window are checked, so a mutation that builds too
/// FEW rows (overscan removed) and one that builds too MANY (e.g. every row,
/// unconditionally) would each redden this test differently.
///
/// 40 rows at 28pt: offset 140 (row 5's top) and viewport 84 (3 rows) bound
/// rows 5..<8 exactly; widened by `overscan == 2` on each side that is
/// 3..<10 — rows 3 through 9.
@Test @MainActor
func aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan() throws {
    let data = items(40)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 140, viewportExtent: 84, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((3...9).map { Float($0) * 28 })
    #expect(ys == expected, "expected rows 3 through 9 built, got y-offsets \(ys.sorted())")
}

/// The list's own height must stay count x rowHeight even though only a
/// window is built — otherwise the scrollbar and the offset clamp are wrong.
@Test @MainActor
func aWindowedListStillReportsItsFullContentHeight() throws {
    let data = items(40)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 140, viewportExtent: 84, axis: .vertical)
    // The host box declares the frame's own height, so a 1120pt list inside a
    // 600pt host would be a flex item with 520pt of negative free space under
    // the legacy engine and no such thing under the kernel — a disagreement the
    // HARNESS would have introduced. 1200 is the smallest round number above
    // 1120 (`LR-BY`).
    let (frame, listBounds) = renderWindowed(list, context: context,
                                             frameHeight: 1200)

    #expect(frame.scrollRegions.count < data.count, "the window must be a strict subset")
    #expect(try #require(listBounds).size.height == px(1120), "40 x 28, unaffected by windowing")
}

/// A row scrolled past keeps its position, so the window is placed rather
/// than merely sized: row 50 sits at 50 x rowHeight, not at the window's top.
@Test @MainActor
func aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop() throws {
    let data = items(100)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    // Row 50's top is 50 x 28 = 1400; a 100pt viewport starting there keeps
    // it comfortably inside the window with room either side for overscan.
    let context = ScrollContext(offset: 1400, viewportExtent: 100, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context, frameHeight: 2000)

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
@Test @MainActor
func aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent() throws {
    let data = items(5)
    let list = List(data, rowHeight: px(0)) { Row($0) }
    let context = ScrollContext(offset: 0, viewportExtent: 100, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

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
@Test @MainActor
func aPresentContextWithZeroViewportExtentBuildsEveryRow() throws {
    let data = items(40)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 0, viewportExtent: 0, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

    #expect(frame.scrollRegions.count == 40)
}

/// `ScrollContext.offset` is raw and unclamped by design (its own doc
/// comment) — events can accumulate between frames with no ceiling until a
/// `ScrollView`'s own `prepaint` next writes one back. `List` owns clamping
/// it against its own exact content extent before deriving a window; without
/// that clamp, an offset far past the end computes `first == last == count`
/// and the list renders NOTHING — the same shape as the clipping milestone's
/// dead-band defect, just at the opposite end of the same missing clamp.
@Test @MainActor
func anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing() throws {
    let data = items(40)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    // 5000 is nowhere near 40 x 28 = 1120; clamped against `extent -
    // viewportExtent` = 1120 - 84 = 1036, which lands exactly on row 37's top.
    let context = ScrollContext(offset: 5000, viewportExtent: 84, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

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
@Test @MainActor
func aScrolledListsSpacerDoesNotShrinkUnderPadding() throws {
    let data = items(10)
    let list = List(data, rowHeight: px(28)) { Row($0) }.padding(px(60))
    // window = 3..<9 (offset 140 / 28 = row 5, minus overscan 2 = row 3;
    // (140 + 56) / 28 = row 7, plus overscan 2 = row 9): spacer height is
    // exactly 3 x 28 = 84, and the padded content box (10 x 28 - 2 x 60 =
    // 160) is smaller than the spacer plus the six windowed rows
    // (84 + 6 x 28 = 252) — real negative free space, not a vacuous check.
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

    let ys = Set(frame.scrollRegions.map(\.bounds.origin.y.value))
    let expected = Set((3...8).map { 60 + Float($0) * 28 })
    #expect(ys == expected,
            "padding must not let the spacer shrink and pull windowed rows up; got \(ys.sorted())")

    // **The arm above cannot see its own subject any more, and this one can.**
    // `.padding(_:)` stopped shrinking the receiver's content box at `f1944f8`
    // (CLAUDE.md's identity bullet: the modifier adds an outer `ModifiedElement`
    // LAYER, and the padding lands on the layer rather than on the `List`), so
    // the fixture above has no negative free space left to distribute and the
    // spacer has nothing to absorb. Measured at `f2e981f`, before this lane
    // touched anything: deleting `spacerStyle.flexShrink = 0` leaves the arm
    // above green, and deleting `rowStyle.flexShrink = 0` leaves the **whole
    // 1580-test suite** green. Both lines were unpinned.
    //
    // `Style.padding` written directly is the spelling that still shrinks the
    // `List`'s own content box (CLAUDE.md's declared-but-inert table draws
    // exactly this distinction), so this arm restores the negative free space
    // the first arm used to create: content box 10 x 28 - 2 x 60 = 160 against
    // a spacer of 84 plus six rows of 28 = 252, a deficit of 92. With the
    // spacer's pin removed it shrinks to 0 and every row rises by 84.
    var padded = List(data, rowHeight: px(28)) { Row($0) }
    padded.style.padding = Edges(all: .pixels(px(60)))
    let (paddedFrame, _) = renderWindowed(padded, context: context)
    let paddedYs = Set(paddedFrame.scrollRegions.map(\.bounds.origin.y.value))
    #expect(paddedYs == expected,
            "the spacer must not absorb a padded List's deficit; got \(paddedYs.sorted())")
}

/// Every other windowing test uses an offset and a viewport extent that are
/// exact multiples of `rowHeight`, so `.rounded(.down)`/`.rounded(.up)` are
/// each a no-op there and swapping the two directions passes unnoticed. A
/// fractional offset forces both to matter: 150 / 28 = 5.357 must floor to
/// 5, and (150 + 90) / 28 = 8.571 must ceil to 9 — swapping either rounding
/// direction reads a different window under this fixture.
@Test @MainActor
func aFractionalOffsetRoundsFirstDownAndLastUp() throws {
    let data = items(40)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    let context = ScrollContext(offset: 150, viewportExtent: 90, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

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
@Test @MainActor
func aVerticalListInsideAHorizontalScrollViewBuildsEveryRow() throws {
    let data = items(40)

    let horizontal = List(data, rowHeight: px(28)) { Row($0) }
    let (across, _) = renderWindowed(horizontal,
                                     context: ScrollContext(offset: 240, viewportExtent: 300,
                                                            axis: .horizontal))
    #expect(across.scrollRegions.count == data.count,
            "a horizontal scroller says nothing about which rows of a vertical list are on screen")

    let vertical = List(data, rowHeight: px(28)) { Row($0) }
    let (down, _) = renderWindowed(vertical,
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
///
/// **Pinned on BOTH layout authorities since stage 4 lane 3** (`LR-CE`; the
/// design assigned this row to lane 4 and lane 3 parameterised the whole file
/// at once). The divergence is `visibleRange`'s, which is authority-blind, so
/// the lowering neither fixes it nor makes it worse — and that is the claim the
/// second arm makes.
@Test @MainActor
func aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows() throws {
    let data = items(40)
    var headerStyle = Style()
    headerStyle.size.height = .length(.pixels(px(300)))
    headerStyle.flexShrink = 0
    var columnStyle = Style()
    columnStyle.flexDirection = .column

    let tree = Box(style: columnStyle) {
        Box(style: headerStyle)
        List(data, rowHeight: px(28)) { Row($0) }
    }
    let (frame, _) = renderWindowed(tree,
                                    context: ScrollContext(offset: 300, viewportExtent: 112,
                                                           axis: .vertical), frameHeight: 2000)

    // Row indices, recovered by subtracting the header the list sits below.
    let built = Set(frame.scrollRegions.map { Int(($0.bounds.origin.y.value - 300) / 28) })
    #expect(built == Set(8...16),
            "today's answer on both authorities, and it is the wrong one: the rows visible at this offset are 0 through 3")
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
///
/// **Under both authorities since stage 5's lane 2** (`LR-CN`), with **no
/// red-before**: record §27 §8.2 said this scenario "aborts" the run under
/// `.proposal`; measured at `e5caefb` it passes there (record §29 §2.3 — the
/// `Deferred` is in-flow, so it lowers as it always has, and
/// `withoutScrollContext` runs on both authorities). The claim was never
/// measured. Its pin under the proposal arm is mutation M2e
/// (`withoutScrollContext` removed from `Deferred.requestLayout`).
@Test @MainActor
func aListInsideADeferredIgnoresTheEscapedScrollersOffset() throws {
    let data = items(40)
    let context = ScrollContext(offset: 280, viewportExtent: 112, axis: .vertical)

    let portal = Deferred { List(data, rowHeight: px(28)) { Row($0) } }
    let (escaped, _) = renderWindowed(portal, context: context)
    #expect(escaped.scrollRegions.count == data.count,
            "a subtree that escapes a scroller's clip and translation has escaped its windowing too")

    let plain = List(data, rowHeight: px(28)) { Row($0) }
    let (windowed, _) = renderWindowed(plain, context: context)
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
@Test @MainActor
func theListsSpacerIsANodeNotAnElement() throws {
    let data = items(10)
    let list = List(data, rowHeight: px(28)) { Row($0) }
    // A scrolled window, so the spacer has real height (84pt) and is a real
    // participant rather than a zero-sized no-op.
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

    // The `List` is the host box's single member, not the frame's root, since
    // stage 4 lane 3 (`LR-BY`) — so its own id is `subjectID(named: nil)`.
    let spacerID = GlobalElementID.child(of: subjectID(named: nil), at: 0, name: nil)
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
/// "a harness that compares nothing agrees" (record §27 §2.4).
///
/// This is the anti-vacuity check itself: the harness must reach a bounded
/// window and a non-empty row-record set, or no later lane's `List` arm means
/// anything. Mutation **M1f** (`frames:` forced back to 1) must redden it.
///
/// **Lane 1 ran it on the legacy authority alone and stage 4's lane 3
/// parameterised it** (`LR-BW`); stage 9 collapsed it to the one authority.
@Test @MainActor
func aListInTheDifferentialHarnessReachesABoundedWindow() throws {
    let data = items(40)
    let table = StateTable()
    // The demo's own scroller shape, and it was load-bearing here until stage
    // 9: the legacy harness root was a `display: .stack` that offered its
    // children fit-content, so a bare `ScrollView` took its content's full
    // 1120pt as its viewport and windowed nothing. `flexGrow(1).flexBasis(0).minHeight(0)` inside a
    // container with a declared height is what bounds the viewport at 200 —
    // exactly what `DemoContent.swift`'s scroller `Box` writes, measured
    // against the two alternatives (a plain fixed-height `Box` around the
    // scroller, and a fixed-height `Box` with `minSize.height: 0` inside it),
    // which both read all 40 rows.
    var column = Style()
    column.flexDirection = .column
    column.size = Size(width: .length(.pixels(px(200))), height: .length(.pixels(px(200))))
    let frame = LayoutDifferential.render(width: 200, height: 200,
                                          stateTable: table, frames: 2) {
        Box(style: column) {
            Box {
                ScrollView(.vertical) {
                    List(data, rowHeight: px(28)) { Row($0) }
                }
            }
            .flexGrow(1).flexBasis(px(0)).cssMinHeight(px(0))
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
@Test @MainActor
func aListsSceneAndHitboxesAreUnchangedByTheGroup() throws {
    let data = items(10)
    let list = List(data, rowHeight: px(28)) { _ in
        Box().background(.accent).onClick {}.cssWidth(px(100))
    }.cssWidth(px(120))
    let context = ScrollContext(offset: 140, viewportExtent: 56, axis: .vertical)
    let (frame, _) = renderWindowed(list, context: context)

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

// MARK: - Stage 4, lane 3 (`LR-BW`, `LR-BX`): the red-before — retired at stage 9

// `aLegacySpelledListRowAbortsAProductionProposalFrame` and its fixture
// `LegacySpelledRow` kept stage 4's red-before as an observable: a row spelled
// with the public `requestNode`/`requestLeaf` aborted a production frame on the
// `customElement` trap. Lane 3 deletes the registrars and the site, so the row
// can no longer be spelled; the re-spelled plain-import guard G6a
// (`aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles`) is what now stops
// a future edit putting `pass.requestNode` back (record §51, lane 1 row 10, R).
