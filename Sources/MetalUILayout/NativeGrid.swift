import MetalUICore

// The grid kernel (plan task 7, stage G): SwiftUI's `Grid`, ported from the
// reference model in `docs/probes/swiftui-grid.swift` — the model is unchanged
// since revision 5, which `GR-B` names as the reference, and the file is at
// revision 6, whose two added modes are additive (record §22). Spec
// `docs/superpowers/specs/2026-09-17-grids-design.md` §4; rulings `GR-A`…
// in `docs/superpowers/2026-09-17-grids-decisions.md`.
//
// **A kernel case, not a `ProposalLayout`** (ruling GR-A): the plan reads row
// membership, cell marks and zero-spacing edges that the public proxy cannot
// reach. Everything here is pure over a `NativeGridPlan` and a measure closure;
// `LayoutTree.swift`'s `.grid` arms and its last extension are the only
// callers.
//
// **All four lanes**: the plan, its indexes and gaps, the nil×nil solve,
// placement and the grid's edges (lane 1); the solve at any other proposal,
// with indexed bookkeeping (lane 2); cell anchors, column alignment, unsized
// axes and the column-sum rule (lane 3, whose modifier-chain walk lives in
// `LayoutTree.gridChildMarks`). The element API — `Grid`, `GridRow` and the
// four cell modifiers — is lane 4's and lives in `Sources/MetalUI/Grid.swift`.

/// A set of layout axes: SwiftUI's `Axis.Set`, for `gridCellUnsizedAxes` (ruling
/// GR-H). MetalUI has no `Axis.Set`, and `ProposalStackAxis` is a two-case enum
/// that cannot express a set.
public struct ProposalAxes: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let horizontal = ProposalAxes(rawValue: 1 << 0)
    public static let vertical = ProposalAxes(rawValue: 1 << 1)
}

/// Whether a node's two edges along one axis take no default spacing (ruling
/// CN-H's `zeroSpacingEdges`, stored).
struct NativeGridEdges: Equatable {
    var leading: Bool
    var trailing: Bool
}

/// What the plan reads about one grid child, gathered by
/// `LayoutTree.gridChildMarks` at the grid's registration, walking the child's
/// modifier chain (rulings GR-A, GR-I).
struct NativeGridChild {
    let node: LayoutNodeID
    /// The row token of the last `markNativeGridRow` over this node; nil for a
    /// non-row child.
    let rowToken: Int?
    /// The alignment written with that token (its vertical factor is read).
    let rowAlignment: ProposalAlignment?
    /// The sum of this child's chain's `gridCellColumns` marks above 1, nil if
    /// none (ruling GR-F; GX15's 3 and 2 span 5, GX16's 2 and 1 span 2).
    let columns: Int?
    /// The innermost `gridCellAnchor` on the chain (rulings GR-G, GR-I).
    let anchor: ProposalAlignment?
    /// The innermost `gridColumnAlignment` on the chain.
    let columnAlignment: ProposalAlignment?
    /// The union of the chain's `gridCellUnsizedAxes` (ruling GR-H).
    let unsizedAxes: ProposalAxes
    let priority: Double
    let horizontalEdges: NativeGridEdges
    let verticalEdges: NativeGridEdges
}

/// One cell of a grid's plan.
struct NativeGridCell {
    let node: LayoutNodeID
    let row: Int
    let column: Int
    /// Columns covered, at least 1, never clamped (ruling GR-Z: the column
    /// count is the widest row's sum of spans). A non-row cell spans every
    /// column.
    let span: Int
    let isRowCell: Bool
    /// `gridCellAnchor`: overrides the column's and the row's and the grid's
    /// alignment on BOTH axes, a non-row child included (ruling GR-G; GL10,
    /// GL11, GL13).
    let anchor: ProposalAlignment?
    /// `gridColumnAlignment` as this cell declares it. A **non-row** cell
    /// declares none (GX13's column half, the model's `where !c.isFull`), and a
    /// spanning cell declares for its first column without being aligned by it
    /// (GL8).
    let columnAlignment: ProposalAlignment?
    /// `gridCellUnsizedAxes` (ruling GR-H): on such an axis the cell is
    /// proposed its current slot instead of a share.
    let unsizedAxes: ProposalAxes
    /// `nativeLayoutPriority` of the child (the finite solve's groups).
    let priority: Double
    let horizontalEdges: NativeGridEdges
    let verticalEdges: NativeGridEdges
}

/// A grid resolved once, at registration (rulings GR-A, GR-U). Immutable.
///
/// **A class, not a struct**, for the depth guard's sake (ruling SA-L): as a
/// struct its payload widened `NativeNode` and every recursion frame that
/// holds one; measured on a 1 MB debug thread, the one-cell-grid ceiling was
/// 164 as a struct and 170 as a class, and the stack's and padding's did not
/// fall further (record §22, lane 1).
final class NativeGridPlan {
    init(alignment: ProposalAlignment, cells: [NativeGridCell], columnCount: Int, rowCount: Int,
         rowAlignments: [ProposalAlignment?], columnAlignments: [ProposalAlignment?],
         rowCells: [[Int]], columnSingleCells: [[Int]],
         hgap: [Double], vgap: [Double]) {
        self.alignment = alignment; self.cells = cells; self.columnCount = columnCount
        self.rowCount = rowCount; self.rowAlignments = rowAlignments
        self.columnAlignments = columnAlignments; self.rowCells = rowCells
        self.columnSingleCells = columnSingleCells; self.hgap = hgap; self.vgap = vgap
    }
    let alignment: ProposalAlignment
    let cells: [NativeGridCell]
    let columnCount: Int
    let rowCount: Int
    /// Per row: the row mark's alignment; nil for a non-row cell's row or an
    /// unaligned row.
    let rowAlignments: [ProposalAlignment?]
    /// Per column: the **first** `gridColumnAlignment` declared for it in row
    /// order, then cell order, by a ROW cell (ruling GR-G; GL4–GL7, and GX13's
    /// column half, where a non-row child declares none).
    let columnAlignments: [ProposalAlignment?]
    /// Per row: its cells' indexes into `cells`, in order.
    let rowCells: [[Int]]
    /// Per column: the indexes of the single-column cells starting there.
    let columnSingleCells: [[Int]]
    /// The gap before each column; `hgap[0]` is 0 (spec §4.1).
    let hgap: [Double]
    /// The gap before each row; `vgap[0]` is 0 when there is a row.
    let vgap: [Double]
}

/// The solver's state after a solve at one proposal (spec §4.2).
struct NativeGridSolution {
    var columnWidths: [Double]
    var rowHeights: [Double]
    /// Each cell's proposal and its answer to it, as recorded by the solve.
    var proposals: [ProposedSize]
    var answers: [SizeD]
    /// The grid's answer: the sums plus the gaps.
    var size: SizeD
    /// Ruling GR-U's counter: cell, column and row records visited by the
    /// finite solve's open-count updates, commit checks and span sums. 0 at
    /// nil×nil.
    var bookkeepingSteps = 0
}

/// Builds a grid's plan from its children in order (spec §4.1).
///
/// - Consecutive children with the same non-nil row token are one row; a child
///   with no token is a non-row cell, a row of its own (GA8).
/// - A row cell's span is `max(1, columns)` (lane 1 treats 0 as 1, GX14); the
///   column count is the largest sum of spans in a row, 1 if there is no row
///   (GX23); row cells take columns left to right; a non-row cell starts at 0
///   and spans every column and ignores its column mark (GX3, GX13).
/// - **Nothing clamps a span** (second critic round, finding 1; ruling GR-Z).
///   The column count is the largest row sum of spans, so within a row the
///   columns left at a cell, `columnCount − column`, are at least the rest of
///   that row's spans and so at least this cell's: a clamp could never bind.
///   GX6's `[a, b] [x span 5]` answers 58 because columns 2–4 are empty, take
///   no width and meet no pair, not because x was cut to 2 (GX21, GX23).
/// - `hgap[j]` is the largest pair value over adjacent cells of one row meeting
///   at j, 0 where none meets (GS5, GS6); `vgap[r]` the largest over cells of
///   rows r−1 and r covering one column (GS4). A pair's value is the explicit
///   spacing if given, else 0 beside a zero-spacing edge, else
///   `ProposalSpacing.platformDefault` (ruling GR-D).
func makeNativeGridPlan(_ children: [NativeGridChild], alignment: ProposalAlignment,
                        horizontalSpacing: Double?, verticalSpacing: Double?) -> NativeGridPlan {
    // Group children into rows: runs of one non-nil token, or one non-row child.
    var groups: [Range<Int>] = []
    var start = 0
    while start < children.count {
        var end = start + 1
        if let token = children[start].rowToken {
            while end < children.count, children[end].rowToken == token { end += 1 }
        }
        groups.append(start..<end)
        start = end
    }

    func span(_ child: NativeGridChild) -> Int { Swift.max(1, child.columns ?? 1) }
    var columnCount = 0
    for group in groups where children[group.lowerBound].rowToken != nil {
        // The sum is checked as it grows, so a row of several huge spans traps
        // with the parameter named instead of overflowing (ruling GR-S; GX24
        // measures that SwiftUI honours such a sum, so this is a deliberate
        // divergence). Each addend is at most `Int32.max`, so the running sum
        // cannot overflow before the check sees it.
        var sum = 0
        for child in children[group] {
            sum += span(child)
            precondition(sum <= Int(Int32.max),
                         "a grid row's gridCellColumns must not sum above Int32.max (GR-S), got \(sum)")
        }
        columnCount = Swift.max(columnCount, sum)
    }
    if columnCount == 0 { columnCount = 1 }

    var cells: [NativeGridCell] = []
    var rowCells: [[Int]] = []
    var rowAlignments: [ProposalAlignment?] = []
    var columnSingleCells = Array(repeating: [Int](), count: columnCount)
    for (row, group) in groups.enumerated() {
        let isRow = children[group.lowerBound].rowToken != nil
        var indexes: [Int] = []
        var column = 0
        for child in children[group] {
            // No clamp: `columnCount` ≥ this row's sum of spans ≥ `column` +
            // this cell's span (ruling GR-Z).
            let cellSpan = isRow ? span(child) : columnCount
            let cellColumn = isRow ? column : 0
            if cellSpan == 1 { columnSingleCells[cellColumn].append(cells.count) }
            indexes.append(cells.count)
            cells.append(NativeGridCell(node: child.node, row: row, column: cellColumn, span: cellSpan,
                                        isRowCell: isRow, anchor: child.anchor,
                                        columnAlignment: child.columnAlignment,
                                        unsizedAxes: child.unsizedAxes, priority: child.priority,
                                        horizontalEdges: child.horizontalEdges,
                                        verticalEdges: child.verticalEdges))
            column += cellSpan
        }
        rowCells.append(indexes)
        rowAlignments.append(isRow ? children[group.lowerBound].rowAlignment : nil)
    }

    // A column's alignment is the FIRST one a ROW cell declares for it, in row
    // order then cell order (GL6 vs GL7); a non-row child declares none (GX13's
    // column half). Resolved here rather than at placement: it is a function of
    // the plan alone.
    var columnAlignments = Array(repeating: ProposalAlignment?.none, count: columnCount)
    for cell in cells where cell.isRowCell {
        if columnAlignments[cell.column] == nil, let alignment = cell.columnAlignment {
            columnAlignments[cell.column] = alignment
        }
    }

    func pair(_ explicit: Double?, _ trailingZero: Bool, _ leadingZero: Bool) -> Double {
        explicit ?? (trailingZero || leadingZero ? 0 : ProposalSpacing.platformDefault)
    }
    var hgapValues = Array(repeating: Double?.none, count: columnCount)
    for indexes in rowCells {
        for (left, right) in zip(indexes, indexes.dropFirst()) {
            let value = pair(horizontalSpacing, cells[left].horizontalEdges.trailing,
                             cells[right].horizontalEdges.leading)
            let column = cells[right].column
            hgapValues[column] = Swift.max(hgapValues[column] ?? value, value)
        }
    }
    var vgap = Array(repeating: 0.0, count: rowCells.count)
    for row in rowCells.indices.dropFirst() {
        // One merge of the two rows' column intervals, both in column order.
        let above = rowCells[row - 1], below = rowCells[row]
        var i = 0, j = 0
        var best: Double?
        while i < above.count, j < below.count {
            let a = cells[above[i]], b = cells[below[j]]
            if a.column < b.column + b.span, b.column < a.column + a.span {
                let value = pair(verticalSpacing, a.verticalEdges.trailing, b.verticalEdges.leading)
                best = Swift.max(best ?? value, value)
            }
            if a.column + a.span <= b.column + b.span { i += 1 } else { j += 1 }
        }
        vgap[row] = best ?? 0
    }

    return NativeGridPlan(alignment: alignment, cells: cells, columnCount: columnCount,
                          rowCount: rowCells.count, rowAlignments: rowAlignments,
                          columnAlignments: columnAlignments,
                          rowCells: rowCells, columnSingleCells: columnSingleCells,
                          hgap: hgapValues.map { $0 ?? 0 }, vgap: vgap)
}

/// Solves `plan` at `proposal` (spec §4.2). `measure` answers cell `i` at a
/// proposal; the tree passes its cached `measureNative`.
///
/// **Both axes nil** (GR-C, GR-F): every cell is measured once at nil, in
/// source order; every answer widens its row, and a single-column cell its
/// column; then each spanning cell, in source order, spreads its width
/// shortfall equally over its spanned columns that hold no single-column cell
/// anywhere in the grid, or over all of them if each does (GX1, GX7, GX11).
///
/// **Any other proposal** is the flexibility-ordered, priority-grouped solve
/// driven below by `NativeGridSolver` (rulings GR-E, GR-F, GR-U), whose loop
/// lives in `LayoutTree.measureGrid(_:atAProposal:)` so that no measurement
/// runs inside the solver's frame (`GR-X` item 2, the depth guard).
///
/// The two branches each carry their own copy of the span-target rule — the
/// spanned columns still holding an unprocessed single-column cell, else those
/// holding none at all, else all of them — so an edit to one is not covered by
/// the other's tests: this branch's is pinned by GX11, `NativeGridSolver`'s by
/// GX9, GX8 and the S1/S2 arms (`GR-AG`).
func solveNativeGrid(_ plan: NativeGridPlan, proposal: ProposedSize,
                     measure: (Int, ProposedSize) -> SizeD) -> NativeGridSolution {
    guard proposal.width == nil, proposal.height == nil else {
        let solver = NativeGridSolver(plan, proposal: proposal)
        while let request = solver.request { solver.provide(measure(request.index, request.proposal)) }
        return solver.solution
    }
    var widths = Array(repeating: 0.0, count: plan.columnCount)
    var heights = Array(repeating: 0.0, count: plan.rowCount)
    var answers: [SizeD] = []
    answers.reserveCapacity(plan.cells.count)
    for index in plan.cells.indices { answers.append(measure(index, proposal)) }
    for (index, cell) in plan.cells.enumerated() {
        heights[cell.row] = Swift.max(heights[cell.row], answers[index].height)
        if cell.span == 1 { widths[cell.column] = Swift.max(widths[cell.column], answers[index].width) }
    }
    for (index, cell) in plan.cells.enumerated() where cell.span > 1 {
        let columns = cell.column..<(cell.column + cell.span)
        let have = columns.reduce(0) { $0 + widths[$1] } + innerGaps(plan, cell)
        let shortfall = answers[index].width - have
        guard shortfall > 0 else { continue }
        var targets = columns.filter { plan.columnSingleCells[$0].isEmpty }
        if targets.isEmpty { targets = Array(columns) }
        for column in targets { widths[column] += shortfall / Double(targets.count) }
    }
    let size = SizeD(width: widths.reduce(0, +) + plan.hgap.reduce(0, +),
                     height: heights.reduce(0, +) + plan.vgap.reduce(0, +))
    return NativeGridSolution(columnWidths: widths, rowHeights: heights,
                              proposals: Array(repeating: proposal, count: plan.cells.count),
                              answers: answers, size: size)
}

/// The gaps inside a cell's span: before each of its columns but the first.
private func innerGaps(_ plan: NativeGridPlan, _ cell: NativeGridCell) -> Double {
    guard cell.span > 1 else { return 0 }
    return plan.hgap[(cell.column + 1)..<(cell.column + cell.span)].reduce(0, +)
}

/// Each cell's placed rect and placement proposal (spec §4.3), the grid's
/// top-left corner at (`x`, `y`).
///
/// A cell's slot is its columns' widths plus inner gaps by its row's height.
/// It is **placed at the slot, unless the slot equals the answer the solve
/// recorded**, in which case at the proposal that answer was measured at (GR1,
/// GP3's c; ruling GR-C). It is measured there and aligned in its slot by the
/// grid's horizontal factor and its row's vertical factor, else the grid's
/// (GL1–GL3, GL9, GL12; ruling GR-G).
func nativeGridCellRects(_ plan: NativeGridPlan, solution: NativeGridSolution, x: Double, y: Double,
                              measure: (Int, ProposedSize) -> SizeD) -> [(rect: LayoutRect, proposal: ProposedSize)] {
    var columnX = Array(repeating: 0.0, count: plan.columnCount)
    var cursor = x
    for column in 0..<plan.columnCount {
        cursor += plan.hgap[column]
        columnX[column] = cursor
        cursor += solution.columnWidths[column]
    }
    var rowY = Array(repeating: 0.0, count: plan.rowCount)
    cursor = y
    for row in 0..<plan.rowCount {
        cursor += plan.vgap[row]
        rowY[row] = cursor
        cursor += solution.rowHeights[row]
    }
    return plan.cells.enumerated().map { index, cell in
        let slot = SizeD(width: solution.columnWidths[cell.column..<(cell.column + cell.span)].reduce(0, +)
                            + innerGaps(plan, cell),
                         height: solution.rowHeights[cell.row])
        let proposal = slot == solution.answers[index]
            ? solution.proposals[index]
            : ProposedSize(width: slot.width, height: slot.height)
        let answer = measure(index, proposal)
        // The anchor wins on both axes (GL10, GL11, GL13); otherwise the column's
        // alignment horizontally — but only for a SINGLE-column cell, so a span
        // declares an alignment it is not itself subject to (GL8) — and the
        // row's vertically; otherwise the grid's (ruling GR-G).
        let fx = cell.anchor?.horizontalFactor
            ?? (cell.span == 1 ? plan.columnAlignments[cell.column]?.horizontalFactor : nil)
            ?? plan.alignment.horizontalFactor
        let fy = cell.anchor?.verticalFactor
            ?? plan.rowAlignments[cell.row]?.verticalFactor
            ?? plan.alignment.verticalFactor
        return (LayoutRect(x: columnX[cell.column] + (slot.width - answer.width) * fx,
                           y: rowY[cell.row] + (slot.height - answer.height) * fy,
                           width: answer.width, height: answer.height),
                proposal)
    }
}

/// A grid's zero-spacing edges seen from an enclosing stack (spec §4.4, ruling
/// GR-R): positional. Along `.horizontal` the leading edge is zero if a cell
/// starting at column 0 has a zero leading edge, the trailing edge if a cell
/// ending at the last column has a zero trailing edge (GE1, GE3, GE4, GE26);
/// along `.vertical`, over the cells of the first and last rows (GE6, GE23,
/// GE24). A non-row cell starts at 0 and ends at the last column (GE25). A grid
/// with no cells has both (GE16).
func nativeGridZeroSpacingEdges(_ plan: NativeGridPlan, axis: ProposalStackAxis) -> (leading: Bool, trailing: Bool) {
    guard !plan.cells.isEmpty else { return (true, true) }
    switch axis {
    case .horizontal:
        return (plan.cells.contains { $0.column == 0 && $0.horizontalEdges.leading },
                plan.cells.contains { $0.column + $0.span == plan.columnCount && $0.horizontalEdges.trailing })
    case .vertical:
        return (plan.rowCells[0].contains { plan.cells[$0].verticalEdges.leading },
                plan.rowCells[plan.rowCount - 1].contains { plan.cells[$0].verticalEdges.trailing })
    }
}

/// The solve at a proposal with a non-nil axis (spec §4.2; rulings GR-E, GR-F,
/// GR-U): the reference model's `solve`, with its scans replaced by counts.
///
/// 1. Every cell is measured at 0×0 and at ∞×∞. Its key is (priority,
///    descending; the number of non-nil proposal axes on which its ∞ answer is
///    infinite; the sum over the other non-nil axes of ∞ answer − 0×0 answer),
///    ties in source order; maximal runs of equal keys are groups (GF10–GF13).
/// 2. W′ and H′ are the proposal less the plan's gaps. At a group's start the
///    share is (W′ − the committed columns' widths) ÷ the open columns (those
///    holding an unprocessed single-column cell of the group's priority), and
///    ∞ on an infinite axis whatever is committed (GP9–GP11). Each cell is
///    proposed max(share, its column's width) on each non-nil axis; a spanning
///    cell W′ less, per column outside it, the share if open or its width if
///    not, plus its inner gaps (GX8, GX12); a nil axis stays nil (GP5, GP6).
/// 3. After the group, each spanning cell widens its columns by its shortfall:
///    first the spanned columns still holding an unprocessed single-column cell
///    (model step 12, GX9), else those holding none anywhere, else all (GX10).
///    Then every column and row with no unprocessed cell of this priority or
///    higher commits, for good (GP2, GF8). Higher-priority groups reserve
///    nothing for lower ones (GQ1–GQ5).
///
/// **The bookkeeping is indexed** (GR-U). Groups arrive in descending
/// priority, so when a group runs every cell of a higher priority is
/// processed, and "no unprocessed cell of this priority or higher" is "no
/// unprocessed cell of this priority". The solver keeps that level's per-column
/// and per-row counts, filled once when the level starts and decremented after
/// each group (so a group's open columns are those at its start, as the model's
/// snapshot is), the number of open columns and rows, each column's unprocessed
/// single-column cells of any priority (step 12), and the committed widths and
/// heights as running sums. The first group's commit check visits every column
/// and row; a later group's visits only its own cells' rows and single-column
/// cells' columns, because a column left uncommitted holds an unprocessed cell
/// of the running level and can only commit when that cell is processed.
/// `bookkeepingSteps` counts each record those updates, checks and span sums
/// visit (`theSolversBookkeepingIsLinearInTheCells`: 11n + 3 on its grid).
///
/// **Inverted, for the depth guard** (ruling SA-L, record §22 lane 2): the
/// solver never calls a measure function. It exposes the one measurement it
/// needs next (`request`) and resumes when given the answer (`provide`), so
/// `LayoutTree.measureGrid` recurses into a cell from its own small loop and
/// none of this state sits on the recursion path. A solver that called its
/// measure closure from inside the group loop let a chain of one-cell grids at
/// 400×400 complete only 65 levels on a 1 MB debug thread.
final class NativeGridSolver {
    private let plan: NativeGridPlan
    private let proposal: ProposedSize
    private let wPrime: Double?
    private let hPrime: Double?

    private var widths: [Double]
    private var heights: [Double]
    private var proposals: [ProposedSize]
    private var answers: [SizeD]
    private var steps = 0

    private var zeroAnswer = SizeD(width: 0, height: 0)
    private var infiniteAxes: [Int]
    private var flexibility: [Double]
    private var order: [Int] = []

    private var unprocessedSingles: [Int]
    private var levelInColumn: [Int]
    private var levelInRow: [Int]
    private var openColumns = 0
    private var openRows = 0
    private var runningLevel: Double?
    private var committedColumn: [Bool]
    private var committedRow: [Bool]
    private var committedWidth = 0.0
    private var committedHeight = 0.0
    private var shareW: Double?
    private var shareH: Double?

    private enum Phase { case probe(Int, infinite: Bool), serve(Int), finished }
    private var phase: Phase
    private var groupStart = 0
    private var groupEnd = 0
    private var isFirstGroup = true

    /// The measurement the solve needs next, nil once it is solved.
    private(set) var request: (index: Int, proposal: ProposedSize)?

    init(_ plan: NativeGridPlan, proposal: ProposedSize) {
        self.plan = plan
        self.proposal = proposal
        wPrime = proposal.width.map { $0 - plan.hgap.reduce(0, +) }
        hPrime = proposal.height.map { $0 - plan.vgap.reduce(0, +) }
        let count = plan.cells.count
        widths = Array(repeating: 0, count: plan.columnCount)
        heights = Array(repeating: 0, count: plan.rowCount)
        proposals = Array(repeating: proposal, count: count)
        answers = Array(repeating: SizeD(width: 0, height: 0), count: count)
        infiniteAxes = Array(repeating: 0, count: count)
        flexibility = Array(repeating: 0, count: count)
        unprocessedSingles = plan.columnSingleCells.map(\.count)
        levelInColumn = Array(repeating: 0, count: plan.columnCount)
        levelInRow = Array(repeating: 0, count: plan.rowCount)
        committedColumn = Array(repeating: false, count: plan.columnCount)
        committedRow = Array(repeating: false, count: plan.rowCount)
        if count == 0 {
            phase = .finished
        } else {
            phase = .probe(0, infinite: false)
            request = (0, ProposedSize(width: 0, height: 0))
        }
    }

    /// The solve's state; valid once `request` is nil.
    var solution: NativeGridSolution {
        NativeGridSolution(columnWidths: widths, rowHeights: heights, proposals: proposals, answers: answers,
                           size: size, bookkeepingSteps: steps)
    }

    /// The grid's answer: the sums plus the gaps; valid once `request` is nil.
    var size: SizeD {
        SizeD(width: widths.reduce(0, +) + plan.hgap.reduce(0, +),
              height: heights.reduce(0, +) + plan.vgap.reduce(0, +))
    }

    /// The answer to `request`; advances to the next measurement.
    func provide(_ answer: SizeD) {
        guard let (index, cellProposal) = request else { preconditionFailure("a grid solver given an answer it did not ask for") }
        switch phase {
        case let .probe(probed, infinite):
            if !infinite {
                zeroAnswer = answer
                phase = .probe(probed, infinite: true)
                request = (probed, ProposedSize(width: .infinity, height: .infinity))
                return
            }
            if proposal.width != nil {
                if answer.width.isInfinite { infiniteAxes[probed] += 1 } else { flexibility[probed] += answer.width - zeroAnswer.width }
            }
            if proposal.height != nil {
                if answer.height.isInfinite { infiniteAxes[probed] += 1 } else { flexibility[probed] += answer.height - zeroAnswer.height }
            }
            if probed + 1 < plan.cells.count {
                phase = .probe(probed + 1, infinite: false)
                request = (probed + 1, ProposedSize(width: 0, height: 0))
            } else {
                sortByKey()
                startGroup(at: 0)
            }
        case let .serve(position):
            let cell = plan.cells[index]
            proposals[index] = cellProposal
            answers[index] = answer
            heighten(cell.row, to: Swift.max(heights[cell.row], answer.height))
            if cell.span == 1 { widen(cell.column, to: Swift.max(widths[cell.column], answer.width)) }
            if position + 1 < groupEnd {
                serve(position + 1)
            } else {
                finishGroup()
                if groupEnd < order.count { startGroup(at: groupEnd) } else { phase = .finished; request = nil }
            }
        case .finished:
            preconditionFailure("a grid solver given an answer after it finished")
        }
    }

    private func sameKey(_ x: Int, _ y: Int) -> Bool {
        plan.cells[x].priority == plan.cells[y].priority && infiniteAxes[x] == infiniteAxes[y]
            && flexibility[x] == flexibility[y]
    }

    private func sortByKey() {
        let cells = plan.cells
        order = cells.indices.sorted { x, y in
            if cells[x].priority != cells[y].priority { return cells[x].priority > cells[y].priority }
            if infiniteAxes[x] != infiniteAxes[y] { return infiniteAxes[x] < infiniteAxes[y] }
            if flexibility[x] != flexibility[y] { return flexibility[x] < flexibility[y] }
            return x < y
        }
    }

    /// Opens the group starting at `start` and asks for its first member.
    ///
    /// The two `Swift.max(…, 1)` clamps below are **defensive and unreachable**
    /// (`GR-AI`, measured): `openRows` is at least 1 whenever a group exists,
    /// because every cell of the level raises its row's count and a later
    /// group's cells have not been decremented yet; and `openColumns` is 0 only
    /// when the level holds no single-column cell, in which case `shareW` is
    /// never read — a span reads `widths[column]` on every outside column
    /// (`levelInColumn` is 0 everywhere) and takes its own branch. Dividing by
    /// 0 instead leaves 20 000 differential solves byte-identical, so **no test
    /// can cover them**; do not write one.
    private func startGroup(at start: Int) {
        groupStart = start
        groupEnd = start + 1
        while groupEnd < order.count, sameKey(order[groupEnd], order[start]) { groupEnd += 1 }
        let level = plan.cells[order[start]].priority
        if level != runningLevel {
            runningLevel = level
            var next = start
            while next < order.count, plan.cells[order[next]].priority == level {
                steps += 1
                let cell = plan.cells[order[next]]
                if cell.span == 1 {
                    if levelInColumn[cell.column] == 0 { openColumns += 1 }
                    levelInColumn[cell.column] += 1
                }
                if levelInRow[cell.row] == 0 { openRows += 1 }
                levelInRow[cell.row] += 1
                next += 1
            }
        }
        shareW = wPrime.map { $0.isInfinite ? $0 : ($0 - committedWidth) / Double(Swift.max(openColumns, 1)) }
        shareH = hPrime.map { $0.isInfinite ? $0 : ($0 - committedHeight) / Double(Swift.max(openRows, 1)) }
        serve(start)
    }

    /// Asks for the group member at `position` at its proposal.
    private func serve(_ position: Int) {
        let index = order[position]
        let cell = plan.cells[index]
        var width: Double?
        if let wPrime, let shareW {
            if cell.unsizedAxes.contains(.horizontal) {
                // GR-H: an unsized axis is proposed the cell's CURRENT slot on
                // that axis — its spanned columns' widths plus inner gaps, which
                // for a single-column cell is just that column's width — instead
                // of a share. Its answer still widens the column (GU5's 100).
                width = spanWidth(cell)
            } else if cell.span == 1 {
                width = Swift.max(shareW, widths[cell.column])
            } else if wPrime.isInfinite {
                width = wPrime
            } else {
                var outside = 0.0
                for column in 0..<plan.columnCount where column < cell.column || column >= cell.column + cell.span {
                    outside += levelInColumn[column] > 0 ? shareW : widths[column]
                }
                steps += plan.columnCount
                width = Swift.max(wPrime - outside + innerGaps(plan, cell), spanWidth(cell))
            }
        }
        let height = shareH.map {
            cell.unsizedAxes.contains(.vertical) ? heights[cell.row] : Swift.max($0, heights[cell.row])
        }
        phase = .serve(position)
        request = (index, ProposedSize(width: width, height: height))
    }

    private func finishGroup() {
        let group = order[groupStart..<groupEnd]
        for index in group {
            steps += 1
            let cell = plan.cells[index]
            if cell.span == 1 {
                unprocessedSingles[cell.column] -= 1
                levelInColumn[cell.column] -= 1
                if levelInColumn[cell.column] == 0 { openColumns -= 1 }
            }
            levelInRow[cell.row] -= 1
            if levelInRow[cell.row] == 0 { openRows -= 1 }
        }
        for index in group where plan.cells[index].span > 1 {
            let cell = plan.cells[index]
            let shortfall = answers[index].width - spanWidth(cell)
            guard shortfall > 0 else { continue }
            let columns = cell.column..<(cell.column + cell.span)
            steps += cell.span
            // Step 12, then the nil branch's own rule, then every spanned
            // column. Each step has its own arm: GX9, then S1/S2 (`GR-AG`;
            // deleting this line was green until they were written), then GX8.
            var targets = columns.filter { unprocessedSingles[$0] > 0 }
            if targets.isEmpty { targets = columns.filter { plan.columnSingleCells[$0].isEmpty } }
            if targets.isEmpty { targets = Array(columns) }
            for column in targets { widen(column, to: widths[column] + shortfall / Double(targets.count)) }
        }
        // The first group sweeps every column and row; later groups check only
        // their own cells'. **This split is a COST rule, not a behavioural one**
        // (`GR-AI`, measured): sweeping every column after every group gives
        // byte-identical answers over 20 000 differential solves, because a
        // column's level count reaches 0 only in the group that serves its last
        // cell at this level, so the extra visits are no-ops on
        // `commitColumn`'s guards. Its only pin is
        // `theSolversBookkeepingIsLinearInTheCells` (test 2.14) — the counter,
        // not a rect. Keep the split, and keep 2.14 reading `ncols`.
        if isFirstGroup {
            isFirstGroup = false
            for column in 0..<plan.columnCount { commitColumn(column) }
            for row in 0..<plan.rowCount { commitRow(row) }
        } else {
            for index in group {
                if plan.cells[index].span == 1 { commitColumn(plan.cells[index].column) }
                commitRow(plan.cells[index].row)
            }
        }
    }

    private func spanWidth(_ cell: NativeGridCell) -> Double {
        steps += cell.span
        return widths[cell.column..<(cell.column + cell.span)].reduce(0, +) + innerGaps(plan, cell)
    }

    private func widen(_ column: Int, to value: Double) {
        let old = widths[column]
        guard value != old else { return }
        widths[column] = value
        if committedColumn[column] { committedWidth += value - old }
    }

    private func heighten(_ row: Int, to value: Double) {
        let old = heights[row]
        guard value != old else { return }
        heights[row] = value
        if committedRow[row] { committedHeight += value - old }
    }

    private func commitColumn(_ column: Int) {
        steps += 1
        guard !committedColumn[column], levelInColumn[column] == 0 else { return }
        committedColumn[column] = true
        committedWidth += widths[column]
    }

    private func commitRow(_ row: Int) {
        steps += 1
        guard !committedRow[row], levelInRow[row] == 0 else { return }
        committedRow[row] = true
        committedHeight += heights[row]
    }
}
