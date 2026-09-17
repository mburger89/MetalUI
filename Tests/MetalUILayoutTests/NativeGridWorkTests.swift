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
