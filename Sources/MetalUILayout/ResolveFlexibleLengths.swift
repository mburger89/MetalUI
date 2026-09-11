import MetalUICore

/// CSS Flexbox §9.7 — resolve flexible lengths for one line.
///
/// The loop exists because clamping an item to its min or max frees space that
/// must be redistributed among the others. Each pass freezes the items whose
/// size is now final and repeats with what is left.
///
/// Three details that are easy to get wrong and that the tests pin:
///
/// - **Shrink is weighted by the INNER base size**, grow is not. Two items with
///   equal `flex-shrink` but different base sizes do not lose equal amounts — a
///   larger item gives up proportionally more. §9.7.4.c. "Inner" is the content
///   box: `baseSize` minus the main-axis padding and border it holds, which
///   `FlexItem.mainEdges` carries — all of them for a declared size or a
///   container, none for a content-sized measured leaf, whose base never
///   included them. `flex_row_shrink_padded_weighting` is WebKit's word on the
///   difference.
/// - **Gaps come out of free space before distribution.** They are part of the
///   line's consumed space, not something items may grow into.
/// - **Flex factors summing to less than one distribute only that fraction**
///   of the *initial* free space, leaving the rest unfilled. §9.7.4.b. Without
///   it `factor / factorTotal` normalises any set of factors to 1, so a lone
///   `flex-grow: 0.5` item would silently swallow all the free space and three
///   `0.25` items would close a row the browser leaves a quarter empty.
///   `flex_row_fractional_grow` is WebKit's word on that.
///
/// The container node itself is deliberately not a parameter: everything this
/// needs from it (`containerMain`, `gap`) is already resolved by the caller, and
/// taking the id as well would invite reading the container's style a second
/// time, in a different way, here. `isRow` and `rootFontSize` went the same way
/// when the §4.5 automatic minimum arrived: their only use was re-resolving each
/// item's main-axis min/max out of its style, which `collectItems` now does once
/// and hands over on `FlexItem`. Do not restore them to resolve a bound here —
/// see §9.7.4.d below for why that reintroduces a silent bug.
func resolveFlexibleLengths(
    _ tree: LayoutTree,
    items: inout [FlexItem],
    containerMain: Double,
    gap: Double
) {
    guard !items.isEmpty else { return }

    let totalGap = gap * Double(items.count - 1)

    // Every walk over `items` in this function is an index loop, including the
    // two sums here and below and the `while` condition, where `reduce` and
    // `contains(where:)` would read more naturally. That is deliberate: in a
    // debug build each of those two allocates per element of `[FlexItem]`
    // (measured with libmalloc's `malloc_logger` hook in this package's debug
    // test build: 2 per element for each), so the loop's allocation pin could
    // not see its own allocations past them. It is not a release cost: a
    // standalone `-O` build of the same sources, with both still in place, made
    // exactly one allocation per pass for the whole function — the violations
    // buffer — so neither allocated there. The sums are the same Doubles
    // either way: `reduce(0)` also starts at +0 and adds in index order.
    var hypotheticalTotal: Double = 0
    for i in items.indices { hypotheticalTotal += items[i].hypotheticalMainSize }

    // §9.7.1 — the used flex factor: grow if the items do not already fill the
    // line, shrink otherwise.
    //
    // The equality case is unobservable, so `<` and `<=` are interchangeable
    // here: when the sum exactly equals the container's main size the free space
    // is 0, and 0 distributed by grow factors and 0 distributed by shrink
    // factors are the same zero. The choice only becomes visible if free space
    // is ever nonzero at equality, which cannot happen — do not "fix" this to
    // match a differently-worded restatement of the spec and expect a fixture to
    // move.
    let usingGrow = hypotheticalTotal + totalGap < containerMain

    /// An item's **raw** flex factor — `flex-grow` or `flex-shrink` exactly as
    /// authored, with no base-size weighting. §9.7.4.b's sub-one test is
    /// specified on these; §9.7.4.c's distribution weights the shrink case by
    /// inner base size. Keeping the two apart is the whole reason this is its own
    /// function: letting the weighting leak into the sub-one sum would make the
    /// clause fire on the wrong items and at the wrong threshold — pinned by
    /// `fractionalShrinkScalesByRawFactorsNotWeightedOnes`.
    func rawFactor(_ item: FlexItem) -> Double {
        let s = tree.style(item.node)
        return usingGrow ? Double(s.flexGrow) : Double(s.flexShrink)
    }

    /// §9.7.4.c's distribution weight for an unfrozen item whose raw factor is
    /// `raw`: the raw factor itself for grow, scaled by the **inner** base size
    /// for shrink. The block at the distribution below says why inner, and why
    /// the `max(0, …)` stays. It takes `raw` rather than calling `rawFactor`
    /// so the summing walk, which needs both, reads the style once.
    func weightedFactor(_ item: FlexItem, raw: Double) -> Double {
        usingGrow ? raw : raw * max(0, item.baseSize - item.mainEdges)
    }

    // §9.7.2 — freeze items that cannot flex in the chosen direction.
    for i in items.indices {
        let inflexible = rawFactor(items[i]) == 0
            || (usingGrow && items[i].baseSize > items[i].hypotheticalMainSize)
            || (!usingGrow && items[i].baseSize < items[i].hypotheticalMainSize)
        if inflexible {
            items[i].targetMainSize = items[i].hypotheticalMainSize
            items[i].frozen = true
        } else {
            items[i].targetMainSize = items[i].baseSize
        }
    }

    // §9.7.3 — the *initial* free space, fixed once here. §9.7.4.b's sub-one
    // clause scales this, not the loop's shrinking `remaining`; recomputing it
    // each pass would let a sub-one line creep towards filling the container as
    // items froze. `flex_row_fractional_grow_clamped` is the browser's word.
    var startingSizes: Double = 0
    for i in items.indices {
        startingSizes += items[i].frozen ? items[i].targetMainSize : items[i].baseSize
    }
    let initialFreeSpace = containerMain - totalGap - startingSizes

    // Termination is provable **for a finite `containerMain`**: §9.7.4.e's three
    // branches are exhaustive and each freezes a nonempty set, so every pass
    // freezes at least one item and at most `items.count` passes can flex
    // anything, with one more to observe the line fully frozen. The cap costs
    // nothing in correct operation.
    //
    // It exists because both plausible ways to break §9.7.4.e — dropping the
    // zero-violation branch, or swapping the two violation signs — spin forever
    // rather than producing a wrong number. A hung CI job diagnoses nothing; a
    // named assertion diagnoses itself.
    //
    // **The cap is NOT "unreachable unless the freezing logic is broken", which
    // is what this comment said until the CONTENT-SIZING milestone measured
    // it.** A **non-finite `containerMain`** reaches it with the freezing logic
    // entirely intact: `inf - inf` and `inf * 0` are NaN, every comparison
    // against a NaN is false, so no item ever registers a violation, nothing
    // freezes, and the loop runs to the cap. Not hypothetical — `measureNode`
    // passed `.infinity` for an indefinite axis in its first version, and three
    // different one-child containers (a `flex-grow` item, a percentage width, a
    // percentage `gap`) each landed here. Ruling **CS-D** closed it at the
    // source: an indefinite axis is `nil`, and `layOutChildren` skips this
    // function rather than handing it a number that is not one. If you reach
    // this from a stack trace, look at the caller's `containerMain` before
    // looking at §9.7.4.e.
    //
    // **A release build has no assertion**, so this path silently freezes every
    // item at whatever it holds — under a NaN `containerMain`, NaN sizes, which
    // reach the stored rects and then the renderer. The debug trap is the only
    // thing that ever says so, which is why the guard above is a `precondition`
    // in spirit and an `assertionFailure` in fact: turning it into a hard trap
    // would take down a user's app for what is, in a correct engine,
    // unreachable.
    let maximumPasses = items.count + 1
    var passes = 0

    /// `items.contains(where: { !$0.frozen })`, as an index loop — see the
    /// note at `hypotheticalTotal` for why.
    func anyUnfrozen(_ items: [FlexItem]) -> Bool {
        for i in items.indices where !items[i].frozen { return true }
        return false
    }

    while anyUnfrozen(items) {
        passes += 1
        if passes > maximumPasses {
            assertionFailure("""
                §9.7 freeze loop did not converge: \(passes - 1) passes over \
                \(items.count) items, and \(items.filter { !$0.frozen }.count) \
                are still unfrozen, with containerMain = \(containerMain). Every \
                pass must freeze at least one item. If containerMain is not \
                finite THAT is the fault and §9.7.4.e is innocent — every \
                comparison against a NaN is false, so nothing ever freezes \
                (ruling CS-D). Otherwise §9.7.4.e's freezing logic is broken.
                """)
            for i in items.indices { items[i].frozen = true }
            break
        }

        // One walk gives every sum the pass needs, with no per-pass array.
        //
        // **Each sum is the same Double to the bit as the `filter(…).reduce`
        // it replaced**: every accumulator starts at +0 and adds the same items
        // in the same index order, and interleaving four accumulators in one
        // loop does not reorder any one of them. `factorTotal` used to be summed
        // over *every* item, a frozen one contributing a literal 0; skipping it
        // instead is exact, because a sum that starts at +0 can never become -0
        // and adding +0 to anything else is the identity.
        //
        // This used to be three `filter`s of whole `FlexItem`s, an `items.map`
        // and a dictionary per pass — allocations that grew with the line's item
        // count, to produce four scalars. Pinned by
        // `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`; the identical
        // arithmetic by `freezeLoopMatchesItsAllocatingReferenceBitForBit`.
        var frozenTotal: Double = 0
        var unfrozenBase: Double = 0
        var rawTotal: Double = 0
        var factorTotal: Double = 0
        for i in items.indices {
            if items[i].frozen {
                frozenTotal += items[i].targetMainSize
            } else {
                let raw = rawFactor(items[i])
                unfrozenBase += items[i].baseSize
                rawTotal += raw
                factorTotal += weightedFactor(items[i], raw: raw)
            }
        }
        var remaining = containerMain - totalGap - frozenTotal - unfrozenBase

        // §9.7.4.b — if the unfrozen items' raw factors sum to less than one,
        // they are entitled to only that fraction of the initial free space.
        //
        // The comparison is on **magnitudes**, not values, because free space is
        // negative while shrinking: `flex_row_fractional_shrink` has a remaining
        // of -100 against a scaled -50, where a bare `scaled < remaining` picks
        // the wrong one and gives 150/150 instead of the browser's 175/175.
        //
        // One narrow case here diverges from WebKit — free space positive and
        // the loop on its second pass. Blink and the spec agree with this code;
        // WebKit is the outlier. See CLAUDE.md's known-divergences section —
        // cited by its subject, "WebKit's flex sub-one clause", because the
        // heading counts them and the count has changed twice — and
        // `subOneScalingNeverExceedsTheRemainingFreeSpace`. `rawTotal` comes
        // from the walk above.
        if rawTotal < 1 {
            let scaled = initialFreeSpace * rawTotal
            if abs(scaled) < abs(remaining) { remaining = scaled }
        }

        // §9.7.4.c — distribute in proportion to the flex factor, which for
        // shrink is scaled by the item's **inner** flex base size: "multiply
        // its flex shrink factor by its inner flex base size".
        //
        // The inner size is `baseSize` minus `mainEdges`, the main-axis
        // padding and border that `baseSize` holds — which `flexBaseSize`
        // reports per branch, because a content-sized measured leaf's base holds
        // none. Weighting by the whole base was this line's reading until a
        // padded fixture existed, and every shrink test before it was blind to
        // the difference, because none of their items had padding or border.
        //
        // **The `max(0, …)` is a guard, not a pinned behaviour.** Replacing it
        // with a trap on a negative difference left the whole suite green, both
        // when this landed and again once the measured-leaf and content-sized
        // container cases had tests — no current input reaches it, so deleting
        // it would redden nothing. By reading rather than measurement: a
        // declared base is floored at the very value subtracted, a measured
        // leaf subtracts 0, and a container's base is its content plus those
        // edges. It stays because a negative weight would not merely be wrong:
        // it would hand a shrinking item growth.
        //
        // **A zero weight is a real answer, not an edge case.** When every
        // unfrozen item's inner base is 0 — `flex-basis: 0` with padding, say —
        // `factorTotal` is 0, the distribution below is skipped, each item keeps
        // its base, and the line overflows. WebKit does exactly that (80 / 80 in
        // a 100 row for two `flex: 0 1 0px; padding: 0 40px` items; the
        // border-box weighting gave 50 / 50, inside the padding). Pinned by
        // `aLineWhoseItemsHaveNoInnerBaseSizeOverflowsInsteadOfShrinking`.
        //
        // The weight is `weightedFactor`, and `factorTotal` was summed by the
        // walk above; each item's weight is recomputed here rather than kept in
        // an array, from the same style and the same fields, so it is the same
        // Double that went into the total.
        if factorTotal > 0 {
            for i in items.indices where !items[i].frozen {
                // The share is added to the item's **base** size, not to zero:
                // `flex: 1 1 100px` keeps its 100 and grows on top of it.
                // Every growing item in the corpus used to have `flex-basis: 0`,
                // which made the two indistinguishable —
                // `flex_row_grow_nonzero_basis` exists to separate them.
                let factor = weightedFactor(items[i], raw: rawFactor(items[i]))
                items[i].targetMainSize = items[i].baseSize + remaining * (factor / factorTotal)
            }
        }

        // §9.7.4.d — clamp each item to its own min/max, recording by how much.
        //
        // The bounds come from `FlexItem`, resolved once by `collectItems`
        // against the container's **main** axis — `flex_column_grow_with_max`
        // caps an item's *height*, which a row-only reading would look up as
        // `maxSize.width` and silently not apply. They are deliberately not
        // re-resolved from the style here: `minMain` is no longer derivable from
        // the style alone, since `min-width: auto` resolves through the item's
        // measure function (CSS Sizing §4.5). A style-only `resolveDimension`
        // returns nil for `.auto` and would drop every automatic floor on the
        // floor without a single test noticing, because the same floor is also
        // applied to `hypotheticalMainSize` — where it is usually a no-op.
        //
        // `violation` is indexed like `items` and allocated per pass, so no
        // entry outlives the pass that wrote it. A frozen item's entry stays 0,
        // which neither direction in §9.7.4.e freezes — exactly as the
        // `[Int: Double]` this replaced held no entry for it at all. Its old
        // iteration order was a dictionary's, i.e. undefined, and nothing
        // depended on it: freezing is idempotent and order-free. What matters
        // is the branch the total selects and that only violators in that
        // direction freeze, and both are unchanged.
        var totalViolation: Double = 0
        var violation = ContiguousArray<Double>(repeating: 0, count: items.count)
        for i in items.indices where !items[i].frozen {
            // An item may never go negative, whatever its min says.
            let bounded = max(0, clamp(items[i].targetMainSize,
                                       min: items[i].minMain, max: items[i].maxMain))
            let v = bounded - items[i].targetMainSize
            violation[i] = v
            totalViolation += v
            items[i].targetMainSize = bounded
        }

        // §9.7.4.e — freeze ONLY the items that violated, in the direction the
        // total says. Freezing everything on a nonzero violation would skip the
        // redistribution this loop exists to perform; freezing nothing would
        // never terminate. Termination holds because a nonzero total guarantees
        // at least one item violated in that direction.
        if totalViolation == 0 {
            for i in items.indices { items[i].frozen = true }
        } else if totalViolation > 0 {
            for i in items.indices where violation[i] > 0 { items[i].frozen = true }   // min violations
        } else {
            for i in items.indices where violation[i] < 0 { items[i].frozen = true }   // max violations
        }
    }
}
