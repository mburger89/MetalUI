import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pctL(_ f: Float) -> Length { .percent(f) }

private func nestedTree() -> (LayoutTree, LayoutNodeID) {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(30), height: px(10))
    var row = Style()
    row.flexDirection = .row
    var node = tree.newNode(style: kid, children: [])
    for _ in 0..<4 {
        node = tree.newNode(style: row, children: [node, tree.newNode(style: kid, children: [])])
    }
    return (tree, node)
}

/// **The only test that can see whether the cache is a cache.** A `storeMeasure`
/// that never stores, or a `cachedMeasure` that always returns nil, leaves every
/// other test in this repo green and the engine exponentially slow.
///
/// **What this actually pins today: one entry, not depth-scaling.** Measured
/// on `nestedTree()` (depth 4): the first call is `misses = 1, hits = 0`, the
/// second is `hits = 1` and no new miss. `measureNode` does not re-enter
/// itself yet — nothing in `Sources/` calls it recursively until the four
/// constant-substituting sites (CLAUDE.md's inert-API table) are wired, which
/// is Task 4's job, not this one's. So the cache holds exactly one entry per
/// top-level call, and the "roughly 700x at depth 6" cost this task exists to
/// avoid is not yet defended by any assertion here — it will need its own,
/// once Task 4 makes the recursion real.
@Test func theCacheIsActuallyConsulted() {
    let (tree, root) = nestedTree()
    let ctx = LayoutContext(rootFontSize: 16)
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    _ = measureNode(ctx, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let firstMisses = ctx.misses
    _ = measureNode(ctx, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)

    #expect(ctx.hits > 0)
    // The second identical query must add no misses at all.
    #expect(ctx.misses == firstMisses)
}

/// **The leaf branch, not just the container branch.** `theCacheIsActuallyConsulted`
/// above measures a container root, so a `storeMeasure` deleted from only
/// `measureNode`'s leaf branch (the one `tree.measure(node)` takes) left the
/// whole 326-test suite green — measured directly, and the composed-tree
/// tests never repeat an identical query against the same leaf. That branch
/// is the one that matters most once M2's text leaves make measurement
/// expensive, so it gets its own direct witness: a leaf queried twice with an
/// identical key must record a hit the second time.
@Test func aRepeatedLeafQueryIsCached() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, _ in SizeD(width: 40, height: 20) }
    let ctx = LayoutContext(rootFontSize: 16)
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    _ = measureNode(ctx, tree, leaf, known: .unspecified, available: q, containingBlockWidth: nil)
    #expect(ctx.hits == 0)
    _ = measureNode(ctx, tree, leaf, known: .unspecified, available: q, containingBlockWidth: nil)

    #expect(ctx.hits == 1)
    #expect(ctx.misses == 1)
}

/// A cached answer must equal the uncached one. Guards a key that collides.
@Test func aCachedAnswerMatchesAFreshOne() {
    let (tree, root) = nestedTree()
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    let warm = LayoutContext(rootFontSize: 16)
    _ = measureNode(warm, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let second = measureNode(warm, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)

    let cold = LayoutContext(rootFontSize: 16)
    let fresh = measureNode(cold, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    #expect(second == fresh)
}

/// **A cache hit must respect `containingBlockWidth`, not just `available`.**
/// `measureNode` passes it straight to `layOutChildren`, where it is the basis
/// for the container's own percentage padding/border and so changes the
/// border box `measureNode` returns — the field `MeasureKey` omitted until a
/// reviewer measured a stale hit on this branch: a container with `10%`
/// padding on all four edges (which CLAUDE.md's rule resolves against the
/// containing block's WIDTH on every edge, vertical included) measured at
/// `containingBlockWidth: 100` and then, in the SAME context, at `400` must
/// not read back the `100`-basis answer.
@Test func aCacheHitRespectsTheContainingBlockWidth() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(200), height: px(200))
    let child = tree.newNode(style: kid, children: [])

    var root = Style()
    root.flexDirection = .row
    root.padding = Edges(top: pctL(0.1), right: pctL(0.1), bottom: pctL(0.1), left: pctL(0.1))
    let container = tree.newNode(style: root, children: [child])

    let ctx = LayoutContext(rootFontSize: 16)
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)

    let narrow = measureNode(ctx, tree, container, known: .unspecified,
                             available: q, containingBlockWidth: 100)
    let wideCached = measureNode(ctx, tree, container, known: .unspecified,
                                 available: q, containingBlockWidth: 400)

    let fresh = LayoutContext(rootFontSize: 16)
    let wideFresh = measureNode(fresh, tree, container, known: .unspecified,
                                available: q, containingBlockWidth: 400)

    #expect(narrow == SizeD(width: 220, height: 220))
    #expect(wideFresh == SizeD(width: 280, height: 280))
    // The bug this guards: without `containingBlockWidth` in the key, `wideCached`
    // reads back `narrow`'s stale 220x220 instead of recomputing 280x280.
    #expect(wideCached == wideFresh)
}

/// Different queries must not share an entry. A key that ignored `available`
/// would pass every other test here.
///
/// **Deviates from the task's original brief, which wrapped this leaf in a
/// row container and measured the container** — and the reason it deviated has
/// since expired. The paragraph here used to say that the container form
/// "measures 90 for both", that `definiteExtent` was the PRIMARY barrier, that
/// "changing that one literal alone would fix nothing", and that fixing the
/// composition "would be a layout-behaviour change, which this task's gate
/// forbids". All four were true when written and the intrinsic-query task made
/// them false; it did not open this file, which is why they survived it. That
/// is taxonomy shape 10 — a prediction about measurement dressed as a fact
/// about the code — and it is the third instance on this branch, so the
/// correction is kept rather than deleted.
///
/// **Measured now**, container form, one `LayoutContext`, queried
/// min → max → min: **30, 90, 30, with `hits = 1` and `misses = 2`.** The
/// container form would therefore work as this test.
///
/// It is still not what this test uses, for a reason that did not expire:
/// querying the **leaf** directly is the shortest thing that can fail for the
/// key's own reason. The container form routes the same distinction through
/// `flexBaseSize`, so it reddens for a propagation bug as readily as for a key
/// bug — `IntrinsicModeTests.swift` is where propagation is pinned, and this
/// file is about `MeasureKey`. Dropping `availableWidth` from the key makes
/// `wide` read back `narrow`'s cached 30 instead of computing 90, reddening
/// the second assertion below.
@Test func minContentAndMaxContentDoNotShareACacheEntry() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }

    let ctx = LayoutContext(rootFontSize: 16)
    let narrow = measureNode(ctx, tree, leaf, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(ctx, tree, leaf, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow.width == 30)
    #expect(wide.width == 90)
}

/// A new run starts cold. The cache must not outlive its `LayoutContext` —
/// the stale-data shape ruling C-3 closed for `LayoutNodeID`.
@Test func eachRunStartsWithAnEmptyCache() {
    let (tree, root) = nestedTree()
    let q = AvailableSpaceSize(width: .maxContent, height: .maxContent)
    let first = LayoutContext(rootFontSize: 16)
    _ = measureNode(first, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    let second = LayoutContext(rootFontSize: 16)
    #expect(second.hits == 0)
    #expect(second.misses == 0)
    _ = measureNode(second, tree, root, known: .unspecified, available: q, containingBlockWidth: nil)
    #expect(second.misses > 0)
}
