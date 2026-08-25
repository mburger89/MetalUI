import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: a single
/// line, fixed sizes, flex-start packing. Grow/shrink, alignment, wrapping and
/// absolute positioning arrive in later tasks, each with its own fixtures.
///
/// **Reverse directions are NOT implemented.** `FlexDirection` offers
/// `.rowReverse` and `.columnReverse`, and `FlexDirection.isReverse` exists, but
/// `layoutContainer` keys only on `isRow`. A `.rowReverse` container therefore
/// lays out silently as `.row` — wrong geometry, no error, no diagnostic. It is
/// listed here because that is the whole mitigation until the alignment task
/// implements it: nothing else in the code says so.
///
/// **The box model is NOT implemented either.** `margin`, `padding`, `border`
/// and `inset` are live `Style` properties, and `resolveEdges` resolves all four
/// edges and is unit-tested, but nothing in this file ever calls it. A root with
/// `width: 300, padding: 20, border: 5` therefore places its 50x50 child at
/// `(0, 0)`, where CSS puts it at `(25, 25)`: child origins are never inset by
/// the parent's padding and border, and the space offered to children is never
/// reduced by them. This is a conspicuous gap rather than a minor one, because
/// `border-box` sizing is the spec's headline sizing constraint (§5.2) — every
/// size here already *claims* to include padding and border, while no code yet
/// subtracts them to find the content box. Like reverse, it fails silently:
/// wrong geometry, no error, no diagnostic, until the box-model work wires
/// `resolveEdges` into `layoutContainer`.
///
/// Every rect written here is **absolute to the root**, not relative to its
/// parent. `roundLayout` keeps no cross-rect state, so its no-drift guarantee
/// depends entirely on receiving absolute coordinates; storing parent-relative
/// ones would silently reintroduce the accumulated error it exists to prevent.
public func computeLayout(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double = 16
) {
    let rootSize = resolveRootSize(tree, root, available: available, rootFontSize: rootFontSize)
    tree.setLayout(root, LayoutRect(x: 0, y: 0, width: rootSize.width, height: rootSize.height))
    layoutContainer(tree, root, containerOrigin: (0, 0), containerSize: rootSize,
                    rootFontSize: rootFontSize)

    // Round last, over the finished absolute rects. Spec §5.7 designates the
    // rounded layout as the comparison space, so the engine must apply the same
    // pass the golden generator does — otherwise a fractional layout is compared
    // against a rounded one and the difference is invisible.
    roundStoredRects(tree, root)
}

/// Apply `roundLayout` to every node's stored rect, depth-first.
///
/// `roundLayout` is stateless per rect — it rounds each rect's own cumulative
/// edges — so applying it node-by-node is equivalent to applying it to the whole
/// tree at once, and requires no traversal order.
private func roundStoredRects(_ tree: LayoutTree, _ node: LayoutNodeID) {
    tree.setLayout(node, roundLayout([tree.layout(node)])[0])
    for kid in tree.children(node) {
        roundStoredRects(tree, kid)
    }
}

/// One flex item, carried through the three phases of a line's layout.
///
/// Split out because §9.7 resolves free space across the *whole* line before any
/// item is positioned — a single loop that sizes and places as it goes cannot
/// express that.
///
/// **Partially written but unread, today:** `collectItems` now computes
/// `baseSize` via §9.2's `flexBaseSize(_:)` and clamps it into
/// `hypotheticalMainSize`, but `positionItems` still only ever reads
/// `targetMainSize` and `crossSize`. `hypotheticalMainSize` is read exactly
/// once — to seed `targetMainSize` — and `baseSize` itself is not read by
/// anything downstream of `collectItems` yet. Both light up fully when Task 3
/// implements the §9.7 freeze loop, which also starts reading `frozen` (still
/// always `false`, still unread) to stop revisiting an item once its size is
/// final. Until then, `targetMainSize` is seeded from `hypotheticalMainSize`
/// and never changed, so the two are numerically identical — do not read that
/// as `hypotheticalMainSize` being redundant; it is the value Task 3 diffs
/// against to find free space to distribute.
struct FlexItem {
    let node: LayoutNodeID
    /// §9.2 flex base size, before min/max clamping. Computed by
    /// `collectItems`; not read again until Task 3's freeze loop.
    var baseSize: Double
    /// §9.2 base size clamped by min/max. Read once, to seed
    /// `targetMainSize`; the freeze loop's growth/shrinkage is Task 3.
    var hypotheticalMainSize: Double
    /// The size after §9.7 distributes free space. Starts at hypothetical.
    var targetMainSize: Double
    var crossSize: Double
    /// §9.7 freezes an item once its size is final. Always `false`, and
    /// unread, until Task 3 implements the freeze loop.
    var frozen: Bool
}

/// Resolve the **root's** own border-box size from its style, falling back to
/// the offered `available` space on any axis its style leaves unresolved.
///
/// This fallback belongs to the root alone (ruling F-1). The root is a block
/// box in the initial containing block, and CSS §10.3.4/§9.2's block-layout
/// rule is that `width: auto` (and, per this framework's single-pass sizing,
/// `height: auto`) on such a box fills the space the box is offered — that is
/// what `computeLayout`'s public `available:` parameter is *for*. A flex
/// item's `auto` main size means something else entirely: it is resolved via
/// §9.2's flex base size (Task 2) and never by inheriting a container's
/// extent, which is why `resolveNodeSize` below must not fall back to
/// `available` — doing so would silently reintroduce the Task 7 scope-boundary
/// fallback this task deletes from item sizing.
private func resolveRootSize(
    _ tree: LayoutTree,
    _ root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(root)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              availableExtent: AvailableSpace) -> Double {
        // The root has no parent, so percentages resolve against nil (CSS
        // treats that as auto) — same as the `.unspecified` parent this
        // function used before the split.
        let resolved = resolveDimension(dim, against: nil, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: nil, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: nil, rootFontSize: rootFontSize)
        let base: Double
        if let resolved {
            base = resolved
        } else if case .definite(let d) = availableExtent {
            base = d
        } else {
            base = 0
        }
        return clamp(base, min: lower, max: upper)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width,
                    availableExtent: available.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height,
                     availableExtent: available.height))
}

/// Resolve a node's own border-box size from its style.
///
/// This is for nodes whose size comes from their own style alone — a flex
/// item's **cross** axis, and any node reached from `collectItems`. Since
/// Task 2, `collectItems` gets an item's main axis from `flexBaseSize(_:)`
/// instead, so this function never touches a flex item's main axis at all;
/// `collectItems` still calls it for the item's full `SizeD` and reads only
/// the cross component out of it. It must never grow a `flexBasis` branch of
/// its own to reach into the main axis anyway — ruling PF-3
/// (`docs/superpowers/2026-08-25-m1a-decisions.md`) named exactly that
/// shortcut as the failure mode: an auto-sized item quietly inheriting a
/// fallback that was only ever meant to be temporary. That is also why,
/// unlike `resolveRootSize`, this function never falls back to an offered
/// available extent — an axis it cannot resolve from the node's own style is
/// 0, on both the cross axis here and the (unused) main axis.
private func resolveNodeSize(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    parent: OptionalSizeD,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              parentExtent: Double?) -> Double {
        let resolved = resolveDimension(dim, against: parentExtent, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: parentExtent, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: parentExtent, rootFontSize: rootFontSize)
        // An unresolvable size is 0 here. On a flex item's main axis this
        // result is computed but discarded — §9.2's flex base size supplies
        // that axis instead.
        return clamp(resolved ?? 0, min: lower, max: upper)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width, parentExtent: parent.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height, parentExtent: parent.height))
}

/// Lay out one container: collect its items, resolve flexible lengths, position.
private func layoutContainer(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let items = collectItems(tree, container, containerSize: containerSize,
                             rootFontSize: rootFontSize)
    guard !items.isEmpty else { return }
    // §9.7 lands here in Task 3. Until then every item keeps its hypothetical
    // main size, which is what the pre-split code did.
    positionItems(tree, container, items: items, containerOrigin: containerOrigin,
                  containerSize: containerSize, rootFontSize: rootFontSize)
}

/// Phase 1 — size every item without positioning any of them.
private func collectItems(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerSize: SizeD,
    rootFontSize: Double
) -> [FlexItem] {
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    let parent = OptionalSizeD(width: containerSize.width, height: containerSize.height)

    return tree.children(container)
        .filter { tree.style($0).display != .none }
        .map { kid in
            let base = flexBaseSize(tree, item: kid, isRow: isRow,
                                    containerMain: containerMain,
                                    containerCross: containerCross,
                                    rootFontSize: rootFontSize)

            let ks = tree.style(kid)
            let minMain = resolveDimension(isRow ? ks.minSize.width : ks.minSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let maxMain = resolveDimension(isRow ? ks.maxSize.width : ks.maxSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let hypothetical = clamp(base, min: minMain, max: maxMain)

            // Cross size still comes from the item's own style. Stretch and
            // content-based cross sizing arrive with the alignment work.
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
            let cross = isRow ? own.height : own.width

            return FlexItem(node: kid, baseSize: base, hypotheticalMainSize: hypothetical,
                            targetMainSize: hypothetical, crossSize: cross, frozen: false)
        }
}

/// Phase 3 — assign absolute rects and recurse.
private func positionItems(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: [FlexItem],
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: isRow ? containerSize.width : containerSize.height,
                            rootFontSize: rootFontSize) ?? 0

    var cursor: Double = 0
    for (index, item) in items.enumerated() {
        // Between items only. A trailing gap is invisible today because `cursor`
        // dies with the loop, but `justify-content` will read the final cursor as
        // the line's content size, where it is a real off-by-`gap` bug.
        if index > 0 { cursor += gap }

        let x = containerOrigin.0 + (isRow ? cursor : 0)
        let y = containerOrigin.1 + (isRow ? 0 : cursor)
        let size = isRow
            ? SizeD(width: item.targetMainSize, height: item.crossSize)
            : SizeD(width: item.crossSize, height: item.targetMainSize)

        tree.setLayout(item.node, LayoutRect(x: x, y: y, width: size.width, height: size.height))
        layoutContainer(tree, item.node, containerOrigin: (x, y), containerSize: size,
                        rootFontSize: rootFontSize)

        cursor += item.targetMainSize
    }
}
