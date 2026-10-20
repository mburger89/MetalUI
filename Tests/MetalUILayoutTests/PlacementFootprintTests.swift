import Testing
import MetalUICore
@testable import MetalUILayout

// C14-e lane 2 (`CF-E`, `CF-J`): what a restored subtree placement stands for stays alive. A restore (`SB-AD`) places
// nothing, so it looks nothing up, and the layout memo's two generations drop every entry below it while it keeps
// hitting; the first frame that must measure or place the subtree for itself (a graft, a changed bound) then pays for
// all of it at once. The placement now carries a footprint (the memo keys its recording used) and a restore touches it.
// Counts, never time. Window-level pin: `MetalUITestingTests/WarmSettleTests.swift`.

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

private let big = ProposedSize(width: 200, height: 200)
private let bounds = LayoutRect(x: 0, y: 0, width: 200, height: 200)

/// `[O, b]` vertical: O a horizontal stack of `[I, c]`, I a horizontal stack of two keyed leaves. `markOuter` and
/// `markInner` choose which of O and I are placement roots; `bWidth` changes the root's signature every frame so the
/// root memo never hits and the marked roots are what is restored.
@MainActor private func nest(generation: UInt64, bWidth: Double, markOuter: Bool, markInner: Bool, memo: LayoutMemo)
    -> LayoutTree {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    let i1 = keyed(tree, "i1", width: 30, height: 12), i2 = keyed(tree, "i2", width: 40, height: 8)
    let inner = tree.newNativeLinearStack(children: [i1, i2], axis: .horizontal)
    let c = keyed(tree, "c", width: 25, height: 9)
    let outer = tree.newNativeLinearStack(children: [inner, c], axis: .horizontal)
    if markInner { tree.markPlacementRoot(inner) }
    if markOuter { tree.markPlacementRoot(outer) }
    let b = keyed(tree, "b\(bWidth)", width: bWidth, height: 10)
    let root = tree.newNativeLinearStack(children: [outer, b], axis: .vertical, alignment: .topLeading)
    tree.computeNativeLayout(root: root, proposal: big, in: bounds)
    return tree
}

/// F1 — after a marked subtree has been restored for two frames, the frame that must place it for itself (the root unmarked,
/// as a graft leaves it: its nodes carry no mark) finds its leaves' measurements in the memo. Only `b`, whose width changes
/// every frame, is measured. **Red before (679f5d7d):** the misses and measure calls exceed the control's (the inner stack and both leaves are measured again). **Mutation:** the
/// `memo.touch` removed from `subtreePlacement`.
@Test @MainActor func aRestoredSubtreeKeepsItsMeasurementsAlive() throws {
    let memo = LayoutMemo()
    let first = nest(generation: 1, bWidth: 30, markOuter: false, markInner: true, memo: memo)
    #expect(first.lastNativeLayoutWork.memoSubtreeHits == 0, "first sight places and records")
    memo.endFrame()
    for (n, width) in [(2, 45.0), (3, 60.0)] {
        let restored = nest(generation: UInt64(n), bWidth: width, markOuter: false, markInner: true, memo: memo)
        try #require(restored.lastNativeLayoutWork.memoSubtreeHits == 1, "frame \(n) restores the inner subtree")
        memo.endFrame()
    }
    let placed = nest(generation: 4, bWidth: 75, markOuter: false, markInner: false, memo: memo)
    let work = placed.lastNativeLayoutWork
    #expect(work.memoSubtreeHits == 0, "nothing is marked in the fourth frame")
    // The control: the same four widths with nothing ever marked, so nothing was ever restored and nothing could age. What is
    // new in the fourth frame is `b` alone (and the root above it), at the stack's two probes: 4 misses, 3 measure calls.
    let control = LayoutMemo()
    var controlWork = NativeLayoutWork()
    for (n, width) in [(1, 30.0), (2, 45.0), (3, 60.0), (4, 75.0)] {
        controlWork = nest(generation: UInt64(n), bWidth: width, markOuter: false, markInner: false, memo: control).lastNativeLayoutWork
        control.endFrame()
    }
    #expect(controlWork.memoMisses == 4 && controlWork.measureCalls == 3, "the control: \(controlWork)")
    #expect(work.memoMisses == controlWork.memoMisses && work.measureCalls == controlWork.measureCalls,
            "a restored subtree's leaves are not measured again: misses \(work.memoMisses), measures \(work.measureCalls)")
}

/// F2 — a restored subtree inside a restored subtree: the inner placement entry and the outer footprint both survive,
/// so the frame that unmarks only the outer one still restores the inner. **Red before:** the inner placement entry has
/// aged out (`memoSubtreeHits == 0`). **Mutation:** the inner placement key not appended to the enclosing recording's
/// footprint (`run.footprintLog.placements.append(recording)` removed) reddens the hit arm; the `touch` removed reddens both.
@Test @MainActor func aRestoredSubtreeKeepsAnInnerPlacementAlive() throws {
    let memo = LayoutMemo()
    _ = nest(generation: 1, bWidth: 30, markOuter: true, markInner: true, memo: memo)
    memo.endFrame()
    for (n, width) in [(2, 45.0), (3, 60.0)] {
        let restored = nest(generation: UInt64(n), bWidth: width, markOuter: true, markInner: true, memo: memo)
        try #require(restored.lastNativeLayoutWork.memoSubtreeHits == 1, "frame \(n) restores the outer subtree only")
        memo.endFrame()
    }
    let placed = nest(generation: 4, bWidth: 75, markOuter: false, markInner: true, memo: memo)
    let work = placed.lastNativeLayoutWork
    #expect(work.memoSubtreeHits == 1, "the inner subtree is still restorable: \(work.memoSubtreeHits)")
    #expect(work.memoMisses == 4 && work.measureCalls == 3, "only b (and the root) is new, as in F1's control: \(work)")
}

/// F3 — a control, green before and after: a footprint keeps only what the memo still had. After the memo has aged out
/// completely the next frame records anew (no restore, no phantom entry), and the entry count stays bounded by what that
/// one frame stored. **Mutation:** `touch` inserting a key found in neither generation cannot be built (it has no value to insert), so
/// this guards the shape, not a mutant.
@Test @MainActor func aTouchAddsNoEntryAndCountsNoLookup() throws {
    let memo = LayoutMemo()
    _ = nest(generation: 1, bWidth: 30, markOuter: false, markInner: true, memo: memo)
    memo.endFrame()
    let before = memo.entryCount
    memo.endFrame(); memo.endFrame()   // everything ages out
    #expect(memo.entryCount == 0)
    let second = nest(generation: 2, bWidth: 45, markOuter: false, markInner: true, memo: memo)
    #expect(second.lastNativeLayoutWork.memoSubtreeHits == 0, "the aged-out placement is a miss, so it records anew")
    #expect(memo.entryCount > 0 && memo.entryCount <= before + 4)
}
