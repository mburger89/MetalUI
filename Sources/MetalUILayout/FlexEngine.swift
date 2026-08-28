import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: §9.2 flex
/// base sizes, §9.3 line collection, §9.4 cross-axis stretch and §9.4.8 line
/// cross sizing, §9.5 justify-content packing, §9.6 cross-axis placement,
/// §9.6.15 align-content, §9.7 grow/shrink, §8.3's `wrap-reverse`, and the box
/// model — `padding` and `border` shrink the content box (`contentBox` below),
/// `margin` sits outside each item's border box (`collectItems`,
/// `positionItems`). Absolute positioning arrives in a later plan, with its own
/// fixtures.
///
/// **The phase order is: size every item, break into lines, distribute cross
/// space among the lines, then per line stretch → flex — and finally position
/// every line.** Positioning is the last phase and a separate pass
/// (`layOutChildren` sizes, `placeNode` positions) so that `measureNode` can
/// run everything up to it and write nothing. Breaking
/// uses *hypothetical* main sizes (§9.3), because §9.7 runs per line and so
/// cannot have run yet; a line's cross size is measured from its items'
/// *unstretched* outer cross sizes (§9.4.8), so it must be measured after the
/// break; `align-content: stretch` then grows those measured sizes, and only
/// after that does §9.4's item stretch fill them. Every one of those orderings
/// is circular or wrong if reversed.
///
/// **Both reversals are conversions at the point of use, not reorderings.**
/// `row-reverse`/`column-reverse` flip the main axis and `wrap-reverse` flips
/// the cross axis; `collectLines` and this file's cursors stay in document
/// order and flex-relative coordinates throughout, and `positionItems` is the
/// single place either becomes physical. `collectLines` *must* see document
/// order — CSS assigns items to lines in document order whatever the direction
/// — so a pre-flipped array reaching it would put the wrong items on the wrong
/// lines. See `positionItems` for the four conversions (two axes × two nesting
/// levels) and the WebKit numbers each was measured against.
///
/// Three gaps remain and are recorded rather than implied: `inset` is still
/// read by nothing (absolute positioning is its own plan), `margin: auto`
/// resolves to 0 instead of absorbing free space, and CSS Sizing §4.5's
/// **specified** size suggestion is missing from `collectItems`' automatic
/// minimum (ruling FS-3) — which content sizing turned from a dormant gap into
/// a measured disagreement with WebKit, because the *content* suggestion it
/// pairs with is now live for containers. All three have rows in CLAUDE.md's
/// inert-API table, and FS-3 additionally has divergence 5 there, where its
/// WebKit numbers live.
///
/// **Cross-axis `stretch` landed in the alignment task, and with it every golden
/// comparison in the suite is now full-rect.** Twelve of them compared the main
/// axis alone until then, because `collectItems` took an item's cross size from
/// its own style and produced 0 where CSS's default `align-items: stretch` gives
/// the container's extent. Nothing was regenerated when they widened: the
/// committed goldens already held WebKit's stretched answers, which is the
/// evidence the rule is right.
///
/// **Content-based cross sizing landed with content sizing** — the other half of
/// §9.4, and the last of the four constants. **Any** item with an `auto` cross
/// size used to measure 0 here, stretched or not, because the size is lost in
/// §9.4.8 line measurement, which runs *before* stretch; `collectItems`'
/// `ownCross` now asks `measureNode` instead. WebKit gives a nested
/// `width: 120px` flex container `120×50` where this engine gave `120×0`, and
/// gives it `120×50` now.
///
/// Ruling **WR-4**'s history is worth keeping because the paragraph that stood
/// here was wrong twice: it scoped the gap to a *non-stretched* item, and said
/// no fixture could catch it without the M2 text system. Both were disproved by
/// measurement — a **nested flex container** has a content cross size with no
/// text in it. The gate was never text metrics but recursive subtree
/// measurement, and naming a mechanism rather than a milestone is what let it
/// be closed a milestone early.
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
    let ctx = LayoutContext(rootFontSize: rootFontSize)
    tree.beginLayout()
    defer { tree.endLayout() }

    // The root's containing block is the space it was offered — ruling FS-1's
    // "the root is a block box in the initial containing block". So the root's
    // own percentage padding and border resolve against `available.width`, NOT
    // against the root's resolved width: a 400-wide root inside an 800-wide
    // viewport has `padding: 10%` of 800. Indefinite offered width means an
    // indefinite containing block, and percentage edges then resolve to 0.
    //
    // `resolveRootSize` below still resolves the root's own `width: 50%`
    // against nil rather than against this same extent — a separate, narrower
    // divergence, recorded in CLAUDE.md; do not "fix" one by reaching into the
    // other, they are different rules with different reach.
    //
    // Hoisted above `resolveRootSize` because that function may now measure the
    // root, and a measure needs the same containing-block width a placement
    // does — the basis for the root's own percentage padding and border, which
    // is part of the border box it reports (ruling CS-F).
    let rootContainingBlockWidth: Double? = {
        if case .definite(let w) = available.width { return w }
        return nil
    }()
    let rootSize = resolveRootSize(ctx, tree, root, available: available,
                                   containingBlockWidth: rootContainingBlockWidth)
    tree.setLayout(root, LayoutRect(x: 0, y: 0, width: rootSize.width, height: rootSize.height))
    placeNode(ctx, tree, root, origin: (0, 0), size: rootSize,
              containingBlockWidth: rootContainingBlockWidth)

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
    /// and both guards on the way in (`layOutChildren`'s `!items.isEmpty` and
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
    /// **`collectItems` leaves this at the item's own resolved cross size even
    /// for a stretch-eligible item**, because the line it stretches into does
    /// not exist yet: `collectLines` needs cross sizes to measure a line, and
    /// stretch needs the measured line. `layOutChildren`'s line phase writes
    /// the stretched value, once per line. Until wrapping landed the two
    /// coincided — there was one line and its cross size *was* the
    /// container's — which is exactly why the split had to happen before any
    /// line code was written.
    ///
    /// Still 0 for **any** item auto-sized on the cross axis, stretched or not —
    /// the size is lost in §9.4.8 line measurement, before stretch runs. Ruling
    /// **WR-4**; a measure function is not the only thing missing, a nested flex
    /// container has a content cross size today and the engine does not compute
    /// it.
    var crossSize: Double
    /// True when §9.4's stretch applies to this item: its resolved alignment is
    /// `stretch` **and** its cross size property is `auto`.
    ///
    /// **Read only by `layOutChildren`'s line phase.** `collectItems` decides
    /// it (it is the phase that has the styles) and nothing else consumes it;
    /// if a second reader ever appears, say so here.
    var stretchEligible: Bool
    /// The item's resolved cross-axis floor and ceiling, nil for "unbounded".
    ///
    /// Carried for the same reason `minMain`/`maxMain` are: the line phase
    /// clamps a stretched size and must not re-resolve the style to do it. The
    /// basis matters and is **not** the line's cross size — a percentage
    /// `min-height` resolves against the containing block (the container's
    /// content box), which is what `collectItems` had to hand. Resolving them
    /// against the line instead would make an item's floor depend on which
    /// line it happened to land on.
    ///
    /// Read only by the line phase's stretch clamp, and only for a
    /// `stretchEligible` item — a non-stretched item's own cross size was
    /// already clamped by `resolveNodeSize`.
    var minCross: Double?
    var maxCross: Double?
    /// §9.7 freezes an item once its size is final, and the loop stops when
    /// every item is frozen.
    var frozen: Bool
    /// The item's resolved leading/trailing margin on the **main** axis —
    /// `(left, right)` in a row, `(top, bottom)` in a column.
    ///
    /// Margins sit *outside* the border box `targetMainSize` describes; an
    /// item's outer main extent is `marginMain.leading + targetMainSize +
    /// marginMain.trailing`. **Two readers**, and both matter: `layOutChildren`
    /// sums every item's pair into `totalMargin` and pre-reduces the grow
    /// budget with it, and `positionItems` uses each item's own pair — the cursor
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
/// This fallback belongs to the root alone (ruling FS-1), and **its
/// justification is `computeLayout`'s contract rather than CSS's block-layout
/// rule** — the two are not the same argument and the difference is ruling
/// **CS-I**, recorded at the `auto` branch below. The engine's root is *not* a
/// block box in a CSS initial containing block: it is a node whose size its
/// host supplies, and `.definite(w)` on an axis of `available:` is the host
/// saying "this axis is w". CSS's block box shrink-wraps its block axis and
/// WebKit measurably does (**800 x 40** where this engine gives 800 x 600), so
/// citing §10.3.4 here would claim agreement that does not exist. A flex
/// item's `auto` main size means something else again: it is resolved via
/// §9.2's flex base size (the FLEX-SIZING milestone's second task) and never by
/// inheriting a container's
/// extent, which is why `resolveNodeSize` below must not fall back to
/// `available` — doing so would silently reintroduce the Task 7 scope-boundary
/// fallback this task deletes from item sizing.
private func resolveRootSize(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ root: LayoutNodeID,
    available: AvailableSpaceSize,
    containingBlockWidth: Double?
) -> SizeD {
    let s = tree.style(root)
    let rootFontSize = ctx.rootFontSize

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
    // change, not a box-model one. Recorded in CLAUDE.md's inert table, and
    // deliberately NOT touched by the content-sizing milestone (spec §2):
    // only the `auto` branch below changes, and a percentage still lands in
    // the `offered` branch exactly as it did.
    func declared(_ dim: Dimension) -> Double? {
        resolveDimension(dim, against: nil, rootFontSize: rootFontSize)
    }

    /// What an axis resolves to without measuring anything: its declared size,
    /// or the extent the root was offered. `nil` — "measure it" — only when
    /// there is no declared size and no offered extent either.
    ///
    /// **The `auto` test is on the DECLARATION, not on `declared(dim) == nil`.**
    /// A percentage against the root's absent parent is also unresolvable, and
    /// routing it through the measuring branch would silently fix the
    /// divergence described above from the wrong end. A percentage keeps
    /// today's answer exactly: the offered extent, or 0.
    func withoutMeasuring(_ dim: Dimension, _ offered: AvailableSpace) -> Double? {
        if let d = declared(dim) { return d }
        guard case .auto = dim else { return definiteExtent(offered) ?? 0 }
        return definiteExtent(offered)
    }

    // **An `auto` root axis with a definite offered extent still takes that
    // extent (ruling CS-I), and the justification is `computeLayout`'s own
    // contract — not a ruling from a layer above this one.**
    //
    // The engine's root is **not a block box in a CSS initial containing
    // block**. It is a node whose size its host supplies: `available:` is the
    // surface the caller is laying out into, and `.definite(w)` on an axis is
    // the host saying "this axis is w". Honouring that is what the parameter
    // means. A browser has no equivalent — its root's containing block is the
    // viewport by construction, and it is never *told* a size.
    //
    // CSS therefore disagrees, and the disagreement is measured rather than
    // assumed: a block-level box fills its inline axis and shrink-wraps its
    // block axis, so in WebKit an 800x600 viewport holding
    // `#root { display: flex }` with one 100x40 child gives the root
    // **800 x 40**, where this engine gives **800 x 600**.
    //
    // **Do not cite EP-5 for this.** That ruling ends with "the WebKit corpus
    // stays the oracle for the engine; this ruling binds everything above it",
    // and `resolveRootSize` is inside the engine — citing it here reads it
    // past its own boundary and weakens it. The evidence that the contract
    // reading is the right one is behavioural, not authoritative: taking
    // WebKit's answer was implemented and reverted, and it reddens six
    // element-pipeline and frame-loop tests at once, because a `Row { … }`
    // rendered into a 400x120 `Frame` declares no height and the window's root
    // would collapse to its content with every `flexGrow(1)` child stretching
    // into 0.
    //
    // **The engine can still express CSS's answer**, which is what makes this
    // an interpretation of one call shape rather than a disagreement with
    // WebKit: a host that offers `.maxContent` on the block axis takes the
    // measuring branch below and gets the shrink-wrapped 40. What differs is
    // only what a *definite* offered extent means for an `auto` axis.
    //
    // **A fixture could hold the divergence** — `#root { display: flex }` with
    // no `width` or `height` is perfectly expressible and its golden would say
    // 800x40 — so the corpus deliberately contains none, on the same footing
    // as WebKit's flex sub-one clause. That all 67 roots declare both axes
    // explains why no *existing* fixture notices; it is not a reason one
    // could not exist.
    //
    // What content sizing *does* change here is the case where there is no
    // offered extent to take: that was a hardcoded 0, and it is now the
    // subtree's own size. A browser cannot express an indefinite viewport, so
    // this half is reasoned from CSS's shrink-to-fit rule rather than measured
    // against one.
    let width = withoutMeasuring(s.size.width, available.width)
    let height = withoutMeasuring(s.size.height, available.height)

    // Measure only when an axis actually needs it. Skipping the call when both
    // axes are settled is not an optimisation: `measureNode` runs the whole
    // subtree, and every fixture in the corpus has a root with both a `width`
    // and a `height`.
    let base: SizeD
    if let width, let height {
        base = SizeD(width: width, height: height)
    } else {
        // A measured axis is offered `.maxContent`, never the definite extent
        // it declined to take. `measureNode` turns a definite available extent
        // into the node's OWN extent, so offering 600 here would lay the root
        // out 600 tall internally — resolving its children's percentage heights
        // against a height the root does not have.
        base = measureNode(
            ctx, tree, root,
            known: OptionalSizeD(width: width, height: height),
            available: AvailableSpaceSize(
                width: width.map { AvailableSpace.definite($0) } ?? .maxContent,
                height: height.map { AvailableSpace.definite($0) } ?? .maxContent),
            containingBlockWidth: containingBlockWidth)
    }

    return SizeD(
        width: clamp(base.width, min: declared(s.minSize.width), max: declared(s.maxSize.width)),
        height: clamp(base.height, min: declared(s.minSize.height), max: declared(s.maxSize.height)))
}

/// Resolve a node's own border-box size from its style.
///
/// This is for nodes whose size comes from their own style alone — a flex
/// item's **cross** axis, and any node reached from `collectItems`. Since
/// the FLEX-SIZING milestone's second task, `collectItems` gets an item's main
/// axis from `flexBaseSize(_:)` instead, so this function never touches a flex
/// item's main axis at all;
/// `collectItems` still calls it for the item's full `SizeD` and reads only
/// the cross component out of it. It must never grow a `flexBasis` branch of
/// its own to reach into the main axis anyway — m1a ruling PF-3
/// (`docs/superpowers/2026-08-25-m1a-decisions.md`) named exactly that
/// shortcut as the failure mode: an auto-sized item quietly inheriting a
/// fallback that was only ever meant to be temporary. That is also why,
/// unlike `resolveRootSize`, this function never falls back to an offered
/// available extent — an axis it cannot resolve from the node's own style is
/// 0, on both the cross axis here and the (unused) main axis.
///
/// **Its 0 is no longer the last word on an `auto` cross size.** `collectItems`
/// keeps calling this for the item's full `SizeD`, but takes the cross
/// component from it only when the cross size property is *not* a literal
/// `auto`; an `auto` one is measured through `measureNode` instead. The 0 above
/// still describes what happens to an unresolvable **percentage**, which WebKit
/// also leaves at 0 rather than content-sizing — see `ownCross` there.
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
///    `borderBox.width` until the BOX MODEL milestone's third task — the box's
///    own size — which is wrong for
///    every box whose width differs from its parent's content width, i.e.
///    almost all of them. Measured against WebKit: a 200-wide `.mid` with
///    `padding: 10%` inside a root whose content box is 270 wide gets **27**,
///    not 20 (10% of its own width) and not 40 (10% of the root's border
///    box). Pinned by `flex_nested_percent_padding`.
///
/// `nil` means the containing block is indefinite on that axis; `resolveEdges`
/// then treats every percentage edge as 0, which is CSS's rule for an
/// unresolvable percentage.
///
/// `edges` is the total this box spends on padding and border per axis — the
/// term that turns a content box back into a border box. It is returned rather
/// than recovered as `borderBox - size` by the caller because that subtraction
/// is not invertible: `size` is clamped at 0 (ruling BM-4, below), and an axis
/// of `borderBox` may be **indefinite**, where there is nothing to subtract
/// from.
///
/// `borderBox` is an `OptionalSizeD` because `measureNode` asks about a node
/// whose size is exactly what it is trying to find out: `nil` on an axis means
/// "indefinite", and the content box is then indefinite too. Padding and border
/// still resolve — they are measured against `containingBlockWidth`, which is a
/// different box — so `edges` is always definite. Ruling **CS-D**: an
/// indefinite axis is `nil`, never `.infinity` and never a large finite
/// stand-in.
private func contentBox(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    borderBox: OptionalSizeD,
    containingBlockWidth: Double?,
    rootFontSize: Double
) -> (origin: (Double, Double), size: OptionalSizeD, edges: SizeD) {
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
    let size = OptionalSizeD(
        width: borderBox.width.map { max(0, $0 - padding.horizontal - border.horizontal) },
        height: borderBox.height.map { max(0, $0 - padding.vertical - border.vertical) })
    let edges = SizeD(width: padding.horizontal + border.horizontal,
                      height: padding.vertical + border.vertical)
    return (leading, size, edges)
}

/// One child of a `.stack` container, at its own size.
///
/// Deliberately NOT a `FlexItem`: eight of that type's eleven fields —
/// `baseSize`, `hypotheticalMainSize`, `minMain`, `maxMain`, `targetMainSize`,
/// `frozen` among them — are meaningless here, because a stack has no main axis
/// and never runs §9.7. Reusing it would need a convention ("width goes in
/// `targetMainSize`") that reads as flex semantics to anyone who did not write it.
private struct StackItem {
    let node: LayoutNodeID
    var size: SizeD
}

/// The result of running §9.2–§9.7 over a container's children, before anything
/// is positioned. `placeNode` goes on to position from it; `measureNode` reads
/// only `contentSize` and `edges` and discards the rest.
private struct ContainerLayout {
    /// The lines, sized and flexed, each carrying the `crossStart` the line
    /// phase computed for it. Empty when the container has no items — which is
    /// the whole of "there is nothing to place", so there is no second
    /// representation of that state.
    var lines: [FlexLine]
    /// The container's resolved CONTENT box — what the items actually occupy,
    /// measured from them rather than from the extent they were offered. That
    /// distinction is the entire reason this field exists: under a `nowrap`
    /// container the *line's* cross size is the container's own extent
    /// (§9.4.8's single-line clause), so reading it back would answer
    /// `measureNode` with the question it asked.
    var contentSize: SizeD
    /// Padding + border per axis, from `contentBox`. `contentSize + edges` is
    /// the container's border box, which is what `measureNode` reports.
    var edges: SizeD
    /// Where and how big the items are placed: `origin` is the leading padding +
    /// border, `size` the content box `positionItems` places into.
    ///
    /// Definite on both axes even when the container's own size was not, because
    /// an axis with no given extent shrinks to fit — `size` takes the measured
    /// `contentSize` there. Not interchangeable with `contentSize` all the same:
    /// where the container *was* given an extent, this is that extent and
    /// `contentSize` is what the items came to.
    var box: (origin: (Double, Double), size: SizeD)
    /// The children of a `.stack` container, each at its own size.
    ///
    /// Empty for a flex container, exactly as `lines` is empty for a stack.
    /// Each field is honest about what it holds rather than one field carrying
    /// two meanings.
    var stackItems: [StackItem]
}

/// Phases 1–2 — collect a container's items, break them into lines, and resolve
/// every size, **without positioning anything**.
///
/// Split out of what used to be `layoutContainer` so the sizing work is
/// reachable without the writing work: `placeNode` runs this and then positions,
/// `measureNode` runs this and reads the size off it. Nothing here calls
/// `setLayout`, and that is the property `measuringWritesNoLayout` guards.
///
/// **Positioning moved out of the per-line loop, and that is behaviour-neutral
/// by construction.** The loop below used to call `positionItems` for each line
/// before advancing its cursor; now it records `crossStart` on the line and
/// `placeNode` positions all the lines afterwards. Nothing the loop computes
/// reads anything `positionItems` writes — it writes only stored rects and
/// recurses — and nothing `positionItems` reads changes after its own line has
/// been stretched and flexed. The 67 browser goldens are the check.
///
/// **An axis of `containerSize` may be `nil`, and that is not the same as 0**
/// (ruling CS-D). It means the container has no given extent there — the shape
/// `measureNode` asks about — and the CSS consequences run right through this
/// function: percentages against it are unresolvable and resolve to 0 or auto
/// (`resolveDimension` already does that with a `nil` basis), free space is
/// indefinite so §9.7 has nothing to distribute, and §9.4.8's single-line
/// clause does not apply because it needs a *definite* container cross size.
/// Each is marked below. Substituting `.infinity` for the missing extent
/// instead — the first version of this — makes the freeze loop diverge and
/// `assertionFailure` out of the process; substituting a large finite number
/// resolves percentages against a fiction.
///
/// **`intrinsic` is the question the container is being asked, and it is only
/// ever consulted on an axis where `containerSize` is `nil`.** That is not a
/// convention to remember: `measureNode` builds it so that a non-nil mode on an
/// axis and a `nil` extent on that axis are the same condition (see
/// `IntrinsicQuery`), and `contentBox` maps `nil` to `nil`, so the same holds
/// for the content box below. `placeNode` passes `.unspecified` — real layout
/// asks no intrinsic question.
private func layOutChildren(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerSize: OptionalSizeD,
    intrinsic: IntrinsicQuery,
    containingBlockWidth: Double?
) -> ContainerLayout {
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
                         rootFontSize: ctx.rootFontSize)

    // A `.stack` container has no main axis, no lines and no §9.7 — it shares
    // only `contentBox` and the `edges` bookkeeping above with the flex path.
    // Branching here, before `collectItems`, means nothing below this line
    // (every flex-specific field and function) is ever reached for a stack.
    if tree.style(container).display == .stack {
        return layOutStack(ctx, tree, container, box: box)
    }

    let items = collectItems(ctx, tree, container, containerSize: box.size,
                             intrinsic: intrinsic)
    // No items, no lines: this is the early return the top-down recursion has
    // always had on a childless container. Returning here rather than
    // falling through is not only an optimisation — `align-content`'s leftover
    // arithmetic below spends `crossGap * (lines.count - 1)`, which is a
    // *negative* gap for zero lines.
    guard !items.isEmpty else {
        // Nothing to place, so the placement box is whatever extent the
        // container has; an indefinite axis shrinks to fit nothing, which is 0.
        return ContainerLayout(
            lines: [], contentSize: .zero, edges: box.edges,
            box: (box.origin, SizeD(width: box.size.width ?? 0,
                                    height: box.size.height ?? 0)),
            stackItems: [])
    }

    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    // Both `nil` where the container has no given extent on that axis. Every
    // use below is written for that case; `resolveLength` and
    // `resolveDimension` already take an optional basis and answer `nil` for a
    // percentage against one, which is CSS's rule for an unresolvable
    // percentage and the reason a percentage `gap` resolves to 0 here rather
    // than to an INFINITE gap — `inf * 0.1` is `inf`, and the line's budget
    // `containerMain - totalGap` is then `inf - inf`, which is NaN.
    let containerMain = isRow ? box.size.width : box.size.height
    let containerCross = isRow ? box.size.height : box.size.width
    // The container's own intrinsic question, resolved onto its axes exactly as
    // the two extents above are. Non-nil only where the matching extent is
    // `nil`, so the two are never both usable and there is no precedence rule
    // to get wrong.
    let mainIntrinsic = isRow ? intrinsic.width : intrinsic.height
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain, rootFontSize: ctx.rootFontSize) ?? 0
    // Ruling WR-1 — the CROSS-axis gap, which is the space **between lines**
    // and had no meaning at all until this task: both `gap` call sites read
    // `isRow ? .horizontal : .vertical`, so a row silently dropped its
    // `row-gap` and a column its `column-gap`. Neither component was dead
    // (each was read in one direction), which is why it never earned a row in
    // CLAUDE.md's inert table and why `gapUsesTheMainAxisOfTheContainer` reads
    // as full coverage while saying nothing about the dropped half.
    //
    // The basis is the container's own content-box extent on the gap's own
    // axis — CSS resolves a percentage `row-gap` against the block size and a
    // percentage `column-gap` against the inline size — so this one resolves
    // against `containerCross` exactly as the main gap resolves against
    // `containerMain`. `flex_wrap_uneven` and
    // `flex_wrap_with_margins_and_padding` both declare the two axes
    // *differently*, so reading the wrong one reddens rather than cancelling.
    let crossGap = resolveLength(isRow ? s.gap.vertical : s.gap.horizontal,
                                 against: containerCross, rootFontSize: ctx.rootFontSize) ?? 0

    // CSS Flexbox §9.3 then §9.4.8: break into lines on the items' hypothetical
    // main sizes, then measure each line's cross size.
    //
    // **A `nowrap` container's single line takes the container's content-box
    // cross extent, not `lineCrossSize`.** That is §9.4.8's single-line clause
    // — a definite container cross size *is* the line's — and it is what keeps
    // every one of the goldens committed before this branch byte-identical through this
    // change. It is keyed on the wrap MODE, not on `lines.count == 1`: a
    // `wrap` container that happens to produce one line measures that line
    // from its items, which is a different (and, per CSS, correct) answer.
    // **The budget is a comparison bound, not an extent**, and it is the one
    // place a missing main size becomes a number: `collectLines` only ever asks
    // whether the next item's outer size *exceeds* the line's budget, and no
    // arithmetic is done on it — which is what separates both values below from
    // the `inf` that made the freeze loop diverge (ruling CS-D).
    //
    // With no main extent the budget comes from the question being asked, and
    // this is CSS Flexbox §9.9.1.1 rather than a convenience:
    //
    // - **max-content, or no question at all: unbounded.** Nothing exceeds it,
    //   so nothing wraps — a container sized to its max-content is a container
    //   wide enough for one line.
    // - **min-content: zero.** Every item after the first "would not fit", so
    //   each item lines alone. That is a WRAPPING fact and it is the whole of
    //   the difference between the two questions for a container: no amount of
    //   `flexBaseSize` work reaches it, because base sizes are per item and
    //   this is about where the breaks go.
    //
    // `.unspecified` (real layout) and `.maxContent` deliberately share the
    // unbounded branch: `placeNode` always has a definite extent here, so that
    // branch is only reachable for it if the invariant above ever breaks, and
    // an unbounded budget is the pre-existing answer.
    let lineBudget = containerMain ?? (mainIntrinsic == .minContent ? 0 : .infinity)
    var lines = collectLines(items, wrap: s.flexWrap,
                             containerMain: lineBudget, gap: gap)
        .map { line in
            // §9.4.8's single-line clause is keyed on the container's cross size
            // being **definite**, which is the spec's own wording and not a
            // paraphrase: an indefinite one gives the line nothing to take, so
            // the line measures itself from its items exactly as a wrapped
            // line does.
            let single = s.flexWrap == .noWrap ? containerCross : nil
            return FlexLine(items: line,
                            crossSize: single ?? lineCrossSize(line),
                            crossStart: 0)
        }

    // The cross extent the items themselves imply — measured HERE, before
    // `align-content` grows the lines and before §9.4 stretches any item into
    // them, because both of those distribute the CONTAINER's extent and this
    // has to be free of it.
    //
    // `lineCrossSize(items)` rather than `lines[i].crossSize`: under `nowrap`
    // with a DEFINITE container cross size, the line's cross size *is*
    // `containerCross` (§9.4.8's single-line clause), so reading it back would
    // answer `measureNode` with the extent it was asked about. (Under an
    // indefinite one the clause does not apply and the two agree — this is
    // about the definite case, which is the one that could be wrong.)
    let contentCross = lines.reduce(0.0) { $0 + lineCrossSize($1.items) }
                     + crossGap * Double(lines.count - 1)

    // CSS Flexbox §9.6.15 / §8.4 — `align-content`. The lines' own cross sizes
    // are now known, so whatever cross space they leave over is distributed
    // among them here, before any line is positioned.
    //
    // The leftover counts the gaps BETWEEN lines: `crossGap` is space the
    // container has already spent, not space `align-content` may spend again.
    // (`lineContentSize` computes exactly this shape for the main axis, but it
    // takes `[Double]` and is shared with Grid; mapping the lines through it
    // reads worse than the one-line reduce.)
    //
    // **`nowrap` is untouched by construction, not by a special case.** Its
    // single line's cross size IS `containerCross` (§9.4.8's single-line
    // clause, above), so `leftoverCross` is exactly 0, every one of the seven
    // values then yields zero offsets and zero growth, and every golden
    // committed before wrapping stays byte-identical. CSS reaches the same
    // place by a different route — §8.4 says the property "has no effect on a
    // single-line flex container" — so there is nothing to key on `flexWrap`
    // here, and keying on it would be a second, silently divergent definition
    // of what a single line is.
    //
    // **The initial value is `stretch`, not `flex-start`.** This milestone's
    // FIRST task shipped
    // cross-start packing as a scoped divergence with a test naming WebKit's
    // numbers; this closes it, and that test is deleted rather than inverted.
    let align = s.alignContent ?? .stretch
    let usedCross = lines.reduce(0.0) { $0 + $1.crossSize }
                  + crossGap * Double(lines.count - 1)
    // No given cross extent, no leftover: `align-content` distributes space the
    // container has and an indefinite container has none to distribute. (It is
    // 0 rather than "skip the rest", so the `stretch` growth and the offsets
    // below stay one code path.)
    let leftoverCross = containerCross.map { $0 - usedCross } ?? 0

    // **Grow the lines BEFORE resolving item stretch, not after.** §9.4's item
    // stretch fills the item's line; if the line grows afterwards, every
    // stretched item on it is short by exactly this amount and sits with slack
    // below it — a composition that is invisible in any fixture whose children
    // all carry explicit cross sizes. `flex_wrap_align_content_stretch` and
    // `aStretchedLineChangesWhatItsStretchedItemsFill` both redden if the two
    // are swapped.
    let growth = lineStretchAmount(align, freeSpace: leftoverCross, lineCount: lines.count)
    if growth != 0 {
        for i in lines.indices { lines[i].crossSize += growth }
    }
    let lineOffsets = distributeLines(align, freeSpace: leftoverCross, lineCount: lines.count)

    // Lines stack from the container's cross-start, separated by `crossGap`
    // plus whatever `align-content` inserts between them, starting
    // `lineOffsets.leading` in. Under `stretch` both offsets are 0 and the
    // growth above has already consumed the leftover.
    //
    // **`crossCursor` is FLEX-relative, not physical** — the same discipline
    // `positionItems`' main-axis `cursor` follows. Under `wrap-reverse` the
    // whole cross axis is flipped, and this loop is deliberately unaware of
    // that: `positionItems` converts, at the one point a physical coordinate
    // is derived. Flipping here instead would leave the per-item
    // `crossAxisOffset` unflipped, which is CSS's other half — see
    // `positionItems`.
    var crossCursor: Double = lineOffsets.leading
    var contentMain: Double = 0
    for i in lines.indices {
        // Between lines only — a trailing gap would be as wrong here as it is
        // on the main axis, and unlike `positionItems`' cursor this one is
        // observable: it feeds `crossCursor` for the next line.
        if i > 0 { crossCursor += crossGap + lineOffsets.between }

        // §9.4 — resolve stretch NOW, against this line, not against the
        // container. `collectItems` recorded eligibility and the min/max
        // clamps; the extent is the one thing only the line knows.
        for j in lines[i].items.indices where lines[i].items[j].stretchEligible {
            let item = lines[i].items[j]
            let availableCross = lines[i].crossSize - item.marginCross.leading - item.marginCross.trailing
            lines[i].items[j].crossSize = clamp(availableCross, min: item.minCross, max: item.maxCross)
        }

        // §9.7 itself is untouched (`ResolveFlexibleLengths.swift` gains no
        // margin awareness) — instead the budget it grows/shrinks into is
        // shrunk by the items' total margin before the call, exactly the way
        // `gap` already shrinks it inside that function. That is sound because
        // every margin here is a fixed (non-flexible) amount: `containerMain' =
        // containerMain - totalMargin` makes `containerMain' - totalGap -
        // sum(targets)` equal `containerMain - totalGap - sum(outerSizes)`, the
        // real leftover space, for any split of `targets` the freeze loop
        // produces. `positionItems` still uses the real, un-shrunk
        // `containerMain` for its own free-space math (`justify-content`),
        // because it distributes space around the outer (margin-inclusive)
        // boxes, not the reduced budget.
        //
        // **Per line, and the extent is the CONTAINER's main size, not the
        // line's.** Each line flexes into the full container main extent
        // independently — that is what makes a wrapped row's second line able
        // to grow into space the first line had no room for — so only the
        // margin total is line-local.
        let totalMargin = lines[i].items.reduce(0.0) { $0 + $1.marginMain.leading + $1.marginMain.trailing }
        if let containerMain {
            resolveFlexibleLengths(tree, items: &lines[i].items,
                                   containerMain: containerMain - totalMargin, gap: gap)
        } else {
            // §9.7 against an indefinite main size: the free space is
            // indefinite, so there is nothing to grow into and nothing to
            // shrink out of, and every item keeps the size §9.7.2 would freeze
            // it at — its hypothetical main size, i.e. its flex base size
            // clamped to its own min/max. `flex-grow` does not apply.
            //
            // Written here rather than by handing `resolveFlexibleLengths` an
            // optional: passing it `.infinity` is what diverged its freeze loop
            // (`inf - inf` and `inf * 0` are NaN, no item ever gets a
            // resolvable violation, and it `assertionFailure`s out of the
            // process), and passing the line's own content total would send the
            // sub-one clause down a path whose answer depends on factors that
            // cannot apply.
            for j in lines[i].items.indices {
                lines[i].items[j].targetMainSize = lines[i].items[j].hypotheticalMainSize
                lines[i].items[j].frozen = true
            }
        }

        // Where `positionItems` used to be called from. The line records the
        // cursor instead and `placeNode` positions every line once this loop
        // has finished, so that `measureNode` can run the same loop and write
        // nothing.
        lines[i].crossStart = crossCursor

        // The main extent this line's items occupy once flexed — the same
        // quantity `positionItems` computes as `content` for `justify-content`,
        // margins and gaps included. The container's content main size is the
        // widest line's, exactly as its cross size is the sum of all of them.
        contentMain = max(contentMain, lineContentSize(
            lines[i].items.map { $0.marginMain.leading + $0.targetMainSize + $0.marginMain.trailing },
            gap: gap))

        crossCursor += lines[i].crossSize
    }

    let contentSize = isRow ? SizeD(width: contentMain, height: contentCross)
                            : SizeD(width: contentCross, height: contentMain)
    return ContainerLayout(
        lines: lines,
        contentSize: contentSize,
        edges: box.edges,
        // An axis with no given extent shrinks to fit — see `box`'s own comment.
        box: (box.origin, SizeD(width: box.size.width ?? contentSize.width,
                                height: box.size.height ?? contentSize.height)),
        stackItems: [])
}

/// A `.stack` container: every child at its own size, the container at the
/// maximum of them on each axis.
///
/// **No main axis, so no §9.7.** There is no flex base size, no freeze loop, no
/// line breaking and no distribution — each child is measured once against the
/// space the stack itself was offered, and the container reports the largest.
///
/// **`box.size` is the ONLY basis a stack child's percentage resolves against,
/// and it is `nil` on an axis the stack itself has no extent on** — Task 1's
/// probe measured this directly (through the equivalent flex shape, since this
/// path did not exist yet): during the intrinsic pass `box.size` is
/// `(nil, nil)`, a `width: 50%` child is unresolvable and contributes 0 exactly
/// as an `auto` childless box does; during placement `box.size` is definite and
/// the same child resolves the ordinary way. That is why each axis below is
/// resolved independently against `box.size`, never against a literal
/// `.definite` extent invented for the indefinite case.
private func layOutStack(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    box: (origin: (Double, Double), size: OptionalSizeD, edges: SizeD)
) -> ContainerLayout {
    let rootFontSize = ctx.rootFontSize

    // A literal `auto` is measured from the child's own content (a stack does
    // not stretch, so this is always `.maxContent` — shrink-wrap, never fill).
    // Anything else that fails to resolve — a percentage against `box.size`'s
    // `nil` — is 0, not content-measured: that is `resolveNodeSize`'s rule
    // elsewhere in this file, and per its comment there it is WebKit's too.
    // Returning `nil` here is the signal "this axis needs measuring".
    //
    // `lower`/`upper` clamp the resolved value exactly as `resolveNodeSize`
    // clamps its own `axis` closure — a stack child is not exempt from its own
    // `minSize`/`maxSize` just because it has no flex algorithm to run them
    // through. Review found this unclamped in the first round: nothing could
    // reach `display: .stack` yet to notice, but Task 5 makes `Stack` public,
    // and from that commit a `.minWidth(_:)` on a stack child would otherwise
    // compile and silently do nothing — the exact "declared but inert" trap
    // CLAUDE.md's table exists to catch, closed here before it opens rather
    // than after.
    func resolvedAxis(_ dim: Dimension, basis: Double?, lower: Double?, upper: Double?) -> Double? {
        if case .auto = dim { return nil }
        let resolved = resolveDimension(dim, against: basis, rootFontSize: rootFontSize) ?? 0
        return clamp(resolved, min: lower, max: upper)
    }

    var items: [StackItem] = []
    var maxWidth = 0.0
    var maxHeight = 0.0

    for kid in tree.children(container) where tree.style(kid).display != .none {
        let ks = tree.style(kid)
        // Resolved against `box.size` — the stack's own content box, the same
        // basis the size itself resolves against — exactly as `collectItems`
        // resolves an item's cross min/max against `containerCross` before
        // using them to clamp `ownCross`.
        let minWidth = resolveDimension(ks.minSize.width, against: box.size.width, rootFontSize: rootFontSize)
        let maxWidthBound = resolveDimension(ks.maxSize.width, against: box.size.width, rootFontSize: rootFontSize)
        let minHeight = resolveDimension(ks.minSize.height, against: box.size.height, rootFontSize: rootFontSize)
        let maxHeightBound = resolveDimension(ks.maxSize.height, against: box.size.height, rootFontSize: rootFontSize)

        let knownWidth = resolvedAxis(ks.size.width, basis: box.size.width, lower: minWidth, upper: maxWidthBound)
        let knownHeight = resolvedAxis(ks.size.height, basis: box.size.height, lower: minHeight, upper: maxHeightBound)

        let size: SizeD
        if let knownWidth, let knownHeight {
            // Both axes resolved from the child's own style — no need to run
            // the child's own layout to size it; `positionStackItems` (Task 3)
            // recurses into it once it has a final origin.
            size = SizeD(width: knownWidth, height: knownHeight)
        } else {
            let measured = measureNode(
                ctx, tree, kid,
                known: OptionalSizeD(width: knownWidth, height: knownHeight),
                available: AvailableSpaceSize(
                    width: knownWidth.map { .definite($0) } ?? .maxContent,
                    height: knownHeight.map { .definite($0) } ?? .maxContent),
                containingBlockWidth: box.size.width)
            // A content-measured axis is clamped here, after measuring — the
            // same order `collectItems`' `ownCross` uses, and CSS's own: min/max
            // bounds the USED size regardless of how it was computed, so a
            // measured axis needs the clamp exactly as much as a declared one
            // (`knownWidth`/`knownHeight` were already clamped by
            // `resolvedAxis` above when they came back non-nil, so this `??`
            // only ever runs the clamp on the axis that was actually measured).
            size = SizeD(width: knownWidth ?? clamp(measured.width, min: minWidth, max: maxWidthBound),
                         height: knownHeight ?? clamp(measured.height, min: minHeight, max: maxHeightBound))
        }

        items.append(StackItem(node: kid, size: size))
        maxWidth = max(maxWidth, size.width)
        maxHeight = max(maxHeight, size.height)
    }

    let contentSize = SizeD(width: maxWidth, height: maxHeight)
    return ContainerLayout(
        lines: [],
        contentSize: contentSize,
        edges: box.edges,
        // An axis with no given extent shrinks to fit — see `box`'s own comment
        // on `ContainerLayout`, and `layOutChildren`'s flex return above, which
        // does the same thing for the same reason.
        box: (box.origin, SizeD(width: box.size.width ?? contentSize.width,
                                height: box.size.height ?? contentSize.height)),
        stackItems: items)
}

/// Lay out one container: collect its items, resolve flexible lengths, position
/// — and recurse into every child.
///
/// **The only entry point that writes layout.** `measureNode` runs the same
/// sizing work through `layOutChildren` and writes nothing; the split is what
/// lets a subtree be asked its size speculatively.
func placeNode(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    origin: (Double, Double),
    size: SizeD,
    containingBlockWidth: Double?
) {
    ctx.enter(node)
    defer { ctx.leave() }

    // Definite on both axes: `placeNode` is only ever called for a node whose
    // size is already decided — `computeLayout` resolves the root's and
    // `positionItems` has just written each item's rect.
    let laid = layOutChildren(ctx, tree, node,
                              containerSize: OptionalSizeD(width: size.width,
                                                           height: size.height),
                              // Real layout asks no intrinsic question: both
                              // axes above are definite, so there is nothing
                              // for a mode to answer.
                              intrinsic: .unspecified,
                              containingBlockWidth: containingBlockWidth)
    // The items' origin is this container's own origin plus its leading padding
    // and border. `laid.box.origin` is that leading edge alone — the container's
    // position is placement data and `layOutChildren` never sees it.
    let childOrigin = (origin.0 + laid.box.origin.0, origin.1 + laid.box.origin.1)

    for line in laid.lines {
        positionItems(ctx, tree, node, items: line.items,
                      lineCross: line.crossSize, lineCrossStart: line.crossStart,
                      containerOrigin: childOrigin,
                      containerSize: laid.box.size)
    }
    // `laid.lines` is empty for a stack and `laid.stackItems` is empty for a
    // flex container (each is honest about what it holds — see
    // `ContainerLayout`), so exactly one of these two loops ever does
    // anything for a given node.
    if !laid.stackItems.isEmpty {
        positionStackItems(ctx, tree, node, items: laid.stackItems,
                           containerOrigin: childOrigin,
                           containerSize: laid.box.size)
    }
}

/// Places a `.stack` container's children, each aligned independently on both
/// axes within the container's content box, and recurses into each.
///
/// **A separate function rather than a branch inside `positionItems`.** That one
/// is dense with flex-specific work — `justifyContent` distribution, gap
/// arithmetic, `wrap-reverse`'s cross-axis flip and §9.4.2's flex-relative
/// start/end mapping — none of which a stack has. Sharing it would mean
/// threading a "there is no main axis" flag through all of it.
///
/// `alignItems` is the block (vertical) axis and `justifyItems` the inline
/// (horizontal) one, unconditionally: a stack does not read `flexDirection`, so
/// there is no axis swap to apply.
private func positionStackItems(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: [StackItem],
    containerOrigin: (Double, Double),
    containerSize: SizeD
) {
    // `nil` reads as CSS's `stretch` on both axes, matching `alignItems`'s
    // existing convention. `Stack.init` always writes an explicit value; a
    // hand-built `Style` may not.
    let s = tree.style(container)
    let vertical = s.alignItems ?? .stretch
    let horizontal = s.justifyItems ?? .stretch

    for item in items {
        var size = item.size
        if horizontal == .stretch { size.width = containerSize.width }
        if vertical == .stretch { size.height = containerSize.height }

        let x: Double
        switch horizontal {
        case .start, .stretch: x = 0
        case .center:           x = (containerSize.width - size.width) / 2
        case .end:               x = containerSize.width - size.width
        }

        let y: Double
        switch vertical {
        case .flexStart, .stretch: y = 0
        case .center:                y = (containerSize.height - size.height) / 2
        case .flexEnd:                y = containerSize.height - size.height
        // `baseline` falls back to the start edge, exactly as it does in
        // `crossAxisOffset` — the engine cannot see an item's baseline at all,
        // because a `MeasureFunction` returns a `SizeD`. See CLAUDE.md's inert
        // table row for what is missing.
        case .baseline:              y = 0
        }

        let origin = (containerOrigin.0 + x, containerOrigin.1 + y)
        tree.setLayout(item.node, LayoutRect(x: origin.0, y: origin.1,
                                             width: size.width, height: size.height))
        // `containerSize` here is the stack's own content box — the item's
        // containing block — exactly as `positionItems` passes it for a flex
        // item, and for the same reason (percentage padding/border resolve
        // against it).
        placeNode(ctx, tree, item.node, origin: origin, size: size,
                  containingBlockWidth: containerSize.width)
    }
}

/// The size `node` reports for itself, **without writing any layout**.
///
/// A leaf answers from its `MeasureFunction`; a container answers by running the
/// flex algorithm over its children and returning the border box that implies.
/// Callers cannot tell which happened, which is the whole point: the four sites
/// that substitute a constant for a container's content size (listed below, and
/// in the content-sizing design spec §1) become one call that works for both.
///
/// **Purity is not enforced by the type system.** A `setLayout` added anywhere
/// below this function would return the right size and pass every golden;
/// `measuringWritesNoLayout` is the guard.
///
/// **The four constant-substituting sites now call this, and that is what makes
/// it load-bearing rather than decorative.** They are `flexBaseSize`'s §9.2
/// content branch, `collectItems`' CSS Sizing §4.5 automatic minimum,
/// `collectItems`' `auto` cross size, and `resolveRootSize`'s `auto` axis with
/// no offered extent. This doc previously said "nothing in `Sources/` calls
/// this yet"; the sentence is kept in the negative because its *consequences*
/// changed with it — the stack cost of one tree level roughly quadrupled when a
/// real recursion started running through here, and `measuringWritesNoLayout`
/// went from a property nobody could violate to the only guard on a path every
/// layout takes. **`LayoutContext.maxDepth` is 64 and stayed 64** (ruling
/// CS-L): it was dropped to 16 for one commit to fit the stack a test harness
/// happened to hand over, which would have trapped on an ordinary
/// `Column { Row { Box { … } } }`; the test sizes its own 4 MB thread instead.
///
/// Two limits that a caller inherits, named here because none of them is
/// visible from the signature:
///
/// 1. **`.minContent` and `.maxContent` are no longer indistinguishable for a
///    container** — this doc said they were, and the fix is the `intrinsic`
///    argument below. Both still leave the axis *indefinite*, which is why the
///    correction is worth keeping: the question does not survive in
///    `containerSize`, it survives beside it. It reaches **three** places:
///    `flexBaseSize`'s content branch in the MAIN axis (an item's base size is
///    its contribution under the container's own question), the same branch's
///    CROSS axis, and `collectLines`' budget (§9.9.1.1: under min-content each
///    item lines alone). `IntrinsicModeTests.swift` kills each independently —
///    one test per site, verified by reverting each site alone.
///
///    **This sentence has already been wrong once, and in the commit that
///    wrote it**: it said "exactly two places" and claimed two tests covered
///    them, while reverting the cross-axis edit reddened 0 of 330. Adding a
///    site here without adding the test that kills it is how that recurs.
/// 2. **`flex-grow` does not apply here, and under CSS it would.** An
///    indefinite main axis skips §9.7 (ruling CS-D) and every item keeps its
///    hypothetical main size — but CSS does not run §9.7 under intrinsic
///    sizing either: it runs **§9.9.1**, which sums max-content
///    *contributions* and lets a flex fraction grow them. The two agree only
///    while that fraction is ≤ 0. Measured on §9.9.1.1's own worked example
///    (`flex-basis: 100px`, `min-width: 0`, a `MeasureFunction` returning 200):
///    `flex-grow: 0` gives 100 here and 100 in CSS; `flex-grow: 1` gives
///    **100 here and 200 in CSS**. **The "unreachable in production by
///    mechanism" clause that stood here has expired, and it expired the way
///    taxonomy shape 10 predicts.** It read: `flexBaseSize`'s content branch is
///    the only route to a contribution larger than the base size, it needs a
///    non-nil `tree.measure(item)`, and `newLeaf` — the only thing that
///    attaches one — has no caller in `Sources/`. M2's `Text` is that caller,
///    so `Column { Text(…).flexGrow(1) }` inside a container that is being
///    *measured* is squarely in the region this paragraph describes. The
///    arithmetic below is unchanged and was **not** re-measured against a text
///    leaf; whoever needs the answer there owes a measurement rather than a
///    reading of this comment. **Still
///    true after the intrinsic query landed, and still true after the four
///    sites were wired** — re-measured both times rather than assumed. Wiring
///    put the content branch in the path and moved nothing here: the worked
///    example is 100 under `flex-grow: 0` and 100 under `flex-grow: 1`, at both
///    `.minContent` and `.maxContent`, because a definite `flex-basis: 100px`
///    wins at `flexBaseSize`'s FIRST branch and the rewired content branch is
///    never reached on that shape. Spelling the same example with
///    `flex-basis: auto` does reach it and gives 200 for both grow values —
///    the flex fraction is ≤ 0 there, which is precisely the region where the
///    substitute and §9.9.1 agree. Recorded in the content-sizing decisions doc
///    with the same numbers.
///
/// This doc used to carry a second limit — "an unbounded probe leaves a
/// `flex-grow` item's target infinite … no test here can see it". **Both halves
/// were false, and the correction stays here** because the shape is this repo's
/// most repeated one (taxonomy shape 10, a prediction about measurement dressed
/// as a fact about the code): the probe did not return infinity, it sent §9.7's
/// freeze loop past its pass cap and `assertionFailure`d the process; and three
/// ten-line tests see it, one each for `flex-grow`, a percentage size and a
/// percentage `gap`. Ruling CS-D and `MeasureNodeTests.swift`'s indefinite
/// group are what replaced it.
func measureNode(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    known: OptionalSizeD,
    available: AvailableSpaceSize,
    containingBlockWidth: Double?
) -> SizeD {
    ctx.enter(node)
    defer { ctx.leave() }

    let key = LayoutContext.MeasureKey(
        node: node, knownWidth: known.width, knownHeight: known.height,
        availableWidth: available.width, availableHeight: available.height,
        containingBlockWidth: containingBlockWidth)
    if let hit = ctx.cachedMeasure(key) { return hit }

    if let measure = tree.measure(node) {
        let result = measure(known, available)
        ctx.storeMeasure(key, result)
        return result
    }

    // A container: run the algorithm and report what the children imply,
    // letting a known size on either axis win over the measured one.
    //
    // `probe` is a BORDER box, like every `containerSize` `layOutChildren`
    // takes — which is why `known` can be returned unchanged below while the
    // measured half has to have `edges` added back to it. An axis with neither
    // a known size nor a definite available space stays `nil`: **indefinite**,
    // not infinite (ruling CS-D).
    let probe = OptionalSizeD(width: known.width ?? definiteExtent(available.width),
                              height: known.height ?? definiteExtent(available.height))
    // What `probe` throws away, carried alongside it. `definiteExtent` maps both
    // intrinsic cases to `nil`, so without this the container's question dies on
    // the line above and every child is asked max-content whatever the container
    // was asked. `IntrinsicQuery.init(known:available:)` is what makes "a
    // non-nil mode means a `nil` extent" true rather than remembered.
    let intrinsic = IntrinsicQuery(known: known, available: available)
    let laid = layOutChildren(ctx, tree, node, containerSize: probe,
                              intrinsic: intrinsic,
                              containingBlockWidth: containingBlockWidth)

    let result = SizeD(width: known.width ?? (laid.contentSize.width + laid.edges.width),
                       height: known.height ?? (laid.contentSize.height + laid.edges.height))
    ctx.storeMeasure(key, result)
    return result
}

/// The number an available space carries, if it carries one.
///
/// **`.minContent` and `.maxContent` return `nil`, and the first version of this
/// returned `.infinity` instead.** That was not a smaller mistake than it looks:
/// a `flex-grow` item's target became `inf`, a percentage width became `inf`, a
/// percentage `gap` turned the line's budget into `inf - inf`, and each sent §9.7's
/// freeze loop past its pass cap — which `assertionFailure`s, killing the test
/// process mid-run with no summary line rather than returning a wrong number.
/// Ruling **CS-D**: indefinite is `nil` and the CSS rules for an indefinite
/// basis then apply on their own.
private func definiteExtent(_ a: AvailableSpace) -> Double? {
    if case .definite(let v) = a { return v }
    return nil
}

/// Which intrinsic size a speculative measure is asking for, on one axis.
///
/// **A separate enum rather than `AvailableSpace?`, and that is the point of
/// it.** `AvailableSpace` can also be `.definite`, and a definite extent is not
/// an intrinsic question — it reaches the recursion as `containerSize`'s
/// extent, where every existing rule already consumes it. Storing one here
/// would make "which of the two wins" a precedence rule someone has to
/// remember; this type cannot express the collision at all.
enum IntrinsicMode: Sendable, Hashable {
    case minContent
    case maxContent

    /// `nil` for `.definite` — see the type's own note.
    init?(_ space: AvailableSpace) {
        switch space {
        case .definite: return nil
        case .minContent: self = .minContent
        case .maxContent: self = .maxContent
        }
    }

    /// Back to the vocabulary a `MeasureFunction` speaks, for the one consumer
    /// that hands the question on to a leaf (`flexBaseSize`'s content branch).
    var availableSpace: AvailableSpace {
        switch self {
        case .minContent: return .minContent
        case .maxContent: return .maxContent
        }
    }
}

/// The intrinsic question a container is being asked, per axis — `nil` on an
/// axis meaning there is none.
///
/// **This exists because `measureNode`'s probe destroys the question.**
/// `definiteExtent` maps both `.minContent` and `.maxContent` to `nil`, and
/// below that line the only size type threaded is `OptionalSizeD`, which cannot
/// say *why* an axis is indefinite. `AvailableSpaceSize` is not threaded down
/// instead because it would then carry the definite extents a second time,
/// beside `containerSize`, with nothing keeping the two agreed.
///
/// **The invariant, which `init(known:available:)` establishes rather than
/// documents:** an axis has a mode here **iff** that axis of the probe is
/// `nil`. A known extent wins outright (it is what a `MeasureFunction`'s
/// `known` means) and clears the mode; a definite available space produces no
/// mode to begin with. `contentBox` maps `nil` to `nil` per axis, so the
/// invariant survives into the content box every consumer actually reads.
/// That is what lets the two consuming sites be written as "the extent if
/// there is one, otherwise the question" with no third case.
///
/// Named `unspecified` for the neither-axis case to match
/// `OptionalSizeD.unspecified`, and for the same reason: a static `.none` on a
/// non-`Optional` type shadows `Optional.none` at call sites.
struct IntrinsicQuery: Sendable, Hashable {
    var width: IntrinsicMode?
    var height: IntrinsicMode?

    /// **Private on purpose.** CS-H's whole argument is that the invariant
    /// above is *established* by `init(known:available:)` rather than
    /// remembered — which is only true if that is the sole door that can build
    /// an arbitrary combination. `.unspecified` is the one caller here.
    private init(width: IntrinsicMode?, height: IntrinsicMode?) {
        self.width = width
        self.height = height
    }

    init(known: OptionalSizeD, available: AvailableSpaceSize) {
        self.width = known.width == nil ? IntrinsicMode(available.width) : nil
        self.height = known.height == nil ? IntrinsicMode(available.height) : nil
    }

    /// No question on either axis: real layout, or a measure whose axes are
    /// both definite.
    static let unspecified = IntrinsicQuery(width: nil, height: nil)
}

/// Phase 1 — size every item without positioning any of them.
///
/// `intrinsic` is passed through **unresolved onto axes**, exactly as
/// `containerSize` is: `flexBaseSize` already takes `isRow:` and picks its own
/// main and cross from it, and giving it a pre-resolved pair would be a second
/// place the row/column choice is made.
private func collectItems(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerSize: OptionalSizeD,
    intrinsic: IntrinsicQuery
) -> [FlexItem] {
    let rootFontSize = ctx.rootFontSize
    let s = tree.style(container)
    let isRow = s.flexDirection.isRow
    // `nil` on an axis means the container has no given extent there (ruling
    // CS-D). Nothing in this function needed changing for it: `flexBaseSize`
    // and every `resolve*` below already take an optional basis, and a
    // percentage against `nil` is unresolvable, which is what CSS says a
    // percentage against an indefinite containing block is.
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    let parent = containerSize

    return tree.children(container)
        .filter { tree.style($0).display != .none }
        .map { kid in
            let base = flexBaseSize(ctx, tree, item: kid, isRow: isRow,
                                    containerMain: containerMain,
                                    containerCross: containerCross,
                                    intrinsic: intrinsic)

            let ks = tree.style(kid)
            // CSS Sizing §4.5's automatic minimum size. `min-width: auto` on a
            // flex item resolves to the item's **content-based** minimum — its
            // min-content size — not to 0, and emphatically **not** to its flex
            // base size. Taking the base size here is the tempting wrong answer
            // and it disables shrinking entirely: every `flex-basis: 200px` item
            // would acquire a 200px floor and refuse to give up a single pixel.
            // `anItemWithNoContentHasNoAutomaticMinimum` and
            // `shrinkIsWeightedByBaseSize` both redden if anyone tries it.
            //
            // A childless leaf with no measure function has no content, so its
            // automatic minimum is its own padding and border — 0 for the empty
            // divs the corpus is made of, and it shrinks freely. It is a number
            // now rather than `nil` ("no floor"), which is behaviour-neutral
            // because `clamp` and §9.7.4.d's `max(0, …)` treat a 0 floor and no
            // floor identically for any non-negative size.
            //
            // **This rule was "not, and cannot yet be, browser-verified" and now
            // is, for containers.** That claim named the M2 text system as the
            // gate and was the same shape as the two CLAUDE.md rows measurement
            // has already disproved (taxonomy shape 10): a **container** item
            // has a content size with no text in it, so a nested flex container
            // whose children are wider than its shrunk main size is now floored
            // by them exactly as WebKit floors it. **The leaf half is live too
            // since M2's `Text` — what it is not is browser-verified**, and the
            // gate there is the oracle rather than the code: WebKit shapes with
            // its own font stack, so no text fixture can compare numbers with
            // this engine, which is why the corpus has none and ruling TX-B
            // treats any moved golden as a stop-and-report. The leaf half is
            // pinned by hand-written closures
            // (`automaticMinimumSizeUsesContentSizeNotFlexBasis`) and, end to
            // end, by `TextMeasureTests`' CoreText oracles.
            // `flex_row_explicit_min` covers **explicit** `min-width` alone.
            //
            // **Ruling FS-3 — half the rule is missing, and since content
            // sizing that is a measured divergence rather than a dormant one.**
            // §4.5's automatic minimum is `min(specified size suggestion,
            // content size suggestion)`; only the content suggestion is
            // implemented. The two differ exactly when a measured content size
            // exceeds a specified one — which needed something to measure
            // content, and a **container** now does. This comment used to say
            // the two "can never be distinguished until M2"; the gate was never
            // the text system, it was the same recursive subtree measurement
            // that closed the auto-cross gap, and it has arrived.
            //
            // Measured against the oracle: `#root { width: 150px }` holding
            // `.a { display: flex; width: 100px }` whose child is 200 wide, and
            // `.b { width: 100px }`, gives **WebKit `a` 100 / `b` 50** — `.a`
            // floors at `min(100, 200)`, its own specified width — and **this
            // engine `a` 200 / `b` 0**, overflowing the root, because the floor
            // here is the content suggestion alone. The differential was run
            // rather than predicted: `.a { width: 130px }` moves WebKit to
            // 130 / 20 while this engine does not move at all, and
            // `min-width: 0` on `.a` gives 75 / 75 in both.
            //
            // **Deliberate, recorded, and pinned** — CLAUDE.md's divergence 5
            // and `aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit`, which
            // is the ONLY pin, because a fixture would encode this engine's
            // answer as correct and a future fix should move nothing in the
            // corpus (the same footing as WebKit's flex sub-one clause). Adding
            // the specified suggestion here changes an item's floor, which
            // §9.7's freeze loop consumes and every ancestor then sees as a
            // different stored size: sizing-plan reach, like ruling BM-4's.
            let minDim = isRow ? ks.minSize.width : ks.minSize.height
            let minMain: Double? = {
                if case .auto = minDim {
                    // **A FOURTH site with hardcoded intrinsic modes, and it
                    // stays hardcoded.** §4.5's content size suggestion IS the
                    // item's min-content size in the main axis, whatever the
                    // container was asked — so unlike `flexBaseSize`'s content
                    // branch, this probe must not take `intrinsic`.
                    //
                    // Worth knowing before measuring a column: the CROSS axis
                    // here is max-content, so this floor is computed from the
                    // item's widest content even when the container is being
                    // asked for its min-content width. A column whose item
                    // reports 33 tall at min-content width and 77 at
                    // max-content gets a floor of 77 and answers 77 — which
                    // looks exactly like the cross-axis query failing to
                    // propagate, and hid it from the first probe written for
                    // `theCrossAxisOfTheQueryReachesTheChildToo`. That test
                    // sets `min-height: 0` to switch this off.
                    //
                    // **`known: .unspecified` is deliberate and is what keeps
                    // ruling FS-3 honest.** §4.5's automatic minimum is
                    // `min(specified size suggestion, content size suggestion)`
                    // and only the content half is implemented; handing the
                    // item's own `width`/`height` down as `known` here would
                    // silently substitute the *specified* suggestion for the
                    // content one. Measured against WebKit: a `width: 120px`
                    // empty div shrinks to 75 in a row that overflows, because
                    // its content suggestion is 0 and 0 wins the `min`.
                    let probe = measureNode(ctx, tree, kid, known: .unspecified,
                                            available: AvailableSpaceSize(
                                                width: isRow ? .minContent : .maxContent,
                                                height: isRow ? .maxContent : .minContent),
                                            containingBlockWidth: containerSize.width)
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
            // `containerSize` here is the CONTENT box (the BOX MODEL milestone
            // threads it into `collectItems`), not the border box.
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
            // **Eligibility is decided here; the size is not.** Stretch fills
            // the ITEM'S LINE, and this phase runs before lines exist —
            // `collectLines` breaks on hypothetical main sizes, and
            // `lineCrossSize` measures the line from the items' *unstretched*
            // outer cross sizes, so computing a stretched size here would feed
            // the line's own measurement back into itself. Until wrapping
            // landed the two were indistinguishable: there was exactly one
            // line and its cross size WAS `containerCross`. Everything below
            // records what the line phase needs, and
            // `layOutChildren` does the arithmetic once per line.
            //
            // The arithmetic it does, unchanged in substance, is: **stretch
            // fills the line's cross extent MINUS the item's own cross
            // margins**, then clamps what is LEFT to the item's min/max — not
            // the other way around. `min`/`max-height` describe the border box,
            // so subtracting margins first and clamping second is the only
            // ordering that answers "how big can the border box be" correctly;
            // clamping the full line cross first and subtracting margins after
            // would let a `max-height` cap the MARGIN box instead, and
            // `stretchWithMaxHeightClampsTheBorderBoxNotTheMarginBox` pins the
            // ordering against WebKit including a `max-height` probe.
            //
            // **Content-based cross sizing is the other half of §9.4, and it is
            // implemented now** — see `ownCross` below. It was missing for four
            // milestones: **any** item with an `auto` cross size got 0 here,
            // stretched or not, because `lineCrossSize` measures the line from
            // this value *before* stretch runs (ruling **WR-4**). A line whose
            // items were all auto-cross measured 0 tall, so it collapsed and
            // every line after it shifted up, and under `align-content: stretch`
            // the bad line corrupted the leftover and moved *every* line.
            //
            // The history is kept because the claim that guarded it was wrong
            // twice: this comment once said the item had to be non-stretched,
            // and that "every fixture in the corpus is an empty div, so nothing
            // catches it — wait for M2". A **nested flex container** has a
            // content cross size with no text in it, which is what
            // `autoCrossNestedContainerMeasuresItsLineLikeWebKit` measured as a
            // divergence and now pins as an agreement;
            // the gate was never text metrics but recursive subtree
            // measurement, which is what `measureNode` now supplies.
            let crossDim = isRow ? ks.size.height : ks.size.width
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
            let align = resolvedAlignment(ks, container: s)
            var stretchEligible = false
            if align == .stretch, case .auto = crossDim { stretchEligible = true }
            // Resolved against `containerCross` — the containing block's cross
            // extent — NOT against the line's, which does not exist yet and
            // would in any case be the wrong basis for a percentage min/max.
            //
            // Resolved BEFORE `ownCross` below, which needs them: an `auto`
            // cross size is measured and then clamped by the item's own cross
            // min/max, exactly as `resolveNodeSize` clamps a declared one.
            let minCross = resolveDimension(isRow ? ks.minSize.height : ks.minSize.width,
                                            against: containerCross, rootFontSize: rootFontSize)
            let maxCross = resolveDimension(isRow ? ks.maxSize.height : ks.maxSize.width,
                                            against: containerCross, rootFontSize: rootFontSize)

            // §9.4 step 7 — the item's HYPOTHETICAL cross size: "perform layout
            // with the used main size and the available space, treating auto as
            // fit-content". This is the third of the four sites that
            // substituted a constant, and the constant was `resolveNodeSize`'s
            // 0 for an unresolvable axis.
            //
            // Three choices here, each measured against WebKit rather than
            // derived, because each has a plausible wrong answer:
            //
            // 1. **Only a literal `auto` is measured.** A *percentage* cross
            //    size against an indefinite `containerCross` is also
            //    unresolvable, and CSS says an unresolvable percentage behaves
            //    as auto — but WebKit does not content-size it: a
            //    `height: 50%` child of an auto-height flex item measures **0**
            //    there, not its content. So the switch is on the declaration,
            //    not on whether `resolveNodeSize` came back with something.
            // 2. **The main axis is passed as `known`, at the item's
            //    HYPOTHETICAL main size, not its flex base size.** "The used
            //    main size" at this point in §9.4 is the base size already
            //    clamped by the item's own main min/max, which is exactly
            //    `hypothetical`. They differ only when a min/max binds, which
            //    is precisely when the difference matters.
            // 3. **The cross axis is offered `.maxContent`, never
            //    `.definite(containerCross)`.** `measureNode` turns a definite
            //    available extent into the measured node's OWN extent (its
            //    `probe`), so offering the container's cross extent would make
            //    the item that big and let its children's cross percentages
            //    resolve against it — WebKit resolves them against nothing
            //    (see 1). It also does not clamp to the container: an item
            //    whose content is 150 tall in an 80-tall row measures **150**
            //    in WebKit and overflows.
            //
            //    **That measurement is sound and the inference drawn from it —
            //    "which is max-content, not fit-content" — is not, which M2's
            //    text leaf exposed.** The probe used a *rigid* box, where
            //    min-content == max-content, so fit-content
            //    (`min(max(min-content, available), max-content)`) and
            //    max-content give the same 150 and the probe cannot tell them
            //    apart. Re-measured on the mirror case, a column 80 wide
            //    holding an auto-width item whose content is a rigid 150x30:
            //    WebKit **150x30** and this engine **150x30** — agreeing, and
            //    for the same reason.
            //
            //    **The measurement stands; the inference "which is max-content,
            //    not fit-content" does not, and the rule it was reaching for is
            //    an INLINE-vs-BLOCK distinction (ruling TX-H).** CSS sizes an
            //    `auto` **inline** axis by shrink-to-fit and an `auto` **block**
            //    axis by content height. A row's cross axis IS the block axis,
            //    so max-content is right there and the 150 above is what both
            //    rules give. A **column's** cross axis is the INLINE axis, and
            //    there the two rules separate as soon as the item's two
            //    intrinsic widths differ — text, or a wrapping container. That
            //    is what the `!isRow` branch below implements, and what
            //    divergence 6 used to be.
            //
            // §10.3.5's fit-content, spelt out because three of its four terms
            // were measured against WebKit rather than derived:
            //
            //   `min(max(min-content, available), max-content)`
            //
            // - **`available` is the container's cross extent MINUS the item's
            //   own cross margins.** A wrapping child of a 120-wide centring
            //   column with `margin-left: 10px; margin-right: 6px` measures
            //   **104** in WebKit, not 120. This is the auto-cross x margins
            //   composition, and it is the pair that existed in the engine and
            //   in no fixture — `flex_column_fit_content_margins` is now the
            //   fixture.
            // - **The `max` with min-content really is a floor and it
            //   overflows.** Four 50-wide items in a **30**-wide centring
            //   column measure `50x80` at `x = -10` in WebKit, not `30x…`.
            //   `flex_column_fit_content_floor`.
            // - **`min` with max-content is why nothing above the fit-content
            //   regime moves**: when `available >= max-content` the second
            //   probe is never taken, which is why no existing golden moves.
            //
            // The `.minContent` probe is taken **only** when the max-content
            // answer overflows `available`, so the ordinary case still costs
            // exactly one measure — which matters here, because this site
            // already fires for every item on every layout.
            //
            // **`intrinsic` is consulted for the indefinite case, and that IS a
            // fourth propagation site.** Ruling CS-H's warning is against an
            // *unguarded* propagation edit, so this one is guarded: an
            // indefinite `containerCross` means the container has no cross
            // extent of its own, and CS-H's invariant is that such an axis
            // always carries a mode. Under `.minContent` the available space is
            // **0** and fit-content collapses to the item's min-content width;
            // under `.maxContent` it is infinite and nothing changes, which is
            // the whole of the old behaviour. Without it a column with an
            // `auto` width reports its *max-content* width as its min-content
            // width, and the nested case diverges: WebKit lays an auto-width
            // centring column inside a 60-wide one out at **70** — its widest
            // item — and the engine at 200. Pinned by `flex_column_fit_content_nested_auto`
            // and `theCrossAxisQueryReachesAnAutoCrossItem`.
            let ownCross: Double = {
                guard case .auto = crossDim else { return isRow ? own.height : own.width }
                let crossKnown = isRow ? OptionalSizeD(width: hypothetical, height: nil)
                                       : OptionalSizeD(width: nil, height: hypothetical)
                let mainSpace = AvailableSpace.definite(hypothetical)
                func measure(cross: AvailableSpace) -> SizeD {
                    measureNode(
                        ctx, tree, kid, known: crossKnown,
                        available: AvailableSpaceSize(width: isRow ? mainSpace : cross,
                                                      height: isRow ? cross : mainSpace),
                        containingBlockWidth: containerSize.width)
                }
                let maxContent = measure(cross: .maxContent)
                var value = isRow ? maxContent.height : maxContent.width
                if !isRow {
                    // `nil` here means "infinite", which is what max-content
                    // already answers — so the probe below is skipped.
                    let available: Double? = containerCross
                        .map { $0 - marginCross.leading - marginCross.trailing }
                        ?? (intrinsic.width == .minContent ? 0 : nil)
                    if let available, value > available {
                        value = max(measure(cross: .minContent).width, available)
                    }
                }
                return clamp(value, min: minCross, max: maxCross)
            }()

            // `targetMainSize:` here is dead — §9.7.2 overwrites it on every
            // item before it is read, and no empty-line path reaches
            // `positionItems`. It repeats `hypothetical` only because a
            // constructor must pass something; nothing depends on which value.
            // See the field's declaration.
            return FlexItem(node: kid, baseSize: base, hypotheticalMainSize: hypothetical,
                            minMain: minMain, maxMain: maxMain,
                            targetMainSize: hypothetical, crossSize: ownCross,
                            stretchEligible: stretchEligible,
                            minCross: minCross, maxCross: maxCross, frozen: false,
                            marginMain: marginMain, marginCross: marginCross)
        }
}

/// Phase 3 — assign absolute rects for **one line** and recurse.
///
/// `lineCross` and `lineCrossStart` are the line's cross extent and its offset
/// from the container's content-box cross-start. For a `nowrap` container they
/// are `containerCross` and `0`, which is what every layout in the corpus was
/// getting before wrapping existed — hence byte-identical goldens.
///
/// `containerSize` is still the container's **content box** and is still needed
/// in full: the main extent is `justify-content`'s free-space basis (each line
/// justifies into the whole container, not into itself), and the width is the
/// containing block for each item's own percentage padding, border and margin.
private func positionItems(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    items: [FlexItem],
    lineCross: Double,
    lineCrossStart: Double,
    containerOrigin: (Double, Double),
    containerSize: SizeD
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
    // document order is the one thing about this loop with a use outside it,
    // and wrapping has since cashed that in: `collectLines` breaks lines in
    // DOM order and must, because CSS assigns items to lines in document
    // order regardless of `row-reverse` — only the placement *within* a line
    // reverses. A flipped array reaching `collectLines` would put the wrong
    // items on the wrong lines, which no amount of care inside this loop
    // could undo. (Baseline grouping, still unimplemented, will want the same
    // thing.) Converting the cursor confines the reversal to the single place
    // a physical position is actually derived, rather than threading a
    // flipped item order through everything downstream of `collectItems`.
    // Verified against WebKit: a `row-reverse` + `wrap` + `gap` + margin probe
    // agrees exactly, item-for-item and line-for-line.
    let isReverse = s.flexDirection.isReverse
    // CSS Flexbox §8.3 — `wrap-reverse` flips the CROSS axis, exactly as
    // `row-reverse`/`column-reverse` flip the main one, and it is converted
    // here for the same reason: `layOutChildren`'s line cursor and
    // `crossAxisOffset`'s per-item offset are both **flex-relative**, and this
    // is the single place either becomes a physical coordinate.
    //
    // **Both halves need the flip; reversing the lines array is not enough.**
    // Measured in WebKit on a 260x300 `wrap-reverse` row holding
    // 120x40 / 120x30 / 120x90 with `align-content: flex-start`: `c` (line 1,
    // alone) at **170**, and `a` and `b` (line 0, together) at **260 and 270**.
    // `a` and `b` differ from each other despite sharing a 40-tall line
    // because each is pinned to its OWN bottom edge — that is the per-item
    // half. Reversing the array alone would put both at the line's top and
    // leave the `align-content` leading offset measured from the wrong edge.
    //
    // The two conversions below are the exact cross-axis mirrors of the main
    // axis's `containerMain - cursor - outerMain(item)`, one per nesting
    // level: the line's flipped start inside the container, and the item's
    // flipped start inside its line.
    let isCrossReverse = s.flexWrap == .wrapReverse
    let containerMain = isRow ? containerSize.width : containerSize.height
    let containerCross = isRow ? containerSize.height : containerSize.width
    // The line's PHYSICAL cross-start. Forward, the flex-relative cursor
    // already is one; reversed, the line's flex-start sits `lineCrossStart` in
    // from the container's physical cross-END, so its physical start is the
    // container's cross extent less the cursor less the line's own extent.
    let linePhysicalCrossStart = isCrossReverse
        ? (containerCross - lineCrossStart - lineCross)
        : lineCrossStart
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: containerMain,
                            rootFontSize: ctx.rootFontSize) ?? 0

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

        // CSS Flexbox §9.6 — alignment measures the item against **its own
        // line**, and `lineCrossStart` then moves the whole line to where it
        // sits on the cross axis. Before wrapping there was one line, its
        // cross size was the container's and its start was 0, so passing
        // `containerCross` here was indistinguishable from passing the line's
        // own size — which is exactly why `stretchFillsTheItemsOwnLineNotThe
        // Container` and `flex_wrap_stretch_auto_cross` had to be written to
        // make the difference observable at all.
        //
        // `crossAxisOffset` is handed the OUTER cross size — margin included
        // — because alignment (e.g. `flex-end`) measures the margin box
        // against the line, not the border box; the result is then nudged by
        // the leading cross margin to land on the border box's own origin.
        //
        // Under `wrap-reverse` the offset `crossAxisOffset` returns is
        // flex-relative and is flipped inside the line before the line's own
        // physical start is added — `align-items: flex-start` then lands the
        // item on its line's BOTTOM edge in a row, and `flex-end` on its top.
        // `center` is symmetric and does not move, which is why a
        // centre-aligned fixture can never pin this flip.
        //
        // `marginCross.leading` is added AFTER the flip and is never flipped,
        // for the same reason `marginMain.leading` is not: it is physical
        // (`margin-top` in a row), and CSS's physical margins do not follow
        // `wrap-reverse` any more than they follow `row-reverse`. The flipped
        // quantity is the whole OUTER (margin) box, so what lands at the
        // line's bottom is the margin box's bottom edge, and the border box
        // starts its own top margin further down.
        let align = resolvedAlignment(tree.style(item.node), container: s)
        let outerCross = item.marginCross.leading + item.crossSize + item.marginCross.trailing
        let flexRelativeCross = crossAxisOffset(align, itemCross: outerCross, lineCross: lineCross)
        let outerPhysicalCrossStart = isCrossReverse
            ? (lineCross - flexRelativeCross - outerCross)
            : flexRelativeCross
        let crossOffset = linePhysicalCrossStart
                         + outerPhysicalCrossStart
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
        // `containerSize` here is THIS container's content box (`placeNode`
        // passes `laid.box.size`), which is exactly the item's containing block — so
        // its width is the basis for the item's own percentage padding and
        // border. Passing `size.width` (the item's own width) instead is the
        // bug the BOX MODEL milestone's third task found: correct only when an
        // item happens to be as wide as
        // its parent's content box.
        placeNode(ctx, tree, item.node, origin: (x, y), size: size,
                  containingBlockWidth: containerSize.width)

        cursor += outerMain(item)
    }
}
