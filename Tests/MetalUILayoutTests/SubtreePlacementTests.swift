import Testing
import MetalUICore
@testable import MetalUILayout

// C14b lane 2 (`SB-AD`, `SB-O`): the subtree placement memo at the kernel. A marked node whose
// structural signature, proposal and bounds (bit for bit) equal an earlier placement's gets that
// placement's unrounded rects back and places nothing under it. Window-level pins are
// `MetalUITestingTests/RetainedPlacementTests.swift`. Counts and values, never time.
//
// Each test names its red-before (the stub of the first commit: the counter exists, the kernel never
// consults the marks) and the mutation that must redden it.

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

private let big = ProposedSize(width: 200, height: 200)
private let bounds = LayoutRect(x: 0, y: 0, width: 200, height: 200)

/// A custom layout whose answer is constant and whose child's x depends on the **proposal** it is
/// placed at, so a restore that ignored the proposal would put the child in the wrong place while
/// every bound stayed equal.
private struct ProposalShifted: ProposalLayout, Hashable {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 50, height: 20))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x + (proposal.width ?? 0) / 10, y: bounds.y),
                          anchor: .topLeading, proposal: ProposedSize(width: 10, height: 10))
    }
}

/// `[A, B]` leading-aligned: A (a horizontal stack of two keyed leaves, marked when `mark`) at the
/// origin, B a keyed leaf of `bWidth` under it. Returns every node of A in pre-order.
private struct Tower {
    let tree: LayoutTree
    let root: LayoutNodeID
    let a: LayoutNodeID
    let aNodes: [LayoutNodeID]
}

@MainActor private func tower(generation: UInt64, bWidth: Double, bHeight: Double = 10, mark: Bool = true,
                              bFirst: Bool = false, memo: LayoutMemo?) -> Tower {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    let a1 = keyed(tree, "a1", width: 30, height: 12), a2 = keyed(tree, "a2", width: 40, height: 8)
    let a = tree.newNativeLinearStack(children: [a1, a2], axis: .horizontal)
    if mark { tree.markPlacementRoot(a) }
    let b = keyed(tree, "b\(bWidth)/\(bHeight)", width: bWidth, height: bHeight)
    let root = tree.newNativeLinearStack(children: bFirst ? [b, a] : [a, b], axis: .vertical, alignment: .topLeading)
    return Tower(tree: tree, root: root, a: a, aNodes: [a, a1, a2])
}

private func rects(_ t: Tower) -> [LayoutRect] {
    ([t.root] + t.aNodes + t.tree.children(t.root)).map { t.tree.layout($0) }
}

/// 2.1 — a marked subtree in the place it stood is restored, not placed: one subtree hit, the same
/// rects as a memo-free tree. **Red before:** `memoSubtreeHits` reads 0. **Mutation:** the lookup
/// disabled (`lookupPlacement` returning `nil` in `subtreePlacement`) reddens the count; the restore
/// loop not writing `layouts` reddens the rect comparison.
@Test @MainActor func aMarkedSubtreeInTheSamePlaceIsRestoredNotPlaced() throws {
    let memo = LayoutMemo()
    let first = tower(generation: 1, bWidth: 30, memo: memo)
    first.tree.computeNativeLayout(root: first.root, proposal: big, in: bounds)
    #expect(first.tree.lastNativeLayoutWork.memoSubtreeHits == 0, "first sight places and stores")
    memo.endFrame()
    // B changes width: the root's signature differs (the root memo misses), A's does not.
    let second = tower(generation: 2, bWidth: 45, memo: memo)
    second.tree.computeNativeLayout(root: second.root, proposal: big, in: bounds)
    #expect(second.tree.lastNativeLayoutWork.memoRootHits == 0)
    #expect(second.tree.lastNativeLayoutWork.memoSubtreeHits == 1)
    let fresh = tower(generation: 3, bWidth: 45, mark: false, memo: nil)
    fresh.tree.computeNativeLayout(root: fresh.root, proposal: big, in: bounds)
    #expect(rects(second) == rects(fresh), "a restored placement is a fresh placement, bit for bit")
}

/// 2.2 — a restore places nothing under the node: the second run asks for fewer measurements than
/// a memo-free run of the same tree, because A's children are not asked about while A is placed. **Red before:** the two runs ask equally often. **Mutation:** as 2.1.
@Test @MainActor func aRestoredSubtreeIsNotDescended() throws {
    func requests(_ work: NativeLayoutWork) -> Int { work.cacheHits + work.cacheMisses + work.memoHits + work.memoMisses }
    let memo = LayoutMemo()
    let first = tower(generation: 1, bWidth: 30, memo: memo)
    first.tree.computeNativeLayout(root: first.root, proposal: big, in: bounds)
    memo.endFrame()
    let second = tower(generation: 2, bWidth: 45, memo: memo)
    second.tree.computeNativeLayout(root: second.root, proposal: big, in: bounds)
    let fresh = tower(generation: 3, bWidth: 45, mark: false, memo: nil)
    fresh.tree.computeNativeLayout(root: fresh.root, proposal: big, in: bounds)
    #expect(second.tree.lastNativeLayoutWork.memoSubtreeHits == 1)
    #expect(requests(second.tree.lastNativeLayoutWork) < requests(fresh.tree.lastNativeLayoutWork),
            "A's leaves are not asked about when A is restored")
}

/// 2.3 — **no translation**: a marked subtree whose bounds moved is placed fresh. B before A
/// grows, so A's `y` moves; the restore would put A's leaves at the old `y`. **Red before:** the
/// hit count reads 0 for the wrong reason (nothing restores); the rect equality passes, so this
/// test's red is its *counter* arm in 2.1. **Mutation** (the one it exists for): the placement key
/// built with `bounds.x`/`y` zeroed reddens the rect comparison here.
@Test @MainActor func aMovedSubtreeIsPlacedFreshNotRestored() throws {
    let memo = LayoutMemo()
    let first = tower(generation: 1, bWidth: 30, bHeight: 10, bFirst: true, memo: memo)
    first.tree.computeNativeLayout(root: first.root, proposal: big, in: bounds)
    memo.endFrame()
    let second = tower(generation: 2, bWidth: 30, bHeight: 14, bFirst: true, memo: memo)
    second.tree.computeNativeLayout(root: second.root, proposal: big, in: bounds)
    #expect(second.tree.lastNativeLayoutWork.memoSubtreeHits == 0)
    let fresh = tower(generation: 3, bWidth: 30, bHeight: 14, mark: false, bFirst: true, memo: nil)
    fresh.tree.computeNativeLayout(root: fresh.root, proposal: big, in: bounds)
    #expect(rects(second) == rects(fresh))
    #expect(second.tree.layout(second.aNodes[1]).y == 14, "A's first leaf sits under B at its new height")
}

/// 2.4 — the proposal is in the key: same signature, same bounds, a different proposal places the
/// child elsewhere (`ProposalShifted`). **Red before:** the equality passes but hits are 0, so the
/// red is 2.1's; **mutation:** the key built with an empty `ProposedSize` reddens the rect equality.
@Test @MainActor func aDifferentProposalOverTheSameBoundsIsPlacedFresh() throws {
    func build(_ generation: UInt64, memo: LayoutMemo?, mark: Bool) -> (LayoutTree, LayoutNodeID, LayoutNodeID) {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let leaf = keyed(tree, "k", width: 10, height: 10)
        let custom = tree.newNativeLayout(ProposalShifted(), children: [leaf])
        if mark { tree.markPlacementRoot(custom) }
        let root = tree.newNativeFrame(child: custom, width: nil, height: nil, alignment: .topLeading)
        return (tree, root, leaf)
    }
    let memo = LayoutMemo()
    let one = build(1, memo: memo, mark: true)
    one.0.computeNativeLayout(root: one.1, proposal: ProposedSize(width: 200, height: 100), in: bounds)
    memo.endFrame()
    let two = build(2, memo: memo, mark: true)
    two.0.computeNativeLayout(root: two.1, proposal: ProposedSize(width: 300, height: 100), in: bounds)
    #expect(two.0.lastNativeLayoutWork.memoSubtreeHits == 0)
    let fresh = build(3, memo: nil, mark: false)
    fresh.0.computeNativeLayout(root: fresh.1, proposal: ProposedSize(width: 300, height: 100), in: bounds)
    #expect(two.0.layout(two.2) == fresh.0.layout(fresh.2))
    #expect(two.0.layout(two.2).x == 30, "the child is placed at the new proposal's tenth")
}

/// 2.5 — an unmarked subtree is not restored (the mark is the opt-in), and a marked one holding an
/// unkeyed leaf (no signature) is neither stored nor restored. **Red before:** both read 0 already;
/// the pair separates 2.1 (marked and keyed restores). **Mutation:** treating every node as marked
/// reddens the first; hashing a missing signature as a constant reddens the second.
@Test @MainActor func onlyAMarkedKeyedSubtreeIsRestored() throws {
    for arm in ["unmarked", "unkeyed"] {
        let memo = LayoutMemo()
        func build(_ generation: UInt64, bWidth: Double) -> Tower {
            guard arm == "unkeyed" else { return tower(generation: generation, bWidth: bWidth, mark: false, memo: memo) }
            let tree = LayoutTree(generation: generation)
            tree.memo = memo
            let a1 = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
            let a = tree.newNativeLinearStack(children: [a1], axis: .horizontal)
            tree.markPlacementRoot(a)
            let b = keyed(tree, "b\(bWidth)", width: bWidth)
            let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical, alignment: .topLeading)
            return Tower(tree: tree, root: root, a: a, aNodes: [a, a1])
        }
        let one = build(1, bWidth: 30)
        one.tree.computeNativeLayout(root: one.root, proposal: big, in: bounds)
        memo.endFrame()
        let two = build(2, bWidth: 45)
        two.tree.computeNativeLayout(root: two.root, proposal: big, in: bounds)
        #expect(two.tree.lastNativeLayoutWork.memoSubtreeHits == 0, "\(arm)")
    }
}

/// 2.6 — verify mode recomputes a restore from nothing and compares (`IV-J`); on an honest restore it
/// passes and still counts the hit. **Red before:** hits 0. **Mutation:** a restore that writes the
/// rects one point to the right traps in verify mode (run once by hand; recorded in record 109 §11).
@Test @MainActor func aVerifiedRestoreStillCountsAndAgrees() throws {
    let memo = LayoutMemo(verifies: true)
    let first = tower(generation: 1, bWidth: 30, memo: memo)
    first.tree.computeNativeLayout(root: first.root, proposal: big, in: bounds)
    memo.endFrame()
    let second = tower(generation: 2, bWidth: 45, memo: memo)
    second.tree.computeNativeLayout(root: second.root, proposal: big, in: bounds)
    #expect(second.tree.lastNativeLayoutWork.memoSubtreeHits == 1)
}

/// 2.7 — a restored placement survives the rounding pass the same way: stored rects are rounded after
/// the restore, and the measured widths the rounding records equal a fresh run's. Fractional leaves
/// make rounding visible. **Red before:** hits 0. **Mutation:** storing the *rounded* rects in the memo
/// (store after `roundNativeStoredRects`) reddens the equality on the second restore (rounded twice).
@Test @MainActor func aRestoreIsRoundedLikeAFreshPlacement() throws {
    func build(_ generation: UInt64, memo: LayoutMemo?, bWidth: Double, mark: Bool) -> Tower {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let a1 = keyed(tree, "a1", width: 30.3, height: 12.7), a2 = keyed(tree, "a2", width: 40.6, height: 8.2)
        let a = tree.newNativeLinearStack(children: [a1, a2], axis: .horizontal, spacing: 3.3)
        if mark { tree.markPlacementRoot(a) }
        let b = keyed(tree, "b\(bWidth)", width: bWidth, height: 10.5)
        let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical, alignment: .topLeading)
        return Tower(tree: tree, root: root, a: a, aNodes: [a, a1, a2])
    }
    let memo = LayoutMemo()
    var restored = 0
    for generation in UInt64(1)...4 {
        let t = build(generation, memo: memo, bWidth: 20 + Double(generation), mark: true)
        t.tree.computeNativeLayout(root: t.root, proposal: big, in: bounds)
        restored += t.tree.lastNativeLayoutWork.memoSubtreeHits
        let fresh = build(generation + 10, memo: nil, bWidth: 20 + Double(generation), mark: false)
        fresh.tree.computeNativeLayout(root: fresh.root, proposal: big, in: bounds)
        #expect(rects(t) == rects(fresh), "generation \(generation)")
        memo.endFrame()
    }
    #expect(restored == 3, "generations 2...4 restore A")
}

private final class Drift: @unchecked Sendable { var value = 0.0 }

/// A custom layout whose placement is impure (it moves its child one point further each time it is
/// asked) under one signature: the stand-in for a key that omitted an input.
private struct Drifting: ProposalLayout, Hashable {
    let drift: Drift
    static func == (l: Drifting, r: Drifting) -> Bool { true }
    func hash(into hasher: inout Hasher) {}
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 50, height: 20))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        drift.value += 1
        subviews[0].place(at: Point(x: bounds.x + drift.value, y: bounds.y), anchor: .topLeading,
                          proposal: ProposedSize(width: 10, height: 10))
    }
}

/// 2.8 — verify mode traps when a restore differs from a fresh placement (`IV-J`, `SB-AD` 4). The
/// impure layout above is restored on its second sight and compared with a fresh placement that moves
/// the child again. **Mutation:** the `precondition` in `subtreePlacement` removed (or `memo.verifies`
/// not consulted) lets the process exit normally -> red. Run as written; the aborted text names `SB-AD`.
@Test func aVerifiedRestoreThatDiffersFromAFreshPlacementTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let memo = LayoutMemo(verifies: true)
        let drift = Drift()
        for generation in 1...3 as ClosedRange<UInt64> {
            let tree = LayoutTree(generation: generation)
            tree.memo = memo
            let leaf = tree.newNativeLeaf(key: "k") { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
            let custom = tree.newNativeLayout(Drifting(drift: drift), children: [leaf])
            tree.markPlacementRoot(custom)
            let other = tree.newNativeLeaf(key: "o\(generation)") { _ in LayoutMeasurement(size: SizeD(width: 4, height: 4)) }
            let root = tree.newNativeLinearStack(children: [custom, other], axis: .vertical, alignment: .topLeading)
            tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                     in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
            memo.endFrame()
        }
    }
    let text = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(text.contains("SB-AD"), "aborted, but not at the subtree placement's verification:\n\(text)")
}
