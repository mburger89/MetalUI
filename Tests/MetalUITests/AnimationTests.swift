import Testing
import Observation
import MetalUICore
import MetalUILayout
import MetalUIRender
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
@Test func withAnimationParksATransactionForTheDurationOfItsBodyOnly() throws {
    #expect(Animation.pendingTransaction == nil)
    let parkedBefore = Animation.parkedTransaction
    // The parked-slot arm below is about the no-build-coming case, so the
    // fixture must actually be in it. `try #require` rather than `#expect`
    // because the arm asserts nothing meaningful otherwise, and because a
    // failure here is cross-test pollution (a dirty window left alive by an
    // earlier test) rather than a defect in `withAnimation` — worth saying
    // loudly rather than reading as a wrong value.
    try #require(!Window.aFrameBuildIsPending,
                 "set up: no live window is about to build a frame")
    var sawInside: Animation?
    withAnimation(.linear(duration: 1)) {
        sawInside = Animation.pendingTransaction
    }
    #expect(sawInside == .linear(duration: 1))
    #expect(Animation.pendingTransaction == nil, "the transaction must not outlive its body")

    // Task 5 fix round 1: the PARKED slot is left exactly as it was found,
    // because this body asked for no redraw and so no frame will ever be
    // built for it to reach. Compared against a locally saved value rather
    // than against `nil`, so this says something about THIS call rather than
    // about whatever ran before it in the suite.
    #expect(Animation.parkedTransaction == parkedBefore, """
            a body that dirties nothing parks nothing — otherwise every one of this \
            file's direct-helper `withAnimation` sites leaves the module-global set \
            for whatever runs next
            """)
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

// MARK: - Fix round 2: the settling scale is the motion that remains, not `travel`

/// Fix round 2, ruling L, half of finding 4 the previous round did not
/// cover. `travel` alone is only the right settling scale when `v0 == 0`; a
/// spring interrupted EXACTLY at its target still carries velocity, and the
/// travel-only threshold declared it finished on arrival regardless — before
/// this fix, `v0 = 19.9` at a spring's own target reported `isFinished` at
/// `t == 0` and then moved another 0.79 of a `0...1` range. This is
/// hypothetical only until Task 3, which re-targets mid-flight and produces
/// exactly this shape (from == to's current value, non-zero inbound
/// velocity) as ordinary behaviour.
@Test func aSpringInterruptedExactlyAtItsTargetIsNotFinishedUntilItSettles() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)
    let atStart = s.value(at: 0.0, from: 50, to: 50, initialVelocity: 19.9)
    #expect(atStart.value == 50, "displacement is 0 at t=0 regardless of velocity")
    #expect(!atStart.isFinished, "still carrying velocity 19.9; must not report finished on arrival")

    // Still not finished a short way in (the velocity has not had time to
    // decay away yet).
    let early = s.value(at: 0.05, from: 50, to: 50, initialVelocity: 19.9)
    #expect(!early.isFinished, "\(early)")

    // Genuinely settles once the velocity has decayed — measured settle
    // time on this exact fixture is ~0.62s; 1.5s is comfortably past it
    // without hardcoding the crossing.
    let late = s.value(at: 1.5, from: 50, to: 50, initialVelocity: 19.9)
    #expect(late.isFinished, "\(late)")
}

/// Fix round 2, ruling L, the other half. Before this fix, `travel == 0` and
/// `travel == 1e-12` with identical momentum (`v0 == 6`) disagreed by four
/// orders of magnitude in settling time (instant vs. 4.35s) — discontinuous
/// in a physical quantity that has no reason to jump. After the fix, a
/// tiny-travel-with-momentum case settles in a time comparable to a
/// unit-travel one, not an order of magnitude later: measured, 0.809s
/// (0→1, v0=0) against 0.6209s (0→1e-12, v0=6) on the same spring — same
/// order of magnitude, where the pre-fix number was ~5x *larger* than the
/// unit case rather than comparable to it.
@Test func aSmallTravelWithMomentumSettlesInComparableTimeToAUnitTravelOne() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)
    func settleTime(from: Double, to: Double, v0: Double) -> Double? {
        for i in 0...100000 {
            let t = Double(i) * 0.0001
            if s.value(at: t, from: from, to: to, initialVelocity: v0).isFinished { return t }
        }
        return nil
    }
    let unitTravel = try! #require(settleTime(from: 0, to: 1, v0: 0))
    let tinyTravelWithMomentum = try! #require(settleTime(from: 0, to: 1e-12, v0: 6))

    // Comfortably below the pre-fix 4.35s and within a small factor of the
    // unit-travel baseline — "comparable", not "identical": the two cases
    // are physically different motions and are not expected to match
    // exactly, only to share an order of magnitude.
    #expect(tinyTravelWithMomentum < 2.0,
            "expected well under the pre-fix 4.35s, got \(tinyTravelWithMomentum)")
    #expect(tinyTravelWithMomentum < unitTravel * 4,
            "expected comparable to the unit-travel settle time \(unitTravel), got \(tinyTravelWithMomentum)")
}

// MARK: - Fix round 3, ruling N: the at-rest case, unprotected until pinned

/// Fix round 3, ruling N.1. The round 2 swap from `<` to `<=` in both
/// `isFinished` comparisons was made unprompted and reasoned about in a
/// comment, but nothing pinned it — and it is load-bearing, not cosmetic.
/// `travel == 0 && v0 == 0` makes `scale` exactly `0`, so `positionThreshold`
/// is exactly `0` too; under `<`, `abs(displacement) < 0` is never true even
/// when `displacement` is also exactly `0` (which it is here, by
/// construction of the closed form) — so a spring created already at its
/// target would report `!isFinished` at `t == 0` and FOREVER, since nothing
/// about a resting spring's state ever changes. Ruling L deleted the
/// `travel == 0` special case that used to route this through a nonzero
/// constant, which is what makes this comparison operator load-bearing
/// rather than a style choice.
@Test func aSpringAlreadyAtRestIsFinishedImmediately() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)
    let r = s.value(at: 0.0, from: 50, to: 50, initialVelocity: 0)
    #expect(r.value == 50)
    #expect(r.velocity == 0)
    #expect(r.isFinished,
            "a spring created already at its target must be finished at t=0, not never")
}

// MARK: - Fix round 2/3: timingCurve finiteness

/// Fix round 2, ruling M, sharpened by fix round 3. `min(max(.nan, 0), 1)`
/// is `.nan` in Swift, so the x-clamp added in round 2 silently passes a
/// NaN control point through — on `Curve.progress`'s own
/// `if u <= 0`/`if u >= 1` guards, every comparison against a NaN is false,
/// so the curve sits at `from` for its whole declared duration and jumps at
/// the very end. `spring`'s `bounce` domain got a loud `precondition` in the
/// same round; this is the same shape of programmer error.
///
/// **Exercises all FIVE arguments individually (fix round 3 review), not
/// two.** The round 2 version checked only `x1` NaN and `duration`
/// infinite — a weakened precondition checking just `x1.isFinite &&
/// duration.isFinite` still passed it, because that pair happened to be
/// exactly the two it exercised. Each case below leaves the other four
/// arguments at a valid, finite value, so the test discriminates the
/// precondition's ARGUMENTS rather than merely its presence.
@Test func timingCurveTrapsOnANonFiniteArgument() async {
    await #expect(processExitsWith: .failure) {
        _ = Animation.timingCurve(.nan, 0.5, 0.75, 0.5, duration: 1)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.timingCurve(0.25, .nan, 0.75, 0.5, duration: 1)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.timingCurve(0.25, 0.5, .nan, 0.5, duration: 1)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.timingCurve(0.25, 0.5, 0.75, .nan, duration: 1)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.timingCurve(0.25, 0.5, 0.75, 0.5, duration: .infinity)
    }
}

// MARK: - Task 3: `animated(_:_:for:pass:)`, the shared registration-time helper
//
// M4 spec 3 §5/§6. Every test below drives the helper directly against a
// throwaway `Frame`/`LayoutPass`, on `StackElementTests.swift`'s own footing
// — no `Window`, no real element tree, just the pass surface the helper
// actually consumes. `animFrame` shares one `StateTable` across several
// `Frame` instances so state persists the way `Window` really threads it
// across frames (`AXNodeTests.swift`'s `sharedFrame` does the same for a
// different reason).

@MainActor private func eid(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

/// At `Frame`'s default authority (the registering-site guard stage 6b pinned to
/// `.legacy`, `LR-DI`, was its only other caller, retired at stage 7b, record §49
/// row 241).
@MainActor private func animFrame(_ table: StateTable, timestamp: Double, side: Float = 300) -> Frame {
    Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)),
          scaleFactor: 1, stateTable: table, timestamp: timestamp)
}

/// Spec §9 test 1's first half. A field that differs while a transaction is
/// in flight begins animating: the frame that STARTS the transition reads
/// its own `from` (elapsed 0), and the next frame — still declaring the new
/// target, no transaction needed on its own part — reads a value strictly
/// between old and new.
@Test @MainActor func aFieldThatDiffersUnderATransactionBeginsAnimatingAndReadsAnIntermediateValueNextFrame() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.flexGrow = 0

    // Frame 1: establish the baseline, no transaction.
    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    let (out1, _) = animated(style, Decoration(), for: id, pass: &pass1)
    #expect(out1.flexGrow == 0)

    // Frame 2: flexGrow -> 100 inside a transaction, same timestamp as frame
    // 1 — this is the instant the animation starts, so it reads `from`.
    style.flexGrow = 100
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        let (out2, _) = animated(style, Decoration(), for: id, pass: &pass2)
        #expect(out2.flexGrow == 0, "the frame that starts the transaction reads its own `from`, not the target")
    }

    // Frame 3: half a second later, still declaring 100 — no transaction of
    // its own; this is the animation begun in frame 2 still running.
    var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
    let (out3, _) = animated(style, Decoration(), for: id, pass: &pass3)
    #expect(out3.flexGrow == 50, "linear(duration: 1) halfway through should read 50, got \(out3.flexGrow)")
}

/// Spec §9 test 1's second half, and the asymmetry is the evidence: the
/// SAME change with no transaction in flight applies immediately and stays
/// put — it does not merely start faster, it never animates at all.
@Test @MainActor func aFieldChangedWithNoTransactionSnaps() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.flexGrow = 0

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)

    style.flexGrow = 100
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0.001))
    let (out2, _) = animated(style, Decoration(), for: id, pass: &pass2)
    #expect(out2.flexGrow == 100, "no transaction in flight — the new value must apply immediately")

    // And it must STAY at 100 rather than having quietly started some
    // animation a later frame would still be advancing.
    var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
    let (out3, _) = animated(style, Decoration(), for: id, pass: &pass3)
    #expect(out3.flexGrow == 100)
}

/// Spec §9 test 7. `display` is not in spec §4's animatable list at all, so
/// this helper never intercepts it — it always carries the caller's own
/// latest declared value straight through, transaction or not.
@Test @MainActor func aSnappingFieldLikeDisplayTakesItsNewValueImmediatelyEvenInsideATransaction() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.display = .flex

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)

    style.display = .stack
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        let (out2, _) = animated(style, Decoration(), for: id, pass: &pass2)
        #expect(out2.display == .stack, "display has no midpoint and must snap even inside a transaction")
    }
}

/// Spec §9 test 8, first direction. `.auto` carries no number, so a
/// transition to a declared length has nothing to interpolate from — it
/// snaps even mid-transaction, and stays snapped on a later frame rather
/// than having started some deferred motion.
@Test @MainActor func aDimensionTransitionFromAutoToLengthSnaps() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.size.width = .auto

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)

    style.size.width = .length(.pixels(Pixels(100)))
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        let (out2, _) = animated(style, Decoration(), for: id, pass: &pass2)
        #expect(out2.size.width == .length(.pixels(Pixels(100))),
                "`.auto` carries no number to interpolate from, so this must snap")
    }

    var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.3))
    let (out3, _) = animated(style, Decoration(), for: id, pass: &pass3)
    #expect(out3.size.width == .length(.pixels(Pixels(100))), "must still be at the target, not mid-flight")
}

/// Spec §9 test 8, second direction. A percentage's basis is not known at
/// this choke point, so a `.pixels -> .percent` transition — same enum,
/// different case — snaps rather than interpolating the raw numbers.
@Test @MainActor func aLengthTransitionFromPixelsToPercentSnaps() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.padding.top = .pixels(Pixels(0))

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)

    style.padding.top = .percent(50)
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        let (out2, _) = animated(style, Decoration(), for: id, pass: &pass2)
        #expect(out2.padding.top == .percent(50),
                "a percentage's basis is not known here, so a case change must snap")
    }
}

/// Two elements, two independent slots — a bug that shared one `$anim` entry
/// across ids, or clobbered one element's state while writing the other's,
/// would make one or both of these numbers wrong. Both animate to DIFFERENT
/// targets over the same transaction so a mix-up is visible either way.
@Test @MainActor func twoElementsAnimateIndependently() {
    let table = StateTable()
    let a = eid("a")
    let b = eid("b")
    var styleA = Style(); styleA.flexGrow = 0
    var styleB = Style(); styleB.flexGrow = 1000

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(styleA, Decoration(), for: a, pass: &pass1)
    _ = animated(styleB, Decoration(), for: b, pass: &pass1)

    styleA.flexGrow = 100
    styleB.flexGrow = 2000
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        _ = animated(styleA, Decoration(), for: a, pass: &pass2)
        _ = animated(styleB, Decoration(), for: b, pass: &pass2)
    }

    var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
    let (outA, _) = animated(styleA, Decoration(), for: a, pass: &pass3)
    let (outB, _) = animated(styleB, Decoration(), for: b, pass: &pass3)

    #expect(outA.flexGrow == 50, "a: linear(0 -> 100) halfway should read 50, got \(outA.flexGrow)")
    #expect(outB.flexGrow == 1500, "b: linear(1000 -> 2000) halfway should read 1500, got \(outB.flexGrow)")
}

/// Ruling H. `StateTable.write` raises `isDirty` and fires
/// `onWrite -> Window.setNeedsRedraw()`; this helper must use `withState`
/// exclusively, or a window whose style never changes would never let its
/// display link pause — the exact hazard CLAUDE.md's `@State` bullet names,
/// arriving from every registering site on every frame.
@Test @MainActor func theHelperNeverDirtiesTheStateTable() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.flexGrow = 42
    style.padding = Edges(all: .pixels(Pixels(4)))

    for frameIndex in 0..<20 {
        var pass = LayoutPass(frame: animFrame(table, timestamp: Double(frameIndex) / 60))
        _ = animated(style, Decoration(), for: id, pass: &pass)
        #expect(!table.isDirty, "frame \(frameIndex): animated(...) must never dirty the table")
    }
}

/// Ruling I. `withState` inserts on access, and this helper runs at every
/// registering site on every frame — a 500-row `List` would mint 500+
/// entries if an unchanging field re-wrote its slot every frame. A static
/// tree writes its baseline once (frame 1) and then leaves the table flat.
///
/// **Calls `table.sweep()` after every frame (fix round 1, minor c).** The
/// original version of this test never did, so it modelled a sequence of
/// `animated(...)` calls rather than an actual frame loop and could not see
/// ruling P's own interaction with `sweep()` at all — `count` alone cannot
/// distinguish "never wrote again" from "was marked every frame" from "went
/// stale and silently got reaped and re-minted with the same count". This
/// test's element count (25) stays far below `StateTable.sweepThreshold`
/// (256), so the reap itself never engages here regardless — see
/// `aSettledAnimationSurvivesRepeatedSweepsAboveTheThresholdAndStillAnimatesWhenLaterChanged`
/// below for the fixture that forces the reap to actually run.
@Test @MainActor func aStaticTreeLeavesStateTableCountUnchangedAcrossFrames() {
    let table = StateTable()
    let ids = (0..<25).map { eid("el\($0)") }
    var style = Style()
    style.padding = Edges(all: .pixels(Pixels(4)))
    style.flexGrow = 1

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    for id in ids { _ = animated(style, Decoration(), for: id, pass: &pass1) }
    table.sweep()
    let afterFirstFrame = table.count

    for frameIndex in 1..<10 {
        var pass = LayoutPass(frame: animFrame(table, timestamp: Double(frameIndex)))
        for id in ids { _ = animated(style, Decoration(), for: id, pass: &pass) }
        table.sweep()
        #expect(table.count == afterFirstFrame, """
                frame \(frameIndex): a static tree must not keep minting $anim entries \
                (started at \(afterFirstFrame), now \(table.count))
                """)
    }
}

/// Ruling C2 (fix round 1). Neither `count` (the test above) nor `isDirty`
/// (`theHelperNeverDirtiesTheStateTable`) can see write FREQUENCY:
/// re-writing an existing key changes neither the dictionary's size nor
/// `isDirty` (`withState` never sets it). `StateTable.writeCount` is what
/// makes frequency assertable — it increments exactly once inside
/// `withState` and nowhere else, so it is a direct count of how many times
/// this helper actually persisted something, as opposed to how many times it
/// was merely called.
///
/// **Measured to redden under the mutation it guards against**: replacing
/// this helper's `if dirty { withState… } else if !existing.isEmpty {
/// mark… }` with an unconditional `withState` on every call passes both
/// tests above (837/837, 0 issues) and reddens exactly this one. See this
/// task's fix-round report for the reproduced count.
@Test @MainActor func aSettledFieldStopsIncrementingTheWriteCount() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.flexGrow = 7

    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)
    table.sweep()
    let afterFirstFrame = table.writeCount
    #expect(afterFirstFrame == 1, "the first sighting establishes exactly one baseline write")

    for frameIndex in 1..<10 {
        var pass = LayoutPass(frame: animFrame(table, timestamp: Double(frameIndex)))
        _ = animated(style, Decoration(), for: id, pass: &pass)
        table.sweep()
        #expect(table.writeCount == afterFirstFrame, """
                frame \(frameIndex): a settled field must not re-write its slot every frame \
                (writeCount \(table.writeCount), expected \(afterFirstFrame))
                """)
    }
}

/// Ruling P (fix round 1), sharpened by Ruling R (fix round 2). Before the
/// fix, a settled `$anim` entry was never re-marked once it stopped needing
/// a write, so it went stale after `StateTable.staleAfterGenerations` (2)
/// sweeps and was reaped on the next one whenever `storage.count` exceeded
/// `sweepThreshold` (256) — EVEN WHILE its element was produced every single
/// frame. `mark`-ing a settled entry whenever one already exists (this
/// helper does now) keeps it live for as long as its element keeps being
/// produced, which is a STRONGER guarantee than the bounded 2-generation
/// excursion CLAUDE.md documents for `$state`/`$focus`/`$ax` — those go
/// stale the moment their element stops being produced even briefly; this
/// entry does not go stale AT ALL while its element is produced every frame,
/// however long that is.
///
/// **This test's first version changed the value only after the churn had
/// already re-settled to an identical baseline, and that made it BLIND to
/// the exact bug it claimed to guard — measured, not assumed (fix round 2
/// review).** Without ruling P's `mark` call, the entry is reaped at a fixed
/// generation (measured: 4, then again at 8, from the ballast fixture
/// below), and the very next `animated` call — REGARDLESS of whether that
/// call's declared value differs — re-mints a fresh baseline via the
/// first-sighting path, which itself calls `withState` and therefore marks
/// the entry again. So a value change landing on any LATER frame finds an
/// already-fresh, already-marked entry and animates correctly even under
/// the bug — the silent failure exists on exactly ONE frame: the one whose
/// own `peek` first returns `nil`. Removing only `mark` and leaving this
/// test's original "change ten settled frames later" shape reddened **0 of
/// 839**, the identical silent-miss shape ruling `TB-R` records elsewhere.
///
/// **The fix is to change the value DURING the churn window, not after
/// it** — ruling R's mechanism. This version renders settled frames one at
/// a time, checking after each sweep whether `$anim`'s own slot has become
/// unreadable (`peek(slotID, as: AnimatedElementState.self) == nil`), and
/// changes the declared value on the VERY NEXT `animated` call once that
/// happens — the frame the bug can actually reach. Self-discovering rather
/// than hardcoding "4": under ruling P's fix the entry is never reaped at
/// all, so the loop exhausts its bound and `reaped` stays `false`, which is
/// asserted directly as the first, structural half of this test; the
/// second half (a value change immediately afterward still reads a
/// mid-flight value rather than snapping) is Ruling R's own literal ask and
/// is kept as insurance even though, under this fix, the first half alone
/// already implies it.
///
/// **The 260-id padding ballast is `TombstoneTests.swift`'s own idiom**,
/// needed because the fixture's own one real entry never comes close to 256
/// on its own — without it the reap gate never opens and this test would
/// pass vacuously regardless of whether ruling P's fix is present.
@Test @MainActor func aSettledAnimationSurvivesRepeatedSweepsAboveTheThresholdAndStillAnimatesWhenLaterChanged() {
    let table = StateTable()

    let paddingIDs = (0..<260).map {
        GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)"))
    }
    for pad in paddingIDs { table.write(pad, 0) }

    let id = eid("box")
    let slotID = animRetentionSlot(for: id)
    var style = Style()
    style.flexGrow = 0

    // Frame 1: establish the baseline.
    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass1)
    for pad in paddingIDs { table.mark(pad) }
    table.sweep()

    // Settled frames — the value never changes — each followed by a sweep,
    // stopping the INSTANT the entry becomes unreadable (bounded well above
    // the measured generation-4 reap so a shift in the exact arithmetic is
    // still caught). Under ruling P's fix this loop always exhausts its
    // bound without ever finding one.
    var reaped = false
    var lastFrameIndex = 0
    for frameIndex in 1...20 {
        lastFrameIndex = frameIndex
        var pass = LayoutPass(frame: animFrame(table, timestamp: Double(frameIndex)))
        _ = animated(style, Decoration(), for: id, pass: &pass)
        for pad in paddingIDs { table.mark(pad) }
        table.sweep()
        if table.peek(slotID, as: AnimatedElementState.self) == nil {
            reaped = true
            break
        }
    }
    #expect(!reaped, """
            ruling P's mark must keep a continuously-produced settled entry alive \
            indefinitely — it was reaped after frame \(lastFrameIndex) instead
            """)

    // The frame immediately after — reaped or not — is where ruling R's
    // mechanism says a missing `mark` silently snaps rather than animates:
    // it is the exact frame whose own `peek` would first see `nil`.
    style.flexGrow = 100
    let changeTimestamp = Double(lastFrameIndex + 1)
    var passChange = LayoutPass(frame: animFrame(table, timestamp: changeTimestamp))
    withAnimation(.linear(duration: 1)) {
        let (out, _) = animated(style, Decoration(), for: id, pass: &passChange)
        #expect(out.flexGrow == 0, """
                the frame that starts the transaction reads its own `from` (0) — a \
                reaped-and-restarted baseline would read 100 (a snap) instead, got \(out.flexGrow)
                """)
    }

    var passMid = LayoutPass(frame: animFrame(table, timestamp: changeTimestamp + 0.5))
    let (out2, _) = animated(style, Decoration(), for: id, pass: &passMid)
    #expect(out2.flexGrow == 50, """
            halfway through linear(duration: 1) should read 50 — a reaped baseline would have \
            snapped straight to 100 with nothing to interpolate from, got \(out2.flexGrow)
            """)
}

// MARK: - Task 4 / stage 6b test 2.1: every registering site substitutes through `animated`

/// **Test 2.1** (stage 6b, `LR-DO` item 2, `LR-DQ`). **The registering-site guard
/// since stage 7b** (record §49 row 241): its legacy twin,
/// `everyRegisteringSiteAnimatesItsStyle`, read `pass.style(node)` — the CSS
/// tree — under the legacy authority (`LR-DI`, owner 7b) and was retired; a site
/// with no `animated(` call on the proposal path reddens here or in the pin the
/// table names. Spec §5's correction block still holds: there is no single choke
/// point, so each site's call is pinned on its own. Stage 6b's map of each of the
/// retired test's site arms to the test that pins the same site **under the
/// proposal authority**:
///
/// | legacy arm | shared `animated(` call | proposal-side pin (its mutation) |
/// |---|---|---|
/// | `Box` | `Box.swift` | `aLoweredBoxRegistersItsAnimatedWidth` (V7), `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` (V1), `aLoweredMarginRegistersItsAnimatedValue` (V4n) |
/// | `Stack` | `Stack.swift` | `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (V4) |
/// | `ScrollView` content | `ScrollView.swift`'s lowered path, its own call | **none** — `aLoweredScrollViewKeepsItsTwoAnimationSlots` pins the slot's existence, not that the lowered content reads the animated value: **arm (b) here** |
/// | `ScrollView` viewport | the same, its own call | `aLoweredScrollViewKeepsItsTwoAnimationSlots` (the slot). Its values are **unobservable** under the proposal authority by construction: the viewport's `LoweredItem` declares `Style()`, and `LR-AS` builds every item wrapper from the declared style, so no animated viewport field is ever read |
/// | `Component` member's own declaration | the member `Box`'s | the `Box` row (the member IS a `Box`, lowered by the same branch) |
/// | a caller's modifier on a `Component` | none (B-7: snaps on both paths) | **none**: **arm (c) here**, pinned wrong on purpose as the legacy arm is |
/// | `ModifiedElement` inner layer | `ModifiedElement.swift`, per layer | **none** — 4.7 and 4.11 animate a one-layer chain's frame layer only: **arm (a)**, inner half |
/// | `ModifiedElement` outermost layer | the same | 4.7 / 4.11 for a **frame** layer; a padding layer's own lowering is unpinned: **arm (a)**, outermost half |
///
/// Every arm renders through `Frame.render` under `.proposal` in a 200×100
/// top-leading `DifferentialRoot`, with diagnostics on and each report required
/// empty, and reads `Frame.elementBounds` — the lowered rects, not a `Style`.
///
/// - **(a)** `Box(10×10).padding(inner).padding(outer)`, inner 4 → 20 and outer
///   8 → 40 under `withAnimation(.linear(duration: 1))`. Derived by hand: before
///   and at the transaction's start the outer layer is (0, 0) 34×34, the inner
///   (8, 8) 18×18 and the leaf (12, 12); half-way (inner 12, outer 24) the outer is
///   (0, 0) 82×82, the inner (24, 24) 34×34 and the leaf (36, 36).
/// - **(b)** `Box { ScrollView(.vertical) { Box(20×10) } }.width(80).height(60)`
///   with an in-flight `padding.left` 40 → 0 seeded into the content node's `$anim`
///   slot (the legacy arm's seeding, a length a lowered container's
///   `paddedAndSized` reads from the animated style): half-way the leaf sits 20
///   right of the viewport's x; the unseeded control, 0.
/// - **(c)** `Row { Panel(100).width(196 → 320).height(40 → 80); 1×1 marker }`:
///   under the proposal authority a caller's `.width` on a component is a native
///   frame around each member (`loweredComponentFrame`, divergence 48's fix), and
///   it SNAPS — the marker's x (the frame's width) reads the target 320 at the
///   transaction's start and half-way, where an animating frame would read 196
///   then 258. **Wrong on purpose (B-7)**: if this reads 196 / 258, the snap is
///   fixed; flip the arm with the legacy one.
///
/// Mutations, one per new arm (record §41 §11): the inner layer lowered from its
/// declared style (`lowerLegacyLayer` handed the pre-`animated` style) reddens
/// (a)'s inner half; the same for the outermost layer, its outer half; the lowered
/// `ScrollView`'s content `animated(` call dropped reddens (b) (and
/// `aLoweredScrollViewKeepsItsTwoAnimationSlots`). (c) has no `animated(` call to
/// drop: it pins an absence, and its reddening event is B-7's fix.
@Test @MainActor func everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority() throws {
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
        GlobalElementID.child(of: parent, at: index, name: nil)
    }
    func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
    }
    /// One proposal frame over `element` in a 200×100 top-leading harness root,
    /// report required empty; the bounds of `ids`.
    func rects<E: ElementGroup>(_ table: StateTable, _ ids: [GlobalElementID], timestamp: Double,
                                animating: Bool, _ element: E) -> [Bounds<Pixels>?] {
        var harness = DifferentialRoot(width: 200, height: 100) { element }
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          stateTable: table, timestamp: timestamp,
                          transaction: animating ? .linear(duration: 1) : nil, reportsUnlowerableFields: true,
                          recordsElementBounds: true)
        frame.render(&harness)
        #expect(frame.unlowerableFields.isEmpty, "t \(timestamp): \(frame.unlowerableFields)")
        return ids.map { frame.elementBounds[$0] }
    }

    // MARK: (a) ModifiedElement — the inner padding layer and the outermost one
    do {
        let outer = child(root, 0), inner = child(outer, 0), leaf = child(inner, 0)
        func chain(inner: Float, outer: Float) -> ModifiedElement<Box<EmptyGroup>> {
            Box().cssWidth(Pixels(10)).cssHeight(Pixels(10))
                .padding(Edges(all: .pixels(Pixels(inner))))
                .padding(Edges(all: .pixels(Pixels(outer))))
        }
        let table = StateTable()
        let ids = [outer, inner, leaf]
        let baseline = rects(table, ids, timestamp: 0, animating: false, chain(inner: 4, outer: 8))
        let start = rects(table, ids, timestamp: 0, animating: true, chain(inner: 20, outer: 40))
        let mid = rects(table, ids, timestamp: 0.5, animating: false, chain(inner: 20, outer: 40))
        let rest = [bounds(0, 0, 34, 34), bounds(8, 8, 18, 18), bounds(12, 12, 10, 10)]
        try #require(baseline == rest, "(a) set up — the baseline chain: \(baseline)")
        #expect(start[0] == rest[0] && mid[0] == bounds(0, 0, 82, 82),
                "(a) outermost padding layer: expected 34 then 82 wide, got \(start[0].map(String.init(describing:)) ?? "nil") then \(mid[0].map(String.init(describing:)) ?? "nil")")
        #expect(start[1] == rest[1] && start[2] == rest[2]
                    && mid[1] == bounds(24, 24, 34, 34) && mid[2] == bounds(36, 36, 10, 10),
                "(a) inner padding layer: expected the leaf at 12 then 36 inside an 18 then 34 layer, got start \(start) mid \(mid)")
    }

    // MARK: (b) ScrollView — the lowered content node reads its animated style
    do {
        let scroller = child(child(root, 0), 0)
        let leaf = child(scroller, 0)
        func tree() -> Box<ScrollView<Box<EmptyGroup>>> {
            Box { ScrollView(.vertical) { Box().cssWidth(Pixels(20)).cssHeight(Pixels(10)) } }
                .cssWidth(Pixels(80)).cssHeight(Pixels(60))
        }
        func leafOffset(seeded: Bool) throws -> Float {
            let table = StateTable()
            if seeded {
                // The legacy arm's seeding, at the lowered branch's own slot: the
                // baseline is the content style the site declares this frame (a
                // column, every other field default), so only the seeded field is
                // in flight.
                var seedStyle = Style()
                seedStyle.flexDirection = .column
                table.write(animRetentionSlot(for: scrollViewContentAnimID(for: scroller)),
                            AnimatedElementState(style: seedStyle, decoration: Decoration(), inFlight: [
                                "padding.left": AnimatedFieldState(caseTag: 0, from: 40, to: 0, startTime: 0,
                                                                   animation: .linear(duration: 1), velocity: 0)
                            ]))
            }
            let r = rects(table, [scroller, leaf], timestamp: 0.5, animating: false, tree())
            let viewport = try #require(r[0], "(b) the scroller recorded no bounds")
            let content = try #require(r[1], "(b) the leaf recorded no bounds")
            return content.origin.x.value - viewport.origin.x.value
        }
        let control = try leafOffset(seeded: false)
        try #require(control == 0, "(b) set up — unseeded, the leaf is at the viewport's x: \(control)")
        let seeded = try leafOffset(seeded: true)
        #expect(seeded == 20, """
                (b) ScrollView content node: the lowered content must lay out the interpolated \
                padding.left (20 half-way from 40 to 0), got \(seeded)
                """)
    }

    // MARK: (c) Component — a caller's modifier snaps (B-7), wrong on purpose
    do {
        struct Panel: Component {
            var content: some ElementGroup { Box().cssWidth(Pixels(100)).cssHeight(Pixels(10)) }
        }
        let row = child(root, 0)
        let marker = child(row, 1)
        func tree(_ w: Float, _ h: Float) -> some Element {
            Row {
                Panel().width(Pixels(w)).height(Pixels(h))
                Box().cssWidth(Pixels(1)).cssHeight(Pixels(1))
            }.alignItems(.flexStart)
        }
        let table = StateTable()
        func markerX(_ w: Float, _ h: Float, timestamp: Double, animating: Bool) -> Float? {
            rects(table, [marker], timestamp: timestamp, animating: animating, tree(w, h))[0]?.origin.x.value
        }
        try #require(markerX(196, 40, timestamp: 0, animating: false) == 196,
                     "(c) set up — the component's frame is 196 wide before the change")
        let start = markerX(320, 80, timestamp: 0, animating: true)
        let mid = markerX(320, 80, timestamp: 0.5, animating: false)
        #expect(start == 320 && mid == 320, """
                WRONG ON PURPOSE — B-7, under the proposal authority too. A caller's .width on a \
                Component snaps: an animating frame would read 196 then 258, and today reads the \
                target 320 at both. If this now reads 196 / 258, the snap is fixed; flip this arm \
                with the legacy one. Read \(String(describing: start)) then \(String(describing: mid))
                """)
    }
}

// MARK: - Task 4 fix round 1: the `Decoration` half was unguarded at every site

/// **`everyRegisteringSiteAnimatesItsStyle` (retired at stage 7b, record §49
/// row 241) read back only `pass.style(node)`,
/// which cannot see `decoration` at all — so `Box.swift`'s own comment
/// ("storing the result back on `self` … is what makes `cornerRadius`
/// animation … reach the screen rather than only the layout node") shipped
/// with ZERO coverage.** Measured, not assumed: mutating `Box.swift` and
/// `Stack.swift`'s `(style, decoration) = animated(…)` to `(style, _) =
/// animated(…)` — dropping the returned `Decoration` on the floor while
/// still substituting `Style` correctly — reddens **0 of 840**. Every
/// existing test either never touches `Decoration` at all or drives
/// `animated(_:_:for:pass:)` directly rather than through a real element's
/// `requestLayout`, so nothing was reading `Box`/`Stack`'s own
/// `self.decoration` back after the call.
///
/// This test does: it builds a real `Box`/`Stack`, calls its `requestLayout`
/// through a real `LayoutPass`, and reads `element.decoration.cornerRadius`
/// back off `self` afterward — exactly the read `Box.paint` performs later
/// the same frame, which is why the mutation above is invisible to every
/// rect-based assertion in the suite (paint is never reached from a bare
/// `requestLayout` call) but is not invisible here.
@Test @MainActor func decorationSubstitutionReachesTheElementOnBoxAndStack() throws {
    func cornerRadius(_ points: Float) -> Decoration {
        var d = Decoration()
        d.cornerRadius = Pixels(points)
        return d
    }

    // MARK: Box

    do {
        let table = StateTable()
        let id = eid("box-decoration")

        var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var box1 = Box(decoration: cornerRadius(0))
        _ = box1.requestLayout(id, pass: &pass1)

        var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var box2 = Box(decoration: cornerRadius(20))
        withAnimation(.linear(duration: 1)) {
            _ = box2.requestLayout(id, pass: &pass2)
        }
        #expect(box2.decoration.cornerRadius.value == 0, """
                Box: decoration substitution does not reach the element — expected the \
                transaction-start value 0, got \(box2.decoration.cornerRadius.value)
                """)

        var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var box3 = Box(decoration: cornerRadius(20))
        _ = box3.requestLayout(id, pass: &pass3)
        #expect(box3.decoration.cornerRadius.value == 10, """
                Box: decoration substitution does not reach the element — expected the \
                halfway value 10, got \(box3.decoration.cornerRadius.value)
                """)
    }

    // MARK: Stack

    do {
        let table = StateTable()
        let id = eid("stack-decoration")

        var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var stack1 = Stack { Box() }.cornerRadius(Pixels(0))
        _ = stack1.requestLayout(id, pass: &pass1)

        var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var stack2 = Stack { Box() }.cornerRadius(Pixels(20))
        withAnimation(.linear(duration: 1)) {
            _ = stack2.requestLayout(id, pass: &pass2)
        }
        #expect(stack2.decoration.cornerRadius.value == 0, """
                Stack: decoration substitution does not reach the element — expected the \
                transaction-start value 0, got \(stack2.decoration.cornerRadius.value)
                """)

        var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var stack3 = Stack { Box() }.cornerRadius(Pixels(20))
        _ = stack3.requestLayout(id, pass: &pass3)
        #expect(stack3.decoration.cornerRadius.value == 10, """
                Stack: decoration substitution does not reach the element — expected the \
                halfway value 10, got \(stack3.decoration.cornerRadius.value)
                """)
    }

    // MARK: ModifiedElement (ruling MC-I; verifier finding on lane 2)

    // The legacy `.padding` wrapper was `Box<Self>` and ran Box's write-back,
    // guarded by the Box arm above. Since lane 2 it is a `ModifiedElement`
    // layer, a different code path with TWO write-backs — the inner layers'
    // and the outermost's — and dropping either returned `Decoration`
    // (`(inner[k].style, _) = animated(…)`, `(outermost.style, _) = animated(…)`)
    // reddened 0 of 1115 before this arm existed. `paint` reads
    // `inner[k].decoration` and `outermost.decoration` later the same frame,
    // so this reads those two back after a real `requestLayout`. The two
    // layers animate to different radii (20 and 40), so a layer reading the
    // other's value, or a shared baseline, is a mismatch.
    do {
        let table = StateTable()
        let id = eid("modified-decoration")

        func radii(inner: Float, outer: Float,
                   at t: Double) -> (layers: Int, inner: Float, outer: Float) {
            var pass = LayoutPass(frame: animFrame(table, timestamp: t))
            var chain = Box().cssWidth(Pixels(10)).cssHeight(Pixels(10))
                .padding(4).cornerRadius(Pixels(inner))
                .padding(8).cornerRadius(Pixels(outer))
            _ = chain.requestLayout(id, pass: &pass)
            return (chain.layerCount,
                    chain.inner.first?.decoration.cornerRadius.value ?? -1,
                    chain.outermost.decoration.cornerRadius.value)
        }

        let baseline = radii(inner: 0, outer: 0, at: 0)
        try #require(baseline.layers == 2,
                     "ModifiedElement: the decoration arm must exercise a two-layer chain")
        var start: (layers: Int, inner: Float, outer: Float)?
        withAnimation(.linear(duration: 1)) {
            start = radii(inner: 20, outer: 40, at: 0)
        }
        let mid = radii(inner: 20, outer: 40, at: 0.5)
        #expect(start?.inner == 0 && mid.inner == 10, """
                ModifiedElement INNER layer: decoration substitution does not reach the \
                element — expected 0 then 10, got \(String(describing: start?.inner)) then \
                \(mid.inner)
                """)
        #expect(start?.outer == 0 && mid.outer == 20, """
                ModifiedElement outermost layer: decoration substitution does not reach the \
                element — expected 0 then 20, got \(String(describing: start?.outer)) then \
                \(mid.outer)
                """)
    }
}

// MARK: - Task 4 fix round 2: ruling U's own two mechanisms

/// **Ruling U's two load-bearing lines were entirely unpinned, and this test
/// is the only thing that observes either of them.** Measured by the fix
/// round 1 re-review, each mutation run separately in an isolated worktree:
/// deleting `inFlight[key] = nil` on `animateField`'s `current.isFinished`
/// branch (`AnimatedStyle.swift`) reddened **0 of 841**, and deleting all
/// three of `number`/`length`/`dimension`'s fast-path gates
/// (`if inFlight[key] == nil && declared == previous { return declared }`)
/// reddened **0 of 841**. No test in the suite asserted anything about
/// `inFlight` at all — so the whole "a settled element stores an EMPTY
/// dictionary, not 28 idle records" claim the 91.6% memory reduction rests on
/// was unobserved.
///
/// The four checkpoints below are one lifecycle, and they are **three**
/// mechanisms rather than four samples of one — checkpoint 1 is the fourth and
/// it is a sanity assertion, not a pinned mechanism:
///
/// 1. **A settled element's `inFlight` is empty** — the resting state ruling U
///    exists to make cheap. **Neither mutation below reddens this checkpoint**,
///    measured rather than reasoned: both were re-run at `18a137d` and the
///    reddened assertions are named in the table's own rows, and this one is
///    in neither. An element that has never had a field differ never reaches
///    `animateField` at all, so neither the `inFlight[key] = nil` deletion nor
///    the gate deletion can put anything here. It is worth asserting — a
///    first-sighting baseline that enrolled its 28 fields would be exactly the
///    allocation ruling U removed — but it is a sanity check on the entry
///    conditions of checkpoints 2-4, and calling it a fourth pinned mechanism
///    would overstate what was measured.
/// 2. **Mid-flight it holds exactly the one field that is moving**, asserted
///    by KEY and not only by count: a count alone cannot tell "flexGrow is
///    animating" from "some other field is animating instead".
/// 3. **It is empty again on the settle frame** ← the `inFlight[key] = nil`
///    mutation reddens here. Values stay correct under that mutation (the
///    settled branch still returns `declared`), so nothing else in the suite
///    can see it; what leaks is memory, one entry per field that has ever
///    animated, for the element's whole life.
/// 4. **An UNCHANGED frame under a live transaction leaves it empty** ← the
///    gate mutation reddens here, and this is the checkpoint that matters
///    for the future rather than for today. The gates are currently
///    value-equivalent because `Animation.pendingTransaction` is only live
///    inside `withAnimation`'s own lexical body (ruling V) — which is why
///    this test, like every other one in this file, calls `animated(...)`
///    *inside* that closure to see a transaction at all. Once Task 5 makes
///    the transaction ambient for a whole frame build, the ungated mutant
///    puts **all 28 fields of every element in the tree** into `inFlight` on
///    every transaction frame, reinstating exactly the allocation ruling U
///    removed.
///
/// **Both mutations were re-run against this test, in an isolated worktree,
/// and both discriminate** (843 tests; six per-target summary lines confirmed
/// summing before any issue count was believed). Re-taken by fix round 3 at
/// `18a137d`, because that round changed `allAnimatableFields` and a fixture
/// change can move a figure recorded under the old one — both counts
/// reproduced, and the second row's **checkpoint attribution did not**:
///
/// | mutation | result |
/// |---|---|
/// | delete `inFlight[key] = nil` on the `isFinished` branch | **3 issues / 2 tests** — checkpoints 3 and 4 here, plus `allTwentyEight…`'s own settle assertion |
/// | delete all three fast-path gates | **3 issues / 1 test** — checkpoint 2's *two* assertions (`atStart` and `atMid`) and checkpoint 4 here, and nothing else in the suite |
///
/// That second row read "checkpoints 2, 3 and 4" until it was re-run: the
/// three issues are `atStart`, `atMid` and checkpoint 4, and **checkpoint 3
/// does not redden under the gate deletion at all**. The count was right and
/// the attribution was not, which is precisely the kind of claim the count
/// alone hides — the reason this branch names the tests, and now the
/// assertions, that a mutation reddens.
///
/// The gate mutation reddens more of this test than predicted, and the reason
/// is worth knowing rather than being read as slack: with the gates gone, the
/// *transition-start* frame (checkpoint 2) also enrols all 28 fields, because
/// every unchanged field then reaches `animateField` under the same live
/// transaction. Checkpoint 4 is still the one that isolates the mechanism —
/// it is the only checkpoint with **no** field differing at all.
///
/// Two honest negatives, stated because a bare "it reddens" hides them:
/// this test does **not** redden under the 25-field-deletion mutation that
/// `allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` is for
/// (it drives `flexGrow`, one of the three fields that survive it), and that
/// test does not redden under the gate mutation (its transaction frames
/// change all 28 fields, so the gates never fire in it). The two tests cover
/// different lines and neither subsumes the other.
@Test @MainActor func theInFlightDictionaryIsEmptyWhenSettledAndHoldsOnlyTheMovingField() throws {
    let table = StateTable()
    let id = eid("lifecycle")
    let slot = animRetentionSlot(for: id)

    func inFlightKeys(_ label: String) throws -> [String] {
        let state = try #require(table.peek(slot, as: AnimatedElementState.self),
                                 "\(label): the $anim slot must hold an AnimatedElementState")
        return state.inFlight.keys.sorted()
    }

    var style = Style()
    style.flexGrow = 0

    // 1. First sighting, and then three unchanged frames: nothing has ever
    //    differed, so nothing is in flight.
    var pass0 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(style, Decoration(), for: id, pass: &pass0)
    let atFirstSighting = try inFlightKeys("first sighting")
    #expect(atFirstSighting.isEmpty, """
            a first-sighting baseline must store an EMPTY inFlight dictionary, got \(atFirstSighting)
            """)

    for frameIndex in 1...3 {
        var pass = LayoutPass(frame: animFrame(table, timestamp: Double(frameIndex) / 60))
        _ = animated(style, Decoration(), for: id, pass: &pass)
        let settledKeys = try inFlightKeys("settled frame \(frameIndex)")
        #expect(settledKeys.isEmpty, """
                a settled element must store an EMPTY inFlight dictionary — frame \(frameIndex) \
                holds \(settledKeys)
                """)
    }

    // 2. Start a transition: exactly one field moves, and it is `flexGrow`.
    style.flexGrow = 100
    var passStart = LayoutPass(frame: animFrame(table, timestamp: 1))
    withAnimation(.linear(duration: 1)) {
        _ = animated(style, Decoration(), for: id, pass: &passStart)
    }
    let atStart = try inFlightKeys("transition start")
    #expect(atStart == ["flexGrow"], """
            the frame that starts a transition must put exactly the moving field in flight, \
            got \(atStart)
            """)

    var passMid = LayoutPass(frame: animFrame(table, timestamp: 1.5))
    let (mid, _) = animated(style, Decoration(), for: id, pass: &passMid)
    #expect(mid.flexGrow == 50, "sanity: halfway through linear(duration: 1), got \(mid.flexGrow)")
    let atMid = try inFlightKeys("mid-flight")
    #expect(atMid == ["flexGrow"], """
            a mid-flight element must hold exactly the moving field, got \(atMid)
            """)

    // 3. The settle frame removes it again. This is the checkpoint the
    //    `inFlight[key] = nil` deletion reddens: `settled.flexGrow` is still
    //    100 under that mutation, so only the dictionary can see it.
    var passSettle = LayoutPass(frame: animFrame(table, timestamp: 2))
    let (settled, _) = animated(style, Decoration(), for: id, pass: &passSettle)
    #expect(settled.flexGrow == 100, "sanity: the settle frame reads the target, got \(settled.flexGrow)")
    let atSettle = try inFlightKeys("settle")
    #expect(atSettle.isEmpty, """
            a finished animation must leave inFlight entirely — ruling U's whole claim — \
            got \(atSettle)
            """)

    // 4. An UNCHANGED frame under a LIVE transaction must still leave it
    //    empty: a transaction is permission to animate a difference, not an
    //    instruction to enrol every field that has none.
    var passIdleTransaction = LayoutPass(frame: animFrame(table, timestamp: 3))
    withAnimation(.linear(duration: 1)) {
        _ = animated(style, Decoration(), for: id, pass: &passIdleTransaction)
    }
    let underIdleTransaction = try inFlightKeys("unchanged frame under a live transaction")
    #expect(underIdleTransaction.isEmpty, """
            an unchanged frame under a live transaction must enrol NOTHING — the fast-path \
            gates are what keep all 28 fields out of inFlight, got \(underIdleTransaction)
            """)
}

/// **All 28 animatable fields, in one table — because the suite pins three.**
/// Measured by the fix round 1 re-review: instrumenting `animateField` to
/// print its key and running the unfiltered suite showed only **6 of the 28
/// keys are ever reached at all** (`size.width`, `size.height`, `flexGrow`,
/// `flexShrink`, `cornerRadius`, `padding.top`), and deleting **25 of the 28**
/// field assignments from `animated(...)` left **841 tests, 0 issues**. The
/// positive control — also deleting `flexGrow`, `flexShrink` and
/// `cornerRadius` — reddened 6 tests / 19 issues, so the instrument worked and
/// the zero was the finding: 25 of the 28 fields could have been silently
/// un-wired and nothing would have noticed.
///
/// **The explicit non-`.auto` baseline is load-bearing, not tidiness.**
/// `inset`, `size`, `minSize`, `maxSize` and `flexBasis` all default to
/// `.auto`, and `.auto -> .length` snaps by spec §4 rule 1 — so from a plain
/// `Style()` baseline only 17 of the 28 fields go in flight and the other 11
/// sit at their declared value, which would make this test's midpoint
/// assertion vacuous for exactly those 11. `allAnimatableFields(0)` gives
/// every one of the 28 a concrete pixel baseline first.
///
/// **The baseline is also per-field DISTINCT, and that half was added by fix
/// round 3 after a measurement.** The *i*-th field of `animatableFieldOrder`
/// runs `i -> 100 + i` and must read `50 + i` here. Fix round 2 shipped this
/// test with a uniform fixture — every field `0 -> 100`, every midpoint
/// compared against the same literal `50` — under which a crossed read, a
/// crossed key and a crossed assignment are all invisible, because both sides
/// of every swap carry the same number. Measured, in an isolated worktree at
/// `18a137d`: cross-wiring `minSize.width` and `maxSize.width` in
/// `animated(...)` left the whole suite **green at 843, 0 issues**. Under the
/// distinct fixture the same mutation reddens this test and names both fields.
///
/// Both halves are asserted: every field reads **exactly** halfway at t = 0.5,
/// and all 28 leave `inFlight` on the settle frame — the same lifecycle
/// `theInFlightDictionaryIsEmptyWhenSettledAndHoldsOnlyTheMovingField` pins
/// for one field, taken across the whole table.
///
/// **The key-set assertion's `unexpected` half is what guards the plan's
/// "`aspectRatio` must not become animatable" constraint, and it needs the
/// fixtures to differ in that field to have any teeth.** Every wiring in
/// `animated(...)` mints its key only when the field differs from its
/// baseline, so a field left equal in both fixtures can be wired and mint
/// nothing. Measured, same worktree and commit: with `aspectRatio` `nil` in
/// both fixtures, wiring it into `animated(...)` left the suite **green at
/// 843, 0 issues** — the constraint was unguarded. `allAnimatableFields` now
/// gives it `1.0` and `2.0`, and `allAnimatableDecoration` gives the three
/// non-animatable colour fields two distinct token sets, for the same reason.
///
/// **Neither this test nor
/// `theInFlightDictionaryIsEmptyWhenSettledAndHoldsOnlyTheMovingField` goes
/// through a registering site** — both call `animated(...)` directly, so
/// neither would notice `Box`/`Stack`/`ScrollView` being un-wired. That is
/// `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` and the
/// per-site guards' job (`everyRegisteringSiteAnimatesItsStyle` until stage 7b); this
/// test covers the field table, not the call sites.
///
/// **The 25-field deletion was re-run against this test in an isolated
/// worktree and reddens it alone: 843 tests, `26 issues / 1 test`** — the
/// key-set assertion, which names all 25 missing keys in its own message, plus
/// one midpoint assertion per deleted field (15 `Dimension` + 10 `Length`).
/// Nothing else in the suite moved, which is the re-review's `0 of 841`
/// reproduced with this test as the only difference. Re-taken at `18a137d`
/// against the distinct fixture rather than carried, because a fixture change
/// can move a mutation figure recorded under the old one.
@Test @MainActor func allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle() throws {
    let dimensionFields: [(key: String, read: (Style) -> Dimension)] = [
        ("inset.top", { $0.inset.top }),
        ("inset.right", { $0.inset.right }),
        ("inset.bottom", { $0.inset.bottom }),
        ("inset.left", { $0.inset.left }),
        ("size.width", { $0.size.width }),
        ("size.height", { $0.size.height }),
        ("minSize.width", { $0.minSize.width }),
        ("minSize.height", { $0.minSize.height }),
        ("maxSize.width", { $0.maxSize.width }),
        ("maxSize.height", { $0.maxSize.height }),
        ("margin.top", { $0.margin.top }),
        ("margin.right", { $0.margin.right }),
        ("margin.bottom", { $0.margin.bottom }),
        ("margin.left", { $0.margin.left }),
        ("flexBasis", { $0.flexBasis }),
    ]
    let lengthFields: [(key: String, read: (Style) -> Length)] = [
        ("padding.top", { $0.padding.top }),
        ("padding.right", { $0.padding.right }),
        ("padding.bottom", { $0.padding.bottom }),
        ("padding.left", { $0.padding.left }),
        ("border.top", { $0.border.top }),
        ("border.right", { $0.border.right }),
        ("border.bottom", { $0.border.bottom }),
        ("border.left", { $0.border.left }),
        ("gap.horizontal", { $0.gap.horizontal }),
        ("gap.vertical", { $0.gap.vertical }),
    ]
    let numberFields: [(key: String, read: (Style) -> Float)] = [
        ("flexGrow", { $0.flexGrow }),
        ("flexShrink", { $0.flexShrink }),
    ]
    // `animatableFieldOrder` is this file's single source for both the fixture
    // values and the expected midpoints, so the four tables here must name
    // exactly the same keys as it does. `try #require`, not `#expect`: every
    // fixture call below indexes into that table by key.
    let expectedKeys = animatableFieldOrder.sorted()
    try #require((dimensionFields.map(\.key) + lengthFields.map(\.key)
                  + numberFields.map(\.key) + ["cornerRadius"]).sorted() == expectedKeys,
                 "the tables above and animatableFieldOrder must name the same fields")
    // A tripwire on THIS TEST's own tables and nothing else — it counts the
    // literals a few lines above it, so it cannot observe `Sources/` or spec
    // §4 moving, only someone editing one of these lists. The assertion that
    // observes `animated(...)` is the key-set one below.
    #expect(expectedKeys.count == 28, "expected 28 animatable fields, listed \(expectedKeys.count)")

    let table = StateTable()
    let id = eid("all-fields")
    let slot = animRetentionSlot(for: id)

    // Frame 1: an explicit, per-field distinct pixel baseline for all 28 —
    // field `i` starts at `i`, not all 28 at 0.
    var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
    _ = animated(allAnimatableFields(0), allAnimatableDecoration(0), for: id, pass: &pass1)

    // Frame 2: all 28 change to `100 + i` inside one transaction.
    let target = allAnimatableFields(100)
    let targetDecoration = allAnimatableDecoration(100)
    var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
    withAnimation(.linear(duration: 1)) {
        _ = animated(target, targetDecoration, for: id, pass: &pass2)
    }
    let started = try #require(table.peek(slot, as: AnimatedElementState.self)).inFlight
    #expect(started.keys.sorted() == expectedKeys, """
            every animatable field must be in flight after the transition starts — missing \
            \(Set(expectedKeys).subtracting(started.keys).sorted()), unexpected \
            \(Set(started.keys).subtracting(expectedKeys).sorted())
            """)

    // Frame 3: exactly halfway, for every field independently — and every
    // field's halfway value is its OWN `50 + i`, so a crossed field lands a
    // number that belongs to a different, named field rather than the 50 that
    // every field would have shared.
    var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
    let (mid, midDecoration) = animated(target, targetDecoration, for: id, pass: &pass3)
    for field in dimensionFields {
        let half = 50 + fieldOffset(field.key)
        #expect(field.read(mid) == Dimension.length(.pixels(Pixels(half))),
                "\(field.key): expected the halfway value \(half), got \(field.read(mid))")
    }
    for field in lengthFields {
        let half = 50 + fieldOffset(field.key)
        #expect(field.read(mid) == Length.pixels(Pixels(half)),
                "\(field.key): expected the halfway value \(half), got \(field.read(mid))")
    }
    for field in numberFields {
        let half = 50 + fieldOffset(field.key)
        #expect(field.read(mid) == half,
                "\(field.key): expected the halfway value \(half), got \(field.read(mid))")
    }
    let halfCornerRadius = 50 + fieldOffset("cornerRadius")
    #expect(midDecoration.cornerRadius.value == halfCornerRadius,
            """
            cornerRadius: expected the halfway value \(halfCornerRadius), got \
            \(midDecoration.cornerRadius.value)
            """)

    // Frame 4: the settle frame empties `inFlight` for all 28 at once.
    var pass4 = LayoutPass(frame: animFrame(table, timestamp: 1))
    _ = animated(target, targetDecoration, for: id, pass: &pass4)
    let settled = try #require(table.peek(slot, as: AnimatedElementState.self)).inFlight
    #expect(settled.isEmpty, """
            every finished field must leave inFlight on the settle frame — \
            \(settled.keys.sorted()) stayed
            """)
}

/// Spec §4's 28 animatable fields in one canonical order, so that every fixture
/// value and every expected midpoint in
/// `allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` can be
/// **distinct per field**: the *i*-th field animates `i -> 100 + i` and reads
/// `50 + i` at the midpoint.
///
/// This table exists because the uniform version of that fixture was shape 1 of
/// `docs/practices/verifying-tests-can-fail.md` — "uniform values on both sides
/// of an assertion". With all 28 fields at `0 -> 100` and every midpoint
/// compared against the same literal `50`, swapping two same-typed baseline
/// reads, two declared reads, two key strings or two assignment targets in
/// `animated(...)` is invisible: both sides of every swap hold the same number.
/// Measured in an isolated worktree at `18a137d` — cross-wiring
/// `minSize.width` and `maxSize.width` left the suite **green at 843, 0
/// issues**; with these offsets it reddens, naming both fields.
private let animatableFieldOrder: [String] = [
    "inset.top", "inset.right", "inset.bottom", "inset.left",
    "size.width", "size.height",
    "minSize.width", "minSize.height",
    "maxSize.width", "maxSize.height",
    "margin.top", "margin.right", "margin.bottom", "margin.left",
    "flexBasis",
    "padding.top", "padding.right", "padding.bottom", "padding.left",
    "border.top", "border.right", "border.bottom", "border.left",
    "gap.horizontal", "gap.vertical",
    "flexGrow", "flexShrink",
    "cornerRadius",
]

/// One animatable field's fixture offset: its index in `animatableFieldOrder`.
///
/// Traps on an unknown key rather than returning a sentinel, because a sentinel
/// would be handed to the fixture and to the expectation alike and the two
/// would agree on it — a silent pass. The trap is reachable only from a typo in
/// this file's own key literals, never from any value produced by `Sources/`,
/// so no mutation of the code under test can route here and truncate the run
/// (the practices doc's shape 13).
private func fieldOffset(_ key: String) -> Float {
    guard let index = animatableFieldOrder.firstIndex(of: key) else {
        preconditionFailure("\(key) is not one of animatableFieldOrder's fields")
    }
    return Float(index)
}

/// Every one of spec §4's 28 animatable fields at a concrete, non-`.auto`,
/// **per-field distinct** value: field *i* of `animatableFieldOrder` gets
/// `base + i`. Used by
/// `allTwentyEightAnimatableFieldsInterpolateAndLeaveInFlightOnSettle` as both
/// baseline (`base` 0) and target (`base` 100); the five `.auto`-defaulting
/// fields are the reason a concrete baseline exists at all, and the crossed-
/// field measurement is the reason the values are distinct (see that test's
/// doc, and `animatableFieldOrder` above).
@MainActor private func allAnimatableFields(_ base: Float) -> Style {
    func dim(_ key: String) -> Dimension { .length(.pixels(Pixels(base + fieldOffset(key)))) }
    func len(_ key: String) -> Length { .pixels(Pixels(base + fieldOffset(key))) }
    var s = Style()
    s.inset = Edges(top: dim("inset.top"), right: dim("inset.right"),
                    bottom: dim("inset.bottom"), left: dim("inset.left"))
    s.size = Size(width: dim("size.width"), height: dim("size.height"))
    s.minSize = Size(width: dim("minSize.width"), height: dim("minSize.height"))
    s.maxSize = Size(width: dim("maxSize.width"), height: dim("maxSize.height"))
    s.margin = Edges(top: dim("margin.top"), right: dim("margin.right"),
                     bottom: dim("margin.bottom"), left: dim("margin.left"))
    s.padding = Edges(top: len("padding.top"), right: len("padding.right"),
                      bottom: len("padding.bottom"), left: len("padding.left"))
    s.border = Edges(top: len("border.top"), right: len("border.right"),
                     bottom: len("border.bottom"), left: len("border.left"))
    s.gap = Axes(horizontal: len("gap.horizontal"), vertical: len("gap.vertical"))
    s.flexGrow = base + fieldOffset("flexGrow")
    s.flexShrink = base + fieldOffset("flexShrink")
    s.flexBasis = dim("flexBasis")
    // NOT animatable, and the plan's Global Constraints say it must not become
    // so — it is in CLAUDE.md's declared-but-inert table, and animating a
    // property nothing reads is that table's trap doubled. It carries two
    // DIFFERING values across this helper's two call sites purely so the
    // key-set assertion can catch it being wired: every wiring in
    // `animated(...)` mints its key only when the field differs from its
    // baseline, so a field left equal in both fixtures mints nothing and
    // passes. Measured at `18a137d` — with `aspectRatio` nil in both fixtures,
    // wiring it into `animated(...)` left the suite green at 843, 0 issues.
    s.aspectRatio = 1 + base / 100
    return s
}

/// `Decoration`'s one animatable field (`cornerRadius`, offset from
/// `animatableFieldOrder` like the other 27) plus its three non-animatable
/// colour fields.
///
/// The colours differ between this helper's two call sites for exactly the
/// reason `aspectRatio` does: `background`, `hoverBackground` and
/// `focusBackground` pass through `animated(...)` untouched today, and the
/// key-set assertion's `unexpected` half is the only thing that would notice
/// one of them being interpolated instead — which it cannot do while both
/// fixtures leave them at `Decoration()`'s `nil`.
@MainActor private func allAnimatableDecoration(_ base: Float) -> Decoration {
    var d = Decoration()
    d.cornerRadius = Pixels(base + fieldOffset("cornerRadius"))
    if base == 0 {
        d.background = .surface
        d.hoverBackground = .surfaceSecondary
        d.focusBackground = .textPrimary
    } else {
        d.background = .accent
        d.hoverBackground = .separator
        d.focusBackground = .scrollIndicator
    }
    return d
}

// MARK: - Task 4b: `animatedColor(_:for:pass:)`, the PAINT-side colour helper
//
// M4 spec 3 §4's third rule. Colour cannot go through `animated(_:_:for:pass:)`
// and that is structural rather than a shortcut: two `ColorToken`s interpolate
// through their theme-*resolved* `Hsla`, re-resolved every frame, and only
// `PaintPass` has a theme (`Passes.swift`'s `PaintPass.theme`, whose own doc
// says it is deliberately absent from the other two passes and why).
//
// **Every fixture below uses a purpose-built `Theme` whose colours differ in
// every RGB component**, per the Task 4 amendment: a pair that agrees on any
// component cannot tell a helper that reads that component from one that
// transposes it. `probeTheme`'s three subject colours and every expected
// midpoint are hand-computed in the comments, from the endpoints, by the
// arithmetic the helper is supposed to perform — an oracle independent of the
// helper itself (taxonomy shape 12).

/// The interpolation space, SETTLED BY MEASUREMENT rather than by argument
/// (ruling `CO-E`'s precedent, which this task's brief invokes by name).
///
/// Two throwaway probes outside this repo, each with a positive control whose
/// answer was known in advance (black → white must read an achromatic grey
/// strictly between the endpoints):
///
/// - **SwiftUI**, through its own `Animatable` conformance — the mechanism its
///   animation engine actually blends with. `Color.Resolved.animatableData`
///   midpoint of blue → orange: sRGB `(0.4893, 0.5107, 0.7078)`, HSL
///   `s = 0.2722`. Distance to the per-component RGB prediction `0.2799`;
///   to the hue-space prediction `0.7229`.
/// - **CoreAnimation**, end-to-end — a real `CALayer` in a real window, a real
///   `CABasicAnimation` on `backgroundColor`, sampled off the PRESENTATION
///   layer. Blue → orange midpoint `(0.5005, 0.3238, 0.4995)` against the
///   gamma-sRGB per-component prediction `(0.5000, 0.3235, 0.5000)` —
///   agreement to 0.0007, which is the sampling jitter.
///
/// **Both say RGB, neither says hue**, so ruling O's open question is closed:
/// there is no arc, no wrap-around sweep through cyan between two neighbouring
/// reds, and no shortest-arc rule to get wrong. The probes DISAGREE on the
/// encoding — CoreAnimation lerps in gamma-encoded sRGB exactly, SwiftUI in the
/// cube root of linear light (measured at four fractions: black → white reads
/// sRGB 0.1315 / 0.3886 / 0.6813 at t = 0.25 / 0.5 / 0.75, matching
/// `srgbEncode(t³)` to four decimals and NOT matching `t`). This framework
/// takes CoreAnimation's: `Rgba` already IS gamma-encoded sRGB, it is the space
/// the compositor blends in (design spec §7.8, CLAUDE.md's `bgra8Unorm`
/// constraint), and adopting SwiftUI's would add the only linearization in the
/// repo. The cost of being wrong is a fade's midpoint sitting at sRGB 0.5 where
/// SwiftUI's sits at 0.389 — same endpoints, same hue, different pacing.
private let probeBackgroundRGB = Rgba(r: 0.10, g: 0.20, b: 0.80)
private let probeAccentRGB = Rgba(r: 0.90, g: 0.70, b: 0.30)
private let probeSeparatorRGB = Rgba(r: 0.60, g: 0.10, b: 0.90)

/// A theme built for discrimination rather than for looks: `background`,
/// `accent` and `separator` differ in **all three** RGB components and in all
/// three HSL components, and each pairwise midpoint is far from both endpoints
/// on every component asserted.
@MainActor private func probeTheme(background: Rgba = probeBackgroundRGB,
                                   accent: Rgba = probeAccentRGB,
                                   separator: Rgba = probeSeparatorRGB) -> Theme {
    Theme(background: background.toHsla(),
          surface: Rgba(r: 0.05, g: 0.55, b: 0.15).toHsla(),
          surfaceSecondary: Rgba(r: 0.25, g: 0.05, b: 0.45).toHsla(),
          accent: accent.toHsla(),
          separator: separator.toHsla(),
          textPrimary: Rgba(r: 0.85, g: 0.15, b: 0.05).toHsla(),
          scrollIndicator: Rgba(r: 0.15, g: 0.85, b: 0.65).toHsla(),
          scrim: Rgba(r: 0.45, g: 0.35, b: 0.95).toHsla())
}

@MainActor private func colorFrame(_ table: StateTable, timestamp: Double,
                                   theme: Theme, side: Float = 100,
                                   mousePosition: Point<Pixels>? = nil,
                                   focusedElement: GlobalElementID? = nil) -> Frame {
    // (Took an optional layout authority from stage 6b, `LR-DG`, until stage 9.)
    Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)),
               scaleFactor: 1, stateTable: table,
               theme: theme, timestamp: timestamp,
               mousePosition: mousePosition, focusedElement: focusedElement)
}

/// Componentwise, with each component named — never `==` on the whole `Hsla`.
/// A single equality would report "colours differ" and say nothing about which
/// channel moved, and a transposition of two channels is exactly what a
/// whole-value comparison cannot describe.
private func expectColor(_ got: Hsla?, h: Float, s: Float, l: Float,
                         tolerance: Float = 2e-4, _ what: String,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    guard let got else {
        Issue.record("\(what): expected a colour, got nil", sourceLocation: sourceLocation)
        return
    }
    #expect(abs(got.h - h) < tolerance,
            "\(what): h expected \(h), got \(got.h)", sourceLocation: sourceLocation)
    #expect(abs(got.s - s) < tolerance,
            "\(what): s expected \(s), got \(got.s)", sourceLocation: sourceLocation)
    #expect(abs(got.l - l) < tolerance,
            "\(what): l expected \(l), got \(got.l)", sourceLocation: sourceLocation)
}

// Hand-computed, from the endpoints above, by the arithmetic the helper is
// meant to perform — this is the independent oracle, not a value read back out
// of the code under test.
//
//   background (0.10, 0.20, 0.80) -> HSL h=0.642857 s=0.777778 l=0.45
//   accent     (0.90, 0.70, 0.30) -> HSL h=0.111111 s=0.75     l=0.60
//   midpoint   (0.50, 0.45, 0.55):
//       max=0.55 (b), min=0.45 (g), delta=0.10, l=(0.55+0.45)/2 = 0.50
//       s = 0.10 / (1 - |2(0.50) - 1|) = 0.10 / 1 = 0.10
//       h = (r - g)/delta + 4 = (0.50 - 0.45)/0.10 + 4 = 4.5, /6 = 0.75
//
// **The `s = 0.10` is what kills hue-space interpolation dead.** Any
// interpolation through hue keeps saturation near the endpoints' own ~0.76 and
// puts the hue between 0.111 and 0.643; the measured RGB answer desaturates to
// a near-grey instead. This one number is the probe's finding, pinned.
private let midBackgroundToAccent = (h: Float(0.75), s: Float(0.10), l: Float(0.50))

// separator (0.60, 0.10, 0.90) -> HSL h=0.770833 s=0.80 l=0.50
//     (this line read h=0.783333 until fix round 1 re-derived it to build the
//      interruption test's oracle: max is b, so h = (r-g)/delta + 4 = 0.625 + 4
//      = 4.625, /6 = 0.770833. Nothing asserted the endpoint, only the midpoint,
//      which is exactly why a wrong number survived in a comment.)
// background -> separator midpoint (0.35, 0.15, 0.85):
//     max=0.85 (b), min=0.15 (g), delta=0.70, l=0.50, s=0.70/1 = 0.70
//     h = (0.35 - 0.15)/0.70 + 4 = 4.285714, /6 = 0.714286
private let midBackgroundToSeparator = (h: Float(0.714286), s: Float(0.70), l: Float(0.50))

/// **Brief test 1.** A `background` token changed under a transaction reads a
/// genuine MID-FLIGHT `Hsla` at the halfway timestamp — a value equal to
/// neither endpoint, asserted componentwise against a hand-computed midpoint.
/// Not "an animation exists".
///
/// The two extra assertions at the end are the signal the drive loop reads:
/// `Frame.hasActiveAnimations` is raised while the fade is live and left alone
/// once it settles. These said `wantsAnotherFrame` when Task 4b wrote them —
/// Task 5 moved the colour helper onto `hasActiveAnimations` so there is ONE
/// notion of "an animation is live" rather than two that would have kept each
/// other green; see `animatedColor`'s own line for the argument.
@Test @MainActor func aBackgroundTokenChangedUnderATransactionReadsAMidFlightColour() {
    let table = StateTable()
    let theme = probeTheme()
    let id = eid("colour-box")

    var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    let out1 = animatedColor(.background, for: id, pass: &f1)
    expectColor(out1, h: 0.642857, s: 0.777778, l: 0.45, "frame 1 baseline is the declared token")

    // Frame 2: the token changes under a transaction, at the same timestamp —
    // the instant the animation starts, so it reads its own `from`.
    let frame2 = colorFrame(table, timestamp: 0, theme: theme)
    var f2 = PaintPass(frame: frame2)
    var out2: Hsla?
    withAnimation(.linear(duration: 1)) {
        out2 = animatedColor(.accent, for: id, pass: &f2)
    }
    expectColor(out2, h: 0.642857, s: 0.777778, l: 0.45,
                "the frame that starts the transaction reads its own `from`, not the target")
    #expect(frame2.hasActiveAnimations,
            "an animation started this frame must ask for the next one")

    // Frame 3: half a second later, still declaring `.accent`, no transaction
    // of its own — the animation begun in frame 2 still running.
    let frame3 = colorFrame(table, timestamp: 0.5, theme: theme)
    var f3 = PaintPass(frame: frame3)
    let out3 = animatedColor(.accent, for: id, pass: &f3)
    expectColor(out3, h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                l: midBackgroundToAccent.l, "halfway through linear(duration: 1)")
    #expect(frame3.hasActiveAnimations, "still mid-flight: the display link must stay awake")

    // Frame 4: past the end. The value lands exactly on the target and the
    // frame stops asking for another one.
    let frame4 = colorFrame(table, timestamp: 1.5, theme: theme)
    var f4 = PaintPass(frame: frame4)
    let out4 = animatedColor(.accent, for: id, pass: &f4)
    expectColor(out4, h: 0.111111, s: 0.75, l: 0.60, tolerance: 1e-5,
                "finished: exactly the target token's resolved colour")
    #expect(!frame4.hasActiveAnimations,
            "a settled colour must not hold the display link awake — M4's own idle criterion")
}

/// **Brief test 2.** The same change with NO transaction snaps: the first frame
/// after the change reads the new token's resolved colour exactly, and stays
/// there rather than having quietly started something a later frame advances.
///
/// The asymmetry against test 1 is the evidence — this is what rules out
/// "everything animates always", which is exactly what step 5's mutation makes
/// the helper do.
@Test @MainActor func aBackgroundTokenChangedWithNoTransactionSnaps() {
    let table = StateTable()
    let theme = probeTheme()
    let id = eid("colour-box")

    var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    _ = animatedColor(.background, for: id, pass: &f1)

    let frame2 = colorFrame(table, timestamp: 0.001, theme: theme)
    var f2 = PaintPass(frame: frame2)
    let out2 = animatedColor(.accent, for: id, pass: &f2)
    expectColor(out2, h: 0.111111, s: 0.75, l: 0.60, tolerance: 1e-5,
                "no transaction in flight — the new token must apply immediately")
    #expect(!frame2.hasActiveAnimations,
            "a snap is not an animation and must not hold the display link awake")

    var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.5, theme: theme))
    let out3 = animatedColor(.accent, for: id, pass: &f3)
    expectColor(out3, h: 0.111111, s: 0.75, l: 0.60, tolerance: 1e-5,
                "and it must STAY there — no animation was quietly started")
}

/// **Brief test 3: hover and focus fade through the same path, and this is the
/// whole reason the helper animates the RESOLVED result of `Box.paint`'s
/// pointer/focus `??` chain rather than the three `Decoration` fields.**
///
/// Animating `background`/`hoverBackground`/`focusBackground` separately would
/// interpolate values that are not on screen; animating the chain's result
/// makes hover and focus fades fall out for free — the affordance CLAUDE.md
/// records a human as unable to read as a static token swap ("a judgement about
/// two dark greys"). Free is not the same as pinned, which is what this is for.
///
/// **Driven through a real `Box.paint` via `Frame.render`**, not through the
/// helper directly: the `??` chain lives in `Box.swift` and a test that
/// resolved the effective token itself would be blind to step 7's mutation.
@Test @MainActor func hoverAndFocusFadeThroughTheSameEffectiveColourPath() throws {
    let theme = probeTheme()

    func box() -> Box<EmptyGroup> {
        var b = Box(style: Style(), decoration: Decoration())
            .cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .background(.background)
            .hoverBackground(.accent)
            .focusBackground(.separator)
            .focusable()
            .onClick {}
        b.elementID = ElementID("chain")
        return b
    }
    let id = eid("chain")
    // Stage 6b (`LR-DG`, R-centre — predicted "fill", but the root declares
    // both axes): the 40x40 root is centred in the 100x100 frame at 30..70
    // (`CN-J`), so (50, 50) is inside it where (20, 20) was at the legacy
    // top-left root; every frame below passes `.proposal`.
    let inside = Point(x: Pixels(50), y: Pixels(50))

    func painted(_ frame: Frame) throws -> Hsla {
        var element = box()
        frame.render(&element)
        let rect = try #require(frame.scene.rects.first)
        return Hsla(h: rect.background.h, s: rect.background.s,
                    l: rect.background.l, a: rect.background.a)
    }

    // MARK: hover
    do {
        let table = StateTable()
        // Frame 1: not hovered — the baseline is the plain `background` token.
        let plain = try painted(colorFrame(table, timestamp: 0, theme: theme))
        expectColor(plain, h: 0.642857, s: 0.777778, l: 0.45, "unhovered: the plain token")

        // Frame 2: hovered, under a transaction. The EFFECTIVE token moved from
        // `background` to `accent` without any `Decoration` field changing at
        // all — which is the point.
        let frame2 = colorFrame(table, timestamp: 0, theme: theme, mousePosition: inside)
        var started: Hsla?
        try withAnimationThrowing(.linear(duration: 1)) { started = try painted(frame2) }
        expectColor(started, h: 0.642857, s: 0.777778, l: 0.45,
                    "the frame hover begins reads its own `from`")

        // Frame 3: still hovered, halfway.
        let mid = try painted(colorFrame(table, timestamp: 0.5, theme: theme, mousePosition: inside))
        expectColor(mid, h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                    l: midBackgroundToAccent.l, "hover fades through the effective colour")
    }

    // MARK: focus — a DIFFERENT token, so a helper that animated `background`
    // alone (step 7's mutation) cannot pass both arms by coincidence.
    do {
        let table = StateTable()
        let plain = try painted(colorFrame(table, timestamp: 0, theme: theme))
        expectColor(plain, h: 0.642857, s: 0.777778, l: 0.45, "unfocused: the plain token")

        let frame2 = colorFrame(table, timestamp: 0, theme: theme, focusedElement: id)
        var started: Hsla?
        try withAnimationThrowing(.linear(duration: 1)) { started = try painted(frame2) }
        expectColor(started, h: 0.642857, s: 0.777778, l: 0.45,
                    "the frame focus begins reads its own `from`")

        let mid = try painted(colorFrame(table, timestamp: 0.5, theme: theme, focusedElement: id))
        expectColor(mid, h: midBackgroundToSeparator.h, s: midBackgroundToSeparator.s,
                    l: midBackgroundToSeparator.l, "focus fades through the effective colour")
    }
}

/// **Brief test 4, and the one that pins the PHASE CHOICE.** A theme change
/// mid-flight is re-resolved, not frozen: the endpoints the animation is
/// travelling between move with the theme, so a theme swap during a fade
/// produces a continuous result rather than a jump (spec §4 rule 3, and its
/// row in spec §11's risk table, which names caching resolved colours as the
/// optimisation that would break it).
///
/// **Without this assertion, "colour lives in paint because only `PaintPass`
/// has a theme" is an argument nothing in the suite can see.** Step 6's
/// mutation — resolve once and store — is exactly the shape it rules out.
///
/// Both arms, because spec §4 says both ends re-resolve: swapping the token the
/// animation is heading TOWARD moves the midpoint, and so does swapping the one
/// it came FROM.
@Test @MainActor func aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints() {
    // MARK: the `to` end
    do {
        let table = StateTable()
        let id = eid("themed")
        var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: probeTheme()))
        _ = animatedColor(.background, for: id, pass: &f1)

        var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: probeTheme()))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.accent, for: id, pass: &f2)
        }

        // Halfway — but `accent` is a different colour now.
        //   background (0.10, 0.20, 0.80) -> accent' (0.30, 0.90, 0.50)
        //   midpoint (0.20, 0.55, 0.65): max=0.65 (b), min=0.20 (r), delta=0.45
        //       l = (0.65 + 0.20)/2 = 0.425
        //       s = 0.45 / (1 - |2(0.425) - 1|) = 0.45 / 0.85 = 0.529412
        //       h = (r - g)/delta + 4 = (0.20 - 0.55)/0.45 + 4 = 3.222222, /6 = 0.537037
        let swapped = probeTheme(accent: Rgba(r: 0.30, g: 0.90, b: 0.50))
        var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.5, theme: swapped))
        let out3 = animatedColor(.accent, for: id, pass: &f3)
        expectColor(out3, h: 0.537037, s: 0.529412, l: 0.425,
                    "the `to` endpoint must be re-resolved against THIS frame's theme")
        // And it is genuinely a different answer from the un-swapped one, so
        // the assertion above cannot be satisfied by a frozen endpoint that
        // happens to land nearby.
        #expect(abs((out3?.l ?? 0) - midBackgroundToAccent.l) > 0.05,
                "the swapped-theme midpoint must differ from the original one")
    }

    // MARK: the `from` end
    do {
        let table = StateTable()
        let id = eid("themed-from")
        var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: probeTheme()))
        _ = animatedColor(.background, for: id, pass: &f1)

        var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: probeTheme()))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.accent, for: id, pass: &f2)
        }

        //   background' (0.50, 0.10, 0.20) -> accent (0.90, 0.70, 0.30)
        //   midpoint (0.70, 0.40, 0.25): max=0.70 (r), min=0.25 (b), delta=0.45
        //       l = (0.70 + 0.25)/2 = 0.475
        //       s = 0.45 / (1 - |2(0.475) - 1|) = 0.45 / 0.95 = 0.473684
        //       h = ((g - b)/delta) mod 6 = (0.40 - 0.25)/0.45 = 0.333333, /6 = 0.055556
        let swapped = probeTheme(background: Rgba(r: 0.50, g: 0.10, b: 0.20))
        var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.5, theme: swapped))
        let out3 = animatedColor(.accent, for: id, pass: &f3)
        expectColor(out3, h: 0.055556, s: 0.473684, l: 0.475,
                    "the `from` endpoint must be re-resolved too — spec §4 says BOTH ends")
    }
}

/// **Brief test 5.** Two elements animate colour independently — different
/// targets, both mid-flight in the same frame, each reading its own midpoint.
/// A single shared `$anim-color` slot, or a slot keyed on anything but the
/// element's own id, collapses these onto one answer.
@Test @MainActor func twoElementsAnimateColourIndependently() {
    let table = StateTable()
    let theme = probeTheme()
    let a = eid("colour-a")
    let b = eid("colour-b")

    var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    _ = animatedColor(.background, for: a, pass: &f1)
    _ = animatedColor(.background, for: b, pass: &f1)

    var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    withAnimation(.linear(duration: 1)) {
        _ = animatedColor(.accent, for: a, pass: &f2)
        _ = animatedColor(.separator, for: b, pass: &f2)
    }

    var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.5, theme: theme))
    let outA = animatedColor(.accent, for: a, pass: &f3)
    let outB = animatedColor(.separator, for: b, pass: &f3)
    expectColor(outA, h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                l: midBackgroundToAccent.l, "element A heads for `accent`")
    expectColor(outB, h: midBackgroundToSeparator.h, s: midBackgroundToSeparator.s,
                l: midBackgroundToSeparator.l, "element B heads for `separator`")
}

/// `withAnimation` takes a non-throwing body, and two arms of the hover/focus
/// test need to `try` inside one. A local rethrowing wrapper over the same
/// save-and-restore, rather than widening the production signature for a test.
@MainActor private func withAnimationThrowing(_ animation: Animation,
                                              _ body: () throws -> Void) rethrows {
    let previous = Animation.pendingTransaction
    Animation.pendingTransaction = animation
    defer { Animation.pendingTransaction = previous }
    try body()
}

/// **An overshooting spring must not hand `fill` a colour outside the HSLA
/// unit range** — the pin for `lerpComponents`' clamp, added because dropping
/// the clamp reddened **nothing** in the 848-test suite and a green mutation is
/// a coverage gap or a broken instrument, never a pass.
///
/// The mechanism, measured rather than predicted. `probeTheme`'s `background →
/// accent` moves red from `0.10` to `0.90`, and a `bounce: 0.6` spring
/// overshoots (`aBouncySpringOvershootsItsTarget` pins that it does), so red
/// genuinely leaves `[0, 1]`. `Rgba.toHsla` then divides by `1 - |2l - 1|`
/// against an out-of-range `l`, and returns a **saturation above 1** — a value
/// that is not a colour, handed straight to `Frame.fill` and into the shader.
///
/// Sampled across the whole flight rather than at one guessed peak: the exact
/// frame the overshoot maxes out is a property of the spring's parameters, and
/// pinning it would be taxonomy shape 8 — an assertion on which frame happened
/// to be chosen rather than on the invariant.
@Test @MainActor func anOvershootingColourSpringStaysInsideTheHslaUnitRange() {
    let table = StateTable()
    let theme = probeTheme()
    let id = eid("bouncy")

    var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    _ = animatedColor(.background, for: id, pass: &f1)

    var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
    withAnimation(.spring(duration: 0.5, bounce: 0.6)) {
        _ = animatedColor(.accent, for: id, pass: &f2)
    }

    // **`slack` sits between two measured numbers, and this comment says which
    // — it claimed "one ULP of `Float`" until fix round 1 measured that too and
    // found 8,389 of them.** `Float(1.0).ulp` is `1.1920929e-07`, so
    // `1e-3 / ulp == 8388.6`; the honest description is not a unit but a
    // placement. `Rgba.toHsla` divides Floats, so a legitimately
    // fully-saturated colour comes back as `s == 1.0000001` — exactly ONE ulp
    // above 1, and the first draft of this test asserted `<= 1` and reddened 14
    // times WITH the clamp in place. The failure being guarded against peaks at
    // `s == 1.2846`, measured in an isolated worktree with the clamp removed.
    // `1e-3` is ~8,000x above the false positive and ~285x below the true one,
    // which is the margin that matters and the reason the value needs no
    // re-tuning even though its stated justification was wrong. (The guessed
    // `1.1481` this line once carried was likewise replaced by the measured
    // `1.2846` — same defect, second occurrence, both now corrected at the
    // line rather than only in a report.)
    let slack: Float = 1e-3
    // **The vacuity guard is `s`, not `l`.** The first version read `l > 0.58`
    // against a target `l` of `0.60`, so a spring that merely ARRIVED without
    // overshooting at all would have satisfied it — and 173 of 240 samples do,
    // at `bounce: 0.0`, measured.
    //
    // **Raising it to `l > 0.60` — the fix round 1 review's own suggestion —
    // would have worked as a vacuity guard while still meaning the wrong
    // thing, and this comment said "`l` cannot serve" until fix round 2
    // measured the difference.** Instrumenting the real fixture over its 240
    // samples: `l > 0.60` fires on **102/240** at `bounce: 0.6` and **0/240**
    // at `bounce: 0.0`, so it *would* have discriminated an overshooting
    // fixture from a flat one. What it would not do is mean what its failure
    // message says. `l` is not a readout of clamping and its relation to
    // overshoot inverts: red clamps at `1.0` while blue keeps falling, so
    // `l == (max + min)/2` rises only until red saturates (peak **0.6185**)
    // and then falls — so of the **42** samples where the clamp actually
    // fires, **26 have `l <= 0.60`** (minimum 0.5866). In the regime this test
    // exists to cover, an `l > 0.60` guard is mostly false. The
    // recommendation was insufficient, not wrong, and saying otherwise was
    // this branch's shape-14 "confident cannot" in the paragraph correcting
    // someone else's.
    //
    // Saturation IS a readout: for `max + min >= 1`,
    // `s == (max - min) / (2 - max - min)`, which is identically `1` exactly
    // when `max == 1` — that is, exactly when the clamp fired — while the
    // resting target `(0.90, 0.70, 0.30)` sits at `s == 0.75` and the whole
    // `bounce: 0.0` flight peaks at `0.7755`.
    var sawTheClampFire = false
    for step in 1...240 {
        let t = Double(step) / 240.0   // two seconds at 120 Hz
        var pass = PaintPass(frame: colorFrame(table, timestamp: t, theme: theme))
        guard let out = animatedColor(.accent, for: id, pass: &pass) else {
            Issue.record("the helper must keep returning a colour while the spring runs")
            return
        }
        #expect(out.s >= -slack && out.s <= 1 + slack,
                "saturation left the unit range at t = \(t): \(out.s)")
        #expect(out.l >= -slack && out.l <= 1 + slack,
                "lightness left the unit range at t = \(t): \(out.l)")
        #expect(out.a >= -slack && out.a <= 1 + slack,
                "alpha left the unit range at t = \(t): \(out.a)")
        // The fixture must actually reach the regime it exists to test, or
        // every assertion above is vacuous (taxonomy shape 15).
        if out.s >= 1 - slack { sawTheClampFire = true }
    }
    #expect(sawTheClampFire, """
            saturation never reached 1, so no component was ever clamped and the \
            assertions above measured nothing — the fixture stopped overshooting
            """)
}

// MARK: - Task 4b fix round 1: the interruption branch, which reddened 0 of 849

/// **Interrupting a running colour fade re-targets from where the colour IS,
/// with the momentum it HAS — and none of that was pinned until this test.**
///
/// Review finding I-1, measured rather than argued: replacing
/// `from: .fixed(current.value)` with `from: running.from` and
/// `velocity: current.velocity` with `.zero` in `AnimatedColor.swift` reddened
/// **0 of 849**. So `ColorEnd.fixed`, `RgbaVelocity`'s entire non-`.zero` path
/// and the sibling no-transaction snap were all declared-but-unverified — the
/// inert table's own shape, inside the file that argues hardest against it.
///
/// Three arms, because the branch has three separable behaviours and a single
/// fixture would let one of them coast:
///
/// - **A** interrupts with a DURATION curve. `Animation.value(at:…)` ignores
///   `initialVelocity` for a duration curve by design, so this arm is blind to
///   the velocity half and pins the `from` half alone.
/// - **B** interrupts with a SPRING, which is the only model that reads
///   `initialVelocity` at all — so it is the only shape that can see
///   `velocity: .zero`. It requires its two candidate answers to DISAGREE
///   before believing the one it asserts (practices doc, shape 15).
/// - **C** changes the declared token mid-flight with NO transaction, which
///   must snap and must stop asking for frames.
///
/// Every expected value is hand-derived from `probeTheme`'s endpoints, with the
/// arithmetic in the comments — not read back out of the helper.
@Test @MainActor func interruptingAColourFadeReTargetsFromItsCurrentValueAndVelocity() throws {
    let theme = probeTheme()

    /// Frames 1-2 of every arm: park a `background → accent` `linear(1)` fade
    /// starting at t = 0. At t = 0.25 it is a quarter of the way along, so
    /// (hand-computed, per component):
    ///     r = 0.10 + 0.25(0.90 - 0.10) = 0.30
    ///     g = 0.20 + 0.25(0.70 - 0.20) = 0.325
    ///     b = 0.80 + 0.25(0.30 - 0.80) = 0.675
    /// and a linear curve's velocity is `(to - from) / seconds` exactly, so
    ///     v = (0.80, 0.50, -0.50) per second, alpha 0 (both ends opaque).
    func parkedFade(_ table: StateTable, _ id: GlobalElementID) {
        var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
        _ = animatedColor(.background, for: id, pass: &f1)
        var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.accent, for: id, pass: &f2)
        }
    }
    let interruptPoint = Rgba(r: 0.30, g: 0.325, b: 0.675)
    let carriedVelocity = RgbaVelocity(r: 0.80, g: 0.50, b: -0.50, a: 0)

    // MARK: A — the `from` half, under a duration curve
    do {
        let table = StateTable()
        let id = eid("interrupt-linear")
        parkedFade(table, id)

        // t = 0.25: re-target at `separator` under a FRESH transaction. The
        // frame that interrupts must read the CURRENT position — not the old
        // `from`, not the new target.
        //   (0.30, 0.325, 0.675): max = b = 0.675, min = r = 0.30, delta = 0.375
        //     l = (0.675 + 0.30)/2 = 0.4875
        //     s = 0.375 / (1 - |2(0.4875) - 1|) = 0.375 / 0.975 = 0.384615
        //     h = (r - g)/delta + 4 = (0.30 - 0.325)/0.375 + 4 = 3.933333, /6 = 0.655556
        var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.25, theme: theme))
        var out3: Hsla?
        withAnimation(.linear(duration: 1)) {
            out3 = animatedColor(.separator, for: id, pass: &f3)
        }
        expectColor(out3, h: 0.655556, s: 0.384615, l: 0.4875,
                    "the interrupting frame reads the colour's CURRENT position")

        // t = 0.75 — half a second into the new linear(1), so halfway from the
        // interrupt point to `separator`:
        //   (0.45, 0.2125, 0.7875): max = b, min = g, delta = 0.575
        //     l = (0.7875 + 0.2125)/2 = 0.50
        //     s = 0.575 / (1 - 0) = 0.575
        //     h = (0.45 - 0.2125)/0.575 + 4 = 4.413043, /6 = 0.735507
        // Re-targeting from `running.from` instead would give the plain
        // `background → separator` midpoint (0.714286, 0.70, 0.50) — which is
        // `midBackgroundToSeparator`, and differs on h and s.
        var f4 = PaintPass(frame: colorFrame(table, timestamp: 0.75, theme: theme))
        let out4 = animatedColor(.separator, for: id, pass: &f4)
        expectColor(out4, h: 0.735507, s: 0.575, l: 0.50,
                    "the re-targeted fade runs from the interrupt point, not from the old `from`")
        // `try #require`, not `out4?.s ?? 0`: the `??` made this sanity check
        // PASS on a nil (|0 - 0.70| > 0.1), and the disagreement guard is the
        // one assertion in the arm that must never pass vacuously.
        let s4 = try #require(out4?.s, "the helper must return a colour mid-flight")
        #expect(abs(s4 - midBackgroundToSeparator.s) > 0.1, """
                sanity: the re-targeted answer must differ from the un-interrupted \
                background -> separator midpoint, or this arm cannot tell them apart
                """)
    }

    // MARK: B — the velocity half, under a spring
    do {
        let table = StateTable()
        let id = eid("interrupt-spring")
        parkedFade(table, id)

        let spring = Animation.spring(duration: 0.5, bounce: 0)
        var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.25, theme: theme))
        withAnimation(spring) {
            _ = animatedColor(.separator, for: id, pass: &f3)
        }

        // The oracle is `Animation.value(at:from:to:initialVelocity:)` — Task 1
        // code, pinned by its own tests, and NOT the code under test here. What
        // is under test is which `from` and which `initialVelocity`
        // `AnimatedColor.swift` hands it, and those arrive as the hand-derived
        // literals above rather than from the helper.
        let target = probeSeparatorRGB
        func projected(_ v: RgbaVelocity) -> Hsla {
            func c(_ from: Float, _ to: Float, _ v0: Double) -> Float {
                Float(min(max(spring.value(at: 0.05, from: Double(from), to: Double(to),
                                           initialVelocity: v0).value, 0), 1))
            }
            return Rgba(r: c(interruptPoint.r, target.r, v.r),
                        g: c(interruptPoint.g, target.g, v.g),
                        b: c(interruptPoint.b, target.b, v.b),
                        a: c(interruptPoint.a, target.a, v.a)).toHsla()
        }
        let withMomentum = projected(carriedVelocity)
        let fromRest = projected(.zero)

        // **Require the two candidates to DISAGREE before believing the one
        // asserted below** (practices doc, shape 15). A spring interrupted at a
        // point where the carried velocity happened not to matter would make
        // the assertion that follows green under both implementations.
        #expect(abs(withMomentum.l - fromRest.l) > 2e-3 || abs(withMomentum.s - fromRest.s) > 2e-3
                || abs(withMomentum.h - fromRest.h) > 2e-3, """
                the carried velocity makes no difference at this sample point \
                (momentum \(withMomentum) vs rest \(fromRest)), so this arm cannot see \
                `velocity: .zero` at all
                """)

        var f4 = PaintPass(frame: colorFrame(table, timestamp: 0.30, theme: theme))
        let out4 = animatedColor(.separator, for: id, pass: &f4)
        expectColor(out4, h: withMomentum.h, s: withMomentum.s, l: withMomentum.l,
                    "the re-targeted spring must carry the momentum the fade had")
    }

    // MARK: C — a mid-flight token change with NO transaction snaps
    do {
        let table = StateTable()
        let id = eid("interrupt-none")
        parkedFade(table, id)

        // separator (0.60, 0.10, 0.90): max = b, min = g, delta = 0.80
        //   l = 0.50, s = 0.80 / (1 - 0) = 0.80
        //   h = (0.60 - 0.10)/0.80 + 4 = 4.625, /6 = 0.770833
        let frame3 = colorFrame(table, timestamp: 0.25, theme: theme)
        var f3 = PaintPass(frame: frame3)
        let out3 = animatedColor(.separator, for: id, pass: &f3)
        expectColor(out3, h: 0.770833, s: 0.80, l: 0.50, tolerance: 1e-5,
                    "a token change with no transaction snaps even mid-flight")
        #expect(!frame3.hasActiveAnimations,
                "and the abandoned animation must stop holding the display link awake")

        let frame4 = colorFrame(table, timestamp: 0.5, theme: theme)
        var f4 = PaintPass(frame: frame4)
        let out4 = animatedColor(.separator, for: id, pass: &f4)
        expectColor(out4, h: 0.770833, s: 0.80, l: 0.50, tolerance: 1e-5,
                    "and it STAYS there — the old animation was dropped, not paused")
        #expect(!frame4.hasActiveAnimations)
    }
}

/// **The settled-path comparison is on the TOKEN, never on the resolved
/// colour** — review finding M-5, and the half of the storage argument that was
/// not pinned.
///
/// Storing the resolved `Hsla` beside the token and comparing against that
/// instead reddened **0 of 849**. The reviewer proved the mutant is not
/// equivalent, and this is that proof turned into an assertion: a theme swap
/// changes what a settled element's unchanged token resolves to, so a
/// colour-keyed comparison sees "the value changed" where nothing was declared
/// differently at all — and with any transaction in flight anywhere in the
/// frame, it starts a fade from the old theme's colour and holds the display
/// link awake for that animation's whole duration. Right pixels eventually,
/// wasted frames throughout, and no diagnostic.
///
/// The transaction is what makes this observable: without one, both
/// implementations snap and the two are indistinguishable.
@Test @MainActor func aThemeSwapAloneNeverStartsAFadeOnASettledElement() {
    let table = StateTable()
    let id = eid("settled-through-a-theme-swap")

    var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: probeTheme()))
    _ = animatedColor(.background, for: id, pass: &f1)

    // Same token, different theme, and a transaction in flight — the exact
    // frame a colour-keyed baseline mistakes for a declaration change.
    //   background' (0.50, 0.10, 0.20): max = r, min = g, delta = 0.40
    //     l = (0.50 + 0.10)/2 = 0.30
    //     s = 0.40 / (1 - |2(0.30) - 1|) = 0.40 / 0.60 = 0.666667
    //     h = ((g - b)/delta) mod 6 = (0.10 - 0.20)/0.40 = -0.25, /6 = -0.041667, +1 = 0.958333
    let swapped = probeTheme(background: Rgba(r: 0.50, g: 0.10, b: 0.20))
    let frame2 = colorFrame(table, timestamp: 0, theme: swapped)
    var f2 = PaintPass(frame: frame2)
    var out2: Hsla?
    withAnimation(.linear(duration: 1)) {
        out2 = animatedColor(.background, for: id, pass: &f2)
    }
    expectColor(out2, h: 0.958333, s: 0.666667, l: 0.30, tolerance: 1e-5,
                "a theme swap on an unchanged token must apply immediately, not fade")
    #expect(!frame2.hasActiveAnimations, """
            nothing was declared differently, so no animation may start and the display \
            link must not be held awake
            """)

    // And nothing is left running to advance on a later frame.
    let frame3 = colorFrame(table, timestamp: 0.5, theme: swapped)
    var f3 = PaintPass(frame: frame3)
    let out3 = animatedColor(.background, for: id, pass: &f3)
    expectColor(out3, h: 0.958333, s: 0.666667, l: 0.30, tolerance: 1e-5,
                "and it stays there")
    #expect(!frame3.hasActiveAnimations)
}

/// **After an interruption the `from` end stops re-resolving, and the `to` end
/// does not** — the narrowing `ColorAnimation` documents, made observable.
///
/// Fix round 1 review, concern 1, and it was more than a coverage gap:
/// `ColorAnimation`'s doc claimed both halves of the narrowing were pinned by
/// `aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints`, and **both of that
/// test's arms drive an UN-interrupted fade** — so they pin the token/token case
/// and say nothing about the narrowed one. The sentence claimed a pin it did not
/// have. This is that pin.
///
/// **The interrupted subject and the un-interrupted control take the SAME theme
/// swap in the same test**, so the only difference between them is whether an
/// interruption happened. Without the control, "the answer did not move" is
/// equally satisfied by a helper that never re-resolves anything at all.
@Test @MainActor func anInterruptedFadeFreezesItsFromEndAgainstALaterThemeSwap() {
    let theme = probeTheme()

    /// Park `background → accent` `linear(1)` at t = 0 and interrupt it at
    /// t = 0.25 toward `separator` under a fresh transaction, exactly as
    /// `interruptingAColourFadeReTargetsFromItsCurrentValueAndVelocity`'s arm A
    /// does. `from` is then `.fixed((0.30, 0.325, 0.675))` — a colour, not a
    /// token — and `toToken` is `.separator`.
    func interruptedFade(_ table: StateTable, _ id: GlobalElementID) {
        var f1 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
        _ = animatedColor(.background, for: id, pass: &f1)
        var f2 = PaintPass(frame: colorFrame(table, timestamp: 0, theme: theme))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.accent, for: id, pass: &f2)
        }
        var f3 = PaintPass(frame: colorFrame(table, timestamp: 0.25, theme: theme))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.separator, for: id, pass: &f3)
        }
    }

    // MARK: the `from` end is frozen — and the control proves the swap bites
    do {
        // `background` — the token the interrupted fade ORIGINALLY came from —
        // now resolves to something else entirely.
        let swapped = probeTheme(background: Rgba(r: 0.50, g: 0.30, b: 0.10))

        let subject = StateTable()
        interruptedFade(subject, eid("interrupted"))
        var f4 = PaintPass(frame: colorFrame(subject, timestamp: 0.75, theme: swapped))
        let out = animatedColor(.separator, for: eid("interrupted"), pass: &f4)
        // Unchanged from arm A's un-swapped answer: `from` is a colour now, so
        // `theme[.background]` is never consulted again on this animation.
        expectColor(out, h: 0.735507, s: 0.575, l: 0.50, """
                    an interrupted fade's `from` end is a fixed colour and must not \
                    move when the token it once came from is re-themed
                    """)

        // CONTROL: the same swap, the same two endpoints, the same elapsed time
        // — but never interrupted, so `from` is still `.token(.background)` and
        // MUST move.
        //   background' (0.50, 0.30, 0.10) -> separator (0.60, 0.10, 0.90)
        //   midpoint (0.55, 0.20, 0.50): max = r, min = g, delta = 0.35
        //     l = (0.55 + 0.20)/2 = 0.375
        //     s = 0.35 / (1 - |2(0.375) - 1|) = 0.35 / 0.75 = 0.466667
        //     h = ((g - b)/delta) mod 6 = (0.20 - 0.50)/0.35 = -0.857143,
        //         /6 = -0.142857, +1 = 0.857143
        // Un-swapped this would be `midBackgroundToSeparator` (0.714286, 0.70,
        // 0.50), so the swap genuinely bites on a fade that still holds tokens.
        let control = StateTable()
        let cid = eid("never-interrupted")
        var c1 = PaintPass(frame: colorFrame(control, timestamp: 0.25, theme: theme))
        _ = animatedColor(.background, for: cid, pass: &c1)
        var c2 = PaintPass(frame: colorFrame(control, timestamp: 0.25, theme: theme))
        withAnimation(.linear(duration: 1)) {
            _ = animatedColor(.separator, for: cid, pass: &c2)
        }
        var c3 = PaintPass(frame: colorFrame(control, timestamp: 0.75, theme: swapped))
        let controlOut = animatedColor(.separator, for: cid, pass: &c3)
        expectColor(controlOut, h: 0.857143, s: 0.466667, l: 0.375, """
                    CONTROL: an un-interrupted fade still holds `from` as a token, so the \
                    identical swap MUST move it — without this the subject's \
                    "did not move" is satisfied by a helper that re-resolves nothing
                    """)
    }

    // MARK: the `to` end still re-resolves, interruption or not
    do {
        //   from (0.30, 0.325, 0.675) -> separator' (0.30, 0.90, 0.50)
        //   midpoint (0.30, 0.6125, 0.5875): max = g, min = r, delta = 0.3125
        //     l = (0.6125 + 0.30)/2 = 0.45625
        //     s = 0.3125 / (1 - |2(0.45625) - 1|) = 0.3125 / 0.9125 = 0.342466
        //     h = (b - r)/delta + 2 = (0.5875 - 0.30)/0.3125 + 2 = 2.92, /6 = 0.486667
        let swapped = probeTheme(separator: Rgba(r: 0.30, g: 0.90, b: 0.50))

        let table = StateTable()
        interruptedFade(table, eid("interrupted-to"))
        var f4 = PaintPass(frame: colorFrame(table, timestamp: 0.75, theme: swapped))
        let out = animatedColor(.separator, for: eid("interrupted-to"), pass: &f4)
        expectColor(out, h: 0.486667, s: 0.342466, l: 0.45625, """
                    the `to` end re-resolves every frame even on a RE-TARGETED animation — \
                    freezing it there would be invisible to \
                    aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints, which never interrupts
                    """)
    }
}

// MARK: - Task 5: the transaction hand-off, `hasActiveAnimations`, the drive loop
//
// Everything above this line drives the two helpers DIRECTLY, from inside a
// `withAnimation` body. That configuration is correct for testing the helpers
// and it is one production cannot reach (ruling V): `withAnimation` restores
// its transaction in a `defer`, and the frame build that reads it runs later,
// from the display link, entirely outside that body. Every window test below
// therefore drives a REAL `Window` — `withAnimation` RETURNS first, and the
// frame is built by a separate `simulateTick`, which is the whole subject of
// this task.

/// The application-side model these tests animate. `@Observable`, so the write
/// inside `withAnimation` reaches the window through the production dirty path
/// and nothing here calls `setNeedsRedraw()` by hand.
@Observable
final class AnimationDriveModel {
    var width: Float = 100
    var show: Bool = true
    var useAccent: Bool = false
}

/// The width of the one 40pt-tall rect the fixtures below paint, in device
/// pixels — the fake surface's scale factor is 1, so this is also points.
///
/// Read out of `Window.lastScene` rather than by calling `animated(...)`: the
/// question this task answers is whether a value reaches the SCENE through a
/// real frame build, and a test that called the helper itself would be blind to
/// a hand-off that never happens.
@MainActor private func subjectWidth(_ window: Window) -> Float? {
    window.lastScene.rects.first { $0.bounds.size.height == 40 }?.bounds.size.width
}

@MainActor private func makeDriveWindow(_ model: AnimationDriveModel)
    throws -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: 300, startsDisplayLink: true) {
        Column {
            if model.show {
                // The background token is model-driven so a fixture can put
                // the window mid-FADE — a state in which it is clean and still
                // drawing every frame. Every assertion below reads the
                // subject's WIDTH, so the token itself is never asserted.
                Box().background(model.useAccent ? .accent : .background)
                    .cssWidth(Pixels(model.width)).cssHeight(Pixels(40))
                    .id("subject")
            }
        }
    }
}

/// **The test this task exists for.** A `withAnimation` whose body mutates
/// state and nothing else, followed by a separately driven frame build, must
/// animate.
///
/// The assertion is a MID-FLIGHT interpolated width — 150 of a 100 → 200 linear
/// second at exactly its halfway point — not "an animation exists". Only a
/// running animation produces 150; a dead hand-off produces 200 on the first
/// frame after the write.
@MainActor @Test func aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeDriveWindow(model)

    platformWindow.simulateTick(timestamp: 100)
    try #require(subjectWidth(window) == 100, "set up: the resting baseline is 100")

    // The body mutates state ONLY. No `animated(...)`, no `Frame.render` and no
    // window call is lexically inside it.
    withAnimation(.linear(duration: 1)) { model.width = 200 }
    #expect(Animation.pendingTransaction == nil, """
            the LEXICAL transaction is already gone by the time the build below runs — \
            which is exactly why a lexically-scoped transaction cannot reach production
            """)

    // The frame that starts the transition reads its own `from`.
    platformWindow.simulateTick(timestamp: 100)
    #expect(subjectWidth(window) == 100, """
            the frame that consumes the transaction starts at elapsed 0, so it reads `from`; \
            got \(String(describing: subjectWidth(window)))
            """)

    // MID-FLIGHT. This number exists only while an animation is running.
    platformWindow.simulateTick(timestamp: 100.5)
    #expect(subjectWidth(window) == 150, """
            halfway through linear(duration: 1) from 100 to 200 is 150; 200 means the change \
            snapped and the hand-off is dead; got \(String(describing: subjectWidth(window)))
            """)

    // And it lands exactly on the target at the duration.
    platformWindow.simulateTick(timestamp: 101)
    #expect(subjectWidth(window) == 200, """
            a duration curve terminates exactly; got \(String(describing: subjectWidth(window)))
            """)
}

/// Spec §9 item 4, and M4 spec 1's ruling `RX-O` finally discharged: the
/// display link stays running while an animation is live and pauses on the
/// frame AFTER the last one ends.
///
/// The two halves are asserted separately because they fail under different
/// mistakes — a flag that is never raised stops the first, a flag that is never
/// cleared stops the second — and the mutation table reddens them separately.
///
/// Nothing writes to the model between the first animating tick and the last:
/// every frame after that one is drawn on the strength of `hasActiveAnimations`
/// alone, because `needsRedraw` is false for all of them.
@MainActor @Test func theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeDriveWindow(model)

    platformWindow.simulateTick(timestamp: 100)
    // Control: with nothing animating, an idle window pauses. Without it, "it
    // paused at the end" is equally satisfied by a window that pauses always.
    platformWindow.simulateTick(timestamp: 100.1)
    try #require(platformWindow.pauseCalls.last == true,
                 "set up: a clean window with no animation must pause")
    #expect(!window.hasActiveAnimations, "set up: nothing is animating yet")

    withAnimation(.linear(duration: 1)) { model.width = 200 }

    platformWindow.simulateTick(timestamp: 100.2)      // starts the animation
    #expect(window.hasActiveAnimations,
            "a frame that left a field mid-interpolation must report an active animation")
    try #require(!window.needsRedraw, """
                 set up: the window is CLEAN from here on — every frame below is drawn on the \
                 strength of the animation alone
                 """)

    let drawnBeforeIdling = window.framesDrawn
    let pausesBefore = platformWindow.pauseCalls.filter { $0 }.count

    platformWindow.simulateTick(timestamp: 100.6)
    #expect(window.framesDrawn == drawnBeforeIdling + 1,
            "a clean window with a live animation must still draw")
    #expect(window.hasActiveAnimations, "still mid-flight")
    #expect(subjectWidth(window) == 140, """
            0.4s into a 1s linear 100 -> 200 is 140; \
            got \(String(describing: subjectWidth(window)))
            """)

    platformWindow.simulateTick(timestamp: 101.2)      // exactly at the duration
    #expect(subjectWidth(window) == 200)
    #expect(!window.hasActiveAnimations, """
            termination is exact for a duration curve: the frame that lands on the target \
            reports NO active animation, which is what lets the link pause on the next one
            """)
    #expect(platformWindow.pauseCalls.filter { $0 }.count == pausesBefore,
            "the link must not have paused at any point while the animation was live")

    platformWindow.simulateTick(timestamp: 101.3)
    #expect(platformWindow.pauseCalls.last == true,
            "the link pauses on the frame AFTER the last animation ends")
    #expect(window.framesDrawn == drawnBeforeIdling + 2,
            "and that pausing tick draws nothing")
}

/// The negative arm, in the same test as the positive one so the two must
/// DISAGREE before either is believed (taxonomy shape 15). A property that is
/// always `false` passes the first half; one that is always `true` passes the
/// third; only a real one passes all four.
@MainActor @Test func aFrameWithNoAnimationsReportsNoActiveAnimationsAndOneMidFlightReportsSome() {
    let table = StateTable()
    let id = eid("box")
    var style = Style()
    style.flexGrow = 0

    let f1 = animFrame(table, timestamp: 0)
    var pass1 = LayoutPass(frame: f1)
    _ = animated(style, Decoration(), for: id, pass: &pass1)
    #expect(!f1.hasActiveAnimations, "a first sighting establishes a baseline and animates nothing")

    // A second static frame: nothing differs, nothing is in flight.
    let f2 = animFrame(table, timestamp: 0.1)
    var pass2 = LayoutPass(frame: f2)
    _ = animated(style, Decoration(), for: id, pass: &pass2)
    #expect(!f2.hasActiveAnimations, "an unchanged element animates nothing")

    // Now one that genuinely differs under a transaction.
    style.flexGrow = 100
    let f3 = animFrame(table, timestamp: 0.1)
    var pass3 = LayoutPass(frame: f3)
    withAnimation(.linear(duration: 1)) {
        _ = animated(style, Decoration(), for: id, pass: &pass3)
    }
    #expect(f3.hasActiveAnimations, "a field left mid-interpolation IS an active animation")

    // …and false again once it settles, which is what makes the flag a
    // per-frame answer rather than a latch.
    let f4 = animFrame(table, timestamp: 1.1)
    var pass4 = LayoutPass(frame: f4)
    _ = animated(style, Decoration(), for: id, pass: &pass4)
    #expect(!f4.hasActiveAnimations, "the frame the animation lands on reports no active animation")
}

/// Spec §3's non-re-entrancy: the pending animation is consumed by the next
/// build and cleared. A second build with no new transaction must not start a
/// second animation.
///
/// The discriminator is a SNAP to an exact declared value. A re-target from the
/// mid-flight position would read something strictly between 125 and 300 — and
/// a transaction that leaked into the second build is exactly what produces
/// that.
@MainActor @Test func aParkedTransactionIsConsumedByExactlyOneBuild() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeDriveWindow(model)

    platformWindow.simulateTick(timestamp: 100)
    try #require(subjectWidth(window) == 100, "set up")

    withAnimation(.linear(duration: 1)) { model.width = 200 }
    platformWindow.simulateTick(timestamp: 100)        // consumes the transaction
    platformWindow.simulateTick(timestamp: 100.25)
    try #require(subjectWidth(window) == 125,
                 "set up: the animation this test exists NOT to see repeated is genuinely running")

    // A second declaration change, with no `withAnimation` of its own.
    model.width = 300
    platformWindow.simulateTick(timestamp: 100.5)
    #expect(subjectWidth(window) == 300, """
            the transaction was consumed by ONE build; a change made without a fresh \
            `withAnimation` snaps; got \(String(describing: subjectWidth(window)))
            """)
    #expect(!window.hasActiveAnimations,
            "and nothing is left interpolating, so the link is free to idle")
}

/// Spec §6's free consequence of `StateTable` tombstones: an animating element
/// that vanishes and returns within the retention window RESUMES on its
/// original trajectory rather than restarting.
///
/// 175 at t = 100.75 is the resumption. A restart from the value it vanished at
/// would read 125 there (a fresh 125 → 200 second, at elapsed 0), and a restart
/// from the declared baseline would read 100.
@MainActor @Test func anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeDriveWindow(model)

    platformWindow.simulateTick(timestamp: 100)
    try #require(subjectWidth(window) == 100, "set up")

    withAnimation(.linear(duration: 1)) { model.width = 200 }
    platformWindow.simulateTick(timestamp: 100)
    platformWindow.simulateTick(timestamp: 100.25)
    try #require(subjectWidth(window) == 125, "set up: mid-flight before it vanishes")

    model.show = false
    platformWindow.simulateTick(timestamp: 100.5)
    try #require(subjectWidth(window) == nil, "set up: the element is genuinely gone")

    model.show = true
    platformWindow.simulateTick(timestamp: 100.75)
    #expect(subjectWidth(window) == 175, """
            resumed on the ORIGINAL trajectory (elapsed 0.75 of the animation started at \
            t = 100), not restarted; got \(String(describing: subjectWidth(window)))
            """)
}

/// The colour analogue of the registering-site guard
/// (`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`), and spec
/// exit criterion 8's shape applied to the paint phase: **one case per site
/// that fills a background**, so a fourth site added later fails a test rather
/// than silently snapping.
///
/// The three sites are `grep -rn "theme\[" Sources/MetalUI/` less the helper's
/// own internals: `Box.paint` (Task 4b), `Stack.paint` and `Text.paint` (Task
/// 5). Two more colour fills exist and are deliberately NOT here, named rather
/// than left for a reader to wonder about:
///
/// - `ScrollView.swift`'s scroll-indicator fill fades its own alpha on a clock
///   of its own and predates the `Animation` type; it declares no background.
/// - `Text.swift`'s glyph fill (`foregroundColor ?? .textPrimary`) is not in
///   spec §4's animatable list at all — animating text colour is spec §8's
///   named hole and stays one.
///
/// Each arm drives a REAL `paint` through `Frame.render` and reads the colour
/// back out of the emitted `MUIRect`, for
/// `hoverAndFocusFadeThroughTheSameEffectiveColourPath`'s reason: a test that
/// resolved the token itself would be blind to an un-wired call site.
@Test @MainActor func everyBackgroundPaintingSiteAnimatesItsColour() throws {
    let theme = probeTheme()

    /// Renders `element` into a fresh frame over `table` and returns the
    /// background colour of the first rect it emitted.
    func painted<E: Element>(_ table: StateTable, _ timestamp: Double,
                             _ element: @autoclosure () -> E) throws -> Hsla {
        let frame = colorFrame(table, timestamp: timestamp, theme: theme)
        var e = element()
        frame.render(&e)
        let rect = try #require(frame.scene.rects.first)
        return Hsla(h: rect.background.h, s: rect.background.s,
                    l: rect.background.l, a: rect.background.a)
    }

    /// The three-frame shape every arm runs: baseline on `.background`, a
    /// transaction-start frame on `.accent` that must read its own `from`, and
    /// a halfway frame that must read the hand-computed midpoint.
    func check<E: Element>(_ site: String,
                           _ make: @escaping @MainActor (ColorToken) -> E) throws {
        let table = StateTable()

        let baseline = try painted(table, 0, make(.background))
        expectColor(baseline, h: 0.642857, s: 0.777778, l: 0.45,
                    "\(site): the resting baseline is the declared token")

        var started: Hsla?
        try withAnimationThrowing(.linear(duration: 1)) {
            started = try painted(table, 0, make(.accent))
        }
        expectColor(started, h: 0.642857, s: 0.777778, l: 0.45,
                    "\(site): the frame that starts the transition reads its own `from`")

        let mid = try painted(table, 0.5, make(.accent))
        expectColor(mid, h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                    l: midBackgroundToAccent.l,
                    "\(site): this painting site does not animate its background colour")
    }

    try check("Box") { token in
        var b = Box().cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(token)
        b.elementID = ElementID("site")
        return b
    }
    try check("Stack") { token in
        var s = Stack { Box() }.cssWidth(Pixels(40)).cssHeight(Pixels(40)).background(token)
        s.elementID = ElementID("site")
        return s
    }
    try check("Text") { token in
        var t = Text("hi").background(token)
        t.elementID = ElementID("site")
        return t
    }
    // Ruling MC-I: a `.padding`/`.frame` chain is ONE `ModifiedElement` that
    // paints each layer's background in a loop, so it gets two arms over a
    // two-layer chain — the background on the INNER layer (the outermost
    // declares none, so the first rect is the inner layer's) and on the
    // outermost. Wiring only the outermost layer, the one `StyledElement`'s
    // accessors reach, passes the second arm and not the first.
    try check("ModifiedElement inner layer") { token in
        var m = Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .padding(Edges(all: .pixels(Pixels(4)))).background(token)
            .padding(Edges(all: .pixels(Pixels(8))))
        m.elementID = ElementID("site")
        return m
    }
    try check("ModifiedElement outermost layer") { token in
        var m = Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .padding(Edges(all: .pixels(Pixels(4))))
            .padding(Edges(all: .pixels(Pixels(8)))).background(token)
        m.elementID = ElementID("site")
        return m
    }
}

/// **The composition the whole idle criterion turns on, and the one no
/// helper-level test can see.** A colour fade lives in PAINT and reaches
/// `hasActiveAnimations` from there; an element whose `Style` never changes
/// raises nothing during layout at all. So a criterion computed from the layout
/// pass — or read before paint — is a fade that stops the instant input stops
/// arriving, with the first frame looking perfectly correct.
///
/// Measured before this test existed: silencing the paint helper's
/// `noteActiveAnimation()` reddened **2 issues, in
/// `aBackgroundTokenChangedUnderATransactionReadsAMidFlightColour` alone** —
/// a real pin on the flag, and nothing anywhere on the drive LOOP. That is
/// taxonomy shape 9: two shipped features (`AnimatedColor` × the display-link
/// guard) whose pair had no fixture, because each was added by the task that
/// added it.
///
/// The subject's width and height are literals, so `animated(_:_:for:pass:)`
/// leaves `inFlight` empty on every frame and the layout half is silent by
/// construction — which is what makes this test about the paint half rather
/// than about both.
@MainActor @Test func aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeFakeWindowOnDefaultDevice(size: 300,
                                                                    startsDisplayLink: true) {
        Box().cssWidth(Pixels(40)).cssHeight(Pixels(40))
            .background(model.useAccent ? .accent : .background)
            .id("subject")
    }
    // The same discrimination-built theme every colour assertion above uses, so
    // the expected midpoint is `midBackgroundToAccent` — hand-derived, with the
    // arithmetic at its declaration, rather than read off `Theme.light`.
    window.theme = probeTheme()

    func painted() throws -> Hsla {
        let rect = try #require(window.lastScene.rects.first)
        return Hsla(h: rect.background.h, s: rect.background.s,
                    l: rect.background.l, a: rect.background.a)
    }

    platformWindow.simulateTick(timestamp: 100)
    expectColor(try painted(), h: 0.642857, s: 0.777778, l: 0.45, "set up: the resting token")
    platformWindow.simulateTick(timestamp: 100.1)
    try #require(platformWindow.pauseCalls.last == true,
                 "set up: a clean window with nothing animating pauses")

    withAnimation(.linear(duration: 1)) { model.useAccent = true }

    platformWindow.simulateTick(timestamp: 100.2)
    expectColor(try painted(), h: 0.642857, s: 0.777778, l: 0.45,
                "the frame that starts the fade reads its own `from`")
    #expect(window.hasActiveAnimations,
            "a colour transition mid-flight is an active animation, and only PAINT knows it")
    try #require(!window.needsRedraw,
                 "set up: the window is clean from here on — nothing but the fade is left")

    let drawnBefore = window.framesDrawn
    platformWindow.simulateTick(timestamp: 100.7)
    #expect(window.framesDrawn == drawnBefore + 1,
            "a clean window with a live COLOUR fade must still draw")
    expectColor(try painted(), h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                l: midBackgroundToAccent.l, "halfway through the fade")

    platformWindow.simulateTick(timestamp: 101.2)
    expectColor(try painted(), h: 0.111111, s: 0.75, l: 0.60, "landed exactly on the target")
    #expect(!window.hasActiveAnimations, "settled")

    platformWindow.simulateTick(timestamp: 101.3)
    #expect(platformWindow.pauseCalls.last == true,
            "and the link pauses on the frame after the fade ends")
}

/// **Fix round 1, review finding I-1**, reproduced as the reviewer wrote it and
/// then closed.
///
/// A `withAnimation` whose body dirties nothing parks a transaction that no
/// frame ever consumes — `takeParkedTransaction()` runs only on a *drawn*
/// frame, and a clean window draws none. Before the fix it waited indefinitely
/// and then applied to whatever happened to differ on the next frame drawn for
/// any reason at all: measured at **400 simulated seconds**, an unrelated
/// `model.width = 200` with no `withAnimation` anywhere read a mid-flight
/// value instead of snapping.
///
/// The two arms must DISAGREE (taxonomy shape 15). A rule that never parks
/// passes the first arm and fails the second; the rule as shipped — park only
/// when `body` asked for a redraw — is the only thing that passes both.
@MainActor @Test func aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange() throws {
    // MARK: the subject — a body that changes nothing the window reads
    do {
        let model = AnimationDriveModel()
        let (window, platformWindow) = try makeDriveWindow(model)
        platformWindow.simulateTick(timestamp: 100)
        try #require(subjectWidth(window) == 100, "set up: the resting baseline")

        withAnimation(.linear(duration: 1)) { }
        platformWindow.simulateTick(timestamp: 100.1)
        try #require(platformWindow.pauseCalls.last == true,
                     "set up: nothing was dirtied, so no frame is drawn and nothing consumes")

        // 400 simulated seconds later, an unrelated change with no
        // `withAnimation` anywhere near it.
        model.width = 200
        platformWindow.simulateTick(timestamp: 500)
        #expect(subjectWidth(window) == 200, """
                a transaction nobody could consume must not animate an unrelated later \
                change; got \(String(describing: subjectWidth(window)))
                """)
        platformWindow.simulateTick(timestamp: 500.5)
        #expect(subjectWidth(window) == 200, "and it stays snapped on the frame after")
        #expect(!window.hasActiveAnimations, "nothing is interpolating, so the link may idle")
    }

    // MARK: the control — the IDENTICAL shape with a body that does dirty,
    // which must still animate. Without this arm, "never park anything at all"
    // passes the subject above.
    do {
        let model = AnimationDriveModel()
        let (window, platformWindow) = try makeDriveWindow(model)
        platformWindow.simulateTick(timestamp: 100)
        try #require(subjectWidth(window) == 100, "set up")

        withAnimation(.linear(duration: 1)) { model.width = 200 }
        platformWindow.simulateTick(timestamp: 100.1)
        platformWindow.simulateTick(timestamp: 100.6)
        #expect(subjectWidth(window) == 150, """
                CONTROL: a body that DID dirty must still park and still animate; \
                got \(String(describing: subjectWidth(window)))
                """)
    }

    // MARK: what the rollback restores — a no-op `withAnimation` must not
    // CLOBBER a transaction an earlier one legitimately parked.
    //
    // Added because rolling back to `nil` instead of to `previouslyParked`
    // reddened 0 of 860, and a green mutation is a coverage gap or a broken
    // instrument, never a pass. The mutant does behave differently, and this
    // is the difference: under it the first transaction is discarded by the
    // second call and the pending change snaps to 200 instead of reading 150.
    //
    // The second animation is deliberately a DIFFERENT duration, so 150 also
    // separates "the first one survived" from "the second one won": 0.5 s of
    // `linear(duration: 4)` over the same 100 -> 200 would read 112.5.
    do {
        let model = AnimationDriveModel()
        let (window, platformWindow) = try makeDriveWindow(model)
        platformWindow.simulateTick(timestamp: 100)
        try #require(subjectWidth(window) == 100, "set up")

        withAnimation(.linear(duration: 1)) { model.width = 200 }
        withAnimation(.linear(duration: 4)) { }
        platformWindow.simulateTick(timestamp: 100.1)
        platformWindow.simulateTick(timestamp: 100.6)
        #expect(subjectWidth(window) == 150, """
                the no-op `withAnimation` must leave the first transaction alone: \
                200 means it discarded it and the change snapped, 112.5 means the \
                no-op one won; got \(String(describing: subjectWidth(window)))
                """)
    }

    // MARK: the same hijack DURING a live animation — the arm that decided
    // against putting `hasActiveAnimations` in `Window.aFrameBuildIsPending`.
    //
    // A window mid-fade is CLEAN and still drawing every frame. With the
    // re-review's suggested predicate in full, the empty `withAnimation`
    // below parks `linear(4)` (measured), and the ordinary bare write after
    // it then animates instead of snapping — fix round 1's bug again,
    // bounded by the fade's lifetime rather than unbounded.
    do {
        let model = AnimationDriveModel()
        let (window, platformWindow) = try makeDriveWindow(model)
        platformWindow.simulateTick(timestamp: 100)
        try #require(subjectWidth(window) == 100, "set up")

        withAnimation(.linear(duration: 1)) { model.useAccent = true }
        platformWindow.simulateTick(timestamp: 100.1)   // the colour fade starts
        platformWindow.simulateTick(timestamp: 100.2)   // and is mid-flight here
        try #require(window.hasActiveAnimations, "set up: a fade is genuinely live")
        try #require(!window.needsRedraw, "set up: and the window is CLEAN while it runs")

        withAnimation(.linear(duration: 4)) { }         // empty body, mid-fade
        model.width = 200                               // ordinary write, no transaction
        platformWindow.simulateTick(timestamp: 100.3)
        #expect(subjectWidth(window) == 200, """
                an empty `withAnimation` during a live fade must park nothing, so this \
                bare write snaps; 100 means it parked and the write animated off a \
                transaction nobody asked for; got \(String(describing: subjectWidth(window)))
                """)
    }
}

/// **Fix round 2, re-review finding N-1**, reproduced as the re-reviewer
/// measured it and then closed.
///
/// Fix round 1 gated parking on `Window.redrawRequests` moving across the body,
/// on the premise that every dirty path reaches `setNeedsRedraw()` before the
/// body returns. **The premise is false for `@Observable`, and not because that
/// path is asynchronous.** `withObservationTracking`'s `onChange` is one-shot
/// and its session is re-armed only by the next *drawn* frame, so the second
/// and every later observable mutation between two frames fires no `onChange`
/// at all. Under the counter-only rule this test's `withAnimation` parked `nil`
/// and the width **snapped to 200** — a legitimate animation, written in
/// ordinary code, discarded with no diagnostic.
///
/// Nothing in the repo regressed, because `Sources/` has no `withAnimation`
/// caller; the defect was in the shipped public API, which is worse rather than
/// better. It was invisible to all 860 tests and to all four of fix round 1's
/// mutations because every existing fixture's animated write happens to be the
/// first of its interval.
///
/// **Two `try #require`s carry the fixture rather than decorate it**: the first
/// proves an interval's first observable write *does* move the counter, and the
/// second proves this one does *not*. Without the second, a future change that
/// re-armed the session every write would make this test pass while testing
/// nothing (taxonomy shape 15) — and it is the arm that fails if the one-shot
/// mechanism this test is named for ever stops being the mechanism.
@MainActor @Test func anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates() throws {
    let model = AnimationDriveModel()
    let (window, platformWindow) = try makeDriveWindow(model)
    platformWindow.simulateTick(timestamp: 100)
    try #require(subjectWidth(window) == 100, "set up: the resting baseline")

    // The FIRST observable write since that drawn frame: the session is armed,
    // `onChange` fires, `markDirtyFromObservation` reaches `setNeedsRedraw()`.
    let beforeFirst = Window.redrawRequests
    model.width = 120
    try #require(Window.redrawRequests > beforeFirst, """
                 set up: an interval's FIRST observable write must reach setNeedsRedraw() — \
                 if it does not, this fixture is not the asymmetry it is named for
                 """)

    // The SECOND, inside a transaction. The session is spent and is re-armed
    // only by the next drawn frame, so nothing observes this at all.
    let beforeSecond = Window.redrawRequests
    withAnimation(.linear(duration: 1)) { model.width = 200 }
    try #require(Window.redrawRequests == beforeSecond, """
                 set up: the second observable write of an interval must move NO counter — \
                 that is the whole regime this test exists in, and a fixture where the \
                 counter moved would pass under the very rule it must reject
                 """)

    // A frame is coming regardless, because the first write left the window
    // dirty. The transaction must survive to reach it.
    platformWindow.simulateTick(timestamp: 100)
    #expect(subjectWidth(window) == 100, """
            the frame that starts the transition reads its own `from`; 200 means the \
            transaction was discarded and the change snapped, \
            got \(String(describing: subjectWidth(window)))
            """)

    platformWindow.simulateTick(timestamp: 100.5)
    #expect(subjectWidth(window) == 150, """
            halfway through a 1s linear 100 -> 200; 200 is the counter-only rule silently \
            dropping a legitimate animation, got \(String(describing: subjectWidth(window)))
            """)
    #expect(window.hasActiveAnimations, "and it is genuinely still interpolating")
}

// MARK: - Stage 8: an animated `.frame(width:)` (`LR-ES`'s R8)

/// A scene rect's bounds, comparable.
private struct SceneRect: Equatable, CustomStringConvertible {
    var x, y, width, height: Float
    init(_ b: MUIBounds) { (x, y, width, height) = (b.origin.x, b.origin.y, b.size.width, b.size.height) }
    var description: String { "(\(x), \(y)) \(width)x\(height)" }
}

@Observable
private final class SidebarWidthModel {
    var wide = false
}

/// The demo sidebar's shape with its width spelled the deprecated way —
/// `.width(_:)` on the padding layer — the class-D arm of N1.5 (`LR-EW`).
private struct SidebarOldSpelling: DeprecatedSpelling {
    let model: SidebarWidthModel
    @available(*, deprecated, message: "spells the sidebar's width with the deprecated .width(_:) on purpose: the old arm of anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid (stage 8, LR-EW class D)")
    func spelled() -> some Element {
        Row {
            Column {
                Text("Library")
                Box().cssHeight(Pixels(26)).background(.surfaceSecondary)
            }
            .alignItems(.stretch)
            .flexGrow(1)
            .padding(Pixels(14))
            .width(model.wide ? Pixels(320) : Pixels(196))
            .background(.accent)
            Box().flexGrow(1)
        }
        .alignItems(.stretch)
        .cssWidth(Pixels(600)).cssHeight(Pixels(400))
    }
}

/// **N1.5** (stage 8 spec §6; `LR-ES`'s R8, `LR-EW`). The demo sidebar's one
/// animated size: `Column { … }.alignItems(.stretch).flexGrow(1).padding(14)`
/// sized 196 → 320 under `withAnimation(.linear(duration: 1))`, in a stretched
/// `Row`, spelled the old way (`.width(_:)` on the padding layer, a class-D
/// witness) and the recipe's way (`.frame(width:, alignment: .top)`, the demo
/// conversion). Driven through a real `Window` by `simulateTick` at the start,
/// ¼, ½ and the end: the scene's rects — the padded box's background and the
/// row inside it — are **equal at every tick**, and the padded box's width at
/// the two mid ticks is **strictly between 196 and 320** (`#require`d, so a pair
/// that both snapped cannot agree at an endpoint and pass).
///
/// Green on arrival — a must-not-move pin (the frame layer reads its fixed size
/// from its animated style, and takes the slot the sized modifier's `$anim` sat
/// at, R7/R8). Its instrument is the mutation.
///
/// Mutation that must redden it: **M1e** (`bound(_:_:)` in
/// `lowerShownLegacyFrameLayer` returns the declared value) → the frame snaps to
/// 320 while the old spelling reads the interpolated width.
@MainActor @Test func anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid() throws {
    func run<E: Element>(_ make: @escaping @MainActor (SidebarWidthModel) -> E) throws -> [[SceneRect]] {
        let model = SidebarWidthModel()
        let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 600, startsDisplayLink: true) {
            make(model)
        }
        var ticks: [[SceneRect]] = []
        platform.simulateTick(timestamp: 100)
        ticks.append(window.lastScene.rects.map { SceneRect($0.bounds) })
        withAnimation(.linear(duration: 1)) { model.wide = true }
        for t in [100, 100.25, 100.5, 101] {
            platform.simulateTick(timestamp: t)
            ticks.append(window.lastScene.rects.map { SceneRect($0.bounds) })
        }
        return ticks
    }
    let old = try run { oldSpelling(SidebarOldSpelling(model: $0)) }
    let new = try run { model in
        Row {
            Column {
                Text("Library")
                Box().cssHeight(Pixels(26)).background(.surfaceSecondary)
            }
            .alignItems(.stretch)
            .flexGrow(1)
            .padding(Pixels(14))
            .frame(width: model.wide ? Pixels(320) : Pixels(196), alignment: .top)
            .background(.accent)
            Box().flexGrow(1)
        }
        .alignItems(.stretch)
        .cssWidth(Pixels(600)).cssHeight(Pixels(400))
    }
    try #require(old.count == 5 && new.count == 5)
    for (i, rects) in old.enumerated() { try #require(rects.count == 2, "old tick \(i): \(rects)") }
    let oldWidths = old.map { $0[0].width }
    try #require(oldWidths.first == 196 && oldWidths.last == 320, "old endpoints: \(oldWidths)")
    for i in [2, 3] {
        try #require(oldWidths[i] > 196 && oldWidths[i] < 320, "old tick \(i) snapped: \(oldWidths)")
    }
    for (i, (o, n)) in zip(old, new).enumerated() {
        #expect(o == n, "tick \(i): old \(o), new \(n)")
    }
}
