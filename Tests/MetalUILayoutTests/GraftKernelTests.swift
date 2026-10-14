import Testing
import MetalUICore
@testable import MetalUILayout

// C14b-2 lane 2 (`RK-B`, `RK-F`): the graft at the kernel. `LayoutTree.captureSegment` takes the rows of the nodes a
// build window registered, `graft` appends them to a later tree under that tree's generation, and the result is
// the tree a fresh build of the same content would have made: children, kernel cases, leaf keys, spacer axes, parents,
// grid marks (row tokens by their equivalence) and, after a layout over both, the rects. Window-level pins are
// `MetalUITestingTests/RetainedGraftTests.swift`. Counts and values, never time.

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

private struct Shifted: ProposalLayout, Hashable {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 50, height: 20))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x + 3, y: bounds.y), anchor: .topLeading,
                          proposal: ProposedSize(width: 10, height: 10))
    }
}

/// The content under test: a grid of two rows (a spanning cell, an anchored cell), a vertical stack holding a spacer, a
/// padded keyed leaf and a custom layout, and an overlay. Every kernel case a segment must carry but the scroll viewport.
/// Returns the top-level nodes (the grid, the stack, the overlay), the nodes of a fresh build in registration order.
@MainActor private func content(_ tree: LayoutTree) -> [LayoutNodeID] {
    let c1 = keyed(tree, "c1", width: 30, height: 12), c2 = keyed(tree, "c2", width: 10, height: 20)
    let c3 = keyed(tree, "c3", width: 25, height: 8), c4 = keyed(tree, "c4", width: 15, height: 15)
    tree.markNativeGridRow([c1, c2], alignment: .topLeading)
    tree.markNativeGridCell(c1, columns: 1, anchor: .bottomTrailing)
    tree.markNativeGridRow([c3, c4])
    let grid = tree.newNativeGrid(children: [c1, c2, c3, c4], alignment: .center, horizontalSpacing: 2, verticalSpacing: 3)
    let spacer = tree.newNativeSpacer(minLength: 4)
    let leaf = keyed(tree, "padded", width: 40, height: 10)
    let padded = tree.newNativePadding(child: leaf, insets: Edges(top: 2, right: 5, bottom: 4, left: 3))
    let inner = keyed(tree, "inner", width: 12, height: 12)
    let custom = tree.newNativeLayout(Shifted(), children: [inner])
    let stack = tree.newNativeLinearStack(children: [spacer, padded, custom], axis: .vertical, spacing: 1)
    let base = keyed(tree, "base", width: 60, height: 30), badge = keyed(tree, "badge", width: 8, height: 8)
    let overlay = tree.newNativeOverlay(children: [base, badge])
    return [grid, stack, overlay]
}

private let proposal = ProposedSize(width: 300, height: 300)
private let bounds = LayoutRect(x: 0, y: 0, width: 300, height: 300)

/// A root over `prefix` leaves and `tops`, laid out; the digest of everything the tree holds.
@MainActor private func laidOut(_ tree: LayoutTree, prefix: [LayoutNodeID], tops: [LayoutNodeID]) -> [String] {
    let root = tree.newNativeLinearStack(children: prefix + tops, axis: .vertical, spacing: 0, alignment: .leading)
    tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    return tree.structureDigest()
}

/// The tree a fresh build makes, behind `prefixCount` unrelated leaves.
@MainActor private func fresh(prefixCount: Int, generation: UInt64) -> [String] {
    let tree = LayoutTree(generation: generation)
    let prefix = (0..<prefixCount).map { keyed(tree, "p\($0)", width: 5, height: 5) }
    return laidOut(tree, prefix: prefix, tops: content(tree))
}

/// The same tree with the content grafted from a segment captured in a tree of another generation.
@MainActor private func grafted(prefixCount: Int, generation: UInt64, from source: UInt64 = 7) throws -> (digest: [String], count: Int) {
    let origin = LayoutTree(generation: source)
    let tops = content(origin)
    let captured = origin.captureSegment(from: 0, tops: tops)
    let segment = try #require(captured.segment, "no segment: \(captured.refusal ?? "?")")
    let tree = LayoutTree(generation: generation)
    let prefix = (0..<prefixCount).map { keyed(tree, "p\($0)", width: 5, height: 5) }
    let ids = tree.graft(segment)
    #expect(ids.allSatisfy { tree.isCurrent($0) }, "the grafted ids belong to the new tree's generation")
    return (laidOut(tree, prefix: prefix, tops: ids), segment.nodeCount)
}

/// 14 — a grafted subtree is the tree a fresh build makes, node by node and rect by rect, at several offsets (the index
/// shift is the thing that goes wrong at the second prefix and not the first). **Red before:** a `graft` that appends
/// nothing (the compile-red stub) leaves every digest short. **Mutations** (each on the committed `graft`): the
/// shift off by one (`base + relative + 1`) reddens the parents and children lines; one table skipped, one run each
/// (`leafKeys`, `spacerAxes`, `nativeParents`, `gridRowTokens`, `gridCellColumns`, `gridCellAnchors`): the digest line of
/// the node carrying it; the grid plan not shifted: the grid's cell list; the generation not restamped: a trap at
/// the first id use.
@Test(arguments: [0, 1, 4]) @MainActor func aGraftedSubtreeEqualsAFreshBuild(prefixCount: Int) throws {
    let expected = fresh(prefixCount: prefixCount, generation: 3)
    let result = try grafted(prefixCount: prefixCount, generation: 3)
    #expect(result.count == 14, "the content registers 14 nodes: the segment holds \(result.count)")
    #expect(result.digest == expected)
    // The digest is not vacuous: it names the grid, a spacer axis, a leaf key and a row mark.
    #expect(expected.contains { $0.contains("grid(") })
    #expect(expected.contains { $0.contains("spacer:Optional(") })
    #expect(expected.contains { $0.contains("key:Optional(") })
    #expect(expected.contains { $0.contains("|row:") })
}

/// 14b — a graft takes fresh grid row tokens: two grafts of one segment into one tree make two distinct row groups, so a
/// token reused would merge the second graft's rows into the first's (a grid of a grid's rows reads one token). **Red
/// before:** the same stub. **Mutation:** the tokens copied from the segment as stored reddens it (the digests' row
/// ranks collapse).
@Test @MainActor func twoGraftsOfOneSegmentHaveDistinctGridRowTokens() throws {
    let origin = LayoutTree(generation: 1)
    let tops = content(origin)
    let segment = try #require(origin.captureSegment(from: 0, tops: tops).segment)
    let tree = LayoutTree(generation: 2)
    let a = tree.graft(segment), b = tree.graft(segment)
    let digest = laidOut(tree, prefix: [], tops: a + b)
    var rowRanks = Set<String>()
    for line in digest { if let range = line.range(of: "|row:") { rowRanks.insert(String(line[range.upperBound...].prefix(2))) } }
    // Two rows per graft, four row groups in all: four distinct ranks.
    #expect(rowRanks.count == 4)
}

/// 14c — a window that is not a clean subtree is refused by name and grafts nothing: a child outside the range, a stray
/// parentless node, a top that has a parent. **Red before:** the stub answers a segment for any range. **Mutation:** a
/// check removed, one run each, reddens its arm.
@Test @MainActor func aWindowThatIsNotACleanSubtreeIsRefusedByName() throws {
    let tree = LayoutTree(generation: 1)
    let before = keyed(tree, "before")
    let lower = tree.nodeCount
    let a = keyed(tree, "a"), b = keyed(tree, "b")
    let stack = tree.newNativeLinearStack(children: [before, a], axis: .horizontal)
    // `before` is outside the window: the stack's child list reaches out of the range.
    #expect(tree.captureSegment(from: lower, tops: [stack]).refusal == "childOutsideRange")
    // `b` is parentless and not a top.
    let tree2 = LayoutTree(generation: 2)
    let x = keyed(tree2, "x"), y = keyed(tree2, "y")
    _ = tree2.newNativeLinearStack(children: [x], axis: .horizontal)
    #expect(tree2.captureSegment(from: 0, tops: [tree2.nodeID(atIndex: 2)]).refusal == "strayRoots")
    _ = (a, b, y)
}

/// 14d — a graft stands on the tree's own generation and the rects of a grafted node start at zero as a registration's do: a
/// layout over it places it (no stale rect from the recording tree). **Red before:** the stub. **Mutation:** the source
/// tree's rects copied into the segment reddens the digest equality of 14 (the first rows hold the recording's rects).
@Test @MainActor func aGraftedNodeHasNoRectUntilItIsPlaced() throws {
    let origin = LayoutTree(generation: 1)
    let tops = content(origin)
    let segment = try #require(origin.captureSegment(from: 0, tops: tops).segment)
    let root = origin.newNativeLinearStack(children: tops, axis: .vertical, spacing: 0)
    origin.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    #expect(tops.contains { origin.layout($0).width > 0 }, "the recording tree was laid out")
    let tree = LayoutTree(generation: 2)
    let ids = tree.graft(segment)
    #expect(ids.allSatisfy { tree.layout($0) == LayoutRect(x: 0, y: 0, width: 0, height: 0) })
}
