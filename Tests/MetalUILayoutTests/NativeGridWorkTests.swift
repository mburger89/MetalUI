import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 1 of `docs/superpowers/specs/2026-09-17-grids-design.md`: the grid's
// measurement work at a nil proposal (spec §4.5; rulings GR-C and SA-M).
// Counts work, never wall clock (practices).

/// One leaf's closure log.
private final class LeafLog: @unchecked Sendable {
    var calls = 0
}

/// GP3 `Grid{[a fl, b 20x20] [c 10x30, d 40x10]}` laid out at nil by ONE
/// `computeNativeLayout` call on a fresh tree, bounds 58×58.
///
/// **Derived by hand before the run** (spec §4.2, §4.3):
/// - `measureNative(grid, nil)`: 1 miss. Its body measures a, b, c, d at nil:
///   4 misses, 4 leaf calls.
/// - `placeNative(grid)` solves again at nil: a, b, c, d at nil are 4 hits.
///   Then each cell at its placement proposal: a's slot 10×20 is not its 10×10
///   answer (miss, call); b's 40×20 is not 20×20 (miss, call); c's 10×30 equals
///   its answer, so c is measured at the nil it was measured at (hit); d's
///   40×30 is not 40×10 (miss, call).
/// - Leaves' `placeNative` measures nothing.
///
/// Total: **7 leaf calls** (the probe's "measured, in order" list for GP3 has 7
/// entries), **8 misses** (1 + 4 + 3), **5 hits** (4 + 1).
///
/// Mutation: re-measure every cell at its slot even when the slot equals its
/// answer (c at 10×30: 8 calls, 9 misses, 4 hits).
@Test func aGridsWorkAtNilIsOneLeafCallPerDistinctProposal() {
    let tree = LayoutTree(generation: 0)
    let logs = (0..<4).map { _ in LeafLog() }
    func leaf(_ log: LeafLog, _ answer: @escaping @Sendable (ProposedSize) -> SizeD) -> LayoutNodeID {
        tree.newNativeLeaf { proposal in
            log.calls += 1
            return LayoutMeasurement(size: answer(proposal))
        }
    }
    let a = leaf(logs[0]) { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) }
    let b = leaf(logs[1]) { _ in SizeD(width: 20, height: 20) }
    let c = leaf(logs[2]) { _ in SizeD(width: 10, height: 30) }
    let d = leaf(logs[3]) { _ in SizeD(width: 40, height: 10) }
    tree.markNativeGridRow([a, b])
    tree.markNativeGridRow([c, d])
    let grid = tree.newNativeGrid(children: [a, b, c, d])
    let answer = tree.computeNativeLayout(root: grid, proposal: ProposedSize(width: nil, height: nil),
                                          in: LayoutRect(x: 0, y: 0, width: 58, height: 58))
    #expect(answer.size == SizeD(width: 58, height: 58))
    #expect(logs.map(\.calls) == [2, 2, 1, 2], "per-leaf calls")
    #expect(tree.lastNativeLayoutWork == NativeLayoutWork(measureCalls: 7, cacheHits: 5, cacheMisses: 8))
}

// MARK: - Lane 2: work at finite proposals (spec §4.5, §6 tests 2.12 and 2.14)

/// GP1 (GA1 at 200×200, bounds 78×58) and GP2 (`[a flexible, b 20x20] [c 10x30,
/// d 40x10]` at 200×100, bounds 200×100), each laid out by ONE
/// `computeNativeLayout` call on a fresh tree.
///
/// **Derived by hand before the run** (spec §4.2, §4.3):
///
/// GP1. `measureNative(grid)`: 1 miss. Each cell at 0×0 and ∞×∞: 8 misses, 8
/// calls. One group (all fixed): W′ = H′ = 192, two open columns and rows, each
/// cell at 96×96: 4 misses, 4 calls. `placeNative(grid)` solves again: 12 hits.
/// Every slot (30×20, 40×20, 30×30, 40×30) differs from its answer: 4 misses, 4
/// calls. Total **16 calls** (the probe's list has 16), **17 misses**, **12
/// hits**; 4 calls per leaf.
///
/// GP2. `measureNative(grid)`: 1 miss; 8 probes (8 misses, 8 calls); group [b,
/// c, d] at 96×46 (3 misses, 3 calls), then group [a] at 152×62 (1, 1).
/// Placement: 12 hits; a's slot 152×62 equals its answer, so it is placed at
/// the recorded 152×62 (a hit); b at 40×62, c at 152×30, d at 40×30 (3 misses, 3
/// calls). Total **15 calls** (the probe's list has 15), **16 misses**, **13
/// hits**; calls per leaf a 3, b 4, c 4, d 4.
///
/// **The spec's mutation does not discriminate here** (record §20 lane 2):
/// re-measuring every cell at its slot changes nothing on GP1, whose four slots
/// already differ from their answers, or on GP2, whose one equal slot (a's
/// 152×62) is also the proposal it was measured at. It reddens 1.5, 1.12, 2.1,
/// 2.9 and 2.13 instead.
///
/// Mutation (substituted): the finite solve also measures every cell at nil×nil
/// first (GP1 reads 20 calls, 21 misses).
@Test func aGridsWorkAtFiniteProposalsIsOneLeafCallPerDistinctProposal() {
    func arm(flexibleA: Bool, _ width: Double, _ height: Double, bounds: SizeD) -> (LayoutTree, [LeafLog], SizeD) {
        let tree = LayoutTree(generation: 0)
        let logs = (0..<4).map { _ in LeafLog() }
        func leaf(_ log: LeafLog, _ answer: @escaping @Sendable (ProposedSize) -> SizeD) -> LayoutNodeID {
            tree.newNativeLeaf { proposal in
                log.calls += 1
                return LayoutMeasurement(size: answer(proposal))
            }
        }
        let a = flexibleA ? leaf(logs[0]) { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) }
                          : leaf(logs[0]) { _ in SizeD(width: 30, height: 10) }
        let b = leaf(logs[1]) { _ in SizeD(width: 20, height: 20) }
        let c = leaf(logs[2]) { _ in SizeD(width: 10, height: 30) }
        let d = leaf(logs[3]) { _ in SizeD(width: 40, height: 10) }
        tree.markNativeGridRow([a, b])
        tree.markNativeGridRow([c, d])
        let grid = tree.newNativeGrid(children: [a, b, c, d])
        let answer = tree.computeNativeLayout(root: grid, proposal: ProposedSize(width: width, height: height),
                                              in: LayoutRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        return (tree, logs, answer.size)
    }
    do { // GP1
        let (tree, logs, answer) = arm(flexibleA: false, 200, 200, bounds: SizeD(width: 78, height: 58))
        #expect(answer == SizeD(width: 78, height: 58), "GP1 answer")
        #expect(logs.map(\.calls) == [4, 4, 4, 4], "GP1 per-leaf calls")
        #expect(tree.lastNativeLayoutWork == NativeLayoutWork(measureCalls: 16, cacheHits: 12, cacheMisses: 17), "GP1 work")
    }
    do { // GP2
        let (tree, logs, answer) = arm(flexibleA: true, 200, 100, bounds: SizeD(width: 200, height: 100))
        #expect(answer == SizeD(width: 200, height: 100), "GP2 answer")
        #expect(logs.map(\.calls) == [3, 4, 4, 4], "GP2 per-leaf calls")
        #expect(tree.lastNativeLayoutWork == NativeLayoutWork(measureCalls: 15, cacheHits: 13, cacheMisses: 16), "GP2 work")
    }
}

/// GR-U: the finite solve's bookkeeping is indexed, not scanned. `solveNativeGrid`
/// directly on *n* rows of `[fixed 20×10, width 0…50 h10, width-flexible h10]`
/// at 300 × nil: three groups (the fixed cells, then the clamps' finite 50,
/// then the one infinite axis), answer 300 wide (20 + 50 + 214 + 16) and 10n +
/// 8(n − 1) tall.
///
/// **Derived by hand from the indexed solver before the run** (`bookkeepingSteps`
/// counts one per cell, column or row record visited by an open-count update, a
/// commit check or a span sum): one priority level, so the level's counts are
/// filled once, 3n; each group's cells are decremented after it, n + n + n; the
/// first group's commit check visits every column and row, 3 + n; each later
/// group's visits its cells' columns and rows, 2n + 2n; no span. Total **11n +
/// 3**: 2203 at n = 200, 1103 at n = 100, so steps(200) − 2 · steps(100) = −3,
/// at most the constant 3.
///
/// **Red first** against a first finite branch in the model's shape (a scan of
/// every cell per column and row, per group); the lane records that count.
/// Mutation: replace the column index in the commit check with a scan of every
/// cell.
///
/// **This test is the ONLY pin on `finishGroup`'s first-group / later-group
/// split** (`GR-AI`). Second mutation, which nothing else in the suite
/// reddens: delete the `isFirstGroup` branch so every group sweeps every
/// column and row (2 issues here, both literals). It is not equivalent in
/// cost and is indistinguishable in behaviour — 20 000 differential solves
/// byte-identical — so the counter is the only witness the split has.
@Test func theSolversBookkeepingIsLinearInTheCells() throws {
    let two = try solveKindsByColumn(rows: 200, columns: 3, width: 300)
    let one = try solveKindsByColumn(rows: 100, columns: 3, width: 300)
    try #require(two.size == SizeD(width: 300, height: 3592), "three groups at n = 200: \(two.size)")
    #expect(two.bookkeepingSteps == 2203, "steps at n = 200: \(two.bookkeepingSteps)")
    #expect(one.bookkeepingSteps == 1103, "steps at n = 100: \(one.bookkeepingSteps)")
    #expect(two.bookkeepingSteps - 2 * one.bookkeepingSteps <= 3,
            "linear: \(two.bookkeepingSteps) − 2 · \(one.bookkeepingSteps)")

    // Lane 3, arm B: the `ncols` term, at a FIXED row count — the dimension the
    // arms above never vary. Same formula, 10/3 · rows · columns + rows +
    // columns, derived by hand: at 20 rows, 15 columns is 1000 + 35 = 1035 and
    // 30 columns is 2000 + 50 = 2050. The `+ columns` is the first group's full
    // commit sweep; without the `isFirstGroup` split the totals would be
    // 2 · rows · columns + 3(rows + columns) = 705 and 1350, and no rect would
    // move (`GR-AI`).
    let narrow = try solveKindsByColumn(rows: 20, columns: 15, width: 2932)
    let wide = try solveKindsByColumn(rows: 20, columns: 30, width: 2932)
    try #require(narrow.size == SizeD(width: 2932, height: 352), "arm B narrow: \(narrow.size)")
    try #require(wide.size == SizeD(width: 2932, height: 352), "arm B wide: \(wide.size)")
    #expect(narrow.bookkeepingSteps == 1035, "steps at 20 × 15: \(narrow.bookkeepingSteps)")
    #expect(wide.bookkeepingSteps == 2050, "steps at 20 × 30: \(wide.bookkeepingSteps)")

    // Lane 3, arm C: SPANNING cells, which the arms above have none of, so
    // `serve`'s `steps += columnCount` and `spanWidth`'s `steps += cell.span`
    // were never exercised. Two rows of six columns — row 0
    // `[s span 3 (fixed 100×10), a, b, c]`, row 1 six 20×10 cells — at 300 × nil.
    // Derived by hand: 10 (the level fill) + 6 (`serve`'s span sum over every
    // column) + 3 (`spanWidth` inside `serve`) + 10 (the decrements) + 3 + 3
    // (`spanWidth` and the shortfall spread in `finishGroup`) + 6 + 2 (the first
    // group's commit sweep) = **43**.
    let spanning = try solveSpanningRow()
    try #require(spanning.size == SizeD(width: 184, height: 28), "arm C size: \(spanning.size)")
    #expect(spanning.bookkeepingSteps == 43, "arm C steps: \(spanning.bookkeepingSteps)")
}

/// `rows` × `columns` of `[fixed 20×10, width 0…50 h10, width-flexible h10]`
/// repeating by column (so `columns` must be a multiple of 3), solved at
/// `width` × nil: three groups of `rows · columns / 3` single-column cells.
private func solveKindsByColumn(rows: Int, columns: Int, width: Double) throws -> NativeGridSolution {
    let tree = LayoutTree(generation: 0)
    var children: [LayoutNodeID] = []
    for _ in 0..<rows {
        let cells = (0..<columns).map { _ in tree.newNativeLeaf { _ in LayoutMeasurement(size: .zero) } }
        tree.markNativeGridRow(cells)
        children += cells
    }
    let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: children)))
    return solveNativeGrid(plan, proposal: ProposedSize(width: width, height: nil)) { index, proposal in
        switch index % 3 {
        case 0: SizeD(width: 20, height: 10)
        case 1: SizeD(width: Swift.min(Swift.max(proposal.width ?? 10, 0), 50), height: 10)
        default: SizeD(width: proposal.width ?? 10, height: 10)
        }
    }
}

/// Arm C's grid: row 0 `[s span 3 (100×10), a, b, c]` over row 1's six 20×10
/// cells, six columns, at 300 × nil.
private func solveSpanningRow() throws -> NativeGridSolution {
    let tree = LayoutTree(generation: 0)
    func cell(_ width: Double) -> LayoutNodeID {
        tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: 10)) }
    }
    let s = cell(100)
    tree.markNativeGridCell(s, columns: 3)
    let top = [s, cell(20), cell(20), cell(20)]
    let bottom = (0..<6).map { _ in cell(20) }
    tree.markNativeGridRow(top)
    tree.markNativeGridRow(bottom)
    let plan = try #require(tree.nativeGridPlan(tree.newNativeGrid(children: top + bottom)))
    return solveNativeGrid(plan, proposal: ProposedSize(width: 300, height: nil)) { index, _ in
        SizeD(width: index == 0 ? 100 : 20, height: 10)
    }
}

// MARK: - 3.13 the kernel's per-column cost (GR-AB, GR-O item 10)

/// `GR-AB`: SwiftUI honours a column count up to `Int32.max` at about **300
/// bytes and 1.5 µs per column** (GX24: a two-cell row summing to 2 × 10⁷
/// columns took 31.5 s and 5.95 GB), so both engines die by allocation
/// somewhere between 10⁷ and 2³¹ with no message. The kernel keeps `GR-S`'s
/// `Int32.max` traps (test 3.6) and adds no cap below them; this arm states its
/// own shape, in **work, never wall clock**.
///
/// The grid is one row `[s span n (fixed 100×10), a (20×10)]` at 300 × nil, so
/// `n + 1` columns hold two cells. **Derived by hand before the run**
/// (`bookkeepingSteps`): 2 (the level fill) + (n + 1) (`serve`'s span sum over
/// every column) + n (`spanWidth` inside `serve`) + 2 (the decrements) + n + n
/// (`spanWidth` and the shortfall spread) + (n + 1) + 1 (the first group's
/// commit sweep over every column and the one row) = **5n + 7**: 163 847 at
/// n = 32 768 and 327 687 at n = 65 536. Per column the kernel keeps `hgap` and
/// `columnSingleCells` in the plan, `widths`, `levelInColumn`,
/// `unprocessedSingles` and `committedColumn` per solve and `columnX` at
/// placement — about 50 bytes — against SwiftUI's ~300.
///
/// **Measurement work does not grow with the column count**: the same grid laid
/// out through the tree is 6 leaf calls, 7 misses and 8 hits whatever n is (one
/// grid miss; each cell at 0×0 and ∞×∞ and then at its served proposal, 6 misses
/// and 6 calls; placement re-solves into 6 hits and places both cells at slots
/// equal to their answers, 2 more hits).
///
/// Mutation: make the first group's commit sweep visit only its own cells'
/// columns (the counter loses its `ncols` term; the lane records the figure).
@Test func aLargeColumnCountCostsTheKernelOnePassPerColumn() throws {
    func grid(_ n: Int) throws -> (tree: LayoutTree, plan: NativeGridPlan, root: LayoutNodeID) {
        let tree = LayoutTree(generation: 0)
        let s = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 10)) }
        let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 10)) }
        tree.markNativeGridCell(s, columns: n)
        tree.markNativeGridRow([s, a])
        let node = tree.newNativeGrid(children: [s, a])
        return (tree, try #require(tree.nativeGridPlan(node)), node)
    }
    func solved(_ n: Int) throws -> NativeGridSolution {
        let built = try grid(n)
        try #require(built.plan.columnCount == n + 1, "n = \(n): \(built.plan.columnCount) columns")
        return solveNativeGrid(built.plan, proposal: ProposedSize(width: 300, height: nil)) { index, _ in
            SizeD(width: index == 0 ? 100 : 20, height: 10)
        }
    }
    let small = try solved(32_768), large = try solved(65_536)
    try #require(small.size == SizeD(width: 128, height: 10), "n = 32 768 answer \(small.size)")
    try #require(large.size == SizeD(width: 128, height: 10), "n = 65 536 answer \(large.size)")
    #expect(small.bookkeepingSteps == 163_847, "5n + 7 at n = 32 768: \(small.bookkeepingSteps)")
    #expect(large.bookkeepingSteps == 327_687, "5n + 7 at n = 65 536: \(large.bookkeepingSteps)")

    let built = try grid(65_536)
    let answer = built.tree.computeNativeLayout(root: built.root, proposal: ProposedSize(width: 300, height: nil),
                                                in: LayoutRect(x: 0, y: 0, width: 128, height: 10))
    #expect(answer.size == SizeD(width: 128, height: 10), "the tree answer: \(answer.size)")
    #expect(built.tree.lastNativeLayoutWork == NativeLayoutWork(measureCalls: 6, cacheHits: 8, cacheMisses: 7),
            "measurement work is O(cells), not O(columns): \(built.tree.lastNativeLayoutWork)")
}
