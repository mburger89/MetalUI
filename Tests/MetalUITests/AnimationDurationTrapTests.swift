import Testing
@testable import MetalUI

// `Animation.linear(duration:)` and `Animation.spring(duration:bounce:)` must
// trap on a non-finite `duration`, the way `timingCurve` already does.
//
// **Why `.infinity` is the dangerous one.** Both evaluators open with a
// `duration > 0` / `seconds > 0` guard that snaps to `to` with `isFinished ==
// true`, so `0`, negatives and `.nan` (every comparison against a NaN is
// false) were never stuck. `.infinity` passes that guard. Measured against
// the unfixed source, elapsed 0, 1, 30 and 1e6, from 0 to 100:
//   - `linear(duration: .infinity)` — `elapsed >= .infinity` is never true
//     and `elapsed / .infinity` is 0, so it sits at `0` with `isFinished ==
//     false` at every sample;
//   - `spring(duration: .infinity, bounce: 0)` — omega is 0, so it sits at `0`
//     with `isFinished == false` at every sample;
//   - `spring(duration: .infinity, bounce: 0.2)` — returns NaN value and
//     `isFinished == false` at every sample.
// An unfinished field stays in `inFlight`, which keeps
// `Frame.hasActiveAnimations` true, which keeps the display link from ever
// pausing — the same consequence `spring`'s `bounce` precondition exists for.
//
// **Not `duration > 0`.** `0` and negatives are the measured-safe snap, and a
// caller computing a duration that lands on `0` means "no animation", not a
// programmer error; the `.success` arms below keep that open. `.nan` does
// trap now: it was safe (it snapped), but `timingCurve` — and so `easeIn`,
// `easeOut` and `easeInOut` — already trapped on a NaN duration, and a
// finiteness rule that differed between `linear` and `easeIn` would be the
// inconsistency. `1e9` is a legitimate (very slow) animation and must not trap.

@Test func linearTrapsOnANonFiniteDuration() async {
    await #expect(processExitsWith: .failure) {
        _ = Animation.linear(duration: .infinity)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.linear(duration: .nan)
    }
}

@Test func springTrapsOnANonFiniteDuration() async {
    await #expect(processExitsWith: .failure) {
        _ = Animation.spring(duration: .infinity, bounce: 0)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.spring(duration: .infinity, bounce: 0.2)
    }
    await #expect(processExitsWith: .failure) {
        _ = Animation.spring(duration: .nan, bounce: 0)
    }
}

/// The positive control (ruling CS-C): without it the two tests above pass
/// against a `precondition(false)`, or against `duration > 0`, which would
/// trap the snap a zero or negative duration has always meant.
///
/// **Each arm also checks what it admits still behaves**, and does so INSIDE
/// the child process, with `precondition` rather than `#expect`. A zero or
/// negative duration must snap to `to`, finished (why `> 0` is wrong); a `1e9`
/// one must be genuinely in flight and finite (why a magnitude cap is wrong).
/// These checks first lived in an ordinary in-process test, and the `> 0`
/// mutant trapped there at `linear(duration: 0)` — killing the test process
/// and truncating the suite with no summary line (practices shape 13), where
/// an exit-test arm reports the same trap as one failed expectation.
@Test func aHugeZeroOrNegativeDurationDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let l = Animation.linear(duration: 1e9).value(at: 1, from: 0, to: 100, initialVelocity: 0)
        precondition(!l.isFinished && l.value.isFinite && l.value > 0, "linear(1e9) -> \(l)")
        let s = Animation.spring(duration: 1e9, bounce: 0.2).value(at: 1, from: 0, to: 100, initialVelocity: 0)
        precondition(!s.isFinished && s.value.isFinite, "spring(1e9) -> \(s)")
    }
    await #expect(processExitsWith: .success) {
        let l = Animation.linear(duration: 0).value(at: 0, from: 0, to: 100, initialVelocity: 0)
        precondition(l.value == 100 && l.isFinished, "linear(0) -> \(l)")
        let s = Animation.spring(duration: 0, bounce: 0).value(at: 0, from: 0, to: 100, initialVelocity: 0)
        precondition(s.value == 100 && s.isFinished, "spring(0) -> \(s)")
    }
    await #expect(processExitsWith: .success) {
        let l = Animation.linear(duration: -1).value(at: 0, from: 0, to: 100, initialVelocity: 0)
        precondition(l.value == 100 && l.isFinished, "linear(-1) -> \(l)")
        let s = Animation.spring(duration: -1, bounce: 0).value(at: 0, from: 0, to: 100, initialVelocity: 0)
        precondition(s.value == 100 && s.isFinished, "spring(-1) -> \(s)")
    }
}
