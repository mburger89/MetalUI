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

    /// A written `.gridCellAnchor(a)` (lane 3).
    func anchor(_ node: LayoutNodeID, _ alignment: ProposalAlignment) -> LayoutNodeID {
        tree.markNativeGridCell(node, anchor: alignment)
        return node
    }

    /// A written `.gridColumnAlignment(a)` (lane 3).
    func colAlign(_ node: LayoutNodeID, _ alignment: ProposalAlignment) -> LayoutNodeID {
        tree.markNativeGridCell(node, columnAlignment: alignment)
        return node
    }

    /// A written `.gridCellUnsizedAxes(axes)` (lane 3).
    func unsized(_ node: LayoutNodeID, _ axes: ProposalAxes) -> LayoutNodeID {
        tree.markNativeGridCell(node, unsizedAxes: axes)
        return node
    }

    /// `dbl`: twice the proposed width (20 at nil), fixed height (lane 3).
    func dbl(_ name: String, _ h: Double = 10) -> LayoutNodeID {
        leaf(name) { SizeD(width: ($0.width ?? 10) * 2, height: h) }
    }

    /// A `.padding(inset)` wrapper (lane 3).
    func pad(_ node: LayoutNodeID, _ inset: Double) -> LayoutNodeID {
        tree.newNativePadding(child: node, insets: Edges(all: inset))
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
/// - T1 `[b, e]` plus a non-row Spacer (which spans both columns): 88×28.
///   T2 the same boundary reached by a row Spacer with `columns: 2`: 88×28.
///   Both from `docs/probes/swiftui-grid-span-edges.swift`, whose C0 and C1
///   reproduce GE25 and GE26.
///
/// Mutations: (a) answer "any cell", as `.custom` does (GE3 reads 68, GE24
/// 48); (b) answer neither edge (GE1 reads 84); (c) the trailing predicate
/// reads `$0.column == plan.columnCount - 1` — the cell must START at the
/// last column — which every GE arm agrees with and T1/T2 read 96 under.
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
    // T1/T2 (`docs/probes/swiftui-grid-span-edges.swift`): the cell reaching the
    // last column SPANS. GE3, GE25 and GE26 all put a single-column cell at the
    // boundary, so "ends at the last column" and "starts at" agree on every one
    // of them; here they differ by the 8pt gap, and GE26's own 96 is what the
    // wrong spelling gives. Both are 88 in SwiftUI.
    let t1 = hArm { $0.grid([row($0.fx("b", 20, 20), $0.fx("e", 20, 20)), .full($0.spacer("s"))]) }
    try #require(t1 != ge26, "T1 must differ from GE26, or the trailing edge is unread")
    #expect(t1 == size(88, 28), "T1 \(t1)")
    let t2 = hArm {
        $0.grid([row($0.fx("b", 20, 20), $0.fx("e", 20, 20)), row($0.span($0.spacer("s"), 2))])
    }
    #expect(t2 == size(88, 28), "T2 \(t2)")
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
/// - GF19–GF18: a greedy `frame(maxWidth: .infinity)` cell (and at nil), a
///   proposal-responsive leaf standing for `Color` (and at nil), a frame
///   greedy on both axes.
/// - GR2 `[a odd, b 20x20]` at 200×200: a placed at the 96×200 it was measured
///   at, never at its 20×20 slot.
///
/// - R1 `[a 50x10 prio 2, b 10x10 prio 2] [c clamp 0…200 prio 1, e clamp 0…300]`
///   at 300×100: the committed widths are a RUNNING sum. The priority-2 group
///   commits columns 0 and 1 at 50 and 10; the priority-1 group then widens
///   column 0 to 200, and e's group must see 210 committed, so it is offered
///   292 − 210 = 82 and the grid answers 290×28. Let the sum go stale and e
///   sees 60, is offered 232 and answers it: 440×28. Probed in
///   `docs/probes/swiftui-grid-finite-shares.swift` (arm R1), where SwiftUI
///   also reads 290×28.
///
/// Mutations: (a) (GZ0's control) every group offered W′/ncols, commits ignored
/// (GP2's a at 96); (b) `widen`'s `if committedColumn[column] { committedWidth
/// += value - old }` deleted — the running sum goes stale (R1 reads 440×28, and
/// nothing else in the suite moves).
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
    do { // GF19
        let arm = Arm()
        let a = arm.tree.newNativeFrame(child: arm.fx("a", 30, 10), maxWidth: .infinity)
        #expect(arm.run(withFirst(arm, a), 200, 100) == size(200, 58), "GF19 size")
        expectRects(arm, "GF19", ["a": r(61, 5, 30, 10), "b": r(170, 0, 20, 20), "c": r(71, 28, 10, 30), "d": r(160, 38, 40, 10)])
    }
    do { // GF20
        let arm = Arm()
        let a = arm.tree.newNativeFrame(child: arm.fx("a", 30, 10), maxWidth: .infinity)
        #expect(arm.run(withFirst(arm, a), nil, nil) == size(78, 58), "GF20 size")
        expectRects(arm, "GF20", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20), "c": r(10, 28, 10, 30), "d": r(38, 38, 40, 10)])
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
    do { // R1 — the committed widths are a RUNNING sum, re-read after a widen
        let arm = Arm()
        let a = arm.prio(arm.fx("a", 50, 10), 2), b = arm.prio(arm.fx("b", 10, 10), 2)
        let c = arm.prio(arm.cw("c", 0, 200), 1)
        let root = arm.grid([row(a, b), row(c, arm.cw("e", 0, 300))])
        #expect(arm.run(root, 300, 100) == size(290, 28), "R1 size")
        expectRects(arm, "R1", ["a": r(75, 0, 50, 10), "b": r(244, 0, 10, 10),
                                "c": r(0, 18, 200, 10), "e": r(208, 18, 82, 10)])
        #expect(arm.proposals("e").contains(proposal(82, 72)),
                "R1 e is offered 292 − 210 committed: \(arm.proposals("e"))")
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
/// - GF19 `[a width-flexible h20] [b clamp 10…80]` at nil × 100 and GF20 at
///   100×100: required to differ.
///
/// **The clause is TWO guards in the source, one per axis, and each is mutated
/// on its own** (CLAUDE.md: "a copy of a pinned implementation is unpinned").
/// GF12/GF13 hold the height guard; GF19/GF20 the width one, whose own deletion
/// left the whole suite green until they were written (`GR-AJ`). GF19's two
/// cells change ORDER if the nil width axis counts: `a`'s ∞ answer is
/// infinitely wide and `b`'s is 80, so counting the width would put `b` (no
/// infinite axis) before `a` (one), where counting only the height puts `a`
/// (flexibility 0) before `b` (70). SwiftUI serves `a` first and answers
/// 10×100 (`docs/probes/swiftui-grid-nil-width-key.swift`, N1; its control N0
/// is GF20, where the finite width DOES count and `b` goes first).
///
/// Mutation: key = the finite sum with ∞ as +∞, one group for equal sums
/// (GF10's b at 96). Mutation: `provide`'s `if proposal.width != nil` →
/// `if true` (GF19 answers 10×74, its b 10×46 at y 28).
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
    func gf19Arm(_ width: Double?) -> (Arm, SizeD) {
        let arm = Arm()
        let answer = arm.run(arm.grid([row(arm.fw("a", 20)), row(arm.cb("b", 10, 80))]), width, 100)
        return (arm, answer)
    }
    let (gf19, gf19Size) = gf19Arm(nil), (gf20, gf20Size) = gf19Arm(100)
    try #require(gf19Size != gf20Size, "GF19 and its control GF20 must differ")
    #expect(gf19Size == size(10, 100), "GF19 size")
    expectRects(gf19, "GF19", ["a": r(0, 0, 10, 20), "b": r(0, 28, 10, 72)])
    #expect(gf20Size == size(100, 74), "GF20 size")
    expectRects(gf20, "GF20", ["a": r(0, 0, 100, 20), "b": r(10, 28, 80, 46)])
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
/// The target rule has three steps, and GX8–GX12 reach only two of them at a
/// finite proposal: a spanned column still holding an unprocessed single (GX9)
/// and, failing that, every spanned column (GX8). The MIDDLE step — the spanned
/// columns holding no single-column cell anywhere in the grid — had an arm only
/// at nil×nil (GX11, in `aSpanShortfallAtNilGoesFirstToSpannedColumnsWithNoSingleColumnCell`),
/// where the other solve runs, so deleting it from `NativeGridSolver.finishGroup`
/// left the whole 1450-test suite green (lane-2 re-verification, ruling
/// `GR-AG`). S1 and S2 are the discriminators, probed now in
/// `docs/probes/swiftui-grid-span-targets.swift` against GX8 and GX11 as
/// positive controls; the probe reads the same rects at nil×nil, so the two
/// branches agree.
///
/// - S1 `[a 20x20] [x 60x20 span 2]` at 200×200: column 1 is spanned only, so
///   the whole 40pt shortfall goes there and **a stays at x = 0**; over both
///   columns it would be 20/20 and a would centre in a 40-wide column 0, at 10.
/// - S2 `[a 20x20, b 30x20] [d 10x20, x 90x20 span 2]` at 300×200: column 2 is
///   spanned only, so it takes the whole 60pt shortfall and **b stays at
///   x = 28**; over both it would be 30/30 and b would centre at 43.
///
/// Neither grid has a cell pair meeting at its last column boundary, so that
/// gap is 0 and not the 8pt default (`GR-D`); SwiftUI's 60×48 and 118×48 are
/// what the probe reads.
///
/// F1 `[a 200x10, b 10x10] [x span 2]` at 100×100 is the FLOOR in that same
/// line, `Swift.max(…, spanWidth(cell))`: W′ is 92 but the span's own columns
/// already sum 218, and SwiftUI proposes the larger, so x reads its "at least
/// 200 wide" height of 40 and the grid answers 218×58. Dropping the floor
/// proposes 100, x answers 20 tall and the grid reads 218×38 — green across the
/// whole suite until this arm, because GX8 serves its span FIRST, with every
/// column still 0. Probed in `docs/probes/swiftui-grid-finite-shares.swift`
/// (arm F1, controls GX8 and GX12).
///
/// Mutations: (a) propose a span the sum of its columns' shares plus inner gaps
/// (GX10's x moves); (b) drop step 12 (GX9's b 231, a's column 61); (c) drop the
/// middle target step, `targets = columns.filter { plan.columnSingleCells[$0].isEmpty }`
/// (S1's a at 10, S2's b at 43, and nothing else in the suite); (d) drop the
/// span proposal's floor, `Swift.max(…, spanWidth(cell))` (F1 reads 218×38).
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
    do { // S1 — the middle target step at a finite proposal (probe swiftui-grid-span-targets.swift)
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 20, 20)), row(arm.span(arm.fx("x", 60, 20), 2))])
        #expect(arm.run(root, 200, 200) == size(60, 48), "S1 size")
        expectRects(arm, "S1", ["a": r(0, 0, 20, 20), "x": r(0, 28, 60, 20)])
    }
    do { // S2 — the same step where the span's other column's singles are merely processed
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 20, 20), arm.fx("b", 30, 20)),
                             row(arm.fx("d", 10, 20), arm.span(arm.fx("x", 90, 20), 2))])
        #expect(arm.run(root, 300, 200) == size(118, 48), "S2 size")
        expectRects(arm, "S2", ["a": r(0, 0, 20, 20), "b": r(28, 0, 30, 20),
                                "d": r(5, 28, 10, 20), "x": r(28, 28, 90, 20)])
    }
    do { // F1 — the span proposal's FLOOR at its own columns' sum
        let arm = Arm()
        // 60 wide; 40 tall only when proposed at least 200 wide, so its height
        // reads back the width the solve offered it.
        let x = arm.leaf("x") { SizeD(width: 60, height: ($0.width ?? 0) >= 200 ? 40 : 20) }
        let root = arm.grid([row(arm.fx("a", 200, 10), arm.fx("b", 10, 10)), row(arm.span(x, 2))])
        #expect(arm.run(root, 100, 100) == size(218, 58), "F1 size")
        expectRects(arm, "F1", ["a": r(0, 0, 200, 10), "b": r(208, 0, 10, 10), "x": r(79, 18, 60, 40)])
        #expect(arm.proposals("x").contains(proposal(218, 82)), "F1 x is offered its columns' 218: \(arm.proposals("x"))")
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
/// - O1 `[a 20x10, b 30x10, c w40 height-flexible] [x clamp 0…250 span 2, d
///   40x10]` at 300×100: SwiftUI **245.33×100**, a (34.83,36), b (132.50,36),
///   c (205.33,0 40×82), d (205.33,90), x (0,90 197.33×10) — it charges the
///   open column outside the span 94.67, W′ ÷ 3 with nothing committed. The
///   model charges that column its group's share at the moment it is served,
///   (284 − 50) ÷ 1 = 234, and proposes x 58: **106×100**. Both readings are
///   from `docs/probes/swiftui-grid-finite-shares.swift` (arm O1) and from
///   `swiftui-grid.swift`'s own `model-arms` mode with O1 added, which reads the
///   model at 106×100 rect for rect — so the kernel follows the model here, as
///   `GR-B` says it does, and the disagreement is the model's, not a solver bug.
///   Without this arm, making the outside term always `widths[column]` (298×100)
///   left the whole suite green.
///
/// Mutations: (a) skip `absorbSpan` at proposals other than nil×nil (GX17 and
/// GS5 move; recorded by the lane); (b) `NativeGridSolver.serve`'s
/// `outside += levelInColumn[column] > 0 ? shareW : widths[column]` made always
/// `widths[column]` (O1 reads 298×100).
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
    do { // O1 — the share charged to an OPEN column outside a span
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 20, 10), arm.fx("b", 30, 10), arm.fh("c", 40)),
                             row(arm.span(arm.cw("x", 0, 250), 2), arm.fx("d", 40, 10))])
        #expect(arm.run(root, 300, 100) == size(106, 100), "O1 size")
        expectRects(arm, "O1", ["a": r(0, 36, 20, 10), "b": r(28, 36, 30, 10), "c": r(66, 0, 40, 82),
                                "d": r(66, 90, 40, 10), "x": r(0, 90, 58, 10)])
        #expect(arm.proposals("x").contains(proposal(58, 46)),
                "O1 x is offered 284 − 234 + 8, the open column charged its group's share: \(arm.proposals("x"))")
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
/// not the grid's: the control T7 (`VStack{z flexible; b height ≥ 58}`, **no
/// grid at all**) reads z 46 where SwiftUI reads 34 (probe
/// `swiftui-grid-stack-ties.swift`). **T7 lives in
/// `NativeStackDistributionTests.swift`** since lane 3 (second critic round,
/// finding 9; `GR-O` item 8), where `CN-B`'s tie belongs, so a later reader
/// does not take it for grid behaviour.
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
/// **Lane 3 drops lane 2's filter**: anchors, column alignment and unsized axes
/// are implemented, so all 120 cases run and `#require` says so.
///
/// Mutations, each with how many of the 120 it reddens, recorded by the lane:
/// GZ0's control (every group offered W′/ncols, commits ignored); the last
/// column-alignment declaration winning instead of the first; and not absorbing
/// an unsized cell's answer on its unsized axis.
@Test func theGridProbeCorpusAgreesCaseByCase() throws {
    try #require(gridCorpus.count == 120, "the corpus holds 120 cases")
    for corpusCase in gridCorpus {
        let built = buildGridCase(corpusCase)
        let tree = built.tree
        let at = ProposedSize(width: corpusCase.proposal.0, height: corpusCase.proposal.1)
        let answer = tree.measureNativeLayout(root: built.grid, proposal: at).size
        let expected = SizeD(width: corpusCase.size.0, height: corpusCase.size.1)
        #expect(close(answer, expected), "corpus \(corpusCase.id) answer \(answer), recorded \(expected)")
        tree.computeNativeLayout(root: built.grid, proposal: at, in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
        try #require(built.leaves.count == corpusCase.rects.count, "corpus \(corpusCase.id) leaf count")
        for (index, leaf) in built.leaves.enumerated() {
            let recorded = corpusCase.rects[index]
            let rect = r(recorded.0, recorded.1, recorded.2, recorded.3)
            #expect(tree.layout(leaf) == rect, "corpus \(corpusCase.id) leaf c\(index + 1): \(tree.layout(leaf)), recorded \(rect)")
        }
    }
}

/// Builds one generated case into a fresh tree: a written priority is a
/// `layoutPriority` node, and the span, anchor, column alignment and unsized
/// axes are marked on the cell's **outermost** node, as the probe writes them
/// outside `.layoutPriority`. A `spacer` kind is a bare `newNativeSpacer()`.
/// Shared by 2.13 (the agreeing corpus) and 3.12 (the divergence handful).
private func buildGridCase(_ corpusCase: GridCorpusCase)
    -> (tree: LayoutTree, grid: LayoutNodeID, leaves: [LayoutNodeID]) {
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
        var axes: ProposalAxes = []
        if cell.unsizedHorizontal { axes.insert(.horizontal) }
        if cell.unsizedVertical { axes.insert(.vertical) }
        if cell.span != 1 || cell.anchor != nil || cell.columnAlignment != nil || !axes.isEmpty {
            tree.markNativeGridCell(node, columns: cell.span == 1 ? nil : cell.span,
                                    anchor: cell.anchor, columnAlignment: cell.columnAlignment,
                                    unsizedAxes: axes)
        }
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
    return (tree, grid, leaves)
}

// MARK: - Lane 3: cell attributes and the modifier-chain walk
//
// Rulings GR-F's column sum, GR-G (anchors, column alignment, inner-wins),
// GR-H (`gridCellUnsizedAxes`), GR-I (which wrappers carry a cell attribute)
// and GR-S. Arm names are SwiftUI's, read by `docs/probes/swiftui-grid.swift`
// (the GL, GU, GW and GX groups; the recorded output is
// `docs/probes/swiftui-grid-default-run.txt`).
//
// **An arm line's `<- w x h` is the PLACEMENT proposal, not the measured one**
// (the probe's header says so), so an arm whose measured proposals differ from
// SwiftUI's can still agree on every rect: GU5 and GU6 are exactly that — the
// reference model keeps an unsized cell in its flexibility group (GR-H) where
// SwiftUI serves it later — and the rects below are the ones both produce.

// MARK: 3.1 column alignment

/// GR-G: `gridColumnAlignment` sets the horizontal alignment of a whole column
/// from any row, and **the first declaration in row order, then cell order,
/// wins**. A non-row child declares none (the model's `where !c.isFull`; GX13).
///
/// - GL4 GA1 with b trailing: b at 58, d at 38 (column 1 is 40 wide).
/// - GL5 the declaration in the later row: `[a 10x10, b] [c 30x30 trailing, d]`,
///   a at 20.
/// - GL6 `[a leading] [b] [c 30x10 trailing]`: a and b at 0, not 20.
/// - GL7 reversed `[a trailing] [b] [c leading]`: a and b at 20.
/// - GX13c, the kernel's own arm for GX13's column-alignment half: a non-row
///   child's `gridColumnAlignment` is **ignored**, so column 0 keeps the grid's
///   centre. Backed by the model and by the 17 corpus cases that write a column
///   alignment on a `.spanning` cell (test 2.13), not by a GL arm of its own.
///
/// Mutation: the last declaration wins (GL6's a at x 20). GX13c's own: honour a
/// non-row child's column alignment (its a at x 12).
@Test func columnAlignmentIsTheFirstDeclarationInRowOrder() {
    do { // GL4
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.colAlign(arm.fx("b", 20, 20), .trailing)),
                             row(arm.fx("c", 10, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(78, 58), "GL4 size")
        expectRects(arm, "GL4", ["a": r(0, 5, 30, 10), "b": r(58, 0, 20, 20),
                                 "c": r(10, 28, 10, 30), "d": r(38, 38, 40, 10)])
    }
    do { // GL5
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 10, 10), arm.fx("b", 20, 20)),
                             row(arm.colAlign(arm.fx("c", 30, 30), .trailing), arm.fx("d", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(78, 58), "GL5 size")
        expectRects(arm, "GL5", ["a": r(20, 5, 10, 10), "b": r(48, 0, 20, 20),
                                 "c": r(0, 28, 30, 30), "d": r(38, 38, 40, 10)])
    }
    do { // GL6
        let arm = Arm()
        let root = arm.grid([row(arm.colAlign(arm.fx("a", 10, 10), .leading)),
                             row(arm.fx("b", 10, 10)),
                             row(arm.colAlign(arm.fx("c", 30, 10), .trailing))])
        #expect(arm.run(root, nil, nil) == size(30, 46), "GL6 size")
        expectRects(arm, "GL6", ["a": r(0, 0, 10, 10), "b": r(0, 18, 10, 10), "c": r(0, 36, 30, 10)])
    }
    do { // GL7
        let arm = Arm()
        let root = arm.grid([row(arm.colAlign(arm.fx("a", 10, 10), .trailing)),
                             row(arm.fx("b", 10, 10)),
                             row(arm.colAlign(arm.fx("c", 30, 10), .leading))])
        #expect(arm.run(root, nil, nil) == size(30, 46), "GL7 size")
        expectRects(arm, "GL7", ["a": r(20, 0, 10, 10), "b": r(20, 18, 10, 10), "c": r(0, 36, 30, 10)])
    }
    do { // GX13c
        let arm = Arm()
        let x = arm.colAlign(arm.fx("x", 88, 10), .trailing)
        let root = arm.grid([row(arm.fx("a", 11, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5)), .full(x)])
        #expect(arm.run(root, nil, nil) == size(88, 38), "GX13c size")
        expectRects(arm, "GX13c", ["a": r(6, 5, 11, 10), "b": r(37, 0, 20, 20),
                                   "e": r(77, 7.5, 5, 5), "x": r(0, 28, 88, 10)])
    }
}

// MARK: 3.2 a span and column alignment

/// GR-G: a spanning cell **declares** a column alignment for its first column
/// and **is not itself aligned by it** (GL8 `[a 10x10, b 10x10] [c 30x10 span 2
/// trailing] [d 40x10]`: a at 30 and d at 0 in a 40-wide column 0, while c sits
/// centred at 14 in its 58-wide slot).
///
/// Mutation: align a span by its first column's alignment (c at x 28).
@Test func aSpanDeclaresColumnAlignmentForItsFirstColumnAndIsNotAlignedByIt() {
    let arm = Arm()
    let c = arm.colAlign(arm.span(arm.fx("c", 30, 10), 2), .trailing)
    let root = arm.grid([row(arm.fx("a", 10, 10), arm.fx("b", 10, 10)), row(c), row(arm.fx("d", 40, 10))])
    #expect(arm.run(root, nil, nil) == size(58, 46), "GL8 size")
    expectRects(arm, "GL8", ["a": r(30, 0, 10, 10), "b": r(48, 0, 10, 10),
                             "c": r(14, 18, 30, 10), "d": r(0, 36, 40, 10)])
}

// MARK: 3.3 anchors

/// GR-G: `gridCellAnchor` overrides the column alignment and the row's and the
/// grid's alignment, on **both** axes, and applies to a non-row child.
///
/// - GL10 `[a 10x10 anchor topLeading + column trailing, b 10x30] [c 40x10]`:
///   a at (0, 0), not (30, 0).
/// - GL11 `[a 40x10, b 10x30] x 10x10 anchor .trailing (non-row)`: x at (48, 38)
///   in its 58-wide slot — an anchor DOES reach a non-row child, where its
///   column alignment (3.1's GX13c) does not.
/// - GL13 `Grid(.topLeading) {[row .bottom: a 10x10 column trailing, b 20x40,
///   e 10x10 anchor center] [c, d, f]}`: a (20, 30) by column and row, e
///   (96, 15) by its anchor on both axes.
///
/// Mutation: read the column alignment before the anchor in `fx` (GL10's a at
/// x 30, GL13's e at x 86).
@Test func aCellAnchorBeatsColumnAndRowAlignmentAndAppliesToNonRowChildren() {
    do { // GL10
        let arm = Arm()
        let a = arm.anchor(arm.colAlign(arm.fx("a", 10, 10), .trailing), .topLeading)
        let root = arm.grid([row(a, arm.fx("b", 10, 30)), row(arm.fx("c", 40, 10))])
        #expect(arm.run(root, nil, nil) == size(58, 48), "GL10 size")
        expectRects(arm, "GL10", ["a": r(0, 0, 10, 10), "b": r(48, 0, 10, 30), "c": r(0, 38, 40, 10)])
    }
    do { // GL11
        let arm = Arm()
        let x = arm.anchor(arm.fx("x", 10, 10), .trailing)
        let root = arm.grid([row(arm.fx("a", 40, 10), arm.fx("b", 10, 30)), .full(x)])
        #expect(arm.run(root, nil, nil) == size(58, 48), "GL11 size")
        expectRects(arm, "GL11", ["a": r(0, 10, 40, 10), "b": r(48, 0, 10, 30), "x": r(48, 38, 10, 10)])
    }
    do { // GL13
        let arm = Arm()
        let a = arm.colAlign(arm.fx("a", 10, 10), .trailing)
        let e = arm.anchor(arm.fx("e", 10, 10), .center)
        let root = arm.grid(alignment: .topLeading,
                            [row(a, arm.fx("b", 20, 40), e, alignment: .bottom),
                             row(arm.fx("c", 30, 30), arm.fx("d", 40, 10), arm.fx("f", 30, 30))])
        #expect(arm.run(root, nil, nil) == size(116, 78), "GL13 size")
        expectRects(arm, "GL13", ["a": r(20, 30, 10, 10), "b": r(38, 0, 20, 40), "e": r(96, 15, 10, 10),
                                  "c": r(0, 48, 30, 30), "d": r(38, 48, 40, 10), "f": r(86, 48, 30, 30)])
    }
}

// MARK: 3.4 two marks on one node

/// GR-G, GR-I: on one view the **inner** declaration wins for an anchor and for
/// a column alignment — the inner modifier marks first, so the first mark on a
/// node stands — and the same holds across a wrapper, where the innermost
/// node's mark wins.
///
/// - GL15 `a.columnAlignment(.leading).columnAlignment(.trailing)`: a at 0.
/// - GL16 `c.anchor(.topLeading).anchor(.bottomTrailing)`: c at (0, 58).
/// - GWI3 inner anchor `.topLeading`, `padding(1)`, outer `.bottomTrailing`:
///   the padding at (0, 58) and c at (1, 59).
/// - GWI4 inner column `.leading`, `padding(1)`, outer `.trailing`: a at (1, 1).
///
/// Mutation: a later mark overwrites an earlier one (GL16's c at (40, 98)).
@Test func onOneNodeTheInnerAnchorAndColumnAlignmentWin() {
    do { // GL15
        let arm = Arm()
        let a = arm.colAlign(arm.colAlign(arm.fx("a", 10, 10), .leading), .trailing)
        let root = arm.grid([row(a), row(arm.fx("e", 50, 10))])
        #expect(arm.run(root, nil, nil) == size(50, 28), "GL15 size")
        expectRects(arm, "GL15", ["a": r(0, 0, 10, 10), "e": r(0, 18, 50, 10)])
    }
    do { // GL16
        let arm = Arm()
        let c = arm.anchor(arm.anchor(arm.fx("c", 10, 10), .topLeading), .bottomTrailing)
        let root = arm.grid([row(arm.fx("a", 50, 10), arm.fx("b", 20, 50)), row(c, arm.fx("d", 20, 50))])
        #expect(arm.run(root, nil, nil) == size(78, 108), "GL16 size")
        expectRects(arm, "GL16", ["a": r(0, 20, 50, 10), "b": r(58, 0, 20, 50),
                                  "c": r(0, 58, 10, 10), "d": r(58, 58, 20, 50)])
    }
    do { // GWI3
        let arm = Arm()
        let padded = arm.anchor(arm.pad(arm.anchor(arm.fx("c", 10, 10), .topLeading), 1), .bottomTrailing)
        let root = arm.grid([row(arm.fx("a", 50, 10), arm.fx("b", 20, 50)), row(padded, arm.fx("d", 20, 50))])
        #expect(arm.run(root, nil, nil) == size(78, 108), "GWI3 size")
        expectRects(arm, "GWI3", ["a": r(0, 20, 50, 10), "b": r(58, 0, 20, 50),
                                  "c": r(1, 59, 10, 10), "d": r(58, 58, 20, 50)])
    }
    do { // GWI4
        let arm = Arm()
        let padded = arm.colAlign(arm.pad(arm.colAlign(arm.fx("a", 10, 10), .leading), 1), .trailing)
        let root = arm.grid([row(padded), row(arm.fx("e", 50, 10))])
        #expect(arm.run(root, nil, nil) == size(50, 30), "GWI4 size")
        expectRects(arm, "GWI4", ["a": r(1, 1, 10, 10), "e": r(0, 20, 50, 10)])
    }
}

// MARK: 3.5 the column sum

/// GR-F, GR-S: two `gridCellColumns` on one view **add their values above 1**,
/// and a count is honoured up to `Int32.max`.
///
/// - GX15 `c.columns(3).columns(2)` spans 5: 109×38, d in column 5 at x 108.
/// - GX16 `c.columns(2).columns(1)` spans 2: 126×38, a at 10.5.
/// - GWI1 inner span 2, `padding(1)`, outer span 1, and GWI2 the reverse: both
///   115×40 — the sum crosses a wrapper (GR-I).
/// - GX21 `columns(100_000)`: 100_001 columns, 71×38, d at x 66.
/// - GX23 `[a, b] [x 100x10 span 3]`: the third column, which only the span
///   covers, takes the whole shortfall (100×38).
///
/// **W0–W3 are the CHAIN's sum** (`GR-AM`), from the companion probe
/// `docs/probes/swiftui-grid-lane3-discriminators.swift`. GWI1 and GWI2 cross a
/// wrapper but write 2 and 1, and 1 is not above 1, so "sum the marks above 1"
/// and "take the largest mark" both answer 2 — mutating the walk's
/// `columns += …` to a `max` left the whole suite green until these arms
/// existed. `c` is a fixed 100×10 leaf inside a `padding(1)`:
///
/// - W0 `.columns(2).padding(1)` and W1 `.padding(1).columns(2)`: one mark of 2
///   wherever it is written, 115×40 with a at x 11.
/// - W2 `.columns(2).padding(1).columns(2)`: span 4, a at x **0** — `#require`d
///   to differ from W0.
/// - W3, W2 with a four-cell top row, where the two rules give different COLUMN
///   COUNTS: 115×40 at span 4 against 130×40 at span 2.
///
/// Mutations: take the largest mark instead of the sum (GX15 reads 3 columns for
/// c: its d moves and the answer changes); `columns > 1` relaxed to
/// `columns >= 1` (GX16's c spans 3); and, for the chain, `columns +=` in
/// `LayoutTree.gridChildMarks` replaced by a `max` (W2 and W3 redden, W0 and W1
/// do not).
@Test func gridCellColumnsDeclaredTwiceAddTheirValuesAboveOne() throws {
    do { // GX15
        let arm = Arm()
        let c = arm.span(arm.span(arm.fx("c", 100, 10), 3), 2)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5), arm.fx("f", 5, 5)),
                             row(c, arm.fx("d", 1, 1))])
        #expect(arm.run(root, nil, nil) == size(109, 38), "GX15 size")
        expectRects(arm, "GX15", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "e": r(66, 7.5, 5, 5),
                                  "f": r(79, 7.5, 5, 5), "c": r(0, 28, 100, 10), "d": r(108, 32.5, 1, 1)])
    }
    do { // GX16
        let arm = Arm()
        let c = arm.span(arm.span(arm.fx("c", 100, 10), 2), 1)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5), arm.fx("f", 5, 5)),
                             row(c, arm.fx("d", 1, 1))])
        #expect(arm.run(root, nil, nil) == size(126, 38), "GX16 size")
        expectRects(arm, "GX16", ["a": r(10.5, 5, 30, 10), "b": r(69.5, 0, 20, 20), "e": r(108, 7.5, 5, 5),
                                  "f": r(121, 7.5, 5, 5), "c": r(0, 28, 100, 10), "d": r(110, 32.5, 1, 1)])
    }
    for (label, inner, outer) in [("GWI1", 2, 1), ("GWI2", 1, 2)] {
        let arm = Arm()
        let c = arm.span(arm.pad(arm.span(arm.fx("c", 100, 10), inner), 1), outer)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5)),
                             row(c, arm.fx("d", 5, 5))])
        #expect(arm.run(root, nil, nil) == size(115, 40), "\(label) size")
        expectRects(arm, label, ["a": r(11, 5, 30, 10), "b": r(71, 0, 20, 20), "e": r(110, 7.5, 5, 5),
                                 "c": r(1, 29, 100, 10), "d": r(110, 31.5, 5, 5)])
    }
    do { // GX21
        let arm = Arm()
        let c = arm.span(arm.fx("c", 10, 10), 100_000)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 5, 5))])
        #expect(arm.run(root, nil, nil) == size(71, 38), "GX21 size")
        expectRects(arm, "GX21", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20),
                                  "c": r(24, 28, 10, 10), "d": r(66, 30.5, 5, 5)])
    }
    do { // GX23
        let arm = Arm()
        let x = arm.span(arm.fx("x", 100, 10), 3)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(x)])
        #expect(arm.run(root, nil, nil) == size(100, 38), "GX23 size")
        expectRects(arm, "GX23", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "x": r(0, 28, 100, 10)])
    }
    // W0, W1, W2: one mark on either side of a padding, then both.
    func wArm(inner: Int?, outer: Int?) -> Arm {
        let arm = Arm()
        var c = arm.fx("c", 100, 10)
        if let inner { c = arm.span(c, inner) }
        c = arm.pad(c, 1)
        if let outer { c = arm.span(c, outer) }
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 5, 5))])
        #expect(arm.run(root, nil, nil) == size(115, 40), "W size")
        return arm
    }
    let w0 = wArm(inner: 2, outer: nil), w1 = wArm(inner: nil, outer: 2), w2 = wArm(inner: 2, outer: 2)
    try #require(w0["a"] != w2["a"], "W0 and W2 must differ, or the second mark reads nothing")
    expectRects(w0, "W0", ["a": r(11, 5, 30, 10), "b": r(71, 0, 20, 20),
                           "c": r(1, 29, 100, 10), "d": r(110, 31.5, 5, 5)])
    expectRects(w1, "W1", ["a": r(11, 5, 30, 10), "b": r(71, 0, 20, 20),
                           "c": r(1, 29, 100, 10), "d": r(110, 31.5, 5, 5)])
    expectRects(w2, "W2", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20),
                           "c": r(1, 29, 100, 10), "d": r(110, 31.5, 5, 5)])
    do { // W3: the value arm — a span of 2 would answer 130x40 with four columns
        let arm = Arm()
        let c = arm.span(arm.pad(arm.span(arm.fx("c", 100, 10), 2), 1), 2)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20), arm.fx("e", 5, 5), arm.fx("f", 7, 7)),
                             row(c, arm.fx("d", 5, 5))])
        #expect(arm.run(root, nil, nil) == size(115, 40), "W3 size (a span of 2 answers 130x40)")
        expectRects(arm, "W3", ["a": r(2, 5, 30, 10), "b": r(44, 0, 20, 20), "e": r(76, 7.5, 5, 5),
                                "f": r(93, 6.5, 7, 7), "c": r(1, 29, 100, 10), "d": r(110, 31.5, 5, 5)])
    }
}

// MARK: 3.7 unsized axes

/// GR-H: on an unsized axis a cell is proposed **its current slot on that axis**
/// — its spanned columns' current widths plus inner gaps, or its row's current
/// height — instead of a share, and its answer **still widens** that column or
/// row. Only a non-nil proposal axis has a share, so nil×nil is unaffected
/// (GU4).
///
/// - GU1 `[a 30x10, b] [c flexible unsized h, d 40x10]` at 200×200 is 78×200,
///   against the control GU2 (c not unsized) at 200×200; a `#require` says they
///   differ.
/// - GU3 unsized on both axes and spanning 2: c is proposed 58×0 and answers it.
/// - GU4 at nil and GU5 at 200×200: c's 100 widens column 0 either way (148×58).
/// - GU6 unsized vertically: c is proposed its row's 0 and its 50 sets the row.
/// - GU7, GU8: an unsized cell in a later flexibility group.
/// - GU11: a lone flexible cell unsized on both axes answers 0×0.
///
/// **U0 and U1 read the proposal a SPAN is given** (`GR-AM`), from the
/// companion probe `docs/probes/swiftui-grid-lane3-discriminators.swift`. GU3
/// is the only unsized span above, and its leaf follows its proposal, so the
/// wrong proposal is re-measured away at placement and no rect moves — reading
/// `widths[cell.column]` instead of `spanWidth(cell)` left the whole suite
/// green. `c` here answers **twice** its proposed width, so the proposal
/// survives into the grid's size: unsized, c is offered its two columns' widths
/// plus their gap (30 + 8 + 20 = 58) and the grid answers 116; not unsized, it
/// is offered 200 and the grid answers 400; offered its first column's 30 it
/// would answer 60.
///
/// Mutation: do not absorb an unsized cell's answer on that axis (GU5 reads
/// 78 wide); per axis, the width half alone and the height half alone; and the
/// unsized branch reading `widths[cell.column]` (U1 reads 60 wide).
@Test func anUnsizedAxisIsProposedItsCurrentSlotAndItsAnswerStillCounts() throws {
    let gu1 = Arm()
    gu1.run(gu1.grid([row(gu1.fx("a", 30, 10), gu1.fx("b", 20, 20)),
                      row(gu1.unsized(gu1.fl("c"), .horizontal), gu1.fx("d", 40, 10))]), 200, 200)
    let gu2 = Arm()
    gu2.run(gu2.grid([row(gu2.fx("a", 30, 10), gu2.fx("b", 20, 20)),
                      row(gu2.fl("c"), gu2.fx("d", 40, 10))]), 200, 200)
    try #require(gu1["c"] != gu2["c"], "GU1 and its control GU2 must differ")
    expectRects(gu1, "GU1", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20),
                             "c": r(0, 28, 30, 172), "d": r(38, 109, 40, 10)])
    expectRects(gu2, "GU2", ["a": r(61, 5, 30, 10), "b": r(170, 0, 20, 20),
                             "c": r(0, 28, 152, 172), "d": r(160, 109, 40, 10)])

    do { // GU3
        let arm = Arm()
        let c = arm.span(arm.unsized(arm.fl("c"), [.horizontal, .vertical]), 2)
        #expect(arm.run(arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c)]), 200, 200) == size(58, 28),
                "GU3 size")
        expectRects(arm, "GU3", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "c": r(0, 28, 58, 0)])
    }
    for (label, width, height) in [("GU4", Double?.none, Double?.none), ("GU5", 200, 200)] {
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.unsized(arm.fx("c", 100, 30), .horizontal), arm.fx("d", 40, 10))])
        #expect(arm.run(root, width, height) == size(148, 58), "\(label) size")
        expectRects(arm, label, ["a": r(35, 5, 30, 10), "b": r(118, 0, 20, 20),
                                 "c": r(0, 28, 100, 30), "d": r(108, 38, 40, 10)])
    }
    do { // GU6
        let arm = Arm()
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)),
                             row(arm.unsized(arm.fx("c", 10, 50), .vertical), arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 200) == size(78, 78), "GU6 size")
        expectRects(arm, "GU6", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20),
                                 "c": r(10, 28, 10, 50), "d": r(38, 48, 40, 10)])
    }
    do { // GU7
        let arm = Arm()
        let root = arm.grid([row(arm.unsized(arm.fl("a"), .horizontal), arm.fl("b")),
                             row(arm.fx("c", 30, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 100) == size(134, 100), "GU7 size")
        expectRects(arm, "GU7", ["a": r(0, 0, 30, 62), "b": r(38, 0, 96, 62),
                                 "c": r(0, 70, 30, 30), "d": r(66, 80, 40, 10)])
    }
    do { // GU8
        let arm = Arm()
        let root = arm.grid([row(arm.unsized(arm.cw("a", 0, 50), .horizontal), arm.fl("b")),
                             row(arm.fx("c", 30, 30), arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 100) == size(200, 100), "GU8 size")
        expectRects(arm, "GU8", ["a": r(0, 26, 30, 10), "b": r(38, 0, 162, 62),
                                 "c": r(0, 70, 30, 30), "d": r(99, 80, 40, 10)])
    }
    do { // GU11
        let arm = Arm()
        let root = arm.grid([row(arm.unsized(arm.fl("a"), [.horizontal, .vertical]))])
        #expect(arm.run(root, 200, 100) == size(0, 0), "GU11 size")
        expectRects(arm, "GU11", ["a": r(0, 0, 0, 0)])
    }
    let u0 = Arm()
    u0.run(u0.grid([row(u0.fx("a", 30, 10), u0.fx("b", 20, 20)), row(u0.span(u0.dbl("c"), 2))]), 200, 200)
    let u1 = Arm()
    u1.run(u1.grid([row(u1.fx("a", 30, 10), u1.fx("b", 20, 20)),
                    row(u1.unsized(u1.span(u1.dbl("c"), 2), .horizontal))]), 200, 200)
    try #require(u0["c"] != u1["c"], "U0 and U1 must differ, or the unsized mark reads nothing")
    expectRects(u0, "U0", ["a": r(85.5, 5, 30, 10), "b": r(294.5, 0, 20, 20), "c": r(0, 28, 400, 10)])
    expectRects(u1, "U1", ["a": r(14.5, 5, 30, 10), "b": r(81.5, 0, 20, 20), "c": r(0, 28, 116, 10)])
}

// MARK: 3.8 an unsized non-row child

/// GR-H: a divider-like non-row child unsized horizontally is proposed its
/// spanned columns' widths plus inner gaps, so it **stops widening the grid**
/// (GU9 58×100) where the same child without the mark takes the whole proposal
/// (GU10 200×100). A `#require` says the two differ.
///
/// Mutation: ignore unsized axes on non-row cells (GU9 reads 200).
@Test func anUnsizedNonRowChildStopsWideningTheGrid() throws {
    let gu9 = Arm()
    let x9 = gu9.unsized(gu9.fl("x"), .horizontal)
    let answer9 = gu9.run(gu9.grid([row(gu9.fx("a", 30, 10), gu9.fx("b", 20, 20)), .full(x9)]), 200, 100)
    let gu10 = Arm()
    let answer10 = gu10.run(gu10.grid([row(gu10.fx("a", 30, 10), gu10.fx("b", 20, 20)), .full(gu10.fl("x"))]), 200, 100)
    try #require(answer9 != answer10, "GU9 and its control GU10 must differ")
    #expect(answer9 == size(58, 100), "GU9 size")
    expectRects(gu9, "GU9", ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "x": r(0, 28, 58, 72)])
    #expect(answer10 == size(200, 100), "GU10 size")
    expectRects(gu10, "GU10", ["a": r(35.5, 5, 30, 10), "b": r(144.5, 0, 20, 20), "x": r(0, 28, 200, 72)])
}

// MARK: 3.9 unsized axes declared twice

/// GR-H: declarations on one view form a **union**.
///
/// - GU12 `.unsized(.vertical).unsized(.horizontal)`: 78×38, c 30×10.
/// - GU13 `.unsized(.horizontal).unsized([])`: 78×200, as GU1.
/// - GWI5 unsized vertically, `padding(1)`, unsized horizontally: the union
///   crosses a wrapper (GR-I), 78×38 with c at (1, 29) 28×8.
///
/// Mutation: a later mark replaces the axes (GU12 reads 78×200, horizontal only).
@Test func unsizedAxesDeclaredTwiceFormAUnion() {
    do { // GU12
        let arm = Arm()
        let c = arm.unsized(arm.unsized(arm.fl("c"), .vertical), .horizontal)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 200) == size(78, 38), "GU12 size")
        expectRects(arm, "GU12", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20),
                                  "c": r(0, 28, 30, 10), "d": r(38, 28, 40, 10)])
    }
    do { // GU13
        let arm = Arm()
        let c = arm.unsized(arm.unsized(arm.fl("c"), .horizontal), [])
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 200) == size(78, 200), "GU13 size")
        expectRects(arm, "GU13", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20),
                                  "c": r(0, 28, 30, 172), "d": r(38, 109, 40, 10)])
    }
    do { // GWI5
        let arm = Arm()
        let c = arm.unsized(arm.pad(arm.unsized(arm.fl("c"), .vertical), 1), .horizontal)
        let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 40, 10))])
        #expect(arm.run(root, 200, 200) == size(78, 38), "GWI5 size")
        expectRects(arm, "GWI5", ["a": r(0, 5, 30, 10), "b": r(48, 0, 20, 20),
                                  "c": r(1, 29, 28, 8), "d": r(38, 28, 40, 10)])
    }
}

// MARK: 3.10 the modifier-chain walk

/// One wrapper kind, and what the two walks do with it. `carriesAttribute` is
/// `GR-I`'s grid walk (`newNativeGrid`'s `gridAttributes(of:)`);
/// `carriesPriority` is the existing `nativeLayoutPriority` walk (`SA-D`,
/// `CN-C`, `CN-D`), and the two DIFFER: a `padding`, a `frame`, a `fixedSize`
/// and an `aspectRatio` carry a cell attribute and hide a priority, while a
/// one-child `HStack`/`ZStack` does the opposite.
private struct GridWrapperKind {
    let name: String
    let carriesAttribute: Bool
    let carriesPriority: Bool
    let wrap: (LayoutTree, LayoutNodeID) -> LayoutNodeID
}

private func gridWrapperKinds() -> [GridWrapperKind] {
    func filler(_ tree: LayoutTree) -> LayoutNodeID {
        tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }
    }
    return [
        GridWrapperKind(name: "padding(0)", carriesAttribute: true, carriesPriority: false) {
            $0.newNativePadding(child: $1, insets: Edges(all: 0))
        },
        GridWrapperKind(name: "padding(1)", carriesAttribute: true, carriesPriority: false) {
            $0.newNativePadding(child: $1, insets: Edges(all: 1))
        },
        GridWrapperKind(name: "frame(12x12)", carriesAttribute: true, carriesPriority: false) {
            $0.newNativeFrame(child: $1, width: 12, height: 12)
        },
        GridWrapperKind(name: "frame(maxWidth: inf)", carriesAttribute: true, carriesPriority: false) {
            $0.newNativeFrame(child: $1, maxWidth: .infinity)
        },
        GridWrapperKind(name: "fixedSize()", carriesAttribute: true, carriesPriority: false) {
            $0.newNativeFixedSize(child: $1, horizontal: true, vertical: true)
        },
        GridWrapperKind(name: "aspectRatio(1, .fit)", carriesAttribute: true, carriesPriority: false) {
            $0.newNativeAspectRatio(child: $1, ratio: 1, contentMode: .fit)
        },
        GridWrapperKind(name: "layoutPriority(1)", carriesAttribute: true, carriesPriority: true) {
            $0.newNativeLayoutPriority(child: $1, priority: 1)
        },
        GridWrapperKind(name: "overlayAttachment primary", carriesAttribute: true, carriesPriority: true) { tree, node in
            tree.newNativeOverlayAttachment(child: node, overlay: filler(tree))
        },
        GridWrapperKind(name: "overlayAttachment content", carriesAttribute: false, carriesPriority: false) { tree, node in
            tree.newNativeOverlayAttachment(child: filler(tree), overlay: node)
        },
        GridWrapperKind(name: "HStack{one}", carriesAttribute: false, carriesPriority: true) {
            $0.newNativeLinearStack(children: [$1], axis: .horizontal, spacing: nil)
        },
        GridWrapperKind(name: "ZStack{one}", carriesAttribute: false, carriesPriority: true) {
            $0.newNativeOverlay(children: [$1], alignment: .center)
        },
    ]
}

/// GR-I: the plan resolves each grid child's attributes by walking its modifier
/// chain from the child node through `frame`, `padding`, `fixedSize`,
/// `aspectRatio`, `layoutPriority` and an overlay attachment's **primary**, and
/// stops at anything else — a one-child `HStack` or `ZStack`, an overlay
/// attachment's content side, a nested grid, a scroll viewport, a custom layout
/// or a leaf. MetalUI's paint-only proposal modifiers register no node, so they
/// carry attributes by construction and need no arm.
///
/// This is `GW`'s reading (GWS/GWA/GWC/GWU rows 1–4, 6, 11, 12, 15–18, and
/// GWP's priority rows): the plan is asserted directly, one arm per node kind
/// per attribute, because the geometric consequence differs by wrapper. The
/// RECTS that follow from the walk are pinned by 3.4's and 3.5's GWI arms
/// (anchor, column alignment and the span through a padding) and 3.9's GWI5
/// (unsized axes).
///
/// Mutations: stop the chain at `padding` (every `padding` arm here reddens, and
/// so do 3.4's GWI3/GWI4 and 3.5's GWI1/GWI2); for R2, take the **innermost**
/// row token instead of the outermost; and for R4, keep the token from the
/// outermost mark but take the ALIGNMENT from the innermost (`GR-AN`).
@Test func cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers() throws {
    for kind in gridWrapperKinds() {
        // Span.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridCell(inner, columns: 2)
            let child = kind.wrap(tree, inner)
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([child, other])
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.cells[0].span == (kind.carriesAttribute ? 2 : 1), "span through \(kind.name)")
        }
        // Anchor.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridCell(inner, anchor: .topLeading)
            let child = kind.wrap(tree, inner)
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([child, other])
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.cells[0].anchor == (kind.carriesAttribute ? .topLeading : nil), "anchor through \(kind.name)")
        }
        // Column alignment.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridCell(inner, columnAlignment: .trailing)
            let child = kind.wrap(tree, inner)
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([child, other])
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.columnAlignments[0] == (kind.carriesAttribute ? .trailing : nil),
                    "column alignment through \(kind.name)")
        }
        // Unsized axes.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridCell(inner, unsizedAxes: .horizontal)
            let child = kind.wrap(tree, inner)
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([child, other])
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.cells[0].unsizedAxes == (kind.carriesAttribute ? .horizontal : []),
                    "unsized axes through \(kind.name)")
        }
        // A row token: with no other row mark, a carried token makes the wrapped
        // child a row cell and leaves the sibling a non-row child.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([inner])
            let child = kind.wrap(tree, inner)
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.cells[0].isRowCell == kind.carriesAttribute, "row token through \(kind.name)")
        }
        // GWP: the priority walk, which the kernel already had.
        do {
            let tree = LayoutTree(generation: 0)
            let inner = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            let child = kind.wrap(tree, tree.newNativeLayoutPriority(child: inner, priority: 1))
            let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            tree.markNativeGridRow([child, other])
            let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: [child, other])))
            #expect(plan.cells[0].priority == (kind.carriesPriority ? 1 : 0), "priority through \(kind.name)")
        }
    }
    // R2 (`GR-AM`, probe `docs/probes/swiftui-grid-lane3-discriminators.swift`):
    // with a row mark on BOTH ends of one chain the OUTERMOST wins, so the
    // padded cell joins its enclosing row instead of making one of its own.
    // SwiftUI spells it `Grid { GridRow { GridRow { a }.padding(1); b } }` and
    // answers 60×20, one row of two columns; the innermost mark winning would
    // put a and b in rows of their own and answer 32×40. Every row arm above
    // writes ONE token per chain, so the clause was unpinned until this one.
    do {
        let tree = LayoutTree(generation: 0)
        let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
        tree.markNativeGridRow([a])
        let padded = tree.newNativePadding(child: a, insets: Edges(all: 1))
        let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        tree.markNativeGridRow([padded, b])
        let grid = tree.newNativeGrid(children: [padded, b])
        let plan = try #require(tree.nativeGridPlan(grid))
        try #require(plan.rowCount == 1, "R2: the outermost row mark makes ONE row, not \(plan.rowCount)")
        let answer = tree.measureNativeLayout(root: grid, proposal: none).size
        #expect(answer == size(60, 20), "R2 answer (the innermost mark winning reads 32x40)")
        tree.computeNativeLayout(root: grid, proposal: none, in: LayoutRect(x: 0, y: 0, width: 60, height: 20))
        #expect(tree.layout(a) == r(1, 5, 30, 10), "R2 a: \(tree.layout(a))")
        #expect(tree.layout(b) == r(40, 0, 20, 20), "R2 b: \(tree.layout(b))")
    }
    // R4 (`GR-AN`, probe `docs/probes/swiftui-grid-row-alignment-inheritance.swift`):
    // the outermost row mark brings its ALIGNMENT with it, not only its token.
    // R2 above writes a nil alignment at both ends of the chain, so it reads the
    // membership only; splitting the two — the token from the outermost mark and
    // the alignment from the innermost — left the whole suite green. SwiftUI
    // spells it `Grid { GridRow(.top) { GridRow(.bottom) { a }.padding(1); b } }`
    // and puts a at (1, 1) (probe arm A3), and the reverse nesting at (1, 29)
    // (A4); the innermost mark winning would swap the two.
    for (label, outer, inner, y) in [("R4a", ProposalAlignment.top, ProposalAlignment.bottom, 1.0),
                                     ("R4b", ProposalAlignment.bottom, ProposalAlignment.top, 29.0)] {
        let tree = LayoutTree(generation: 0)
        let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 30, height: 10)) }
        tree.markNativeGridRow([a], alignment: inner)
        let padded = tree.newNativePadding(child: a, insets: Edges(all: 1))
        let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 40)) }
        tree.markNativeGridRow([padded, b], alignment: outer)
        let grid = tree.newNativeGrid(children: [padded, b])
        let plan = try #require(tree.nativeGridPlan(grid))
        #expect(plan.rowAlignments[0] == outer, "\(label) row alignment: \(String(describing: plan.rowAlignments[0]))")
        let answer = tree.measureNativeLayout(root: grid, proposal: none).size
        #expect(answer == size(60, 40), "\(label) answer")
        tree.computeNativeLayout(root: grid, proposal: none, in: LayoutRect(x: 0, y: 0, width: 60, height: 40))
        #expect(tree.layout(a) == r(1, y, 30, 10), "\(label) a: \(tree.layout(a))")
        #expect(tree.layout(b) == r(40, 0, 20, 40), "\(label) b: \(tree.layout(b))")
    }
}

// MARK: 3.11 gridCellColumns(0)

/// Divergence pin (`GR-O` item 3), **green on arrival**: `gridCellColumns(0)`
/// lays out as 1 in the kernel. SwiftUI puts such a cell in column 0 **without
/// consuming it**, so GX14 `[a 30x10, b 20x20] [c 10x10 columns(0), d 5x5]`
/// reads c (0, 28 10×10) and d (12.5, 30.5 5×5) — d shares column 0 — where the
/// kernel reads c (10, 28) and d (45.5, 30.5), d in column 1. Both answer 58×38.
/// Accepted rather than reproduced (`SA-J`: SwiftUI does not reject it).
///
/// Mutation: treat 0 as 2 (c spans two columns and d moves to column 2).
@Test func gridCellColumnsZeroLaysOutAsOne() {
    let arm = Arm()
    let c = arm.span(arm.fx("c", 10, 10), 0)
    let root = arm.grid([row(arm.fx("a", 30, 10), arm.fx("b", 20, 20)), row(c, arm.fx("d", 5, 5))])
    #expect(arm.run(root, nil, nil) == size(58, 38), "GX14 size")
    expectRects(arm, "GX14 (pinned wrong on purpose, GR-O 3)",
                ["a": r(0, 5, 30, 10), "b": r(38, 0, 20, 20), "c": r(10, 28, 10, 10), "d": r(45.5, 30.5, 5, 5)])
}

// MARK: 3.12 the divergence corpus

/// Divergence pin (`GR-O` item 2, `GR-AA`), **wrong on purpose**: five of the
/// 65 cases the replay corpus throws away
/// (`docs/probes/swiftui-grid-divergences.txt`, same generator, seed and budget
/// as `GridCorpus.swift`), at the **model's** figures, which the kernel ports
/// (`GR-B`). SwiftUI's are in the table below. One per symptom of `GR-F`'s
/// `classify-spans` table, plus two with no span:
///
/// | id | symptom | SwiftUI | the model (asserted) |
/// |---|---|---|---|
/// | 11 | SwiftUI wider | 64×80, c1 (0,0 64×42) | 52×80, c1 (0,0 52×42) |
/// | 22 | the model wider | 114.8×100, c2 (38,0 76.8×100) | 200×100, c2 (38,0 162×100) |
/// | 33 | equal sizes, different rects | 100×80, c2 (0,10 66.67×70) | 100×80, c2 (0,10 100×70) |
/// | 36 | no span, the model wider | 114×45, c4 (76,35 19×10) | 132×45, c4 (76,35 28×10) |
/// | 54 | no span, equal sizes, different rects | 38×80, c3 (0,48 20×20), c4 (0,76 20×4) | 38×80, c3 (0,48 20×24), c4 (0,80 20×0) |
///
/// The corpus itself is by construction the grids on which model and SwiftUI
/// AGREE, so no test in this stage can see agreement getting worse; this handful
/// is the committed shape of the disagreement. Owner: plan task 15's closeout,
/// which re-runs the GZ table and decides whether to close the gap.
///
/// Mutations: GZ0's control (every group offered W′/ncols, commits ignored), and
/// the two one-rule model variants `classify-spans` names — variant 4 (a span
/// keeps its columns open while it is unprocessed) and variant 6 (a column
/// holding no single-column cell counts as open for every share and never
/// commits). The lane records which of the five each moves.
@Test func theModelDisagreesWithSwiftUIOnTheDivergenceCorpus() throws {
    let cases: [GridCorpusCase] = [
        GridCorpusCase(id: 11, proposal: (nil, 80.0), alignment: .topTrailing, horizontalSpacing: 12.0, verticalSpacing: nil,
            children: [.row(.bottom, [.init(.flex, span: 3)]),
                       .row(nil, [.init(.clampW(0.0, 150.0, 10.0), columnAlignment: .trailing),
                                  .init(.fixed(30.0, 30.0), unsizedVertical: true)])],
            size: (52.0, 80.0), rects: [(0.0, 0.0, 52.0, 42.0), (0.0, 50.0, 10.0, 10.0), (22.0, 50.0, 30.0, 30.0)]),
        GridCorpusCase(id: 22, proposal: (200.0, 100.0), alignment: .center, horizontalSpacing: nil, verticalSpacing: nil,
            children: [.row(.bottom, [.init(.flexH(30.0), span: 3), .init(.flex, span: 2, anchor: .center)])],
            size: (200.0, 100.0), rects: [(0.0, 0.0, 30.0, 100.0), (38.0, 0.0, 162.0, 100.0)]),
        GridCorpusCase(id: 33, proposal: (nil, 80.0), alignment: .bottomTrailing, horizontalSpacing: nil, verticalSpacing: 0.0,
            children: [.spanning(.init(.fixed(100.0, 10.0), span: 3)),
                       .row(.bottom, [.init(.spacer, span: 2, columnAlignment: .trailing)])],
            size: (100.0, 80.0), rects: [(0.0, 0.0, 100.0, 10.0), (0.0, 10.0, 100.0, 70.0)]),
        GridCorpusCase(id: 36, proposal: (150.0, nil), alignment: .bottomLeading, horizontalSpacing: 3.0, verticalSpacing: 5.0,
            children: [.spanning(.init(.clampW(30.0, 50.0, 10.0))),
                       .row(.bottom, [.init(.clampW(0.0, 20.0, 30.0)),
                                      .init(.clampW(30.0, 50.0, 20.0), priority: -1.0, unsizedVertical: true),
                                      .init(.half)])],
            size: (132.0, 45.0), rects: [(0.0, 0.0, 50.0, 10.0), (0.0, 15.0, 20.0, 30.0), (23.0, 25.0, 50.0, 20.0), (76.0, 35.0, 28.0, 10.0)]),
        GridCorpusCase(id: 54, proposal: (nil, 80.0), alignment: .bottomLeading, horizontalSpacing: nil, verticalSpacing: nil,
            children: [.row(nil, [.init(.half, columnAlignment: .trailing), .init(.fixed(10.0, 40.0), priority: 1.0)]),
                       .row(nil, [.init(.clampBoth(20.0, 50.0))]),
                       .row(nil, [.init(.flexH(20.0), priority: -1.0)])],
            size: (38.0, 80.0), rects: [(10.0, 30.0, 10.0, 10.0), (28.0, 0.0, 10.0, 40.0), (0.0, 48.0, 20.0, 24.0), (0.0, 80.0, 20.0, 0.0)]),
    ]
    try #require(cases.count == 5, "one per classify-spans symptom, and two with no span")
    for divergent in cases {
        let built = buildGridCase(divergent)
        let tree = built.tree
        let at = ProposedSize(width: divergent.proposal.0, height: divergent.proposal.1)
        let answer = tree.measureNativeLayout(root: built.grid, proposal: at).size
        let expected = SizeD(width: divergent.size.0, height: divergent.size.1)
        #expect(close(answer, expected), "divergence \(divergent.id) answer \(answer), the model's \(expected)")
        tree.computeNativeLayout(root: built.grid, proposal: at,
                                 in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
        try #require(built.leaves.count == divergent.rects.count, "divergence \(divergent.id) leaf count")
        for (index, leaf) in built.leaves.enumerated() {
            let recorded = divergent.rects[index]
            let rect = r(recorded.0, recorded.1, recorded.2, recorded.3)
            #expect(tree.layout(leaf) == rect,
                    "divergence \(divergent.id) leaf c\(index + 1): \(tree.layout(leaf)), the model's \(rect)")
        }
    }
}
