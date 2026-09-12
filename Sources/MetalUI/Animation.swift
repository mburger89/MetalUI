import Foundation

/// A curve that answers "where is this value at time `t`" and nothing else —
/// pure maths, with no dependency on an element, a pass, or `Frame`. M4 spec 3
/// (`docs/superpowers/specs/2026-09-03-animation-design.md`) §7.
///
/// **Two models, because a duration and a spring answer different questions
/// and neither subsumes the other (spec §7).** A duration curve's endpoint is
/// declared and its termination is exact (`elapsed >= duration`); a spring has
/// no declared endpoint — it settles, and *when* it settles is itself computed
/// from the motion rather than from a clock.
///
/// **Deliberately not `@MainActor`.** Everything else in `MetalUI` is
/// actor-heavy, but a curve is a pure function of `(elapsed, from, to,
/// initialVelocity)` and should be evaluable from anywhere. Only
/// `Animation.pendingTransaction` and `withAnimation` below need the main
/// actor, because only they touch mutable, cross-call state.
public struct Animation: Sendable, Equatable {

    /// A unit cubic Bézier timing function, the same shape CSS and SwiftUI
    /// both spell: two interior control points, with the curve pinned at
    /// `(0, 0)` and `(1, 1)`.
    enum Curve: Equatable, Sendable {
        /// Kept as its own case rather than `.bezier(0, 0, 1, 1)`. That
        /// quadruple *would* describe a literal straight line — all four
        /// control points are colinear on `y = x`, so the curve's `X(t)` and
        /// `Y(t)` polynomials share identical coefficients and are therefore
        /// equal for every `t`, which does make the *shape* linear. But
        /// reaching that shape through `.bezier` still means solving
        /// `X(t) = x` by bisection for every sample, which converges to a
        /// tolerance rather than landing on the input bit-for-bit — and this
        /// type's own test asserts exact equality (`0`, `25`, `50`, `100`) at
        /// fractional elapsed times. A dedicated case sidesteps the solve
        /// entirely and returns the input value back out, exactly.
        case linear
        case bezier(x1: Double, y1: Double, x2: Double, y2: Double)

        /// Progress in `[0, 1]` at normalized elapsed time `u` in `[0, 1]`.
        func progress(at u: Double) -> Double {
            // Both control-point curves are pinned at (0,0) and (1,1), so the
            // endpoints are exact by construction and are special-cased here
            // rather than trusted to a bisection that only converges to a
            // tolerance. This is what lets a duration curve's value land on
            // `from`/`to` bit-for-bit at u == 0 / u == 1, which
            // `aDurationCurveIsFinishedExactlyAtItsDuration` depends on for a
            // non-linear curve (easeInOut).
            if u <= 0 { return 0 }
            if u >= 1 { return 1 }
            switch self {
            case .linear:
                return u
            case let .bezier(x1, y1, x2, y2):
                // Solve X(t) = u for the Bézier's own parameter t, then
                // evaluate Y(t) at that t. Bisection, not Newton: X(t) is
                // monotonic increasing in t for every timing-function shape
                // this type constructs — and that precondition is ENFORCED,
                // not merely true of the four built-in eases: `timingCurve`
                // (the only public entry point that can construct a
                // `.bezier` with caller-chosen control points) clamps x1 and
                // x2 to [0, 1] before this case is ever reached, which is
                // exactly CSS's own rule for `cubic-bezier()` and exactly
                // why — an x outside that range makes X(t) non-monotonic and
                // the solve below ambiguous (measured: `timingCurve(2.0, 0,
                // -1.0, 1.0)` has three roots at u = 0.5 without the clamp).
                // Newton's method additionally needs a derivative and can
                // step outside [0, 1] where that derivative is small, which
                // happens right at t == 0 for easeOut (x1 == 0 makes
                // dX/dt == 0 there). Bisection never leaves its bracket and
                // is guaranteed to converge for any monotonic function,
                // which matters more here than Newton's faster convergence
                // — this is evaluated at most a few times per frame, never
                // in a hot loop.
                var lo = 0.0
                var hi = 1.0
                for _ in 0..<32 {
                    let mid = (lo + hi) / 2
                    if Curve.bezierComponent(mid, x1, x2) < u {
                        lo = mid
                    } else {
                        hi = mid
                    }
                }
                return Curve.bezierComponent((lo + hi) / 2, y1, y2)
            }
        }

        /// One component (x or y) of a unit cubic Bézier pinned at 0 and 1:
        /// `B(t) = 3(1-t)² t · p1 + 3(1-t) t² · p2 + t³`.
        private static func bezierComponent(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
        }
    }

    enum Kind: Equatable, Sendable {
        case duration(Curve, seconds: Double)
        case spring(duration: Double, bounce: Double)
    }

    let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    // MARK: - Duration curves

    /// **`duration` must be finite — a `precondition`, on `timingCurve`'s own
    /// footing.** `durationValue`'s `seconds > 0` guard snaps a zero, negative
    /// or NaN duration to `to`, finished; `.infinity` passes that guard, and
    /// then `elapsed >= seconds` is never true and `elapsed / seconds` is 0.
    /// Measured on the unfixed source: `linear(duration: .infinity)` from 0 to
    /// 100 sat at 0 with `isFinished == false` at elapsed 0, 1, 30 and 1e6 — a
    /// field that never leaves `inFlight`, so a display link that never
    /// pauses. `0` and negatives are deliberately still admitted (they mean
    /// "no animation"); `.nan` traps because `easeIn` and its siblings, which
    /// route through `timingCurve`, already did.
    public static func linear(duration: Double) -> Animation {
        precondition(duration.isFinite,
                     "Animation.linear's duration must be finite; got duration=\(duration). " +
                     "0 or a negative duration snaps; .infinity would never finish.")
        return Animation(.duration(.linear, seconds: duration))
    }

    /// CSS's `ease-in`: `cubic-bezier(0.42, 0.0, 1.0, 1.0)` — starts slow.
    public static func easeIn(duration: Double) -> Animation {
        timingCurve(0.42, 0.0, 1.0, 1.0, duration: duration)
    }

    /// CSS's `ease-out`: `cubic-bezier(0.0, 0.0, 0.58, 1.0)` — starts fast.
    public static func easeOut(duration: Double) -> Animation {
        timingCurve(0.0, 0.0, 0.58, 1.0, duration: duration)
    }

    /// CSS's `ease-in-out`: `cubic-bezier(0.42, 0.0, 0.58, 1.0)`.
    public static func easeInOut(duration: Double) -> Animation {
        timingCurve(0.42, 0.0, 0.58, 1.0, duration: duration)
    }

    /// The general form the three named eases above are fixed points of.
    ///
    /// **`x1` and `x2` are clamped to `[0, 1]`; `y1` and `y2` are left
    /// free.** This is CSS's own rule for `cubic-bezier()`, and CSS's own
    /// reason: `Curve.progress(at:)` solves `X(t) = u` by bisection, which
    /// needs `X` monotonic increasing — true for any x1, x2 inside [0, 1]
    /// and not guaranteed outside it. Measured without the clamp:
    /// `timingCurve(2.0, 0, -1.0, 1.0)` makes `X(t) = u` have **three**
    /// roots at `u = 0.5`, and the bisection silently returns whichever one
    /// the bracket happens to converge to (0.0352, where 0.5 is also a
    /// root) — a caller-chosen `y` outside [0, 1], by contrast, is the
    /// legitimate "overshoot" some timing functions want deliberately, and
    /// nothing about the solve depends on `Y`'s range, so it is not
    /// touched. Every named ease above is written in terms of this
    /// function, so the clamp is universal rather than a built-ins-only
    /// property — this is called out at `Curve.progress(at:)` too, which is
    /// where a reader chasing the monotonicity claim will be looking.
    ///
    /// **All five arguments must be finite (fix round 2 review, ruling M,
    /// on `spring(duration:bounce:)`'s precondition's own footing).** Swift's
    /// `min`/`max` pass a `.nan` straight through — `min(max(.nan, 0), 1)` is
    /// `.nan`, not a clamped `0` or `1` — so the x-clamp above silently
    /// admits one: `timingCurve(.nan, 0, 0.5, 1, duration: 1)` sat at `from`
    /// for its whole duration and jumped at the end, with no diagnostic
    /// anywhere. Shipping that silently beside `spring`'s loud
    /// `precondition(bounce > -1 && bounce < 1)` in the same fix round would
    /// be the inconsistency — not the NaN itself, which is exactly the same
    /// shape of programmer error `bounce` traps on.
    public static func timingCurve(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, duration: Double
    ) -> Animation {
        precondition(x1.isFinite && y1.isFinite && x2.isFinite && y2.isFinite && duration.isFinite,
                     "Animation.timingCurve's control points and duration must all be finite; " +
                     "got x1=\(x1) y1=\(y1) x2=\(x2) y2=\(y2) duration=\(duration).")
        let clampedX1 = min(max(x1, 0), 1)
        let clampedX2 = min(max(x2, 0), 1)
        return Animation(.duration(.bezier(x1: clampedX1, y1: y1, x2: clampedX2, y2: y2), seconds: duration))
    }

    // MARK: - Springs

    /// SwiftUI's modern spelling: `duration` and `bounce` rather than raw
    /// mass/stiffness/damping, because the latter is a physics API and this
    /// one is a design API (spec §7).
    ///
    /// **`bounce` must be inside `(-1, 1)`, exclusive on both ends, and this
    /// is a `precondition`, not a clamp** — `LayoutTree.setStyle` already
    /// uses this shape for exactly this reason: it is programmer error, and
    /// a clamp would silently animate something other than what was asked
    /// for. Both boundary values fail open rather than loud, which is what
    /// makes this non-negotiable rather than a nicety. Measured (fix round
    /// 1 review, reproduced here): `bounce: 1.0` makes `zeta` exactly 0
    /// (undamped) — a `spring(duration: 0.5, bounce: 1.0)` from 0 to 100 is
    /// still not `isFinished` after 30 simulated seconds, because an
    /// undamped oscillator never decays. `bounce: -1.0` divides by
    /// `1 + bounce == 0`, so `zeta` is infinite and every downstream term is
    /// `NaN` — `value`, `velocity`, and `isFinished` (every `NaN` comparison
    /// is `false`, so this also never finishes, just silently instead of
    /// obviously). Task 5 wires `isFinished` to `hasActiveAnimations`, so
    /// either pathology reaching production is a window whose display link
    /// never pauses — M4's own exit criterion, sabotaged from call-site
    /// user code that looks entirely reasonable.
    ///
    /// **`duration` must be finite too, for the same reason reached through
    /// the other parameter.** `springValue`'s `duration > 0` guard snaps a
    /// zero, negative or NaN duration to `to`, finished; `.infinity` passes it
    /// and makes `omega` 0. Measured on the unfixed source, from 0 to 100 at
    /// elapsed 0, 1, 30 and 1e6: `bounce: 0` sat at 0 with `isFinished ==
    /// false`, and `bounce: 0.2` returned NaN with `isFinished == false`, at
    /// every sample. The precondition is `isFinite`, NOT `> 0` — `0` and
    /// negatives are the snap and stay admitted, and `1e9` is a legitimate
    /// (very slow) spring.
    public static func spring(duration: Double, bounce: Double) -> Animation {
        precondition(bounce > -1 && bounce < 1,
                     "Animation.spring(bounce:) must be strictly between -1 and 1; got \(bounce). " +
                     "0 is critically damped, 1 is undamped (never settles), and -1 divides by zero.")
        precondition(duration.isFinite,
                     "Animation.spring's duration must be finite; got duration=\(duration). " +
                     "0 or a negative duration snaps; .infinity never settles.")
        return Animation(.spring(duration: duration, bounce: bounce))
    }

    /// A gentle, mostly-settled spring. **Not** SwiftUI's `Animation.default`
    /// — probed (fix round 1 review): SwiftUI's own `.default` is a distinct
    /// `DefaultAnimation()` value that compares unequal to this one. What
    /// this value matches is SwiftUI's **`.smooth`**: both print
    /// `FluidSpringAnimation(response: 0.5, dampingFraction: 1.0,
    /// blendDuration: 0.0)`. Still a reasonable default shape (critically
    /// damped, half-second response) — the sentence above is corrected, not
    /// the value.
    public static let `default` = Animation.spring(duration: 0.5, bounce: 0)

    // MARK: - Evaluation

    /// Where this animation puts `from → to` at `elapsed` seconds, given the
    /// value and velocity it started from (`initialVelocity` matters only for
    /// a spring — a duration curve has no notion of inbound momentum and
    /// ignores it, spec §7's "interruption re-targets" applies to the spring
    /// model specifically).
    public func value(
        at elapsed: Double, from: Double, to: Double, initialVelocity: Double
    ) -> (value: Double, velocity: Double, isFinished: Bool) {
        switch kind {
        case let .duration(curve, seconds):
            return Animation.durationValue(curve: curve, seconds: seconds, elapsed: elapsed, from: from, to: to)
        case let .spring(duration, bounce):
            return Animation.springValue(
                duration: duration, bounce: bounce, elapsed: elapsed,
                from: from, to: to, initialVelocity: initialVelocity)
        }
    }

    private static func durationValue(
        curve: Curve, seconds: Double, elapsed: Double, from: Double, to: Double
    ) -> (value: Double, velocity: Double, isFinished: Bool) {
        guard seconds > 0 else {
            return (to, 0, true)
        }
        let isFinished = elapsed >= seconds
        let u = min(max(elapsed / seconds, 0), 1)
        let p = curve.progress(at: u)
        let value = from + (to - from) * p

        // Velocity by central finite difference in normalized time, then
        // converted to "per second of elapsed time" by the 1/seconds
        // chain-rule factor. Chosen over an analytic Bézier derivative
        // because that derivative is degenerate exactly at the endpoints
        // these curves are built with (easeOut's x1 == 0 makes dX/dt == 0 at
        // t == 0 — a removable but fiddly singularity), and this function is
        // a pure evaluation with no per-frame performance pressure, so the
        // extra pair of `progress(at:)` calls costs nothing that matters.
        // Past the end, the curve is pinned rather than extrapolating (the
        // clamp on `u` above), and velocity is pinned to 0 to match — a
        // finished duration curve has stopped, and reporting a nonzero
        // velocity forever after (this returned `100` for `linear(duration:
        // 1)` at t = 9 before this guard) is a real value a caller could
        // read and act on, not a cosmetic loose end.
        let velocity: Double
        if isFinished {
            velocity = 0
        } else {
            let epsilon = 1e-4
            let uBefore = max(u - epsilon, 0)
            let uAfter = min(u + epsilon, 1)
            let du = uAfter - uBefore
            if du > 0 {
                let pBefore = curve.progress(at: uBefore)
                let pAfter = curve.progress(at: uAfter)
                velocity = (to - from) * (pAfter - pBefore) / du / seconds
            } else {
                velocity = 0
            }
        }

        return (value, velocity, isFinished)
    }

    private static func springValue(
        duration: Double, bounce: Double, elapsed: Double, from: Double, to: Double, initialVelocity: Double
    ) -> (value: Double, velocity: Double, isFinished: Bool) {
        guard duration > 0 else {
            return (to, 0, true)
        }

        // --- Parameter conversion: SwiftUI's (duration, bounce) spelling to
        // the damped-harmonic-oscillator parameters (omega, zeta) the closed
        // form below is written in terms of. Derived, not transcribed. ---
        //
        // omega — the undamped natural angular frequency. This treats
        // `duration` the way SwiftUI's older, explicit
        // `.spring(response:dampingFraction:)` treats `response`: as the
        // natural (undamped) oscillation PERIOD, i.e. `response == 2π / ω`.
        // That correspondence is Apple's own public description of
        // `response` ("the stiffness of the spring, defined as an
        // approximate duration in seconds") — this is not an invented
        // constant, only that same relationship reapplied to the newer
        // duration/bounce spelling:
        let omega = 2 * Double.pi / duration

        // zeta — the damping ratio. SwiftUI's own documented semantics for
        // `bounce` are qualitative: 0 is critically damped, positive is
        // underdamped with growing overshoot as bounce approaches 1,
        // negative is overdamped:
        //   bounce >= 0:  zeta = 1 - bounce       (1 at 0, -> 0 as bounce -> 1)
        //   bounce <  0:  zeta = 1 / (1 + bounce)  (1 at 0, -> +inf as bounce -> -1)
        //
        // This is not merely the simplest mapping satisfying those three
        // qualitative cases — measured (fix round 1 review, independent
        // SwiftUI probe): together with the `omega` derivation above, this
        // conversion is a BIT-EXACT match to Apple's own `Spring` type
        // across all three damping regimes (under-, critically, and
        // over-damped) and the initial-velocity / interruption case.
        let zeta = bounce >= 0 ? (1 - bounce) : (1 / (1 + bounce))

        let x0 = from - to // displacement from the target (the equilibrium)
        let v0 = initialVelocity

        let (displacement, velocity) = Animation.dampedHarmonicMotion(
            omega: omega, zeta: zeta, t: elapsed, x0: x0, v0: v0)
        let value = to + displacement

        // --- Settling threshold: derived, not picked (spec §7 forbids a
        // tuned constant). A spring at its target with velocity still in it
        // is mid-overshoot, so BOTH position and velocity must be within
        // threshold. ---
        //
        // **`scale` is the motion that REMAINS if this spring runs to
        // completion, not merely `travel` (fix round 2 review, ruling L).**
        // `travel` (== |x0|) is the correct scale only when `v0 == 0` — the
        // half of the input space fix round 1 measured. `v0` also carries a
        // spring away from rest on its own, and `|v0| / omega` is the
        // displacement that velocity alone would produce in the UNDAMPED
        // case, so it is dimensionally a length and `travel`'s natural
        // companion term:
        //
        //     scale = max(|travel|, |v0| / omega)
        //
        // This subsumes both consequences fix round 1's flat-when-`travel ==
        // 0` fallback had and fix round 2 measured:
        //   - A spring interrupted exactly AT its target (`x0 == 0`, `v0 !=
        //     0` — Task 3's re-targeting mid-flight, one task from now) no
        //     longer falls back to the flat `absoluteCeiling` below. Its
        //     `scale` is `|v0| / omega`, so the same relative logic that
        //     fixed opacity/colour travel now also gates a re-targeted
        //     spring's settling on the velocity it actually carries. Before
        //     this fix: `v0 == 19.9` into a spring exactly at its target
        //     reported `isFinished` at `t == 0` and then moved another
        //     `0.79` — 79% of a `0...1` range "settled" before it moved,
        //     finding 4's original complaint, this time from `v0` rather
        //     than `travel`.
        //   - `scale` is CONTINUOUS in `(travel, v0)` together, where the
        //     flat fallback was not: `travel == 0` used to finish instantly
        //     and `travel == 1e-12` with the same `v0` took **4.35 s** — four
        //     orders of magnitude apart for the same momentum, and ~20x the
        //     frames a paused display link would otherwise hold awake once
        //     Task 5 wires `isFinished` to `hasActiveAnimations`.
        //
        // The only case still needing a guard is `travel == 0 AND v0 == 0` —
        // genuinely at rest, where `scale == 0` and the closed form below
        // gives `displacement == velocity == 0` identically. `<=` below
        // (not `<`) is what settles that case immediately rather than never:
        // a strict `<` against a `positionThreshold` of exactly `0` is
        // false even when `displacement` is also exactly `0`.
        let scale = max(abs(x0), abs(v0) / omega)

        // **`positionThreshold` is a CEILING on the threshold — a floor on
        // PRECISION, not a floor on the threshold's value — and this
        // paragraph is the correction of two comment clauses fix round 2
        // review found saying the opposite (record-mechanism 1: a
        // measurement recorded in a review is not a measurement applied to
        // the source until it is walked back to the mutated line, and that
        // applies to a review's own prose fix just as much).** The previous
        // round called the constant below an "absolute floor" and said the
        // `min` "caps how much precision is ever demanded for a large
        // [scale]" — right about what `min` does, wrong about which word
        // names it: `min` bounds `positionThreshold` from ABOVE, so a large
        // `scale` gets the SMALLER (more precise) of the two operands, not
        // the larger one — `0.001 * scale` alone would ask for `1.0`pt of
        // slop at `scale == 1000`, and `min` keeps it at the tighter
        // `0.1667`pt instead. "Floor" was the wrong word for a clause that
        // makes the number smaller, not larger; it is a ceiling on how much
        // imprecision `positionThreshold` may ever demand.
        //
        // `0.001` — one part in a thousand of `scale` — is the relative
        // criterion: displacement below a tenth of a percent of the total
        // motion is imperceptible for a continuously varying quantity,
        // independent of what unit that quantity happens to be in.
        // `absoluteCeiling` is the previous derivation, unchanged — half a
        // device pixel at a plausible high-density (3x) scale factor — and
        // is reached only once `scale` is large enough that a flat fraction
        // of it would ask for finer than half-a-device-pixel precision:
        //     absoluteCeiling = 0.5 device px / 3 px-per-point ≈ 0.1667
        //
        // The `3.0` is hardcoded rather than read from a real surface (spec
        // §7 says "the surface's scale factor") because this type has no
        // surface to ask — it is deliberately usable with no isolation and
        // no rendering context at all. It should become a parameter reading
        // the surface's actual scale factor once Task 5 gives this a caller
        // that has one.
        let absoluteCeiling = 0.5 / 3.0
        let positionThreshold = min(0.001 * scale, absoluteCeiling)

        // Velocity: a spring within `positionThreshold` but still moving
        // fast enough to cross back out of it within a single frame has not
        // settled either. This project's fastest target frame rate is
        // 120 Hz ProMotion (§2), so one frame is 1/120 s, and the velocity
        // that could cover exactly `positionThreshold` in one such frame is
        // `positionThreshold / (1/120)` — derived from `positionThreshold`
        // itself so it scales down with `scale` exactly the way
        // `positionThreshold` does.
        let velocityThreshold = positionThreshold * 120.0

        let isFinished = abs(displacement) <= positionThreshold && abs(velocity) <= velocityThreshold

        return (value, velocity, isFinished)
    }

    /// Closed-form position and velocity of a damped harmonic oscillator
    /// `x'' + 2ζωx' + ω²x = 0` at time `t`, given `x(0) = x0`, `x'(0) = v0`.
    /// Evaluated directly rather than integrated step by step — `value(at:)`
    /// is a pure function of elapsed time, not a per-frame simulation state.
    private static func dampedHarmonicMotion(
        omega: Double, zeta: Double, t: Double, x0: Double, v0: Double
    ) -> (displacement: Double, velocity: Double) {
        if abs(zeta - 1) < 1e-9 {
            // Critically damped (bounce == 0): x(t) = (x0 + (v0 + ωx0)t) e^{-ωt}.
            let b = v0 + omega * x0
            let e = exp(-omega * t)
            let d = (x0 + b * t) * e
            let dv = e * (b - omega * (x0 + b * t))
            return (d, dv)
        } else if zeta < 1 {
            // Underdamped (bounce > 0): decaying oscillation.
            let omegaD = omega * (1 - zeta * zeta).squareRoot()
            let decay = zeta * omega
            let e = exp(-decay * t)
            let c = cos(omegaD * t)
            let s = sin(omegaD * t)
            let b = (v0 + decay * x0) / omegaD
            let d = e * (x0 * c + b * s)
            let dv = e * ((-decay * x0 + b * omegaD) * c + (-decay * b - x0 * omegaD) * s)
            return (d, dv)
        } else {
            // Overdamped (bounce < 0): sum of two decaying exponentials.
            // x(t) = C1 e^{r1 t} + C2 e^{r2 t}, r1,2 = ω(-ζ ± √(ζ²-1)).
            let disc = (zeta * zeta - 1).squareRoot()
            let r1 = omega * (-zeta + disc)
            let r2 = omega * (-zeta - disc)
            let c1 = (v0 - r2 * x0) / (r1 - r2)
            let c2 = x0 - c1
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            let d = c1 * e1 + c2 * e2
            let dv = c1 * r1 * e1 + c2 * r2 * e2
            return (d, dv)
        }
    }
}

// MARK: - Transaction

extension Animation {
    /// The animation `withAnimation` has parked for the body it wraps, or
    /// `nil` outside of one.
    ///
    /// `@MainActor` alone, not the whole type: `Animation` itself is a pure
    /// value with no isolation requirement, but this is mutable, cross-call
    /// state, and the binding spec's discipline for exactly this shape of
    /// state is "write from input, never from a phase" (CLAUDE.md's
    /// `@State`/`@Observable` bullets) — main-actor isolation is what makes
    /// that a compile-time fact rather than a rule to remember.
    ///
    /// A plain static var in this task; a dedicated per-window store lands in
    /// Task 5 per the brief.
    ///
    /// **`internal`, not `public` (fix round 1 review).** Public, anything
    /// outside this module could write the ambient transaction directly,
    /// bypassing `withAnimation`'s save-and-restore entirely — defeating the
    /// one thing the transaction model exists to guarantee. `withAnimation`
    /// itself is the public surface; this is the slot it manages.
    /// `AnimationTests.swift` reads and writes it directly through
    /// `@testable import`, which is why the narrowing needs its own
    /// `swiftc -typecheck` guard against a PLAIN import to be demonstrated
    /// at all (`@testable` widens `internal`, taxonomy shape 16, ruling
    /// `TB-N`) — see `pendingTransactionIsNotPublic` in
    /// `ErasureCompileGuards.swift`.
    @MainActor
    static var pendingTransaction: Animation?

    /// The animation `withAnimation` has PARKED for the next frame build to
    /// consume, or `nil` once a build has taken it.
    ///
    /// **This is the hand-off, and without it production animates nothing**
    /// (ruling V). `pendingTransaction` above is restored in `withAnimation`'s
    /// `defer`, so it lives for the *lexical duration of the closure body*;
    /// `animated(_:_:for:pass:)` and `animatedColor(_:for:pass:)` run during
    /// the frame build, which happens later, from the display link, entirely
    /// outside that body. So `withAnimation { model.x = 1 }` marked the window
    /// dirty, the next frame built, and every animatable field found
    /// `pendingTransaction == nil` and snapped. All four sites Task 4 wired ran
    /// and none of them could ever start an animation.
    ///
    /// **A transaction is parked only if `body` actually asked for a redraw,
    /// and this rule is a FIX, not an optimisation** (fix round 1, review
    /// finding I-1, reproduced rather than reasoned). Without it, a
    /// `withAnimation(.linear(duration: 1)) { }` whose body dirties nothing —
    /// `withAnimation { if cond { model.x = 1 } }` with a false `cond` is
    /// ordinary code — parks a transaction that no frame ever consumes,
    /// because `takeParkedTransaction` runs only on a *drawn* frame and no
    /// frame is drawn. Measured: **400 seconds later**, an unrelated
    /// `model.width = 200` with no `withAnimation` anywhere read a mid-flight
    /// `150` instead of snapping to `200`. Spec §3 already accepts collateral
    /// animation ("a value that changed in the same frame for an unrelated
    /// reason also animates") — but that is *the same frame*, and this was an
    /// arbitrarily distant one about something else.
    ///
    /// So `withAnimation` parks eagerly and **rolls the slot back only when
    /// nothing is going to build a frame** — neither `Window.redrawRequests`
    /// moved across `body`, nor was `Window.aFrameBuildIsPending` already true
    /// when it started.
    ///
    /// **Both halves are needed, and the second was added because the first
    /// alone was measured to be WRONG** (fix round 2, re-review finding N-1).
    /// The counter answers "did *this* body dirty a *clean* window", which is
    /// narrower than "will there be a next build", and the gap is ordinary
    /// code rather than a corner:
    ///
    /// - **`@State` is genuinely covered by the counter.** `StateTable.write`
    ///   fires `onWrite` unconditionally on **every** write and `Window` wires
    ///   that straight to `setNeedsRedraw()`.
    /// - **`@Observable` is not, and the reason is not asynchrony.** The
    ///   `markDirtyFromObservation` main-thread branch *is* synchronous — that
    ///   much was true when this comment claimed it settled the path, and it
    ///   does not settle it. `withObservationTracking`'s `onChange` is
    ///   **one-shot**, and the session is re-armed only by the next *drawn*
    ///   frame. So the second and every later `@Observable` mutation between
    ///   two frames fires no `onChange` at all and moves no counter. Measured:
    ///   `model.width = 120` then
    ///   `withAnimation(.linear(duration: 1)) { model.width = 200 }` parked
    ///   `nil` and **snapped to 200** where the animation reads **150** — a
    ///   legitimate animation, silently discarded, with no diagnostic. The
    ///   window was already dirty from the first write and a frame was
    ///   certainly coming.
    ///
    /// `Window.aFrameBuildIsPending` asks whether any live window is dirty —
    /// `drawFrameIfNeeded`'s guard less its `hasActiveAnimations` half, which
    /// that property's own doc argues can never be needed here and measures
    /// doing harm when included. It also fixes a
    /// second, benign instance the same round measured: a `withAnimation`
    /// before a window's first frame has ever been drawn used to roll back
    /// even though `needsRedraw` is `true` from `init`.
    ///
    /// **A counter-silent body never DISPLACES a park that is already there,
    /// and that clause is the whole of the difference between this rule and
    /// the re-review's suggestion as written.** Taking the suggestion bare —
    /// park whenever a build is pending — made
    /// `withAnimation(.linear(duration: 1)) { model.width = 200 }` followed by
    /// an empty `withAnimation(.linear(duration: 4)) { }` hand the *empty* one
    /// the build, because the first call's own dirty made a build pending for
    /// the second. Measured, by running it: `112.5` where the first
    /// transaction reads `150`, reddening
    /// `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`'s
    /// third arm. So the full rule is: **a body that asked for no redraw keeps
    /// the slot only when the slot was FREE and a build was already coming** —
    /// which is exactly the N-1 case, an observable write nobody observed. If
    /// the slot was already claimed, the claimant's body demonstrably dirtied
    /// a clean window, so it has the stronger claim and gets it back.
    ///
    /// **The residual, stated rather than discovered.** Two `withAnimation`
    /// calls in one frame interval where the SECOND one's writes are
    /// unobserved (`withAnimation(a) { model.x = 1 }; withAnimation(b) { model.y = 2 }`)
    /// give the build `a`, not `b`. Only one ambient transaction reaches one
    /// build in any case, so this is which-curve-wins rather than a dropped
    /// animation — `y` still animates — and "the one whose body demonstrably
    /// dirtied" is the defensible half of the choice. Unpinned by any test.
    ///
    /// **This also stops the module-global leaking across the suite.** The 13+
    /// direct-helper `withAnimation` sites from Tasks 3, 4 and 4b build no
    /// frame and dirty no window, so they now park nothing at all rather than
    /// each leaving the global set for whatever runs next. They are unaffected
    /// otherwise: every one of them reads the LEXICAL slot below.
    ///
    /// **The reviewer's alternative — bound the park to the current run-loop
    /// turn with a `Task { @MainActor }` clear — was considered and not
    /// taken**, for two reasons stated rather than assumed. It races the thing
    /// it must not: the clear is enqueued on the main actor *before* the
    /// display link's next callback is, so on a FIFO main queue it runs first
    /// and the hand-off dies exactly the way ruling V describes. And it is
    /// untestable in this suite by construction — `simulateTick(timestamp:)`
    /// is synchronous and the test never returns to a run loop between the
    /// park and the tick, so a turn-bounded rule would be exercised only in
    /// production, where nothing can see it.
    ///
    /// **The two slots cannot disagree about WHICH animation, only about
    /// WHEN.** `withAnimation` writes both, in the same statement, with the
    /// same value. `pendingTransaction` is the *lexical* ambient (alive only
    /// inside the body, restored on the way out, so a nested `withAnimation`
    /// leaves the outer one in effect); this is the *parked* one (alive from
    /// the call until the next build takes it, and no longer). Production only
    /// ever reaches the parked one, because a production `withAnimation` body
    /// never contains a frame build; the direct-helper tests from Tasks 3, 4
    /// and 4b only ever reach the lexical one, because they never build a
    /// frame. `animated`/`animatedColor` prefer the frame-carried value and
    /// fall back to the lexical one, which is what keeps both configurations
    /// working off one implementation.
    ///
    /// **Spec §3 says this is stored "on the `Window`", and it is not — a
    /// deliberate, reportable narrowing.** `withAnimation` is a free function
    /// with no window in scope and no way to name one; there is no ambient
    /// "current window" in this framework and inventing one to satisfy the
    /// letter of §3 would be a larger global than this is. The cost is a
    /// multi-window one, stated rather than discovered: with two windows live,
    /// whichever builds first consumes the transaction and the other snaps.
    /// The fix, when a second window ever exists, is a per-window parking slot
    /// plus a way for `withAnimation` to name its window — a signature change,
    /// not a re-design of anything here.
    ///
    /// **`internal`, on `pendingTransaction`'s own footing** — public, anything
    /// outside the module could park a transaction that no `withAnimation`
    /// call authorised, which is the one thing the transaction model exists to
    /// prevent.
    @MainActor
    static var parkedTransaction: Animation?

    /// Takes the parked transaction and clears it, so it is consumed by
    /// **exactly one** build (spec §3: "`withAnimation` is NOT re-entrant
    /// across frames. The pending animation is consumed by the next build and
    /// cleared."). `Window.drawFrameIfNeeded` is the only production caller,
    /// and it calls this once per drawn frame whether or not anything is
    /// parked. Pinned by `aParkedTransactionIsConsumedByExactlyOneBuild`.
    @MainActor
    static func takeParkedTransaction() -> Animation? {
        defer { parkedTransaction = nil }
        return parkedTransaction
    }
}

/// Runs `body` with `animation` as the ambient transaction, and **parks it for
/// the next frame build** — spec §3's "stores a pending `Animation`, runs
/// `body`, and clears it", where the clearing is done by the build that
/// consumes it rather than by this function's own `defer`.
///
/// Two writes, two lifetimes, one value; see `Animation.parkedTransaction` for
/// why both exist and what makes them agree.
///
/// - `Animation.pendingTransaction` is set for the *lexical* duration of
///   `body` and then RESTORED to whatever was parked before — not `nil` — so a
///   `withAnimation` nested inside another leaves the outer one in effect once
///   the inner body returns.
/// - `Animation.parkedTransaction` survives this call **if and only if a frame
///   build is coming** — `body` asked for a redraw, or one was already pending
///   when the call started — i.e. only if there is going to be a next frame
///   build for it to reach — and is then taken by the next
///   `Window.drawFrameIfNeeded`. That is the whole hand-off: the mutation
///   inside `body` marks the window dirty through `@State`'s `onWrite` or
///   `@Observable`'s tracking, this function returns, and the frame that
///   results is the one that reads the animation. A body that dirties nothing
///   leaves the slot exactly as it found it; see `Animation.parkedTransaction`
///   for the 400-second failure that rule closes.
///
/// **Nesting is unchanged by the rollback: the INNER animation still wins.**
/// The park is eager and the rollback restores whatever was parked *before*
/// this call, so an inner `withAnimation` whose body dirtied something keeps
/// its slot when the outer one's `defer` runs (the outer's own count moved
/// too, so the outer does not roll back). One transaction reaches one build,
/// so `withAnimation(fast) { withAnimation(slow) { a = 1 }; b = 2 }` animates
/// both `a` and `b` with `slow` — neither SwiftUI's answer nor obviously
/// wrong, and a consequence of one-ambient-transaction-per-build rather than
/// of this rule. Nothing in the suite exercises nesting; stated rather than
/// discovered.
@MainActor
public func withAnimation(_ animation: Animation = .default, _ body: () -> Void) {
    let previous = Animation.pendingTransaction
    let previouslyParked = Animation.parkedTransaction
    let redrawsBefore = Window.redrawRequests
    // Sampled BEFORE the body, and that is the meaningful reading: it asks
    // whether a build was ALREADY coming when this call started. Sampled
    // after, it would also be true of any body that dirtied something, which
    // the counter already covers.
    let buildAlreadyPending = Window.aFrameBuildIsPending
    Animation.pendingTransaction = animation
    Animation.parkedTransaction = animation
    // `defer`, not a trailing assignment: nothing today can skip past `body()`
    // without restoring (it is non-throwing), but this makes the restore
    // survive a future signature change (e.g. `rethrows`) rather than
    // silently stop happening on the path that would need it most.
    //
    // The LEXICAL slot is restored unconditionally. The PARKED one is rolled
    // back when nothing is going to build a frame, and also when the slot was
    // already claimed by a call whose body did dirty something — restoring it
    // unconditionally is precisely the pre-task behaviour that made production
    // animate nothing, and mutation 5 in this task's report is that line put
    // back. Rolled back to `previouslyParked` rather than to `nil`, so a
    // no-op `withAnimation` cannot clobber a transaction an earlier one
    // legitimately parked.
    defer {
        Animation.pendingTransaction = previous
        if Window.redrawRequests == redrawsBefore
            && (!buildAlreadyPending || previouslyParked != nil) {
            Animation.parkedTransaction = previouslyParked
        }
    }
    body()
}
