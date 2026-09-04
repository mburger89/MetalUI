import Testing
import MetalUICore
@testable import MetalUI

// M4 spec 3. Curve maths first, with no framework coupling — an `Animation`
// answers "where is this value at time t" and nothing else. Every assertion
// below feeds an explicit elapsed time; nothing sleeps and nothing reads a
// clock, which is what makes these deterministic on a loaded machine.

@Test func aLinearCurveIsExactlyProportional() {
    let a = Animation.linear(duration: 1)
    #expect(a.value(at: 0.00, from: 0, to: 100, initialVelocity: 0).value == 0)
    #expect(a.value(at: 0.25, from: 0, to: 100, initialVelocity: 0).value == 25)
    #expect(a.value(at: 0.50, from: 0, to: 100, initialVelocity: 0).value == 50)
    #expect(a.value(at: 1.00, from: 0, to: 100, initialVelocity: 0).value == 100)
}

/// Termination is EXACT for a duration curve, which is what lets
/// `hasActiveAnimations` have a precise answer and the display link pause on
/// the frame the last animation ends rather than one frame later.
@Test func aDurationCurveIsFinishedExactlyAtItsDuration() {
    let a = Animation.easeInOut(duration: 0.5)
    #expect(!a.value(at: 0.499, from: 0, to: 1, initialVelocity: 0).isFinished)
    #expect(a.value(at: 0.500, from: 0, to: 1, initialVelocity: 0).isFinished)
    #expect(a.value(at: 0.500, from: 0, to: 1, initialVelocity: 0).value == 1)
    // Past the end it stays pinned rather than extrapolating.
    #expect(a.value(at: 9.999, from: 0, to: 1, initialVelocity: 0).value == 1)
}

/// The eases must actually differ from linear and from each other, or the API
/// offers four names for one curve. Asserting the DIRECTION of the difference
/// at the midpoint is what discriminates: ease-in is behind linear, ease-out is
/// ahead of it.
@Test func theEasesDifferFromLinearInTheDirectionTheirNamesClaim() {
    let t = 0.5
    let linear = Animation.linear(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value
    let easeIn = Animation.easeIn(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value
    let easeOut = Animation.easeOut(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value

    #expect(linear == 0.5)
    #expect(easeIn < linear, "ease-in starts slow, so at the midpoint it is behind")
    #expect(easeOut > linear, "ease-out starts fast, so at the midpoint it is ahead")
}

/// Spec §7. A spring is NOT finished merely because it is at its target — one
/// at the target with velocity still in it is mid-overshoot. Both halves of the
/// settling test are needed and they fail under different mistakes.
@Test func aSpringIsNotFinishedWhileItStillHasVelocity() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)

    // Early: neither settled nor still.
    let early = s.value(at: 0.05, from: 0, to: 100, initialVelocity: 0)
    #expect(!early.isFinished)

    // Mid-flight: the spring's first swing carries it back THROUGH the
    // target on its way to overshoot, so displacement crosses zero while
    // velocity is still near its peak. This is the case the position-alone
    // mistake gets wrong and the two samples above do not exercise.
    //
    // SCANNED rather than a single hand-picked instant (fix round 1 review):
    // the exact crossing time sits in a sub-millisecond window of the
    // closed-form motion, which is a fragile thing to hardcode. Instead,
    // scan for any sample near the target (a loose bound, well outside the
    // actual — travel-scaled — position threshold) while the velocity is
    // still above 20, the LARGEST `velocityThreshold` can ever be for any
    // travel (it is `positionThreshold * 120`, and `positionThreshold`
    // itself is capped at the absolute floor of 1/6). That implication —
    // velocity this large means not finished — holds for every travel size
    // and does not depend on knowing the internal threshold at all, so it
    // survives the exact crossing time moving by anything less than the
    // whole scan.
    var sawNearTargetStillMoving = false
    for i in stride(from: 0, through: 1000, by: 1) {
        let t = Double(i) * 0.001
        let sample = s.value(at: t, from: 0, to: 100, initialVelocity: 0)
        if abs(sample.value - 100) < 0.5 && abs(sample.velocity) > 20 {
            sawNearTargetStillMoving = true
            #expect(!sample.isFinished, "near target but still moving fast at t=\(t): \(sample)")
        }
    }
    #expect(sawNearTargetStillMoving,
            "fixture never reaches a near-target, still-moving state — cannot exercise the velocity gate")

    // Late: both position and velocity within threshold.
    let late = s.value(at: 5.0, from: 0, to: 100, initialVelocity: 0)
    #expect(late.isFinished)
    #expect(abs(late.value - 100) < 0.5, "settled means at the target, got \(late.value)")
}

/// A bouncy spring must actually overshoot, or `bounce` is decorative and the
/// settling-on-velocity rule above has nothing to catch.
@Test func aBouncySpringOvershootsItsTarget() {
    let s = Animation.spring(duration: 0.4, bounce: 0.5)
    let samples = stride(from: 0.0, through: 1.0, by: 0.01).map {
        s.value(at: $0, from: 0, to: 100, initialVelocity: 0).value
    }
    #expect(samples.contains { $0 > 100.5 },
            "a bounce of 0.5 must overshoot 100; max was \(samples.max() ?? -1)")
}

/// Spec §7. Interruption re-targets from the current value and velocity rather
/// than restarting — a spring handed a non-zero initial velocity does not begin
/// from rest.
@Test func aSpringHandedInitialVelocityDoesNotStartFromRest() {
    let s = Animation.spring(duration: 0.5, bounce: 0.2)
    let atRest = s.value(at: 0.02, from: 0, to: 100, initialVelocity: 0).value
    let moving = s.value(at: 0.02, from: 0, to: 100, initialVelocity: 500).value
    #expect(moving > atRest,
            "inbound velocity must carry the value further; \(moving) vs \(atRest)")
}

/// `withAnimation` parks a transaction and clears it. The clearing half is what
/// stops every later frame animating.
@MainActor
@Test func withAnimationParksATransactionForTheDurationOfItsBodyOnly() {
    #expect(Animation.pendingTransaction == nil)
    var sawInside: Animation?
    withAnimation(.linear(duration: 1)) {
        sawInside = Animation.pendingTransaction
    }
    #expect(sawInside == .linear(duration: 1))
    #expect(Animation.pendingTransaction == nil, "the transaction must not outlive its body")
}

// MARK: - Fix round 1: three regions the original seven tests left uncovered

/// Fix round 1, Important 1. Nothing named `easeInOut` at a point other than
/// its symmetric midpoint (0.5, shared with `linear`), so a mutation that
/// replaces `easeInOut`'s curve with `.linear` passed all seven original
/// tests — `aDurationCurveIsFinishedExactlyAtItsDuration` only checks
/// `isFinished`/`value == 1`, which a straight line satisfies identically.
/// 0.25 is asymmetric and discriminates: `linear` gives exactly 0.25,
/// `easeInOut` (starting slow) gives less. Reference value independently
/// computed (fix round 1 review) at `0.1292`; reproduced here to high
/// precision by this file's own 32-iteration bisection.
@Test func easeInOutDiffersFromLinearAtAnAsymmetricPoint() {
    let value = Animation.easeInOut(duration: 1).value(at: 0.25, from: 0, to: 1, initialVelocity: 0).value
    #expect(abs(value - 0.12916) < 1e-4, "expected ease-in-out(0.25) ~= 0.1292, got \(value)")
}

/// Fix round 1, Important 1. `timingCurve` is in this type's own public
/// Interfaces and had zero coverage — a mutation replacing its curve with
/// `.linear`, ignoring all four control points, passed every original test.
/// Reference value independently computed (fix round 1 review) at `0.4406`.
@Test func timingCurveHonorsItsOwnControlPoints() {
    let a = Animation.timingCurve(0.17, 0.67, 0.83, 0.67, duration: 1)
    let value = a.value(at: 0.25, from: 0, to: 1, initialVelocity: 0).value
    #expect(abs(value - 0.44057) < 1e-4, "expected timingCurve(0.17,0.67,0.83,0.67)(0.25) ~= 0.4406, got \(value)")
}

/// Fix round 1, Important 1. A duration curve's `velocity` was never
/// asserted, so a mutation hardcoding it to 0 passed every original test —
/// silent because `velocity` is exactly what Task 3's interruption hand-off
/// will read. `linear(duration: 1)` over a 0→100 travel has constant
/// velocity 100/s at every unfinished instant.
@Test func aDurationCurveReportsNonzeroVelocityWhileRunning() {
    let velocity = Animation.linear(duration: 1).value(at: 0.5, from: 0, to: 100, initialVelocity: 0).velocity
    #expect(abs(velocity - 100) < 1e-6, "expected linear(1)'s velocity to be ~100, got \(velocity)")
}

/// Fix round 1, Important 3. Redone in normalized (0...1) units to prove the
/// settling threshold actually gates for a small-magnitude travel like
/// opacity or a colour channel, not only for a pixel-scale one — the exact
/// case the flat 1/6-point threshold could never resolve (measured: it
/// settled a 0→1 travel at 83.6% complete). Both halves still apply: never
/// finished while moving fast in normalized units, and finished once truly
/// settled.
@Test func theSettlingThresholdGatesForANormalizedZeroToOneTravelToo() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)

    var sawNearTargetStillMoving = false
    for i in stride(from: 0, through: 1000, by: 1) {
        let t = Double(i) * 0.001
        let sample = s.value(at: t, from: 0, to: 1, initialVelocity: 0)
        // 0.2 is well outside the true (travel-scaled, sub-thousandth)
        // threshold for a travel of 1, and this only needs a velocity that
        // is unambiguously "still moving" relative to the same travel.
        if abs(sample.value - 1) < 0.2 && abs(sample.velocity) > 0.2 {
            sawNearTargetStillMoving = true
            #expect(!sample.isFinished, "near target but still moving at t=\(t): \(sample)")
        }
    }
    #expect(sawNearTargetStillMoving,
            "fixture never reaches a near-target, still-moving state in normalized units")

    let late = s.value(at: 5.0, from: 0, to: 1, initialVelocity: 0)
    #expect(late.isFinished)
    #expect(abs(late.value - 1) < 0.01, "settled means at the target, got \(late.value)")
}

/// Fix round 1, Important 2. `x1`/`x2` outside `[0, 1]` makes `X(t) = u`
/// non-monotonic, so the bisection solve is ambiguous — measured (fix round
/// 1 review): `timingCurve(2.0, 0, -1.0, 1.0)` has THREE roots at `u = 0.5`,
/// and unclamped, the lowest one (~0.035) is what the solve happened to
/// return, not the "obviously intended" 0.5. Clamping x1/x2 to `[0, 1]`
/// (CSS's own rule for `cubic-bezier()`) makes the curve monotonic and the
/// root unambiguous; `y1`/`y2` are left untouched, since a `y` outside that
/// range is deliberate overshoot rather than a solver hazard.
@Test func timingCurveClampsOutOfRangeControlPointsToKeepTheSolveMonotonic() {
    let value = Animation.timingCurve(2.0, 0.0, -1.0, 1.0, duration: 1)
        .value(at: 0.5, from: 0, to: 1, initialVelocity: 0).value
    #expect(abs(value - 0.5) < 0.05,
            "expected the clamped curve's root near 0.5, got \(value) (the unclamped bug picks ~0.035)")
}

// MARK: - Fix round 1: bounce domain

/// Fix round 1, Important 4, the dangerous one. Task 5 wires `isFinished` to
/// `hasActiveAnimations`; either pathology below reaching production is a
/// window whose display link never pauses. `bounce` must be strictly inside
/// `(-1, 1)`, and that is a `precondition` — programmer error, not a value
/// to clamp and silently animate something else.
@Test func bounceOutsideItsOpenDomainTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = Animation.spring(duration: 0.5, bounce: 1.0)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.spring(duration: 0.5, bounce: -1.0)
    }
}
