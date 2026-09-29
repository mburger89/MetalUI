/// The value arithmetic of `Slider` and `Stepper`, pure (rulings `DD-W`,
/// `DD-X`; spec `2026-09-26-controls-and-selection-design.md` §4).
///
/// **Two different measured rules, kept apart on purpose.** A slider
/// adjustment **always writes**, changed or not (probe SA2: `value set 10.0` at
/// the maximum); a stepper step **writes only when the value moves** (STA1,
/// STA2). So `sliderAdjusted` returns a value and `stepped` an optional — a
/// shared helper would have to pick one of the two rules.
enum ValueStepping {
    typealias Direction = ControlKeys.Direction

    /// `value` clamped into `bounds`.
    static func clamp<V: Comparable>(_ value: V, _ bounds: ClosedRange<V>) -> V {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    // MARK: Slider (`DD-W`)

    /// Where `value` sits along `bounds`, in `0...1`, clamped first — an
    /// out-of-range value is **drawn** clamped (SA5, SA6) and never written back.
    /// Equal bounds answer 0.
    static func fraction(of value: Double, in bounds: ClosedRange<Double>) -> Double {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return (clamp(value, bounds) - bounds.lowerBound) / span
    }

    /// `value` placed on the grid `lower + k·step`, **rounding half up**, and
    /// never past the last grid point inside the bounds (SA3: 7 → 8 on a step of
    /// 2; SA4: 12 → 9 on 0…10 by 3).
    static func onGrid(_ value: Double, in bounds: ClosedRange<Double>, step: Double) -> Double {
        let lower = bounds.lowerBound
        // A small tolerance, so a span that is a whole number of steps in exact
        // arithmetic keeps its last point in floating point.
        let last = ((bounds.upperBound - lower) / step + 1e-9).rounded(.down)
        let k = min(max(((value - lower) / step + 0.5).rounded(.down), 0), last)
        return lower + k * step
    }

    /// One adjustment — an accessibility increment/decrement or an arrow key
    /// (`DD-W` item 3): from the value clamped into the bounds, one step when
    /// stepped (onto the grid), else 10% of the span (SA1, SA7), clamped. The
    /// caller **writes the result whatever it is** (SA2).
    static func sliderAdjusted(_ value: Double, in bounds: ClosedRange<Double>, step: Double?,
                               _ direction: Direction) -> Double {
        let sign: Double = direction == .forward ? 1 : -1
        let start = clamp(value, bounds)
        guard let step else {
            return clamp(start + sign * 0.1 * (bounds.upperBound - bounds.lowerBound), bounds)
        }
        return onGrid(start + sign * step, in: bounds, step: step)
    }

    /// The value under a pointer at window `x` over a track whose box starts at
    /// `minX` and is `width` wide, with a thumb `thumb` wide (`DD-W` item 5,
    /// MetalUI's own rule — CK0 failed): `lower + clamp01((x − minX − thumb/2) /
    /// (width − thumb))·span`, onto the grid when stepped. A track no wider than
    /// its thumb answers the lower bound.
    static func sliderValue(atX x: Double, minX: Double, width: Double, thumb: Double,
                            in bounds: ClosedRange<Double>, step: Double?) -> Double {
        let travel = width - thumb
        let f = travel > 0 ? min(max((x - minX - thumb / 2) / travel, 0), 1) : 0
        let value = bounds.lowerBound + f * (bounds.upperBound - bounds.lowerBound)
        guard let step else { return value }
        return onGrid(value, in: bounds, step: step)
    }

    // MARK: Stepper (`DD-X`)

    /// One step, or `nil` when nothing should be written (`DD-X` item 2):
    /// `clamp(clamp(value) ± step)` — clamped before (STA4: 5 on 0…3 steps from
    /// 3) and after (STA3) — and `nil` when that equals `value` (STA1, STA2). With
    /// no bounds, no clamp (STA5).
    static func stepped<V: Strideable>(_ value: V, in bounds: ClosedRange<V>?, step: V.Stride,
                                       _ direction: Direction) -> V? {
        let delta = direction == .forward ? step : -step
        let next: V
        if let bounds {
            next = clamp(clamp(value, bounds).advanced(by: delta), bounds)
        } else {
            next = value.advanced(by: delta)
        }
        return next == value ? nil : next
    }

    /// A value as an accessibility client reads it: a whole number without a
    /// trailing `.0` (SA0 reads `5`), anything else as Swift prints it.
    static func accessibilityText(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }
}
