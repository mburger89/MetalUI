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
/// **The kernel's proposal sequence, by hand** — re-derived for ruling CN-B
/// (plan task 6, lane 1: the flexibility-ordered distribution, and
/// `ReferenceLinearStack` rewritten to it), and for ruling CN-G (lane 2: AR
/// proposes its ratio-shaped size once and answers b2's answer; the tree has
/// no spacer, so CN-C's marks change nothing). "miss" runs a body; "hit" is a
/// lookup that found its key; "call" is user code (a leaf closure or a custom
/// `sizeThatFits`). Proposals are written (width, height); c is a cross height.
///
/// **One evaluation of A at (100, c)** (H, 100 − 6 = 94 left): miss A.
/// Priority 1 reserves the lower children's minimums at (0, c): a2, a3 and P4
/// → a4 (4 misses, 3 calls, all 0 wide) and offers P1 94 → a1 (2 misses, 1
/// call, 40). Priority 0 reserves P4 (hit), probes a2 and a3 at (∞, c) (2
/// misses, 2 calls) and (0, c) (2 hits), and, tied at flexibility 30, offers a2
/// 27 and a3 27 (2 misses, 2 calls). Priority −1 offers P4 0 (hit). A answers
/// 100×12 at every c. **11 misses, 4 hits, 8 calls.**
///
/// **B at (100, c)** (overlay, each child at (100, c)): AR proposes (100, 50)
/// when 100 / 2 ≤ c, else (2c, c). c = ∞ — B, b1, AR, b2 at (100, 50), b3: 5
/// misses, 3 calls, 100×50; c = 0 — the same five, b2 at (0, 0): 5 misses, 3
/// calls, 30×14; c = 94 — b2 at (100, 50) is a hit: 4 misses, 1 hit, 2 calls,
/// 100×50. (Lane 1's AR also measured b2 at its parent's proposal first: 6/4,
/// 6/4, 5/1/3.)
///
/// **C at (100, c)** (the reference stack, one group of three): miss C, call
/// its `sizeThatFits`. It probes c1, F and c3 at (∞, c) and (0, c) (F → c2 at
/// the same keys) and serves c1 (flexibility 0) at 33.3 → 20, c3 (0) at 40 →
/// 15, F (∞) at 65 → c2 at (65, c). **13 misses, 10 calls.** C answers
/// 100 × max(10, c, 5): ∞ at c = ∞, 10 at c = 0.
///
/// **Measure R at (100, 200)** (V, one group of three): miss R. It probes A,
/// B and C at (100, ∞) and (100, 0) — flexibilities A 0, B 36, C ∞ — and
/// serves A at 66.67 (→ 12), B at 94 (→ 50), C at 138 (→ 138). So A, B and C
/// are each evaluated three times: A 33 misses, 12 hits, 24 calls; B 14
/// misses, 1 hit, 8 calls; C 39 misses, 30 calls. **87 misses, 13 hits, 62
/// calls.**
///
/// **Place R** at (100, 200), cross 100 given, so no second pass: its solve
/// re-asks the six probes and three offers (9 hits).
/// - Place A (proposal (100, 66.67)): its solve re-asks its 12 lookups (12
///   hits); placing P1 and P4 re-asks a1 and a4 (2 hits). **14.**
/// - Place B (ruling CN-E's `ZStack` clause, lane 4): B is stored at its
///   answer, 100×50, and proposes each child that size — b1, AR and b3 at
///   (100, 50) are new keys (3 misses, 2 calls: b1 and b3); AR's body asks b2
///   at (100, 50) (1 hit); placing AR re-asks b2 there (1 hit). **3 misses, 2
///   hits, 2 calls** (before lane 4, at B's proposal (100, 94): 4 hits).
/// - Place C: its `placeSubviews` re-solves at (100, 138) (9 hits) and records
///   each child; the kernel measures each record (3 hits) and placing F re-asks
///   c2 at (65, 138) (1 hit). **13.**
/// **38 hits, 3 misses, 2 calls.**
///
/// Totals: misses 87 + 3 = **90**; hits 13 + 38 = **51**; calls 62 + 2 =
/// **64** (lanes 2–3: 87, 53, 62; lane 1: 90, 54, 65; before CN-B: 25, 27,
/// 16). The staged prototype read 66 / 51 / 47 after
/// lane 1 and 63 / 50 / 44 after lane 2 (CN-B's table); it did not carry this
/// file's rewritten reference stack, so its C evaluated differently — a
/// difference recorded in `docs/record/17-containers.md`, not an edit to these
/// literals. Lane 2 moves the same three counts the prototype did: −3 misses,
/// −1 hit, −3 calls.
///
/// **(4)**: A is placed at (7, 11), 12 tall; a3 lands at x = 7 + 40 + 2 + 27 + 2
/// = 78, y = 11 + (12 − 8) × 0.5 = 13, at its offer 27 and its own 8:
/// (78, 13, 27, 8) — unchanged by CN-B.
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
    #expect(work.measureCalls == 64, "measureCalls")
    #expect(work.cacheHits == 51, "cacheHits")
    #expect(work.cacheMisses == 90, "cacheMisses")

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
