import Testing
import MetalUICore
@testable import MetalUILayout

// C14-f lane 2 (`RG-E`): a marked subtree whose structural signature, proposal and **size** equal an earlier placement's but whose origin
// moved by an exact sixteenth gets that placement back translated; any other move falls back to the exact-origin key (`SB-AD`).
// Counts and values, never time. Each test runs the memo in verify mode: a translated hit is recomputed from nothing and compared.

private func keyed(_ tree: LayoutTree, _ key: String, width: Double, height: Double) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

private let big = ProposedSize(width: 400, height: 200)
private let bounds = LayoutRect(x: 0, y: 0, width: 400, height: 200)

private struct Stack {
    let tree: LayoutTree, root: LayoutNodeID, a: LayoutNodeID
    var all: [LayoutRect] { tree.children(root).flatMap { [$0] + tree.children($0) }.map { tree.layout($0) } + [tree.layout(root)] }
}

/// `[A, B]` trailing-aligned: A a horizontal stack of two leaves (marked), B a leaf of `bWidth`; A's x is `300 - ...` so B's width moves it.
@MainActor private func stack(_ generation: UInt64, bWidth: Double, mark: Bool = true, memo: LayoutMemo?) -> Stack {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    let a1 = keyed(tree, "a1", width: 30, height: 12), a2 = keyed(tree, "a2", width: 40, height: 8)
    let a = tree.newNativeLinearStack(children: [a1, a2], axis: .horizontal, spacing: 3.25)
    if mark { tree.markPlacementRoot(a) }
    let b = keyed(tree, "b\(bWidth)", width: bWidth, height: 10)
    let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical, alignment: .trailing)
    return Stack(tree: tree, root: root, a: a)
}

private func run(_ s: Stack) -> NativeLayoutWork {
    s.tree.computeNativeLayout(root: s.root, proposal: big, centredIn: bounds)
    return s.tree.lastNativeLayoutWork
}

/// 7 - B grows from 30 to 100 (an exact move of A's origin by 35: the trailing edge is fixed, A's width is 73.25): A restores translated, the
/// rects equal a memo-free tree's bit for bit. Red before: `memoSubtreeHits` reads 0 (the exact key misses). Mutation: the translated
/// lookup removed; or the origin not added back (verify mode traps and the rects differ).
@Test @MainActor func aSubtreeShiftedByAnExactAmountRestoresTranslated() throws {
    let memo = LayoutMemo(verifies: true)
    let first = stack(1, bWidth: 30, memo: memo)
    _ = run(first)
    memo.endFrame()
    let second = stack(2, bWidth: 100, memo: memo)
    let work = run(second)
    #expect(work.memoRootHits == 0)
    #expect(work.memoSubtreeHits == 1, "A restored where it moved")
    let fresh = stack(3, bWidth: 100, mark: false, memo: nil)
    _ = run(fresh)
    #expect(second.all == fresh.all, "bit for bit")
    #expect(first.tree.layout(first.a).x != second.tree.layout(second.a).x, "the fixture moved A")
}

/// 8 - an origin that is not an exact sixteenth falls back to the exact key (a miss: A is placed fresh); the rects equal a fresh tree's.
/// B's width 100.3 moves A by 35.15. Mutation: the exactness guard dropped (the hit is taken; verify mode compares it with a fresh
/// placement, and the count reads 1).
@Test @MainActor func aNonSixteenthShiftFallsBackToTheExactKey() throws {
    let memo = LayoutMemo(verifies: true)
    _ = run(stack(1, bWidth: 30, memo: memo))
    memo.endFrame()
    let second = stack(2, bWidth: 100.3, memo: memo)
    let work = run(second)
    #expect(work.memoSubtreeHits == 0, "an inexact origin is placed fresh")
    let fresh = stack(3, bWidth: 100.3, mark: false, memo: nil)
    _ = run(fresh)
    #expect(second.all == fresh.all)
}

/// 8b - a subtree holding a custom layout is never translated (its placement may read the absolute origin): the exact key decides.
/// Mutation: the custom-layout refusal removed (the count reads 1).
@Test @MainActor func aSubtreeHoldingACustomLayoutIsNotTranslated() throws {
    struct Absolute: ProposalLayout, Hashable {
        func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
            LayoutMeasurement(size: SizeD(width: 50, height: 20))
        }
        func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
            subviews[0].place(at: Point(x: bounds.x.rounded(.down) * 2, y: bounds.y), anchor: .topLeading,
                              proposal: ProposedSize(width: 10, height: 10))
        }
    }
    func build(_ generation: UInt64, bWidth: Double, memo: LayoutMemo?) -> Stack {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let leaf = keyed(tree, "leaf", width: 10, height: 10)
        let a = tree.newNativeLayout(Absolute(), children: [leaf])
        tree.markPlacementRoot(a)
        let b = keyed(tree, "b\(bWidth)", width: bWidth, height: 10)
        let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical, alignment: .trailing)
        return Stack(tree: tree, root: root, a: a)
    }
    let memo = LayoutMemo(verifies: true)
    _ = run(build(1, bWidth: 30, memo: memo))
    memo.endFrame()
    let second = build(2, bWidth: 100, memo: memo)
    #expect(run(second).memoSubtreeHits == 0)
    let fresh = build(3, bWidth: 100, memo: nil)
    fresh.tree.computeNativeLayout(root: fresh.root, proposal: big, centredIn: bounds)
    #expect(second.all == fresh.all)
}
