import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 1 ("the plan and the nil proposal") of
// `docs/superpowers/specs/2026-09-17-grids-design.md`: rulings GR-A, GR-C, GR-D,
// GR-F at nil (without the column sum), GR-G's grid and row alignment, GR-R's
// edges and Spacer marks, GR-T's row marks and GR-W (the stack arms are
// measured, not placed, in this lane) in
// `docs/superpowers/2026-09-17-grids-decisions.md`.
//
// Every arm name and number is SwiftUI's, read by `docs/probes/swiftui-grid.swift`
// (revision 5), whose header holds the recorded output. The leaves are the
// probe's (`fx`, `fl`, `hf`, `fw`, `fh`, `cb`, `cw`, `ch`, `odd`); a probe
// `Spacer()` is `newNativeSpacer()` (its 8pt default minimum); a `GridRow` is
// `markNativeGridRow` over its cells before the grid registers; a
// `gridCellColumns(n)` is `markNativeGridCell(_:columns:)`. A root is measured
// at the arm's proposal and laid out at that proposal in bounds of its own
// answer at the origin, as the probe's `Probe` layout places the view under
// test; a rect is compared with `roundLayout` of the probe's rect.

/// A leaf's distinct proposals, in the order first asked, and its call count.
private final class ProposalLog: @unchecked Sendable {
    var proposals: [ProposedSize] = []
    var calls = 0
    func record(_ proposal: ProposedSize) {
        calls += 1
        if !proposals.contains(proposal) { proposals.append(proposal) }
    }
}

/// One child of a grid arm: a row of cells (a `GridRow`) or a non-row child.
private enum GridChild {
    case row([LayoutNodeID], ProposalAlignment?)
    case full(LayoutNodeID)
}

private func row(_ cells: LayoutNodeID..., alignment: ProposalAlignment? = nil) -> GridChild {
    .row(cells, alignment)
}

/// One probe arm: a tree, its named nodes and their logs.
private final class Arm {
    let tree = LayoutTree(generation: 0)
    private var nodes: [String: LayoutNodeID] = [:]
    private var logs: [String: ProposalLog] = [:]

    func leaf(_ name: String, _ answer: @escaping @Sendable (ProposedSize) -> SizeD) -> LayoutNodeID {
        let log = ProposalLog()
        let id = tree.newNativeLeaf { proposal in
            log.record(proposal)
            return LayoutMeasurement(size: answer(proposal))
        }
        nodes[name] = id
        logs[name] = log
        return id
    }

    /// `fx`: fixed.
    func fx(_ name: String, _ w: Double, _ h: Double) -> LayoutNodeID { leaf(name) { _ in SizeD(width: w, height: h) } }
    /// `fl`: proposal ?? 10 on both axes.
    func fl(_ name: String) -> LayoutNodeID { leaf(name) { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) } }
    /// `hf`: half the proposed width (40 at nil), height 10.
    func hf(_ name: String) -> LayoutNodeID { leaf(name) { SizeD(width: ($0.width ?? 40) / 2, height: 10) } }
    /// `fh`: fixed width, height proposal ?? 10.
    func fh(_ name: String, _ w: Double = 20) -> LayoutNodeID { leaf(name) { SizeD(width: w, height: $0.height ?? 10) } }
    /// `cb`: clamp(proposal ?? 10, lo, hi) on both axes.
    func cb(_ name: String, _ lo: Double, _ hi: Double) -> LayoutNodeID {
        leaf(name) { SizeD(width: Swift.min(Swift.max($0.width ?? 10, lo), hi), height: Swift.min(Swift.max($0.height ?? 10, lo), hi)) }
    }
    /// `cw`: width clamp(proposal ?? 10, lo, hi), fixed height.
    func cw(_ name: String, _ lo: Double, _ hi: Double, _ h: Double = 10) -> LayoutNodeID {
        leaf(name) { SizeD(width: Swift.min(Swift.max($0.width ?? 10, lo), hi), height: h) }
    }
    /// `odd`: 20×20, except exactly 15×15 when proposed exactly 20×20.
    func odd(_ name: String) -> LayoutNodeID {
        leaf(name) { ($0.width == 20 && $0.height == 20) ? SizeD(width: 15, height: 15) : SizeD(width: 20, height: 20) }
    }

    func spacer(_ name: String) -> LayoutNodeID { self.name(tree.newNativeSpacer(), name) }

    func span(_ node: LayoutNodeID, _ columns: Int) -> LayoutNodeID {
        tree.markNativeGridCell(node, columns: columns)
        return node
    }

    /// Marks each row child, then registers the grid over every child's nodes,
    /// named "grid".
    func grid(alignment: ProposalAlignment = .center,
              h: Double? = nil, v: Double? = nil, _ children: [GridChild]) -> LayoutNodeID {
        var cells: [LayoutNodeID] = []
        for child in children {
            switch child {
            case let .row(nodes, rowAlignment):
                tree.markNativeGridRow(nodes, alignment: rowAlignment)
                cells += nodes
            case let .full(node):
                cells.append(node)
            }
        }
        return self.name(tree.newNativeGrid(children: cells, alignment: alignment,
                                            horizontalSpacing: h, verticalSpacing: v), "grid")
    }

    /// A stack at `spacing: nil`, the platform default per pair (`HStack {}`).
    func hstack(_ name: String, _ children: [LayoutNodeID], spacing: Double? = nil) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .horizontal, spacing: spacing), name)
    }

    func vstack(_ name: String, _ children: [LayoutNodeID], spacing: Double? = nil) -> LayoutNodeID {
        self.name(tree.newNativeLinearStack(children: children, axis: .vertical, spacing: spacing), name)
    }

    @discardableResult
    func name(_ id: LayoutNodeID, _ name: String) -> LayoutNodeID {
        nodes[name] = id
        return id
    }

    /// Measures `root` at `proposal`, then lays it out at `proposal` in bounds
    /// of its answer at the origin, and returns the answer.
    @discardableResult
    func run(_ root: LayoutNodeID, _ width: Double?, _ height: Double?) -> SizeD {
        let proposal = ProposedSize(width: width, height: height)
        let answer = tree.measureNativeLayout(root: root, proposal: proposal).size
        tree.computeNativeLayout(root: root, proposal: proposal,
                                 in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
        return answer
    }

    /// Measures only.
    func measure(_ root: LayoutNodeID, _ width: Double?, _ height: Double?) -> SizeD {
        tree.measureNativeLayout(root: root, proposal: ProposedSize(width: width, height: height)).size
    }

    subscript(_ name: String) -> LayoutRect { tree.layout(nodes[name]!) }
    func node(_ name: String) -> LayoutNodeID { nodes[name]! }
    func proposals(_ name: String) -> [ProposedSize] { logs[name]!.proposals }
    func plan() -> NativeGridPlan? { tree.nativeGridPlan(nodes["grid"]!) }
}

/// The probe's rect, rounded as the kernel stores rects.
private func r(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> LayoutRect {
    roundLayout([LayoutRect(x: x, y: y, width: width, height: height)])[0]
}

private func size(_ width: Double, _ height: Double) -> SizeD { SizeD(width: width, height: height) }

private let none = ProposedSize(width: nil, height: nil)

// MARK: - 1.1 columns and rows

/// GR-C: a column is as wide as its widest single-column cell, a row as tall as
/// its tallest cell; a cell sits centred in its slot; the answer is the sums
/// plus gaps.
///
/// - GA1 `Grid{[a 30x10, b 20x20] [c 10x30, d 40x10]}` at nil: 78×58, b at 48
///   (column 1 is d's 40), c at 10 (column 0 is a's 30).
/// - GA4, unequal rows `[a 30x10, b 20x20, e 5x5] [c 10x30]`: 71×58; the short
///   row's missing cells are empty.
/// - GP3 `[a fl, b 20x20] [c 10x30, d 40x10]` at nil: 58×58, a measured 10×10
///   at nil and placed at its 10×20 slot.
///
/// Mutation: take a column's width from its first cell, not the widest (GA1's b
/// at 38, the answer 58 wide).
@Test func aGridSizesColumnsFromTheWidestCellAndRowsFromTheTallest() {
    do { // GA1
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(78, 58), "GA1 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GA1 a")
        #expect(arm["b"] == r(48, 0, 20, 20), "GA1 b")
        #expect(arm["c"] == r(10, 28, 10, 30), "GA1 c")
        #expect(arm["d"] == r(38, 38, 40, 10), "GA1 d")
    }
    do { // GA4
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5)),
                             row(arm.fx("c", 10, 30))])
        #expect(arm.run(root, nil, nil) == size(71, 58), "GA4 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GA4 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GA4 b")
        #expect(arm["e"] == r(66, 7.5, 5, 5), "GA4 e")
        #expect(arm["c"] == r(10, 28, 10, 30), "GA4 c")
    }
    do { // GP3
        let arm = Arm()
        let root = arm.grid([row(arm.fl("a"), arm.fx("b", 20, 20)),
                             row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(58, 58), "GP3 size")
        #expect(arm["a"] == r(0, 0, 10, 20), "GP3 a")
        #expect(arm["b"] == r(28, 0, 20, 20), "GP3 b")
        #expect(arm["c"] == r(0, 28, 10, 30), "GP3 c")
        #expect(arm["d"] == r(18, 38, 40, 10), "GP3 d")
    }
}

// MARK: - 1.2 empty grids and non-row children

/// GR-C: an empty `Grid` and a `Grid` whose only row is empty answer 0×0 (GA5,
/// GA6: `markNativeGridRow([])` marks nothing); a grid whose children are all
/// non-row children has one column (GA8: `{x 30x10; y 10x20}` at nil is 30×38,
/// y centred at 10).
///
/// Mutation: group consecutive children by token equality including nil (GA8's
/// x and y become one row, 48×20).
@Test func anEmptyGridOrRowIsNothingAndNonRowChildrenMakeOneColumn() {
    do { // GA5
        let arm = Arm()
        let root = arm.grid([])
        #expect(arm.run(root, nil, nil) == size(0, 0), "GA5 size")
        #expect(arm["grid"] == r(0, 0, 0, 0), "GA5 grid")
    }
    do { // GA6
        let arm = Arm()
        let root = arm.grid([.row([], nil)])
        #expect(arm.run(root, nil, nil) == size(0, 0), "GA6 size")
    }
    do { // GA8
        let arm = Arm()
        let root = arm.grid([.full(arm.fx("x", 30, 10)), .full(arm.fx("y", 10, 20))])
        #expect(arm.run(root, nil, nil) == size(30, 38), "GA8 size")
        #expect(arm["x"] == r(0, 0, 30, 10), "GA8 x")
        #expect(arm["y"] == r(10, 18, 10, 20), "GA8 y")
    }
}

// MARK: - 1.3 spans at nil

/// GR-F at nil: every cell is measured once; single-column cells widen their
/// columns first, then each spanning cell spreads its shortfall, in source
/// order; a non-row child spans every column; a span is clamped to the
/// columns left.
///
/// - GX1 `[a 30x10, b 20x20] [c 100x10 span 2]`: 100×38, columns 51/41.
/// - GX2 `[a, b] [c 10x10 span 2]`: 58×38, c centred in 58.
/// - GX3 `[a, b] x 100x10 (non-row) [c 10x30, d 40x10]`: 100×76, columns 41/51.
/// - GX4 `[a, b] x hf (non-row)`: x placed at its 58 slot answers 29.
/// - GX5 `[a, b, c 5x5] [x 100x10 span 2, y 1x1]`: 113×38.
/// - GX6 `[a, b] [x 10x10 span 5]`: clamped, 58×38.
/// - GX7 `[x 100x10 span 2] [a, b]`: the span declared first reads GX1's
///   columns.
///
/// Mutation: absorb each span in source order among the single-column cells
/// (GX7's a at x 8).
@Test func atANilProposalSpansWidenTheirColumnsAfterEverySingleColumnCell() {
    do { // GX1
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.span(arm.fx("c", 100, 10), 2))])
        #expect(arm.run(root, nil, nil) == size(100, 38), "GX1 size")
        #expect(arm["a"] == r(10.5, 5, 30, 10), "GX1 a")
        #expect(arm["b"] == r(69.5, 0, 20, 20), "GX1 b")
        #expect(arm["c"] == r(0, 28, 100, 10), "GX1 c")
    }
    do { // GX2
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.span(arm.fx("c", 10, 10), 2))])
        #expect(arm.run(root, nil, nil) == size(58, 38), "GX2 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GX2 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GX2 b")
        #expect(arm["c"] == r(24, 28, 10, 10), "GX2 c")
    }
    do { // GX3
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             .full(arm.fx("x", 100, 10)),
                             row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(100, 76), "GX3 size")
        #expect(arm["a"] == r(5.5, 5, 30, 10), "GX3 a")
        #expect(arm["b"] == r(64.5, 0, 20, 20), "GX3 b")
        #expect(arm["x"] == r(0, 28, 100, 10), "GX3 x")
        #expect(arm["c"] == r(15.5, 46, 10, 30), "GX3 c")
        #expect(arm["d"] == r(54.5, 56, 40, 10), "GX3 d")
    }
    do { // GX4
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), .full(arm.hf("x"))])
        #expect(arm.run(root, nil, nil) == size(58, 38), "GX4 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GX4 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GX4 b")
        #expect(arm["x"] == r(14.5, 28, 29, 10), "GX4 x")
    }
    do { // GX5
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("c", 5, 5)),
                             row(arm.span(arm.fx("x", 100, 10), 2), arm.fx("y", 1, 1))])
        #expect(arm.run(root, nil, nil) == size(113, 38), "GX5 size")
        #expect(arm["a"] == r(10.5, 5, 30, 10), "GX5 a")
        #expect(arm["b"] == r(69.5, 0, 20, 20), "GX5 b")
        #expect(arm["c"] == r(108, 7.5, 5, 5), "GX5 c")
        #expect(arm["x"] == r(0, 28, 100, 10), "GX5 x")
        #expect(arm["y"] == r(110, 32.5, 1, 1), "GX5 y")
    }
    do { // GX6
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.span(arm.fx("x", 10, 10), 5))])
        #expect(arm.run(root, nil, nil) == size(58, 38), "GX6 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GX6 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GX6 b")
        #expect(arm["x"] == r(24, 28, 10, 10), "GX6 x")
    }
    do { // GX7
        let arm = Arm()
        let root = arm.grid([row(arm.span(arm.fx("x", 100, 10), 2)),
                             row(arm.fx("a", 30, 10), arm.fx("b", 20, 20))])
        #expect(arm.run(root, nil, nil) == size(100, 38), "GX7 size")
        #expect(arm["x"] == r(0, 0, 100, 10), "GX7 x")
        #expect(arm["a"] == r(10.5, 23, 30, 10), "GX7 a")
        #expect(arm["b"] == r(69.5, 18, 20, 20), "GX7 b")
    }
}

// MARK: - 1.4 where a span's shortfall goes at nil

/// GR-F at nil: a span's shortfall goes to the spanned columns that hold no
/// single-column cell anywhere in the grid, when there are any.
///
/// GX11 `[a cb(0,100), b 100x40 span 2, c cw(30,40,40) span 2] [d fh(10) span
/// 2, e fh(10), f cw(30,180,10)]` at nil: 156×58. b spans columns 1 and 2;
/// column 2 holds e, so column 1 takes all of b's 82 and column 2 stays 10.
///
/// Mutation: spread over every spanned column (column 1 41, column 2 51).
@Test func aSpanShortfallAtNilGoesFirstToSpannedColumnsWithNoSingleColumnCell() {
    let arm = Arm()
    let root = arm.grid([row(arm.cb("a", 0, 100), arm.span(arm.fx("b", 100, 40), 2), arm.span(arm.cw("c", 30, 40, 40), 2)),
                         row(arm.span(arm.fh("d", 10), 2), arm.fh("e", 10), arm.cw("f", 30, 180, 10))])
    #expect(arm.run(root, nil, nil) == size(156, 58), "GX11 size")
    #expect(arm["a"] == r(0, 0, 10, 40), "GX11 a")
    #expect(arm["b"] == r(18, 0, 100, 40), "GX11 b")
    #expect(arm["c"] == r(126, 0, 30, 40), "GX11 c")
    #expect(arm["d"] == r(45, 48, 10, 10), "GX11 d")
    #expect(arm["e"] == r(108, 48, 10, 10), "GX11 e")
    #expect(arm["f"] == r(126, 48, 30, 10), "GX11 f")
}

// MARK: - 1.5 the placement proposal

/// GR-C: a cell whose slot equals its answer is placed at the proposal that
/// answer was measured at, not at its slot.
///
/// - GR0, the control: an `odd` leaf proposed exactly 20×20 answers 15×15 (in a
///   fixed 20×20 frame it sits at (2.5, 2.5)); required first, or GR1 cannot
///   tell the two proposals apart.
/// - GR1 `[a odd, b 20x20]` at nil: a answers 20×20 at nil, its slot is 20×20,
///   and it is placed at nil: 20×20 at the origin.
/// - GP3's c (10×30 in a 10×30 slot) is never asked anything but nil.
///
/// Mutation: always place at the slot size (GR1's a reads 15×15 at (2.5, 2.5)).
@Test func aCellWhoseSlotEqualsItsAnswerIsPlacedAtTheProposalItWasMeasuredAt() throws {
    do { // GR0
        let arm = Arm()
        let root = arm.tree.newNativeFrame(child: arm.odd("a"), width: 20, height: 20)
        try #require(arm.run(root, nil, nil) == size(20, 20), "GR0 size")
        try #require(arm["a"] == r(2.5, 2.5, 15, 15), "GR0 a: odd answers 15×15 at exactly 20×20")
    }
    do { // GR1
        let arm = Arm()
        let root = arm.grid([row(arm.odd("a"), arm.fx("b", 20, 20))])
        #expect(arm.run(root, nil, nil) == size(48, 20), "GR1 size")
        #expect(arm["a"] == r(0, 0, 20, 20), "GR1 a")
        #expect(arm["b"] == r(28, 0, 20, 20), "GR1 b")
        #expect(arm.proposals("a") == [none], "GR1 a is asked nil only")
    }
    do { // GP3's c
        let arm = Arm()
        let root = arm.grid([row(arm.fl("a"), arm.fx("b", 20, 20)),
                             row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        arm.run(root, nil, nil)
        #expect(arm.proposals("c") == [none], "GP3 c is placed at nil")
        #expect(arm.proposals("a") == [none, ProposedSize(width: 10, height: 20)], "GP3 a is placed at its slot")
    }
}

// MARK: - 1.6 gaps

/// GR-D: the gap before column j is the largest pair spacing of adjacent cells
/// in one row meeting at j, 0 where no pair meets; the gap before row r the
/// largest over cells covering one column in rows r−1 and r. A pair's spacing
/// is the explicit spacing if given, else 0 beside a zero-spacing edge (a
/// Spacer's, through a frame, a one-child stack or ZStack, a zero padding
/// inset, not an overlay's content side), else 8. Read from the plan
/// (`hgap[0]` and `vgap[0]` are 0 by construction).
///
/// - GS1 `[Spacer, b] [c, d]`: 8 (c|d) and 8 (b over d).
/// - GS2 `[a, Spacer, c]`: 0, 0; GS3 (an 8×8 leaf instead): 8, 8 — required to
///   differ.
/// - GS4 `[a hf] [Spacer, c]`: no pair meets at column 1 in row 0 and the
///   Spacer's is 0; row 1 sits under a Spacer (0) and nothing (0).
/// - GS5 `[a 40x40] [b hf, c span 2] [d]`: column 2 has no pair: 8, 0; rows 8, 8.
/// - GS11 `[a, Spacer, c]` at horizontal spacing 12: 12, 12.
/// - GS12 `Spacer.frame(width: 8)`: 0, 0. GS13 `Spacer.padding(.leading, 4)`:
///   8, 0. GS14 `HStack(spacing: 0){Spacer}`: 0, 0. GS15 `ZStack{Spacer}`: 0, 0.
///   GS16 an 8×8 leaf with a Spacer overlay: 8, 8. GS17 `[a] [Spacer.frame(height:
///   8)] [c]`: 0, 0. GS18 its control with an 8×8 leaf: 8, 8.
/// - GS6 (GS5 at nil) laid out: 68×136; GQ6 (GS1 at nil): 58×58.
///
/// Mutation: `platformDefault` before every column j ≥ 1 regardless of pairs
/// and edges (GS2's plan reads 8, 8; GS6 reads 76).
@Test func eachGapIsTheLargestPairSpacingMeetingThere() throws {
    func gaps(_ build: (Arm) -> LayoutNodeID) throws -> (h: [Double], v: [Double]) {
        let arm = Arm()
        _ = build(arm)
        let plan = try #require(arm.plan())
        return (plan.hgap, plan.vgap)
    }
    let gs1 = try gaps { a in a.grid([row(a.spacer("s"), a.fx("b", 20, 20)), row(a.fx("c", 10, 30), a.fx("d", 40, 10))]) }
    #expect(gs1.h == [0, 8] && gs1.v == [0, 8], "GS1 \(gs1)")
    let gs2 = try gaps { a in a.grid([row(a.fx("a", 30, 10), a.spacer("s"), a.fh("c", 10))]) }
    let gs3 = try gaps { a in a.grid([row(a.fx("a", 30, 10), a.fx("s", 8, 8), a.fh("c", 10))]) }
    try #require(gs2.h != gs3.h, "GS2 and its control GS3 must differ")
    #expect(gs2.h == [0, 0, 0] && gs2.v == [0], "GS2 \(gs2)")
    #expect(gs3.h == [0, 8, 8], "GS3 \(gs3)")
    let gs4 = try gaps { a in a.grid([row(a.hf("a")), row(a.spacer("s"), a.cw("c", 30, 180, 20))]) }
    #expect(gs4.h == [0, 0] && gs4.v == [0, 0], "GS4 \(gs4)")
    let gs5 = try gaps { a in
        a.grid([row(a.fx("a", 40, 40)), row(a.hf("b"), a.span(a.fx("c", 20, 40), 2)), row(a.cw("d", 0, 30, 40))])
    }
    #expect(gs5.h == [0, 8, 0] && gs5.v == [0, 8, 8], "GS5 \(gs5)")
    let gs11 = try gaps { a in a.grid(h: 12, [row(a.fx("a", 30, 10), a.spacer("s"), a.fx("c", 10, 10))]) }
    #expect(gs11.h == [0, 12, 12], "GS11 \(gs11)")
    let gs12 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10), a.tree.newNativeFrame(child: a.spacer("s"), width: 8), a.fx("c", 10, 10))])
    }
    #expect(gs12.h == [0, 0, 0], "GS12 \(gs12)")
    let gs13 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10), a.tree.newNativePadding(child: a.spacer("s"), insets: Edges(top: 0, right: 0, bottom: 0, left: 4)),
                    a.fx("c", 10, 10))])
    }
    #expect(gs13.h == [0, 8, 0], "GS13 \(gs13)")
    let gs14 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10), a.hstack("h", [a.spacer("s")], spacing: 0), a.fx("c", 10, 10))])
    }
    #expect(gs14.h == [0, 0, 0], "GS14 \(gs14)")
    let gs15 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10), a.tree.newNativeOverlay(children: [a.spacer("s")]), a.fx("c", 10, 10))])
    }
    #expect(gs15.h == [0, 0, 0], "GS15 \(gs15)")
    let gs16 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10), a.tree.newNativeOverlayAttachment(child: a.fx("l", 8, 8), overlay: a.spacer("s")),
                    a.fx("c", 10, 10))])
    }
    #expect(gs16.h == [0, 8, 8], "GS16 \(gs16)")
    let gs17 = try gaps { a in
        a.grid([row(a.fx("a", 30, 10)), row(a.tree.newNativeFrame(child: a.spacer("s"), height: 8)), row(a.fx("c", 10, 10))])
    }
    #expect(gs17.v == [0, 0, 0] && gs17.h == [0], "GS17 \(gs17)")
    let gs18 = try gaps { a in a.grid([row(a.fx("a", 30, 10)), row(a.fx("s", 8, 8)), row(a.fx("c", 10, 10))]) }
    #expect(gs18.v == [0, 8, 8], "GS18 \(gs18)")

    do { // GS6
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 40, 40)), row(arm.hf("b"), arm.span(arm.fx("c", 20, 40), 2)),
                             row(arm.cw("d", 0, 30, 40))])
        #expect(arm.run(root, nil, nil) == size(68, 136), "GS6 size")
        #expect(arm["a"] == r(0, 0, 40, 40), "GS6 a")
        #expect(arm["b"] == r(10, 63, 20, 10), "GS6 b")
        #expect(arm["c"] == r(48, 48, 20, 40), "GS6 c")
        #expect(arm["d"] == r(5, 96, 30, 40), "GS6 d")
    }
    do { // GQ6
        let arm = Arm()
        let root = arm.grid([row(arm.spacer("s"), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(58, 58), "GQ6 size")
        #expect(arm["b"] == r(28, 0, 20, 20), "GQ6 b")
        #expect(arm["c"] == r(0, 28, 10, 30), "GQ6 c")
        #expect(arm["d"] == r(18, 38, 40, 10), "GQ6 d")
        #expect(arm["s"] == r(0, 0, 10, 20), "GQ6 s")
    }
}

// MARK: - 1.7 explicit spacing

/// GR-D: explicit spacing is verbatim on each axis, and negative spacing is
/// accepted unclamped.
///
/// - GA2, GA1 at 0/0: 70×50. GA3 at 3/5: 73×55. GS8 at −10/−5: 60×45.
///
/// Mutation: clamp a given spacing at 0 (GS8 reads 70×50).
@Test func explicitGridSpacingIsVerbatimAndNegativeSpacingIsAccepted() {
    func ga1(_ arm: Arm, _ h: Double, _ v: Double) -> LayoutNodeID {
        arm.grid(h: h, v: v, [row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
    }
    do { // GA2
        let arm = Arm()
        #expect(arm.run(ga1(arm, 0, 0), nil, nil) == size(70, 50), "GA2 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GA2 a")
        #expect(arm["b"] == r(40, 0, 20, 20), "GA2 b")
        #expect(arm["c"] == r(10, 20, 10, 30), "GA2 c")
        #expect(arm["d"] == r(30, 30, 40, 10), "GA2 d")
    }
    do { // GA3
        let arm = Arm()
        #expect(arm.run(ga1(arm, 3, 5), nil, nil) == size(73, 55), "GA3 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GA3 a")
        #expect(arm["b"] == r(43, 0, 20, 20), "GA3 b")
        #expect(arm["c"] == r(10, 25, 10, 30), "GA3 c")
        #expect(arm["d"] == r(33, 35, 40, 10), "GA3 d")
    }
    do { // GS8
        let arm = Arm()
        #expect(arm.run(ga1(arm, -10, -5), nil, nil) == size(60, 45), "GS8 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GS8 a")
        #expect(arm["b"] == r(30, 0, 20, 20), "GS8 b")
        #expect(arm["c"] == r(10, 15, 10, 30), "GS8 c")
        #expect(arm["d"] == r(20, 25, 40, 10), "GS8 d")
    }
}

// MARK: - 1.8 grid and row alignment

/// GR-G: `Grid(alignment:)` places cells on both axes and places non-row
/// children; a row's alignment overrides it vertically for its cells.
///
/// - GL1 GA1 at `.topLeading`; GL2 at `.bottomTrailing`; GL3 GA1 with row 0
///   `.top`; GL9 `Grid(.bottom){[row .top: a 10x10, b 10x30] [c 10x10, d
///   10x30]}`; GL12 `Grid(.leading){[a 40x10, b 10x30] x 10x10}`.
///
/// Mutation: ignore the row alignment (GL3's a at y 5).
@Test func gridAndRowAlignmentPlaceCellsInTheirSlots() {
    func ga1(_ arm: Arm, _ alignment: ProposalAlignment, row0: ProposalAlignment? = nil) -> LayoutNodeID {
        arm.grid(alignment: alignment, [row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), alignment: row0),
                                        row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
    }
    do { // GL1
        let arm = Arm()
        #expect(arm.run(ga1(arm, .topLeading), nil, nil) == size(78, 58), "GL1 size")
        #expect(arm["a"] == r(0, 0, 30, 10), "GL1 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GL1 b")
        #expect(arm["c"] == r(0, 28, 10, 30), "GL1 c")
        #expect(arm["d"] == r(38, 28, 40, 10), "GL1 d")
    }
    do { // GL2
        let arm = Arm()
        #expect(arm.run(ga1(arm, .bottomTrailing), nil, nil) == size(78, 58), "GL2 size")
        #expect(arm["a"] == r(0, 10, 30, 10), "GL2 a")
        #expect(arm["b"] == r(58, 0, 20, 20), "GL2 b")
        #expect(arm["c"] == r(20, 28, 10, 30), "GL2 c")
        #expect(arm["d"] == r(38, 48, 40, 10), "GL2 d")
    }
    do { // GL3
        let arm = Arm()
        #expect(arm.run(ga1(arm, .center, row0: .top), nil, nil) == size(78, 58), "GL3 size")
        #expect(arm["a"] == r(0, 0, 30, 10), "GL3 a")
        #expect(arm["b"] == r(48, 0, 20, 20), "GL3 b")
        #expect(arm["c"] == r(10, 28, 10, 30), "GL3 c")
        #expect(arm["d"] == r(38, 38, 40, 10), "GL3 d")
    }
    do { // GL9
        let arm = Arm()
        let root = arm.grid(alignment: .bottom, [row(arm.fx("a", 10, 10), arm.fx("b", 10, 30), alignment: .top),
                                                 row(arm.fx("c", 10, 10), arm.fx("d", 10, 30))])
        #expect(arm.run(root, nil, nil) == size(28, 68), "GL9 size")
        #expect(arm["a"] == r(0, 0, 10, 10), "GL9 a")
        #expect(arm["b"] == r(18, 0, 10, 30), "GL9 b")
        #expect(arm["c"] == r(0, 58, 10, 10), "GL9 c")
        #expect(arm["d"] == r(18, 38, 10, 30), "GL9 d")
    }
    do { // GL12
        let arm = Arm()
        let root = arm.grid(alignment: .leading, [row(arm.fx("a", 40, 10), arm.fx("b", 10, 30)), .full(arm.fx("x", 10, 10))])
        #expect(arm.run(root, nil, nil) == size(58, 48), "GL12 size")
        #expect(arm["a"] == r(0, 10, 40, 10), "GL12 a")
        #expect(arm["b"] == r(48, 0, 10, 30), "GL12 b")
        #expect(arm["x"] == r(0, 38, 10, 10), "GL12 x")
    }
}

// MARK: - 1.9 row tokens

/// GR-T and GR-A: consecutive children carrying one row token are one row, and
/// a node marked twice takes the LATER mark — an enclosing `GridRow` registers
/// after the one it contains — token and alignment both, nil included.
///
/// - GG3 `[[a, b], c 5x5]` (inner mark, then the enclosing one over all
///   three): one row, 71×20.
/// - GG10 outer `.top`, inner `.bottom` over `[a 10x10, b 10x30]`, then c
///   10x20: a at y 0. GG11 the reverse: a at y 20. GG12 outer unaligned, inner
///   `.bottom`: a at y 10, centred by the grid.
/// - GG9 `[a, b]` then a stack holding cells marked as a row: the stack is a
///   non-row child, 58×58.
/// - Two adjacent rows of equal (nil) alignment stay two rows: GA1's figures.
///
/// Mutations: (a) compare rows by alignment instead of token (the adjacent rows
/// merge); (b) keep the inner alignment when the enclosing mark's is nil (GG12's
/// a at y 20).
@Test func consecutiveCellsOfOneRowTokenAreOneRowAndTheOutermostRowMarkWins() {
    do { // GG3
        let arm = Arm()
        let a = arm.fx("a", 30, 10), b = arm.fx("b", 20, 20), c = arm.fx("c", 5, 5)
        arm.tree.markNativeGridRow([a, b])
        let root = arm.grid([row(a, b, c)])
        #expect(arm.run(root, nil, nil) == size(71, 20), "GG3 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GG3 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GG3 b")
        #expect(arm["c"] == r(66, 7.5, 5, 5), "GG3 c")
    }
    func nested(_ outer: ProposalAlignment?, _ inner: ProposalAlignment?) -> Arm {
        let arm = Arm()
        let a = arm.fx("a", 10, 10), b = arm.fx("b", 10, 30), c = arm.fx("c", 10, 20)
        arm.tree.markNativeGridRow([a, b], alignment: inner)
        arm.run(arm.grid([row(a, b, c, alignment: outer)]), nil, nil)
        return arm
    }
    do { // GG10
        let arm = nested(.top, .bottom)
        #expect(arm["grid"] == r(0, 0, 46, 30), "GG10 size")
        #expect(arm["a"] == r(0, 0, 10, 10), "GG10 a")
        #expect(arm["b"] == r(18, 0, 10, 30), "GG10 b")
        #expect(arm["c"] == r(36, 0, 10, 20), "GG10 c")
    }
    do { // GG11
        let arm = nested(.bottom, .top)
        #expect(arm["a"] == r(0, 20, 10, 10), "GG11 a")
        #expect(arm["b"] == r(18, 0, 10, 30), "GG11 b")
        #expect(arm["c"] == r(36, 10, 10, 20), "GG11 c")
    }
    do { // GG12
        let arm = nested(nil, .bottom)
        #expect(arm["a"] == r(0, 10, 10, 10), "GG12 a")
        #expect(arm["b"] == r(18, 0, 10, 30), "GG12 b")
        #expect(arm["c"] == r(36, 5, 10, 20), "GG12 c")
    }
    do { // GG9
        let arm = Arm()
        let c = arm.fx("c", 10, 30), d = arm.fx("d", 40, 10)
        arm.tree.markNativeGridRow([c, d])
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), .full(arm.hstack("h", [c, d]))])
        #expect(arm.run(root, nil, nil) == size(58, 58), "GG9 size")
        #expect(arm["a"] == r(0, 5, 30, 10), "GG9 a")
        #expect(arm["b"] == r(38, 0, 20, 20), "GG9 b")
        #expect(arm["c"] == r(0, 28, 10, 30), "GG9 c")
        #expect(arm["d"] == r(18, 38, 40, 10), "GG9 d")
    }
    do { // two adjacent rows, both unaligned
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(78, 58), "adjacent rows size")
        #expect(arm["c"] == r(10, 28, 10, 30), "adjacent rows c")
        #expect(arm["d"] == r(38, 38, 40, 10), "adjacent rows d")
    }
}

// MARK: - 1.10 a grid seen from a stack

/// GR-R: a grid's zero-spacing edges are positional — leading if a cell starting
/// at column 0 has one, trailing if a cell ending at the last column has one,
/// top and bottom over its first and last rows; an empty grid has both.
///
/// **Measured, not placed, in this lane (GR-W).** An enclosing stack places its
/// children at its measured cross size, so it would propose the grid a
/// concrete axis — the finite branch, lane 2's. The stack's answer at nil×nil
/// carries every gap the edges decide, so each arm asserts the stack answer the
/// probe reads (its rects are lane 2's, test 2.11).
///
/// - GE1 `HStack{a 30x10; Grid{[Spacer, b 20x20]}; c 10x10}`: 76×20; GE2 (the
///   Spacer an 8×8 leaf): 92×20, required to differ.
/// - GE3 `[b, Spacer]`: 76×20 (leading 8, trailing 0).
/// - GE4 `[Spacer, b] [d, e]`: 96×48. GE5 `[Spacer, b] [Spacer, e]`: 76×48.
/// - GE6 `VStack{a; Grid{[Spacer] [b]}; c}`: 30×56; GE7 (8×8 leaf): 30×72,
///   required to differ.
/// - GE16 `HStack{a; Grid{}; c}`: 40×10.
/// - GE23 `VStack{a; Grid{[Spacer, b]}; c}`: 30×40. GE24 `[b] [Spacer]`: 30×56.
/// - GE25 `HStack{a; Grid{[b] Spacer (non-row)}; c}`: 60×28. GE26 `[b, e]
///   [Spacer]`: 96×28.
///
/// Mutations: (a) answer "any cell", as `.custom` does (GE3 reads 68, GE24
/// 48); (b) answer neither edge (GE1 reads 84).
@Test func aGridSeenFromAStackHasPositionalZeroSpacingEdges() throws {
    func hArm(_ grid: (Arm) -> LayoutNodeID) -> SizeD {
        let arm = Arm()
        let a = arm.fx("a", 30, 10)
        let g = grid(arm)
        return arm.measure(arm.hstack("stack", [a, g, arm.fx("c", 10, 10)]), nil, nil)
    }
    func vArm(_ grid: (Arm) -> LayoutNodeID) -> SizeD {
        let arm = Arm()
        let a = arm.fx("a", 30, 10)
        let g = grid(arm)
        return arm.measure(arm.vstack("stack", [a, g, arm.fx("c", 10, 10)]), nil, nil)
    }
    let ge1 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20))]) }
    let ge2 = hArm { $0.grid([row($0.fx("s", 8, 8), $0.fx("b", 20, 20))]) }
    try #require(ge1 != ge2, "GE1 and its control GE2 must differ")
    #expect(ge1 == size(76, 20), "GE1 \(ge1)")
    #expect(ge2 == size(92, 20), "GE2 \(ge2)")
    let ge3 = hArm { $0.grid([row($0.fx("b", 20, 20), $0.spacer("s"))]) }
    #expect(ge3 == size(76, 20), "GE3 \(ge3)")
    let ge4 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20)), row($0.fx("d", 20, 20), $0.fx("e", 20, 20))]) }
    #expect(ge4 == size(96, 48), "GE4 \(ge4)")
    let ge5 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20)), row($0.spacer("t"), $0.fx("e", 20, 20))]) }
    #expect(ge5 == size(76, 48), "GE5 \(ge5)")
    let ge6 = vArm { $0.grid([row($0.spacer("s")), row($0.fx("b", 20, 20))]) }
    let ge7 = vArm { $0.grid([row($0.fx("s", 8, 8)), row($0.fx("b", 20, 20))]) }
    try #require(ge6 != ge7, "GE6 and its control GE7 must differ")
    #expect(ge6 == size(30, 56), "GE6 \(ge6)")
    #expect(ge7 == size(30, 72), "GE7 \(ge7)")
    let ge16 = hArm { $0.grid([]) }
    #expect(ge16 == size(40, 10), "GE16 \(ge16)")
    let ge23 = vArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20))]) }
    #expect(ge23 == size(30, 40), "GE23 \(ge23)")
    let ge24 = vArm { $0.grid([row($0.fx("b", 20, 20)), row($0.spacer("s"))]) }
    #expect(ge24 == size(30, 56), "GE24 \(ge24)")
    let ge25 = hArm { $0.grid([row($0.fx("b", 20, 20)), .full($0.spacer("s"))]) }
    #expect(ge25 == size(60, 28), "GE25 \(ge25)")
    let ge26 = hArm { $0.grid([row($0.fx("b", 20, 20), $0.fx("e", 20, 20)), row($0.spacer("s"))]) }
    #expect(ge26 == size(96, 28), "GE26 \(ge26)")
}

// MARK: - 1.11 a stack does not mark a grid's Spacer

/// GR-R: `markSpacers` stops at a grid. GE29 `HStack{a 30x10; VStack{Grid{[Spacer,
/// b 20x20]}}; c 10x10}` answers 76×20: the VStack does not mark the Spacer, so
/// it keeps its 8pt nil width, the grid answers 28×20 (the VStack's width, 76 −
/// 30 − 8 − 10, with a zero leading gap) and its leading edge stays zero. GE30,
/// the control, holds the VStack's own Spacer, which it marks: 76×28.
/// Measured, not placed (GR-W).
///
/// Mutation: walk `markSpacers` into a grid's children (the Spacer answers 0
/// wide at nil: the grid reads 20×20 and GE29 reads 68×20).
@Test func aStackDoesNotMarkASpacerInsideAGrid() throws {
    let ge29 = Arm()
    let grid = ge29.grid([row(ge29.spacer("s"), ge29.fx("b", 20, 20))])
    let stack29 = ge29.hstack("stack", [ge29.fx("a", 30, 10), ge29.vstack("v", [grid]), ge29.fx("c", 10, 10)])
    let ge30 = Arm()
    let stack30 = ge30.hstack("stack", [ge30.fx("a", 30, 10), ge30.vstack("v", [ge30.spacer("s"), ge30.fx("b", 20, 20)]),
                                        ge30.fx("c", 10, 10)])
    let answer29 = ge29.measure(stack29, nil, nil)
    let answer30 = ge30.measure(stack30, nil, nil)
    try #require(answer29 != answer30, "GE29 and its control GE30 must differ")
    #expect(answer29 == size(76, 20), "GE29 \(answer29)")
    #expect(ge29.measure(grid, nil, nil) == size(28, 20), "GE29's grid")
    #expect(answer30 == size(76, 28), "GE30 \(answer30)")
}

// MARK: - 1.13 reset

/// GR-A: `reset(generation:)` clears the row marks. Two nodes marked as one row
/// in generation 1; after the reset, two 30×10 leaves registered at the same
/// indexes under a grid carry no mark and are two non-row cells: 30×28, not one
/// row's 68×10.
///
/// Mutation: do not clear the row-token dictionary in `reset` (68×10).
@Test func resetClearsGridRowMarks() throws {
    let tree = LayoutTree(generation: 1)
    let first = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
    let second = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
    tree.markNativeGridRow([first, second])
    tree.reset(generation: 2)
    let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
    let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
    try #require(a.index == first.index && b.index == second.index, "the new leaves reuse the marked indexes")
    let grid = tree.newNativeGrid(children: [a, b])
    #expect(tree.measureNativeLayout(root: grid, proposal: ProposedSize(width: nil, height: nil)).size == size(30, 28))
}
