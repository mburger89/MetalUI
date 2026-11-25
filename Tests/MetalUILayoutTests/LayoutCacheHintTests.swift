import Testing
import MetalUICore
import MetalUITestSupport
@testable import MetalUILayout

// G51 (record 420): a layout call's measurement cache and the memo's three generations are made at the size the last one ended at,
// not grown from empty each frame (a 1000-entry `Dictionary<NativeMeasurementKey, LayoutMeasurement>` is about 70 KiB, rehashed
// through seven doublings). Allocations of a settled frame, differential against the same frame with the hints off by construction.

@MainActor private func hintedFrame(_ generation: UInt64, memo: LayoutMemo) -> (LayoutTree, LayoutNodeID) {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    var rows: [LayoutNodeID] = []
    for r in 0..<20 {
        var cells: [LayoutNodeID] = (0..<19).map { c in
            tree.newNativeLeaf(key: "k\(r)-\(c)") { proposal in
                LayoutMeasurement(size: SizeD(width: Swift.min(20, proposal.width ?? 20), height: 10))
            }
        }
        // One unkeyed leaf taints the row, so the memo answers its 19 keyed leaves one by one every frame.
        cells.append(tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) })
        rows.append(tree.newNativeLinearStack(children: cells, axis: .horizontal))
    }
    return (tree, tree.newNativeLinearStack(children: rows, axis: .vertical))
}

/// **G51-D** A settled frame's layout call and the memo's `endFrame` allocate under a ceiling. Mutations: the run's cache or the memo's
/// generations made empty (`NativeLayoutRun(tree:)` without `cacheHint`, `endFrame` assigning `[:]`) regrow through a run of
/// doublings and go over it.
@Test @MainActor func aSettledLayoutCallDoesNotRegrowItsDictionaries() throws {
    #if canImport(Darwin)
    let memo = LayoutMemo()
    let bounds = LayoutRect(x: 0, y: 0, width: 2000, height: 600)
    let proposal = ProposedSize(width: 2000, height: 600)
    for generation in UInt64(1)...3 {
        let (tree, root) = hintedFrame(generation, memo: memo)
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
        memo.endFrame()
    }
    let (tree, root) = hintedFrame(4, memo: memo)
    let seen = try #require(countAllocatedBytes {
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
        memo.endFrame()
    })
    print("G51 layout frame: allocations \(seen.allocations) bytes \(seen.bytes)")
    // 4000440 bytes here; the memo's generations remade empty read 4788504.
    #expect(seen.bytes <= 4_150_000, "bytes \(seen.bytes)")
    #endif
}
