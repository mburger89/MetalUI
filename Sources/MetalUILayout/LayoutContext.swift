/// Per-run layout state: the memo cache (Task 3) and the values every level of
/// the recursion needs.
///
/// **A `final class`, not a `struct`, and that is load-bearing.** A struct
/// threaded by value gives every recursion level its own copy of the cache, so
/// nothing is ever shared, every lookup misses, and the engine stays *correct*
/// while doing exponential work. The only guard that can see that failure is
/// `theCacheIsActuallyConsulted` in Task 3.
///
/// It is created in `computeLayout` and dies with it. It deliberately does not
/// live on `LayoutTree`: the tree is storage, and a cache outliving a run is the
/// stale-data shape ruling C-3 spent a milestone closing.
final class LayoutContext {
    let rootFontSize: Double

    /// How deep the recursion currently is. `LayoutTree.newNode` accepts
    /// arbitrary child ids, so a cycle is constructible and would otherwise
    /// recurse until the stack dies with no attribution.
    private(set) var depth: Int = 0

    /// Deeper than any real UI, and shallow enough that the **guard fires
    /// before the stack runs out** — on every stack this engine has been
    /// measured on, not just the roomiest one.
    ///
    /// **It was 256, and 256 is past most of the stacks this code runs on.**
    /// Measured here by bisection, raising this constant out of the way and
    /// laying out N nested nodes on a Swift Testing exit-test task: **196
    /// levels lay out, 197 dies with SIGBUS.** Review measured the same shape
    /// on two other stacks — an explicit 256 KB thread gives out around 110,
    /// and the main thread's 8 MB does reach 256 and trap properly. So at 256
    /// the guard fired on the main thread alone, and everywhere else the
    /// `placeNode` -> `positionItems` recursion exhausted the stack first: the
    /// exact crash this exists to attribute, happening unattributed.
    ///
    /// **The boundary is a frame-size measurement, not a constant**, which is
    /// the reason for the margin rather than for a number just under it. It
    /// moves whenever a frame in that cycle grows, and Task 4's measurement
    /// recursion adds frames per level; 64 clears the 256 KB ceiling with room
    /// for that.
    ///
    /// The number is not a matter of taste and must not be raised without
    /// re-measuring: `layingOutATreeDeeperThanTheLimitTraps` lays out
    /// `maxDepth + 1` **real** nested nodes and asserts the guard's own message
    /// on stderr. It is green at 64 and red at 256 — the stack wins there and
    /// the message never appears — so a future change to this constant is a
    /// measurement rather than a claim.
    static let maxDepth = 64

    init(rootFontSize: Double) {
        self.rootFontSize = rootFontSize
    }

    func enter(_ node: LayoutNodeID) {
        depth += 1
        precondition(depth <= LayoutContext.maxDepth,
                     "layout recursion exceeded \(LayoutContext.maxDepth) levels at node \(node) — the child lists contain a cycle")
    }

    func leave() {
        depth -= 1
    }

    /// A measurement query.
    ///
    /// **Not every field has the same equality.** `knownWidth`, `knownHeight`
    /// and `containingBlockWidth` are hashed and compared by `bitPattern`: a
    /// near-miss on floating-point equality costs a recompute and never a
    /// wrong answer, which is the right direction for those three to fail.
    /// `availableWidth`/`availableHeight` are `AvailableSpace`, whose
    /// `Hashable` is the compiler-synthesized one over its `.definite(Double)`
    /// case — ordinary IEEE equality, not `bitPattern`: `definite(0.0)` and
    /// `definite(-0.0)` collide there and `definite(.nan)` does not collide
    /// with itself. Harmless today (nothing feeds `-0` or `NaN` into an
    /// `AvailableSpace`), but it is a real difference from the other three
    /// fields, not a paraphrase of it.
    ///
    /// **`containingBlockWidth` is here because dropping it once made a cache
    /// hit return a wrong answer, not a recompute.** `measureNode` passes it
    /// straight to `layOutChildren`, where it is the basis for the
    /// container's own percentage padding/border and so changes the border
    /// box `measureNode` returns — the same node measured once with an
    /// indefinite containing block (a parent's speculative measure) and once
    /// with a definite one (real placement) must not share an entry. Guarded
    /// by `aCacheHitRespectsTheContainingBlockWidth`.
    ///
    /// **The intrinsic query needs no field of its own**, and that is a
    /// derivation rather than an oversight: `IntrinsicQuery(known:available:)`
    /// is a pure function of `known` and `available`, both of which are already
    /// here in full — `availableWidth`/`availableHeight` keep `.minContent` and
    /// `.maxContent` as distinct cases rather than collapsing them the way
    /// `definiteExtent` does. Two calls that differ only in their query
    /// therefore differ in this key already. Adding a field would be redundant
    /// today and would go stale the moment the query stops being derived that
    /// way, so the rule for whoever changes that constructor is: if it ever
    /// reads anything not in this key, it belongs in this key.
    struct MeasureKey: Hashable {
        var node: LayoutNodeID
        var knownWidth: Double?
        var knownHeight: Double?
        var availableWidth: AvailableSpace
        var availableHeight: AvailableSpace
        var containingBlockWidth: Double?

        static func == (l: MeasureKey, r: MeasureKey) -> Bool {
            l.node == r.node
                && l.knownWidth?.bitPattern == r.knownWidth?.bitPattern
                && l.knownHeight?.bitPattern == r.knownHeight?.bitPattern
                && l.availableWidth == r.availableWidth
                && l.availableHeight == r.availableHeight
                && l.containingBlockWidth?.bitPattern == r.containingBlockWidth?.bitPattern
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(node)
            hasher.combine(knownWidth?.bitPattern)
            hasher.combine(knownHeight?.bitPattern)
            hasher.combine(availableWidth)
            hasher.combine(availableHeight)
            hasher.combine(containingBlockWidth?.bitPattern)
        }
    }

    private var memo: [MeasureKey: SizeD] = [:]

    /// Cache observability. **Test-only in intent and the only way to see that
    /// the cache is a cache** — a `storeMeasure` that never stores leaves every
    /// behavioural test green. Pinned by `theCacheIsActuallyConsulted`.
    private(set) var hits = 0
    private(set) var misses = 0

    func cachedMeasure(_ key: MeasureKey) -> SizeD? {
        if let v = memo[key] { hits += 1; return v }
        misses += 1
        return nil
    }

    func storeMeasure(_ key: MeasureKey, _ size: SizeD) { memo[key] = size }
}
