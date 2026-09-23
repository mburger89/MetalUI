/// The state of ONE native layout call: its measurement cache, the
/// bookkeeping the subview proxies check against, the depth guard (ruling
/// SA-L) and the work counters (ruling SA-M).
///
/// **A `final class`, not a struct**, for the reason `LayoutContext` records:
/// a struct copied per recursion level shares no cache.
///
/// **Its lifetime is one call.** `LayoutTree.computeNativeLayout` and
/// `measureNativeLayout` each create one, mark it inactive on return and drop
/// it. The tree holds it (`activeNativeRun`) only while that call runs, so
/// `setLayout` can read `measureDepth`, and clears the reference on return: no
/// measurement can outlive the call, let alone the tree generation its keys
/// were minted in (ruling C-3's footing; ruling SA-H's clause 1).
///
/// Subview proxies (`MeasurementSubviews`, `PlacementSubviews` and their
/// elements) hold the run **strongly**, so a proxy that escapes its call
/// reaches the `isActive` precondition and its message rather than an unowned
/// read with no attribution.
final class NativeLayoutRun {
    unowned let tree: LayoutTree
    var cache: [NativeMeasurementKey: LayoutMeasurement] = [:]

    /// False once the entry point that created this run has returned. Every
    /// proxy member checks it first.
    var isActive = true

    /// The token of the innermost `placeSubviews` call in progress; 0 is none.
    /// A `PlacementSubview` may record a placement only while its own call's
    /// token is the active one (ruling SA-C).
    var activePlacement: UInt64 = 0
    var nextPlacementToken: UInt64 = 1

    /// Greater than zero while any measurement body is running: a leaf closure,
    /// a built-in case's body or a custom `sizeThatFits`. A `PlacementSubview`
    /// used while it is non-zero traps (ruling SA-C's dynamic backstop), and so
    /// does `LayoutTree.setLayout` (ruling SA-H clause 4).
    var measureDepth = 0

    /// How many `measureNative` and `placeNative` frames are on the stack
    /// (ruling SA-L). **One counter for both recursions**: placement calls
    /// measurement from inside itself, so counting them together tracks the
    /// real stack.
    private(set) var depth = 0

    /// The largest `depth` `enter` reached in this call, copied to
    /// `LayoutTree.lastNativeLayoutDeepestLevel` when the entry point returns
    /// (plan task 7, stage 6b, ruling `LR-DK`).
    private(set) var deepestLevel = 0

    /// This call's work, copied to `LayoutTree.lastNativeLayoutWork` when the
    /// entry point returns (ruling SA-M).
    var work = NativeLayoutWork()

    /// The deepest native recursion `enter` allows, in native NODES (ruling
    /// SA-L). **Its own constant, not `LayoutContext.maxDepth`**: the engines'
    /// per-level stack costs differ, and they count different units.
    ///
    /// **Chosen by legacy's safety fraction, not legacy's number.** Legacy took
    /// 64 = 0.60 of its 107-level debug ceiling on a 1 MB thread. Native takes
    /// the largest multiple of 8 not above 0.60 of the SMALLEST native debug
    /// ceiling on a 1 MB thread: 0.60 × 151 = 90.6, so **88**.
    ///
    /// Ceilings, bisected 2026-09-14 on this lane's own build (debug, a
    /// `Thread` with a 1 MB stack, one `swift test --skip-build` per candidate
    /// depth between 50 and 600, each boundary re-confirmed; the first failing
    /// depth dies with no summary line and the same depth completes on a 4 MB
    /// thread), N nested one-child nodes over a leaf through
    /// `computeNativeLayout`:
    ///
    /// | kind | last depth that completes | first that dies | ≈ per level |
    /// |---|---|---|---|
    /// | padding | 169 | 170 | 6.1 KB |
    /// | frame (fixed 100×100) | 168 | 169 | 6.1 KB |
    /// | one-child vertical `linearStack` | **151** | 152 | 6.8 KB |
    /// | custom `ProposalLayout`, measuring and placing through the proxy | 156 | 157 | 6.6 KB |
    ///
    /// The design's pass, before the run object carried the guard, the
    /// checkpoints and the counters, measured padding and frame at 193 and the
    /// stack at 171 (so 96); every kind lost 17–25 levels to this lane's own
    /// per-frame cost, which is why the number was re-bisected rather than
    /// carried. Legacy's figure for comparison: 107 (≈9.8 KB, carried from
    /// `LayoutContext.maxDepth`). **Release is unmeasured.**
    ///
    /// **Re-taken 2026-09-17 by the grids track (lane 1, ruling GR-M)**, same
    /// method, `/usr/bin/swift` 6.4 debug, laid out at 400×400 (a grid at
    /// nil×nil, its only lane-1 branch); record §22:
    ///
    /// | kind | at `cb2e708` | with lane 1's `.grid` case |
    /// |---|---|---|
    /// | padding | 197 / 198 | 194 / 195 |
    /// | one-child vertical `linearStack` | **128 / 129** | **127 / 128** |
    /// | one-cell grid (nil×nil) | — | 170 / 171 |
    ///
    /// **The stack's ceiling no longer supports 88**: 0.60 × 127 = 76.2, so
    /// `SA-L`'s rule gives 72. It had already moved at `cb2e708` (128), before
    /// any grid code, so the drop from 151 predates this track; 88 is unchanged
    /// here and the finding is left to `LR-Q`'s stage 6b re-bisection. The
    /// grid's first two implementations measured 110 and 117 (a solver frame
    /// and `Array.map` on the recursion path); lane 1 measures a nil grid's
    /// cells directly in `LayoutTree.measureGrid`.
    ///
    /// **Re-taken by grids lane 2** (same method; first failing depth completes
    /// on 4 MB): one-cell grid at 400×400 (the finite solve) **155 / 156**, at
    /// nil×nil 167 / 168; stack 127 / 128 and padding 194 / 195, unchanged. A
    /// first finite solve that called its measure closure from inside its group
    /// loop read 65 / 66; `NativeGridSolver` is inverted (it asks, the tree
    /// measures) for that reason. Both grid ceilings clear `GR-M`'s gate of 147.
    ///
    /// **Re-taken by grids lane 3**, which re-bisected the PLACEMENT path
    /// (`GR-AC` item 4): lanes 1 and 2 bisected chains of ONE-cell grids, whose
    /// slot always equals the cell's answer, so `nativeGridCellRects`' fresh
    /// measurement never ran on the measured stack. A chain of two-cell rows
    /// whose inner cell's slot differs from its answer at **every** level (the
    /// row one point taller than the inner grid) completes **154** levels and
    /// dies at 155 — the same before and after lane 3's code, and 155 completes
    /// on a 4 MB thread, so it is a stack ceiling and not a logic failure. It
    /// clears the gate of 147 by seven levels, so `placeGrid` keeps its shape
    /// (the solver loop and `nativeGridCellRects`' `map`) and is not routed
    /// through `measureGrid(_:atAProposal:)`. Same run: one-cell grid at nil×nil
    /// 167 / 168 (unchanged), at 400×400 **154 / 155** (155 / 156 in lane 2, one
    /// level for lane 3's locals), stack 127 / 128 and padding 194 / 195,
    /// unchanged.
    ///
    /// **No parity with legacy is claimed.** One legacy level ported as
    /// `.padding(…).frame(width:)` is at least three native levels, so a
    /// ported tree near legacy's 64 can exceed 88 native levels and trap where
    /// legacy laid it out; the trap names the node. Raise this only with a
    /// re-bisection. Pinned by `layingOutANativeTreeDeeperThanTheLimitTraps`,
    /// `measuringANativeTreeDeeperThanTheLimitTraps`,
    /// `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps` and
    /// `aNativeTreeAtTheDepthLimitDoesNotTrap`.
    static let maxDepth = 88

    init(tree: LayoutTree) { self.tree = tree }

    /// Enters one native recursion level for `node`; `leave()` on return.
    func enter(_ node: LayoutNodeID) {
        depth += 1
        if depth > deepestLevel { deepestLevel = depth }
        precondition(depth <= NativeLayoutRun.maxDepth,
                     "native layout recursion exceeded \(NativeLayoutRun.maxDepth) levels at node \(node) (SA-L)")
    }

    func leave() { depth -= 1 }

    /// Every subview-proxy member calls this first, so a proxy that escaped
    /// its call traps with attribution instead of measuring a finished run.
    func requireActive() {
        precondition(isActive, "a layout subview outlived its layout run")
    }
}

/// One cache entry's key: a node at one proposal. Proposal equality is
/// `ProposedSize`'s synthesized `Hashable` (ruling SA-H's clause 3).
struct NativeMeasurementKey: Hashable {
    let id: LayoutNodeID
    let proposal: ProposedSize
}

/// The work one native layout call did (ruling SA-M): a test observable,
/// read through `LayoutTree.lastNativeLayoutWork`.
///
/// `cacheMisses >= measureCalls` always; the difference is built-in node
/// bodies, which run no user code.
struct NativeLayoutWork: Equatable {
    /// Leaf-closure and custom `sizeThatFits` invocations: user code, where a
    /// text leaf shapes.
    var measureCalls = 0
    /// Lookups that found their `(node, proposal)` key.
    var cacheHits = 0
    /// Measurement bodies run, every node kind.
    var cacheMisses = 0
}
