#if canImport(Darwin)
import Testing
import MetalUICore
import MetalUITestSupport
@testable import MetalUILayout

// P2 lane 1 (`PA-J`): thread-filtered, differential allocation pins. Darwin only.

/// Exactly `count` mallocs: `UnsafeMutablePointer.allocate` is one `malloc`, with no array machinery.
@inline(never) private func allocateBuffers(_ count: Int) -> Int {
    var total = 0
    for i in 0..<count {
        let buffer = UnsafeMutablePointer<Double>.allocate(capacity: 16 + i)
        buffer.initialize(to: Double(i))
        total &+= Int(buffer.pointee)
        buffer.deallocate()
    }
    return total
}

/// The counter's own proof: a known allocation is seen, none reads 0, and another thread's allocations are not counted.
@Test func theCounterSeesAKnownAllocationAndOnlyTheCallersThread() throws {
    let one = try #require(countAllocations { _ = allocateBuffers(1) })
    let sixteen = try #require(countAllocations { _ = allocateBuffers(16) })
    let none = try #require(countAllocations { _ = 5 + 5 })
    #expect(none == 0, "an addition allocates nothing; read \(none)")
    // A debug build logs more than one event per malloc (measured 2 each), so the control is a floor, not an equality.
    #expect(sixteen - one >= 15, "positive control: 16 buffers minus 1 is at least 15 allocations; read \(sixteen) and \(one)")
    // Separating arm: the foreign thread allocates 1000 buffers while the caller allocates none.
    let foreign = try #require(countAllocationsIgnoringAnotherThread { _ = allocateBuffers(1000) })
    #expect(foreign < 100, "a foreign thread's 1000 allocations must not be counted; read \(foreign)")
}

private func stackOfLeaves(_ count: Int) -> (LayoutTree, LayoutNodeID) {
    let tree = LayoutTree(generation: 1)
    var leaves: [LayoutNodeID] = []
    for i in 0..<count {
        leaves.append(tree.newNativeLeaf(key: i) { _ in LayoutMeasurement(size: SizeD(width: 10.3, height: 7.7)) })
    }
    let root = tree.newNativeLinearStack(children: leaves, axis: .vertical)
    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: nil),
                             in: LayoutRect(x: 0.2, y: 0.3, width: 100, height: 100))
    return (tree, root)
}

/// Mutation: restore `roundLayout([layout(node)])[0]` in `roundNativeStoredRects`.
@Test @MainActor func roundingStoredRectsAllocatesNothingPerNode() throws {
    let (small, smallRoot) = stackOfLeaves(50)
    let (large, largeRoot) = stackOfLeaves(500)
    // Warm each once (lazy runtime caches), then count.
    small.roundStoredRectsForTesting(smallRoot); large.roundStoredRectsForTesting(largeRoot)
    let a = try #require(countAllocations { small.roundStoredRectsForTesting(smallRoot) })
    let b = try #require(countAllocations { large.roundStoredRectsForTesting(largeRoot) })
    #expect(b - a == 0, "rounding 450 more nodes must allocate nothing more; 50 nodes: \(a), 500 nodes: \(b)")
}

/// Mutation: restore the exact `reserveCapacity(base + n)` in `graft`.
@Test @MainActor func graftingManySegmentsReallocatesLogarithmically() throws {
    let source = LayoutTree(generation: 1)
    var tops: [LayoutNodeID] = []
    for i in 0..<5 { tops.append(source.newNativeLeaf(key: i) { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }) }
    let captured = source.captureSegment(from: 0, tops: tops)
    let segment = try #require(captured.segment, "capture refused: \(String(describing: captured.refusal))")
    let target = LayoutTree(generation: 2)
    var capacities: Set<Int> = [target.childListsCapacityForTesting]
    for _ in 0..<200 {
        _ = target.graft(segment)
        capacities.insert(target.childListsCapacityForTesting)
    }
    #expect(capacities.count <= 12, "200 grafts of 5 nodes saw \(capacities.count) distinct capacities")
}
#endif
