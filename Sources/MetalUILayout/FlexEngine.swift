import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: a single
/// line, §9.2 flex base sizes, §9.7 grow/shrink, §9.5 justify-content packing,
/// §9.4 cross-axis stretch, §9.6 cross-axis placement, and the box model —
/// `padding` and `border` shrink the content box (`contentBox` below),
/// `margin` sits outside each item's border box (`collectItems`,
/// `positionItems`). Wrapping, `align-content` and absolute positioning arrive
/// in later tasks, each with its own fixtures.
///
/// Two box-model gaps remain and are recorded rather than implied: `inset` is
/// still read by nothing (absolute positioning is its own plan), and
/// `margin: auto` resolves to 0 instead of absorbing free space. Both have
/// rows in CLAUDE.md's inert-API table.
///
/// **Cross-axis `stretch` landed in the alignment task, and with it every golden
/// comparison in the suite is now full-rect.** Twelve of them compared the main
/// axis alone until then, because `collectItems` took an item's cross size from
/// its own style and produced 0 where CSS's default `align-items: stretch` gives
/// the container's extent. Nothing was regenerated when they widened: the
/// committed goldens already held WebKit's stretched answers, which is the
/// evidence the rule is right.
///
/// **Content-based cross sizing is still NOT implemented** — the other half of
/// §9.4. An item that is not stretched (its alignment is `center`, `flex-start`
/// or `flex-end`) and has an `auto` cross size measures 0 here, where CSS gives
/// it its content's cross size. Every fixture in the corpus is an empty div, so
/// no browser comparison can see it; it needs the M2 text system.
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
    // The root's containing block is the space it was offered — ruling FS-1's
    // "the root is a block box in the initial containing block". So the root's
    // own percentage padding and border resolve against `available.width`, NOT
    // against the root's resolved width: a 400-wide root inside an 800-wide
    // viewport has `padding: 10%` of 800. Indefinite offered width means an
    // indefinite containing block, and percentage edges then resolve to 0.
    //
    // `resolveRootSize` above still resolves the root's own `width: 50%`
    // against nil rather than against this same extent — a separate, narrower
    // divergence, recorded in CLAUDE.md; do not "fix" one by reaching into the
    // other, they are different rules with different reach.
    let rootContainingBlockWidth: Double? = {
        if case .definite(let w) = available.width { return w }
        return nil
    }()
    layoutContainer(tree, root, containerOrigin: (0, 0), containerSize: rootSize,
                    containingBlockWidth: rootContainingBlockWidth,
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
    /// The item's final cross-axis size: its own style's cross size, or — when
    /// its resolved alignment is `stretch` and that size is `auto` — the line's
    /// cross extent clamped by the item's cross min/max (§9.4).
    ///
    /// Still 0 for an item that is auto-sized on the cross axis and *not*
    /// stretched: content-based cross sizing needs a measure function and
    /// arrives with the M2 text system.
    var crossSize: Double
    /// §9.7 freezes an item once its size is final, and the loop stops when
    /// every item is frozen.
    var frozen: Bool
    /// The item's resolved leading/trailing margin on the **main** axis —
    /// `(left, right)` in a row, `(top, bottom)` in a column.
    ///
    /// Margins sit *outside* the border box `targetMainSize` describes; an
    /// item's outer main extent is `marginMain.leading + targetMainSize +
    /// marginMain.trailing`. `positionItems` is the only reader: the cursor
    /// advances by the outer extent, and the item's own rect starts
    /// `marginMain.leading` after the cursor.
    var marginMain: (leading: Double, trailing: Double)
    /// The item's resolved leading/trailing margin on the **cross** axis —
    /// `(top, bottom)` in a row, `(left, right)` in a column.
    ///
    /// Read only by `positionItems`, which offsets `crossAxisOffset`'s result
    /// by `marginCross.leading` and — per the brief — passes the *outer*
    /// cross size (`marginCross.leading + crossSize + marginCross.trailing`)
    /// as `crossAxisOffset`'s `itemCross`, so alignment measures the margin
    /// box, not the border box.
    var marginCross: (leading: Double, trailing: Double)
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
        //
        // **This is knowingly asymmetric with `computeLayout`, which resolves
        // the root's percentage PADDING against `available.width`.** Both
        // cannot be right, and this one is the divergence: measured in WebKit,
        // a root with `width: 50%` in an 800-wide body is **400**, while this
        // returns nil and falls back to the offered 800. Changing it means
        // deciding whether `available` is the initial containing block (ruling
        // FS-1 says it is) for *sizing* as well as for insets, and moves the
        // root's stored size, which every descendant consumes — a sizing
        // change, not a box-model one. Recorded in CLAUDE.md's inert table.
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

/// A container's content box: where its children start, and how much room they get.
///
/// **Border-box sizing means `borderBox` is the node's stored size**, so this
/// subtracts rather than adds. The returned origin is *relative to the
/// container's own origin* — callers add it to the absolute origin, keeping the
/// "all stored rects are absolute" invariant in one place.
///
/// Percentages in `padding` and `border` resolve against
/// `containingBlockWidth` — the width of the box's **containing block**, on
/// every edge including top and bottom. Two separate rules are packed into
/// that sentence and each has its own mutation:
///
/// 1. **Width, not height**, even for `padding-top`/`padding-bottom`. CSS, not
///    a simplification; `resolveEdges` documents it too, and
///    `flex_percent_padding_nonsquare` is what distinguishes the bases (a
///    square container cannot).
/// 2. **The containing block's width, not this box's own.** The containing
///    block of a flex item is its flex container's *content* box, and for the
///    root it is the space `computeLayout` was offered. This function passed
///    `borderBox.width` until Task 3 — the box's own size — which is wrong for
///    every box whose width differs from its parent's content width, i.e.
///    almost all of them. Measured against WebKit: a 200-wide `.mid` with
///    `padding: 10%` inside a root whose content box is 270 wide gets **27**,
///    not 20 (10% of its own width) and not 40 (10% of the root's border
///    box). Pinned by `flex_nested_percent_padding`.
///
/// `nil` means the containing block is indefinite on that axis; `resolveEdges`
/// then treats every percentage edge as 0, which is CSS's rule for an
/// unresolvable percentage.
private func contentBox(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    borderBox: SizeD,
    containingBlockWidth: Double?,
    rootFontSize: Double
) -> (origin: (Double, Double), size: SizeD) {
    let s = tree.style(container)
    let padding = resolveEdges(s.padding, against: containingBlockWidth, rootFontSize: rootFontSize)
    let border = resolveEdges(s.border, against: containingBlockWidth, rootFontSize: rootFontSize)

    let leading = (padding.left + border.left, padding.top + border.top)
    // Ruling BM-4 (CLAUDE.md's known divergences) — this is a deliberate stand-in,
    // not a faithful CSS clamp. CSS's actual answer when padding + border
    // exceeds the specified size on an axis is to GROW the border box itself
    // (`box-sizing: border-box` defines the used size as
    // `max(specified, padding + border)`), never to let the content box go
    // negative. This function does not grow the border box — `borderBox` here
    // is exactly the node's already-stored size, and changing it is a sizing
    // change (`resolveNodeSize`/`flexBaseSize`) with reach well beyond this
    // function: the freeze loop and every ancestor consume a node's stored
    // size. `max(0, …)` is the narrower, local stand-in: it leaves the border
    // box exactly as specified and only prevents the content box from
    // inverting. See `containerDoesNotGrowToFitOverconstrainedPaddingUnlikeWebKit`
    // in BoxModelTests.swift for the pinned divergence and WebKit's real numbers.
    let size = SizeD(
        width: max(0, borderBox.width - padding.horizontal - border.horizontal),
        height: max(0, borderBox.height - padding.vertical - border.vertical))
    return (leading, size)
}

/// Lay out one container: collect its items, resolve flexible lengths, position.
private func layoutContainer(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    containingBlockWidth: Double?,
    rootFontSize: Double
) {
    // `containerSize` is the border box (§5.2). Everything below this line that
    // concerns the children — their available space, the freeze loop's main
    // extent, and their positioned origin and cross extent — works in the
    // CONTENT box instead: `containerSize` must not be used for children again.
    //
    // `containingBlockWidth` is a THIRD width and must not be confused with
    // either: it belongs to this container's *parent*, and its only use is as
    // the basis for this container's own percentage padding and border.
    let box = contentBox(tree, container, borderBox: containerSize,
                         containingBlockWidth: containingBlockWidth,
                         rootFontSize: rootFontSize)
    let childOrigin = (containerOrigin.0 + box.origin.0, containerOrigin.1 + box.origin.1)

    var items = collectItems(tree, container, containerSize: box.size,
                             rootFontSize: rootFontSize)
    guard !items.isEmpty else { return }

    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    let containerMain = isRow ? box.size.width : box.size.height
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain, rootFontSize: rootFontSize) ?? 0

    // §9.7 itself is untouched (`ResolveFlexibleLengths.swift` gains no margin
    // awareness) — instead the budget it grows/shrinks into is shrunk by the
    // items' total margin before the call, exactly the way `gap` already
    // shrinks it inside that function. That is sound because every margin here
    // is a fixed (non-flexible) amount: `containerMain' = containerMain -
    // totalMargin` makes `containerMain' - totalGap - sum(targets)` equal
    // `containerMain - totalGap - sum(outerSizes)`, the real leftover space,
    // for any split of `targets` the freeze loop produces. `positionItems`
    // below still uses the real, un-shrunk `containerMain` for its own
    // free-space math (`justify-content`), because it distributes space
    // around the outer (margin-inclusive) boxes, not the reduced budget.
    let totalMargin = items.reduce(0.0) { $0 + $1.marginMain.leading + $1.marginMain.trailing }
    resolveFlexibleLengths(tree, items: &items, containerMain: containerMain - totalMargin, gap: gap)

    positionItems(tree, container, items: items, containerOrigin: childOrigin,
                  containerSize: box.size, rootFontSize: rootFontSize)
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
            // **Ruling FS-3 — half the rule is deliberately missing.** §4.5's
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

            // Margins sit outside the border box `own`/`base` describe.
            // Percentages resolve against the containing block's **width**,
            // on every edge including top and bottom — CSS's rule, which
            // `resolveMargin` (like `resolveEdges`) already implements.
            // `containerSize` here is the CONTENT box (Task 1 threads it
            // into `collectItems`), not the border box.
            //
            // Resolved BEFORE the stretch block below, not after: a stretched
            // item's cross size must subtract `marginCross` (CSS stretches the
            // *margin box* to fill the line, not the border box), so
            // `marginCross` has to exist before that clamp runs. Getting this
            // ordering backwards was fix-round-1 bug 2 — `cross =
            // clamp(containerCross, …)` filled the whole line and then
            // silently overflowed it by the item's own margins, undetected by
            // any of the 153 tests at the time, because no fixture combined
            // `auto` cross sizing with a nonzero cross margin. Pinned now by
            // `stretchSubtractsCrossMarginsBeforeClamping` and the
            // `flex_row_stretch_with_margins` fixture.
            let margin = resolveMargin(ks.margin, against: containerSize.width,
                                       rootFontSize: rootFontSize)
            // Typed explicitly (not inferred) so `.leading`/`.trailing` are
            // usable locally, below, before either value reaches `FlexItem`'s
            // own labelled-tuple fields.
            let marginMain: (leading: Double, trailing: Double) =
                isRow ? (margin.left, margin.right) : (margin.top, margin.bottom)
            let marginCross: (leading: Double, trailing: Double) =
                isRow ? (margin.top, margin.bottom) : (margin.left, margin.right)

            // CSS Flexbox §9.4 — cross-axis stretch.
            //
            // An item stretches when its resolved alignment is `stretch` AND its
            // cross size property is `auto`. A definite cross size wins outright;
            // a stretched size is still clamped by the item's cross min/max.
            //
            // This is why every fixture whose children have no explicit cross
            // size agreed with WebKit only on the main axis until now: CSS's
            // initial `align-items` behaves as `stretch`, so the browser filled
            // the container while we produced 0.
            //
            // `crossDim` is selected per axis, not hardwired to `height`: a
            // column's cross axis is width, and `flex_column_grow_with_max`'s
            // golden holds `width: 100` for children that declare none.
            //
            // **Stretch fills the line's cross extent MINUS the item's own
            // cross margins**, then clamps what is LEFT to the item's min/max —
            // not the other way around. `min`/`max-height` describe the border
            // box, so subtracting margins first and clamping second is the only
            // ordering that answers "how big can the border box be" correctly;
            // clamping the full `containerCross` first and subtracting margins
            // after would let a `max-height` cap the MARGIN box instead, and
            // `stretchWithMaxHeightClampsTheBorderBoxNotTheMarginBox` pins the
            // ordering against WebKit including a `max-height` probe.
            //
            // **Content-based cross sizing is still missing**, and it is the
            // other half of §9.4. An item that is *not* stretched — because its
            // alignment is `center`, `flex-start`, `flex-end`, or because the
            // container wraps — and has an `auto` cross size gets 0 here, where
            // CSS gives it its content's cross size. Every fixture in the corpus
            // is an empty div, for which 0 is right, so nothing catches it; when
            // the M2 text system lands, this is where `tree.measure` belongs.
            let crossDim = isRow ? ks.size.height : ks.size.width
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
            let ownCross = isRow ? own.height : own.width
            let align = resolvedAlignment(ks, container: s)
            var cross = ownCross
            if align == .stretch, case .auto = crossDim {
                let lowerCross = resolveDimension(isRow ? ks.minSize.height : ks.minSize.width,
                                                  against: containerCross, rootFontSize: rootFontSize)
                let upperCross = resolveDimension(isRow ? ks.maxSize.height : ks.maxSize.width,
                                                  against: containerCross, rootFontSize: rootFontSize)
                let availableCross = containerCross - marginCross.leading - marginCross.trailing
                cross = clamp(availableCross, min: lowerCross, max: upperCross)
            }

            // `targetMainSize:` here is dead — §9.7.2 overwrites it on every
            // item before it is read, and no empty-line path reaches
            // `positionItems`. It repeats `hypothetical` only because a
            // constructor must pass something; nothing depends on which value.
            // See the field's declaration.
            return FlexItem(node: kid, baseSize: base, hypotheticalMainSize: hypothetical,
                            minMain: minMain, maxMain: maxMain,
                            targetMainSize: hypothetical, crossSize: cross, frozen: false,
                            marginMain: marginMain, marginCross: marginCross)
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
    // §9.4.2's "flex-start" and "flex-end" are keyed to the *flex-relative*
    // direction, so a `.rowReverse`/`.columnReverse` container's main-start is
    // its physical right/bottom edge, not its left/top. `cursor` below still
    // accumulates along the flex-relative axis exactly as the forward case
    // does — `distributeMainAxis`, `gap`, and item order are all unaware of
    // reversal — and only the point where a position is *read out* converts
    // that flex-relative cursor into a physical coordinate.
    //
    // Reversing `items` instead is not a correctness requirement: done
    // correctly it is numerically equivalent to this cursor conversion.
    // `distributeMainAxis` has no per-item notion of "first" to corrupt — it
    // takes only `justify`, `freeSpace` and `itemCount`. What array-reversal
    // would need is a compensating flip of which side `offsets.leading` is
    // measured from, and that matters for exactly the **asymmetric**
    // distributions — the ones where the space before the line differs from
    // the space after it. That is `flex-start` (leading 0, trailing all of it)
    // and `flex-end` (the reverse), and no others: `center`, `space-around`,
    // `space-evenly` and `space-between` all put equal space at both ends, so
    // reversing without a flip lands on identical numbers. Verified by
    // measurement — a `row-reverse` + `space-around` + `gap` probe matches
    // WebKit under array-reversal with no flip at all, while `flex-start` and
    // `flex-end` do not. (Two earlier attempts at this paragraph named the
    // wrong discriminator: it is `leading == trailing`, not `leading == 0`.)
    // This file keeps `items` in document order instead because
    // document order is the one thing about this loop with a use outside it:
    // wrapping's line collection and baseline grouping (neither implemented
    // yet) will need to index items by DOM position, and converting the
    // cursor confines the reversal to the single place a physical position is
    // actually derived, rather than threading a flipped item order through
    // everything downstream of `collectItems`.
    let isReverse = s.flexDirection.isReverse
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain,
                            rootFontSize: rootFontSize) ?? 0

    // The line's content size counts margins — an item's OUTER main extent,
    // not its border box — or free space is overstated and every
    // `justify-content` value lands wrong (the space-between fixture is the
    // browser's word on this). `lineContentSize` itself stays margin-blind
    // ([Double] in, shared with Grid); outer sizes are computed here instead.
    func outerMain(_ item: FlexItem) -> Double {
        item.marginMain.leading + item.targetMainSize + item.marginMain.trailing
    }
    let content = lineContentSize(items.map(outerMain), gap: gap)
    let offsets = distributeMainAxis(s.justifyContent ?? .flexStart,
                                     freeSpace: containerMain - content,
                                     itemCount: items.count)

    // `cursor` tracks the flex-relative start of each item's OUTER (margin)
    // box, exactly as it tracked the border box before margins existed. The
    // border box's own position is derived from `cursor` further down, but
    // NOT by adding `marginMain.leading` to `cursor` itself — `marginMain` is
    // physical, `cursor` is flex-relative, and the two must not mix before
    // `cursor` is converted to a physical coordinate. See the conversion
    // below for why, and for the bug that mixing them caused.
    var cursor: Double = offsets.leading
    for (index, item) in items.enumerated() {
        // Between items only.
        if index > 0 { cursor += gap + offsets.between }

        // CSS Flexbox §9.6 — the line's cross size is the container's cross
        // extent (single-line only; wrapping would make this the line's own
        // measured cross size instead).
        //
        // `crossAxisOffset` is handed the OUTER cross size — margin included
        // — because alignment (e.g. `flex-end`) measures the margin box
        // against the line, not the border box; the result is then nudged by
        // the leading cross margin to land on the border box's own origin.
        let align = resolvedAlignment(tree.style(item.node), container: s)
        let outerCross = item.marginCross.leading + item.crossSize + item.marginCross.trailing
        let crossOffset = crossAxisOffset(align, itemCross: outerCross,
                                          lineCross: containerCross)
                         + item.marginCross.leading

        // Convert the flex-relative cursor to the OUTER box's physical
        // main-axis position, THEN add the margin — not the other way
        // around. `marginMain` is **physical**: `(margin.left, margin.right)`
        // for a row, `(margin.top, margin.bottom)` for a column, unaffected
        // by `isReverse` (CSS's `margin-left`/`margin-right` do not flip with
        // `row-reverse`, unlike a logical property such as
        // `margin-inline-start` — this framework has no logical properties).
        // `marginMain.leading` is therefore always the physical-start
        // margin. Adding it to the still-flex-relative `cursor` before
        // reversing — the bug fix-round-1 found — silently put `margin-left`
        // on a `row-reverse` item's physical RIGHT instead of its left,
        // undetected by any of the 153 tests because none combined `isReverse`
        // with a nonzero margin. Measured against WebKit
        // (`row-reverse`, `a{w:50, ml:10, mr:30}` in a 400-wide line):
        // WebKit puts `a.x` at 320; `cursor + marginMain.leading` first, then
        // reversed, gave 340. Pinned now by
        // `reverseContainersApplyMarginsToThePhysicalEdge` and the
        // `flex_row_reverse_margins` / `flex_column_reverse_margins`
        // fixtures — two, because a row-only fix could still transpose
        // top/bottom on the column axis and nothing here would catch it.
        //
        // Forward: the OUTER box's physical main-start IS `cursor` (the
        // container's flex-relative start already is its physical
        // main-start), so the border box's physical start is `cursor +
        // marginMain.leading`.
        // Reversed: the OUTER box's flex-relative start sits `cursor` in
        // from the container's flex-start, which is the container's
        // physical main-END, so the OUTER box's physical start is
        // `containerMain - cursor - outerMain(item)` — using the OUTER
        // extent, since that whole margin box is what is being flipped to
        // the other physical edge. The border box's physical start is then
        // that OUTER physical start plus the physical-start margin, exactly
        // as in the forward case: `+ marginMain.leading`.
        let outerPhysicalStart = isReverse
            ? (containerMain - cursor - outerMain(item))
            : cursor
        let main = outerPhysicalStart + item.marginMain.leading
        let x = containerOrigin.0 + (isRow ? main : crossOffset)
        let y = containerOrigin.1 + (isRow ? crossOffset : main)
        let size = isRow
            ? SizeD(width: item.targetMainSize, height: item.crossSize)
            : SizeD(width: item.crossSize, height: item.targetMainSize)

        tree.setLayout(item.node, LayoutRect(x: x, y: y, width: size.width, height: size.height))
        // `containerSize` here is THIS container's content box (`layoutContainer`
        // passes `box.size`), which is exactly the item's containing block — so
        // its width is the basis for the item's own percentage padding and
        // border. Passing `size.width` (the item's own width) instead is the
        // bug Task 3 found: correct only when an item happens to be as wide as
        // its parent's content box.
        layoutContainer(tree, item.node, containerOrigin: (x, y), containerSize: size,
                        containingBlockWidth: containerSize.width,
                        rootFontSize: rootFontSize)

        cursor += outerMain(item)
    }
}
