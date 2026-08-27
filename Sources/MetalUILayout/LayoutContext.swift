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
}
