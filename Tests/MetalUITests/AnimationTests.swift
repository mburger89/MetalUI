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
    // mistake gets wrong and the two samples above do not exercise: at
    // t = 0.22 the displacement (measured, ~-0.06) is already inside
    // `positionThreshold` (1/6) but the velocity (measured, ~240) is twelve
    // times `velocityThreshold` (20) — declaring this finished on position
    // alone is exactly "at the target with velocity still in it".
    let midFlight = s.value(at: 0.22, from: 0, to: 100, initialVelocity: 0)
    #expect(abs(midFlight.value - 100) < 0.5, "expected near the target in passing, got \(midFlight.value)")
    #expect(!midFlight.isFinished, "velocity is still large here; must not be finished")

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
