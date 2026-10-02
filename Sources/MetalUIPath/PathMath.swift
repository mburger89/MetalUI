/// This target's own trigonometry (ruling GX-B). The Swift standard library
/// has no `sin`, and every platform's libm rounds differently, so a path's
/// coverage could otherwise differ by a byte between macOS, Linux and
/// Windows. Basic operations only — `+ − × ÷`, `rounded()` — and no fused
/// multiply-add (`GX-R` item 2), so the same bits come out everywhere
/// (pinned exactly by `sinCosMatchesTheReferenceTable`).
package enum PathMath {
    // π/2 in two parts (fdlibm's pio2_1/pio2_1t): the first has 33 bits, so
    // `k × pio2Hi` is exact for |k| < 2^20 and the reduction loses nothing
    // for every angle a UI produces (|x| up to about 1.6 × 10⁶).
    private static let pio2Hi = 1.57079632673412561417e+00
    private static let pio2Lo = 6.07710050650619224932e-11
    private static let twoOverPi = 6.36619772367581382433e-01

    // fdlibm's __kernel_sin (degree 13) and __kernel_cos (degree 12) minimax
    // coefficients, |r| ≤ π/4.
    private static let s1 = -1.66666666666666324348e-01
    private static let s2 = 8.33333333332248946124e-03
    private static let s3 = -1.98412698298579493134e-04
    private static let s4 = 2.75573137070700676789e-06
    private static let s5 = -2.50507602534068634195e-08
    private static let s6 = 1.58969099521155010221e-10
    private static let c1 = 4.16666666666666019037e-02
    private static let c2 = -1.38888888888741095749e-03
    private static let c3 = 2.48015872894767294178e-05
    private static let c4 = -2.75573143513906633035e-07
    private static let c5 = 2.08757232129817482790e-09
    private static let c6 = -1.13596475577881948265e-11

    /// `(sin x, cos x)`. Exactly odd in `sin` and even in `cos` by
    /// construction: the work is done on `|x|` and the sine's sign restored
    /// (which also keeps `sin(−0) = −0`). Non-finite input gives NaN.
    package static func sinCos(_ value: Double) -> (sin: Double, cos: Double) {
        guard value.isFinite else { return (.nan, .nan) }
        let negative = value.sign == .minus
        let (s, c) = positiveSinCos(negative ? -value : value)
        return (negative ? -s : s, c)
    }

    private static func positiveSinCos(_ x: Double) -> (sin: Double, cos: Double) {
        let k = (x * twoOverPi).rounded(.toNearestOrEven)
        let r = (x - k * pio2Hi) - k * pio2Lo
        let z = r * r
        let sinR = r + r * z * (s1 + z * (s2 + z * (s3 + z * (s4 + z * (s5 + z * s6)))))
        let cosR = 1 - z * 0.5 + z * z * (c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * c6)))))
        let quadrant = Int((k.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4))
        switch quadrant {
        case 0: return (sinR, cosR)
        case 1: return (cosR, -sinR)
        case 2: return (-sinR, -cosR)
        default: return (-cosR, sinR)
        }
    }
}
