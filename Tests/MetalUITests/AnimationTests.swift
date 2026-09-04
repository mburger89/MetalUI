import Testing
import MetalUICore
import MetalUILayout
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
        let animID = GlobalElementID.child(of: id, at: 0, name: ElementID("$anim-content"))
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
        let animID = GlobalElementID.child(of: id, at: 0, name: ElementID("$anim-viewport"))
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
