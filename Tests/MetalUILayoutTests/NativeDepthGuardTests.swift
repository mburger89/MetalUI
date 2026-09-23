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
        waitUntilFinished(t)
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
        waitUntilFinished(t)
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
        waitUntilFinished(t)
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
        waitUntilFinished(t)
    }
}

// MARK: - Grids (lane 1 of `docs/superpowers/specs/2026-09-17-grids-design.md`)
//
// A grid is ONE native level (spec §4.5): its solver runs in functions called
// from `measureNative` and `placeNative`, and each cell is entered once. The
// depth literals are literals on purpose (ruling GR-M, critic finding 2), not
// `NativeLayoutRun.maxDepth` arithmetic: a leaf under 72 nested one-cell grids
// is 73 levels and traps; under 71 it is 72 levels and lays out. Both lay out
// at a nil proposal (lane 1's branch; the finite solve's ceiling is also in the
// table below and clears the same gate), on a 4 MB thread as above. The one-cell-grid debug ceiling is in
// `NativeLayoutRun.maxDepth`'s table.
//
// **88 / 87 until stage 6b's lane 1** (`LR-DK`): `maxDepth` fell to 72 by `SA-L`'s
// own rule on the re-bisected debug ceilings, and these two were re-derived by hand
// (renamed from `aChainOf88GridsTraps` / `aChainOf87GridsDoesNotTrap`).

/// Mutation: `NativeLayoutRun.maxDepth` 73 (the child exits `.success`).
@Test func aChainOf72GridsTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<72 {
                node = tree.newNativeGrid(children: [node])
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: nil, height: nil),
                                     in: LayoutRect(x: 0, y: 0, width: 10, height: 10))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    #expect(stderrText(result).contains("native layout recursion exceeded 72 levels"),
            "aborted, but not at the native depth guard:\n\(stderrText(result))")
}

/// Mutation: `NativeLayoutRun.maxDepth` 71 (the child traps). The child also
/// requires the run's deepest level to be the limit itself
/// (`LayoutTree.lastNativeLayoutDeepestLevel`, `LR-DK`), so a limit raised above 72
/// reddens this arm too.
@Test func aChainOf71GridsDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<71 {
                node = tree.newNativeGrid(children: [node])
            }
            let size = tree.computeNativeLayout(root: node, proposal: ProposedSize(width: nil, height: nil),
                                                in: LayoutRect(x: 0, y: 0, width: 10, height: 10)).size
            precondition(size == SizeD(width: 10, height: 10), "answered \(size)")
            precondition(tree.lastNativeLayoutDeepestLevel == 72,
                         "deepest level \(tree.lastNativeLayoutDeepestLevel), not 72")
            precondition(NativeLayoutRun.maxDepth == 72, "the chain is at the limit only while it is 72")
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
}

// MARK: - Every node kind at `maxDepth − 1` on a 1 MB thread (lane 4, GR-AC item 3)
//
// `SA-L` sets `maxDepth` at 0.60 of the SMALLEST debug ceiling over every native
// node kind, and `GR-AC` recorded that the fraction was already breached at
// `cb2e708` by the one-child vertical stack (128 → 76 < 88), a dated obligation
// owned by `LR-Q`'s stage 6b re-bisection — **discharged by stage 6b's lane 1**
// (`LR-DK`): the re-bisected debug stack ceiling is 127, so `maxDepth` is 72 and the
// fraction holds again (72 / 127 = 0.57). The half that CAN be tested is the
// hard one: that every kind still *completes* a chain the guard admits, on the
// 1 MB stack the fraction is stated about — not the 4 MB thread every other test
// in this file uses, which is chosen to isolate the guard from the stack.
//
// So this test is the only one here that runs on 1 MB, and it fails the day any
// kind's ceiling falls below `maxDepth` itself, which is the condition the 0.60
// margin exists to keep far away. It cannot see the margin.

/// A custom layout that measures its one child and places it: the shape the
/// `maxDepth` table bisected as "custom `ProposalLayout`, measuring and placing
/// through the proxy", so both recursions grow with the chain.
private struct PassesThroughItsChild: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

/// **A chain of `maxDepth − 1` nodes of every kind lays out on a 1 MB thread**
/// (`GR-AC` item 3): padding, a fixed frame, the one-child vertical
/// `linearStack`, a custom `ProposalLayout` and the grid, each over a leaf, each
/// expected to exit `.success`. The control is the same padding chain at
/// `maxDepth + 8`, which must exit `.failure` at the guard — so "it completed"
/// cannot be read off a harness that never runs the body.
///
/// Green on arrival. Mutation: `NativeLayoutRun.maxDepth` raised, so that
/// `maxDepth − 1` exceeds a kind's ceiling; the lane records which arms die at
/// which raise (the ceilings differ by a factor of 1.5, so a single raise does
/// not kill them all).
@Test func aChainOfMaxDepthNodesOfEveryKindSurvivesAOneMegabyteThread() async {
    // Each body below is written out in full: an exit test's body is re-entered
    // in a subprocess and must not capture context, so no shared helper and no
    // captured `chain` constant.
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                node = tree.newNativeFrame(child: node, width: 100, height: 100)
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                node = tree.newNativeLinearStack(children: [node], axis: .vertical, spacing: nil)
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                node = tree.newNativeLayout(PassesThroughItsChild(), children: [node])
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    // The grid, on the PLACEMENT path lane 3 bisected: a two-cell row whose
    // inner cell's slot differs from its answer at every level, so
    // `nativeGridCellRects`' fresh-measurement branch is on the measured stack
    // (`GR-AK`).
    await #expect(processExitsWith: .success) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth - 1) {
                let tall = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 11)) }
                tree.markNativeGridRow([node, tall])
                node = tree.newNativeGrid(children: [node, tall])
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    // The control: eight levels past the guard must abort at the guard.
    let over = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let t = Thread {
            let tree = LayoutTree(generation: 0)
            var node = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            for _ in 0..<(NativeLayoutRun.maxDepth + 8) {
                node = tree.newNativePadding(child: node, insets: Edges(all: 1))
            }
            tree.computeNativeLayout(root: node, proposal: ProposedSize(width: 400, height: 400),
                                     in: LayoutRect(x: 0, y: 0, width: 400, height: 400))
        }
        t.stackSize = 4 * 1024 * 1024
        t.start()
        waitUntilFinished(t)
    }
    #expect(stderrText(over).contains("native layout recursion exceeded"),
            "the control aborted, but not at the native depth guard:\n\(stderrText(over))")
}
