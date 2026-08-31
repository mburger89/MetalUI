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
func flexBaseSize(
    _ ctx: LayoutContext,
    _ tree: LayoutTree,
    item: LayoutNodeID,
    isRow: Bool,
    containerMain: Double?,
    containerCross: Double?,
    intrinsic: IntrinsicQuery
) -> Double {
    let rootFontSize = ctx.rootFontSize
    let s = tree.style(item)

    // The item's containing block is the container's CONTENT box, whose width
    // is the container's main extent in a row and its cross extent in a column
    // — the same `box.size.width` `collectItems` was handed, re-derived from
    // the two axis-resolved extents this function already takes rather than
    // added as a fifth parameter that would have to be kept agreeing with them.
    //
    // Hoisted above step 1 because ruling BM-4's floor in step 2 needs it as
    // the basis for this item's own percentage padding and border; step 3's
    // `measureNode` call is the other consumer.
    let containingBlockWidth = isRow ? containerMain : containerCross

    // 1. Definite flex-basis.
    //
    // **Deliberately NOT floored at the item's padding + border**, unlike step
    // 2 below — ruling BM-4 is about the size PROPERTY, and the differential
    // was measured rather than assumed: `flex: 0 0 100px; min-width: 0` with
    // 120 of horizontal padding+border measures **100** in WebKit, where the
    // same box spelled `width: 100px; min-width: 0` measures **120**.
    if let basis = resolveDimension(s.flexBasis, against: containerMain,
                                    rootFontSize: rootFontSize) {
        return basis
    }

    // 2. flex-basis: auto -> the main size property, if definite.
    //
    // Ruling BM-4 — a declared size is floored at the item's own padding +
    // border (`borderBoxFloor`), because `box-sizing: border-box` defines the
    // used size as `max(specified, padding + border)`. Reachable on the main
    // axis only when the item carries an explicit `min-width`/`min-height`
    // below that floor: §4.5's automatic minimum is the item's min-content
    // size, which already includes its padding and border, so the default
    // floor is never lower. Measured: `width: 100px; min-width: 0` with
    // `padding: 0 50px; border-width: 0 10px` is **120** in WebKit and was
    // 100 here. Pinned by `anItemWithMinZeroStillGrowsToFitItsPaddingAndBorder`.
    let mainDim = isRow ? s.size.width : s.size.height
    if let main = resolveDimension(mainDim, against: containerMain,
                                   rootFontSize: rootFontSize) {
        let floor = borderBoxFloor(tree, item, containingBlockWidth: containingBlockWidth,
                                   rootFontSize: rootFontSize)
        return max(main, isRow ? floor.width : floor.height)
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
    return isRow ? measured.width : measured.height
}
