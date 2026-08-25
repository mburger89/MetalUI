import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: a single
/// line, §9.2 flex base sizes, §9.7 grow/shrink, flex-start packing. Alignment,
/// wrapping and absolute positioning arrive in later tasks, each with its own
/// fixtures.
///
/// **Alignment is NOT implemented**, and that is visible in every browser
/// comparison: `collectItems` takes an item's cross size from the item's own
/// style, so an item with no explicit cross size is 0 where CSS's default
/// `align-items: stretch` gives it the container's extent. The freeze-loop
/// golden comparisons in `FreezeLoopTests` therefore compare the main axis
/// only, and say so at the assertion helper.
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
/// **Every field is now read.** Earlier milestones carried `baseSize`,
/// `hypotheticalMainSize` and `frozen` as write-only placeholders; the §9.7
/// freeze loop in `ResolveFlexibleLengths.swift` reads all three, and
/// `positionItems` reads `targetMainSize` and `crossSize`. Verify rather than
/// trust this — `grep -rn "hypotheticalMainSize" Sources/` — and if a field
/// ever goes back to being written and never read, say so here: silence at a
/// declaration reads as "consumed".
///
/// That is a claim about the **fields**, and one of the *writes* at
/// construction is nonetheless dead: the value `collectItems` gives
/// `targetMainSize` is never read. See that field's own comment.
///
/// `hypotheticalMainSize` and `targetMainSize` are no longer numerically
/// identical. They coincide only for an item §9.7.1 froze outright.
struct FlexItem {
    let node: LayoutNodeID
    /// §9.2 flex base size, before min/max clamping. §9.7 distributes free
    /// space *from* this, not from the clamped size, and weights shrink by it.
    var baseSize: Double
    /// §9.2 base size clamped by min/max. §9.7 sums these to decide whether
    /// the line is growing or shrinking, and compares against `baseSize` to
    /// find the items that cannot flex in that direction.
    var hypotheticalMainSize: Double
    /// The item's resolved main-axis floor and ceiling, nil for "unbounded".
    ///
    /// These are carried rather than re-resolved inside §9.7.4.d because
    /// `minMain` is **not** a pure function of the style any more: since the
    /// §4.5 automatic minimum landed, `min-width: auto` resolves through the
    /// item's measure function, and `resolveDimension` alone returns nil for it.
    /// A second, style-only resolution inside the freeze loop would silently
    /// drop every automatic floor — the loop would clamp against nothing and the
    /// rule would apply to `hypotheticalMainSize` only, which is where the base
    /// size already exceeds the floor and the clamp does nothing. One
    /// resolution, one place: `collectItems`.
    var minMain: Double?
    var maxMain: Double?
    /// The size after §9.7 distributes free space — the only size
    /// `positionItems` reads.
    ///
    /// **The value passed here at construction is dead. It is not a seed the
    /// freeze loop refines.** §9.7.2 assigns `targetMainSize` unconditionally
    /// across `items.indices` — every item takes either its hypothetical size
    /// (if frozen) or its base size (if not) — before anything reads the field,
    /// and both guards on the way in (`layoutContainer`'s `!items.isEmpty` and
    /// `resolveFlexibleLengths`' own) return early on an empty line. So no
    /// constructed item can reach `positionItems` without passing through that
    /// loop. Measured rather than reasoned: setting the argument at
    /// `collectItems`' `FlexItem(...)` to `-999` leaves the whole suite green.
    ///
    /// It is kept because Swift requires every stored property initialised and
    /// both alternatives are worse. A default on this declaration would
    /// relocate the same dead write rather than remove it — `-999` would still
    /// be expressible and still green. Splitting `FlexItem` into a pre- and
    /// post-§9.7 pair would delete the write, at the price of moving §9.7.2's
    /// "unfrozen items start at their base size" rule out of the block that
    /// cites the spec for it, into `collectItems`.
    ///
    /// Consequences for anyone editing this file: do not build anything on the
    /// value written at construction, and do not read this field before
    /// `resolveFlexibleLengths` has run.
    var targetMainSize: Double
    /// The item's own style's cross-axis size. **Alignment is not
    /// implemented**, so an item with no explicit cross size is 0 here where a
    /// browser's `align-items: stretch` default would give it the container's
    /// extent.
    var crossSize: Double
    /// §9.7 freezes an item once its size is final, and the loop stops when
    /// every item is frozen.
    var frozen: Bool
}

/// Resolve the **root's** own border-box size from its style, falling back to
/// the offered `available` space on any axis its style leaves unresolved.
///
/// This fallback belongs to the root alone (ruling FS-1). The root is a block
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
/// its own to reach into the main axis anyway — m1a ruling PF-3
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
    var items = collectItems(tree, container, containerSize: containerSize,
                             rootFontSize: rootFontSize)
    guard !items.isEmpty else { return }

    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let containerMain = isRow ? containerSize.width : containerSize.height
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain, rootFontSize: rootFontSize) ?? 0

    resolveFlexibleLengths(tree, items: &items, containerMain: containerMain, gap: gap)

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
            // CSS Sizing §4.5's automatic minimum size. `min-width: auto` on a
            // flex item resolves to the item's **content-based** minimum — its
            // min-content size — not to 0, and emphatically **not** to its flex
            // base size. Taking the base size here is the tempting wrong answer
            // and it disables shrinking entirely: every `flex-basis: 200px` item
            // would acquire a 200px floor and refuse to give up a single pixel.
            // `anItemWithNoContentHasNoAutomaticMinimum` and Task 3's
            // `shrinkIsWeightedByBaseSize` both redden if anyone tries it.
            //
            // An item with no measure function has no content, so its automatic
            // minimum is 0 and it shrinks freely.
            //
            // **This rule is not, and cannot yet be, browser-verified.** WebKit's
            // content size comes from real text; nothing in this framework
            // measures any until the text system lands in M2, and every fixture
            // in the corpus is an empty div — for which the rule is a no-op. So
            // it is pinned only by hand-written tests carrying explicit measure
            // closures (`automaticMinimumSizeUsesContentSizeNotFlexBasis`), and
            // `flex_row_explicit_min` covers **explicit** `min-width` alone.
            // When the text system lands, add a fixture with real content and
            // delete this paragraph.
            //
            // **Ruling F-3 — half the rule is deliberately missing.** §4.5's
            // automatic minimum is `min(specified size suggestion, content size
            // suggestion)`; only the content suggestion is implemented. The
            // specified suggestion (the item's own definite `width`/`height`,
            // when it has one) can never be distinguished from this until
            // something measures content in production, because the two differ
            // only when a measured content size exceeds a specified size. That
            // is M2 work, not an oversight.
            let minDim = isRow ? ks.minSize.width : ks.minSize.height
            let minMain: Double? = {
                if case .auto = minDim {
                    guard let measure = tree.measure(kid) else { return nil }
                    let probe = measure(.unspecified,
                                        AvailableSpaceSize(width: isRow ? .minContent : .maxContent,
                                                           height: isRow ? .maxContent : .minContent))
                    return isRow ? probe.width : probe.height
                }
                // An explicit `min-width` wins outright: it *replaces* the
                // automatic minimum rather than being combined with it, so an
                // item may be told to shrink below what its content needs.
                // Verified against WebKit with a probe fixture: 40 monospace
                // W's (min-content ~384px) inside `min-width: 150px` lays out
                // at exactly 150.
                return resolveDimension(minDim, against: containerMain, rootFontSize: rootFontSize)
            }()
            let maxMain = resolveDimension(isRow ? ks.maxSize.width : ks.maxSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let hypothetical = clamp(base, min: minMain, max: maxMain)

            // Cross size still comes from the item's own style. Stretch and
            // content-based cross sizing arrive with the alignment work.
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
            let cross = isRow ? own.height : own.width

            // `targetMainSize:` here is dead — §9.7.2 overwrites it on every
            // item before it is read, and no empty-line path reaches
            // `positionItems`. It repeats `hypothetical` only because a
            // constructor must pass something; nothing depends on which value.
            // See the field's declaration.
            return FlexItem(node: kid, baseSize: base, hypotheticalMainSize: hypothetical,
                            minMain: minMain, maxMain: maxMain,
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
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain,
                            rootFontSize: rootFontSize) ?? 0

    let content = lineContentSize(items, gap: gap)
    let offsets = distributeMainAxis(s.justifyContent ?? .flexStart,
                                     freeSpace: containerMain - content,
                                     itemCount: items.count)

    var cursor: Double = offsets.leading
    for (index, item) in items.enumerated() {
        // Between items only.
        if index > 0 { cursor += gap + offsets.between }

        // CSS Flexbox §9.6 — the line's cross size is the container's cross
        // extent (single-line only; wrapping would make this the line's own
        // measured cross size instead).
        let align = resolvedAlignment(tree.style(item.node), container: s)
        let crossOffset = crossAxisOffset(align, itemCross: item.crossSize,
                                          lineCross: containerCross)

        let x = containerOrigin.0 + (isRow ? cursor : crossOffset)
        let y = containerOrigin.1 + (isRow ? crossOffset : cursor)
        let size = isRow
            ? SizeD(width: item.targetMainSize, height: item.crossSize)
            : SizeD(width: item.crossSize, height: item.targetMainSize)

        tree.setLayout(item.node, LayoutRect(x: x, y: y, width: size.width, height: size.height))
        layoutContainer(tree, item.node, containerOrigin: (x, y), containerSize: size,
                        rootFontSize: rootFontSize)

        cursor += item.targetMainSize
    }
}
