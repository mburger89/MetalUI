import MetalUICore

/// One flex line: the items collected onto it, and the cross size measured for
/// it.
///
/// **Assembled by the engine, not by `collectLines`** (ruling WR-2). The break
/// decision is a pure function over items — no styles, no cross sizes — so it
/// stays testable alone and reusable by Grid, for the same reason
/// `lineContentSize` takes `[Double]` rather than `[FlexItem]`. This type is
/// where `layoutContainer` pairs a returned line with the cross size it then
/// computes for it, and it exists so that every line's cross size is known
/// *before* any line is positioned — which is what `align-content` (Task 2)
/// needs and this task does not yet use for anything but stacking.
///
/// `items` is `var` because §9.7 mutates a line's items in place: the freeze
/// loop runs **per line**, over this array.
struct FlexLine {
    var items: [FlexItem]
    /// The line's cross extent. For a `nowrap` container this is the
    /// container's content-box cross extent (§9.4.8's single-line clause, and
    /// the reason `nowrap` layouts are byte-identical to what they were before
    /// wrapping existed); for a wrapped container it is `lineCrossSize`.
    var crossSize: Double
}

/// CSS Flexbox §9.3 — collect items into flex lines.
///
/// **Breaking uses hypothetical main sizes, not flexed ones.** An item's flexed
/// size is not known until §9.7 runs, and §9.7 runs *per line* — so breaking on
/// flexed sizes would be circular. Break first, flex second.
///
/// An item that does not fit on an empty line stays on it anyway and overflows;
/// a line is never empty. Without that guard an oversized item produces an empty
/// line before it and every subsequent index shifts.
///
/// **`.wrapReverse` collects lines exactly like `.wrap` here and is NOT
/// reversed anywhere else** — Task 3 owns that, and until then a
/// `wrap-reverse` container wraps but stacks its lines cross-start to
/// cross-end, i.e. it lays out as `wrap`. Recorded in CLAUDE.md's inert-API
/// table and pinned by `wrapReverseCollectsLinesButDoesNotReverseThemYet`;
/// deleting either without implementing the reversal is how a half-rule goes
/// silent.
func collectLines(
    _ items: [FlexItem],
    wrap: FlexWrap,
    containerMain: Double,
    gap: Double
) -> [[FlexItem]] {
    guard wrap != .noWrap else { return items.isEmpty ? [] : [items] }

    var lines: [[FlexItem]] = []
    var current: [FlexItem] = []
    var used: Double = 0

    for item in items {
        let outer = item.marginMain.leading + item.hypotheticalMainSize + item.marginMain.trailing
        let withGap = current.isEmpty ? outer : used + gap + outer
        // `>`, not `>=`: CSS breaks when the next item "would not fit", and an
        // item that fits to the pixel fits. `flex_wrap_uneven` is 218 wide for
        // exactly this reason — its third child closes the line at 218 — so
        // this comparison has a browser-checked boundary.
        if !current.isEmpty && withGap > containerMain {
            lines.append(current)
            current = [item]
            used = outer
        } else {
            current.append(item)
            used = withGap
        }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

/// CSS Flexbox §9.4.8 — a line's cross size is the largest **outer** cross size
/// among its items: each item's border box plus its own cross margins.
///
/// A single-line (`nowrap`) container does not use this: its line's cross size is
/// the container's content-box cross extent, which is definite. That distinction
/// is why `nowrap` layouts are unchanged by this plan.
///
/// **Axis-blind on purpose.** The brief's signature took an `isRow:` flag; it
/// had no body to be used in, because `crossSize` and `marginCross` are already
/// axis-resolved by `collectItems`. A parameter that exists and does nothing is
/// this repo's most-repeated bug shape, so it is not here.
func lineCrossSize(_ items: [FlexItem]) -> Double {
    items.reduce(0.0) {
        Swift.max($0, $1.marginCross.leading + $1.crossSize + $1.marginCross.trailing)
    }
}
