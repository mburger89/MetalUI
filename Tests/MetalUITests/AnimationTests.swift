import Testing
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

// MARK: - Task 4: every registering site substitutes through `animated`

/// Spec §5's correction block: there is no single choke point. `Box`,
/// `Stack` and `ScrollView`'s two nodes each call
/// `LayoutPass.requestNode` independently, so nothing enforces that any one
/// of them actually routes its declared `Style`/`Decoration` through
/// `animated(_:_:for:pass:)` before handing it to the layout engine — on
/// `onClickIsLiveOnEveryConformerThatCanRegisterOne`'s footing
/// (`InputDispatchTests.swift`), which exists for the identical reason: a
/// conformer can compile and register nothing.
///
/// **`Box` and `Stack`** are checked the way Task 3's own tests check the
/// helper directly (see `aFieldThatDiffersUnderATransactionBeginsAnimating…`
/// above): a fresh element is reconstructed each frame — exactly as
/// `Frame.render` rebuilds one from the content closure every frame — with a
/// real, caller-visible field (`flexGrow`) declared differently, and the
/// registered node's `Style` is read back through `pass.style(_:)`.
///
/// **`ScrollView`'s two nodes have no caller-visible `Style` at all** — the
/// type is not `StyledElement`, and `contentStyle`/`viewportStyle` are built
/// entirely from constants inside `requestLayout` (spec §5's own reason this
/// site needs two independent `$anim` slots — see `ScrollView.requestLayout`'s
/// comment). So there is no declared field a test can vary across frames the
/// way it can for `Box`/`Stack`. Each is instead checked by pre-seeding an
/// in-flight, unfinished `AnimatedFieldState` directly into the `inFlight`
/// dictionary of an `AnimatedElementState` baseline written to the exact
/// `$anim` slot that site's own wiring derives (ruling U's reshaped
/// storage — `AnimatedStyle.swift`), targeting the value the site always
/// declares (`flexShrink: 0` for the content node, `flexGrow: 0` — never
/// explicitly set — for the viewport node). A wired site substitutes the
/// still-interpolating value in; an unwired one hands the raw declared value
/// straight through unchanged, which is exactly the differential a mutation
/// that un-wires the site needs to redden.
@Test @MainActor func everyRegisteringSiteAnimatesItsStyle() throws {
    func styled(flexGrow: Float) -> Style {
        var s = Style()
        s.flexGrow = flexGrow
        return s
    }

    // MARK: Box

    do {
        let table = StateTable()
        let id = eid("box")

        var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var box1 = Box(style: styled(flexGrow: 0))
        _ = box1.requestLayout(id, pass: &pass1)

        var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var midStyle: Style!
        withAnimation(.linear(duration: 1)) {
            var box2 = Box(style: styled(flexGrow: 100))
            let (node, _) = box2.requestLayout(id, pass: &pass2)
            midStyle = pass2.style(node)
        }
        #expect(midStyle.flexGrow == 0, """
                Box: registering site does not animate — expected the transaction-start \
                'from' value 0, got \(midStyle.flexGrow)
                """)

        var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var box3 = Box(style: styled(flexGrow: 100))
        let (node3, _) = box3.requestLayout(id, pass: &pass3)
        #expect(pass3.style(node3).flexGrow == 50, """
                Box: registering site does not animate — expected the halfway value 50, \
                got \(pass3.style(node3).flexGrow)
                """)
    }

    // MARK: Stack

    do {
        let table = StateTable()
        let id = eid("stack")

        var pass1 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var stack1 = Stack { Box() }
        _ = stack1.requestLayout(id, pass: &pass1)

        var pass2 = LayoutPass(frame: animFrame(table, timestamp: 0))
        var midStyle: Style!
        withAnimation(.linear(duration: 1)) {
            var stack2 = Stack { Box() }.flexGrow(100)
            let (node, _) = stack2.requestLayout(id, pass: &pass2)
            midStyle = pass2.style(node)
        }
        #expect(midStyle.flexGrow == 0, """
                Stack: registering site does not animate — expected the transaction-start \
                'from' value 0, got \(midStyle.flexGrow)
                """)

        var pass3 = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var stack3 = Stack { Box() }.flexGrow(100)
        let (node3, _) = stack3.requestLayout(id, pass: &pass3)
        #expect(pass3.style(node3).flexGrow == 50, """
                Stack: registering site does not animate — expected the halfway value 50, \
                got \(pass3.style(node3).flexGrow)
                """)
    }

    // MARK: ScrollView — content node

    do {
        let table = StateTable()
        let id = eid("scroll-content")
        let animID = scrollViewContentAnimID(for: id)
        let slot = animRetentionSlot(for: animID)
        // Ruling U: the baseline `style` must match what `ScrollView` will
        // actually declare for `contentStyle` this frame (a default `Style`
        // with `flexShrink = 0`) so every OTHER field's native equality
        // check short-circuits and only the pre-seeded `flexShrink` entry
        // exercises the animation machinery.
        var seedStyle = Style()
        seedStyle.flexShrink = 0
        let seed = AnimatedElementState(style: seedStyle, decoration: Decoration(), inFlight: [
            "flexShrink": AnimatedFieldState(caseTag: 0, from: -100, to: 0, startTime: 0,
                                             animation: .linear(duration: 1), velocity: 0)
        ])
        table.write(slot, seed)

        var pass = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var scroll = ScrollView { Box() }
        let (_, layout) = scroll.requestLayout(id, pass: &pass)
        let out = pass.style(layout.contentNode)
        #expect(out.flexShrink == -50, """
                ScrollView content node: registering site does not animate — expected the \
                interpolated value -50, got \(out.flexShrink)
                """)
    }

    // MARK: ScrollView — viewport node

    do {
        let table = StateTable()
        let id = eid("scroll-viewport")
        let animID = scrollViewViewportAnimID(for: id)
        let slot = animRetentionSlot(for: animID)
        // Ruling U: `viewportStyle` never sets `flexGrow` explicitly, so the
        // seeded baseline is a plain default `Style()` — matching what
        // `ScrollView` will actually declare this frame, on the content
        // node's footing above.
        let seed = AnimatedElementState(style: Style(), decoration: Decoration(), inFlight: [
            "flexGrow": AnimatedFieldState(caseTag: 0, from: -100, to: 0, startTime: 0,
                                           animation: .linear(duration: 1), velocity: 0)
        ])
        table.write(slot, seed)

        var pass = LayoutPass(frame: animFrame(table, timestamp: 0.5))
        var scroll = ScrollView { Box() }
        let (node, _) = scroll.requestLayout(id, pass: &pass)
        let out = pass.style(node)
        #expect(out.flexGrow == -50, """
                ScrollView viewport node: registering site does not animate — expected the \
                interpolated value -50, got \(out.flexGrow)
                """)
    }
}

// MARK: - Task 4 fix round 1: the `Decoration` half was unguarded at every site

/// **`everyRegisteringSiteAnimatesItsStyle` reads back only `pass.style(node)`,
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
/// `everyRegisteringSiteAnimatesItsStyle` and the per-site guards' job; this
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
/// The two extra assertions at the end are the signal Task 5 will read:
/// `Frame.wantsAnotherFrame` is raised while the fade is live and left alone
/// once it settles. `Window.drawFrameIfNeeded` already consumes it
/// (`Window.swift`'s `if frame.wantsAnotherFrame { setNeedsRedraw() }`), and
/// paint runs before that check, so a paint-phase contribution is reachable.
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
    #expect(frame2.wantsAnotherFrame,
            "an animation started this frame must ask for the next one")

    // Frame 3: half a second later, still declaring `.accent`, no transaction
    // of its own — the animation begun in frame 2 still running.
    let frame3 = colorFrame(table, timestamp: 0.5, theme: theme)
    var f3 = PaintPass(frame: frame3)
    let out3 = animatedColor(.accent, for: id, pass: &f3)
    expectColor(out3, h: midBackgroundToAccent.h, s: midBackgroundToAccent.s,
                l: midBackgroundToAccent.l, "halfway through linear(duration: 1)")
    #expect(frame3.wantsAnotherFrame, "still mid-flight: the display link must stay awake")

    // Frame 4: past the end. The value lands exactly on the target and the
    // frame stops asking for another one.
    let frame4 = colorFrame(table, timestamp: 1.5, theme: theme)
    var f4 = PaintPass(frame: frame4)
    let out4 = animatedColor(.accent, for: id, pass: &f4)
    expectColor(out4, h: 0.111111, s: 0.75, l: 0.60, tolerance: 1e-5,
                "finished: exactly the target token's resolved colour")
    #expect(!frame4.wantsAnotherFrame,
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
    #expect(!frame2.wantsAnotherFrame,
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
            .width(Pixels(40)).height(Pixels(40))
            .background(.background)
            .hoverBackground(.accent)
            .focusBackground(.separator)
            .focusable()
            .onClick {}
        b.elementID = ElementID("chain")
        return b
    }
    let id = eid("chain")
    let inside = Point(x: Pixels(20), y: Pixels(20))

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
    // **The vacuity guard is `s`, not `l`, and the first version was too weak
    // to mean what its message said.** It read `l > 0.58` against a target `l`
    // of `0.60`, so a spring that merely ARRIVED without overshooting at all
    // would have satisfied it. `l` cannot serve here: red clamps at `1.0` while
    // green rises and blue falls, so `l == (max + min)/2` DROPS as the
    // overshoot grows (`0.60` at 20% overshoot, `0.575` at 30%) instead of
    // rising. Saturation can: for `max + min >= 1`, `s == (max - min) /
    // (2 - max - min)`, which is identically `1` when `max == 1` — that is,
    // exactly when the clamp fired — while the resting target
    // `(0.90, 0.70, 0.30)` sits at `s == 0.75`. So `s` reaching 1 is a direct
    // readout of the clamp having done something, not a proxy for it.
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
@Test @MainActor func interruptingAColourFadeReTargetsFromItsCurrentValueAndVelocity() {
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
        #expect(abs((out4?.s ?? 0) - midBackgroundToSeparator.s) > 0.1, """
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
        #expect(!frame3.wantsAnotherFrame,
                "and the abandoned animation must stop holding the display link awake")

        let frame4 = colorFrame(table, timestamp: 0.5, theme: theme)
        var f4 = PaintPass(frame: frame4)
        let out4 = animatedColor(.separator, for: id, pass: &f4)
        expectColor(out4, h: 0.770833, s: 0.80, l: 0.50, tolerance: 1e-5,
                    "and it STAYS there — the old animation was dropped, not paused")
        #expect(!frame4.wantsAnotherFrame)
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
    #expect(!frame2.wantsAnotherFrame, """
            nothing was declared differently, so no animation may start and the display \
            link must not be held awake
            """)

    // And nothing is left running to advance on a later frame.
    let frame3 = colorFrame(table, timestamp: 0.5, theme: swapped)
    var f3 = PaintPass(frame: frame3)
    let out3 = animatedColor(.background, for: id, pass: &f3)
    expectColor(out3, h: 0.958333, s: 0.666667, l: 0.30, tolerance: 1e-5,
                "and it stays there")
    #expect(!frame3.wantsAnotherFrame)
}
