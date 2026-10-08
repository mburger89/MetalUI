import Testing
@testable import MetalUI

// C10 lane 2: `KeyframeTimeline` as a pure function of time (rulings `LK-I`
// items 1–8; spec `2026-10-08-controls-looks-design.md` §4.2). Every literal is
// SwiftUI's own, pasted verbatim from probe `docs/probes/swiftui-controls-looks.swift`
// arms `K1`–`K9` (`time:value` pairs, printed to three places), and compared
// within 0.001 — the print's rounding is 0.0005 — or 0.005 where the ruling says
// so (`K4d`). No window, no clock: `value(time:)` is arithmetic.

/// `"t:v t:v …"` from a probe line, as pairs.
private func samples(_ line: String) -> [(time: Double, value: Double)] {
    line.split(separator: " ").map { pair in
        let parts = pair.split(separator: ":")
        return (Double(parts[0])!, Double(parts[1])!)
    }
}

/// Every probe sample of `line` against `timeline`, within `tolerance`.
private func expectMatches(_ timeline: KeyframeTimeline<Double>, _ line: String, tolerance: Double = 0.001,
                           _ name: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let misses = samples(line).compactMap { sample -> String? in
        let actual = timeline.value(time: sample.time)
        return abs(actual - sample.value) <= tolerance ? nil : "t=\(sample.time): \(actual), SwiftUI \(sample.value)"
    }
    #expect(misses.isEmpty, "\(name): \(misses.joined(separator: "; "))", sourceLocation: sourceLocation)
}

/// The probe's fifteen sample times' line for `K1`.
private let k1 = "-0.100:0.000 0.000:0.000 0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:5.000 0.300:0.000 0.350:-5.000 0.400:-10.000 0.500:-5.000 0.600:-0.000 0.800:0.000 1.000:0.000 1.500:0.000"

/// **K1** (`LK-I` items 2–3). Three linear keyframes 0 → 10 → −10 → 0, 0.2 s
/// each: 0.6 s long, the initial value before 0, the last value after the end.
/// Mutation: apply the curve to the whole track (one linear 0 → 0 over 0.6 s).
@Test func linearKeyframesMatchK1() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            LinearKeyframe(10.0, duration: 0.2)
            LinearKeyframe(-10.0, duration: 0.2)
            LinearKeyframe(0.0, duration: 0.2)
        }
    }
    #expect(abs(timeline.duration - 0.6) < 1e-12, "duration \(timeline.duration)")
    expectMatches(timeline, k1, "K1")
}

/// **K2** (`LK-I` item 3). `LinearKeyframe(10, duration: 0.4, timingCurve:
/// .easeInOut)`: 0.311 at 0.05 s. Mutation: ignore the curve (2.5 at 0.05 s).
@Test func easeInOutMatchesK2() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { LinearKeyframe(10.0, duration: 0.4, timingCurve: .easeInOut) }
    }
    expectMatches(timeline, "-0.100:0.000 0.000:0.000 0.050:0.311 0.100:1.292 0.150:2.928 0.200:5.000 0.250:7.072 0.300:8.708 0.350:9.689 0.400:10.000 0.500:10.000 0.600:10.000 0.800:10.000 1.000:10.000 1.500:10.000", "K2")
}

/// **K3b** (`LK-I` item 4). A lone cubic keyframe starts and ends at velocity
/// 0 — smoothstep, 1.562 at a quarter. Mutation: a linear tangent (2.5).
@Test func aLoneCubicIsSmoothstepK3b() {
    let timeline = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0.4) } }
    expectMatches(timeline, "-0.100:0.000 0.000:0.000 0.050:0.430 0.100:1.562 0.150:3.164 0.200:5.000 0.250:6.836 0.300:8.437 0.350:9.570 0.400:10.000 0.500:10.000 0.600:10.000 0.800:10.000 1.000:10.000 1.500:10.000", "K3b")
}

/// **K3, K3c, K3f, K3g** (`LK-I` item 4). Between two cubic keyframes the
/// velocity is `(next − previous) / (t_next − t_previous)`: equal segments
/// (`K3`, `K3f`) and unequal ones (`K3c`, `K3g` — 75/s over 0.1 s and 0.3 s).
/// **Mutation (the separating arm)**: tangent `(next − previous) / 2` per
/// segment, which agrees with the rule on equal segments and fails `K3g` only.
@Test func cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g() {
    let k3 = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            CubicKeyframe(10.0, duration: 0.2)
            CubicKeyframe(-10.0, duration: 0.2)
            CubicKeyframe(0.0, duration: 0.2)
        }
    }
    expectMatches(k3, "-0.100:0.000 0.000:0.000 0.050:1.797 0.100:5.625 0.150:9.141 0.200:10.000 0.250:6.406 0.300:0.000 0.350:-6.406 0.400:-10.000 0.500:-5.625 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000", "K3")
    let k3c = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { CubicKeyframe(10.0, duration: 0.1); CubicKeyframe(0.0, duration: 0.3) }
    }
    expectMatches(k3c, "0.025:1.562 0.050:5.000 0.075:8.437 0.100:10.000 0.150:9.259 0.200:7.407 0.250:5.000 0.300:2.593 0.350:0.741", "K3c")
    let k3f = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { CubicKeyframe(10.0, duration: 0.2); CubicKeyframe(30.0, duration: 0.2) }
    }
    expectMatches(k3f, "0.050:0.859 0.100:3.125 0.150:6.328 0.250:15.234 0.300:21.875 0.350:27.578", "K3f")
    let k3g = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { CubicKeyframe(10.0, duration: 0.1); CubicKeyframe(30.0, duration: 0.3) }
    }
    expectMatches(k3g, "0.025:1.211 0.050:4.062 0.075:7.383 0.175:16.289 0.250:22.812 0.325:27.930", "K3g")
}

/// **K3d, K3h** (`LK-I` item 4). At a boundary with a non-cubic keyframe the
/// cubic takes that keyframe's velocity: 50/s from the linear before and 25/s
/// from the linear after (`K3d`), 0 from a linear hold (`K3h`). Mutation:
/// velocity 0 at every non-cubic boundary (`K3d` at 0.25 reads 8.437).
@Test func aCubicTakesALinearNeighboursVelocityK3dK3h() {
    let k3d = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            LinearKeyframe(10.0, duration: 0.2)
            CubicKeyframe(0.0, duration: 0.2)
            LinearKeyframe(5.0, duration: 0.2)
        }
    }
    expectMatches(k3d, "0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:9.609 0.300:5.625 0.350:1.328 0.400:0.000 0.500:2.500", "K3d")
    let k3h = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            CubicKeyframe(10.0, duration: 0.2)
            CubicKeyframe(30.0, duration: 0.2)
            LinearKeyframe(30.0, duration: 0.2)
        }
    }
    expectMatches(k3h, "0.250:15.234 0.300:21.875 0.350:27.578", "K3h")
}

/// **K3e** (`LK-I` item 4). An explicit start velocity wins: 50/s over 0.4 s,
/// 7.5 at the midpoint. Mutation: ignore `startVelocity` (smoothstep, 5.0).
@Test func anExplicitStartVelocityWinsK3e() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { CubicKeyframe(10.0, duration: 0.4, startVelocity: 50, endVelocity: 0) }
    }
    expectMatches(timeline, "0.050:2.344 0.100:4.375 0.200:7.500 0.300:9.375 0.350:9.844", "K3e")
}

/// **K4** (`LK-I` item 5). `SpringKeyframe(10, duration: 0.4, spring:
/// Spring(duration: 0.4, bounce: 0))` stops at its duration holding 9.864 —
/// never 10. Mutation: run the spring to its target at the end.
@Test func aSpringKeyframeHoldsWhereItsDurationEndsK4() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack { SpringKeyframe(10.0, duration: 0.4, spring: Spring(duration: 0.4, bounce: 0)) }
    }
    expectMatches(timeline, "-0.100:0.000 0.000:0.000 0.050:1.860 0.100:4.656 0.150:6.819 0.200:8.210 0.250:9.029 0.300:9.487 0.350:9.734 0.400:9.864 0.500:9.864 0.600:9.864 0.800:9.864 1.000:9.864 1.500:9.864", "K4")
}

/// **K4e** (`LK-I` item 5). A spring after a linear keyframe starts with the
/// linear's velocity, 50/s: 9.280 at 0.05 s into it. Mutation: start the
/// spring at rest (8.140 there).
@Test func aSpringCarriesTheIncomingVelocityK4e() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            LinearKeyframe(10.0, duration: 0.2)
            SpringKeyframe(0.0, duration: 0.4, spring: Spring(duration: 0.4, bounce: 0))
        }
    }
    expectMatches(timeline, "0.200:10.000 0.250:9.280 0.300:6.384 0.400:2.222 0.600:0.173", "K4e")
}

/// **K4c** (`LK-I` item 5). The keyframe after a cut-short spring starts from
/// the spring's value, 8.210 — not its target 10. Mutation: start the next
/// keyframe from the spring's target.
@Test func theNextKeyframeStartsFromTheSpringsValueK4c() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            SpringKeyframe(10.0, duration: 0.2, spring: Spring(duration: 0.4, bounce: 0))
            LinearKeyframe(0.0, duration: 0.2)
        }
    }
    expectMatches(timeline, "-0.100:0.000 0.000:0.000 0.050:1.860 0.100:4.656 0.150:6.819 0.200:8.210 0.250:6.158 0.300:4.105 0.350:2.053 0.400:0.000 0.500:0.000 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000", "K4c")
}

/// **K4d** (`LK-I` item 5). `Spring(duration:bounce:)`'s value toward 10 at
/// t = 0.1 for eight springs (critically, under- and overdamped), within 0.005.
/// Mutation: `zeta = 1 − bounce` for a negative bounce too (the overdamped
/// arm, 3.724, moves).
@Test func springValuesMatchK4dAtPointOne() {
    let probe: [(duration: Double, bounce: Double, value: Double)] = [
        (0.4, 0.0, 4.656), (0.4, 0.3, 5.614), (0.4, 0.5, 6.473), (0.4, -0.3, 3.724),
        (1.0, 0.0, 1.313), (1.0, 0.3, 1.457), (0.5, 0.15, 3.881), (0.2, 0.7, 13.679),
    ]
    for arm in probe {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { SpringKeyframe(10.0, duration: 1, spring: Spring(duration: arm.duration, bounce: arm.bounce)) }
        }
        let value = timeline.value(time: 0.1)
        #expect(abs(value - arm.value) <= 0.005,
                "Spring(duration: \(arm.duration), bounce: \(arm.bounce)) at 0.1: \(value), SwiftUI \(arm.value)")
    }
}

/// **K5** (`LK-I` item 6). A move keyframe jumps: 10 at 0.2 s (the linear's
/// end), −5 the instant after, then linear to 0. Mutation: interpolate the move
/// over the following keyframe's duration.
@Test func aMoveKeyframeJumpsK5() {
    let timeline = KeyframeTimeline(initialValue: 0.0) {
        KeyframeTrack {
            LinearKeyframe(10.0, duration: 0.2)
            MoveKeyframe(-5.0)
            LinearKeyframe(0.0, duration: 0.2)
        }
    }
    expectMatches(timeline, "-0.100:0.000 0.000:0.000 0.050:2.500 0.100:5.000 0.150:7.500 0.200:10.000 0.250:-3.750 0.300:-2.500 0.350:-1.250 0.400:0.000 0.500:0.000 0.600:0.000 0.800:0.000 1.000:0.000 1.500:0.000", "K5")
}

/// Two fields, as the probe's `Shake`.
private struct Shake: Equatable {
    var x = 0.0
    var s = 1.0
}

/// **K6** (`LK-I` item 1). Two tracks run in parallel: the timeline lasts the
/// longer's 0.6 s and the shorter holds its last value. Mutation: sum the
/// tracks' durations (1.0 s).
@Test func tracksRunInParallelAndHoldK6() {
    let timeline = KeyframeTimeline(initialValue: Shake()) {
        KeyframeTrack(\.x) { LinearKeyframe(10.0, duration: 0.2); LinearKeyframe(0.0, duration: 0.2) }
        KeyframeTrack(\.s) { LinearKeyframe(2.0, duration: 0.6) }
    }
    #expect(abs(timeline.duration - 0.6) < 1e-12, "duration \(timeline.duration)")
    let probe = "-0.100:(0.000,1.000) 0.000:(0.000,1.000) 0.050:(2.500,1.083) 0.100:(5.000,1.167) 0.150:(7.500,1.250) 0.200:(10.000,1.333) 0.250:(7.500,1.417) 0.300:(5.000,1.500) 0.350:(2.500,1.583) 0.400:(0.000,1.667) 0.500:(0.000,1.833) 0.600:(0.000,2.000) 0.800:(0.000,2.000) 1.000:(0.000,2.000) 1.500:(0.000,2.000)"
    for pair in probe.split(separator: " ") {
        let parts = pair.split(separator: ":")
        let time = Double(parts[0])!
        let numbers = parts[1].dropFirst().dropLast().split(separator: ",").map { Double($0)! }
        let value = timeline.value(time: time)
        #expect(abs(value.x - numbers[0]) <= 0.001 && abs(value.s - numbers[1]) <= 0.001,
                "K6 t=\(time): (\(value.x), \(value.s)), SwiftUI (\(numbers[0]), \(numbers[1]))")
    }
}

/// **K7** (`LK-I` item 1). A field no track names keeps the initial value: 7
/// throughout. Mutation: reset an untracked field to its type's zero.
@Test func anUntrackedFieldKeepsItsInitialValueK7() {
    let timeline = KeyframeTimeline(initialValue: Shake(x: 3, s: 7)) {
        KeyframeTrack(\.x) { LinearKeyframe(10.0, duration: 0.2) }
    }
    let probe: [(Double, Double, Double)] = [(0, 3, 7), (0.1, 6.5, 7), (0.2, 10, 7), (0.5, 10, 7)]
    for (time, x, s) in probe {
        let value = timeline.value(time: time)
        #expect(abs(value.x - x) <= 0.001 && value.s == s, "K7 t=\(time): (\(value.x), \(value.s))")
    }
}

/// **K8** (`LK-I` item 7, divergence 171). A zero-duration keyframe reads its
/// target at its own time — SwiftUI reads `nan` there (`K8`) — and nothing the
/// timeline returns is non-finite. The probe's own arm (initial 4, target 4)
/// cannot tell a target from the initial value, so the separating arm is
/// initial 0, target 10. Mutation: divide by the duration (`nan`).
@Test func aZeroDurationKeyframeReadsItsTarget() {
    let probe = KeyframeTimeline(initialValue: 4.0) { KeyframeTrack { LinearKeyframe(4.0, duration: 0) } }
    #expect(probe.duration == 0)
    #expect(probe.value(time: 0) == 4 && probe.value(time: 0.1) == 4, "K8: \(probe.value(time: 0)), \(probe.value(time: 0.1))")
    let separating = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0) } }
    for time in [0.0, 0.1, 1] {
        let value = separating.value(time: time)
        #expect(value == 10, "a zero-duration keyframe at t=\(time) reads \(value), not its target 10")
    }
    #expect(separating.value(progress: 0.5) == 10, "value(progress:) of a zero-length timeline")
    let cubic = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { CubicKeyframe(10.0, duration: 0) } }
    let spring = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { SpringKeyframe(10.0, duration: 0) } }
    #expect(cubic.value(time: 0) == 10 && spring.value(time: 0) == 10,
            "cubic \(cubic.value(time: 0)), spring \(spring.value(time: 0))")
}

/// **K9** (`LK-I` item 2). `value(progress:)` is `value(time: clamp(progress,
/// 0, 1) × duration)`: 0, 5, 10, 10 at 0, 0.5, 1, 1.5. The clamp itself cannot
/// be seen through values — before 0 a track reads its initial value and after
/// its end its last, so an unclamped time reads the same — so the separating
/// arm is the duration it scales by: the **longest** track's, 0.75 of 0.8 s.
/// Mutation: scale by the first track's duration (0.2 s; `s` reads 1.75).
@Test func valueProgressClampsK9() {
    let timeline = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(10.0, duration: 0.4) } }
    let values = [0, 0.5, 1, 1.5].map { timeline.value(progress: $0) }
    #expect(zip(values, [0.0, 5, 10, 10]).allSatisfy { abs($0 - $1) <= 0.001 }, "K9: \(values)")
    // The separating arm: two tracks of unequal length.
    let two = KeyframeTimeline(initialValue: Shake()) {
        KeyframeTrack(\.x) { LinearKeyframe(10.0, duration: 0.2) }
        KeyframeTrack(\.s) { LinearKeyframe(3.0, duration: 0.4); LinearKeyframe(5.0, duration: 0.4) }
    }
    let clamped = two.value(progress: 0.75)
    #expect(abs(clamped.s - 4) <= 0.001, "progress 0.75 of 0.8 s: s \(clamped.s)")
    #expect(abs(two.value(progress: 1.5).s - 5) <= 0.001 && abs(two.value(progress: -1).s - 1) <= 0.001,
            "progress outside 0…1 clamps: \(two.value(progress: 1.5).s), \(two.value(progress: -1).s)")
}
