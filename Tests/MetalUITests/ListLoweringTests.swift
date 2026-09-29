import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 4 of the engine replacement — **lane 2**, the windowed
// proposal `List`.
// Design: `docs/superpowers/specs/2026-09-23-engine-stage-4-design.md` §6 lane 2
// (rulings `LR-BQ`, `LR-BR`, `LR-CA`).
//
// Under the proposal authority `List.requestLayout` stops reporting
// `list.noLowering` and stops building a zero-row `Box`. `ListRows` registers
// the realized rows under the same ids, consumes their `LoweredItem` records,
// plans and registers their item wrappers with `planLegacyItems` /
// `registerLegacyItems` at `parentSite: .list`, and returns ONE node — a
// `WindowedRowsLayout` over the wrapped rows, which places row *i* at
// `(firstIndex + i) × rowHeight` and answers the list's FULL content extent on
// the stacking axis. There is no leading spacer on this path: the layout places
// each realized row at its absolute offset directly.
//
// **Four of the nine tests here are red by failure at lane 1's HEAD** — 2.1,
// 2.5, 2.7 and 2.8, each rendering a `List` under the proposal authority with
// diagnostics on, so the report carries `list.noLowering` and the proposal side
// builds no rows at all. The other five (2.2, 2.3, 2.4, 2.4b, 2.6) read
// `WindowedRowsLayout`'s own answer, so they do not COMPILE at lane 1's HEAD
// and cannot be a red-before (`LR-BX`); they arrive with their subject and
// their evidence is the lane's mutations, named in the commit message.
//
// **Stage 9** (record §51, lane 1; ruling `LR-FE`): the legacy authority is
// deleted, so each test renders one side, keeps its literals (lane 1's legacy
// oracle values, which the lowered side equalled), loses its agreement checks,
// and gains a literal where only the agreement carried a named observation (2.1's
// B4, 2.8's identity).

private func lpx(_ v: Float) -> Pixels { Pixels(v) }

private struct LItem: Identifiable, Equatable {
    let id: String
}

private func lItems(_ n: Int) -> [LItem] {
    (0..<n).map { LItem(id: "item-\($0)") }
}

private func lBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let lRoot = GlobalElementID.child(of: nil, at: 0, name: nil)

private func lChild(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func lNamed(_ parent: GlobalElementID, _ name: String) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: 0, name: ElementID(name))
}

/// A `column` style of the given width — P1a6's host shape (record §27 §2.2):
/// a declared cross size on the container is what removes `DifferentialRoot`'s
/// own divergence 53 from every arm below, so what the arms measure is the
/// `List` and not the harness root.
private func lColumn(width: Float) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size.width = .length(.pixels(lpx(width)))
    return style
}

/// A fixed-size leaf spelled **through the lowering** — P3's re-spelling (`LR-BW`,
/// record §27 §2.5), not `ProbeLeaf`'s. (It registered a legacy leaf under the
/// legacy authority until stage 9; its site moved from `.customElement`, which
/// lane 3 deletes, to `.box`, which reports nothing for a default style either.)
///
/// The difference is the whole of `LR-BW`: `ProbeLeaf` registers a native leaf
/// **directly** under the proposal authority, so it records no `LoweredItem`,
/// `planLegacyItems` cannot plan it and no lowered container ever stretches it
/// — measured at 7×3 against the legacy engine's 7×10 (record §27 §2.2, P1a2).
/// A `List` row's content has to be stretched by its row `Box` exactly as the
/// legacy engine stretches it, so a row fixture here goes through
/// `lowerLegacyLeaf`.
@MainActor
private struct LoweredProbeLeaf: Element {
    var width: Float
    var height: Float

    mutating func requestLayout(_ id: GlobalElementID,
                                pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let w = Double(width), h = Double(height)
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Nothing was reported. (Until stage 9 this was `lExpectAgreement`, which also
/// required every observation to agree with the legacy engine's; that comparison
/// is the deleted concept, `LR-FE` item 2.)
@MainActor
private func lExpectNothingReported(_ r: LayoutDifferential.Report, _ arm: String,
                                    sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
}

/// One arm rendered over its own `StateTable` seeded with `offset` at
/// `scrollerID`, over `frames` frames. (Until stage 9 it rendered both sides,
/// each over its own table, and compared them.)
///
/// **Two frames is not a detail** (`LR-BY`): `ScrollContext.viewportExtent` is
/// written only by `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload, so
/// on frame 1 it is 0 and `List.visibleRange` declines to window. Frame 2 is
/// the first frame with a bounded window.
@MainActor
private func lSeeded<Content: ElementGroup>(
    width: Float, height: Float, frames: Int, offset: Double,
    scrollerID: GlobalElementID,
    @ElementBuilder _ make: @MainActor () -> Content
) -> (report: LayoutDifferential.Report, lowered: Frame) {
    let table = StateTable()
    table.withState(scrollerID, initial: ScrollState()) { $0.offset = offset }
    let lowered = LayoutDifferential.render(width: width, height: height,
                                            stateTable: table, frames: frames, make)
    return (LayoutDifferential.report(lowered), lowered)
}

/// The realized rows' logical indices, from the accessibility records a bounded
/// window publishes (`AB-L`, `AB-X` rule 1: an unbounded window publishes the
/// table and no rows at all, so a non-empty set is itself the boundedness
/// check).
@MainActor
private func lRealizedIndices(_ frame: Frame) -> [Int] {
    frame.axEmissions.compactMap { $0.declared.logicalIndex }.sorted()
}

/// The anti-vacuity check every windowed arm owes before it asserts anything
/// (`LR-BY`): a bounded window and a **non-empty** row-record set (on both sides
/// until stage 9), and a window that is a strict subset of the logical count.
@MainActor
private func lRequireBoundedWindow(_ lowered: Frame, count: Int, _ arm: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
    for (name, frame) in [("lowered", lowered)] {
        let tables = frame.axEmissions.filter { $0.declared.logicalCount != nil }
        try #require(tables.count == 1, "\(arm) \(name): exactly one AXTable record",
                     sourceLocation: sourceLocation)
        try #require(tables[0].declared.logicalCount == count, "\(arm) \(name): logical count",
                     sourceLocation: sourceLocation)
        let rows = lRealizedIndices(frame)
        try #require(!rows.isEmpty,
                     "\(arm) \(name): an unbounded window publishes no rows — this arm never windowed",
                     sourceLocation: sourceLocation)
        try #require(rows.count < count, "\(arm) \(name): the window must be a strict subset",
                     sourceLocation: sourceLocation)
    }
}

// MARK: - The scrolled host, and the ids inside it

/// The one host shape in which a `List` inside the differential harness reaches
/// a **bounded** window, found by measurement in lane 1 (record §27 §6.7) and
/// re-used here: `DifferentialRoot`'s legacy arm (until stage 9) was a
/// `display: .stack` that offered its children fit-content, so a bare `ScrollView { List }` takes its
/// content's full extent as its viewport and windows nothing. The demo's own
/// spelling — `.flexGrow(1).flexBasis(0).minHeight(0)` inside a container with
/// a declared height — is what bounds the viewport.
@MainActor
private func lScrolledHost<Content: ElementGroup>(@ElementBuilder _ list: () -> Content)
    -> Box<Box<ScrollView<Content>>> {
    var column = Style()
    column.flexDirection = .column
    column.size = Size(width: .length(.pixels(lpx(100))), height: .length(.pixels(lpx(100))))
    return Box(style: column) {
        Box {
            ScrollView(.vertical) { list() }
        }
        .flexGrow(1).flexBasis(lpx(0)).cssMinHeight(lpx(0))
    }
}

/// `lScrolledHost`'s ids: the outer column is the harness root's member 0, the
/// growing `Box` its member 0, the `ScrollView` that `Box`'s member 0, and the
/// `List` the scroller's member 0. All positional — nothing here declares an
/// `elementID`.
private let lHostColumn = lChild(lRoot, 0)
private let lHostGrow = lChild(lHostColumn, 0)
private let lHostScroller = lChild(lHostGrow, 0)
private let lHostList = lChild(lHostScroller, 0)

// MARK: - 2.1 Every windowed shape

/// **Test 2.1** (`LR-BQ`, `LR-BR`). Five arms through the differential harness
/// in which the windowed proposal `List` and the legacy spacer-plus-rows `Box`
/// agree in **every** observation — element rects, the emitted and finalized
/// scenes, the hitbox list, the accessibility records with their geometry, and
/// the `StateTable` ids.
///
/// | arm | shape | what it adds |
/// |---|---|---|
/// | **B1** | `Box(width 100, column) { List(6 rows, 10) { Box() } }` | the unwindowed case: no scroll context at all, so `visibleRange` returns `0..<count` and `firstIndex` is 0 |
/// | **B2** | the scrolled host, 20 rows of 10, two frames, offset 0 | a **bounded** window at `firstIndex` 0 — rows 0…11 for a 100pt viewport over 10pt rows with `overscan` 2 |
/// | **B3** | the same, stored offset 50 | `firstIndex` **3** — rows 3…16. The arm the whole layout exists for: every realized row is placed at its ABSOLUTE index, with no spacer on the proposal side to place it |
/// | **B4** | the same at offset 50, the `List` `.width(80).padding(10)` | a `ModifiedElement` padding layer above the windowed layout, and a row narrower than the viewport |
/// | **B6** | `Box(width 100, column) { List(1 row, 10) { Box() } }` | **one** row under a `List` that declares no width: the single-child stretch elision must NOT fire, because the windowed layout is not fit-content (`LR-CD`) |
/// | **B5** | `Box(width 100, column) { List(3 rows, 28) { LoweredProbeLeaf(0×60) } }` | P3's tall row: content taller than `rowHeight`, floored at `rowHeight` on both sides |
///
/// **B2, B3 and B4 render two frames per side and `try #require` a bounded
/// window and a non-empty row-record set on both sides before asserting
/// anything** (`LR-BY`): one frame cannot window a `List` in this harness, and
/// an unwindowed arm's `accessibilityEqual` compares one table record with one
/// table record and passes vacuously.
///
/// **The literals are lane 1's, taken on the LEGACY side before this lane
/// existed** (record §27 §6.7) — the `List` at (0, 0) 100×200, row *i* at
/// (0, 10·i) 100×10, its content at (0, 10·i) 0×10, realized 0…11 unwindowed
/// and 3…16 at a stored offset of 50 — so they are an oracle rather than a
/// transcription of this lane's first green run.
///
/// **Measured, not predicted** (record §27 §7.4). This test is reddened by
/// **M2a** (`firstIndex` ignored: 30 issues across B3 and B4), **M2d**
/// (`planLegacyItems` skipped and the rows registered raw: every arm), **M2f**
/// (the rows' records not consumed: every arm) and **M2h** (the planning
/// parent's cross size left at the `List`'s own, so the elision fires — **B6
/// only**, which is the whole reason B6 exists).
///
/// **It is NOT reddened by M2b** (the height answer made greedy), and the
/// design predicted it would be. `List`'s own `Box` declares
/// `size.height = count × rowHeight`, which `paddedAndSized` turns into a fixed
/// native frame around the arrangement, so the layout's own height answer is
/// **masked in every composed tree** and only the kernel-level tests 2.2, 2.3
/// and 2.4b can see it. That is the measured reason 2.2 is not redundant with
/// this test.
///
/// It is not reddened by **M2e** either (the windowed node's
/// `recordLoweredItem` dropped) — see 2.7, where the same finding is written up
/// with the proof that nothing can observe it.
///
/// **Stage 9** (`LR-FE` item 2): one side, against the literals above; the
/// agreement — element rects, scenes, hitboxes, accessibility and state ids — is
/// the deleted concept. **B4**, whose only literal was that agreement, gains its
/// own, derived by hand before the run: the padding layer puts the 80-wide list
/// at (10, 10) 80×200 inside a 100×220 layer, row *i* at (10, 10 + 10·i) 80×10 and its content at
/// (10, 10 + 10·i) 0×10, and the window at a stored offset of 50 is B3's 3…16 —
/// `List.visibleRange` reads the scroller's offset and extent, not the list's
/// position inside the content. **Renamed** from
/// `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` (`LR-FE` item 6).
@MainActor
@Test func aLoweredListLaysOutEveryWindowedShape() throws {
    // B1 — unwindowed, no scroller.
    let b1 = LayoutDifferential.report(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(6), rowHeight: lpx(10)) { _ in Box() }
        }
    }
    lExpectNothingReported(b1, "B1")
    let b1List = lChild(lChild(lRoot, 0), 0)
    #expect(b1.bounds[b1List] == lBounds(0, 0, 100, 60), "B1 list: \(String(describing: b1.bounds[b1List]))")
    for index in 0..<6 {
        let row = lNamed(b1List, "item-\(index)")
        #expect(b1.bounds[row] == lBounds(0, Float(index) * 10, 100, 10),
                "B1 row \(index): \(String(describing: b1.bounds[row]))")
        #expect(b1.bounds[lChild(row, 0)] == lBounds(0, Float(index) * 10, 0, 10),
                "B1 row \(index) content: \(String(describing: b1.bounds[lChild(row, 0)]))")
    }

    // B2 — a bounded window at firstIndex 0.
    let b2 = lSeeded(width: 100, height: 100, frames: 2, offset: 0, scrollerID: lHostScroller) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.cssWidth(lpx(100)) }
    }
    try lRequireBoundedWindow(b2.lowered, count: 20, "B2")
    #expect(lRealizedIndices(b2.lowered) == Array(0...11), "B2 lowered window: \(lRealizedIndices(b2.lowered))")
    lExpectNothingReported(b2.report, "B2")
    #expect(b2.report.bounds[lHostList] == lBounds(0, 0, 100, 200),
            "B2 list: \(String(describing: b2.report.bounds[lHostList]))")

    // B3 — the same, scrolled to 50, so firstIndex is 3.
    let b3 = lSeeded(width: 100, height: 100, frames: 2, offset: 50, scrollerID: lHostScroller) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.cssWidth(lpx(100)) }
    }
    try lRequireBoundedWindow(b3.lowered, count: 20, "B3")
    #expect(lRealizedIndices(b3.lowered) == Array(3...16), "B3 lowered window: \(lRealizedIndices(b3.lowered))")
    lExpectNothingReported(b3.report, "B3")
    #expect(b3.report.bounds[lHostList] == lBounds(0, 0, 100, 200),
            "B3 list: \(String(describing: b3.report.bounds[lHostList]))")
    for index in 3...16 {
        let row = lNamed(lHostList, "item-\(index)")
        #expect(b3.report.bounds[row] == lBounds(0, Float(index) * 10, 100, 10),
                "B3 row \(index): \(String(describing: b3.report.bounds[row]))")
        #expect(b3.report.bounds[lChild(row, 0)] == lBounds(0, Float(index) * 10, 0, 10),
                "B3 row \(index) content: \(String(describing: b3.report.bounds[lChild(row, 0)]))")
    }

    // B4 — the same, with a padding layer above the list and a narrower row.
    let b4 = lSeeded(width: 100, height: 100, frames: 2, offset: 50, scrollerID: lHostScroller) {
        lScrolledHost {
            List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.cssWidth(lpx(80)).padding(lpx(10))
        }
    }
    try lRequireBoundedWindow(b4.lowered, count: 20, "B4")
    // **2…15 since plan task 10 (ruling `DD-O`, a changed answer of `DD-F`)**:
    // the padding layer puts the list 10pt down its scroller's content, so at
    // offset 50 the list-local band is 40…140 (rows 4…13, plus two of
    // overscan). It read 3…16 while the window ignored the list's origin
    // (divergence 14, retired).
    #expect(lRealizedIndices(b4.lowered) == Array(2...15), "B4 window: \(lRealizedIndices(b4.lowered))")
    lExpectNothingReported(b4.report, "B4")
    // The padding layer takes the list's slot; the list is its member 0.
    let b4Layer = lHostList, b4List = lChild(b4Layer, 0)
    #expect(b4.report.bounds[b4Layer] == lBounds(0, 0, 100, 220), "B4 layer: \(String(describing: b4.report.bounds[b4Layer]))")
    #expect(b4.report.bounds[b4List] == lBounds(10, 10, 80, 200), "B4 list: \(String(describing: b4.report.bounds[b4List]))")
    for index in 2...15 {
        let row = lNamed(b4List, "item-\(index)")
        #expect(b4.report.bounds[row] == lBounds(10, 10 + Float(index) * 10, 80, 10),
                "B4 row \(index): \(String(describing: b4.report.bounds[row]))")
        #expect(b4.report.bounds[lChild(row, 0)] == lBounds(10, 10 + Float(index) * 10, 0, 10),
                "B4 row \(index) content: \(String(describing: b4.report.bounds[lChild(row, 0)]))")
    }

    // B6 — ONE row, and the `List` declaring no width of its own. The arm
    // exists because `planLegacyItems`' single-child stretch elision (`LR-AC`)
    // would otherwise fire here and leave that row unstretched: the elision's
    // premise is that a fit-content parent stretching its only child is the
    // identity, and `WindowedRowsLayout` is not fit-content — it answers the
    // proposal. Without `loweredNode`'s planning-parent correction (`LR-CD`)
    // this row reads 0 wide against the legacy engine's 100. Six rows hide it,
    // which is why five of the six arms above cannot see it.
    let b6 = LayoutDifferential.report(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(1), rowHeight: lpx(10)) { _ in Box() }
        }
    }
    lExpectNothingReported(b6, "B6")
    let b6Row = lNamed(lChild(lChild(lRoot, 0), 0), "item-0")
    #expect(b6.bounds[b6Row] == lBounds(0, 0, 100, 10),
            "B6 row: \(String(describing: b6.bounds[b6Row]))")

    // B5 — P3's tall row: 60pt of content in a 28pt row, floored at 28 on both
    // sides, with each row still at `index × rowHeight`.
    let b5 = LayoutDifferential.report(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(3), rowHeight: lpx(28)) { _ in LoweredProbeLeaf(width: 0, height: 60) }
        }
    }
    lExpectNothingReported(b5, "B5")
    let b5List = lChild(lChild(lRoot, 0), 0)
    for index in 0..<3 {
        let row = lNamed(b5List, "item-\(index)")
        #expect(b5.bounds[row] == lBounds(0, Float(index) * 28, 100, 28),
                "B5 row \(index): \(String(describing: b5.bounds[row]))")
    }
}

// MARK: - 2.5 A realized row is placed at its absolute index

/// **Test 2.5** (`LR-BR`). Under the **proposal** authority a realized row sits
/// at `(firstIndex + i) × rowHeight`, not at the window's top — the invariant
/// the leading spacer buys on the legacy path and that `WindowedRowsLayout`
/// buys directly on this one.
///
/// Read from `Frame.elementBounds` on the lowered side alone (the only side
/// since stage 9).
///
/// Mutation that must redden it: **M2a** (`firstIndex` ignored: every row slides
/// up by 30).
@MainActor
@Test func aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight() throws {
    let table = StateTable()
    table.withState(lHostScroller, initial: ScrollState()) { $0.offset = 50 }
    let frame = LayoutDifferential.render(width: 100, height: 100,
                                          stateTable: table, frames: 2) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.cssWidth(lpx(100)) }
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    let realized = lRealizedIndices(frame)
    try #require(realized == Array(3...16), "the window this arm is about: \(realized)")
    for index in realized {
        let row = lNamed(lHostList, "item-\(index)")
        #expect(frame.elementBounds[row] == lBounds(0, Float(index) * 10, 100, 10),
                "row \(index): \(String(describing: frame.elementBounds[row]))")
    }
    // Not one realized row sits in the window's own coordinate space: row 3 is
    // at 30, not at 0.
    #expect(frame.elementBounds[lNamed(lHostList, "item-3")]?.origin.y == lpx(30))
}

// MARK: - 2.7 The `.list` site reports nothing, and the rows' item fields lower

/// **Test 2.7** (`LR-BV` as amended, §4.2(d)). A plain `List` under the
/// proposal authority with diagnostics on reports **nothing at all**.
///
/// Two separately removable halves:
///
/// - **the site-level entry is gone**: `list.noLowering` was the whole of
///   `List`'s report until this lane, and no entry may carry site `.list` now.
///   `LoweringSite.list` itself stays, reachable through `planLegacyItems`'
///   `parentSite:` (`flexGrow.weights`, which no row can raise today — the row
///   style sets no `flexGrow` and a caller's closure builds the row's CONTENT,
///   one level below, whose records are planned at the row `Box`'s own site)
///   and through an unconsumed record;
/// - **the rows' own item fields are consumed**: `rowStyle` declares
///   `flexShrink = 0` and `minSize.height = 0`, both non-default, so a row
///   record the group failed to consume would report
///   `box.flexShrink.unconsumed` and `box.minSize.unconsumed` when the root's
///   registration returns (`LR-AQ`). An empty report is therefore a statement
///   about the consumption as well as about the site.
///
/// Mutation that reddens it: **M2f** (the rows' records not consumed) — three
/// `box.flexShrink.unconsumed` and three `box.minSize.unconsumed` entries here,
/// and it reddens `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s new
/// absence arm as well, which is what says that arm is not vacuous.
///
/// **M2e — the windowed node's own `recordLoweredItem` dropped — reddens
/// NOTHING**, where the design predicted an `…unconsumed` entry here. Both
/// halves of that prediction are wrong, and the reason is provable by reading
/// rather than merely unmeasured (`LR-CD`, the shape lane 1's M1c took):
///
/// - a **dropped** record never joins `LoweringState.order`, which
///   `reportUnconsumedLoweredItems` iterates, so it cannot produce an
///   `…unconsumed` entry by construction — an unconsumed record can, which is
///   M2f;
/// - and the record's only other effect is the stretch item frame the enclosing
///   `Box` would wrap the arrangement in, which is **redundant against a
///   proposal-greedy layout**: `WindowedRowsLayout` already answers
///   `proposal.width`, so W's greedy width changes no number. The record is
///   kept for `LR-AB`'s uniform convention (every lowered site records the node
///   it returns) and for the `<field>.unconsumed` reachability
///   `UnlowerableField.owningStage`'s `.list` comment claimed until stage 10
///   deleted that per-site switch for `owner` (record §53), not because
///   anything can see it today.
@MainActor
@Test func theListSiteReportsNothingAndItsRowsItemFieldsAreLowered() throws {
    let frame = LayoutDifferential.render(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(6), rowHeight: lpx(10)) { _ in Box() }
        }
    }
    #expect(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    #expect(frame.unlowerableFields.allSatisfy { $0.site != .list },
            "no entry may name the list site: \(frame.unlowerableFields)")
    // The arm is not vacuous: the rows really were built on this side.
    #expect(frame.elementBounds[lNamed(lChild(lChild(lRoot, 0), 0), "item-5")] != nil,
            "the lowered side must build its rows, or an empty report says nothing")
}

// MARK: - 2.8 Row identity

/// **Test 2.8** (`TB-` rulings, §4.1 row 1). The windowed layout introduces no
/// identity level: `ListRows` is a GROUP, and the outer `Box` still reuses the
/// `List`'s own id, so a row's `GlobalElementID` is
/// `child(of: listID, name: String(describing: datum.id))`.
///
/// **Until stage 9** the strong half was the two authorities' `StateTable` id
/// sets being **equal** — which caught an extra level, a missing level and a
/// renamed slot at once. **Since then** (`LR-FE` item 2) it is a literal on the
/// one table, derived by hand before the run: every `StateTable` entry under the
/// list sits, one level below the list, at a **named** row id `item-0`…`item-5`
/// or at a `$`-named slot of the list's own — so a positional level introduced
/// between the `List` and its rows fails it — and all six rows own an entry and
/// record bounds. `rowID(4)` is asserted separately, as before, because a
/// mutation that emptied the table would satisfy the "every entry" half alone.
///
/// Mutation that must redden it: **M2a** is not it — the ids do not depend on
/// placement. A level introduced between the `List` and its rows is what this
/// pins, which is why `ListRows` is a group and the spec says so.
///
/// **Renamed at stage 9** from `aLoweredListsRowIdentitiesAreTheLegacyOnes`
/// (`LR-FE` item 6).
@MainActor
@Test func aLoweredListsRowsAreNamedDirectlyUnderTheList() throws {
    let lowered = LayoutDifferential.render(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(6), rowHeight: lpx(10)) { _ in Box() }
        }
    }
    try #require(lowered.unlowerableFields.isEmpty, "\(lowered.unlowerableFields)")

    let listID = lChild(lChild(lRoot, 0), 0)
    let rowNames = Set((0..<6).map { ElementID("item-\($0)") })
    // The level directly below the list for each entry under it.
    func levelBelow(_ id: GlobalElementID, _ ancestor: GlobalElementID) -> GlobalElementID? {
        var cursor: GlobalElementID? = id
        while let current = cursor {
            if current.parent == ancestor { return current }
            cursor = current.parent
        }
        return nil
    }
    let underList = lowered.stateTable.ids.compactMap { levelBelow($0, listID) }
    try #require(!underList.isEmpty, "the list's rows must own StateTable entries")
    for level in underList {
        let ok: Bool
        switch level.component {
        case .named(let name): ok = rowNames.contains(name) || name.name.hasPrefix("$")
        default: ok = false
        }
        #expect(ok, "an entry under the list at an unexpected level: \(level)")
    }
    for index in 0..<6 {
        let row = lNamed(listID, "item-\(index)")
        #expect(underList.contains(row), "row \(index) must own a StateTable entry under \(row)")
        #expect(lowered.elementBounds[row] != nil, "row \(index)'s bounds")
    }
    let rowID = lNamed(listID, "item-4")
    func descends(_ id: GlobalElementID, from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let current = cursor {
            if current == ancestor { return true }
            cursor = current.parent
        }
        return false
    }
    #expect(lowered.stateTable.ids.contains(where: { descends($0, from: rowID) }),
            "row 4 must own at least one StateTable entry under \(rowID)")
}

// MARK: - The kernel fixture the layout's own tests measure on

/// `n` native leaves, each answering `width × height` at every proposal, under
/// one `WindowedRowsLayout` — the layout alone, with no `List`, no `Box`
/// lowering and no item wrappers in the way, so every measure call and every
/// cache lookup below can be hand-derived before the run.
///
/// **`widths` gives each row its own width** so a nil-axis answer can be told
/// from "the first row's" and from "the last row's".
///
/// **Each leaf answers the proposal on an axis that has one** and its own width
/// (or 9) on an axis that does not — a real `List` row's shape, where the row
/// `Box` pins the height and stretch pins the width. A leaf answering a
/// constant whatever it is proposed would make every placement rect the same
/// and hide what `place(at:anchor:proposal:)` stores.
@MainActor
private func lKernelWindow(widths: [Float], rowHeight: Double, logicalCount: Int,
                           firstIndex: Int, generation: UInt64)
    -> (tree: LayoutTree, node: LayoutNodeID, rows: [LayoutNodeID]) {
    let tree = LayoutTree(generation: generation)
    let rows = widths.map { w in
        tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? Double(w),
                                          height: proposal.height ?? 9))
        }
    }
    let node = tree.newNativeLayout(
        WindowedRowsLayout(rowHeight: rowHeight, logicalCount: logicalCount, firstIndex: firstIndex),
        children: rows)
    return (tree, node, rows)
}

// MARK: - 2.2 The full content extent, and the proposed width

/// **Test 2.2** (`LR-BR`). The windowed layout answers `rowHeight ×
/// logicalCount` on the stacking axis at **every** proposal, and the proposal
/// itself on the other axis whenever one is offered.
///
/// **Arrives with its subject** — it reads `WindowedRowsLayout`'s own answer, so
/// it cannot compile at lane 1's HEAD and is not a red-before (`LR-BX`). Its
/// literals are hand-derived: 40 logical rows of 28 are **1120** whatever is
/// proposed and whatever the twelve realized rows measure, and a 100pt width
/// proposal is answered 100.
///
/// **The height half is where MetalUI's `List` deliberately diverges from
/// SwiftUI's** (probe K6): `K6a` answers the proposal 100×100, `K6b` 0×0 at
/// nil×nil, `K6c` 100×0 and `K6d` 0×100 — greedy and content-blind, because
/// SwiftUI's `List` **is** its own viewport. MetalUI's is its scroller's
/// content, so the full extent is what the clamp and the thumb must read.
///
/// **1120 at an infinite proposal too**, where `K6e` answers ∞: a measurement
/// may be infinite (`SA-J` checkpoint 1) but this one is not, because the
/// content extent does not depend on the offer.
///
/// Mutation that must redden it: **M2b** (the height answer made greedy, i.e.
/// K6's).
@MainActor
@Test func aWindowedListAnswersItsFullContentHeightAndItsProposedWidth() throws {
    let fixture = lKernelWindow(widths: Array(repeating: Float(37), count: 12),
                                rowHeight: 28, logicalCount: 40, firstIndex: 0, generation: 4001)
    // Every proposal, including the two SwiftUI answers 0 on and the infinite one.
    let answers: [(ProposedSize, SizeD)] = [
        (ProposedSize(width: 100, height: 100), SizeD(width: 100, height: 1120)),   // vs K6a 100x100
        (ProposedSize(width: nil, height: nil), SizeD(width: 37, height: 1120)),    // vs K6b 0x0
        (ProposedSize(width: 100, height: nil), SizeD(width: 100, height: 1120)),   // vs K6c 100x0
        (ProposedSize(width: nil, height: 100), SizeD(width: 37, height: 1120)),    // vs K6d 0x100
        (ProposedSize(width: .infinity, height: .infinity),
         SizeD(width: .infinity, height: 1120)),                                    // vs K6e infxinf
        (ProposedSize(width: 0, height: 0), SizeD(width: 0, height: 1120)),
    ]
    for (proposal, expected) in answers {
        let measured = fixture.tree.measureNativeLayout(root: fixture.node, proposal: proposal)
        #expect(measured.size == expected, "\(proposal): \(measured.size)")
        #expect(measured.firstBaseline == nil && measured.lastBaseline == nil,
                "no producer and no consumer for baselines: \(measured)")
    }

    // The height is the LOGICAL count's, not the realized one's: twelve rows
    // are realized here and 12 x 28 = 336 is not 1120.
    #expect(fixture.rows.count == 12)
}

// MARK: - 2.3 One measurement per realized row, and it is placement's

/// **Test 2.3** (`LR-CA`). On the concrete-width path the layout costs **one
/// `measureNative` lookup per realized row**, and that lookup is
/// `LayoutTree.placeCustom`'s, not `sizeThatFits`'s — the arithmetic this
/// stage's design had to correct, having first priced the path at zero.
///
/// Hand-derived before the run, on the kernel fixture alone (twelve rows, a
/// 100×60 proposal, placed at its own answer):
///
/// | phase | what runs | misses | hits | `measureCalls` |
/// |---|---|---|---|---|
/// | measure | `measureNative(W)` misses and calls `sizeThatFits`, which measures **no** subview — the width comes from the proposal and the height from `logicalCount` | 1 | 0 | 1 |
/// | place | `placeCustom` runs `placeSubviews` (which measures nothing either), then re-measures each of the twelve children at its recorded `(100, 28)` — a key nothing has asked for | 12 | 0 | 12 |
/// | **total** | | **13** | **0** | **13** |
///
/// **Zero hits is the load-bearing figure**: it says the placement lookups are
/// real work and not a cached echo of a measurement pass, which is why `LR-CA`
/// had to be written.
///
/// **`measureCalls` counts leaf closures as well as custom `sizeThatFits`
/// bodies** (`NativeLayoutWork.measureCalls`' own doc: "Leaf-closure and custom
/// `sizeThatFits` invocations"), so the 13 is one layout body plus twelve leaf
/// bodies, not one. The first writing of this test predicted 1, read 13, and
/// the derivation above was corrected against the counter rather than the
/// number against the derivation.
///
/// **`O(window)`, not `O(logicalCount)`** — 40 logical rows, 13 lookups — which
/// is the property the stage's exit test counts.
///
/// **Arrives with its subject.** Measured: **M2b** (the height answer made
/// greedy) reddens it — the placement proposals change with the answer — where
/// **M2d** cannot reach this fixture, which has no item wrappers by
/// construction. The pin is the three literals themselves, derived by hand
/// before the run.
@MainActor
@Test func aWindowedListPlacesEachRealizedRowWithExactlyOneMeasurement() throws {
    let fixture = lKernelWindow(widths: Array(repeating: Float(37), count: 12),
                                rowHeight: 28, logicalCount: 40, firstIndex: 0, generation: 4002)
    let proposal = ProposedSize(width: 100, height: 60)
    let measured = fixture.tree.computeNativeLayout(
        root: fixture.node, proposal: proposal,
        in: LayoutRect(x: 0, y: 0, width: 100, height: 1120))
    #expect(measured.size == SizeD(width: 100, height: 1120))

    let work = fixture.tree.lastNativeLayoutWork
    #expect(work.cacheMisses == 13, "cacheMisses: \(work.cacheMisses)")
    #expect(work.cacheHits == 0, "cacheHits: \(work.cacheHits)")
    #expect(work.measureCalls == 13, "measureCalls: \(work.measureCalls)")

    // And the rows really were placed at their absolute offsets, so the count
    // above is the cost of doing the work rather than of skipping it.
    for index in fixture.rows.indices {
        #expect(fixture.tree.layout(fixture.rows[index])
                    == LayoutRect(x: 0, y: Double(index) * 28, width: 100, height: 28),
                "row \(index): \(fixture.tree.layout(fixture.rows[index]))")
    }
}

// MARK: - 2.4 A nil width answers the widest realized row

/// **Test 2.4** (`LR-BR`). The one half of one axis on which this layout
/// deliberately does **not** follow SwiftUI: at a nil width it answers the
/// **widest** realized row, where `K6b`/`K6d` answer 0.
///
/// The composition that reaches a nil width is a vertical `List` inside a
/// **horizontal** `ScrollView` — `visibleRange` already declines to window that
/// one (`aVerticalListInsideAHorizontalScrollViewBuildsEveryRow`) — and
/// answering 0 there would render it blank, a second blank-render mode beside
/// divergence 14's.
///
/// **Widest, not first and not last**: the rows here are 20, 61 and 33 wide in
/// that order, so a mutation answering either end reads a different number.
///
/// **Arrives with its subject.** Mutation that reddens it: **M2c** (the width
/// answer made 0 on a nil axis, i.e. K6's). Measured: M2c reddens 2.4, 2.2's
/// two nil-width arms and 2.4b — three tests, not "this one only" as the design
/// predicted. Three pins for the diverging half is more than one, not fewer;
/// 2.4 is the one that names it.
@MainActor
@Test func aWindowedListAtANilWidthAnswersItsWidestRow() throws {
    let fixture = lKernelWindow(widths: [20, 61, 33], rowHeight: 10, logicalCount: 9,
                                firstIndex: 0, generation: 4003)
    let nilWidth = fixture.tree.measureNativeLayout(root: fixture.node,
                                                    proposal: ProposedSize(width: nil, height: 90))
    #expect(nilWidth.size == SizeD(width: 61, height: 90), "\(nilWidth.size)")

    // The control: a concrete width is answered, so the branch above is the
    // nil one and not a widest-row answer given unconditionally.
    let concrete = fixture.tree.measureNativeLayout(root: fixture.node,
                                                    proposal: ProposedSize(width: 200, height: 90))
    #expect(concrete.size == SizeD(width: 200, height: 90), "\(concrete.size)")
}

// MARK: - 2.4b The nil-width path measures every LOGICAL row twice

/// **Test 2.4b** (`LR-CA`, spec §3.2.1). The nil-width path costs **two**
/// `measureNative` lookups per row at two different proposals —
/// `sizeThatFits` at `(nil, rowHeight)` and `placeCustom` at
/// `(bounds.width, rowHeight)`, a key nothing has asked for, so the second is a
/// **miss** and not a hit — and on that path every LOGICAL row is realized,
/// because `visibleRange` declines to window a non-`.vertical` context. So the
/// path is `O(logicalCount)`, unbounded, at any row count.
///
/// **The prediction was written down before the run**: `1 + 2n` misses and 0
/// hits for *n* realized rows, giving a slope of exactly **2 per row**. A
/// different slope is a finding, not a number to write down. (`measureCalls`
/// reads `1 + 2n` as well — it counts leaf closures beside custom
/// `sizeThatFits` bodies, which the first writing of 2.3 got wrong and this one
/// inherits corrected.)
///
/// Two halves, because the claim has two:
///
/// - **the kernel half**, at *n* = 6 and *n* = 15, where the arithmetic is
///   exact because nothing else is in the tree;
/// - **the composition half**, a real vertical `List` inside a horizontal
///   `ScrollView` at three row counts, where the per-row cost is whatever the
///   rows' own lowering adds on top and the pinned claim is that it is
///   **linear in the LOGICAL count** — equal first differences — and that the
///   window really is every row.
///
/// Mitigating the cost would change `visibleRange`, which `LR-BT` pins shut;
/// spec §9 carries it to stage 6b.
///
/// **Arrives with its subject.**
@MainActor
@Test func aNilWidthListMeasuresEveryLogicalRowTwice() throws {
    for (n, generation) in [(6, UInt64(4004)), (15, UInt64(4005))] {
        let fixture = lKernelWindow(widths: Array(repeating: Float(37), count: n),
                                    rowHeight: 10, logicalCount: n, firstIndex: 0,
                                    generation: generation)
        let measured = fixture.tree.measureNativeLayout(root: fixture.node,
                                                        proposal: ProposedSize(width: nil, height: 40))
        try #require(measured.size == SizeD(width: 37, height: Double(n) * 10), "\(n): \(measured.size)")
        // Placement re-measures at the concrete bounds width, which is the
        // second, different key.
        _ = fixture.tree.computeNativeLayout(root: fixture.node,
                                             proposal: ProposedSize(width: nil, height: 40),
                                             in: LayoutRect(x: 0, y: 0, width: 37,
                                                            height: Double(n) * 10))
        let work = fixture.tree.lastNativeLayoutWork
        #expect(work.cacheMisses == 1 + 2 * n, "n = \(n) cacheMisses: \(work.cacheMisses)")
        #expect(work.cacheHits == 0, "n = \(n) cacheHits: \(work.cacheHits)")
        #expect(work.measureCalls == 1 + 2 * n, "n = \(n) measureCalls: \(work.measureCalls)")
    }

    // The composition half. A vertical `List` inside a HORIZONTAL `ScrollView`
    // is the one shape that reaches the nil-width branch in production, and it
    // is also the one `visibleRange` refuses to window — so the work is linear
    // in the logical count, not in a window's size.
    var totals: [Int: Int] = [:]
    for n in [4, 8, 12] {
        let frame = LayoutDifferential.render(width: 200, height: 200) {
            Box {
                ScrollView(.horizontal) {
                    List(lItems(n), rowHeight: lpx(10)) { _ in Box() }
                }
            }
        }
        try #require(frame.unlowerableFields.isEmpty, "n = \(n): \(frame.unlowerableFields)")
        // Every logical row realized: the window is not a window here.
        try #require(frame.elementBounds[lNamed(lChild(lChild(lChild(lRoot, 0), 0), 0),
                                                "item-\(n - 1)")] != nil,
                     "n = \(n): the last row must be built, or this is not the unwindowed path")
        let work = frame.tree.lastNativeLayoutWork
        totals[n] = work.cacheMisses + work.cacheHits
    }
    let d1 = try #require(totals[8]).advanced(by: -(try #require(totals[4])))
    let d2 = try #require(totals[12]).advanced(by: -(try #require(totals[8])))
    #expect(d1 == d2,
            "the lookups must be linear in the LOGICAL row count: \(totals.sorted { $0.key < $1.key })")
    #expect(d1 % 4 == 0, "four rows' worth: \(d1)")
}

// MARK: - 2.6 A zero row height lowers quietly

/// **Test 2.6** (`SA-J`). `rowHeight` 0 is legal, quiet input `List` has always
/// accepted — `visibleRange` declines to window against it
/// (`aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent`) — and the windowed
/// layout **rejects nothing**, so the degenerate case has to lower rather than
/// trap.
///
/// `SA-J`'s three checkpoints, on this input: the measurement is finite (0 ×
/// 0), every stored rect is finite, and nothing is NaN. The layout's own
/// arithmetic is `0 × logicalCount` and `bounds.y + index × 0`, neither of
/// which can produce a NaN from a finite `bounds`.
///
/// Both authorities, through the differential until stage 9, because "does not
/// trap" is only half of it: the legacy engine sized every row and the whole list
/// to zero and the lowered one had to agree. Since then the rows are a literal,
/// derived by hand before the run from B1's shape: each row stretched to the
/// column's 100 and 0 tall, at y 0 (`index × 0`).
///
/// **Arrives with its subject.**
@MainActor
@Test func aZeroRowHeightLowersWithoutTrappingOrProducingNaN() throws {
    let report = LayoutDifferential.report(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(5), rowHeight: lpx(0)) { _ in Box() }
        }
    }
    lExpectNothingReported(report, "zero rowHeight")
    let listID = lChild(lChild(lRoot, 0), 0)
    for index in 0..<5 {
        let row = try #require(report.bounds[lNamed(listID, "item-\(index)")],
                               "row \(index) must be built — five rows, no window")
        #expect(row == lBounds(0, 0, 100, 0), "row \(index): \(row)")
        for value in [row.origin.x.value, row.origin.y.value, row.size.width.value, row.size.height.value] {
            #expect(value.isFinite, "row \(index) rect is not finite: \(row)")
        }
    }
    #expect(report.bounds[listID]?.size.height == lpx(0),
            "\(String(describing: report.bounds[listID]))")
}
