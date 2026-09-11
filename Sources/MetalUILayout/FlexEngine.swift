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
/// **The phase order is CSS Flexbox's own, and it is: size every item, break
/// into lines, then per line flex (§9.7) → re-measure a non-stretched
/// auto-cross item's fit-content size (§9.4 step 7); then measure each line
/// (§9.4.8) and the container's content cross extent; then distribute cross
/// space among the lines (`align-content`, step 9); and finally, per line,
/// stretch (step 11) and record where the line starts.** Positioning is the
/// last phase and a separate pass (`layOutChildren` sizes, `placeNode`
/// positions) so that `measureNode` can run everything up to it and write
/// nothing. Breaking uses *hypothetical* main sizes (§9.3), because §9.7 runs
/// per line and so cannot have run yet; a line's cross size is measured from
/// its items' *unstretched* outer cross sizes (§9.4.8), so it must be measured
/// after the break; `align-content: stretch` then grows those measured sizes,
/// and only after that does §9.4's item stretch fill them. Every one of those
/// orderings is circular or wrong if reversed.
///
/// **The re-measure step is ruling TX-H and its POSITION is ruling SZ-O.**
/// `collectItems` has to give every auto-cross item a first cross size before
/// any of that can run, from its hypothetical main size, but CSS Flexbox §9.4
/// step 7 actually wants it measured from the item's USED main size, which
/// only exists once §9.7 (the flex step) has resolved it — so the per-line
/// loop measures it again, for exactly the items whose main size moved. TX-H
/// landed that re-measure *after* the line and container cross extents were
/// already computed, so it corrected the item and left everything above it
/// holding the pre-flex number: a 40-tall item inside a 20-tall parent, and a
/// wrapping container's second line stacked 20pt too high, i.e. overlapping
/// siblings. SZ-O moved §9.7 and the re-measure above the line measurement,
/// which is the only reordering the fix needed — §9.7 was never part of the
/// circular chain the paragraph above describes, because it reads no
/// cross-axis quantity at all.
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
/// **One gap remains of the three this paragraph used to list, and the other
/// two closed in different milestones.** `margin: auto` still resolves to 0
/// instead of absorbing free space, and it still has a row in CLAUDE.md's
/// inert-API table. Of the departed: `inset` was "read by nothing" until the
/// absolute-positioning milestone wired it (`placeAbsolute`, below, is the
/// reader), and CSS Sizing §4.5's **specified** size suggestion was missing
/// from `collectItems`' automatic minimum (ruling FS-3) until the sizing
/// milestone's Task 6 added it — so CLAUDE.md's divergence 5 is closed and
/// `sizing_specified_suggestion` is the fixture that holds WebKit's numbers.
/// This sentence has been stale twice, in the same shape both times: a gap
/// closed elsewhere in the file and described as open here.
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
    // `resolveRootSize` below now resolves the root's own `width: 50%`
    // against this same offered extent too — but per axis, not per box: its
    // `width` resolves against `available.width` and its `height` against
    // `available.height`. The two bases are no longer different in KIND, but
    // they are still different in RULE: percentage padding and border above
    // resolve against `available.width` on every edge, vertical edges
    // included, where a box's own size percentage resolves each axis against
    // the matching axis of its containing block. A square containing block
    // cannot tell the two rules apart, which is why `flex_percent_padding_nonsquare`
    // is deliberately non-square.
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

    // The initial containing block: the root's own padding box, regardless of
    // the root's `position` — there is no ancestor to fall back to. If the
    // root's `position` happens to be `.static` (the default), `placeNode`
    // threads this straight through to the whole subtree unchanged; if it is
    // positioned, `placeNode` recomputes the identical box from `laid` and
    // this seed is never consulted. Calling `contentBox` here (the same
    // function `layOutChildren` calls internally) reuses its percentage
    // resolution rather than re-deriving it — the mistake the containing-block
    // width note above already warns about.
    let rootBox = contentBox(tree, root,
                             borderBox: OptionalSizeD(width: rootSize.width, height: rootSize.height),
                             containingBlockWidth: rootContainingBlockWidth,
                             rootFontSize: rootFontSize)
    let rootPaddingBox = ContainingBlock(
        origin: (rootBox.origin.0 - rootBox.padding.left, rootBox.origin.1 - rootBox.padding.top),
        size: SizeD(width: (rootBox.size.width ?? rootSize.width) + rootBox.padding.horizontal,
                    height: (rootBox.size.height ?? rootSize.height) + rootBox.padding.vertical))

    placeNode(ctx, tree, root, origin: (0, 0), size: rootSize,
              containingBlockWidth: rootContainingBlockWidth, containingBlock: rootPaddingBox)

    // Round last, over the finished absolute rects. Spec §5.7 designates the
    // rounded layout as the comparison space, so the engine must apply the same
    // pass the golden generator does — otherwise a fractional layout is compared
    // against a rounded one and the difference is invisible.
    roundStoredRects(tree, root)
}

/// Apply `roundLayout` to every node's stored rect, depth-first, recording each
/// node's pre-rounding width on the way.
///
/// `roundLayout` is stateless per rect — it rounds each rect's own cumulative
/// edges — so applying it node-by-node is equivalent to applying it to the whole
/// tree at once, and requires no traversal order.
///
/// **This is the only place the unrounded width still exists**, which is why the
/// recording happens here rather than at the site that wants it. `roundLayout`
/// stores `round(x + w) - round(x)`; that keeps every boundary closed on its
/// parent and is not in question, but it lands below `w` about half the time,
/// and a phase after layout that re-derives content from the stored width is
/// then asking a different question from the one the measure function answered.
/// See `LayoutTree.measuredWidth(_:)`, whose sole reader is `Text.paint`.
private func roundStoredRects(_ tree: LayoutTree, _ node: LayoutNodeID) {
    tree.setMeasuredWidth(node, tree.layout(node).width)
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
    /// space *from* this, not from the clamped size.
    ///
    /// **Not §9.7.4.c's shrink weight**, because it may hold the item's own
    /// padding and border — see `mainEdges`. It holds them for a declared size
    /// (ruling BM-4 floors both of `flexBaseSize`'s declared branches there) and
    /// for a content-sized container (`measureNode` adds them back), and does
    /// **not** for a content-sized measured leaf, whose `MeasureFunction` answer
    /// `measureNode` returns unchanged. So "a border box" is true of it only
    /// where a leaf's border box and content box are the same thing.
    var baseSize: Double
    /// The main-axis padding plus border that `baseSize` **holds** —
    /// horizontal in a row, vertical in a column — as reported by
    /// `flexBaseSize` from the branch that produced the base: the item's
    /// resolved edges, or 0 for a content-sized measured leaf.
    ///
    /// **Read only by §9.7.4.c**, which weights shrink by the item's INNER flex
    /// base size, `baseSize - mainEdges`. Weighting by `baseSize` itself gives a
    /// padded item too much to lose: a 200 row holding a `width: 200px;
    /// padding: 0 40px` box and a plain `width: 200px` one is 125 / 75 in WebKit
    /// and was 100 / 100 here (`flex_row_shrink_padded_weighting`). Subtracting
    /// the item's edges whether or not the base holds them is the opposite
    /// mistake, and it reached a padded `Text`:
    /// `aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`.
    ///
    /// No default value, deliberately: a `= 0` here would let a construction
    /// site omit it and silently weight by the border box again, green on every
    /// unpadded test.
    let mainEdges: Double
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

    // A root percentage now resolves against the extent the root was offered
    // on that SAME axis (ruling SZ-A,
    // `docs/superpowers/2026-08-30-sizing-decisions.md`) — matching WebKit,
    // and matching how `computeLayout` already resolves the root's
    // percentage PADDING against `available.width`. Measured through the
    // oracle: a root with `width: 50%; height: 25%` inside an 800x600
    // offered space is `400 x 150` (`rootPercentageMatchesWebKit`,
    // `Tests/MetalUILayoutTests/SizingFixtureTests.swift`). Before this
    // change `declared` always resolved against `nil`, so a percentage was
    // unresolvable here and this function silently fell back to the offered
    // extent untouched (800 x 600 for the fixture above) — the divergence
    // CLAUDE.md's "Declared but inert" table used to record as "A percentage
    // `width`/`height` on the root: falls back to the offered space, not to
    // the percentage." That row has been deleted from CLAUDE.md.
    //
    // **The basis is per axis, not per box.** `withoutMeasuring` is called
    // once for `width` with `available.width` and once for `height` with
    // `available.height`, so `basis` below is always the offered extent on
    // the SAME axis as the dimension being resolved — the ordinary CSS rule
    // for a box's own width/height percentage, which is not the same rule
    // that governs percentage padding and border (those always resolve
    // against the containing block's WIDTH, on both axes — see the
    // padding/border bullet in CLAUDE.md's Build section).
    //
    // **The two-arity form exists for exactly this call; the `min`/`max`
    // clamps at the end of this function deliberately keep calling the
    // one-arity, no-basis form below.** Whether a percentage `minSize`/
    // `maxSize` on the root should also take a basis is a separate,
    // unresolved question with no fixture behind it — do not extend the
    // basis to those callers here.
    func declared(_ dim: Dimension, axis basis: Double?) -> Double? {
        resolveDimension(dim, against: basis, rootFontSize: rootFontSize)
    }
    func declared(_ dim: Dimension) -> Double? { declared(dim, axis: nil) }

    /// What an axis resolves to without measuring anything: its declared
    /// size — now resolved against the extent this same axis was offered —
    /// or that offered extent itself. `nil` — "measure it" — only when there
    /// is neither a declared size nor an offered extent.
    ///
    /// **The `auto` test is on the DECLARATION, not on `declared(dim) ==
    /// nil`, and that is still true after the basis change above.**
    /// `declared` returns `nil` for a literal `.auto` whatever basis it is
    /// given, so the `auto` branch below is byte-identical to what it was
    /// before this change, and ruling CS-I — an `auto` root axis taking a
    /// definite offered extent rather than shrink-wrapping it — is
    /// untouched. A percentage now resolves through `declared` whenever
    /// there IS an offered extent on this axis to serve as its basis; only
    /// when there is none (the offered extent is indefinite) does a
    /// percentage still fall through to the old fallback below — unchanged,
    /// because `definiteExtent(offered)` is `nil` in that case, so the basis
    /// is `nil` too and `declared` behaves exactly as it always did.
    func withoutMeasuring(_ dim: Dimension, _ offered: AvailableSpace) -> Double? {
        if let d = declared(dim, axis: definiteExtent(offered)) { return d }
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
    // as WebKit's flex sub-one clause. That all 81 fixture roots declare both axes
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

    // Ruling BM-4 — the root grows to fit its own padding and border like any
    // other box, after its min/max clamp. Its containing block is the space it
    // was offered (`containingBlockWidth`), which is the same basis
    // `computeLayout` resolves the root's percentage padding against a few
    // lines below this call; resolving it against the root's own resolved
    // width instead is the mistake `contentBox`'s containing-block note
    // records.
    let floor = borderBoxFloor(tree, root, containingBlockWidth: containingBlockWidth,
                               rootFontSize: rootFontSize)
    return SizeD(
        width: max(clamp(base.width, min: declared(s.minSize.width), max: declared(s.maxSize.width)),
                   floor.width),
        height: max(clamp(base.height, min: declared(s.minSize.height), max: declared(s.maxSize.height)),
                    floor.height))
}

/// A box's own padding + border per axis — the floor its **border box** may
/// never go below. Ruling **BM-4**.
///
/// `box-sizing: border-box` defines a box's used size on an axis as
/// `max(specified, padding + border)`: when the two edges together exceed the
/// specified size, the browser grows the BORDER BOX rather than letting the
/// content box invert. Every site that turns a node's declared `width`/`height`
/// into a used border-box size takes this floor — `resolveRootSize`,
/// `resolveNodeSize`, `flexBaseSize`'s `mainFloor()`, `layOutStack` and
/// `placeAbsolute`. Five, and the count is literal. A sixth function floors a
/// size that was never declared: `positionStackItems`, whose `stretch` branch
/// hands an `auto` axis the stack's content extent, clamps it by the child's
/// min/max and floors the result (review finding B-8; it assigned the extent
/// bare before). Run
/// `grep -rn 'borderBoxFloor(tree' Sources/MetalUILayout/` and **read the
/// lines rather than the count**: it returns **eight**. One is the sentence you
/// are reading, which names the pattern while explaining it. The other is
/// `collectItems`' automatic minimum. It floors no declared size: it re-floors
/// §4.5's minimum after a `max-*` has clamped it, and only when the clamp bit
/// and the item is not a measured leaf.
/// (Written that way deliberately after the first draft claimed "exactly those
/// five lines" and was falsified by its own quotation in the same edit — the
/// failure mode CLAUDE.md's `evictUnusedSince` row is about, where a number
/// tracks the prose instead of the code. Five *calls*; the claim is which
/// functions call it.) **`flexBaseSize` is the one to read carefully** — this used to say
/// "`flexBaseSize`'s size-property branch", which names one of the *two*
/// branches that floor. `mainFloor()` is a single call site consumed by both:
/// branch 1, a definite `flex-basis`, and branch 2, `flex-basis: auto`
/// deferring to the size property. Branch 3 reads it too, without flooring
/// anything: for a content-sized container it reports the edges `measureNode`
/// added back, as `FlexItem.mainEdges`. Flooring only the second is a real bug this
/// file shipped once, on a bad oracle reading — see the paragraph below and
/// `mainFloor()`'s own comment, which carries the table.
/// Each was measured against WebKit rather than reasoned:
/// `width: 100px; height: 80px; padding: 60px 50px; border-width: 10px` gives
/// **120x140** as a root, as a flex item, as an absolutely-positioned box and
/// as a grid item (the closest CSS analogue to `display: .stack`).
///
/// **The floor applies AFTER the min/max clamp, and that ordering is measured,
/// not chosen.** A `max-height: 40px` box with 140 of vertical padding+border
/// measures **140** in WebKit, not 40; `max-width: 40px` with 120 horizontal
/// measures **120**. So a `max-*` smaller than the floor does not win — which
/// is the one case the two orderings disagree on, and the reason this is a
/// `max(clamp(…), floor)` everywhere rather than a `clamp(max(…), …)`.
///
/// **A definite `flex-basis` is floored too, and the claim that it was not cost
/// this milestone a review round.** The measurement behind that claim put its
/// box alone in its flex container, where WebKit answers incoherently; with any
/// in-flow sibling present, all four spellings measure 120. `flexBaseSize`'s
/// own doc carries the table and CSS Flexbox §7.2.3, which settles it.
///
/// Percentage `padding` and `border` resolve against the containing block's
/// **width on every edge**, vertical ones included — CSS's rule, and the same
/// one `contentBox` implements; `edges` there is this same quantity, computed
/// for a box whose border box is already known. This function exists because
/// the floor is needed *before* that, while the border box is still being
/// decided.
///
/// **Three compositions this floor does not reach.** The list is exhaustive as
/// of the sizing milestone's Task 4 and every entry was measured through the
/// oracle; it read as two until a reviewer found the third, so treat it as a
/// list that has been wrong once. Each entry names the site that would have to
/// change, because none of them is reachable from this function.
///
/// 1. `width: 100px; min-width: 0; max-width: 40px` with 120 of padding+border
///    is **120** in WebKit and **40** here — the size property is floored by
///    this function, and `collectItems`' `hypothetical` then clamps it back
///    down to the max. Needs the floor on the item's *used* main size.
/// 2. Two `width: 500px; min-width: 0` items with 120 of padding+border each,
///    shrinking into a 200-wide row, are **120** each in WebKit (overflowing)
///    and 100 each here — §9.7 shrinks below the floor. Same site as 1.
///    WebKit's 120 was re-measured when §9.7.4.c's weight became the inner
///    base size (`FlexItem.mainEdges`), and that change does **not** reach
///    this shape: the two inner bases are equal, so the overflow still splits
///    evenly — 100 each here, by the loop's arithmetic rather than a fresh
///    engine run. It closes only the limiting case, where every item's inner
///    base is 0: those items now keep their base and overflow, as WebKit does
///    (`aLineWhoseItemsHaveNoInnerBaseSizeOverflowsInsteadOfShrinking`).
/// 3. An **`auto`** cross size clamped by a `max-*` below the floor:
///    `height: auto; max-height: 40px; padding: 60px 0; border-width: 10px 0`
///    is **140** in WebKit and **40** here. This one is not about the used main
///    size — it is `itemFitContentCrossSize` (`collectItems`' `ownCross`
///    formerly inlined it), whose `clamp` at the end this floor never sees, so
///    it takes exactly the `max-*` win the ordering ruling above says must not
///    happen. **Left to the milestone's TX-H task, and TX-H's own task
///    deliberately deferred it a second time**: TX-H's job was reordering
///    *when* an item's fit-content cross size is measured (against the used
///    main size instead of the hypothetical one), not composing that
///    measurement with a floor it has never consulted — a different rule
///    change, and folding it in here would put two behind one review, exactly
///    as this paragraph already said. Closing it needs
///    `itemFitContentCrossSize`'s final `clamp` to take `max(…, floor)` rather
///    than `clamp(…)` alone, mirroring `resolveNodeSize`'s own
///    `max(clamp(…), floor)` — plus a fixture, red on arrival, since none
///    exists. **Deferred a THIRD time by the milestone's fix wave** (ruling
///    `SZ-O`), which moved *when* this measurement's result is consumed and
///    again went nowhere near the `clamp`; that it cannot be an instance of
///    either reordering is checkable rather than asserted, since this
///    composition fails on a lone item whose main size never moves and so
///    reaches neither `SZ-M`'s guard nor `SZ-O`'s. Re-measured there through
///    the live oracle and unchanged: **WebKit 100x140, this engine 100x40**.
///    Still nobody's task.
///
/// 1 and 2 need an explicit `min-width: 0` to be reachable at all: §4.5's
/// automatic minimum is the item's min-content size, which already includes
/// padding and border, so the default floor is never below this one. 3 needs no
/// such switch — an `auto` cross size never consults §4.5 in the first place,
/// which is what makes it the easiest of the three to hit by accident.
func borderBoxFloor(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    containingBlockWidth: Double?,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)
    let padding = resolveEdges(s.padding, against: containingBlockWidth, rootFontSize: rootFontSize)
    let border = resolveEdges(s.border, against: containingBlockWidth, rootFontSize: rootFontSize)
    return SizeD(width: padding.horizontal + border.horizontal,
                 height: padding.vertical + border.vertical)
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
///
/// **Ruling BM-4 — the result is floored at the node's own padding + border**
/// (`borderBoxFloor`, above), after the min/max clamp. The 0 for an
/// unresolvable axis is therefore a 0 only for a node with no padding and no
/// border; a `height: 50%` child of an auto-height container with 20px of
/// vertical padding is 20 tall, not 0, which is the border box CSS's own
/// `box-sizing: border-box` guarantees it.
private func resolveNodeSize(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    parent: OptionalSizeD,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)
    // The containing block of the node this is called for is its flex
    // container's CONTENT box, which is exactly what `collectItems` passes as
    // `parent` — so `parent.width` is the basis every percentage padding and
    // border edge resolves against, vertical edges included.
    let floor = borderBoxFloor(tree, node, containingBlockWidth: parent.width,
                               rootFontSize: rootFontSize)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              parentExtent: Double?, floor: Double) -> Double {
        let resolved = resolveDimension(dim, against: parentExtent, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: parentExtent, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: parentExtent, rootFontSize: rootFontSize)
        // An unresolvable size is 0 here, before the floor. On a flex item's
        // main axis this result is computed but discarded — §9.2's flex base
        // size supplies that axis instead.
        //
        // Ruling BM-4: the floor is applied LAST, outside the clamp, because
        // WebKit does not let a `max-*` cap a border box below its own padding
        // and border — measured, see `borderBoxFloor`.
        return max(clamp(resolved ?? 0, min: lower, max: upper), floor)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width,
                    parentExtent: parent.width, floor: floor.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height,
                     parentExtent: parent.height, floor: floor.height))
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
/// is not invertible: `size` is clamped at 0 (the `max(0, …)` below, which
/// ruling BM-4 narrowed rather than removed), and an axis of `borderBox` may be
/// **indefinite**, where there is nothing to subtract from. `edges` is also the
/// same quantity `borderBoxFloor` computes — that function answers it for a box
/// whose border box is not decided yet, which is where the floor has to be
/// applied.
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
) -> (origin: (Double, Double), size: OptionalSizeD, edges: SizeD, padding: ResolvedEdges) {
    let s = tree.style(container)
    let padding = resolveEdges(s.padding, against: containingBlockWidth, rootFontSize: rootFontSize)
    let border = resolveEdges(s.border, against: containingBlockWidth, rootFontSize: rootFontSize)

    let leading = (padding.left + border.left, padding.top + border.top)
    // Ruling BM-4 — the growing is done UPSTREAM of this function now, and
    // `max(0, …)` is what is left of it. CSS's answer when padding + border
    // exceeds the specified size on an axis is to grow the border box itself
    // (`box-sizing: border-box` defines the used size as
    // `max(specified, padding + border)`), never to let the content box go
    // negative — and the SIZING milestone implemented exactly that, at every
    // site that turns a declared size into a used one (`borderBoxFloor`). So a
    // `borderBox` arriving here from any of them is already at or above
    // `padding + border`, and this subtraction cannot go negative for it.
    //
    // The guard stays because a declared size is not the only way an axis
    // reaches this function. §9.7 can still shrink a flexed main size below the
    // floor when an explicit `min-width: 0` switches §4.5's automatic minimum
    // off — one of the two compositions `borderBoxFloor`'s doc records as
    // deliberately out of reach, WebKit's answer for it being the grown box.
    // A stretched child then inherits the container's cross extent directly,
    // so without `max(0, …)` its *stored* height goes negative: measured at
    // **−80** for a 500-tall row with 140 of vertical padding+border shrunk
    // into a 60-tall column.
    //
    // **Deleting this line reddened NOTHING on the 746-test suite the sizing
    // milestone's Task 4 left behind**, and that is why the test above exists.
    // It was reachable through the old
    // `containerDoesNotGrowToFitOverconstrainedPadding…` pin, whose unfloored
    // 100×80 root really did have a −20 × −60 content box; flooring the border
    // box everywhere a declared size becomes a used one took that away and left
    // the guard live in the engine and dead to the suite.
    // `aShrunkContainerNeverHandsItsChildANegativeContentBox`
    // (BoxModelTests.swift) is the pin, and it reddens on exactly this line.
    let size = OptionalSizeD(
        width: borderBox.width.map { max(0, $0 - padding.horizontal - border.horizontal) },
        height: borderBox.height.map { max(0, $0 - padding.vertical - border.vertical) })
    let edges = SizeD(width: padding.horizontal + border.horizontal,
                      height: padding.vertical + border.vertical)
    return (leading, size, edges, padding)
}

/// The rect an absolutely-positioned descendant is placed against.
///
/// Threaded **downward** through `placeNode` rather than resolved by walking up:
/// `LayoutTree` has no parent accessor, and adding one would be redundant state
/// to keep in sync. A node whose `position` is not `.static` replaces this for
/// its own descendants.
///
/// The rect is the containing block's **padding box** — inside its border, per
/// CSS (spec §3.3). `origin` is absolute to the root, the same space `placeNode`
/// positions in. Derived as the content box (`ContainerLayout.box`) expanded
/// back out by the container's own resolved padding (`ContainerLayout.padding`)
/// — NOT the border box, and not the content box unchanged. Using the content
/// box would shift every absolute child inward by its containing block's
/// padding: a small, uniform error that reads as rounding rather than a wrong
/// box. `theContainingBlockIsThePaddingBoxNotTheBorderBox` pins it.
struct ContainingBlock {
    var origin: (Double, Double)
    var size: SizeD
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
    /// This container's own resolved padding, from `contentBox` — kept
    /// separate from `edges` (which is padding + border combined) because
    /// `placeNode` needs padding alone to derive an absolutely-positioned
    /// descendant's containing block, which CSS defines as the PADDING box
    /// (inside the border, outside the content). Reusing this rather than
    /// re-resolving `Style.padding` in `placeNode` avoids a second percentage
    /// resolution against a basis that would be easy to get wrong (see the
    /// containing-block width note on `contentBox` above).
    var padding: ResolvedEdges
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
/// been stretched and flexed. The 81 browser goldens are the check.
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
        return layOutStack(ctx, tree, container, box: box, intrinsic: intrinsic)
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
            stackItems: [], padding: box.padding)
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

    // CSS Flexbox §9.3 — break into lines on the items' hypothetical main
    // sizes. §9.4.8 (each line's cross size) is a separate loop further down,
    // **after** §9.7 and §9.4 step 7 have finished with the item cross sizes it
    // reads; ruling SZ-O, and the two used to be one statement here.
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
        // `crossSize` is filled in below, after §9.7 and §9.4 step 7 — see the
        // two loops that follow. A `FlexLine` between here and there carries a
        // placeholder 0 and **nothing may read it**; the compiler cannot
        // enforce that, so the only code between the two points is the flex
        // step, which reads no cross-axis field at all (verified: `grep -n
        // "crossSize\|marginCross\|minCross\|maxCross\|stretchEligible"
        // Sources/MetalUILayout/ResolveFlexibleLengths.swift` returns nothing).
        .map { FlexLine(items: $0, crossSize: 0, crossStart: 0) }

    // §9.7 — resolve the flexible lengths, per line, BEFORE any cross-axis
    // quantity is computed from the items.
    //
    // **This loop and the two blocks after it are CSS Flexbox's step order
    // 6 → 7 → 8, and getting it wrong is what ruling SZ-O corrects.** Step 6
    // is the flex step, step 7 measures each item's cross size *from its used
    // main size*, and step 8 measures each line from those item cross sizes.
    // Until this milestone's fix wave the engine ran 8 → (align-content) →
    // 11 → 6 → 7, so step 7's answer landed after everything that consumes it:
    // TX-H updated the item and left the line and the container reporting the
    // pre-flex extent. That produced a 40-tall item inside a 20-tall parent,
    // and, in a wrapping container, a second line stacked 20pt too high —
    // overlapping siblings. See `crossSizeAfterFlexPropagatesToTheLine` and
    // `crossSizeAfterFlexPropagatesToAnAutoContainer`.
    //
    // **The header's "circular or wrong if reversed" still holds and this is
    // not a counter-example to it.** The orderings it names are cross-axis
    // ones — break before line measurement, `align-content` growth before
    // §9.4's item stretch — and every one of them is unchanged. §9.7 simply
    // was never in that dependency chain: it reads `containerMain`, the
    // items' base and hypothetical main sizes and their main min/max, and no
    // cross-axis field exists in `ResolveFlexibleLengths.swift` at all. So it
    // is free to move earlier, which is the only thing that moved.
    for i in lines.indices {
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

        // CSS Flexbox §9.4 step 7 (ruling TX-H) — re-measure a non-stretched
        // auto-cross item's fit-content cross size now that §9.7, just above,
        // has resolved its USED main size. `collectItems` already measured
        // every such item once, against its HYPOTHETICAL main size, because
        // §9.7's own input (each item's hypothetical main size) has to exist
        // before it can run and `collectItems` is the one pass that produces
        // it — see `itemFitContentCrossSize`'s own doc. That first measurement
        // is wrong only for an item whose target actually moved; most items
        // freeze at their hypothetical size (`ResolveFlexibleLengths.swift`'s
        // freeze loop is a no-op the moment nothing violates a min/max), and
        // for those the first measurement already is the answer CSS wants, so
        // this only re-measures the ones that changed (ruling SZ-M —
        // "re-run", not "move": the alternative shape recomputes every
        // auto-cross item unconditionally here and is strictly more work for
        // the same answer, since a frozen item's hypothetical and used main
        // sizes are numerically equal and the fit-content formula is a pure
        // function of that one number).
        //
        // A stretch-eligible item is skipped outright: its cross size is set
        // below, in the positioning loop, to the LINE's own extent (minus its
        // cross margins) — that is what "stretch" means, and it does not
        // depend on the item's main size or its content at all. Only a
        // NON-stretched `auto` cross size is `itemFitContentCrossSize`'s
        // business, which is why this re-derives `crossDim` from the item's
        // own style rather than trusting `stretchEligible == false` alone: a
        // definite cross size was never measured by `collectItems` in the
        // first place (see its own `ownCross` guard) and must not be measured
        // here either.
        for j in lines[i].items.indices {
            let item = lines[i].items[j]
            guard !item.stretchEligible,
                  item.targetMainSize != item.hypotheticalMainSize
            else { continue }
            let itemStyle = tree.style(item.node)
            guard case .auto = (isRow ? itemStyle.size.height : itemStyle.size.width)
            else { continue }
            lines[i].items[j].crossSize = itemFitContentCrossSize(
                ctx, tree, item.node, mainSize: item.targetMainSize, isRow: isRow,
                containerCross: containerCross, intrinsic: intrinsic,
                minCross: item.minCross, maxCross: item.maxCross,
                marginCross: item.marginCross, containingBlockWidth: box.size.width)
        }
    }

    // §9.4.8 — each line's cross size, from the item cross sizes step 7 has
    // just finalised.
    for i in lines.indices {
        // §9.4.8's single-line clause is keyed on the container's cross size
        // being **definite**, which is the spec's own wording and not a
        // paraphrase: an indefinite one gives the line nothing to take, so
        // the line measures itself from its items exactly as a wrapped
        // line does.
        let single = s.flexWrap == .noWrap ? containerCross : nil
        lines[i].crossSize = single ?? lineCrossSize(lines[i].items)
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
    //
    // **It is also after §9.4 step 7, and that is what makes an `auto`-cross
    // container report the height its flexed children actually occupy.** A
    // `nowrap` row 120 wide holding one wrapping child declared at its
    // max-content 200 reported 20 here and drew a 40-tall child inside it
    // until ruling SZ-O moved the flex step above this line;
    // `crossSizeAfterFlexPropagatesToAnAutoContainer` is the pin.
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
        stackItems: [], padding: box.padding)
}

/// A `.stack` container: every child at its own size, the container at the
/// maximum of them on each axis.
///
/// **No main axis, so no §9.7.** There is no flex base size, no freeze loop, no
/// line breaking and no distribution — each child is measured once against the
/// space the stack itself was offered, and the container reports the largest.
///
/// **`box.size` is the ONLY basis a stack child's percentage resolves against,
/// and it is `nil` on an axis the stack itself has no extent on.** During the
/// intrinsic pass `box.size` is `(nil, nil)`, so a `width: 50%` child is
/// unresolvable and is **measured from its own content**, exactly as a literal
/// `auto` is; during placement `box.size` is definite and the same child
/// resolves the ordinary way. That is why each axis below is resolved
/// independently against `box.size`, never against a literal `.definite` extent
/// invented for the indefinite case.
///
/// **"Contributes 0" is what Task 1's probe measured and it was the wrong
/// generalisation.** That probe's percentage child was *empty*, so "contributes
/// 0" and "contributes its own content size" were the same number and the probe
/// could not tell them apart; ST-E generalised from it to percentage children
/// with content, a shape nothing had measured. WebKit measures the content —
/// see `resolvedAxis` below for the numbers and the fixture that pins them.
private func layOutStack(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    box: (origin: (Double, Double), size: OptionalSizeD, edges: SizeD, padding: ResolvedEdges),
    intrinsic: IntrinsicQuery
) -> ContainerLayout {
    let rootFontSize = ctx.rootFontSize

    // A literal `auto` is measured from the child's own content — content
    // height on the block axis, fit-content on the inline axis (see the
    // measuring branch below; a stack does not stretch, so it never fills).
    // **So is a percentage that fails to resolve** — against `box.size`'s `nil`
    // on an axis the stack itself has no extent on yet. Returning `nil` here is
    // the signal "this axis needs measuring", and both cases return it.
    //
    // **This line was `?? 0` until the milestone's final review, and that was a
    // measured disagreement with WebKit rather than a judgement call.** The `0`
    // was justified by citing `resolveNodeSize`'s rule for an unresolvable
    // percentage, and that citation was a scope error: `resolveNodeSize`'s
    // comment is about a flex item's *cross* axis, where the item is about to be
    // stretched or aligned by a container that already has a definite cross
    // extent, and `layOutStack` applied it to *both* axes of a child whose
    // container is still being intrinsically sized. Measured through this
    // repo's own `LayoutOracle` — an auto-sized stack holding a `width: 50%`
    // child that itself contains an 80x30 box, plus a fixed 40x20 sibling:
    // WebKit gives the stack `80x30` and the percentage child `40x30`; the `?? 0`
    // engine gave `40x30` and `20x30`. `stack_percent_child_with_content`
    // pins it. Ruling ST-E's original text asserted WebKit's numbers as this
    // engine's without ever calling the engine — see
    // `docs/superpowers/2026-08-28-stack-decisions.md`.
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
        guard let resolved = resolveDimension(dim, against: basis, rootFontSize: rootFontSize)
        else { return nil }
        return clamp(resolved, min: lower, max: upper)
    }

    var items: [StackItem] = []
    var maxWidth = 0.0
    var maxHeight = 0.0

    for kid in tree.children(container)
    where tree.style(kid).display != .none && tree.style(kid).position != .absolute {
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

        var size: SizeD
        if let knownWidth, let knownHeight {
            // Both axes resolved from the child's own style — no need to run
            // the child's own layout to size it; `positionStackItems` (Task 3)
            // recurses into it once it has a final origin.
            size = SizeD(width: knownWidth, height: knownHeight)
        } else {
            // The child measured with every axis it has resolved held as
            // `known`, and `width` asked on the one it may not have. The block
            // axis is always content height: `.maxContent` unless declared.
            func measure(width: AvailableSpace, knownWidth: Double?) -> SizeD {
                measureNode(
                    ctx, tree, kid,
                    known: OptionalSizeD(width: knownWidth, height: knownHeight),
                    available: AvailableSpaceSize(
                        width: width,
                        height: knownHeight.map { .definite($0) } ?? .maxContent),
                    containingBlockWidth: box.size.width)
            }
            // A content-measured axis is clamped here, after measuring — the
            // same order `collectItems`' `ownCross` uses, and CSS's own: min/max
            // bounds the USED size regardless of how it was computed, so a
            // measured axis needs the clamp exactly as much as a declared one
            // (`knownWidth`/`knownHeight` were already clamped by
            // `resolvedAxis` above when they came back non-nil, so only the
            // axis that was actually measured is clamped below).
            if let knownWidth {
                let measured = measure(width: .definite(knownWidth), knownWidth: knownWidth)
                size = SizeD(width: knownWidth,
                             height: clamp(measured.height, min: minHeight, max: maxHeightBound))
            } else {
                // **An `auto` WIDTH is fit-content, not max-content** — CSS
                // sizes an `auto` inline axis by shrink-to-fit and an `auto`
                // block axis by content height (ruling TX-H's distinction),
                // and the grid item a stack is modelled on follows it. This
                // branch measured every content-sized child at `.maxContent`
                // until review finding B-4: a 120-wide stack holding a
                // wrapping row of four 50x20 items (min-content 50,
                // max-content 200) laid the row out 200x20 at x = -40 where
                // WebKit's grid analogue gives 120x40 at 0
                // (`stack_fit_content_inline`). The arithmetic is
                // `fitContentInlineSize`'s, shared with a column item's cross
                // size so the two container types cannot drift apart again.
                //
                // **Offering `.definite(box.size.width)` in place of
                // `.maxContent` is not this fix; it is a third wrong answer.**
                // `measureNode` lays a container out INSIDE a definite offer and
                // reports its content extent, not the offer — so a wrapping
                // child answers its widest line, and in the floor regime its
                // items shrink into the offer. Built as a mutant and measured:
                // `stack_fit_content_inline`'s `.a` 100x40 at x = 10 (WebKit
                // 120x40 at 0), `stack_fit_content_floor`'s child 30x40 (WebKit
                // 50x40), and the min-content case untouched at 200, because an
                // intrinsic question offers no width to be definite about.
                //
                // `box.size.width` is `nil` while the stack is itself being
                // asked an intrinsic question, and `intrinsic.width` then
                // answers: under `.minContent` the child is offered 0, so a
                // stack's min-content width is its widest child's MIN-content —
                // what CSS §4.5's automatic minimum reads when a stack is a
                // shrinking flex item (`stack_fit_content_min_content_contribution`:
                // 100 in WebKit, 200 here before). No margin is subtracted:
                // neither this function nor `positionStackItems` reads a stack
                // child's margin at all.
                let maxContent = measure(width: .maxContent, knownWidth: nil)
                let fit = fitContentInlineSize(
                    maxContent: maxContent.width, containerExtent: box.size.width,
                    margin: (0, 0), intrinsic: intrinsic.width,
                    minContent: { measure(width: .minContent, knownWidth: nil).width })
                let width = clamp(fit, min: minWidth, max: maxWidthBound)
                // **The height is measured at the USED width**, after the
                // clamp — a wrapping child capped at `max-width: 70` wraps at
                // 70. The max-content measurement is reused only where the
                // width did not move from it — a child whose max-content fits
                // its offer and is not clamped, which is every stack child in
                // the goldens committed before these three (none moved).
                // `stack_fit_content_inline`'s `.m` is 80 tall in WebKit;
                // measured at max-content it was 20.
                size = SizeD(
                    width: width,
                    height: knownHeight ?? clamp(
                        (width == maxContent.width
                            ? maxContent
                            : measure(width: .definite(width), knownWidth: width)).height,
                        min: minHeight, max: maxHeightBound))
            }
        }

        // Ruling BM-4 — a stack child grows to fit its own padding and border
        // exactly as a flex item does, after its min/max clamp
        // (`borderBoxFloor`). Applied to both branches above rather than inside
        // `resolvedAxis`, so the declared and measured paths cannot drift; on
        // the measured path it is a no-op, `measureNode` already reporting a
        // border box that includes `edges`. Measured against WebKit's closest
        // analogue to `display: .stack`, a grid item: `width: 100px;
        // height: 80px; padding: 60px 50px; border-width: 10px` is 120x140.
        let floor = borderBoxFloor(tree, kid, containingBlockWidth: box.size.width,
                                   rootFontSize: rootFontSize)
        size = SizeD(width: max(size.width, floor.width),
                     height: max(size.height, floor.height))

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
        stackItems: items, padding: box.padding)
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
    containingBlockWidth: Double?,
    containingBlock: ContainingBlock
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

    // The containing block for THIS node's descendants: itself if it is
    // positioned, otherwise whatever was threaded in from above. Computed once
    // here, ahead of the in-flow positioning below, so both the in-flow
    // recursion and the absolute-child loop after it see the same value —
    // `childCB` does not depend on anything either positioning pass produces.
    //
    // The PADDING box, not the border box: `childOrigin` is the content box's
    // origin (leading padding + border, per the comment above) and
    // `laid.box.size` its size, so backing out only the padding — not the
    // border — lands on the padding box CSS requires. `laid.padding` is the
    // same resolved padding `layOutChildren` already computed, reused rather
    // than re-resolved.
    let s = tree.style(node)
    let childCB: ContainingBlock = s.position == .static
        ? containingBlock
        : ContainingBlock(
            origin: (childOrigin.0 - laid.padding.left, childOrigin.1 - laid.padding.top),
            size: SizeD(width: laid.box.size.width + laid.padding.horizontal,
                       height: laid.box.size.height + laid.padding.vertical))

    for line in laid.lines {
        positionItems(ctx, tree, node, items: line.items,
                      lineCross: line.crossSize, lineCrossStart: line.crossStart,
                      containerOrigin: childOrigin,
                      containerSize: laid.box.size,
                      containingBlock: childCB)
    }
    // `laid.lines` is empty for a stack and `laid.stackItems` is empty for a
    // flex container (each is honest about what it holds — see
    // `ContainerLayout`), so exactly one of these two loops ever does
    // anything for a given node.
    if !laid.stackItems.isEmpty {
        positionStackItems(ctx, tree, node, items: laid.stackItems,
                           containerOrigin: childOrigin,
                           containerSize: laid.box.size,
                           containingBlock: childCB)
    }

    // Absolute children, placed against `childCB` rather than in flow. They
    // were filtered out of `laid.lines`/`laid.stackItems` by Task 2, so this
    // is the only thing that positions them.
    for kid in tree.children(node)
    where tree.style(kid).display != .none && tree.style(kid).position == .absolute {
        placeAbsolute(ctx, tree, kid, in: childCB)
    }
}

/// Places one absolutely-positioned box against its containing block, reading
/// `Style.inset` to size and position it.
///
/// **Per-axis bases, and this is NOT CLAUDE.md:997's rule.** That constraint is
/// about `padding` and `border`, where CSS resolves every percentage against
/// the containing block's width. An inset does not: `left`/`right` resolve
/// against width, `top`/`bottom` against height.
///
/// Each axis is independent and follows the same three-way branch `resolveNodeSize`
/// uses for a flex item's cross axis, plus one case that function has no
/// occasion for (both insets given): a declared, non-`auto` size always wins —
/// which is also this function's fix for a bug Task 3 left, below — an `auto`
/// size with both insets given stretches to fill the gap between them, and an
/// `auto` size with fewer than two insets falls back to `measureNode`, exactly
/// as an item's `auto` cross size does in `collectItems`.
///
/// Position, per axis: the leading inset (`left`/`top`) wins when given,
/// regardless of the trailing one — which is CSS's over-constrained rule
/// (drop `right`/`bottom`) applied uniformly rather than as a special case,
/// since a declared size already ignores the trailing inset for sizing and
/// this reuses the same "leading wins" read for position. Only the trailing
/// inset given positions from the far edge. Neither given places at the
/// containing block's origin — the box's all-`auto` behaviour, and Task 3's
/// existing one; spec §3.5 records it as a deliberate divergence from CSS's
/// static position.
///
/// **The 0×0 sizing bug this task's brief named.** Task 3 sized every absolute
/// child by calling `measureNode(known: .unspecified, …)` unconditionally —
/// for a childless node with no `MeasureFunction`, that falls into
/// `measureNode`'s container branch and returns `contentSize + edges`, zero
/// for an empty container, never consulting `Style.size`. `declaredAxis`
/// below is what fixes it: a declared size is resolved from the node's own
/// style FIRST, the same way `resolveNodeSize` resolves a flex item's cross
/// axis, and `measureNode` is reached only when the axis is genuinely `auto`
/// and not fully bounded by its two insets.
private func placeAbsolute(_ ctx: LayoutContext, _ tree: LayoutTree,
                           _ node: LayoutNodeID, in cb: ContainingBlock) {
    let s = tree.style(node)

    let left = resolveDimension(s.inset.left, against: cb.size.width, rootFontSize: ctx.rootFontSize)
    let right = resolveDimension(s.inset.right, against: cb.size.width, rootFontSize: ctx.rootFontSize)
    let top = resolveDimension(s.inset.top, against: cb.size.height, rootFontSize: ctx.rootFontSize)
    let bottom = resolveDimension(s.inset.bottom, against: cb.size.height, rootFontSize: ctx.rootFontSize)

    // A declared, non-`auto` size, clamped by its own min/max — `nil` when the
    // property IS `auto`, which is how "not given" is told from "given as 0"
    // (`resolveDimension`'s existing convention, reused here for `Style.size`).
    func declaredAxis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
                      against parent: Double) -> Double? {
        guard let resolved = resolveDimension(dim, against: parent, rootFontSize: ctx.rootFontSize) else {
            return nil
        }
        let lower = resolveDimension(minDim, against: parent, rootFontSize: ctx.rootFontSize)
        let upper = resolveDimension(maxDim, against: parent, rootFontSize: ctx.rootFontSize)
        return clamp(resolved, min: lower, max: upper)
    }

    let declaredWidth = declaredAxis(s.size.width, s.minSize.width, s.maxSize.width, against: cb.size.width)
    let declaredHeight = declaredAxis(s.size.height, s.minSize.height, s.maxSize.height, against: cb.size.height)

    // `auto` size, both insets given on that axis: stretch to fill the gap.
    let stretchWidth = (declaredWidth == nil && left != nil && right != nil)
        ? cb.size.width - left! - right! : nil
    let stretchHeight = (declaredHeight == nil && top != nil && bottom != nil)
        ? cb.size.height - top! - bottom! : nil

    let known = OptionalSizeD(width: declaredWidth ?? stretchWidth, height: declaredHeight ?? stretchHeight)
    var size: SizeD
    if let w = known.width, let h = known.height {
        size = SizeD(width: w, height: h)
    } else {
        // Neither declared nor stretched by two insets: the box's own
        // content size, exactly the call every other constant-substituting
        // site in this file makes (`measureNode`'s doc comment).
        let measured = measureNode(ctx, tree, node, known: known,
                                   available: AvailableSpaceSize(width: .definite(cb.size.width),
                                                                 height: .definite(cb.size.height)),
                                   containingBlockWidth: cb.size.width)
        size = SizeD(width: known.width ?? measured.width, height: known.height ?? measured.height)
    }

    // Ruling BM-4 — an absolutely-positioned box grows to fit its own padding
    // and border like any other box (`borderBoxFloor`). Applied to the final
    // size rather than inside `declaredAxis`, so all three branches above take
    // it: the declared one, the stretched-between-two-insets one (which can
    // otherwise land below the floor when the insets leave less room than the
    // edges need) and the measured one (where it is a no-op, `measureNode`
    // already reporting a border box that includes `edges`). Measured against
    // WebKit: `position: absolute; width: 100px; height: 80px;
    // padding: 60px 50px; border-width: 10px` is 120x140. Percentage edges
    // resolve against the containing block's WIDTH on every edge, which is
    // `cb.size.width` — the same basis `placeNode` hands this subtree.
    let floor = borderBoxFloor(tree, node, containingBlockWidth: cb.size.width,
                               rootFontSize: ctx.rootFontSize)
    size = SizeD(width: max(size.width, floor.width), height: max(size.height, floor.height))

    // Leading wins over trailing when both are given — CSS's over-constrained
    // rule (drop `right`/`bottom`) falls out of this uniformly, since sizing
    // above already ignored the trailing inset once a size was declared.
    let x = cb.origin.0 + (left ?? (right.map { cb.size.width - $0 - size.width } ?? 0))
    let y = cb.origin.1 + (top ?? (bottom.map { cb.size.height - $0 - size.height } ?? 0))

    tree.setLayout(node, LayoutRect(x: x, y: y, width: size.width, height: size.height))
    placeNode(ctx, tree, node, origin: (x, y), size: size,
              containingBlockWidth: cb.size.width, containingBlock: cb)
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
    containerSize: SizeD,
    containingBlock: ContainingBlock
) {
    // `nil` reads as CSS's `stretch` on both axes, matching `alignItems`'s
    // existing convention. `Stack.init` always writes an explicit value; a
    // hand-built `Style` may not.
    let s = tree.style(container)
    let vertical = s.alignItems ?? .stretch
    let horizontal = s.justifyItems ?? .stretch

    for item in items {
        var size = item.size
        // `stretch` fills the axis ONLY when the child's own declared size on
        // that axis is `auto` — CSS Box Alignment's rule, and WebKit's
        // measured behaviour (a 20x10 child under `justify-items: stretch;
        // align-items: stretch` stays 20x10 at the start edge; only an
        // unsized child fills the cell). A declared size — including a
        // percentage, which is not `auto` either — keeps its own value and is
        // placed at the start edge below, exactly as an unstretched item
        // would be. Read from the child's own `Style`, not threaded through
        // `StackItem`, since `tree.style(item.node)` is already how every
        // other per-item read in this file reaches it.
        let itemStyle = tree.style(item.node)
        let widthIsAuto: Bool = { if case .auto = itemStyle.size.width { return true }; return false }()
        let heightIsAuto: Bool = { if case .auto = itemStyle.size.height { return true }; return false }()
        // **A stretched axis is still clamped by the child's own min/max and
        // then floored at its padding + border** — clamp then floor, the order
        // `layOutStack` applies to the size it hands this function and
        // `borderBoxFloor`'s doc records for every other site. These two lines
        // were bare assignments of `containerSize` until review finding B-8,
        // which threw away both of `layOutStack`'s answers one function after
        // its comment said that exact trap was closed. Measured against the
        // grid analogue: an auto child of a 300x200 cell with `max-height: 50`
        // is 300x50 in WebKit (`stack_stretch_max`), with `min-width: 340;
        // min-height: 260` is 340x260 (`stack_stretch_min`), and with
        // `padding: 60px 50px; border: 10px` in a 100x100 cell is 120x140 —
        // still 120x140 with `max-width: 40; max-height: 50` added, not 40x50
        // (`stack_stretch_border_box_floor`). The engine gave the bare cell
        // size for all of them.
        //
        // Bounds resolve per axis against `containerSize`, the stack's content
        // box: the same basis `layOutStack` resolves them against in the
        // placement pass (its `box.size`, definite there), and read from the
        // child's style here for the reason the paragraph above gives.
        let stretchWidth = horizontal == .stretch && widthIsAuto
        let stretchHeight = vertical == .stretch && heightIsAuto
        if stretchWidth || stretchHeight {
            func stretched(_ extent: Double, min minDim: Dimension, max maxDim: Dimension,
                           floor: Double) -> Double {
                let lower = resolveDimension(minDim, against: extent, rootFontSize: ctx.rootFontSize)
                let upper = resolveDimension(maxDim, against: extent, rootFontSize: ctx.rootFontSize)
                return max(clamp(extent, min: lower, max: upper), floor)
            }
            let floor = borderBoxFloor(tree, item.node, containingBlockWidth: containerSize.width,
                                       rootFontSize: ctx.rootFontSize)
            if stretchWidth {
                size.width = stretched(containerSize.width, min: itemStyle.minSize.width,
                                       max: itemStyle.maxSize.width, floor: floor.width)
            }
            if stretchHeight {
                size.height = stretched(containerSize.height, min: itemStyle.minSize.height,
                                        max: itemStyle.maxSize.height, floor: floor.height)
            }
        }

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
        //
        // `containingBlock` threads through unchanged: it is what `container`
        // established for its own children (its own padding box if
        // positioned, otherwise whatever it inherited), and every one of
        // `container`'s in-flow children shares it, subject to `item.node`
        // overriding it for its own descendants inside the recursive
        // `placeNode` call if `item.node` is itself positioned.
        placeNode(ctx, tree, item.node, origin: origin, size: size,
                  containingBlockWidth: containerSize.width, containingBlock: containingBlock)
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
///
///    **And "three" is stale again, by two.** `fitContentInlineSize` consults
///    the query for an `auto` inline axis with no container extent, and it has
///    two callers: a column item's cross size (`itemFitContentCrossSize`,
///    killed by `theCrossAxisQueryReachesAnAutoCrossItem`) and a stack child's
///    width (`layOutStack`, killed by `stackMinContentContributionMatchesWebKit`).
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

/// CSS Flexbox §9.4 step 7 / §10.3.5's fit-content — an item's cross size,
/// "treating auto as fit-content", shared by two call sites that differ only
/// in **which** main size they pass in as `mainSize`. `collectItems` calls
/// this with an item's HYPOTHETICAL main size, before `resolveFlexibleLengths`
/// (§9.7) has run at all — see that call site for the full derivation of
/// every clause here, including the three choices measured against WebKit and
/// the fit-content formula's own three terms. `layOutChildren` calls it a
/// second time per line, with the item's USED main size, once
/// `resolveFlexibleLengths` has resolved it — ruling TX-H, and the correction
/// this milestone's Task 8 owns. This function holds only the arithmetic
/// both call sites share; neither comment is repeated here.
private func itemFitContentCrossSize(
    _ ctx: LayoutContext, _ tree: LayoutTree, _ kid: LayoutNodeID,
    mainSize: Double, isRow: Bool,
    containerCross: Double?, intrinsic: IntrinsicQuery,
    minCross: Double?, maxCross: Double?,
    marginCross: (leading: Double, trailing: Double),
    containingBlockWidth: Double?
) -> Double {
    let crossKnown = isRow ? OptionalSizeD(width: mainSize, height: nil)
                           : OptionalSizeD(width: nil, height: mainSize)
    let mainSpace = AvailableSpace.definite(mainSize)
    func measure(cross: AvailableSpace) -> SizeD {
        measureNode(
            ctx, tree, kid, known: crossKnown,
            available: AvailableSpaceSize(width: isRow ? mainSpace : cross,
                                          height: isRow ? cross : mainSpace),
            containingBlockWidth: containingBlockWidth)
    }
    let maxContent = measure(cross: .maxContent)
    let value = isRow
        ? maxContent.height
        : fitContentInlineSize(
            maxContent: maxContent.width, containerExtent: containerCross,
            margin: marginCross, intrinsic: intrinsic.width,
            minContent: { measure(cross: .minContent).width })
    return clamp(value, min: minCross, max: maxCross)
}

/// §10.3.5's fit-content on an INLINE axis,
/// `min(max(min-content, available), max-content)` — the arithmetic both
/// container types that size an `auto` inline axis share: a column item's
/// cross size (`itemFitContentCrossSize`, ruling TX-H) and a stack child's
/// width (`layOutStack`). One function so the two cannot disagree; until
/// review finding B-4 the stack measured max-content and they did.
///
/// `available` is `containerExtent` less the item's inline margins when the
/// container has an extent. Without one it comes from the container's own
/// intrinsic question: `.minContent` offers 0, collapsing the answer to
/// min-content; anything else offers nothing, and `nil` here means "infinite",
/// which is what max-content already answers. `minContent` is a closure
/// because it is a second measurement, taken **only** when max-content
/// overflows `available` — the ordinary case costs one measure.
private func fitContentInlineSize(
    maxContent: Double, containerExtent: Double?,
    margin: (leading: Double, trailing: Double),
    intrinsic: IntrinsicMode?, minContent: () -> Double
) -> Double {
    let available: Double? = containerExtent
        .map { $0 - margin.leading - margin.trailing }
        ?? (intrinsic == .minContent ? 0 : nil)
    guard let available, maxContent > available else { return maxContent }
    return max(minContent(), available)
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
        // **Two exclusions, and they are different kinds.** `display: none`
        // removes a box entirely; `position: absolute` removes it from *flow*
        // while leaving it in the tree for `placeNode` to position against its
        // containing block. An absolute box contributes nothing to this
        // container's size and occupies no space on either axis.
        .filter { tree.style($0).display != .none && tree.style($0).position != .absolute }
        .map { kid in
            // `mainEdges` is the padding and border `base` holds on the main
            // axis, which §9.7.4.c subtracts to weight shrink by the INNER base
            // size. **Take it from `flexBaseSize`, never re-resolve it here**:
            // whether the base holds the edges depends on which of its branches
            // ran — a content-sized measured leaf's does not — and nothing out
            // here can see that. Resolving them here for every item is the
            // version that shipped first and moved a padded `Text`
            // (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`).
            let (base, mainEdges) = flexBaseSize(ctx, tree, item: kid, isRow: isRow,
                                                 containerMain: containerMain,
                                                 containerCross: containerCross,
                                                 intrinsic: intrinsic)

            let ks = tree.style(kid)
            // The item's own border-box size, resolved from its style alone.
            //
            // **Hoisted above `minMain`, and the hoist is what ruling FS-3
            // needed.** This used to sit beside `ownCross` two hundred lines
            // down, which is still its main consumer; §4.5's *specified* size
            // suggestion needs the same number on the MAIN axis, and
            // `resolveNodeSize` is a pure function of the node's style and its
            // containing block, so calling it earlier changes nothing and
            // duplicating the call would leave two resolutions to keep agreed.
            //
            // Its main component is discarded by `ownCross` (§9.2's flex base
            // size supplies that axis) and is exactly what the specified size
            // suggestion is: ruling BM-4's floor is applied inside it, so under
            // `box-sizing: border-box` this is the item's **used** preferred
            // size, not its declared one.
            let own = resolveNodeSize(tree, kid, parent: parent, rootFontSize: rootFontSize)
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
            // **Ruling FS-3 — BOTH halves are implemented now.** §4.5's
            // automatic minimum is `min(specified size suggestion, content size
            // suggestion)`, and this engine implemented the content half alone
            // for four milestones. CLAUDE.md's divergence 5 recorded the gap;
            // it is closed, and `sizing_specified_suggestion` is the fixture.
            //
            // Measured against the oracle: `#root { width: 150px }` holding
            // `.a { display: flex; width: 130px }` whose child is 200 wide, and
            // `.b { width: 100px }`, gives WebKit — and now this engine —
            // `a` 130 / `b` 20. 130 is the discriminating width: flooring at
            // the content 200 gives 200 / 0, not flooring at all lets `.a`
            // shrink to 75, and only the `min` gives 130 / 20. `.b` is empty,
            // so its content suggestion is 0 and 0 wins its own `min` — which
            // is what stops "floor every item at its declared size" passing.
            //
            // **The specified size suggestion is the item's USED preferred
            // size, not its declared one, and ruling BM-4 is what makes those
            // differ.** Under `box-sizing: border-box` an over-constrained
            // `width: 100px` item whose padding and border come to 120 has a
            // specified size suggestion of **120** — which is why this reads
            // `own`, whose `resolveNodeSize` applies `borderBoxFloor`, rather
            // than resolving `ks.size` itself.
            //
            // **`sizing_over_constrained_grows` does NOT guard this reading,
            // and the plan's ruling said it did — measured false.** Taking the
            // declared 100 there leaves that fixture GREEN, because an
            // automatic minimum can only RAISE and `borderBoxFloor` has
            // already put the item's flex base size at 120: `min(100, 130)`
            // is below the base and never binds. The fixture that does guard
            // it is `sizing_specified_suggestion_is_used_value`, which adds a
            // **shrinking sibling** so the floor actually binds — WebKit 120/30
            // against the declared reading's 100/50. Its HTML comment carries
            // the arithmetic and the reason a sibling is required.
            //
            // **It exists only when the declared main size is DEFINITE.** An
            // `auto` main size has no preferred size to suggest, and neither
            // does a percentage against an indefinite container — CSS's
            // "definite" covers both, so the guard is on `resolveDimension`
            // coming back non-nil rather than on the declaration not being
            // `.auto`. `own` itself cannot express the difference: it maps an
            // unresolvable axis to 0 (then floors it), and a 0 suggestion
            // would floor every such item at its padding and border while
            // pretending to be the item's own width.
            // Hoisted above `minMain`, which clamps §4.5's automatic minimum by
            // it. A pure function of the item's style and `containerMain`, so
            // resolving it earlier changes nothing for `hypothetical` or for
            // `FlexItem.maxMain`, its other two readers.
            let maxMain = resolveDimension(isRow ? ks.maxSize.width : ks.maxSize.height,
                                           against: containerMain, rootFontSize: rootFontSize)
            let minDim = isRow ? ks.minSize.width : ks.minSize.height
            let specifiedMain: Double? = {
                let mainDim = isRow ? ks.size.width : ks.size.height
                guard resolveDimension(mainDim, against: containerMain,
                                       rootFontSize: rootFontSize) != nil else { return nil }
                return isRow ? own.width : own.height
            }()
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
            //
            // Hoisted above `minMain`, whose column probe subtracts
            // `marginCross` for the same reason. A pure function of the item's
            // style and `containerSize.width`, so resolving it earlier changes
            // nothing for its other readers.
            let margin = resolveMargin(ks.margin, against: containerSize.width,
                                       rootFontSize: rootFontSize)
            // Typed explicitly (not inferred) so `.leading`/`.trailing` are
            // usable locally, below, before either value reaches `FlexItem`'s
            // own labelled-tuple fields.
            let marginMain: (leading: Double, trailing: Double) =
                isRow ? (margin.left, margin.right) : (margin.top, margin.bottom)
            let marginCross: (leading: Double, trailing: Double) =
                isRow ? (margin.top, margin.bottom) : (margin.left, margin.right)
            // Resolved against `containerCross` — the containing block's cross
            // extent — NOT against the line's, which does not exist yet and
            // would in any case be the wrong basis for a percentage min/max.
            //
            // Resolved BEFORE `ownCross` below, which needs them: an `auto`
            // cross size is measured and then clamped by the item's own cross
            // min/max, exactly as `resolveNodeSize` clamps a declared one.
            // Hoisted above `minMain`, whose column probe clamps by them too.
            let minCross = resolveDimension(isRow ? ks.minSize.height : ks.minSize.width,
                                            against: containerCross, rootFontSize: rootFontSize)
            let maxCross = resolveDimension(isRow ? ks.maxSize.height : ks.maxSize.width,
                                            against: containerCross, rootFontSize: rootFontSize)
            let minMain: Double? = {
                if case .auto = minDim {
                    // **A FOURTH site with hardcoded intrinsic modes, and it
                    // stays hardcoded.** §4.5's content size suggestion IS the
                    // item's min-content size in the main axis, whatever the
                    // container was asked — so unlike `flexBaseSize`'s content
                    // branch, this probe must not take `intrinsic`.
                    //
                    // **In a column the probe is asked at the WIDTH layout
                    // will give the item, and it used to be asked at
                    // max-content.** A column's main axis is the block axis,
                    // so the item's min-content height depends on its width.
                    // At max-content width every wrapping row is one line.
                    // Measured through the WebKit oracle: a wrapping row of
                    // four 50x20 boxes over a 40-tall sibling in a 120x60
                    // column is 40 tall in WebKit and was 30 here.
                    // `sizing_column_content_suggestion`.
                    //
                    // The width is the one layout computes, not
                    // `containerCross`. A definite declared width is `own`'s,
                    // clamped and floored as `ownCross` takes it. Otherwise
                    // it is stretch's arithmetic from `layOutChildren`: the
                    // container's cross extent minus the item's cross
                    // margins, clamped by its cross min/max. Offering the bare
                    // `containerCross` was measured wrong three ways in that
                    // fixture (`margin-left: 40px`, `width: 80px`,
                    // `max-width: 80px`: WebKit 80, bare 40). A centred
                    // fit-content item is laid out at that width too. Its
                    // used width can be narrower only when its max-content
                    // fits, and then it is one line at either width.
                    //
                    // **The fallback is still max-content** when the
                    // container has no definite cross extent. That case
                    // computes the floor from the item's widest content even
                    // when the container is being asked for its min-content
                    // width. A column whose item reports 33 tall at
                    // min-content width and 77 at max-content gets a floor of
                    // 77 and answers 77. That looks exactly like the
                    // cross-axis query failing to propagate, and hid it from
                    // the first probe written for
                    // `theCrossAxisOfTheQueryReachesTheChildToo`. That test
                    // sets `min-height: 0` to switch this off.
                    //
                    // **§9.2's flex base size does not do the same yet.**
                    // `flexBaseSize` offers a column item the bare
                    // `containerCross`, so shapes where the floor does not
                    // bind stay wrong: `margin-left: 40px; min-height: 0` is
                    // 80 tall in WebKit and 40 here, and `min-width: 200px`
                    // is 20 in WebKit and 30 here.
                    //
                    // The ROW arm is unchanged: a row's cross axis is the
                    // block axis, which content-sizes, so max-content is
                    // right there.
                    //
                    // **`known: .unspecified` is deliberate and is MORE
                    // load-bearing now that both halves of ruling FS-3 are
                    // live, not less.** This probe must answer the CONTENT
                    // size suggestion alone; handing the item's own
                    // `width`/`height` down as `known` would make it answer
                    // the *specified* suggestion instead, and the `min` below
                    // would then be a `min` of one quantity with itself.
                    // Measured against WebKit: a `width: 120px` empty div
                    // shrinks to 75 in a row that overflows, because its
                    // content suggestion is 0 and 0 wins the `min`.
                    let probe: SizeD
                    if isRow {
                        probe = measureNode(ctx, tree, kid, known: .unspecified,
                                            available: AvailableSpaceSize(width: .minContent,
                                                                          height: .maxContent),
                                            containingBlockWidth: containerSize.width)
                    } else {
                        // A definite declared width goes down as `known`
                        // WIDTH only. `known.height` stays `nil`, so the probe
                        // still answers the content suggestion (see below).
                        let declaredWidth: Double? =
                            resolveDimension(ks.size.width, against: containerCross,
                                             rootFontSize: rootFontSize) == nil ? nil : own.width
                        let usedWidth: Double? = declaredWidth ?? containerCross.map {
                            clamp(Swift.max(0, $0 - marginCross.leading - marginCross.trailing),
                                  min: minCross, max: maxCross)
                        }
                        probe = measureNode(ctx, tree, kid,
                                            known: OptionalSizeD(width: declaredWidth, height: nil),
                                            available: AvailableSpaceSize(
                                                width: usedWidth.map { .definite($0) } ?? .maxContent,
                                                height: .minContent),
                                            containingBlockWidth: containerSize.width)
                    }
                    let content = isRow ? probe.width : probe.height
                    // §4.5: `min(specified size suggestion, content size
                    // suggestion)`, the specified one standing down when the
                    // item declares no definite main size.
                    let suggestion = specifiedMain.map { Swift.min($0, content) } ?? content
                    // **§4.5 clamps the automatic minimum by a definite max
                    // main size, and this branch did not.** A floor above the
                    // item's own `max-*` beats it (`clamp` applies the floor
                    // last), so an `auto`-width item whose min-content exceeds
                    // its `max-width` ignored the cap. Measured through the
                    // WebKit oracle: a `display: flex; max-width: 50px` item
                    // around a 200-wide `flex: none` child is 50 in WebKit and
                    // was 200 here. `sizing_max_clamps_content_suggestion`.
                    guard let maxMain, maxMain < suggestion else { return suggestion }
                    // **The clamp alone is the obvious fix and it is wrong.**
                    // Ruling BM-4's floor comes after the clamp, as it does in
                    // `resolveNodeSize`: `width: 100px; max-width: 40px` with
                    // 120 of padding and border is 120 in WebKit, which this
                    // engine answered only because the automatic minimum was
                    // unclamped. Clamping without the floor made it 40, and no
                    // test saw it.
                    // `sizing_max_below_floor_keeps_automatic_minimum` pins it.
                    //
                    // The floor is the edges the suggestion was measured WITH,
                    // so a measured leaf gets none. `measureNode` returns a
                    // leaf's `MeasureFunction` answer unchanged (record §05's
                    // leaf-padding row), so flooring a clamped leaf at its
                    // padding would give an inert modifier a live effect
                    // (`aClampedMeasuredLeafIsNotFlooredByItsInertPadding`).
                    //
                    // Reached only where the clamp bites, so every other item
                    // keeps exactly the suggestion it had.
                    guard tree.measure(kid) == nil else { return maxMain }
                    let edges = borderBoxFloor(tree, kid, containingBlockWidth: containerSize.width,
                                               rootFontSize: rootFontSize)
                    return Swift.max(maxMain, isRow ? edges.width : edges.height)
                }
                // An explicit `min-width` wins outright: it *replaces* the
                // automatic minimum rather than being combined with it, so an
                // item may be told to shrink below what its content needs.
                // Verified against WebKit with a probe fixture: 40 monospace
                // W's (min-content ~384px) inside `min-width: 150px` lays out
                // at exactly 150.
                return resolveDimension(minDim, against: containerMain, rootFontSize: rootFontSize)
            }()
            let hypothetical = clamp(base, min: minMain, max: maxMain)

            // `margin`, `marginMain` and `marginCross` are resolved above
            // `minMain`, which needs `marginCross` in a column.
            //
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
            // `own` is resolved near the top of this closure now — §4.5's
            // specified size suggestion needs it before `minMain`. Only its
            // cross component is read here.
            let align = resolvedAlignment(ks, container: s)
            var stretchEligible = false
            if align == .stretch, case .auto = crossDim { stretchEligible = true }
            // `minCross` and `maxCross` are resolved above `minMain`, which
            // clamps a column's §4.5 probe width by them.

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
            //    HYPOTHETICAL main size here — this call runs before §9.7 has
            //    resolved anything, so "the used main size" does not exist
            //    yet, and the base size clamped by the item's own main
            //    min/max (`hypothetical`) is the nearest approximation
            //    available at this point in the algorithm.
            //
            //    **This is only ever a placeholder now, per ruling TX-H — see
            //    `layOutChildren`'s own call to `itemFitContentCrossSize`,
            //    after `resolveFlexibleLengths` has run.** CSS Flexbox §9.4
            //    step 7 measures a non-stretched auto-cross item from its
            //    USED main size, i.e. after §9.7 (step 6) has flexed it, not
            //    from its hypothetical one — and an item that shrinks or
            //    grows can therefore report a cross size here that
            //    `layOutChildren` immediately supersedes. This first
            //    measurement still has to happen: `collectLines` breaks on
            //    hypothetical main sizes and a line's own (pre-flex) cross
            //    extent is measured from it, so an approximate value is
            //    needed before §9.7 can even run. Only the SECOND
            //    measurement, once the used main size exists, is what a
            //    caller reading `FlexItem.crossSize` after layout actually
            //    sees.
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
                return itemFitContentCrossSize(
                    ctx, tree, kid, mainSize: hypothetical, isRow: isRow,
                    containerCross: containerCross, intrinsic: intrinsic,
                    minCross: minCross, maxCross: maxCross, marginCross: marginCross,
                    containingBlockWidth: containerSize.width)
            }()

            // `targetMainSize:` here is dead — §9.7.2 overwrites it on every
            // item before it is read, and no empty-line path reaches
            // `positionItems`. It repeats `hypothetical` only because a
            // constructor must pass something; nothing depends on which value.
            // See the field's declaration.
            return FlexItem(node: kid, baseSize: base, mainEdges: mainEdges,
                            hypotheticalMainSize: hypothetical,
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
    containerSize: SizeD,
    containingBlock: ContainingBlock
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
        // `containingBlock` threads through unchanged, for the same reason
        // `positionStackItems` passes it unchanged: it is what `container`
        // established for its children, and `item.node` only replaces it for
        // ITS OWN descendants — inside the recursive call — if `item.node` is
        // itself positioned.
        placeNode(ctx, tree, item.node, origin: (x, y), size: size,
                  containingBlockWidth: containerSize.width, containingBlock: containingBlock)

        cursor += outerMain(item)
    }
}
