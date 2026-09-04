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

    public static func linear(duration: Double) -> Animation {
        Animation(.duration(.linear, seconds: duration))
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
    public static func timingCurve(
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, duration: Double
    ) -> Animation {
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
    public static func spring(duration: Double, bounce: Double) -> Animation {
        precondition(bounce > -1 && bounce < 1,
                     "Animation.spring(bounce:) must be strictly between -1 and 1; got \(bounce). " +
                     "0 is critically damped, 1 is undamped (never settles), and -1 divides by zero.")
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
        // **Relative to the travel, with an absolute ceiling — not a flat
        // absolute number.** `value(at:)` is unit-agnostic (spec §7 names no
        // unit at all), and a single absolute point-valued threshold breaks
        // the moment `from`/`to` are not points: measured (fix round 1
        // review) on `spring(0.5, 0.4)` with a flat 1/6-point threshold, a
        // 100pt travel settled at 99.8% complete, a 2pt travel at 91.8%, and
        // a 0→1 opacity travel — the exact shape `Decoration.background`'s
        // `Hsla` animation uses (spec §4) — at 83.6%: the flat threshold is
        // more than a SIXTH of the whole opacity range, so it "settles" a
        // sixth of the way from done.
        //
        // A fraction of the travel fixes that (a 0→1 property and a 0→100pt
        // one settle at the same fraction of completion), but a pure
        // fraction breaks the opposite way for a travel too small to
        // resolve at all — so the two are combined with `min`, which makes
        // the fraction tighten the requirement for a small travel while the
        // absolute value caps how much precision is ever demanded for a
        // large one (a spring is never required to resolve BELOW
        // sub-perceptual precision, which is what "floor" means here — a
        // floor under how much imprecision is acceptable, not a floor on
        // the threshold's value):
        //
        //     positionThreshold = min(0.001 * |travel|, absoluteFloor)
        //
        // `0.001` — one part in a thousand of the travel — is the relative
        // criterion: displacement below a tenth of a percent of the total
        // motion is imperceptible for a continuously varying quantity,
        // independent of what unit that quantity happens to be in.
        // `absoluteFloor` is the previous derivation, unchanged, and now
        // reached only once the travel is large enough that a flat fraction
        // of it would ask for finer than half-a-device-pixel precision —
        // exactly the "floor for pixel-valued travel" a large point-valued
        // travel needs and an opacity or colour travel never reaches:
        //     absoluteFloor = 0.5 device px / 3 px-per-point (a plausible
        //                     high-density scale factor) = 1/6 pt ≈ 0.1667
        //
        // The `3.0` is hardcoded rather than read from a real surface (spec
        // §7 says "the surface's scale factor") because this type has no
        // surface to ask — it is deliberately usable with no isolation and
        // no rendering context at all. It should become a parameter reading
        // the surface's actual scale factor once Task 5 gives this a caller
        // that has one.
        //
        // A travel of exactly 0 (already at the target, resting) falls back
        // to `absoluteFloor` alone (`0.001 * 0 == 0` would otherwise demand
        // an unsatisfiable zero threshold) — which is also the physically
        // right answer: with `x0 == 0` and `v0 == 0` the closed form below
        // gives `displacement == velocity == 0` identically, comfortably
        // inside any positive threshold, so this still reports finished
        // immediately rather than never.
        let travel = abs(x0)
        let absoluteFloor = 0.5 / 3.0
        let positionThreshold = travel > 0 ? min(0.001 * travel, absoluteFloor) : absoluteFloor

        // Velocity: a spring within `positionThreshold` but still moving
        // fast enough to cross back out of it within a single frame has not
        // settled either. This project's fastest target frame rate is
        // 120 Hz ProMotion (§2), so one frame is 1/120 s, and the velocity
        // that could cover exactly `positionThreshold` in one such frame is
        // `positionThreshold / (1/120)` — derived from `positionThreshold`
        // itself so it scales down with a small travel exactly the way
        // `positionThreshold` does. This is the other half of what the flat
        // constant broke: measured, that spring's peak velocity on the 0→1
        // opacity travel above is ~6.2/s against a flat 20/s threshold, so
        // the velocity gate could never bind for a normalized property at
        // all — scaling it with the travel restores that.
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
    // `defer`, not a trailing assignment: nothing today can skip past `body()`
    // without restoring (it is non-throwing), but this makes the restore
    // survive a future signature change (e.g. `rethrows`) rather than
    // silently stop happening on the path that would need it most.
    defer { Animation.pendingTransaction = previous }
    body()
}
