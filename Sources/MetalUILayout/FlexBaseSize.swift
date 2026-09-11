import MetalUICore

/// CSS Flexbox §9.2 — a flex item's base size, before min/max clamping.
///
/// **This is deliberately not part of `resolveNodeSize`.** An item's main size
/// comes from this cascade; only its cross size comes from its own style. Merging
/// the two would recreate the "auto means the container's extent" fallback that
/// m1a ruling PF-3 removed, and that failure is silent.
///
/// The cascade, in spec order:
/// 1. a definite `flex-basis` wins outright, even over an explicit `width`;
/// 2. `flex-basis: auto` defers to the main size property, if that is definite;
/// 3. otherwise the item is content-sized — its measure function under **the
///    container's own question** in the main axis.
///
/// Step 3's main axis was a hardcoded `.maxContent` until the intrinsic query
/// was threaded into the recursion. That is the whole of `intrinsic` here: a
/// container asked for its min-content size must ask its items for theirs, and
/// a hardcoded max-content silently answered the wrong one of the two
/// questions. It is `nil` per axis for real layout, and non-nil only where the
/// matching container extent is `nil` — so `containerCross` below is consulted
/// first and the question is the fallback, never a competing answer.
///
/// **Step 3 asks `measureNode`, not `tree.measure(item)`.** It went straight to
/// the measure function and returned 0 when there was none, so a **container**
/// with no measure function reported 0 for its own content — one of the four
/// sites that substituted a constant for a subtree's size. `measureNode`
/// answers for a container by running the flex algorithm over its children and
/// for a leaf from its `MeasureFunction`, and the caller cannot tell which
/// happened.
///
/// What survives of the old "an item with no measure function is 0" note is
/// the case it now describes exactly: a **childless leaf** with no measure
/// function still reports 0, because `measureNode` returns its padding and
/// border and that is 0 for such a node. That is honest rather than
/// convenient — a zero-width box is visibly wrong where a container-width box
/// is plausibly wrong. It is no longer a statement about containers.
///
/// **It also reports `mainEdges`: how much of that size is the item's own
/// main-axis padding and border.** §9.7.4.c weights shrink by the INNER base
/// size, and only the branch that produced a base knows what it put in it:
/// - steps 1 and 2 floor a declared size at those edges (ruling BM-4), so the
///   base holds them and `mainEdges` is the floor;
/// - step 3 on a **container** holds them too: `measureNode` adds `contentBox`'s
///   `edges` back onto what the children come to, resolved against the same
///   `containingBlockWidth` the floor uses;
/// - step 3 on a **measured leaf** holds none: `measureNode` returns a
///   `MeasureFunction`'s answer unchanged, because a leaf's box model is not
///   implemented (record §05's leaf-padding row). `mainEdges` is 0, so the
///   padding stays out of the weight exactly as it stays out of the size.
///   Subtracting it anyway put a padded content-sized leaf at 83 / 17 in a row
///   where its unpadded twin is 50 / 50 —
///   `aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`.
///
/// Asking the caller to resolve the edges itself is how that last case went
/// wrong: the caller cannot see which branch ran.
func flexBaseSize(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    item: LayoutNodeID,
    isRow: Bool,
    containerMain: Double?,
    containerCross: Double?,
    intrinsic: IntrinsicQuery
) -> (size: Double, mainEdges: Double) {
    let rootFontSize = ctx.rootFontSize
    let s = tree.style(item)

    // The item's containing block is the container's CONTENT box, whose width
    // is the container's main extent in a row and its cross extent in a column
    // — the same `box.size.width` `collectItems` was handed, re-derived from
    // the two axis-resolved extents this function already takes rather than
    // added as a fifth parameter that would have to be kept agreeing with them.
    //
    // Hoisted above step 1 because ruling BM-4's floor needs it as the basis
    // for this item's own percentage padding and border; step 3's
    // `measureNode` call is the other consumer.
    let containingBlockWidth = isRow ? containerMain : containerCross

    // Ruling BM-4's floor on this item's main axis: `box-sizing: border-box`
    // defines a used size as `max(specified, padding + border)`, so neither of
    // the two declared branches below may return less than the item's own
    // edges. A function rather than a `let` because step 3 needs it only for a
    // container, to report the edges `measureNode` added back; a measured leaf
    // on that path never pays for its two `resolveEdges` walks.
    //
    // **Both declared branches take it, and an earlier version of this file
    // floored only step 2 on the strength of a bad measurement.** That probe
    // put its box ALONE in its flex container, which is a shape where WebKit
    // answers incoherently — it reports a border box NARROWER than the padding
    // and border it contains (100 against 120, and 0 against 120 for
    // `flex-basis: 0`), which is geometrically impossible, padding being inside
    // the border box by definition. Add any in-flow sibling and the same four
    // spellings all measure **120**:
    //
    //     flex: 0 0 100px; min-width: 0                              -> 120
    //     flex-basis: 100px; flex-grow:0; flex-shrink:0; min-width:0 -> 120
    //     flex-basis: 100px; flex-grow:0; flex-shrink:0              -> 120
    //     width: 100px; flex: 0 0 auto; min-width: 0                 -> 120
    //     the same with box-sizing: content-box                      -> 220
    //
    // Alone in its container, the first three of those measure 100 and the
    // fourth still measures 120. So there is no `flex-basis`-versus-`width`
    // rule to encode — there is a WebKit inconsistency, and the spec settles
    // it: CSS Flexbox §7.2.3 says `flex-basis` is "interpreted the same as
    // `width`", which makes `box-sizing` apply to it. The engine floors both.
    func mainFloor() -> Double {
        let floor = borderBoxFloor(tree, item, containingBlockWidth: containingBlockWidth,
                                   rootFontSize: rootFontSize)
        return isRow ? floor.width : floor.height
    }

    // 1. Definite flex-basis.
    if let basis = resolveDimension(s.flexBasis, against: containerMain,
                                    rootFontSize: rootFontSize) {
        let floor = mainFloor()
        return (max(basis, floor), floor)
    }

    // 2. flex-basis: auto -> the main size property, if definite.
    //
    // Reachable on the main axis only when the item carries an explicit
    // `min-width`/`min-height` below the floor: §4.5's automatic minimum is the
    // item's min-content size, which already includes its padding and border,
    // so the default floor is never lower. Measured: `width: 100px;
    // min-width: 0` with `padding: 0 50px; border-width: 0 10px` is **120** in
    // WebKit and was 100 here. Pinned by
    // `anItemWithMinZeroStillGrowsToFitItsPaddingAndBorder`.
    let mainDim = isRow ? s.size.width : s.size.height
    if let main = resolveDimension(mainDim, against: containerMain,
                                   rootFontSize: rootFontSize) {
        let floor = mainFloor()
        return (max(main, floor), floor)
    }

    // 3. Content size, under the CONTAINER's own question in the main axis.
    let known = OptionalSizeD(
        width: isRow ? nil : resolveDimension(s.size.width, against: containerCross,
                                              rootFontSize: rootFontSize),
        height: isRow ? resolveDimension(s.size.height, against: containerCross,
                                         rootFontSize: rootFontSize) : nil)
    // The container's question, per axis, with `.maxContent` as the fallback it
    // has always had.
    //
    // **The two `?? .maxContent`s are not the same.** The main one is live and
    // load-bearing: a `nil` mode there is real layout (`placeNode`) or an axis
    // the caller made definite, and both still offer the item max-content,
    // which is what keeps the intrinsic-query change behaviour-preserving.
    //
    // The CROSS one is **unreachable**, and by construction rather than by
    // observation. Ruling CS-H's invariant is that an axis carries a mode iff
    // that axis of the probe is `nil`, and `contentBox` maps `nil` to `nil`
    // per axis — so `containerCross == nil` and "the cross mode is non-nil"
    // are the same condition. When `containerCross` is non-nil the `.map`
    // fires and the inner `??` is never evaluated; when it is `nil` the mode
    // is always there. Measured: replacing the inner `?? .maxContent` with
    // `fatalError()` leaves the whole suite green. It is kept only so the
    // expression is a total function and does not depend on an invariant
    // enforced two files away; delete it only together with that invariant.
    // (An earlier version of this comment claimed the opposite — that the
    // cross fallback was live for `placeNode` — which is exactly the case
    // where `containerCross` IS definite.)
    let mainAvailable = (isRow ? intrinsic.width : intrinsic.height)?.availableSpace ?? .maxContent
    let crossAvailable = containerCross.map { AvailableSpace.definite($0) }
        ?? ((isRow ? intrinsic.height : intrinsic.width)?.availableSpace ?? .maxContent)
    let available = AvailableSpaceSize(
        width: isRow ? mainAvailable : crossAvailable,
        height: isRow ? crossAvailable : mainAvailable)
    let measured = measureNode(ctx, tree, item, known: known, available: available,
                               containingBlockWidth: containingBlockWidth)
    // What that size holds of the item's own edges (this function's doc).
    // `measureNode` branches on exactly this test: a node with a
    // `MeasureFunction` gets its answer back unchanged, and anything else has
    // `contentBox`'s `edges` added, resolved against the `containingBlockWidth`
    // passed just above — the basis `mainFloor()` uses, so the two agree.
    let mainEdges = tree.measure(item) == nil ? mainFloor() : 0
    return (isRow ? measured.width : measured.height, mainEdges)
}
