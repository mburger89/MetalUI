import MetalUICore

public struct ResolvedEdges: Sendable, Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }

    public static let zero = ResolvedEdges(top: 0, right: 0, bottom: 0, left: 0)
}

/// Resolve a length against its containing block.
///
/// Returns nil when the value cannot be resolved — a percentage against an
/// indefinite parent. CSS treats that as `auto`, and callers must too.
///
/// The percentage product is formed in `Float`, the precision the fraction is
/// stored at, and only then widened — the honest conversion boundary, since the
/// fraction never had more than `Float` precision to begin with. This *reduces*
/// the storage noise rather than eliminating it. Neither ordering is exact and
/// neither dominates: widening first makes `10%` of `200` visibly worse
/// (20.000000298023224 rather than 20), while this order makes `9%` of `300`
/// slightly worse (27.000001907348633 rather than 27.000001072883606). Treat
/// the result as carrying ~1e-4pt of error and compare it with a tolerance
/// rather than for equality; that is roughly 130x below WebKit's 1/64 quantum.
///
/// **That error DOES reach a fixture, and the "130x below the quantum" argument
/// is what hides it** (ruling WR-5). Cumulative rounding amplifies it at a .5
/// boundary: `flex: 1 0 60%` beside `flex: 0 0 15%` in a 400px container with
/// `padding: 0 20px 0 30px` and `column-gap: 12px` gives an exact 285.5, but 60%
/// of the 350 content box is `210.00001525878906` in `Float`, which drags the
/// sum to `285.49999618` — the wrong side of `roundLayout`'s boundary. WebKit
/// says 286/328; this engine says 285/327.
///
/// Not a wrapping bug: it reproduces under `nowrap`, and reproduces via `Float`
/// `flexGrow`/`flexShrink` with no percentage anywhere. Fixing it is a units
/// decision — widen the product, or round on a different rule — not a layout one,
/// so it is recorded rather than patched here. Do not restore the old claim that
/// this never reaches a fixture; it was measured.
public func resolveLength(_ l: Length, against parent: Double?, rootFontSize: Double) -> Double? {
    switch l {
    case .pixels(let p): Double(p.value)
    case .rems(let r):   Double(r.value) * rootFontSize
    case .percent(let f): parent.map { Double(f * Float($0)) }
    }
}

/// Resolve a `Dimension` against its containing block.
///
/// **`.auto` means different things in different fields.** For `Style.size` and
/// `Style.inset` it means "derive from content". For `Style.maxSize` it means
/// **unconstrained** — CSS's initial value for `max-width`/`max-height` is
/// `none`, and `Dimension` has no `none` case, so `.auto` stands in for it (the
/// Taffy convention). Either way this function returns nil, and it is the
/// caller's job to read that nil correctly: an unresolved `maxSize` must impose
/// no upper bound, never a content-derived one. Getting this backwards produces
/// wrong clamping that only surfaces later, in fixtures.
public func resolveDimension(_ d: Dimension, against parent: Double?, rootFontSize: Double) -> Double? {
    switch d {
    case .auto: nil
    case .length(let l): resolveLength(l, against: parent, rootFontSize: rootFontSize)
    }
}

/// Resolve all four edges. Percentages resolve against `parent`, which callers
/// must supply as the containing block's **width** even for top and bottom —
/// that is CSS's rule, not a simplification.
///
/// **`contentBox` in `FlexEngine.swift` is the caller**, and since the BOX
/// MODEL milestone's third task it is a real one: from M1a until the box-model work this function was fully
/// unit-tested with no production caller at all, and "callers must supply"
/// described nobody.
///
/// It supplies the containing block's width, which is **not** the width of the
/// box whose padding is being resolved. For a flex item that is its flex
/// container's *content* box; for the root it is the extent `computeLayout` was
/// offered. `contentBox` passed the box's own border-box width until that same
/// task — wrong for every box narrower than its parent's content box, and invisible
/// because no fixture had percentage padding. See `contentBox`'s own comment
/// for WebKit's numbers.
///
/// `parent` is optional because a containing block can be indefinite; every
/// percentage edge then resolves to 0, which is CSS's rule for an unresolvable
/// percentage and not a stand-in for anything.
public func resolveEdges(_ e: Edges<Length>, against parent: Double?, rootFontSize: Double) -> ResolvedEdges {
    func r(_ l: Length) -> Double {
        resolveLength(l, against: parent, rootFontSize: rootFontSize) ?? 0
    }
    return ResolvedEdges(top: r(e.top), right: r(e.right), bottom: r(e.bottom), left: r(e.left))
}

/// Resolve margin edges, which — unlike padding and border — may be `auto`.
///
/// Percentages resolve against `parent`, which callers must supply as the
/// containing block's **width** even for top and bottom — the same CSS rule
/// `resolveEdges` follows.
///
/// **`collectItems` in `FlexEngine.swift` is the caller**, and it supplies the
/// container's *content*-box width. That is already the containing block: an
/// item's containing block IS its flex container's content box, so unlike
/// `resolveEdges` — which is called for a box's own padding and therefore needs
/// its *parent's* width — the value in hand here is the right one. The two
/// functions read alike and are reached from opposite directions; do not
/// "harmonise" them.
public func resolveMargin(_ e: Edges<Dimension>, against parent: Double?,
                          rootFontSize: Double) -> ResolvedEdges {
    func r(_ d: Dimension) -> Double {
        // `resolveDimension` returns nil for TWO unrelated reasons, and this
        // `?? 0` answers both the same way for opposite reasons:
        //
        // 1. `d` is `.auto`. **This resolves to 0, and that is not CSS.** An
        //    auto margin absorbs free space *before* `justify-content`
        //    distributes any, so a CSS `margin-left: auto` pushes its item to
        //    the end of the line; here it does nothing. THIS is the line
        //    where that gets implemented — not the doc comment above, this
        //    `?? 0`. Until it does, the `margin: auto` row in CLAUDE.md's
        //    inert-API table stands.
        // 2. `d` is a percentage and `parent` is nil (an indefinite
        //    containing block). This is correct, unremarkable CSS — the same
        //    "unresolvable percentage treated as auto, which resolves to
        //    0-for-margin" rule `resolveEdges` already follows for padding
        //    and border — and has nothing to do with gap 1. It is not a
        //    deliberate omission and needs no fixing.
        //
        // Do not conflate the two if this line ever grows a real `.auto`
        // implementation: only case 1 changes then, and case 2 must keep
        // resolving to 0 exactly as it does today.
        resolveDimension(d, against: parent, rootFontSize: rootFontSize) ?? 0
    }
    return ResolvedEdges(top: r(e.top), right: r(e.right), bottom: r(e.bottom), left: r(e.left))
}

/// Clamp to min/max, with min taking precedence when they conflict (CSS §10.4).
public func clamp(_ value: Double, min lower: Double?, max upper: Double?) -> Double {
    var v = value
    if let upper { v = Swift.min(v, upper) }
    if let lower { v = Swift.max(v, lower) }
    return v
}
