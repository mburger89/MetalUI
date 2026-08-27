import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }

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

/// Different queries must not share an entry. A key that ignored `available`
/// would pass every other test here.
///
/// **Deviates from the task-3 brief, which wrapped this leaf in a row
/// container.** That version measures 90 for both `narrow` and `wide`, not
/// because the cache shares an entry, but because of the carried-risk gap
/// already on record in `docs/superpowers/2026-08-26-content-sizing-decisions.md`:
/// "`measureNode` cannot tell `.minContent` from `.maxContent` for a
/// container." `FlexBaseSize.swift`'s content-size branch (line ~50) queries
/// a row's content child at a hardcoded `.maxContent` regardless of the
/// container's own query, so the *first, uncached* computation already
/// returns 90 either way — confirmed by running the brief's version verbatim
/// before this edit. Fixing that composition would be a layout-behaviour
/// change, which this task's gate forbids. Querying the leaf directly still
/// fully exercises `MeasureKey.availableWidth`: dropping it from the key (Step
/// 7's mutation 2) makes `wide` read back `narrow`'s cached 30 instead of
/// computing 90, reddening the second assertion below.
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
