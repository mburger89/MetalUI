import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 2 ("boundaries") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the invalidation contract, ruling SA-H, and the one layout flag, ruling SA-I,
// in `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
//
// `@testable` because it reads `isLayingOut` and `measureNativeLayout`, both
// internal.
//
// SA-H clause 2 (each `(node, proposal)` body runs at most once per call) is
// pinned by lane 1's `aSubviewMeasuresOncePerDistinctProposalWithinOneRun`, and
// lane 3's count test pins it on a branching tree; it gets no third test here.
//
// **Three tests below are green on arrival**, because the kernel already builds
// a fresh cache per call. For those, the mutation named in each doc comment is
// the red run, and it was run and recorded before the tests were committed.

/// A counter a `@Sendable` measure closure may carry.
private final class Calls: @unchecked Sendable {
    var proposals: [[ProposedSize]]
    init(_ count: Int) { proposals = Array(repeating: [], count: count) }
    var counts: [Int] { proposals.map(\.count) }
}

// MARK: - One flag for both engines

nonisolated(unsafe) private var flagTree: LayoutTree?
nonisolated(unsafe) private var flagSeenInside = 0

/// Native layout holds `isLayingOut` while it runs, and only then (ruling SA-I).
///
/// An exit `.success` test, because its red run on a correct-looking mutation
/// is a trap: a flag that is never cleared makes the `setStyle` after the call
/// abort, and in-process that would take the suite with it (practices shape 11).
@Test func nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        flagTree = tree
        let legacy = tree.newNode(style: Style(), children: [])
        let leaf = tree.newNativeLeaf { _ in
            precondition(flagTree?.isLayingOut == true,
                         "isLayingOut is false inside a native measure closure")
            flagSeenInside += 1
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        precondition(!tree.isLayingOut, "isLayingOut before the call")
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
        precondition(flagSeenInside > 0, "the measure closure never ran")
        precondition(!tree.isLayingOut, "isLayingOut still true after the call returned")
        tree.setStyle(legacy, Style())
    }
}

// MARK: - Measurement never writes a rect

/// Lane 1's reference tree (`ProposalLayoutTests.swift`'s `ReferenceTree`),
/// rebuilt here with the built-in stack only, because that builder is private
/// to its file. Same geometry, including the x.5 adjustment recorded there.
private func buildReferenceTree(_ tree: LayoutTree) -> (root: LayoutNodeID, all: [LayoutNodeID]) {
    var all: [LayoutNodeID] = []
    func keep(_ id: LayoutNodeID) -> LayoutNodeID { all.append(id); return id }
    func fixed(_ width: Double, _ height: Double) -> LayoutNodeID {
        keep(tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: height)) })
    }
    func flexible(ideal: Double, height: Double) -> LayoutNodeID {
        keep(tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal), height: height))
        })
    }

    let a80p = keep(tree.newNativeLayoutPriority(child: flexible(ideal: 80, height: 9), priority: 1))
    let a60 = flexible(ideal: 60, height: 11)
    let a50p = keep(tree.newNativeLayoutPriority(child: flexible(ideal: 50, height: 7), priority: -1))
    let a20 = fixed(20, 13)
    let a = keep(tree.newNativeLinearStack(children: [a80p, a60, a50p, a20], axis: .horizontal,
                                           spacing: 3, alignment: .bottom))

    let b30 = fixed(30, 10)
    let bSpacer = keep(tree.newNativeSpacer(minLength: 10))
    let b20 = fixed(20, 18)
    let bSpacer2 = keep(tree.newNativeLayoutPriority(child: keep(tree.newNativeSpacer()), priority: 2))
    let b11 = fixed(11, 8)
    let b = keep(tree.newNativeLinearStack(children: [b30, bSpacer, b20, bSpacer2, b11], axis: .horizontal,
                                           spacing: 5, alignment: .center))

    let root = keep(tree.newNativeLinearStack(children: [a, b], axis: .vertical, spacing: 7,
                                              alignment: .trailing))
    return (root, all)
}

/// `measureNativeLayout` measures and writes nothing (ruling SA-H clause 4):
/// every stored rect and measured width stays at its registration zero, and
/// its answer equals `computeNativeLayout`'s on a twin tree.
///
/// **Shape 15:** the twin's rects are `try #require`d NOT all zero, so "every
/// rect is zero" is a claim a placing entry point could fail.
///
/// The answer is **157×38** (derivation in
/// `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`). Plan
/// task 6's lane 1 (ruling CN-B) read 157×91, because the root's second child
/// holds spacers that, unmarked until lane 2's CN-C, claimed the 71pt cross
/// proposal the distribution offered it; lane 2's marks restore 38.
@Test func measuringANativeTreeWritesNoRect() throws {
    let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)
    let proposal = ProposedSize(width: 157, height: 91)

    let measured = LayoutTree(generation: 0)
    let measuredIDs = buildReferenceTree(measured)
    let measurement = measured.measureNativeLayout(root: measuredIDs.root, proposal: proposal)

    let twin = LayoutTree(generation: 0)
    let twinIDs = buildReferenceTree(twin)
    let placed = twin.computeNativeLayout(root: twinIDs.root, proposal: proposal,
                                          in: LayoutRect(x: 13, y: 17, width: 157, height: 91))
    try #require(twinIDs.all.contains { twin.layout($0) != zero },
                 "the twin must store rects, or 'every rect is zero' discriminates nothing")

    #expect(measurement == placed)
    #expect(measurement == LayoutMeasurement(size: SizeD(width: 157, height: 38)))
    for (index, id) in measuredIDs.all.enumerated() {
        #expect(measured.layout(id) == zero, "node \(index)")
        #expect(measured.measuredWidth(id) == 0, "measured width of node \(index)")
    }
}

// MARK: - A cache per call (SA-H clauses 1 and 5)

/// A horizontal stack, spacing 0, of `widths.count` leaves: leaf `i` answers
/// `min(widths[i], proposal.width ?? widths[i])` × `height` and records every
/// proposal its closure is called with.
private func recordingStack(_ tree: LayoutTree, widths: [Double], height: Double,
                            calls: Calls) -> (root: LayoutNodeID, leaves: [LayoutNodeID]) {
    let leaves = widths.enumerated().map { index, ideal in
        tree.newNativeLeaf { proposal in
            calls.proposals[index].append(proposal)
            return LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal),
                                                 height: height))
        }
    }
    return (tree.newNativeLinearStack(children: leaves, axis: .horizontal), leaves)
}

/// Two `computeNativeLayout` calls on one tree at one proposal measure every
/// leaf again: nothing survives a call (ruling SA-H clause 1). **This is the
/// deliberate divergence from SwiftUI's probe F**, where a forced same-size
/// relayout re-ran nothing.
///
/// Hand-derived for ruling CN-B (plan task 6, lane 1): three leaves capped at
/// 30, 40 and 20 in a stack offered 120×80 form one priority group, so each is
/// probed at (∞, 80) and (0, 80) and then offered its share — the 20 leaf
/// (flexibility 20) at 40, the 30 leaf at 50, the 40 leaf at 70 — and placement
/// re-asks those keys, all hits. Three calls per leaf per call.
///
/// Green on arrival. Red run: the cache hoisted to a stored property on
/// `LayoutTree`, so the second call reads the first call's entries.
@Test func aSecondComputeNativeLayoutCallReMeasuresEveryLeaf() {
    let tree = LayoutTree(generation: 0)
    let calls = Calls(3)
    let (root, _) = recordingStack(tree, widths: [30, 40, 20], height: 10, calls: calls)
    let proposal = ProposedSize(width: 120, height: 80)
    let bounds = LayoutRect(x: 0, y: 0, width: 120, height: 80)

    tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    #expect(calls.counts == [3, 3, 3])
    tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    #expect(calls.counts == [6, 6, 6])
}

/// A second call at a different root proposal re-measures at the new
/// allocations and moves the stored rects (ruling SA-H clause 5).
///
/// Hand-derived for ruling CN-B (plan task 6, lane 1): two leaves of ideal 70,
/// height 10, in a horizontal stack.
/// - At 120×80: each probed at (∞, 80) → 70 and (0, 80) → 0 (equal
///   flexibility, declaration order), the first offered 60, the second the 60
///   left. Rects (0, 35, 60, 10), (60, 35, 60, 10).
/// - At 90×80: a fresh run probes (∞, 80) and (0, 80) again, then offers 45
///   each. Rects (0, 35, 45, 10), (45, 35, 45, 10).
///
/// Green on arrival. Red run: `computeNativeLayout`'s result memoized on the
/// root id alone, so the second call returns without measuring or placing.
@Test func aDifferentRootProposalReMeasuresAndMovesTheRects() {
    let tree = LayoutTree(generation: 0)
    let calls = Calls(2)
    let (root, leaves) = recordingStack(tree, widths: [70, 70], height: 10, calls: calls)

    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 120, height: 80),
                             in: LayoutRect(x: 0, y: 0, width: 120, height: 80))
    #expect(tree.layout(leaves[0]) == LayoutRect(x: 0, y: 35, width: 60, height: 10))
    #expect(tree.layout(leaves[1]) == LayoutRect(x: 60, y: 35, width: 60, height: 10))

    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 90, height: 80),
                             in: LayoutRect(x: 0, y: 0, width: 90, height: 80))
    let expected = [ProposedSize(width: .infinity, height: 80), ProposedSize(width: 0, height: 80),
                    ProposedSize(width: 60, height: 80),
                    ProposedSize(width: .infinity, height: 80), ProposedSize(width: 0, height: 80),
                    ProposedSize(width: 45, height: 80)]
    #expect(calls.proposals[0] == expected)
    #expect(calls.proposals[1] == expected)
    #expect(tree.layout(leaves[0]) == LayoutRect(x: 0, y: 35, width: 45, height: 10))
    #expect(tree.layout(leaves[1]) == LayoutRect(x: 45, y: 35, width: 45, height: 10))
}

/// After `reset(generation:)`, leaves registered at the same indices are
/// measured from scratch: nothing survives a reset (ruling SA-H clause 1).
///
/// Hand-derived: before, leaves 30×10 and 40×10 in a stack at indices 0, 1, 2.
/// After, leaves 50×20 and 25×20 at the same indices. Offered 100×50: the
/// stack measures 75×20, so the leaves sit at y = (50 − 20)/2 = 15:
/// (0, 15, 50, 20) and (50, 15, 25, 20). Under ruling CN-B (plan task 6, lane
/// 1) each closure, before and after, runs three times — probed at (∞, 50) and
/// (0, 50), then offered its share — and no more.
///
/// Green on arrival. Red run: a persistent cache keyed on `(id.index, proposal)`
/// that `reset` does not clear.
///
/// The spacer arm (containers lane 2, ruling CN-C): a stack's cross-axis mark
/// does not survive a reset. A default spacer marked by an `HStack` at index 0,
/// then reset, then a bare default spacer registered at index 0 and measured
/// at 100×50 answers 100×50 (probe SPB3), not the stale mark's 100×0.
/// Mutation, measured: deleting `spacerAxes.removeAll` in `reset` reddens it.
@Test func aResetTreeMeasuresItsNewRegistrationsFromScratch() {
    let tree = LayoutTree(generation: 0)
    let proposal = ProposedSize(width: 100, height: 50)
    let bounds = LayoutRect(x: 0, y: 0, width: 100, height: 50)

    let before = Calls(2)
    let (oldRoot, _) = recordingStack(tree, widths: [30, 40], height: 10, calls: before)
    #expect(tree.computeNativeLayout(root: oldRoot, proposal: proposal, in: bounds)
            == LayoutMeasurement(size: SizeD(width: 70, height: 10)))

    tree.reset(generation: 1)
    let after = Calls(2)
    let (root, leaves) = recordingStack(tree, widths: [50, 25], height: 20, calls: after)
    #expect(root.index == oldRoot.index, "the new registrations must reuse the old indices")

    #expect(tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
            == LayoutMeasurement(size: SizeD(width: 75, height: 20)))
    #expect(after.counts == [3, 3])
    #expect(before.counts == [3, 3])
    #expect(tree.layout(leaves[0]) == LayoutRect(x: 0, y: 15, width: 50, height: 20))
    #expect(tree.layout(leaves[1]) == LayoutRect(x: 50, y: 15, width: 25, height: 20))

    do { // a reset clears the spacer marks
        let spacerTree = LayoutTree(generation: 0)
        let marked = spacerTree.newNativeSpacer()
        _ = spacerTree.newNativeLinearStack(children: [marked], axis: .horizontal, spacing: 0)
        spacerTree.reset(generation: 1)
        let bare = spacerTree.newNativeSpacer()
        #expect(bare.index == marked.index, "the bare spacer must reuse the marked index")
        #expect(spacerTree.measureNativeLayout(root: bare, proposal: proposal).size
                == SizeD(width: 100, height: 50))
    }
}
