import MetalUICore

/// CSS Flexbox §9.7 — resolve flexible lengths for one line.
///
/// The loop exists because clamping an item to its min or max frees space that
/// must be redistributed among the others. Each pass freezes the items whose
/// size is now final and repeats with what is left.
///
/// Three details that are easy to get wrong and that the tests pin:
///
/// - **Shrink is weighted by base size**, grow is not. Two items with equal
///   `flex-shrink` but different base sizes do not lose equal amounts — a larger
///   item gives up proportionally more. §9.7.4.b.
/// - **Gaps come out of free space before distribution.** They are part of the
///   line's consumed space, not something items may grow into.
/// - **Flex factors summing to less than one distribute only that fraction**
///   of the *initial* free space, leaving the rest unfilled. §9.7.4.a. Without
///   it `factor / factorTotal` normalises any set of factors to 1, so a lone
///   `flex-grow: 0.5` item would silently swallow all the free space and three
///   `0.25` items would close a row the browser leaves a quarter empty.
///   `flex_row_fractional_grow` is WebKit's word on that.
///
/// The container node itself is deliberately not a parameter: everything this
/// needs from it (`containerMain`, `gap`, `isRow`) is already resolved by the
/// caller, and taking the id as well would invite reading the container's style
/// a second time, in a different way, here.
func resolveFlexibleLengths(
    _ tree: LayoutTree,
    items: inout [FlexItem],
    containerMain: Double,
    gap: Double,
    isRow: Bool,
    rootFontSize: Double
) {
    guard !items.isEmpty else { return }

    let totalGap = gap * Double(items.count - 1)
    let hypotheticalTotal = items.reduce(0) { $0 + $1.hypotheticalMainSize }
    let usingGrow = hypotheticalTotal + totalGap < containerMain

    /// An item's **raw** flex factor — `flex-grow` or `flex-shrink` exactly as
    /// authored, with no base-size weighting. §9.7.4.a's sub-one test is
    /// specified on these; §9.7.4.b's distribution weights the shrink case by
    /// base size. Keeping the two apart is the whole reason this is its own
    /// function: letting the weighting leak into the sub-one sum would make the
    /// clause fire on the wrong items and at the wrong threshold.
    func rawFactor(_ item: FlexItem) -> Double {
        let s = tree.style(item.node)
        return usingGrow ? Double(s.flexGrow) : Double(s.flexShrink)
    }

    // §9.7.1 — freeze items that cannot flex in the chosen direction.
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

    // §9.7.3 — the *initial* free space, fixed once here. §9.7.4.a's sub-one
    // clause scales this, not the loop's shrinking `remaining`; recomputing it
    // each pass would let a sub-one line creep towards filling the container as
    // items froze.
    let initialFreeSpace = containerMain - totalGap - items.reduce(0) {
        $0 + ($1.frozen ? $1.targetMainSize : $1.baseSize)
    }

    // The loop terminates because every pass freezes at least one item.
    while items.contains(where: { !$0.frozen }) {
        let frozenTotal = items.filter(\.frozen).reduce(0) { $0 + $1.targetMainSize }
        let unfrozenBase = items.filter { !$0.frozen }.reduce(0) { $0 + $1.baseSize }
        var remaining = containerMain - totalGap - frozenTotal - unfrozenBase

        // §9.7.4.a — if the unfrozen items' raw factors sum to less than one,
        // they are entitled to only that fraction of the initial free space.
        // The magnitude test is what keeps this from *increasing* the space
        // distributed once clamping has already eaten into it.
        //
        // **KNOWN DIVERGENCE FROM THE ORACLE — the magnitude test is the one
        // line in this file WebKit contradicts.** It only bites when the loop
        // runs twice *and* the factors sum below one, which needs a min/max
        // violation to force the second pass. Probe fixture:
        //
        //     #root { display: flex; width: 400px; }
        //     .a { flex: 0.25 1 0; min-width: 350px; }
        //     .b { flex: 0.25 1 0; }
        //
        // Pass 2 has remaining free space 50 (400 - a's clamped 350) and a
        // scaled value of 100 (initial 400 x 0.25). The spec says |100| is not
        // less than |50|, so `b` gets 50 and the row closes exactly on 400.
        // **WebKit gives `b` 100 and lets the row overflow to 450** — i.e. it
        // behaves as if this `abs` guard were absent.
        //
        // The spec reading is kept because ruling F-2 mandates this clause in
        // writing and because overflowing a definite container on a *grow* pass
        // is the less defensible of the two answers. It is a deliberate,
        // recorded choice, not an oversight, and it is pinned by
        // `subOneScalingNeverExceedsTheRemainingFreeSpace` in FreezeLoopTests —
        // read that test's comment before changing this line. No fixture is
        // committed for the probe above precisely because the corpus is the
        // browser's word and we are knowingly not taking it here.
        let rawTotal = items.filter { !$0.frozen }.reduce(0) { $0 + rawFactor($1) }
        if rawTotal < 1 {
            let scaled = initialFreeSpace * rawTotal
            if abs(scaled) < abs(remaining) { remaining = scaled }
        }

        // §9.7.4.b — distribute in proportion to the flex factor, which for
        // shrink is scaled by the base size.
        let factors: [Double] = items.map { item in
            guard !item.frozen else { return 0 }
            return usingGrow ? rawFactor(item) : rawFactor(item) * item.baseSize
        }
        let factorTotal = factors.reduce(0, +)

        if factorTotal > 0 {
            for i in items.indices where !items[i].frozen {
                items[i].targetMainSize = items[i].baseSize + remaining * (factors[i] / factorTotal)
            }
        }

        // §9.7.4.c/d — clamp, then freeze according to the sign of the total
        // violation. Freezing only the violating items is what makes the loop
        // converge instead of oscillating.
        var totalViolation: Double = 0
        var violation: [Int: Double] = [:]
        for i in items.indices where !items[i].frozen {
            let s = tree.style(items[i].node)
            let lower = resolveDimension(isRow ? s.minSize.width : s.minSize.height,
                                         against: containerMain, rootFontSize: rootFontSize)
            let upper = resolveDimension(isRow ? s.maxSize.width : s.maxSize.height,
                                         against: containerMain, rootFontSize: rootFontSize)
            // An item may never go negative, whatever its min says.
            let bounded = max(0, clamp(items[i].targetMainSize, min: lower, max: upper))
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
            for (i, v) in violation where v > 0 { items[i].frozen = true }   // min violations
        } else {
            for (i, v) in violation where v < 0 { items[i].frozen = true }   // max violations
        }
    }
}
