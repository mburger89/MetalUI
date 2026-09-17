import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

// Lane 3 ("robustness") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the native depth guard, ruling SA-L in
// `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
//
// **One counter covers both recursions**: `NativeLayoutRun.depth` is entered at
// the top of `measureNative` and of `placeNative`. A tree deeper than the limit
// traps in measurement first, so a test through `computeNativeLayout` alone
// would stay green with `enter` deleted from `measureNative`. Hence three trap
// tests, each reddened by a different deletion:
// - `layingOutANativeTreeDeeperThanTheLimitTraps`: both deleted;
// - `measuringANativeTreeDeeperThanTheLimitTraps`: `measureNative`'s alone
//   (measurement only, through `measureNativeLayout`);
// - `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps`: `placeNative`'s
//   alone (a chain whose measurement never recurses).
// `LayoutContextTests` records the same shape-4 hazard for legacy `placeNode`.
//
// **Every layout runs on an explicitly-sized 4 MB `Thread`**, for the reason
// `layingOutATreeDeeperThanTheLimitTraps` gives: `maxDepth` is a statement
// about the stacks the framework runs on, and an exit-test task's own stack is
// not one of them. `maxDepth + 1` = 89 levels at ≤ ≈6.8 KB each (debug, the
// bisection table on `NativeLayoutRun.maxDepth`) is ≈0.6 MB, so 4 MB overflows
// at none of these depths.
//
// **The fragment is `"native layout recursion exceeded"`**, because legacy's
// `"layout recursion exceeded"` is a substring of it.

private func stderrText(_ result: ExitTest.Result?) -> String {
    String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
}

/// Answers a constant without measuring and places its one child at a fixed
/// proposal, so a chain of these recurses in placement only.
private struct PlacesWithoutMeasuring: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y),
                          proposal: ProposedSize(width: 10, height: 10))
    }
}

/// A leaf under `maxDepth` padding nodes: `maxDepth + 1` native levels.
@Test func layingOutANativeTreeDeeperThanTheLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<NativeLayoutRun.maxDepth {
                node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        // The guard aborts the process, so on the passing path this spin never
        // completes; it keeps the body from returning and reporting a clean exit.
        while !t.isFinished { usleep(1000) }
    }
    #expect(stderrText(result).contains("native layout recursion exceeded"),
            "aborted, but not at the native depth guard:\n\(stderrText(result))")
}

/// The same chain through the measure-only entry point: only `measureNative`'s
/// `enter` can see it.
@Test func measuringANativeTreeDeeperThanTheLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<NativeLayoutRun.maxDepth {
                node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            }
            _ = tree.measureNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        while !t.isFinished { usleep(1000) }
    }
    #expect(stderrText(result).contains("native layout recursion exceeded"),
            "aborted, but not at the native depth guard:\n\(stderrText(result))")
}

/// A leaf under `maxDepth` custom layouts that each answer a constant and place
/// their child at a fixed proposal. Measurement reaches one level below any
/// node it starts from, so only placement's depth grows with the chain.
@Test func aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<NativeLayoutRun.maxDepth {
                node = tree.newNativeLayout(PlacesWithoutMeasuring(), children: [node])
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 10, height: 10),
                                     in: LayoutRect(x: 0, y: 0, width: 10, height: 10))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        while !t.isFinished { usleep(1000) }
    }
    #expect(stderrText(result).contains("native layout recursion exceeded"),
            "aborted, but not at the native depth guard:\n\(stderrText(result))")
}

/// A leaf under `maxDepth − 1` padding nodes, exactly `maxDepth` levels, lays
/// out without trapping. Green on arrival; red under `depth < maxDepth`.
@Test func aNativeTreeAtTheDepthLimitDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            }
            let size = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                                in: LayoutRect(x: 0, y: 0, width: 400, height: 400)).size
            let expected = 10 + 2 * Double(NativeLayoutRun.maxDepth - 1)
            precondition(size == SizeD(width: expected, height: expected), "answered \(size)")
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        while !t.isFinished { usleep(1000) }
    }
}

// MARK: - Grids (lane 1 of `docs/superpowers/specs/2026-09-17-grids-design.md`)
//
// A grid is ONE native level (spec §4.5): its solver runs in functions called
// from `measureNative` and `placeNative`, and each cell is entered once. The
// depth literals are literals on purpose (ruling GR-M, critic finding 2), not
// `NativeLayoutRun.maxDepth` arithmetic: a leaf under 88 nested one-cell grids
// is 89 levels and traps; under 87 it is 88 levels and lays out. Both lay out
// at a nil proposal (lane 1's branch; the finite solve's ceiling is also in the
// table below and clears the same gate), on a 4 MB thread as above. The one-cell-grid debug ceiling is in
// `NativeLayoutRun.maxDepth`'s table.

/// Mutation: `NativeLayoutRun.maxDepth` 89 (the child exits `.success`).
@Test func aChainOf88GridsTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<88 {
                node = tree.newNativeGrid(children: [node])
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: nil, height: nil),
                                     in: LayoutRect(x: 0, y: 0, width: 10, height: 10))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        while !t.isFinished { usleep(1000) }
    }
    #expect(stderrText(result).contains("native layout recursion exceeded"),
            "aborted, but not at the native depth guard:\n\(stderrText(result))")
}

/// Mutation: `NativeLayoutRun.maxDepth` 87 (the child traps).
@Test func aChainOf87GridsDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<87 {
                node = tree.newNativeGrid(children: [node])
            }
            let size = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: nil, height: nil),
                                                in: LayoutRect(x: 0, y: 0, width: 10, height: 10)).size
            precondition(size == SizeD(width: 10, height: 10), "answered \(size)")
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        while !t.isFinished { usleep(1000) }
    }
}
