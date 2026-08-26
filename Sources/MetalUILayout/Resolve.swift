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
/// rather than for equality; that is roughly 130x below WebKit's 1/64 quantum,
/// so it never reaches a fixture.
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
public func resolveEdges(_ e: Edges<Length>, against parent: Double?, rootFontSize: Double) -> ResolvedEdges {
    func r(_ l: Length) -> Double {
        resolveLength(l, against: parent, rootFontSize: rootFontSize) ?? 0
    }
    return ResolvedEdges(top: r(e.top), right: r(e.right), bottom: r(e.bottom), left: r(e.left))
}

/// Resolve margin edges, which — unlike padding and border — may be `auto`.
///
/// **`.auto` resolves to 0, and that is not CSS.** An auto margin absorbs free
/// space *before* `justify-content` distributes any, so a CSS `margin-left: auto`
/// pushes its item to the end of the line; here it does nothing. This one line is
/// where that gets implemented. Until it does, the row in CLAUDE.md's inert-API
/// table stands.
///
/// Percentages resolve against `parent`, which callers must supply as the
/// containing block's **width** even for top and bottom — the same CSS rule
/// `resolveEdges` follows.
public func resolveMargin(_ e: Edges<Dimension>, against parent: Double?,
                          rootFontSize: Double) -> ResolvedEdges {
    func r(_ d: Dimension) -> Double {
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
