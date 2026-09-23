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

/// A `column` style of the given width — P1a6's host shape (record §26 §2.2):
/// a declared cross size on the container is what removes `DifferentialRoot`'s
/// own divergence 53 from every arm below, so what the arms measure is the
/// `List` and not the harness root.
private func lColumn(width: Float) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size.width = .length(.pixels(lpx(width)))
    return style
}

/// A fixed-size leaf spelled **through the lowering** on both authorities —
/// P3's re-spelling (`LR-BW`, record §26 §2.5), not `ProbeLeaf`'s.
///
/// The difference is the whole of `LR-BW`: `ProbeLeaf` registers a native leaf
/// **directly** under the proposal authority, so it records no `LoweredItem`,
/// `planLegacyItems` cannot plan it and no lowered container ever stretches it
/// — measured at 7×3 against the legacy engine's 7×10 (record §26 §2.2, P1a2).
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
        if pass.lowersToProposal {
            let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .customElement) {
                pass.frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: w, height: h)) }
            }
            return (node, ())
        }
        return (pass.requestLeaf(style: Style()) { _, _ in SizeD(width: w, height: h) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// Every whole-frame observation agrees and nothing was reported — the same
/// roll call `LoweringScrollTests.lane2ExpectAgreement` makes, repeated here
/// because that one is `private` to its own file.
@MainActor
private func lExpectAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                              sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly.count) loweredOnly \(r.loweredOnly.count)",
            sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

/// Both sides of one arm, each rendered over its **own** `StateTable` seeded
/// with `offset` at `scrollerID`, each over `frames` frames.
///
/// `LayoutDifferential.compare` cannot do this: it takes `frames:` but
/// deliberately not `stateTable:` (`LR-CC` item 1 — one shared table would make
/// `stateSlotsEqual` compare a set with itself). A scrolled arm needs a stored
/// offset before frame 1, so it builds its two sides by hand and hands them to
/// `report(legacy:lowered:)`, which is what `compare` does anyway.
///
/// **Two frames is not a detail** (`LR-BY`): `ScrollContext.viewportExtent` is
/// written only by `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload, so
/// on frame 1 it is 0 and `List.visibleRange` declines to window. Frame 2 is
/// the first frame with a bounded window.
@MainActor
private func lSeededSides<Content: ElementGroup>(
    width: Float, height: Float, frames: Int, offset: Double,
    scrollerID: GlobalElementID,
    @ElementBuilder _ make: @MainActor () -> Content
) -> (report: LayoutDifferential.Report, legacy: Frame, lowered: Frame) {
    func side(_ authority: LayoutAuthority) -> Frame {
        let table = StateTable()
        table.withState(scrollerID, initial: ScrollState()) { $0.offset = offset }
        return LayoutDifferential.render(authority: authority, width: width, height: height,
                                         stateTable: table, frames: frames, make)
    }
    let legacy = side(.legacy)
    let lowered = side(.proposal)
    return (LayoutDifferential.report(legacy: legacy, lowered: lowered), legacy, lowered)
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
/// (`LR-BY`): a bounded window and a **non-empty** row-record set on **both**
/// sides, and a window that is a strict subset of the logical count.
@MainActor
private func lRequireBoundedWindow(_ legacy: Frame, _ lowered: Frame, count: Int, _ arm: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
    for (name, frame) in [("legacy", legacy), ("lowered", lowered)] {
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
/// a **bounded** window, found by measurement in lane 1 (record §26 §6.7) and
/// re-used here: `DifferentialRoot`'s legacy arm is a `display: .stack` that
/// offers its children fit-content, so a bare `ScrollView { List }` takes its
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
        .flexGrow(1).flexBasis(lpx(0)).minHeight(lpx(0))
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

// MARK: - 2.1 Every windowed shape agrees with the legacy engine

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
/// | **B5** | `Box(width 100, column) { List(3 rows, 28) { LoweredProbeLeaf(0×60) } }` | P3's tall row: content taller than `rowHeight`, floored at `rowHeight` on both sides |
///
/// **B2, B3 and B4 render two frames per side and `try #require` a bounded
/// window and a non-empty row-record set on both sides before asserting
/// anything** (`LR-BY`): one frame cannot window a `List` in this harness, and
/// an unwindowed arm's `accessibilityEqual` compares one table record with one
/// table record and passes vacuously.
///
/// **The literals are lane 1's, taken on the LEGACY side before this lane
/// existed** (record §26 §6.7) — the `List` at (0, 0) 100×200, row *i* at
/// (0, 10·i) 100×10, its content at (0, 10·i) 0×10, realized 0…11 unwindowed
/// and 3…16 at a stored offset of 50 — so they are an oracle rather than a
/// transcription of this lane's first green run.
///
/// Mutations that must redden it: **M2a** (`firstIndex` ignored), **M2b** (the
/// height answer made greedy, i.e. SwiftUI's K6), **M2d** (`planLegacyItems`
/// skipped and the rows registered raw), **M2f** (the rows' records not
/// consumed).
@MainActor
@Test func aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape() throws {
    // B1 — unwindowed, no scroller.
    let b1 = LayoutDifferential.compare(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(6), rowHeight: lpx(10)) { _ in Box() }
        }
    }
    lExpectAgreement(b1, "B1")
    let b1List = lChild(lChild(lRoot, 0), 0)
    #expect(b1.legacyBounds[b1List] == lBounds(0, 0, 100, 60), "B1 list: \(String(describing: b1.legacyBounds[b1List]))")
    for index in 0..<6 {
        let row = lNamed(b1List, "item-\(index)")
        #expect(b1.loweredBounds[row] == lBounds(0, Float(index) * 10, 100, 10),
                "B1 row \(index): \(String(describing: b1.loweredBounds[row]))")
        #expect(b1.loweredBounds[lChild(row, 0)] == lBounds(0, Float(index) * 10, 0, 10),
                "B1 row \(index) content: \(String(describing: b1.loweredBounds[lChild(row, 0)]))")
    }

    // B2 — a bounded window at firstIndex 0.
    let b2 = lSeededSides(width: 100, height: 100, frames: 2, offset: 0, scrollerID: lHostScroller) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.width(lpx(100)) }
    }
    try lRequireBoundedWindow(b2.legacy, b2.lowered, count: 20, "B2")
    #expect(lRealizedIndices(b2.legacy) == Array(0...11), "B2 legacy window: \(lRealizedIndices(b2.legacy))")
    #expect(lRealizedIndices(b2.lowered) == Array(0...11), "B2 lowered window: \(lRealizedIndices(b2.lowered))")
    lExpectAgreement(b2.report, "B2")
    #expect(b2.report.loweredBounds[lHostList] == lBounds(0, 0, 100, 200),
            "B2 list: \(String(describing: b2.report.loweredBounds[lHostList]))")

    // B3 — the same, scrolled to 50, so firstIndex is 3.
    let b3 = lSeededSides(width: 100, height: 100, frames: 2, offset: 50, scrollerID: lHostScroller) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.width(lpx(100)) }
    }
    try lRequireBoundedWindow(b3.legacy, b3.lowered, count: 20, "B3")
    #expect(lRealizedIndices(b3.legacy) == Array(3...16), "B3 legacy window: \(lRealizedIndices(b3.legacy))")
    #expect(lRealizedIndices(b3.lowered) == Array(3...16), "B3 lowered window: \(lRealizedIndices(b3.lowered))")
    lExpectAgreement(b3.report, "B3")
    #expect(b3.report.loweredBounds[lHostList] == lBounds(0, 0, 100, 200),
            "B3 list: \(String(describing: b3.report.loweredBounds[lHostList]))")
    for index in 3...16 {
        let row = lNamed(lHostList, "item-\(index)")
        #expect(b3.report.loweredBounds[row] == lBounds(0, Float(index) * 10, 100, 10),
                "B3 row \(index): \(String(describing: b3.report.loweredBounds[row]))")
        #expect(b3.report.loweredBounds[lChild(row, 0)] == lBounds(0, Float(index) * 10, 0, 10),
                "B3 row \(index) content: \(String(describing: b3.report.loweredBounds[lChild(row, 0)]))")
    }

    // B4 — the same, with a padding layer above the list and a narrower row.
    let b4 = lSeededSides(width: 100, height: 100, frames: 2, offset: 50, scrollerID: lHostScroller) {
        lScrolledHost {
            List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.width(lpx(80)).padding(lpx(10))
        }
    }
    try lRequireBoundedWindow(b4.legacy, b4.lowered, count: 20, "B4")
    #expect(lRealizedIndices(b4.legacy) == lRealizedIndices(b4.lowered),
            "B4 windows: \(lRealizedIndices(b4.legacy)) vs \(lRealizedIndices(b4.lowered))")
    lExpectAgreement(b4.report, "B4")

    // B5 — P3's tall row: 60pt of content in a 28pt row, floored at 28 on both
    // sides, with each row still at `index × rowHeight`.
    let b5 = LayoutDifferential.compare(width: 200, height: 200) {
        Box(style: lColumn(width: 100)) {
            List(lItems(3), rowHeight: lpx(28)) { _ in LoweredProbeLeaf(width: 0, height: 60) }
        }
    }
    lExpectAgreement(b5, "B5")
    let b5List = lChild(lChild(lRoot, 0), 0)
    for index in 0..<3 {
        let row = lNamed(b5List, "item-\(index)")
        #expect(b5.loweredBounds[row] == lBounds(0, Float(index) * 28, 100, 28),
                "B5 row \(index): \(String(describing: b5.loweredBounds[row]))")
    }
}

// MARK: - 2.5 A realized row is placed at its absolute index

/// **Test 2.5** (`LR-BR`). Under the **proposal** authority a realized row sits
/// at `(firstIndex + i) × rowHeight`, not at the window's top — the invariant
/// the leading spacer buys on the legacy path and that `WindowedRowsLayout`
/// buys directly on this one.
///
/// Read from `Frame.elementBounds` on the lowered side alone, so it fails even
/// if the legacy side were to move with it — 2.1 is the arm that compares the
/// two.
///
/// Mutation that must redden it: **M2a** (`firstIndex` ignored: every row slides
/// up by 30).
@MainActor
@Test func aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight() throws {
    let table = StateTable()
    table.withState(lHostScroller, initial: ScrollState()) { $0.offset = 50 }
    let frame = LayoutDifferential.render(authority: .proposal, width: 100, height: 100,
                                          stateTable: table, frames: 2) {
        lScrolledHost { List(lItems(20), rowHeight: lpx(10)) { _ in Box() }.width(lpx(100)) }
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
/// Mutations that must redden it: **M2e** (the windowed node's
/// `recordLoweredItem` dropped), **M2f** (the rows' records not consumed).
@MainActor
@Test func theListSiteReportsNothingAndItsRowsItemFieldsAreLowered() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 200, height: 200) {
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

// MARK: - 2.8 Row identity is the legacy one

/// **Test 2.8** (`TB-` rulings, §4.1 row 1). The windowed layout introduces no
/// identity level: `ListRows` is a GROUP, and the outer `Box` still reuses the
/// `List`'s own id, so a row's `GlobalElementID` is
/// `child(of: listID, name: String(describing: datum.id))` on both authorities
/// and the two `StateTable` id sets are **equal**.
///
/// The set equality is the strong half — it catches an extra level, a missing
/// level and a renamed slot at once. `rowID(4)` is asserted separately because
/// a mutation that emptied both tables would satisfy set equality alone.
///
/// Mutation that must redden it: **M2a** is not it — the ids do not depend on
/// placement. A level introduced between the `List` and its rows is what this
/// pins, which is why `ListRows` is a group and the spec says so.
@MainActor
@Test func aLoweredListsRowIdentitiesAreTheLegacyOnes() throws {
    func side(_ authority: LayoutAuthority) -> Frame {
        LayoutDifferential.render(authority: authority, width: 200, height: 200) {
            Box(style: lColumn(width: 100)) {
                List(lItems(6), rowHeight: lpx(10)) { _ in Box() }
            }
        }
    }
    let legacy = side(.legacy), lowered = side(.proposal)
    try #require(lowered.unlowerableFields.isEmpty, "\(lowered.unlowerableFields)")
    let legacyOnlySlots = legacy.stateTable.ids.subtracting(lowered.stateTable.ids)
    let loweredOnlySlots = lowered.stateTable.ids.subtracting(legacy.stateTable.ids)
    #expect(legacy.stateTable.ids == lowered.stateTable.ids,
            "legacy only: \(legacyOnlySlots); lowered only: \(loweredOnlySlots)")

    let listID = lChild(lChild(lRoot, 0), 0)
    let rowID = lNamed(listID, "item-4")
    func descends(_ id: GlobalElementID, from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let current = cursor {
            if current == ancestor { return true }
            cursor = current.parent
        }
        return false
    }
    for (name, frame) in [("legacy", legacy), ("lowered", lowered)] {
        #expect(frame.stateTable.ids.contains(where: { descends($0, from: rowID) }),
                "\(name): row 4 must own at least one StateTable entry under \(rowID)")
        #expect(frame.elementBounds[rowID] != nil, "\(name): row 4's bounds")
    }
}
