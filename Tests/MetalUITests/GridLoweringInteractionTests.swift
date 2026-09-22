import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
import MetalUIText
@testable import MetalUI

// Integration of plan task 7's two parallel stage-2 tracks (record §23): the
// engine track's legacy LOWERING (`docs/record/21-engine-replacement-stage-2.md`,
// rulings `LR-AB`…`LR-BA`) and the grids track's `Grid`/`GridRow`
// (`docs/record/22-grids.md`, rulings `GR-A`…`GR-AT`). Neither track could run
// these: each holds only its own half.
//
// The two meet at exactly one seam — a kernel node under the **proposal layout
// authority**, where a lowered legacy element and a grid are both simply native
// nodes (ruling `LR-T`). Three consequences, none of which either track's suite
// can see:
//
// 1. a grid cell whose content the lowering produced is measured TWICE, at the
//    nil/served proposal and again at its slot, so stage 2's greedy item frame W
//    answers a width the GRID chose (X1);
// 2. a grid inside a lowered legacy container is a child with **no `LoweredItem`
//    record**, so the container's item lowering skips it entirely — it is never
//    stretched, grown or margined, while its recorded siblings are (X2);
// 3. a lowered `Text` and a `ProposalText` share one measurement (`LR-F`, lane
//    3's clamp), so two cells of one grid column that spell the same string the
//    two different ways size that column identically (X3);
// 4. a grid consumes no item record, so an item field declared on a top-level
//    cell reports `<site>.<field>.unconsumed` rather than silently doing nothing
//    (X4, ruling `LR-AQ`).
//
// **Geometry is hand-derived before the run** (practices): every extent an
// alignment divides is even, and each test's doc comment carries the derivation.
// Each test names the mutation that reddens it; record §23 names what each
// reddened.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

/// A fixed-size childless `Box`.
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(px(w)).height(px(h))
}

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// The proposal frame's diagnostics for `make()` inside a `width`×`height` harness root.
@MainActor
private func report<C: ElementGroup>(width: Float = 300, height: Float = 200,
                                     @ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(authority: .proposal, width: width, height: height, make).unlowerableFields
}

/// A legacy element placed where a **proposal** container expects proposal content
/// — here, as a grid cell. Under the proposal authority a lowered legacy element
/// registers only native nodes (ruling `LR-T`), so the typed entry mints its ids
/// through the internal initializer (`ProposalNodeID.swift`'s hole 3, open to
/// `@testable` code). Layout- and identity-transparent: it advances no cursor of
/// its own, so its content numbers from 0 under whatever encloses it.
///
/// A copy of `LoweringItemTests.swift`'s, deliberately: this file adds no member
/// to a shared one, and a copy of a pinned helper is pinned by this file's own
/// mutations (practices, "a copy of a pinned implementation is unpinned").
@MainActor
private struct LegacyUnderProposal<Content: ElementGroup>: ProposalElementGroup {
    var content: Content

    init(_ content: Content) { self.content = content }

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], Content.GroupLayout) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes.map { ProposalNodeID($0) }, layout)
    }

    mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                             pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

// MARK: - X1 — a grid's column width reaches stage 2's greedy item frame

/// **X1.** A grid cell that is a lowered legacy container with a **growing** child:
/// the grower fills the width the GRID gave the cell, not the width the cell
/// answered on its own.
///
/// This is the seam. The grids track measures a cell at nil (or at its served
/// share) and then, when the slot it ends up with differs from that answer,
/// measures it AGAIN at the slot (`nativeGridCellRects`). The engine track lowers
/// `flexGrow` to a greedy item frame W whose answer depends on the proposal
/// (`LR-AE`). Neither track has a cell whose content is lowered, so neither can
/// see that the second measurement re-runs the whole distribution.
///
/// Tree, in a 120×40 harness root so the grid's own proposal is 120×40:
///
/// ```
/// Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
///     GridRow { LegacyUnderProposal(Row { fixed(20, 10); Box().height(10).flexGrow(1) }) }
///     GridRow { LegacyUnderProposal(fixed(50, 12)) }
/// }
/// ```
///
/// Derivation. One column. The `Row` cell is flexible (its grower answers its
/// proposal), so the finite solve serves it the whole 120 and it answers 120×10;
/// the `fixed(50, 12)` cell is rigid at 50×12. Column 0 = max(120, 50) = **120**;
/// row heights 10 and 12; `vgap[1]` = 10, so the grid is 120 × 32 and the second
/// row starts at y = 20.
///
/// - the `Row` cell's slot (120×10) equals its answer, so it is placed at the
///   proposal it was measured at: **(0, 0, 120, 10)**;
/// - the rigid cell's slot (120×12) does NOT equal its answer (50×12), so it is
///   re-measured at 120×12, still answers 50×12, and `.topLeading` puts it at
///   **(0, 20, 50, 12)** — the control: a rigid cell does not grow to its slot;
/// - inside the `Row`, the lowered stack is offered 120: `fixed` takes its natural
///   20 and the one grower takes the surplus, so the grower's W is **(20, 0, 100,
///   10)** and `fixed` is **(0, 0, 20, 10)**. The grower's element rect IS W's
///   (the stretch/grow alias, `LR-AB` item 3).
///
/// Mutations that must redden it: the grid's `GV-1` (`nativeGridCellRects` always
/// places at the recorded proposal), and the lowering's `M2a` (W greedy on the
/// cross axis instead of the main one). The first breaks the rigid cell's arm,
/// the second the grower's.
@MainActor
@Test func aGridsColumnWidthReachesAGrowingChildInsideALoweredCell() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 120, height: 40) {
        Grid(alignment: .topLeading, horizontalSpacing: px(10), verticalSpacing: px(10)) {
            GridRow {
                LegacyUnderProposal(Row {
                    fixed(20, 10)
                    Box().height(px(10)).flexGrow(1)
                })
            }
            GridRow { LegacyUnderProposal(fixed(50, 12)) }
        }
    }
    try #require(frame.unlowerableFields.isEmpty, "the tree must lower whole: \(frame.unlowerableFields)")

    let grid = child(rootID, 0)
    let loweredRow = child(child(grid, 0), 0)
    let rigidCell = child(child(grid, 1), 0)

    #expect(frame.elementBounds[grid] == bounds(0, 0, 120, 32), "the grid")
    #expect(frame.elementBounds[loweredRow] == bounds(0, 0, 120, 10), "the lowered cell fills its slot")
    #expect(frame.elementBounds[rigidCell] == bounds(0, 20, 50, 12), "a rigid cell does not")
    #expect(frame.elementBounds[child(loweredRow, 0)] == bounds(0, 0, 20, 10), "the fixed sibling")
    #expect(frame.elementBounds[child(loweredRow, 1)] == bounds(20, 0, 100, 10),
            "the grower takes the surplus of the width the GRID chose")
}

// MARK: - X2 — a grid inside a lowered legacy container is not an item

/// **X2.** A `Grid` placed inside a lowered legacy container registers no
/// `LoweredItem`, so `planLegacyItems` gives it an empty plan: it is never
/// stretched, grown, margined or wrapped, while a recorded sibling in the same
/// container is.
///
/// Under the LEGACY authority this tree traps (`SA-G`: a native node under a
/// legacy node), so it is rendered under the proposal authority only and has no
/// legacy side to differ from. That is the point: the grids track's elements only
/// became reachable from a legacy container when the engine track's authority
/// landed.
///
/// Tree, in a 300×200 harness root:
///
/// ```
/// Row { fixed(20, 10); Box().width(15); Grid(.topLeading, h: 10, v: 10) { GridRow { 30×10; 40×10 } } }
///     .alignItems(.stretch).height(40)
/// ```
///
/// Derivation. The `Row` declares height 40, so its lowered fixed frame proposes
/// (nil, 40) to the stack and the line is 40 deep.
///
/// - `fixed(20, 10)` declares its cross size, so `crossAuto` is false and it is
///   NOT stretched: **(0, 0, 20, 10)**;
/// - `Box().width(15)` leaves its height `auto` and the parent stretches, so it
///   gets a greedy vertical W and fills the line: **(20, 0, 15, 40)** — the
///   control, which proves stretch is live in this very tree;
/// - the `Grid` has no record, so no W: it keeps its own answer, 30 + 10 + 40 =
///   80 wide and 10 tall, at the stack's cross factor 0: **(35, 0, 80, 10)**;
/// - its two cells at **(35, 0, 30, 10)** and **(75, 0, 40, 10)**;
/// - the `Row` is 20 + 15 + 80 = 115 wide by its declared 40: **(0, 0, 115, 40)**.
///
/// Mutation that must redden it: `planLegacyItems`' `guard let item else` arm made
/// to fall through to the recorded path with a default `LoweredItem`, so an
/// unrecorded child is stretched like a legacy one (the grid would become 40 tall).
@MainActor
@Test func aGridInsideALoweredContainerIsNeverStretchedWhereItsRecordedSiblingIs() throws {
    let frame = LayoutDifferential.render(authority: .proposal, width: 300, height: 200) {
        Row {
            fixed(20, 10)
            Box().width(px(15))
            Grid(alignment: .topLeading, horizontalSpacing: px(10), verticalSpacing: px(10)) {
                GridRow {
                    Rectangle(width: px(30), height: px(10))
                    Rectangle(width: px(40), height: px(10))
                }
            }
        }
        .alignItems(.stretch)
        .height(px(40))
    }
    try #require(frame.unlowerableFields.isEmpty, "the tree must lower whole: \(frame.unlowerableFields)")

    let row = child(rootID, 0)
    let grid = child(row, 2)
    let gridRow = child(grid, 0)

    #expect(frame.elementBounds[row] == bounds(0, 0, 115, 40), "the lowered row")
    #expect(frame.elementBounds[child(row, 0)] == bounds(0, 0, 20, 10), "a cross-sized item is not stretched")
    #expect(frame.elementBounds[child(row, 1)] == bounds(20, 0, 15, 40), "a cross-auto item IS stretched")
    #expect(frame.elementBounds[grid] == bounds(35, 0, 80, 10), "the grid keeps its own answer")
    #expect(frame.elementBounds[child(gridRow, 0)] == bounds(35, 0, 30, 10), "its first cell")
    #expect(frame.elementBounds[child(gridRow, 1)] == bounds(75, 0, 40, 10), "its second cell")
}

// MARK: - X3 — one text measurement, two spellings, one column

/// **X3.** A lowered `Text` and a `ProposalText` are measured by the same function
/// (`proposalTextMeasurement`, ruling `LR-F`, with lane 3's `min(proposal, widest
/// line)` clamp), so two cells of one grid column that spell the same string the
/// two different ways size that column identically — and a grid column is the one
/// place in the framework where the two answers are compared by arithmetic rather
/// than by a reader.
///
/// No literal width: a glyph advance is not hand-derivable. The test's content is
/// three `#require`d relations, each of which a de-unified measurement breaks:
///
/// - both cells answer the **same** width, and that width is the column's;
/// - the column is narrower than the 300 the grid is offered, so the clamp is the
///   thing being read and not the proposal;
/// - a longer string in the same shape gives a **wider** column (the control: the
///   equality above is not two zeroes agreeing).
///
/// The two rows also prove the column is sized from the cells and not from the
/// first one alone: swapping the order must not move it, which the second arm does.
///
/// Mutation that must redden it: `Text`'s lowered leaf measured by anything but
/// `proposalTextMeasurement` — e.g. its clamp dropped on the lowered path only
/// (`min(proposal, widest)` → `widest`) — after which the two rows disagree.
@MainActor
@Test func aLoweredTextAndAProposalTextSizeOneGridColumnIdentically() throws {
    // `EitherGroup` does not conform to `ProposalElementGroup`, so the two
    // orderings are two trees, not a builder `if`.
    @MainActor
    func widths(_ frame: Frame, loweredFirst: Bool) throws -> (legacy: Float, proposal: Float, grid: Float) {
        try #require(frame.unlowerableFields.isEmpty, "the tree must lower whole: \(frame.unlowerableFields)")
        let grid = child(rootID, 0)
        let first = try #require(frame.elementBounds[child(child(grid, 0), 0)], "the first row's cell")
        let second = try #require(frame.elementBounds[child(child(grid, 1), 0)], "the second row's cell")
        let gridBounds = try #require(frame.elementBounds[grid], "the grid")
        return loweredFirst
            ? (legacy: first.size.width.value, proposal: second.size.width.value,
               grid: gridBounds.size.width.value)
            : (legacy: second.size.width.value, proposal: first.size.width.value,
               grid: gridBounds.size.width.value)
    }

    @MainActor
    func loweredFirst(_ string: String, offer: Float = 300) throws -> (legacy: Float, proposal: Float, grid: Float) {
        try widths(LayoutDifferential.render(authority: .proposal, width: offer, height: 100) {
            Grid(alignment: .topLeading, horizontalSpacing: px(10), verticalSpacing: px(10)) {
                GridRow { LegacyUnderProposal(Text(string)) }
                GridRow { Text(string).proposalLayout() }
            }
        }, loweredFirst: true)
    }

    @MainActor
    func proposalFirst(_ string: String) throws -> (legacy: Float, proposal: Float, grid: Float) {
        try widths(LayoutDifferential.render(authority: .proposal, width: 300, height: 100) {
            Grid(alignment: .topLeading, horizontalSpacing: px(10), verticalSpacing: px(10)) {
                GridRow { Text(string).proposalLayout() }
                GridRow { LegacyUnderProposal(Text(string)) }
            }
        }, loweredFirst: false)
    }

    let short = try loweredFirst("alpha bravo")
    try #require(short.legacy > 0, "the lowered Text must measure something")
    try #require(short.legacy < 300, "the column must be the clamp's answer, not the grid's offer")
    #expect(short.legacy == short.proposal, "one measurement, two spellings")
    #expect(short.grid == short.legacy, "the column is that width")

    let swapped = try proposalFirst("alpha bravo")
    #expect(swapped.grid == short.grid, "the order of the two spellings does not move the column")

    let long = try loweredFirst("alpha bravo charlie delta echo")
    try #require(long.grid > short.grid, "the control: a longer string must widen the column")
    #expect(long.legacy == long.proposal, "one measurement, two spellings, at a second width")

    // The clamp's own arms, on both sides of its boundary, and the reason this
    // test exists. A word far wider than the grid's offer: the typesetter breaks
    // INSIDE it, and the line it produces can be wider than the offer — one
    // character plus the space it hangs (stage 1's T3/T4 read 11.18 against a
    // proposal of 5). `min(proposal, widest line)` is the only thing that makes
    // the answer the offer there.
    //
    // **Measured, not assumed, and this is the arm that had no owner.** Dropping
    // that clamp from the lowered `Text` alone left all 1548 merged tests green
    // (mutation XM4) until this arm existed: lane 3 pinned the clamp through
    // `ProposalText`, and no test reached it through a lowered `Text`. At an offer
    // of 12 or 16 the broken line already fits (12 and 15), so only a very narrow
    // offer discriminates.
    let word = "supercalifragilisticexpialidocious"
    let clamped = try loweredFirst(word, offer: 5)
    #expect(clamped.legacy == 5, "the lowered Text is clamped to the grid's offer")
    #expect(clamped.proposal == 5, "and so is the ProposalText")
    #expect(clamped.grid == 5, "so the column is the offer")

    let unclamped = try loweredFirst(word, offer: 16)
    try #require(unclamped.grid < 16, "the control: at 16 the broken line fits, so no clamp applies")
    #expect(unclamped.legacy == unclamped.proposal, "and the two spellings still agree there")
}

// MARK: - X4 — a grid consumes no item record

/// **X4.** A grid is a proposal container, not a flex parent: it consumes no
/// `LoweredItem`, so an item field declared on a top-level cell is reported
/// `<site>.<field>.unconsumed` (ruling `LR-AQ`) rather than silently doing nothing.
///
/// `LR-AQ` exists precisely so a lowering site that receives children and forgets
/// to consume them cannot make its children's fields go quiet. A `Grid` is the
/// first container in the tree that receives lowered children and legitimately
/// consumes nothing, so this is the ruling's first real case rather than a
/// diagnostic about a bug — and it is what an author will hit, because
/// `.flexGrow(1)` on a grid cell compiles.
///
/// One arm per field the report names, each compared with a control arm that
/// declares the same element with no item field and must report nothing. The
/// enclosing `GridRow` is a proposal group and consumes nothing either, so the
/// report is the grid's behaviour and not the row's.
///
/// Mutation that must redden it: `Grid.requestProposalLayout` made to consume its
/// children's records (`children.forEach { _ = pass.frame.lowering.consume($0.layoutNodeID) }`),
/// after which every arm reports nothing.
@MainActor
@Test func anItemFieldOnAGridCellIsReportedUnconsumed() throws {
    func field(_ name: String) -> UnlowerableField { UnlowerableField(site: .box, field: name) }

    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10)) } } } == [],
            "the control: a cell with no item field reports nothing")

    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10).flexGrow(1)) } } }
            == [field("flexGrow.unconsumed")], "flexGrow")
    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10).flexShrink(0)) } } }
            == [field("flexShrink.unconsumed")], "flexShrink")
    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10).alignSelf(.flexEnd)) } } }
            == [field("alignSelf.unconsumed")], "alignSelf")
    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10).margin(px(3))) } } }
            == [field("margin.unconsumed")], "margin")
    #expect(report { Grid { GridRow { LegacyUnderProposal(fixed(20, 10).minWidth(px(5))) } } }
            == [field("minSize.unconsumed")], "minSize")
}
