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
    /// the largest multiple of 8 not above 0.60 of the SMALLEST native **debug**
    /// ceiling on a 1 MB thread (the iOS main thread the spec targets):
    /// 0.60 × 127 = 76.2, so **72** (plan task 7, stage 6b, ruling `LR-DK`; it was
    /// 88 = 0.60 × 151 from 2026-09-14 until then).
    ///
    /// **Re-bisected in debug and — for the first time — release by stage 6b**
    /// (`LR-Q` item 3; record §39 §5; `docs/probes/native-depth-ceiling/bisect.sh`
    /// at `aef88ce`, a chain of N one-child nodes of each kind over a leaf laid out
    /// at 400×400 through `computeNativeLayout` on a 1 MB `Thread`, the guard raised
    /// out of the way, one process per depth, each boundary re-confirmed; positive
    /// control `padding 10` completes and `padding 2000000` dies in both
    /// configurations):
    ///
    /// | kind | debug last / first that dies | release last / first that dies |
    /// |---|---|---|
    /// | padding | 194 / 195 | 1256 / 1257 |
    /// | fixed frame 100×100 | 194 / 195 | 1256 / 1257 |
    /// | flexible frame, 0…∞ both axes | 194 / 195 | 1256 / 1257 |
    /// | one-child vertical `linearStack` | **127 / 128** | **653 / 654** |
    /// | one-child horizontal `linearStack` | 127 / 128 | 653 / 654 |
    /// | overlay | 169 / 170 | 1256 / 1257 |
    /// | custom `ProposalLayout`, measuring and placing its child | 178 / 179 | 1037 / 1038 |
    /// | scroll viewport (vertical) | 194 / 195 | 1256 / 1257 |
    /// | two-cell grid row (the placement path, `GR-AK`) | 155 / 156 | 1256 / 1257 |
    ///
    /// **Debug governs**: `precondition` is live in `-O`, so the guard fires in
    /// release at the same 72, and release's smallest ceiling (653, the stacks) is
    /// nine times it — headroom, not a second rule. 72 / 127 = 0.57 in debug.
    ///
    /// **Superseded tables, kept as history.** The 2026-09-14 bisection (this
    /// lane's own build then, debug, 1 MB) read padding 169 / 170, frame 168 / 169,
    /// the vertical stack **151 / 152** and a custom layout 156 / 157 — which gave
    /// 88. The grids track (2026-09-17, `GR-M`, `GR-AC`; record §22) re-read the
    /// stack at 128 / 129 at `cb2e708` and 127 / 128 with its `.grid` case, padding
    /// 197 / 198 then 194 / 195, a one-cell grid 170 / 171 (nil×nil) and 155 / 156
    /// (400×400), and a two-cell row's placement path 154 / 155; it recorded that
    /// 127 no longer supported 88 and left the finding to `LR-Q`'s stage 6b
    /// re-bisection, which this is. The drop from 151 predates the grids track
    /// (it had moved at `cb2e708`, before any grid code).
    ///
    /// **Production roots sit far below it** (record §39 §5, measured through a
    /// `Window` at `aef88ce` with the default flipped): the demo's deepest native
    /// level is 29 (modal off, on, and animating), the proposal preview 10, a
    /// `ScrollView { List }` root 15 — read through `LayoutTree
    /// .lastNativeLayoutDeepestLevel`, which records this run's maximum `depth`.
    ///
    /// **No parity with legacy is claimed.** One legacy level ported as
    /// `.padding(…).frame(width:)` is at least three native levels, and a padded,
    /// sized legacy `Box` with a margin and a stretch lowers to five, so a ported
    /// tree near legacy's 64 can exceed 72 native levels and trap where legacy laid
    /// it out; the trap names the node. Raise this only with a re-bisection. Pinned
    /// by `layingOutANativeTreeDeeperThanTheLimitTraps`,
    /// `measuringANativeTreeDeeperThanTheLimitTraps`,
    /// `aPlacementOnlyChainOfCustomLayoutsDeeperThanTheLimitTraps` and
    /// `aNativeTreeAtTheDepthLimitDoesNotTrap` (arithmetic on this constant), and by
    /// eight literal boundary tests re-derived by hand for 72: `aChainOf72GridsTraps`
    /// / `aChainOf71GridsDoesNotTrap`, `aLoweredChainAtTheNativeDepthLimitLaysOut` /
    /// `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` (24 / 25 padded boxes,
    /// 72 / 75 levels), and the three- and four-wrapper item chains of
    /// `LoweringPipelineParityTests` (2.14) and `LoweringBoxModelTests` (4.8), each
    /// 72 / 73.
    static let maxDepth = 72

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
