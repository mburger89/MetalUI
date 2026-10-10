import Testing
import MetalUITestSupport

// C10 lane 2, keyframe guards (rulings `LK-I` items 5 and 8, `LK-T` items 2
// and 4, `LK-V` items 2–3; spec `2026-10-08-controls-looks-design.md` §4.2).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import — a
// `@testable` test cannot prove what an external module can spell. No
// `PlatformWindow` conformer is declared here (`LK-T` item 1).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `LK-I call shape`, `LK-V
// conformances` and `LK-I spring duration` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// `LK-I` items 9–12, `LK-T` items 2 and 4. MetalCreator's refused-wire shake
/// (`M5-i`) typechecks from an external module in SwiftUI's call shape — on a
/// legacy `Box`, on proposal content in an `HStack`, as the `KeyframeAnimator`
/// view, the repeating form and a two-track timeline over a struct — and a
/// legacy `Self`-returning decoration written **after** the animator does not
/// (divergence 120's rule; written inside the content closure it does).
///
/// Mutations: rename `trigger:` (the positive fails); make the modifier return
/// `Self`-typed content (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func keyframeAnimatorTypechecksWithSwiftUIsCallShape() throws {
    let positive = try typecheckFile("""
        struct Wobble { var x = 0.0; var scale = 1.0 }
        @MainActor func tree(_ refusals: Int, _ spinning: Bool) -> some Element {
            Column {
                Box().frame(width: Pixels(20), height: Pixels(20))
                    .keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, x in
                        content.offset(x: Pixels(Float(x)))
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(6, duration: 0.05)
                            LinearKeyframe(-6, duration: 0.1)
                            LinearKeyframe(0, duration: 0.05)
                        }
                    }
                Text("a").onClick {}
                    .keyframeAnimator(initialValue: Wobble(), repeating: spinning) { content, w in
                        content.offset(x: Pixels(Float(w.x))).scaleEffect(w.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\\.x) { CubicKeyframe(4, duration: 0.2); SpringKeyframe(0, duration: 0.3, spring: Spring(duration: 0.3, bounce: 0.2)) }
                        KeyframeTrack(\\.scale) { MoveKeyframe(1.2); LinearKeyframe(1, duration: 0.4, timingCurve: .easeOut) }
                    }
                HStack {
                    ProposalText("b").keyframeAnimator(initialValue: Angle.zero, trigger: refusals) { content, a in
                        content.rotationEffect(a)
                    } keyframes: { _ in
                        KeyframeTrack { LinearKeyframe(Angle.degrees(10), duration: 0.1, timingCurve: .bezier(startControlPoint: UnitPoint(x: 0.2, y: 0), endControlPoint: .bottomTrailing)) }
                    }
                }
                KeyframeAnimator(initialValue: 0.0, trigger: refusals) { x in
                    Text("c").offset(x: Pixels(Float(x)))
                } keyframes: { start in
                    KeyframeTrack { LinearKeyframe(start + 1, duration: 0.1) }
                }
            }
        }
        func timeline() -> Double {
            let t = KeyframeTimeline(initialValue: 0.0) { KeyframeTrack { LinearKeyframe(1.0, duration: 1) } }
            return t.value(time: 0.5) + t.value(progress: 0.5) + t.duration
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree(_ refusals: Int) -> some Element {
            Column {
                Box().frame(width: Pixels(20), height: Pixels(20))
                    .keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, x in
                        content.offset(x: Pixels(Float(x)))
                    } keyframes: { _ in
                        KeyframeTrack { LinearKeyframe(6, duration: 0.05) }
                    }
                    .onClick {}
            }
        }
        """, importing: "MetalUI")
    print("""
        LK-I call shape: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 SwiftUI's call shape must compile and a decoration after the animator must not, or this \
                 guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("onClick"), "the negative must be refused for onClick:\n\(negative.output)")
}

/// `LK-V` item 2 (`MC-G`'s precedent). A type outside MetalUI cannot write its
/// own keyframes: the carriers `KeyframeTrackContentGroup` and `KeyframesGroup`
/// have no public initialiser, so a conformance that builds one does not
/// compile; forwarding to MetalUI's own keyframes (the positive control) does.
///
/// Mutation: make `KeyframeTrackContentGroup.init` and `KeyframesGroup.init`
/// public (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func userConformancesToKeyframesDoNotCompile() throws {
    let positive = try typecheckFile("""
        struct Nudge: KeyframeTrackContent {
            var _keyframes: KeyframeTrackContentGroup<Double> { LinearKeyframe(1.0, duration: 0.1)._keyframes }
        }
        struct Tracks: Keyframes {
            var _tracks: KeyframesGroup<Double> { KeyframeTrack { Nudge() }._tracks }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        struct Nudge: KeyframeTrackContent {
            var _keyframes: KeyframeTrackContentGroup<Double> { KeyframeTrackContentGroup([]) }
        }
        struct Tracks: Keyframes {
            var _tracks: KeyframesGroup<Double> { KeyframesGroup([]) }
        }
        """, importing: "MetalUI")
    print("""
        LK-V conformances: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 a forwarding conformance must compile and a building one must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("initializer") || negative.messages.contains("inaccessible"),
            "the negative must be refused for the carrier's initialiser:\n\(negative.output)")
}

/// `LK-I` item 5, divergence 168. `SpringKeyframe` without `duration:` does not
/// compile (SwiftUI's default length is unfitted, `K4b`); with it, it does.
///
/// Mutation: default `duration` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func springKeyframeWithoutDurationDoesNotCompile() throws {
    let positive = try typecheckFile("""
        let t = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { SpringKeyframe(10.0, duration: 0.4, spring: Spring(duration: 0.4, bounce: 0.3)) }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        let t = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { SpringKeyframe(10.0, spring: Spring(duration: 0.4, bounce: 0.3)) }
        }
        """, importing: "MetalUI")
    print("""
        LK-I spring duration: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 a SpringKeyframe with a duration must compile and one without must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
    #expect(negative.messages.contains("duration"), "the negative must be refused for duration:\n\(negative.output)")
}
