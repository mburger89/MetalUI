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
                // this type constructs (x1, x2 both in [0, 1]), which is
                // exactly bisection's precondition and not Newton's — Newton
                // additionally needs a derivative and can step outside
                // [0, 1] where that derivative is small, which happens right
                // at t == 0 for easeOut (x1 == 0 makes dX/dt == 0 there).
                // Bisection never leaves its bracket and is guaranteed to
                // converge for any monotonic function, which matters more
                // here than Newton's faster convergence — this is evaluated
                // at most a few times per frame, never in a hot loop.
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

    public static func linear(duration: Double) -> Animation {
        Animation(.duration(.linear, seconds: duration))
    }

    /// CSS's `ease-in`: `cubic-bezier(0.42, 0.0, 1.0, 1.0)` — starts slow.
    public static func easeIn(duration: Double) -> Animation {
        Animation(.duration(.bezier(x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0), seconds: duration))
    }

    /// CSS's `ease-out`: `cubic-bezier(0.0, 0.0, 0.58, 1.0)` — starts fast.
    public static func easeOut(duration: Double) -> Animation {
        Animation(.duration(.bezier(x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0), seconds: duration))
    }

    /// CSS's `ease-in-out`: `cubic-bezier(0.42, 0.0, 0.58, 1.0)`.
    public static func easeInOut(duration: Double) -> Animation {
        Animation(.duration(.bezier(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0), seconds: duration))
    }

    /// The general form the four named eases above are fixed points of.
    public static func timingCurve(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, duration: Double
    ) -> Animation {
        Animation(.duration(.bezier(x1: x1, y1: y1, x2: x2, y2: y2), seconds: duration))
    }

    // MARK: - Springs

    /// SwiftUI's modern spelling: `duration` and `bounce` rather than raw
    /// mass/stiffness/damping, because the latter is a physics API and this
    /// one is a design API (spec §7).
    public static func spring(duration: Double, bounce: Double) -> Animation {
        Animation(.spring(duration: duration, bounce: bounce))
    }

    /// A gentle, mostly-settled spring — SwiftUI's own default shape
    /// (critically damped, half-second response).
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
        let epsilon = 1e-4
        let uBefore = max(u - epsilon, 0)
        let uAfter = min(u + epsilon, 1)
        let du = uAfter - uBefore
        let velocity: Double
        if du > 0 {
            let pBefore = curve.progress(at: uBefore)
            let pAfter = curve.progress(at: uAfter)
            velocity = (to - from) * (pAfter - pBefore) / du / seconds
        } else {
            velocity = 0
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
        // negative is overdamped. The simplest mapping that satisfies all
        // three, is continuous at 0, and stays inside `bounce`'s documented
        // domain of (-1, 1) is:
        //   bounce >= 0:  zeta = 1 - bounce       (1 at 0, -> 0 as bounce -> 1)
        //   bounce <  0:  zeta = 1 / (1 + bounce)  (1 at 0, -> +inf as bounce -> -1)
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
        // Position: half a device pixel is the standard "not worth resolving
        // further" perceptual floor. At a plausible high-density scale
        // factor of 3x (iPhone Pro-class; a 2x Mac display's pixel is
        // larger, so 3x is the stricter — smaller — bound and the more
        // conservative choice):
        //     positionThreshold = 0.5 device px / 3 px-per-point = 1/6 pt ≈ 0.1667
        let positionThreshold = 0.5 / 3.0

        // Velocity: a spring within `positionThreshold` but still moving
        // fast enough to cross back out of it within a single frame has not
        // settled either. This project's fastest target frame rate is
        // 120 Hz ProMotion (§2), so one frame is 1/120 s, and the velocity
        // that could cover exactly `positionThreshold` in one such frame is:
        //     velocityThreshold = positionThreshold / (1/120) = (1/6) * 120 = 20 pt/s
        let velocityThreshold = positionThreshold * 120.0

        let isFinished = abs(displacement) < positionThreshold && abs(velocity) < velocityThreshold

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
    @MainActor
    public static var pendingTransaction: Animation?
}

/// Parks `animation` as the ambient transaction for the duration of `body`,
/// then RESTORES whatever was parked before — not `nil` — so a
/// `withAnimation` nested inside another leaves the outer one in effect once
/// the inner body returns. (This task's own test only exercises the
/// non-nested case — parked, then cleared back to `nil` — so the restore
/// behaviour is written and stated here rather than proven by a test in this
/// task; nesting is spec §3's transaction model and a future task's frame
/// integration is what will exercise it.)
@MainActor
public func withAnimation(_ animation: Animation = .default, _ body: () -> Void) {
    let previous = Animation.pendingTransaction
    Animation.pendingTransaction = animation
    body()
    Animation.pendingTransaction = previous
}
