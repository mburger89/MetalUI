import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 3 ("robustness") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// the native work counters, ruling SA-M in
// `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
//
// Practices: performance tests count work, never wall clock, and measure on a
// BRANCHING tree, never a chain, because a chain collapses every probe onto a
// few keys. `LayoutTree.lastNativeLayoutWork` is the only native work a test
// can read after a call returns; the cache itself dies with the call (SA-H).

/// One leaf's closure log: its call count and the distinct proposals it saw.
private final class LeafLog: @unchecked Sendable {
    var calls = 0
    var proposals: Set<ProposedSize> = []
}

/// A leaf whose width is `min(ideal, proposal.width ?? ideal)`, logging every
/// call.
private func cappedLeaf(_ tree: LayoutTree, ideal: Double, height: Double, _ log: LeafLog) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        log.calls += 1
        log.proposals.insert(proposal)
        return LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal), height: height))
    }
}

/// A leaf of a fixed size, logging every call.
private func fixedLeaf(_ tree: LayoutTree, _ width: Double, _ height: Double, _ log: LeafLog) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        log.calls += 1
        log.proposals.insert(proposal)
        return LayoutMeasurement(size: SizeD(width: width, height: height))
    }
}

/// A leaf answering its proposal, an unspecified axis read as 10, logging
/// every call.
private func echoLeaf(_ tree: LayoutTree, _ log: LeafLog) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        log.calls += 1
        log.proposals.insert(proposal)
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10))
    }
}

/// The branching tree, registered identically on every call.
private struct BranchingTree {
    var root: LayoutNodeID
    var logs: [String: LeafLog] = [:]
    var a3: LayoutNodeID

    init(_ tree: LayoutTree) {
        var logs: [String: LeafLog] = [:]
        func log(_ name: String) -> LeafLog {
            let l = LeafLog()
            logs[name] = l
            return l
        }
        // (i) an overflowing prioritized horizontal stack, spacing 2.
        let a1 = cappedLeaf(tree, ideal: 40, height: 10, log("a1"))
        let a2 = cappedLeaf(tree, ideal: 30, height: 12, log("a2"))
        let a3 = cappedLeaf(tree, ideal: 30, height: 8, log("a3"))
        let a4 = cappedLeaf(tree, ideal: 20, height: 6, log("a4"))
        let branchA = tree.newNativeLinearStack(
            children: [tree.newNativeLayoutPriority(child: a1, priority: 1), a2, a3,
                       tree.newNativeLayoutPriority(child: a4, priority: -1)],
            axis: .horizontal, spacing: 2)
        // (ii) an overlay of three leaves, one under an aspect ratio of 2.
        let b1 = fixedLeaf(tree, 30, 14, log("b1"))
        let b2 = echoLeaf(tree, log("b2"))
        let b3 = fixedLeaf(tree, 16, 6, log("b3"))
        let branchB = tree.newNativeOverlay(children: [b1, tree.newNativeAspectRatio(child: b2, ratio: 2), b3])
        // (iii) a custom reference stack, one child under `frame(idealWidth: 25)`.
        let c1 = fixedLeaf(tree, 20, 10, log("c1"))
        let c2 = echoLeaf(tree, log("c2"))
        let c3 = fixedLeaf(tree, 15, 5, log("c3"))
        let branchC = tree.newNativeLayout(ReferenceLinearStack(axis: .horizontal),
                                           children: [c1, tree.newNativeFrame(child: c2, idealWidth: 25), c3])

        root = tree.newNativeLinearStack(children: [branchA, branchB, branchC], axis: .vertical)
        self.logs = logs
        self.a3 = a3
    }
}

/// The branching tree's work is exactly what a once-per-distinct-proposal cache
/// does, counted against literals derived by hand BEFORE the run (shape 12).
///
/// **The tree.** Root R: a vertical stack, spacing 0, offered (100, 200) at
/// bounds (7, 11, 100, 200), over three branches:
/// - (i) A: a horizontal stack, spacing 2, over P1(a1) · a2 · a3 · P4(a4),
///   where P1/P4 are `layoutPriority` 1 and −1 and the leaves are capped at
///   ideals 40/30/30/20 (heights 10/12/8/6);
/// - (ii) B: an overlay over b1 (fixed 30×14) · AR(b2) · b3 (fixed 16×6),
///   AR an aspect ratio of 2 and b2 an echo leaf (nil → 10);
/// - (iii) C: `ReferenceLinearStack(.horizontal)` over c1 (fixed 20×10) ·
///   F(c2) · c3 (fixed 15×5), F a `frame(idealWidth: 25)` and c2 an echo leaf.
///
/// **The kernel's proposal sequence, by hand.** "miss" runs a body; "hit" is a
/// lookup that found its key; "call" is user code (a leaf closure or a custom
/// `sizeThatFits`).
///
/// Measure R at (100, 200): miss R. Child proposal (100, nil).
/// - A at (100, nil): miss A. Its children at (nil, nil): miss P1 → miss+call
///   a1; miss+call a2; miss+call a3; miss P4 → miss+call a4. Natural
///   40+30+30+20+3×2 = 126, answered min(126, 100) = 100 wide, 12 tall.
///   **7 misses, 4 calls.**
/// - B at (100, nil): miss B. b1 at (100, nil): miss+call. AR: miss; b2 at
///   (100, nil) miss+call → 100×10, so the ratio answers 100×50; b2 at
///   (100, 50) miss+call. b3 at (100, nil): miss+call. **6 misses, 4 calls.**
/// - C at (100, nil): miss C, call its `sizeThatFits`. Children at (nil, nil):
///   c1 miss+call; F miss → c2 at (25, nil) miss+call; c3 miss+call. Natural
///   20+25+15 = 60. **5 misses, 4 calls.**
///
/// Place R: A, B, C at (100, nil) to measure (3 hits), no overflow at 200, so
/// each again at the same constrained proposal (3 hits). **6 hits.**
/// - Place A (width 100): its four children at (nil, nil), 4 hits. Overflow:
///   remaining 100 − 6 = 94; priority 1 takes P1's 40 (54 left); priority 0's
///   ideal 60 > 54, so a2 and a3 get 27 each; priority −1 gets 0. Then P1 at
///   (40, nil) miss → a1 miss+call, and placing P1 re-asks a1, hit; a2 at
///   (27, nil) miss+call; a3 at (27, nil) miss+call; P4 at (0, nil) miss → a4
///   miss+call, and placing P4 re-asks a4, hit. **6 hits, 6 misses, 4 calls.**
/// - Place B: b1, AR, b3 at (100, nil), 3 hits; placing AR re-asks b2 at
///   (100, nil) and (100, 50), 2 hits. **5 hits.**
/// - Place C: its `placeSubviews` asks the three children at (nil, nil) twice
///   (6 hits) and records each at (nil, nil); the kernel then measures each
///   record once (3 hits), and placing F re-asks c2 at (25, nil) (1 hit).
///   **10 hits.**
///
/// Totals: misses 1 + 7 + 6 + 5 + 6 = **25**; hits 6 + 6 + 5 + 10 = **27**;
/// calls 4 + 4 + 4 + 4 = **16**.
///
/// **(4)**: a3 lands at x = 7 + 40 + 2 + 27 + 2 = 78, y = 11 + (12 − 8) × 0.5
/// = 13, at its allocation 27 and its own 8: (78, 13, 27, 8).
///
/// Assertion (1) is **green on arrival**, because the cache predates the
/// counters; (2) and (3) are red against a zero-filled `NativeLayoutWork`.
/// Mutations: disable the cache (delete the hit branch) reddens (1), (2) and
/// (3); key on node only reddens (4); count a hit before checking the key
/// reddens (3).
@Test func aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal() throws {
    let tree = LayoutTree(generation: 0)
    let fixture = BranchingTree(tree)
    tree.computeNativeLayout(root: fixture.root, proposal: ProposedSize(width: 100, height: 200),
                             in: LayoutRect(x: 7, y: 11, width: 100, height: 200))

    // (1) Every leaf closure ran once per distinct proposal it saw.
    try #require(fixture.logs.count == 10)
    for (name, log) in fixture.logs.sorted(by: { $0.key < $1.key }) {
        #expect(log.calls == log.proposals.count,
                "\(name) ran \(log.calls) times for \(log.proposals.count) distinct proposals")
    }

    // (2) and (3), against the hand-derived literals above.
    let work = tree.lastNativeLayoutWork
    #expect(work.measureCalls == 16, "measureCalls")
    #expect(work.cacheHits == 27, "cacheHits")
    #expect(work.cacheMisses == 25, "cacheMisses")

    // (4) A compressed leaf is stored at its hand-derived allocation.
    #expect(tree.layout(fixture.a3) == LayoutRect(x: 78, y: 13, width: 27, height: 8))
}

/// The record is per CALL: a second call on the same tree at the same proposal
/// reports the same counts as the first, not their sum. Its red run is the
/// mutation "accumulate into `lastNativeLayoutWork` instead of assigning it".
@Test func nativeLayoutWorkIsPerCall() throws {
    let tree = LayoutTree(generation: 0)
    let fixture = BranchingTree(tree)
    let proposal = ProposedSize(width: 100, height: 200)
    let bounds = LayoutRect(x: 7, y: 11, width: 100, height: 200)

    tree.computeNativeLayout(root: fixture.root, proposal: proposal, in: bounds)
    let first = tree.lastNativeLayoutWork
    try #require(first.cacheMisses > 0, "the first call counted nothing")
    tree.computeNativeLayout(root: fixture.root, proposal: proposal, in: bounds)
    #expect(tree.lastNativeLayoutWork == first)
}
