import MetalUICore

// The grid kernel (plan task 7, stage G): SwiftUI's `Grid`, ported from the
// reference model in `docs/probes/swiftui-grid.swift` (revision 5). Spec
// `docs/superpowers/specs/2026-09-17-grids-design.md` §4; rulings `GR-A`…
// in `docs/superpowers/2026-09-17-grids-decisions.md`.
//
// **A kernel case, not a `ProposalLayout`** (ruling GR-A): the plan reads row
// membership, cell marks and zero-spacing edges that the public proxy cannot
// reach. Everything here is pure over a `NativeGridPlan` and a measure closure;
// `LayoutTree.swift`'s `.grid` arms and its last extension are the only
// callers.
//
// **Lane 1 of four**: the plan, its indexes and gaps, the nil×nil solve,
// placement and the grid's edges. A proposal with any non-nil axis is lane 2's
// and traps here. Cell anchors, column alignment, unsized axes, the column-sum
// rule and the modifier-chain walk are lane 3's.

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

/// What the plan reads about one grid child, gathered by `LayoutTree` at the
/// grid's registration (ruling GR-A). In lane 1 the marks are read on the child
/// node alone.
struct NativeGridChild {
    let node: LayoutNodeID
    /// The row token of the last `markNativeGridRow` over this node; nil for a
    /// non-row child.
    let rowToken: Int?
    /// The alignment written with that token (its vertical factor is read).
    let rowAlignment: ProposalAlignment?
    /// `markNativeGridCell(_:columns:)`'s count, nil if unmarked.
    let columns: Int?
    let priority: Double
    let horizontalEdges: NativeGridEdges
    let verticalEdges: NativeGridEdges
}

/// One cell of a grid's plan.
struct NativeGridCell {
    let node: LayoutNodeID
    let row: Int
    let column: Int
    /// Columns covered, at least 1, clamped to the columns left in the row. A
    /// non-row cell spans every column.
    let span: Int
    let isRowCell: Bool
    /// `nativeLayoutPriority` of the child (read by lane 2's groups).
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
/// fall further (record §20, lane 1).
final class NativeGridPlan {
    init(alignment: ProposalAlignment, cells: [NativeGridCell], columnCount: Int, rowCount: Int,
         rowAlignments: [ProposalAlignment?], rowCells: [[Int]], columnSingleCells: [[Int]],
         hgap: [Double], vgap: [Double]) {
        self.alignment = alignment; self.cells = cells; self.columnCount = columnCount
        self.rowCount = rowCount; self.rowAlignments = rowAlignments; self.rowCells = rowCells
        self.columnSingleCells = columnSingleCells; self.hgap = hgap; self.vgap = vgap
    }
    let alignment: ProposalAlignment
    let cells: [NativeGridCell]
    let columnCount: Int
    let rowCount: Int
    /// Per row: the row mark's alignment; nil for a non-row cell's row or an
    /// unaligned row.
    let rowAlignments: [ProposalAlignment?]
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
///   (GX23); row cells take columns left to right, a span clamped to the
///   columns left (GX6); a non-row cell starts at 0 and spans every column and
///   ignores its column mark (GX3, GX13).
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
        columnCount = Swift.max(columnCount, children[group].reduce(0) { $0 + span($1) })
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
            let cellSpan = isRow ? Swift.max(1, Swift.min(span(child), columnCount - column)) : columnCount
            let cellColumn = isRow ? column : 0
            if cellSpan == 1 { columnSingleCells[cellColumn].append(cells.count) }
            indexes.append(cells.count)
            cells.append(NativeGridCell(node: child.node, row: row, column: cellColumn, span: cellSpan,
                                        isRowCell: isRow, priority: child.priority,
                                        horizontalEdges: child.horizontalEdges,
                                        verticalEdges: child.verticalEdges))
            column += cellSpan
        }
        rowCells.append(indexes)
        rowAlignments.append(isRow ? children[group.lowerBound].rowAlignment : nil)
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
/// **Any other proposal** is lane 2's flexibility-ordered solve.
func solveNativeGrid(_ plan: NativeGridPlan, proposal: ProposedSize,
                     measure: (Int, ProposedSize) -> SizeD) -> NativeGridSolution {
    guard proposal.width == nil, proposal.height == nil else {
        return solveNativeGridAtAProposal(plan, proposal: proposal, measure: measure)
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
        let fx = plan.alignment.horizontalFactor
        let fy = plan.rowAlignments[cell.row]?.verticalFactor ?? plan.alignment.verticalFactor
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

/// SCANNING FIRST BRANCH (red first for GR-U): the model's shape, every open
/// count and commit check a scan of every cell.
private func solveNativeGridAtAProposal(_ plan: NativeGridPlan, proposal: ProposedSize,
                                        measure: (Int, ProposedSize) -> SizeD) -> NativeGridSolution {
    let cells = plan.cells
    var steps = 0
    var widths = Array(repeating: 0.0, count: plan.columnCount)
    var heights = Array(repeating: 0.0, count: plan.rowCount)
    var proposals = Array(repeating: proposal, count: cells.count)
    var answers = Array(repeating: SizeD(width: 0, height: 0), count: cells.count)
    var infinite = Array(repeating: 0, count: cells.count)
    var finite = Array(repeating: 0.0, count: cells.count)
    for index in cells.indices {
        let zero = measure(index, ProposedSize(width: 0, height: 0))
        let inf = measure(index, ProposedSize(width: .infinity, height: .infinity))
        if proposal.width != nil {
            if inf.width.isInfinite { infinite[index] += 1 } else { finite[index] += inf.width - zero.width }
        }
        if proposal.height != nil {
            if inf.height.isInfinite { infinite[index] += 1 } else { finite[index] += inf.height - zero.height }
        }
    }
    func sameKey(_ x: Int, _ y: Int) -> Bool {
        cells[x].priority == cells[y].priority && infinite[x] == infinite[y] && finite[x] == finite[y]
    }
    let order = cells.indices.sorted { x, y in
        if cells[x].priority != cells[y].priority { return cells[x].priority > cells[y].priority }
        if infinite[x] != infinite[y] { return infinite[x] < infinite[y] }
        if finite[x] != finite[y] { return finite[x] < finite[y] }
        return x < y
    }
    let wPrime = proposal.width.map { $0 - plan.hgap.reduce(0, +) }
    let hPrime = proposal.height.map { $0 - plan.vgap.reduce(0, +) }
    var done = Array(repeating: false, count: cells.count)
    var committedColumns = Array(repeating: false, count: plan.columnCount)
    var committedRows = Array(repeating: false, count: plan.rowCount)
    func spanWidth(_ cell: NativeGridCell) -> Double {
        widths[cell.column..<(cell.column + cell.span)].reduce(0, +) + innerGaps(plan, cell)
    }
    var start = 0
    while start < order.count {
        var end = start + 1
        while end < order.count, sameKey(order[end], order[start]) { end += 1 }
        let level = cells[order[start]].priority
        var open = Array(repeating: false, count: plan.columnCount)
        for column in 0..<plan.columnCount {
            for (index, cell) in cells.enumerated() {
                steps += 1
                if cell.span == 1, cell.column == column, cell.priority == level, !done[index] { open[column] = true; break }
            }
        }
        var openRows = 0
        for row in 0..<plan.rowCount {
            for (index, cell) in cells.enumerated() {
                steps += 1
                if cell.row == row, cell.priority == level, !done[index] { openRows += 1; break }
            }
        }
        let openColumns = open.filter { $0 }.count
        let shareW = wPrime.map { w -> Double in
            if w.isInfinite { return w }
            steps += plan.columnCount
            let committed = zip(widths, committedColumns).reduce(0.0) { $0 + ($1.1 ? $1.0 : 0) }
            return (w - committed) / Double(Swift.max(openColumns, 1))
        }
        let shareH = hPrime.map { h -> Double in
            if h.isInfinite { return h }
            steps += plan.rowCount
            let committed = zip(heights, committedRows).reduce(0.0) { $0 + ($1.1 ? $1.0 : 0) }
            return (h - committed) / Double(Swift.max(openRows, 1))
        }
        for index in order[start..<end] {
            let cell = cells[index]
            var width: Double?
            if let wPrime, let shareW {
                if cell.span == 1 {
                    width = Swift.max(shareW, widths[cell.column])
                } else if wPrime.isInfinite {
                    width = wPrime
                } else {
                    var outside = 0.0
                    for column in 0..<plan.columnCount where !(cell.column..<(cell.column + cell.span)).contains(column) {
                        steps += 1
                        outside += open[column] ? shareW : widths[column]
                    }
                    steps += cell.span
                    width = Swift.max(wPrime - outside + innerGaps(plan, cell), spanWidth(cell))
                }
            }
            let height = shareH.map { Swift.max($0, heights[cell.row]) }
            let cellProposal = ProposedSize(width: width, height: height)
            let answer = measure(index, cellProposal)
            proposals[index] = cellProposal
            answers[index] = answer
            heights[cell.row] = Swift.max(heights[cell.row], answer.height)
            if cell.span == 1 { widths[cell.column] = Swift.max(widths[cell.column], answer.width) }
            done[index] = true
        }
        for index in order[start..<end] where cells[index].span > 1 {
            let cell = cells[index]
            let columns = cell.column..<(cell.column + cell.span)
            steps += cell.span
            let shortfall = answers[index].width - spanWidth(cell)
            guard shortfall > 0 else { continue }
            var targets: [Int] = []
            for column in columns {
                for (other, candidate) in cells.enumerated() {
                    steps += 1
                    if candidate.span == 1, candidate.column == column, !done[other] { targets.append(column); break }
                }
            }
            if targets.isEmpty { targets = columns.filter { plan.columnSingleCells[$0].isEmpty } }
            if targets.isEmpty { targets = Array(columns) }
            for column in targets { widths[column] += shortfall / Double(targets.count) }
        }
        for column in 0..<plan.columnCount where !committedColumns[column] {
            var blocked = false
            for (index, cell) in cells.enumerated() {
                steps += 1
                if cell.span == 1, cell.column == column, !done[index], cell.priority >= level { blocked = true; break }
            }
            if !blocked { committedColumns[column] = true }
        }
        for row in 0..<plan.rowCount where !committedRows[row] {
            var blocked = false
            for (index, cell) in cells.enumerated() {
                steps += 1
                if cell.row == row, !done[index], cell.priority >= level { blocked = true; break }
            }
            if !blocked { committedRows[row] = true }
        }
        start = end
    }
    let size = SizeD(width: widths.reduce(0, +) + plan.hgap.reduce(0, +),
                     height: heights.reduce(0, +) + plan.vgap.reduce(0, +))
    return NativeGridSolution(columnWidths: widths, rowHeights: heights, proposals: proposals,
                              answers: answers, size: size, bookkeepingSteps: steps)
}
