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

    /// `fw`: width proposal ?? 10, fixed height (lane 2).
    func fw(_ name: String, _ h: Double = 20) -> LayoutNodeID { leaf(name) { SizeD(width: $0.width ?? 10, height: h) } }

    /// A written `.layoutPriority(p)` over `node` (lane 2).
    func prio(_ node: LayoutNodeID, _ priority: Double) -> LayoutNodeID {
        tree.newNativeLayoutPriority(child: node, priority: priority)
    }

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

    /// Measures `root` at `proposal`, then lays it out at `proposal` in
    /// `bounds` — which need not be the answer, as a window root's are not
    /// (`CN-J`). Returns the answer.
    @discardableResult
    func run(_ root: LayoutNodeID, _ width: Double?, _ height: Double?, in bounds: LayoutRect) -> SizeD {
        let proposal = ProposedSize(width: width, height: height)
        let answer = tree.measureNativeLayout(root: root, proposal: proposal).size
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
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
/// **GX13** (second critic round, finding 2): a non-row child's column mark is
/// **ignored** — it spans every column whatever it says (GR-F). `[a 30x10,
/// b 20x20, e 5x5] x 10x10 columns(1)` at nil is 71×38 with x measured at the
/// whole 71 and centred in it, not measured at column 0's 30. Normative in spec
/// §4.1 and implemented since lane 1, and until this arm no test read it.
///
/// Mutations: (a) group consecutive children by token equality including nil
/// (GA8's x and y become one row, 48×20); (b) honour a non-row child's column
/// mark when it has one — `isRow ? span(child) : (child.columns.map { max(1,
/// $0) } ?? columnCount)`, which leaves GA8, GX3 and GX4 (no marks) untouched
/// and moves GX13's x.
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
    do { // GX13: the non-row child's columns(1) is ignored.
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5)),
                             .full(arm.span(arm.fx("x", 10, 10), 1))])
        #expect(arm.run(root, nil, nil) == size(71, 38), "GX13 size")
        #expect(arm["e"] == r(66, 7.5, 5, 5), "GX13 e")
        #expect(arm["x"] == r(30.5, 28, 10, 10), "GX13 x")
        #expect(arm.proposals("x") == [proposal(nil, nil), proposal(71, 10)],
                "GX13 x is offered the whole grid, not column 0: \(arm.proposals("x"))")
    }
}

// MARK: - 1.3 spans at nil

/// GR-F at nil: every cell is measured once; single-column cells widen their
/// columns first, then each spanning cell spreads its shortfall, in source
/// order; a non-row child spans every column. **Nothing is clamped** (GR-Z):
/// the column count is the widest row's sum of spans, so a span always fits.
///
/// - GX1 `[a 30x10, b 20x20] [c 100x10 span 2]`: 100×38, columns 51/41.
/// - GX2 `[a, b] [c 10x10 span 2]`: 58×38, c centred in 58.
/// - GX3 `[a, b] x 100x10 (non-row) [c 10x30, d 40x10]`: 100×76, columns 41/51.
/// - GX4 `[a, b] x hf (non-row)`: x placed at its 58 slot answers 29.
/// - GX5 `[a, b, c 5x5] [x 100x10 span 2, y 1x1]`: 113×38.
/// - GX6 `[a, b] [x 10x10 span 5]`: 58×38 — x spans all **five** columns and
///   columns 2–4 are empty, take no width and meet no pair (GX21, GX23).
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
/// - GD-H1 and GD-V1 put the LARGER pair FIRST, so "largest" and "the last pair
///   seen" answer differently; every arm above has it last.
///   GD-H1 `[c 10x30, d 40x10] [Spacer, b 20x20]`: the 8 of row 0's (c, d)
///   survives row 1's (Spacer, b) 0, so the grid is 58 wide, not 50.
///   GD-V1 `[b 20x20, Spacer] [d 40x10, c 10x30]`: the 8 of column 0's (b, d)
///   survives column 1's (Spacer, c) 0, so it is 58 tall, not 50.
///   Both are read from SwiftUI by `docs/probes/swiftui-grid-gap-order.swift`
///   (arms H1 and V1, against GA1 and GQ6 as positive controls) — the arms in
///   `docs/probes/swiftui-grid.swift` cannot tell the two rules apart.
///
/// Mutation: `platformDefault` before every column j ≥ 1 regardless of pairs
/// and edges (GS2's plan reads 8, 8; GS6 reads 76).
///
/// Mutation (GR-D's "largest", the lane-1 verifier's H2/H3): both reductions in
/// `makeNativeGridPlan` take the LAST pair meeting at a gap instead of the
/// largest (`hgapValues[column] = value`, `best = value`) — GD-H1's hgap reads
/// [0, 0] and its size 50×58; GD-V1's vgap reads [0, 0] and its size 58×50.
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

    // The larger pair FIRST, one axis each: the only arms here that "largest"
    // and "the last pair seen" answer differently.
    let gdh1 = try gaps { a in a.grid([row(a.fx("c", 10, 30), a.fx("d", 40, 10)), row(a.spacer("s"), a.fx("b", 20, 20))]) }
    #expect(gdh1.h == [0, 8] && gdh1.v == [0, 8], "GD-H1 \(gdh1)")
    let gdv1 = try gaps { a in a.grid([row(a.fx("b", 20, 20), a.spacer("s")), row(a.fx("d", 40, 10), a.fx("c", 10, 30))]) }
    #expect(gdv1.h == [0, 8] && gdv1.v == [0, 8], "GD-V1 \(gdv1)")

    do { // GD-H1 laid out
        let arm = Arm()
        let root = arm.grid([row(arm.fx("c", 10, 30), arm.fx("d", 40, 10)), row(arm.spacer("s"), arm.fx("b", 20, 20))])
        #expect(arm.run(root, nil, nil) == size(58, 58), "GD-H1 size")
        #expect(arm["c"] == r(0, 0, 10, 30), "GD-H1 c")
        #expect(arm["d"] == r(18, 10, 40, 10), "GD-H1 d")
        #expect(arm["b"] == r(28, 38, 20, 20), "GD-H1 b")
        #expect(arm["s"] == r(0, 38, 10, 20), "GD-H1 s")
    }
    do { // GD-V1 laid out
        let arm = Arm()
        let root = arm.grid([row(arm.fx("b", 20, 20), arm.spacer("s")), row(arm.fx("d", 40, 10), arm.fx("c", 10, 30))])
        #expect(arm.run(root, nil, nil) == size(58, 58), "GD-V1 size")
        #expect(arm["b"] == r(10, 0, 20, 20), "GD-V1 b")
        #expect(arm["d"] == r(0, 38, 40, 10), "GD-V1 d")
        #expect(arm["c"] == r(48, 28, 10, 30), "GD-V1 c")
        #expect(arm["s"] == r(48, 0, 10, 20), "GD-V1 s")
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
/// - GL-B1 is GL1 laid out in bounds LARGER than its answer and at a non-zero
///   origin (7, 11, 200×200), as a window root's are (`CN-J`): spec §4.3's
///   "the cells start at `bounds`' origin whatever its size, as ZStack's union
///   does (`CN-E`)". Every other arm here lays a grid out in bounds of its own
///   answer at the origin, so none of them can see it.
///
/// Mutation: ignore the row alignment (GL3's a at y 5).
///
/// Mutation (spec §4.3's origin, the lane-1 verifier's H9): `placeGrid` centres
/// the cells in `bounds` instead of starting at `bounds.x`/`bounds.y` — GL-B1's
/// a reads (68, 82), not (7, 11).
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
    do { // GL-B1: GL1 in bounds larger than its answer, at a non-zero origin
        let arm = Arm()
        let bounds = LayoutRect(x: 7, y: 11, width: 200, height: 200)
        #expect(arm.run(ga1(arm, .topLeading), nil, nil, in: bounds) == size(78, 58), "GL-B1 answer")
        #expect(arm["grid"] == r(7, 11, 200, 200), "GL-B1 grid")
        #expect(arm["a"] == r(7, 11, 30, 10), "GL-B1 a")
        #expect(arm["b"] == r(45, 11, 20, 20), "GL-B1 b")
        #expect(arm["c"] == r(7, 39, 10, 30), "GL-B1 c")
        #expect(arm["d"] == r(45, 39, 40, 10), "GL-B1 d")
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

/// GR-A: `reset(generation:)` clears the column-span marks. A node marked
/// `columns: 2` in generation 1; after the reset, a 100×10 leaf registered at
/// its index is an unmarked one-cell row above a row of two 30×10 cells, so it
/// widens only the first column: 138×28. The control marks the same leaf
/// `columns: 2` in generation 2, so its shortfall is shared by both columns:
/// 100×28. `markNativeGridCell(_:columns: nil)` writes nothing, so a stale mark
/// on a reused index is read by `newNativeGrid` unless `reset` clears it.
///
/// Mutation (verifier V1): do not clear the column-span dictionary in `reset`
/// (100×28).
@Test func resetClearsGridCellColumnMarks() throws {
    func arm(markBeforeReset: Bool, markAfterReset: Bool) throws -> SizeD {
        let tree = LayoutTree(generation: 1)
        let stale = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 10)) }
        if markBeforeReset { tree.markNativeGridCell(stale, columns: 2) }
        tree.reset(generation: 2)
        let wide = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 10)) }
        let left = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
        let right = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
        try #require(wide.index == stale.index, "the new leaf reuses the marked index")
        tree.markNativeGridCell(wide, columns: markAfterReset ? 2 : nil)
        tree.markNativeGridRow([wide])
        tree.markNativeGridRow([left, right])
        let grid = tree.newNativeGrid(children: [wide, left, right])
        return tree.measureNativeLayout(root: grid, proposal: ProposedSize(width: nil, height: nil)).size
    }
    let afterReset = try arm(markBeforeReset: true, markAfterReset: false)
    let control = try arm(markBeforeReset: false, markAfterReset: true)
    try #require(afterReset != control, "an unmarked cell and a two-column span must answer differently")
    #expect(afterReset == size(138, 28), "a mark from before the reset \(afterReset)")
    #expect(control == size(100, 28), "the control's two-column span \(control)")
}

// MARK: - Lane 2: the finite solve
//
// Lane 2 ("the finite solve") of the grids spec: rulings GR-B, GR-E, GR-F at
// proposals other than nil×nil (model step 12), GR-R's priority and answers in
// stacks, GR-U. Every figure is the probe's `Grid` reading where the reference
// model agrees with it (`model-arms`), and the model's own reading where it
// does not (2.9, pinned wrong on purpose).

/// Each named rect of `arm` against the probe's, labelled with the arm id.
private func expectRects(_ arm: Arm, _ label: String, _ expected: [String: LayoutRect],
                         sourceLocation: SourceLocation = #_sourceLocation) {
    for (name, rect) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(arm[name] == rect, "\(label) \(name): \(arm[name])", sourceLocation: sourceLocation)
    }
}

/// An answer against the probe's, to 1e-9 or equal infinities.
private func close(_ a: SizeD, _ b: SizeD) -> Bool {
    func axis(_ x: Double, _ y: Double) -> Bool { x == y || abs(x - y) <= 1e-9 }
    return axis(a.width, b.width) && axis(a.height, b.height)
}

private func proposal(_ width: Double?, _ height: Double?) -> ProposedSize { ProposedSize(width: width, height: height) }

/// GA1's leaves `[a 30x10, b 20x20] [c 10x30, d 40x10]`, or GP2's with a
/// flexible `a`.
private func ga1(_ arm: Arm, flexibleA: Bool = false) -> LayoutNodeID {
    arm.grid([row(flexibleA ? arm.fl("a") : arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
              row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
}

/// A GA1-shaped grid whose first cell is `first`.
private func withFirst(_ arm: Arm, _ first: LayoutNodeID) -> LayoutNodeID {
    arm.grid([row(first, arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
}

// MARK: 2.1 groups, shares and commits

/// GR-E: every cell is measured at 0×0 and ∞×∞; cells are served in groups of
/// equal (priority, infinite-axis count, finite flexibility); a group's cells
/// are offered max(share, their column's width), the share being W′ minus the
/// committed columns over the open ones; a column commits once no cell of this
/// priority or higher is left in it. The grid answers its sums (it does not
/// fill with fixed content). Figures: the probe's arms.
///
/// - GP1 GA1 at 200×200: 78×58, GA1's rects. GP2 (a flexible) at 200×100: a
///   152×62 = 192 − 40 by 92 − 30. GP7 one flexible cell at 100×100. GA9 two
///   non-row children at 200×100.
/// - GF1–GF9: half, width-flexible, height-flexible, clamped and flexible cells;
///   GF7 overflows to 138 and its d is proposed 120 wide (b's column).
/// - GF14–GF18: a greedy `frame(maxWidth: .infinity)` cell (and at nil), a
///   proposal-responsive leaf standing for `Color` (and at nil), a frame
///   greedy on both axes.
/// - GR2 `[a odd, b 20x20]` at 200×200: a placed at the 96×200 it was measured
///   at, never at its 20×20 slot.
///
/// Mutation (GZ0's control): every group offered W′/ncols, commits ignored (GP2's
/// a at 96).
@Test func aFiniteProposalServesGroupsWithSharesAndCommits() {
    do { // GP1
        let arm = Arm()
        #expect(arm.run(ga1(arm), 200, 200) == size(78, 58), "GP1 size")
        expectRects(arm, "GP1", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20), "c": r(10, 28, 10, 30), "d": r(38, 38, 40, 10)])
    }
    do { // GP2
        let arm = Arm()
        #expect(arm.run(ga1(arm, flexibleA: true), 200, 100) == size(200, 100), "GP2 size")
        expectRects(arm, "GP2", ["a": r(0, 0, 152, 62), "b": r(170, 21, 20, 20), "c": r(71, 70, 10, 30), "d": r(160, 80, 40, 10)])
    }
    do { // GP7
        let arm = Arm()
        #expect(arm.run(arm.grid([row(arm.fl("a"))]), 100, 100) == size(100, 100), "GP7 size")
        expectRects(arm, "GP7", ["a": r(0, 0, 100, 100)])
    }
    do { // GA9
        let arm = Arm()
        #expect(arm.run(arm.grid([.full(arm.fx("x", 30, 10)), .full(arm.fl("y"))]), 200, 100) == size(200, 100), "GA9 size")
        expectRects(arm, "GA9", ["x": r(85, 0, 30, 10), "y": r(0, 18, 200, 82)])
    }
    do { // GF1
        let arm = Arm()
        let root = arm.grid([row(arm.hf("a"), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.hf("d"))])
        #expect(arm.run(root, 200, 200) == size(104, 58), "GF1 size")
        expectRects(arm, "GF1", ["a": r(12, 5, 24, 10), "b": r(70, 0, 20, 20), "c": r(19, 28, 10, 30), "d": r(68, 38, 24, 10)])
    }
    do { // GF2
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.fw("a", 20)), 200, 100) == size(200, 58), "GF2 size")
        expectRects(arm, "GF2", ["a": r(0, 0, 152, 20), "b": r(170, 0, 20, 20), "c": r(71, 28, 10, 30), "d": r(160, 38, 40, 10)])
    }
    do { // GF3
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.fh("a", 20)), 200, 100) == size(68, 100), "GF3 size")
        expectRects(arm, "GF3", ["a": r(0, 0, 20, 62), "b": r(38, 21, 20, 20), "c": r(5, 70, 10, 30), "d": r(28, 80, 40, 10)])
    }
    do { // GF4
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.cb("a", 0, 150)), 200, 100) == size(198, 100), "GF4 size")
        expectRects(arm, "GF4", ["a": r(0, 0, 150, 62), "b": r(168, 21, 20, 20), "c": r(70, 70, 10, 30), "d": r(158, 80, 40, 10)])
    }
    do { // GF5
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.cb("a", 0, 50)), 200, 100) == size(98, 88), "GF5 size")
        expectRects(arm, "GF5", ["a": r(0, 0, 50, 50), "b": r(68, 15, 20, 20), "c": r(20, 58, 10, 30), "d": r(58, 68, 40, 10)])
    }
    do { // GF6
        let arm = Arm()
        let root = arm.grid([row(arm.fl("a"), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.fl("d"))])
        #expect(arm.run(root, 200, 100) == size(200, 100), "GF6 size")
        expectRects(arm, "GF6", ["a": r(0, 0, 96, 46), "b": r(142, 13, 20, 20), "c": r(43, 62, 10, 30), "d": r(104, 54, 96, 46)])
    }
    do { // GF7
        let arm = Arm()
        let root = arm.grid([row(arm.fl("a"), arm.fx("b", 120, 20)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, 100, 100) == size(138, 100), "GF7 size")
        expectRects(arm, "GF7", ["a": r(0, 0, 10, 62), "b": r(18, 21, 120, 20), "c": r(0, 70, 10, 30), "d": r(58, 80, 40, 10)])
        #expect(arm.proposals("d") == [proposal(0, 0), proposal(.infinity, .infinity), proposal(120, 46), proposal(120, 30)],
                "GF7 d is proposed b's 120 in its group, then placed at its 120×30 slot: \(arm.proposals("d"))")
    }
    do { // GF8
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 20, 20), arm.fl("b"), arm.fl("c"))])
        #expect(arm.run(root, 200, 100) == size(200, 100), "GF8 size")
        expectRects(arm, "GF8", ["a": r(0, 40, 20, 20), "b": r(28, 0, 82, 100), "c": r(118, 0, 82, 100)])
    }
    do { // GF9
        let arm = Arm()
        let root = arm.grid([row(arm.cw("a", 0, 30), arm.cw("b", 0, 55))])
        #expect(arm.run(root, 100, 100) == size(93, 10), "GF9 size")
        expectRects(arm, "GF9", ["a": r(0, 0, 30, 10), "b": r(38, 0, 55, 10)])
    }
    do { // GF14
        let arm = Arm()
        let a = arm.tree.newNativeFrame(child: arm.fx("a", 30, 10), maxWidth: .infinity)
        #expect(arm.run(withFirst(arm, a), 200, 100) == size(200, 58), "GF14 size")
        expectRects(arm, "GF14", ["a": r(61, 5, 30, 10), "b": r(170, 0, 20, 20), "c": r(71, 28, 10, 30), "d": r(160, 38, 40, 10)])
    }
    do { // GF15
        let arm = Arm()
        let a = arm.tree.newNativeFrame(child: arm.fx("a", 30, 10), maxWidth: .infinity)
        #expect(arm.run(withFirst(arm, a), nil, nil) == size(78, 58), "GF15 size")
        expectRects(arm, "GF15", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20), "c": r(10, 28, 10, 30), "d": r(38, 38, 40, 10)])
    }
    do { // GF16
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.fl("k")), 200, 100) == size(200, 100), "GF16 size")
        expectRects(arm, "GF16", ["k": r(0, 0, 152, 62), "b": r(170, 21, 20, 20), "c": r(71, 70, 10, 30), "d": r(160, 80, 40, 10)])
    }
    do { // GF17
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.fl("k")), nil, nil) == size(58, 58), "GF17 size")
        expectRects(arm, "GF17", ["k": r(0, 0, 10, 20), "b": r(28, 0, 20, 20), "c": r(0, 28, 10, 30), "d": r(18, 38, 40, 10)])
    }
    do { // GF18
        let arm = Arm()
        let a = arm.tree.newNativeFrame(child: arm.fx("a", 30, 10), maxWidth: .infinity, maxHeight: .infinity)
        #expect(arm.run(withFirst(arm, a), 200, 100) == size(200, 100), "GF18 size")
        expectRects(arm, "GF18", ["a": r(61, 26, 30, 10), "b": r(170, 21, 20, 20), "c": r(71, 70, 10, 30), "d": r(160, 80, 40, 10)])
    }
    do { // GR2
        let arm = Arm()
        let root = arm.grid([row(arm.odd("a"), arm.fx("b", 20, 20))])
        #expect(arm.run(root, 200, 200) == size(48, 20), "GR2 size")
        expectRects(arm, "GR2", ["a": r(0, 0, 20, 20), "b": r(28, 0, 20, 20)])
        #expect(arm.proposals("a") == [proposal(0, 0), proposal(.infinity, .infinity), proposal(96, 200)],
                "GR2 a is placed at the 96×200 it answered 20×20 to: \(arm.proposals("a"))")
    }
}

// MARK: 2.2 the flexibility key

/// GR-E step 2: the key counts the proposal-finite axes whose ∞ answer is
/// infinite first, then the finite flexibility over the others; a nil axis
/// counts for neither.
///
/// - GF10 `[a half, b flexible]` at 200×100: a (one infinite axis) before b
///   (two): a proposed 96, then b the remaining 144.
/// - GF11 `[a width 10…20, b height-flexible, c width 10…160 h30]`: c's finite
///   150 before b's one infinite axis.
/// - GF12 `[a clamp 10…50, b height-flexible w30, c flexible]` at 150 × nil and
///   GF13 at 150×100: required to differ.
///
/// Mutation: key = the finite sum with ∞ as +∞, one group for equal sums
/// (GF10's b at 96).
@Test func theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis() throws {
    do { // GF10
        let arm = Arm()
        #expect(arm.run(arm.grid([row(arm.hf("a"), arm.fl("b"))]), 200, 100) == size(200, 100), "GF10 size")
        expectRects(arm, "GF10", ["a": r(12, 45, 24, 10), "b": r(56, 0, 144, 100)])
    }
    do { // GF11
        let arm = Arm()
        let root = arm.grid([row(arm.cw("a", 10, 20), arm.fh("b", 20), arm.cw("c", 10, 160, 30))])
        #expect(arm.run(root, 200, 100) == size(138, 100), "GF11 size")
        expectRects(arm, "GF11", ["a": r(0, 45, 20, 10), "b": r(28, 0, 20, 100), "c": r(56, 35, 82, 30)])
    }
    func gf12Arm(_ height: Double?) -> Arm {
        let arm = Arm()
        arm.run(arm.grid([row(arm.cb("a", 10, 50), arm.fh("b", 30), arm.fl("c"))]), 150, height)
        return arm
    }
    let gf12 = gf12Arm(nil), gf13 = gf12Arm(100)
    try #require(gf12["grid"] != gf13["grid"], "GF12 and its control GF13 must differ")
    #expect(gf12["grid"] == r(0, 0, 150, 10), "GF12 size")
    expectRects(gf12, "GF12", ["a": r(0, 0, 50, 10), "b": r(58, 0, 30, 10), "c": r(96, 0, 54, 10)])
    #expect(gf13["grid"] == r(0, 0, 150, 100), "GF13 size")
    expectRects(gf13, "GF13", ["a": r(0, 25, 44.67, 50), "b": r(52.67, 0, 30, 100), "c": r(90.67, 0, 59.33, 100)])
}

// MARK: 2.3 one-axis and infinite proposals

/// GR-E steps 3 and 5: a nil proposal axis stays nil in every cell's proposal;
/// an infinite one shares infinity, and a cell answering infinity makes the
/// grid answer it.
///
/// - GP5 GP2 at 200 × nil: 200×58, a 152×20. GP6 at nil × 100: 58×100, a 10×62.
/// - GP4 GP2 at ∞×∞: ∞×∞. GP8 GA1 at ∞×∞: 78×58. Both measured only: an
///   infinite answer traps at checkpoint 3 when stored (SA-J).
///
/// The logs are asserted as well as the rects (as the probe's "measured, in
/// order" lists read them): GP5's a is asked 152 × nil in its group and placed
/// at its 152×20 slot; GP6's a is asked nil × 62 and, its 10×62 slot equalling
/// that answer, placed there. **The rects alone cannot see the mutant below**:
/// a proposed 152×0 answers 152×0, and its 152×20 slot re-measures it to the
/// same rect (measured, record §20 lane 2).
///
/// Mutation: propose a nil grid axis as 0 (GP5's a is asked 152×0).
@Test func oneAxisNilAndInfiniteProposalsAnswerAsTheProbeReads() {
    do { // GP5
        let arm = Arm()
        #expect(arm.run(ga1(arm, flexibleA: true), 200, nil) == size(200, 58), "GP5 size")
        expectRects(arm, "GP5", ["a": r(0, 0, 152, 20), "b": r(170, 0, 20, 20), "c": r(71, 28, 10, 30), "d": r(160, 38, 40, 10)])
        #expect(arm.proposals("a") == [proposal(0, 0), proposal(.infinity, .infinity), proposal(152, nil), proposal(152, 20)],
                "GP5 a: \(arm.proposals("a"))")
    }
    do { // GP6
        let arm = Arm()
        #expect(arm.run(ga1(arm, flexibleA: true), nil, 100) == size(58, 100), "GP6 size")
        expectRects(arm, "GP6", ["a": r(0, 0, 10, 62), "b": r(28, 21, 20, 20), "c": r(0, 70, 10, 30), "d": r(18, 80, 40, 10)])
        #expect(arm.proposals("a") == [proposal(0, 0), proposal(.infinity, .infinity), proposal(nil, 62)],
                "GP6 a: \(arm.proposals("a"))")
    }
    do { // GP4
        let arm = Arm()
        #expect(arm.measure(ga1(arm, flexibleA: true), .infinity, .infinity) == size(.infinity, .infinity), "GP4")
    }
    do { // GP8
        let arm = Arm()
        #expect(arm.measure(ga1(arm), .infinity, .infinity) == size(78, 58), "GP8")
    }
}

// MARK: 2.4 an infinite axis after an infinite committed column

/// GR-E step 3: on an infinite proposal axis every share is ∞, even after a
/// column of infinite width has committed (GP9–GP11: SwiftUI never produces
/// nan there). **An exit test** because the mutant proposes nan, which traps at
/// checkpoint 1 and would end the suite. Each leaf's set of distinct proposals
/// was derived by hand from spec §4.2 before the run:
///
/// - GP9 `[a flexible, b width 0…50 h10 priority −1]` at ∞×∞: groups [a], [b];
///   a ∞×∞ commits column 0 at ∞; b's share is ∞, its proposal ∞×∞ (a hit).
///   a {0×0, ∞×∞}, b {0×0, ∞×∞}; answer ∞×∞.
/// - GP10 `[a flexible] [b flexible, c 10x10 priority −1]` at ∞×∞: groups [a,
///   b], [c]. a, b, c each {0×0, ∞×∞}; answer ∞×∞.
/// - GP11 `[a flexible, b height-flexible w10 priority −1]` at ∞ × 100: group a
///   shares ∞ × 100 and commits row 0 at 100; group b shares ∞ × (100 − 100) =
///   0, proposed ∞ × max(0, 100). a {0×0, ∞×∞, ∞×100}, b {0×0, ∞×∞, ∞×100};
///   answer ∞×100.
///
/// Mutation: compute `(W′ − committed) / open` on an infinite axis: ∞ − ∞ is
/// nan, and the child exits `.failure` (a nan proposal, or a finite one in the
/// set).
@Test func anInfiniteAxisSharesInfinityAfterAnInfiniteCommittedColumn() async {
    await #expect(processExitsWith: .success) {
        final class Log: @unchecked Sendable { var proposals: Set<ProposedSize> = [] }
        let tree = LayoutTree(generation: 0)
        func leaf(_ answer: @escaping @Sendable (ProposedSize) -> SizeD) -> (LayoutNodeID, Log) {
            let log = Log()
            return (tree.newNativeLeaf { p in log.proposals.insert(p); return LayoutMeasurement(size: answer(p)) }, log)
        }
        let flexible: @Sendable (ProposedSize) -> SizeD = { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) }
        let zero = ProposedSize(width: 0, height: 0), inf = ProposedSize(width: .infinity, height: .infinity)
        let infinite = SizeD(width: .infinity, height: .infinity)

        let (a9, a9Log) = leaf(flexible)
        let (b9, b9Log) = leaf { SizeD(width: Swift.min(Swift.max($0.width ?? 10, 0), 50), height: 10) }
        let p9 = tree.newNativeLayoutPriority(child: b9, priority: -1)
        tree.markNativeGridRow([a9, p9])
        let gp9 = tree.newNativeGrid(children: [a9, p9])
        precondition(tree.measureNativeLayout(root: gp9, proposal: inf).size == infinite, "GP9 answer")
        precondition(a9Log.proposals == [zero, inf], "GP9 a \(a9Log.proposals)")
        precondition(b9Log.proposals == [zero, inf], "GP9 b \(b9Log.proposals)")

        let (a10, a10Log) = leaf(flexible)
        let (b10, b10Log) = leaf(flexible)
        let (c10, c10Log) = leaf { _ in SizeD(width: 10, height: 10) }
        let p10 = tree.newNativeLayoutPriority(child: c10, priority: -1)
        tree.markNativeGridRow([a10])
        tree.markNativeGridRow([b10, p10])
        let gp10 = tree.newNativeGrid(children: [a10, b10, p10])
        precondition(tree.measureNativeLayout(root: gp10, proposal: inf).size == infinite, "GP10 answer")
        precondition(a10Log.proposals == [zero, inf], "GP10 a \(a10Log.proposals)")
        precondition(b10Log.proposals == [zero, inf], "GP10 b \(b10Log.proposals)")
        precondition(c10Log.proposals == [zero, inf], "GP10 c \(c10Log.proposals)")

        let (a11, a11Log) = leaf(flexible)
        let (b11, b11Log) = leaf { SizeD(width: 10, height: $0.height ?? 10) }
        let p11 = tree.newNativeLayoutPriority(child: b11, priority: -1)
        tree.markNativeGridRow([a11, p11])
        let gp11 = tree.newNativeGrid(children: [a11, p11])
        let at = ProposedSize(width: .infinity, height: 100)
        precondition(tree.measureNativeLayout(root: gp11, proposal: at).size == SizeD(width: .infinity, height: 100), "GP11 answer")
        precondition(a11Log.proposals == [zero, inf, at], "GP11 a \(a11Log.proposals)")
        precondition(b11Log.proposals == [zero, inf, at], "GP11 b \(b11Log.proposals)")
    }
}

// MARK: 2.5 priority with no reservation

/// GR-E: higher-priority groups are served first with nothing reserved for
/// lower ones, whose columns count at their current width afterwards; the grid
/// can answer wider than its proposal.
///
/// - GQ1 `[a flexible, b flexible priority 1]` at 100×100: b 92, a 0.
/// - GQ2 `[a width 0…200, b width 30…200 priority −1, c width 20…200]`: a and c
///   42, then b 30: 130×10. GQ3 (b priority 1): b 84, then a 0 and c 20: 120×10.
/// - GQ4 `[a flexible, b 20x20] [c 10x30, d flexible priority 1]` at 200×100:
///   d 192×92 first: 210×120. GQ5 `[a clamp 10…70 priority 1] [b 20x10 priority
///   1, c 150x30, d width 30…180 h40]` at 100×100: 266×118.
///
/// Mutation: reserve lower groups' 0×0 widths, as CN-B's stack does (GQ2's a and
/// c read 27).
@Test func higherPriorityGroupsAreServedFirstWithNoReservation() {
    do { // GQ1
        let arm = Arm()
        #expect(arm.run(arm.grid([row(arm.fl("a"), arm.prio(arm.fl("b"), 1))]), 100, 100) == size(100, 100), "GQ1 size")
        expectRects(arm, "GQ1", ["a": r(0, 0, 0, 100), "b": r(8, 0, 92, 100)])
    }
    func gq23(_ priority: Double) -> Arm {
        let arm = Arm()
        arm.run(arm.grid([row(arm.cw("a", 0, 200), arm.prio(arm.cw("b", 30, 200), priority), arm.cw("c", 20, 200))]), 100, 100)
        return arm
    }
    do { // GQ2
        let arm = gq23(-1)
        #expect(arm["grid"] == r(0, 0, 130, 10), "GQ2 size")
        expectRects(arm, "GQ2", ["a": r(0, 0, 42, 10), "b": r(50, 0, 30, 10), "c": r(88, 0, 42, 10)])
    }
    do { // GQ3
        let arm = gq23(1)
        #expect(arm["grid"] == r(0, 0, 120, 10), "GQ3 size")
        expectRects(arm, "GQ3", ["a": r(0, 0, 0, 10), "b": r(8, 0, 84, 10), "c": r(100, 0, 20, 10)])
    }
    do { // GQ4
        let arm = Arm()
        let root = arm.grid([row(arm.fl("a"), arm.fx("b", 20, 20)), row(arm.fx("c", 10, 30), arm.prio(arm.fl("d"), 1))])
        #expect(arm.run(root, 200, 100) == size(210, 120), "GQ4 size")
        expectRects(arm, "GQ4", ["a": r(0, 0, 10, 20), "b": r(104, 0, 20, 20), "c": r(0, 59, 10, 30), "d": r(18, 28, 192, 92)])
    }
    do { // GQ5
        let arm = Arm()
        let root = arm.grid([row(arm.prio(arm.cb("a", 10, 70), 1)),
                             row(arm.prio(arm.fx("b", 20, 10), 1), arm.fx("c", 150, 30), arm.cw("d", 30, 180, 40))])
        #expect(arm.run(root, 100, 100) == size(266, 118), "GQ5 size")
        expectRects(arm, "GQ5", ["a": r(0, 0, 70, 70), "b": r(25, 93, 20, 10), "c": r(78, 83, 150, 30), "d": r(236, 78, 30, 40)])
    }
}

// MARK: 2.6 a bare Spacer cell

/// GR-E: a bare Spacer is priority −∞ (the kernel's walk), so it is served
/// last, and flexible on both axes (no stack marks it inside a grid).
///
/// - GS1 `[Spacer s, b 20x20] [c 10x30, d 40x10]` at 200×100: 190×80, s 142×42
///   = (192 − 40 − 10) by (92 − 30 − 20). GQ7 the same with `minLength: 0`.
/// - GQ8 a lone Spacer at 100×100 fills it.
/// - GQ9, GS1 with `.layoutPriority(0)` on the Spacer: an ordinary flexible cell,
///   200×100, s 152×62 — required to differ from GS1.
///
/// Mutation: read a cell's priority as 0 (GS1 reads GQ9's figures).
@Test func aBareSpacerCellIsPriorityMinusInfinityAndFlexibleOnBothAxes() throws {
    func gs1Arm(_ spacer: (Arm) -> LayoutNodeID) -> Arm {
        let arm = Arm()
        arm.run(withFirst(arm, spacer(arm)), 200, 100)
        return arm
    }
    let gs1 = gs1Arm { $0.spacer("s") }
    let gq9 = gs1Arm { $0.prio($0.spacer("s"), 0) }
    try #require(gs1["grid"] != gq9["grid"], "GS1 and GQ9 must differ")
    #expect(gs1["grid"] == r(0, 0, 190, 80), "GS1 size")
    expectRects(gs1, "GS1", ["s": r(0, 0, 142, 42), "b": r(160, 11, 20, 20), "c": r(66, 50, 10, 30), "d": r(150, 60, 40, 10)])
    let gq7 = gs1Arm { $0.name($0.tree.newNativeSpacer(minLength: 0), "s") }
    #expect(gq7["grid"] == r(0, 0, 190, 80), "GQ7 size")
    expectRects(gq7, "GQ7", ["s": r(0, 0, 142, 42), "b": r(160, 11, 20, 20), "c": r(66, 50, 10, 30), "d": r(150, 60, 40, 10)])
    #expect(gq9["grid"] == r(0, 0, 200, 100), "GQ9 size")
    expectRects(gq9, "GQ9", ["s": r(0, 0, 152, 62), "b": r(170, 21, 20, 20), "c": r(71, 70, 10, 30), "d": r(160, 80, 40, 10)])
    do { // GQ8
        let arm = Arm()
        #expect(arm.run(arm.grid([row(arm.spacer("s"))]), 100, 100) == size(100, 100), "GQ8 size")
        expectRects(arm, "GQ8", ["s": r(0, 0, 100, 100)])
    }
}

// MARK: 2.7 gaps at finite proposals

/// GR-D at a proposal: W′ and H′ are the proposal less the plan's gaps, which
/// the zero-spacing-edge walk decides (lane 1's plan, laid out here).
///
/// - GS1 at 200×100 (190×80). GS2 `[a 30x10, Spacer, c height-flexible w10]` at
///   nil × 80: 48×80; GS3 (an 8x8 leaf): 64×80. GS11 at spacing 12: 72×70.
/// - GS12 `Spacer.frame(width: 8)`, GS13 `Spacer.padding(.leading, 4)`, GS14
///   `HStack(spacing: 0){Spacer}`, GS15 `ZStack{Spacer}`, GS16 an 8x8 leaf with a
///   Spacer overlay, all at nil × 80; GS17 `[a] [Spacer.frame(height: 8)] [c]`
///   and its control GS18 at 80 × nil.
///
/// Mutation: subtract no gaps from W′ and H′ (GS1 moves; recorded by the lane).
@Test func gapsHoldAtFiniteProposals() {
    do { // GS1
        let arm = Arm()
        #expect(arm.run(withFirst(arm, arm.spacer("s")), 200, 100) == size(190, 80), "GS1 size")
        expectRects(arm, "GS1", ["s": r(0, 0, 142, 42), "b": r(160, 11, 20, 20), "c": r(66, 50, 10, 30), "d": r(150, 60, 40, 10)])
    }
    func middle(_ build: (Arm) -> LayoutNodeID, trailing: (Arm) -> LayoutNodeID = { $0.fx("c", 10, 10) }) -> Arm {
        let arm = Arm()
        arm.run(arm.grid([row(arm.fx("a", 30, 10), build(arm), trailing(arm))]), nil, 80)
        return arm
    }
    do { // GS2
        let arm = middle({ $0.spacer("s") }, trailing: { $0.fh("c", 10) })
        #expect(arm["grid"] == r(0, 0, 48, 80), "GS2 size")
        expectRects(arm, "GS2", ["a": r(0, 35, 30, 10), "c": r(38, 0, 10, 80), "s": r(30, 0, 8, 80)])
    }
    do { // GS3
        let arm = middle({ $0.fx("s", 8, 8) }, trailing: { $0.fh("c", 10) })
        #expect(arm["grid"] == r(0, 0, 64, 80), "GS3 size")
        expectRects(arm, "GS3", ["a": r(0, 35, 30, 10), "s": r(38, 36, 8, 8), "c": r(54, 0, 10, 80)])
    }
    do { // GS11
        let arm = Arm()
        arm.run(arm.grid(h: 12, [row(arm.fx("a", 30, 10), arm.spacer("s"), arm.fx("c", 10, 10))]), nil, 80)
        #expect(arm["grid"] == r(0, 0, 72, 70), "GS11 size")
        expectRects(arm, "GS11", ["a": r(0, 30, 30, 10), "c": r(62, 30, 10, 10), "s": r(42, 0, 8, 70)])
    }
    do { // GS12
        let arm = middle { $0.tree.newNativeFrame(child: $0.spacer("s"), width: 8) }
        #expect(arm["grid"] == r(0, 0, 48, 80), "GS12 size")
        expectRects(arm, "GS12", ["a": r(0, 35, 30, 10), "c": r(38, 35, 10, 10), "s": r(30, 0, 8, 80)])
    }
    do { // GS13
        let arm = middle { $0.tree.newNativePadding(child: $0.spacer("s"), insets: Edges(top: 0, right: 0, bottom: 0, left: 4)) }
        #expect(arm["grid"] == r(0, 0, 60, 80), "GS13 size")
        expectRects(arm, "GS13", ["a": r(0, 35, 30, 10), "c": r(50, 35, 10, 10), "s": r(42, 0, 8, 80)])
    }
    do { // GS14
        let arm = middle { $0.hstack("h", [$0.spacer("s")], spacing: 0) }
        #expect(arm["grid"] == r(0, 0, 48, 10), "GS14 size")
        expectRects(arm, "GS14", ["a": r(0, 0, 30, 10), "c": r(38, 0, 10, 10), "s": r(30, 5, 8, 0)])
    }
    do { // GS15
        let arm = middle { $0.tree.newNativeOverlay(children: [$0.spacer("s")]) }
        #expect(arm["grid"] == r(0, 0, 48, 70), "GS15 size")
        expectRects(arm, "GS15", ["a": r(0, 30, 30, 10), "c": r(38, 30, 10, 10), "s": r(30, 0, 8, 70)])
    }
    do { // GS16
        let arm = middle { $0.tree.newNativeOverlayAttachment(child: $0.fx("s", 8, 8), overlay: $0.tree.newNativeSpacer()) }
        #expect(arm["grid"] == r(0, 0, 64, 10), "GS16 size")
        expectRects(arm, "GS16", ["a": r(0, 0, 30, 10), "s": r(38, 1, 8, 8), "c": r(54, 0, 10, 10)])
    }
    do { // GS17
        let arm = Arm()
        arm.run(arm.grid([row(arm.fx("a", 30, 10)), row(arm.tree.newNativeFrame(child: arm.spacer("s"), height: 8)),
                          row(arm.fx("c", 10, 10))]), 80, nil)
        #expect(arm["grid"] == r(0, 0, 80, 28), "GS17 size")
        expectRects(arm, "GS17", ["a": r(25, 0, 30, 10), "c": r(35, 18, 10, 10), "s": r(0, 10, 80, 8)])
    }
    do { // GS18
        let arm = Arm()
        arm.run(arm.grid([row(arm.fx("a", 30, 10)), row(arm.fx("s", 8, 8)), row(arm.fx("c", 10, 10))]), 80, nil)
        #expect(arm["grid"] == r(0, 0, 30, 44), "GS18 size")
        expectRects(arm, "GS18", ["a": r(0, 0, 30, 10), "s": r(11, 18, 8, 8), "c": r(10, 34, 10, 10)])
    }
}

// MARK: 2.8 spans at a finite proposal

/// GR-F at a proposal: a spanning cell is offered W′ less, for each column
/// outside it, the share if that column is open or its width if not, plus its
/// inner gaps; its shortfall widens first the spanned columns still holding an
/// unprocessed single-column cell (model step 12), after its group.
///
/// - GX8 GX7 at 300×100: 100×38, x proposed 300×46.
/// - GX9 `[a 30x10, b flexible] [x 100x10 span 2]` at 300×100: x's shortfall goes
///   to b's still-open column; a's column stays 30 and b is 262 wide.
/// - GX10 `[a 30x10, b 20x10] [x flexible span 2]`: no open column, both widen
///   (151/141).
/// - GX12 `[a clamp 20…120, b width 0…60 h30] x width-flexible h10 (non-row)` at
///   300×200: x proposed 300; slots 176 and 116.
///
/// Mutations: (a) propose a span the sum of its columns' shares plus inner gaps
/// (GX10's x moves); (b) drop step 12 (GX9's b 231, a's column 61).
@Test func aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndWidensItsOpenColumnsFirst() {
    do { // GX8
        let arm = Arm()
        let root = arm.grid([row(arm.span(arm.fx("x", 100, 10), 2)), row(arm.fx("a", 30, 10), arm.fx("b", 20, 20))])
        #expect(arm.run(root, 300, 100) == size(100, 38), "GX8 size")
        expectRects(arm, "GX8", ["x": r(0, 0, 100, 10), "a": r(10.5, 23, 30, 10), "b": r(69.5, 18, 20, 20)])
        #expect(arm.proposals("x").contains(proposal(300, 46)), "GX8 x is offered 300×46: \(arm.proposals("x"))")
    }
    do { // GX9
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fl("b")), row(arm.span(arm.fx("x", 100, 10), 2))])
        #expect(arm.run(root, 300, 100) == size(300, 100), "GX9 size")
        expectRects(arm, "GX9", ["a": r(0, 36, 30, 10), "b": r(38, 0, 262, 82), "x": r(100, 90, 100, 10)])
    }
    do { // GX10
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 10)), row(arm.span(arm.fl("x"), 2))])
        #expect(arm.run(root, 300, 100) == size(300, 100), "GX10 size")
        expectRects(arm, "GX10", ["a": r(60.5, 0, 30, 10), "b": r(219.5, 0, 20, 10), "x": r(0, 18, 300, 82)])
    }
    do { // GX12
        let arm = Arm()
        let root = arm.grid([row(arm.cb("a", 20, 120), arm.cw("b", 0, 60, 30)), .full(arm.fw("x", 10))])
        #expect(arm.run(root, 300, 200) == size(300, 114), "GX12 size")
        expectRects(arm, "GX12", ["a": r(28, 0, 120, 96), "b": r(212, 33, 60, 30), "x": r(0, 104, 300, 10)])
    }
}

// MARK: 2.9 the model's disagreements with SwiftUI

/// GR-B and GR-F: where the reference model disagrees with SwiftUI the kernel
/// follows the model. **Pinned wrong on purpose**; SwiftUI's figures (probe
/// revision 5, `model-arms`):
///
/// - GX17 `[a 30x10, b flexible, c 20x20] [x 150x10 span 3]` at 200×100: SwiftUI
///   284×100 (the span overflow), a (0,36), b (38,0 218×82), c (264,31), x (67,90).
/// - GX18 `[a flexible, b width 10…30, c width 20…50] x 60x10 (non-row)` at
///   200×100: SwiftUI 231.33×100, a (0,0 135.33×82), b (143.33,36), c
///   (181.33,36), x (85.67,90).
/// - GS4 `[a half] [Spacer s, c width 30…180 h20]` at 60×60: SwiftUI 90×40, a
///   (0,0 30×10), c (30,15 60×20), s (0,10 30×30).
/// - GS5 `[a 40x40] [b half, c 20x40 span 2] [d width 0…30 h40]` at 300×200:
///   SwiftUI 76.67×136, a (4.33,0), b (12.17,63 24.33×10), c (56.67,48), d
///   (9.33,96).
///
/// GX19 (GX18 with x 40 wide) is the control on which SwiftUI and the model
/// agree: 200×100, x (80,90 40×10).
///
/// Mutation: skip `absorbSpan` at proposals other than nil×nil (GX17 and GS5
/// move; recorded by the lane).
@Test func theModelsDisagreementsWithSwiftUIArePinned() {
    do { // GX17
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fl("b"), arm.fx("c", 20, 20)), row(arm.span(arm.fx("x", 150, 10), 3))])
        #expect(arm.run(root, 200, 100) == size(200, 100), "GX17 size")
        expectRects(arm, "GX17", ["a": r(0, 36, 30, 10), "b": r(38, 0, 134, 82), "c": r(180, 31, 20, 20), "x": r(25, 90, 150, 10)])
    }
    func gx18(_ width: Double) -> Arm {
        let arm = Arm()
        arm.run(arm.grid([row(arm.fl("a"), arm.cw("b", 10, 30), arm.cw("c", 20, 50)), .full(arm.fx("x", width, 10))]), 200, 100)
        return arm
    }
    do { // GX18
        let arm = gx18(60)
        #expect(arm["grid"] == r(0, 0, 200, 100), "GX18 size")
        expectRects(arm, "GX18", ["a": r(0, 0, 104, 82), "b": r(112, 36, 30, 10), "c": r(150, 36, 50, 10), "x": r(70, 90, 60, 10)])
    }
    do { // GX19
        let arm = gx18(40)
        #expect(arm["grid"] == r(0, 0, 200, 100), "GX19 size")
        expectRects(arm, "GX19", ["a": r(0, 0, 104, 82), "b": r(112, 36, 30, 10), "c": r(150, 36, 50, 10), "x": r(80, 90, 40, 10)])
    }
    do { // GS4
        let arm = Arm()
        let root = arm.grid([row(arm.hf("a")), row(arm.spacer("s"), arm.cw("c", 30, 180, 20))])
        #expect(arm.run(root, 60, 60) == size(45, 40), "GS4 size")
        expectRects(arm, "GS4", ["a": r(0, 0, 15, 10), "c": r(15, 15, 30, 20), "s": r(0, 10, 15, 30)])
    }
    do { // GS5
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 40, 40)), row(arm.hf("b"), arm.span(arm.fx("c", 20, 40), 2)),
                             row(arm.cw("d", 0, 30, 40))])
        #expect(arm.run(root, 300, 200) == size(164, 136), "GS5 size")
        expectRects(arm, "GS5", ["a": r(48, 0, 40, 40), "b": r(34, 63, 68, 10), "c": r(144, 48, 20, 40), "d": r(53, 96, 30, 40)])
    }
}

// MARK: 2.10 no priority passed to a stack

/// GR-R: `nativeLayoutPriority` of a grid is 0, one cell or many.
///
/// - GE8 `HStack{a flexible; Grid{[c flexible priority 1]}}` at 100×100: 46/46,
///   against GE27 (the same HStack with no grid) 0/92.
/// - GE10 `HStack{a flexible; Grid{[c flexible priority 1, d 10x10]}}`: **pinned
///   wrong on purpose** at the kernel's 46/38/10 (the stack 110 wide); SwiftUI
///   reads 36/38/10. Not the grid's doing (ruling GR-X): the grid and `a` both
///   answer ∞ at main ∞, and MetalUI's stack breaks that tie in declaration
///   order (CN-B) where SwiftUI served the grid, larger at 0 (18), first; probe
///   `swiftui-grid-stack-ties.swift` T1, and T7 with no grid. The grid's own
///   answer to its 46 offer (56 = 38 + 8 + 10) is the model's.
/// - GE11 `HStack{a flexible; Grid{[Spacer s]}}`: 50/50, against GE28 (no grid)
///   92/8.
///
/// Mutation: the `.grid` arm passes a one-cell grid's child priority, as a
/// one-child stack does (GE8 reads 0/92, GE11 92/8).
@Test func aGridPassesNoPriorityToAnEnclosingStack() throws {
    let ge8 = Arm()
    ge8.run(ge8.hstack("stack", [ge8.fl("a"), ge8.grid([row(ge8.prio(ge8.fl("c"), 1))])]), 100, 100)
    let ge27 = Arm()
    ge27.run(ge27.hstack("stack", [ge27.fl("a"), ge27.prio(ge27.fl("c"), 1)]), 100, 100)
    try #require(ge8["a"] != ge27["a"], "GE8 and its control GE27 must differ")
    expectRects(ge8, "GE8", ["a": r(0, 0, 46, 100), "c": r(54, 0, 46, 100)])
    expectRects(ge27, "GE27", ["a": r(0, 0, 0, 100), "c": r(8, 0, 92, 100)])

    let ge10 = Arm()
    ge10.run(ge10.hstack("stack", [ge10.fl("a"), ge10.grid([row(ge10.prio(ge10.fl("c"), 1), ge10.fx("d", 10, 10))])]), 100, 100)
    expectRects(ge10, "GE10 (pinned wrong on purpose, GR-X)", ["a": r(0, 0, 46, 100), "c": r(54, 0, 38, 100), "d": r(100, 45, 10, 10)])

    let ge11 = Arm()
    ge11.run(ge11.hstack("stack", [ge11.fl("a"), ge11.grid([row(ge11.spacer("s"))])]), 100, 100)
    let ge28 = Arm()
    ge28.run(ge28.hstack("stack", [ge28.fl("a"), ge28.spacer("s")]), 100, 100)
    try #require(ge11["a"] != ge28["a"], "GE11 and its control GE28 must differ")
    expectRects(ge11, "GE11", ["a": r(0, 0, 50, 100), "s": r(50, 0, 50, 100)])
    expectRects(ge28, "GE28", ["a": r(0, 0, 92, 100), "s": r(92, 50, 8, 0)])
}

// MARK: 2.11 grids inside stacks

/// GR-R: a grid in a stack lays out as the model does in that stack (GE17–GE22,
/// each agreeing with SwiftUI in the probe), and the edge arms of 1.10/1.11 are
/// laid out here, where the stack proposes the grid a concrete cross axis
/// (GR-W).
///
/// **GE19 is pinned wrong on purpose** (ruling GR-X): SwiftUI reads the stack
/// 200×100, z (0,0 200×34), a (0,42 152×20), b (170,42), c (71,70), d (160,80),
/// serving the grid (58 tall at 0, ∞ at ∞) before the flexible z declared
/// first; MetalUI's stack keeps declaration order on that tie (CN-B), so z takes
/// 46 and the grid answers 58 to its 46 offer: 200×112. The cause is the stack's,
/// not the grid's: the control T7 (`VStack{z flexible; b height ≥ 58}`, no grid)
/// reads z 46 here where SwiftUI reads 34 (probe `swiftui-grid-stack-ties.swift`).
///
/// Mutation (GZ0's control): every group offered W′/ncols, commits ignored (GE17
/// moves; recorded by the lane).
@Test func aGridInAStackLaysOutAsTheModelInAStack() {
    func ga1Grid(_ arm: Arm, flexibleA: Bool) -> LayoutNodeID { ga1(arm, flexibleA: flexibleA) }
    do { // GE17
        let arm = Arm()
        arm.run(arm.hstack("stack", [arm.fl("z"), ga1Grid(arm, flexibleA: true)]), 200, 100)
        #expect(arm["stack"] == r(0, 0, 200, 100), "GE17 size")
        expectRects(arm, "GE17", ["a": r(104, 0, 48, 62), "b": r(170, 21, 20, 20), "c": r(123, 70, 10, 30), "d": r(160, 80, 40, 10), "z": r(0, 0, 96, 100)])
    }
    do { // GE18
        let arm = Arm()
        arm.run(arm.hstack("stack", [arm.fw("z", 20), ga1Grid(arm, flexibleA: false)]), 200, 100)
        #expect(arm["stack"] == r(0, 0, 200, 58), "GE18 size")
        expectRects(arm, "GE18", ["a": r(122, 5, 30, 10), "b": r(170, 0, 20, 20), "c": r(132, 28, 10, 30), "d": r(160, 38, 40, 10), "z": r(0, 19, 114, 20)])
    }
    do { // GE19
        let arm = Arm()
        arm.run(arm.vstack("stack", [arm.fl("z"), ga1Grid(arm, flexibleA: true)]), 200, 100)
        #expect(arm["stack"] == r(0, 0, 200, 112), "GE19 size (pinned wrong on purpose, GR-X)")
        expectRects(arm, "GE19 (pinned wrong on purpose, GR-X)",
                    ["a": r(0, 54, 152, 20), "b": r(170, 54, 20, 20), "c": r(71, 82, 10, 30), "d": r(160, 92, 40, 10), "z": r(0, 0, 200, 46)])
    }
    do { // T7, the stack-only control for GE19 (probe swiftui-grid-stack-ties.swift): SwiftUI z 34, b 58
        let arm = Arm()
        let b = arm.leaf("b") { SizeD(width: $0.width ?? 10, height: Swift.max($0.height ?? 10, 58)) }
        arm.run(arm.vstack("stack", [arm.fl("z"), b]), 200, 100)
        expectRects(arm, "T7 (pinned wrong on purpose, GR-X)", ["stack": r(0, 0, 200, 112), "z": r(0, 0, 200, 46), "b": r(0, 54, 200, 58)])
    }
    do { // GE20
        let arm = Arm()
        let grid = arm.grid([row(arm.hf("b"), arm.fl("x")), row(arm.fx("e", 10, 30))])
        arm.run(arm.hstack("stack", [arm.cw("z", 0, 100, 10), grid]), 150, 80)
        #expect(arm["stack"] == r(0, 0, 150, 80), "GE20 size")
        expectRects(arm, "GE20", ["b": r(82.9375, 16, 7.875, 10), "e": r(81.875, 50, 10, 30), "x": r(102.75, 0, 47.25, 42), "z": r(0, 35, 71, 10)])
    }
    do { // GE21
        let arm = Arm()
        arm.run(arm.hstack("stack", [arm.fx("z", 30, 10), ga1Grid(arm, flexibleA: true)]), nil, 80)
        #expect(arm["stack"] == r(0, 0, 96, 80), "GE21 size")
        expectRects(arm, "GE21", ["a": r(38, 0, 10, 42), "b": r(66, 11, 20, 20), "c": r(38, 50, 10, 30), "d": r(56, 60, 40, 10), "z": r(0, 35, 30, 10)])
    }
    do { // GE22
        let arm = Arm()
        let grid = arm.grid([row(arm.cw("a", 0, 60), arm.fh("b", 10)), row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        arm.run(arm.vstack("stack", [arm.hf("z"), grid]), 120, nil)
        #expect(arm["stack"] == r(0, 0, 108, 66), "GE22 size")
        expectRects(arm, "GE22", ["a": r(0, 18, 60, 10), "b": r(83, 18, 10, 10), "c": r(25, 36, 10, 30), "d": r(68, 46, 40, 10), "z": r(24, 0, 60, 10)])
    }

    func hArm(_ grid: (Arm) -> LayoutNodeID) -> Arm {
        let arm = Arm()
        let a = arm.fx("a", 30, 10)
        let g = grid(arm)
        arm.run(arm.hstack("stack", [a, g, arm.fx("c", 10, 10)]), nil, nil)
        return arm
    }
    func vArm(_ grid: (Arm) -> LayoutNodeID) -> Arm {
        let arm = Arm()
        let a = arm.fx("a", 30, 10)
        let g = grid(arm)
        arm.run(arm.vstack("stack", [a, g, arm.fx("c", 10, 10)]), nil, nil)
        return arm
    }
    let ge1 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20))]) }
    expectRects(ge1, "GE1", ["stack": r(0, 0, 76, 20), "a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "c": r(66, 5, 10, 10), "s": r(30, 0, 8, 20)])
    let ge2 = hArm { $0.grid([row($0.fx("s", 8, 8), $0.fx("b", 20, 20))]) }
    expectRects(ge2, "GE2", ["stack": r(0, 0, 92, 20), "a": r(0, 5, 30, 10), "s": r(38, 6, 8, 8), "b": r(54, 0, 20, 20), "c": r(82, 5, 10, 10)])
    let ge3 = hArm { $0.grid([row($0.fx("b", 20, 20), $0.spacer("s"))]) }
    expectRects(ge3, "GE3", ["stack": r(0, 0, 76, 20), "a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "c": r(66, 5, 10, 10), "s": r(58, 0, 8, 20)])
    let ge4 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20)), row($0.fx("d", 20, 20), $0.fx("e", 20, 20))]) }
    expectRects(ge4, "GE4", ["stack": r(0, 0, 96, 48), "a": r(0, 19, 30, 10), "b": r(58, 0, 20, 20), "d": r(30, 28, 20, 20),
                             "e": r(58, 28, 20, 20), "c": r(86, 19, 10, 10), "s": r(30, 0, 20, 20)])
    let ge5 = hArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20)), row($0.spacer("t"), $0.fx("e", 20, 20))]) }
    expectRects(ge5, "GE5", ["stack": r(0, 0, 76, 48), "a": r(0, 19, 30, 10), "b": r(38, 0, 20, 20), "e": r(38, 28, 20, 20),
                             "c": r(66, 19, 10, 10), "t": r(30, 28, 8, 20), "s": r(30, 0, 8, 20)])
    let ge6 = vArm { $0.grid([row($0.spacer("s")), row($0.fx("b", 20, 20))]) }
    expectRects(ge6, "GE6", ["stack": r(0, 0, 30, 56), "a": r(0, 0, 30, 10), "b": r(5, 18, 20, 20), "c": r(10, 46, 10, 10), "s": r(5, 10, 20, 8)])
    let ge7 = vArm { $0.grid([row($0.fx("s", 8, 8)), row($0.fx("b", 20, 20))]) }
    expectRects(ge7, "GE7", ["stack": r(0, 0, 30, 72), "a": r(0, 0, 30, 10), "s": r(11, 18, 8, 8), "b": r(5, 34, 20, 20), "c": r(10, 62, 10, 10)])
    let ge16 = hArm { $0.grid([]) }
    expectRects(ge16, "GE16", ["stack": r(0, 0, 40, 10), "a": r(0, 0, 30, 10), "c": r(30, 0, 10, 10)])
    let ge23 = vArm { $0.grid([row($0.spacer("s"), $0.fx("b", 20, 20))]) }
    expectRects(ge23, "GE23", ["stack": r(0, 0, 30, 40), "a": r(0, 0, 30, 10), "b": r(10, 10, 20, 20), "c": r(10, 30, 10, 10), "s": r(0, 10, 10, 20)])
    let ge24 = vArm { $0.grid([row($0.fx("b", 20, 20)), row($0.spacer("s"))]) }
    expectRects(ge24, "GE24", ["stack": r(0, 0, 30, 56), "a": r(0, 0, 30, 10), "b": r(5, 18, 20, 20), "c": r(10, 46, 10, 10), "s": r(5, 38, 20, 8)])
    let ge25 = hArm { $0.grid([row($0.fx("b", 20, 20)), .full($0.spacer("s"))]) }
    expectRects(ge25, "GE25", ["stack": r(0, 0, 60, 28), "a": r(0, 9, 30, 10), "b": r(30, 0, 20, 20), "c": r(50, 9, 10, 10), "s": r(30, 20, 20, 8)])
    let ge26 = hArm { $0.grid([row($0.fx("b", 20, 20), $0.fx("e", 20, 20)), row($0.spacer("s"))]) }
    expectRects(ge26, "GE26", ["stack": r(0, 0, 96, 28), "a": r(0, 9, 30, 10), "b": r(30, 0, 20, 20), "e": r(58, 0, 20, 20),
                               "c": r(86, 9, 10, 10), "s": r(30, 20, 20, 8)])

    do { // GE29
        let arm = Arm()
        let grid = arm.grid([row(arm.spacer("s"), arm.fx("b", 20, 20))])
        arm.run(arm.hstack("stack", [arm.fx("a", 30, 10), arm.vstack("v", [grid]), arm.fx("c", 10, 10)]), nil, nil)
        expectRects(arm, "GE29", ["stack": r(0, 0, 76, 20), "a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "c": r(66, 5, 10, 10), "s": r(30, 0, 8, 20)])
    }
    do { // GE30
        let arm = Arm()
        arm.run(arm.hstack("stack", [arm.fx("a", 30, 10), arm.vstack("v", [arm.spacer("s"), arm.fx("b", 20, 20)]), arm.fx("c", 10, 10)]), nil, nil)
        expectRects(arm, "GE30", ["stack": r(0, 0, 76, 28), "a": r(0, 9, 30, 10), "b": r(38, 8, 20, 20), "c": r(66, 9, 10, 10), "s": r(48, 0, 0, 8)])
    }
}

// MARK: 2.13 the corpus

/// GR-B's exit test: the probe's replay corpus (`GridCorpus.swift`, 120 grids on
/// which SwiftUI and the reference model agree), each built from native leaves
/// standing for the probe's kinds — a written priority a `layoutPriority` node,
/// a span a column mark on the cell's outermost node, a `spacer` a bare
/// `newNativeSpacer()` — laid out at its proposal at the origin and compared
/// with the recorded answer (to 1e-9) and `roundLayout` of every recorded rect.
/// **Lane 2 filters** to the cases with no anchor, column alignment or unsized
/// axis, which it requires to be 18; lane 3 drops the filter.
///
/// Mutation (GZ0's control): recorded by the lane, how many of the 18 redden.
@Test func theGridProbeCorpusAgreesCaseByCase() throws {
    try #require(gridCorpus.count == 120, "the corpus holds 120 cases")
    let cases = gridCorpus.filter { corpusCase in
        corpusCase.cells.allSatisfy { $0.anchor == nil && $0.columnAlignment == nil && !$0.unsizedHorizontal && !$0.unsizedVertical }
    }
    try #require(cases.count == 18, "lane 2 runs the 18 cases with no anchor, column alignment or unsized axis")
    for corpusCase in cases {
        let tree = LayoutTree(generation: 0)
        var children: [LayoutNodeID] = []
        var leaves: [LayoutNodeID] = []
        func cell(_ cell: GridCorpusCase.Cell) -> LayoutNodeID {
            var node: LayoutNodeID
            switch cell.kind {
            case .spacer:
                node = tree.newNativeSpacer()
            default:
                let kind = cell.kind
                node = tree.newNativeLeaf { LayoutMeasurement(size: kind.answer($0)) }
            }
            leaves.append(node)
            if cell.priority != 0 { node = tree.newNativeLayoutPriority(child: node, priority: cell.priority) }
            if cell.span != 1 { tree.markNativeGridCell(node, columns: cell.span) }
            return node
        }
        for child in corpusCase.children {
            switch child {
            case let .row(alignment, cells):
                let nodes = cells.map(cell)
                tree.markNativeGridRow(nodes, alignment: alignment)
                children += nodes
            case let .spanning(spanning):
                children.append(cell(spanning))
            }
        }
        let grid = tree.newNativeGrid(children: children, alignment: corpusCase.alignment,
                                      horizontalSpacing: corpusCase.horizontalSpacing,
                                      verticalSpacing: corpusCase.verticalSpacing)
        let at = ProposedSize(width: corpusCase.proposal.0, height: corpusCase.proposal.1)
        let answer = tree.measureNativeLayout(root: grid, proposal: at).size
        let expected = SizeD(width: corpusCase.size.0, height: corpusCase.size.1)
        #expect(close(answer, expected), "corpus \(corpusCase.id) answer \(answer), recorded \(expected)")
        tree.computeNativeLayout(root: grid, proposal: at, in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
        try #require(leaves.count == corpusCase.rects.count, "corpus \(corpusCase.id) leaf count")
        for (index, leaf) in leaves.enumerated() {
            let recorded = corpusCase.rects[index]
            let rect = r(recorded.0, recorded.1, recorded.2, recorded.3)
            #expect(tree.layout(leaf) == rect, "corpus \(corpusCase.id) leaf c\(index + 1): \(tree.layout(leaf)), recorded \(rect)")
        }
    }
}
