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

    /// Deeper than any real UI, and shallower than the **main thread's** stack.
    /// A tree legitimately this deep is a bug in the caller, not a limit worth
    /// raising.
    ///
    /// **Not shallower than every stack, which is what "the stack can take"
    /// said here until it was measured.** On a Swift Testing exit-test task,
    /// `computeLayout` over 150 nested nodes finishes and over 200 dies with
    /// SIGBUS: the `placeNode` -> `positionItems` recursion exhausts a task's
    /// stack long before depth 256, so on that stack this guard never fires and
    /// the crash it exists to attribute happens anyway. Layout runs on the main
    /// thread in production (`Frame`, `@MainActor`), which has 8 MB and reaches
    /// the limit — but the claim is about a stack, not about all of them.
    ///
    /// That is why `placeNodeConsultsTheDepthGuard` enters this context by hand
    /// and then calls `placeNode` once, rather than laying out a deep tree: the
    /// deep-tree version of that test passes with the guard's call site
    /// **deleted**, because the stack kills the subprocess either way.
    static let maxDepth = 256

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
