import MetalUICore

// Dash patterns of underline and strikethrough (rulings TM-B…TM-E; probe
// `docs/probes/text-line-patterns.swift`). A pattern is a cycle of on/off
// lengths in units of the line's thickness; the emitter below splits one
// decoration rectangle into segment rectangles on the CPU, so no shader and
// no renderer changes (`TE-AD` satisfied by construction) and the geometry is
// the same on every platform.

extension Text.LineStyle.Pattern {
    /// The cycle's alternating on/off lengths, in thicknesses, starting with
    /// "on" (probe `P`: dot 3/3, dash 10/5, dashDot 10/3/3/3, dashDotDot
    /// 10/3/3/3/3/3). Empty for ``solid``.
    var cycle: [Double] {
        switch kind {
        case .solid: []
        case .dot: [3, 3]
        case .dash: [10, 5]
        case .dashDot: [10, 3, 3, 3]
        case .dashDotDot: [10, 3, 3, 3, 3, 3]
        }
    }
}

/// The unit a pattern's lengths are multiples of: the face's thickness
/// **rounded up to a whole point, at least one** — SwiftUI draws the band at
/// that thickness (probe `T`: 9–17 pt text 1, 20–28 pt 2, 36–48 pt 3, 72 pt 5,
/// every size `ceil` of CoreText's underline thickness), and the patterns are
/// multiples of the drawn one. MetalUI's band keeps the face's own thickness
/// (divergence 152); only the pattern unit rounds (`TM-C`).
func linePatternUnit(thickness: Double) -> Double {
    Swift.max(1, (thickness - 1e-4).rounded(.up))
}

/// The "on" intervals of `pattern` over `[low, high]`, with the cycle starting
/// "on" at `origin` — the line's own start, not the decoration's (probe
/// `PS`: an underline beginning mid-line is cut from the line's cycle, and
/// the cycle is carried across runs, `TM-D`). `solid` is the whole interval.
func linePatternSegments(_ pattern: Text.LineStyle.Pattern, unit: Double, origin: Double, from low: Double,
                         to high: Double) -> [(min: Double, max: Double)] {
    guard high > low else { return [] }
    let cycle = pattern.cycle
    let period = cycle.reduce(0, +) * unit
    guard !cycle.isEmpty, period > 0, period.isFinite else { return [(low, high)] }
    var result: [(min: Double, max: Double)] = []
    var start = origin + ((low - origin) / period).rounded(.down) * period
    while start < high {
        var cursor = start
        for (index, length) in cycle.enumerated() {
            let end = cursor + length * unit
            if index % 2 == 0 {
                let a = Swift.max(cursor, low), b = Swift.min(end, high)
                if b > a { result.append((a, b)) }
            }
            cursor = end
            if cursor >= high { break }
        }
        start += period
    }
    return result
}
