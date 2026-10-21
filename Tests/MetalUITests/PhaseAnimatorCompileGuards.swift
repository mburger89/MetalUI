import Testing
import MetalUITestSupport

// G1 lane 2, phase-animator guards (rulings `GS-H`, `GS-I`; divergence 120's rule, `LK-T` item 2).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import. A guard skips silently
// when `.build/<triple>/debug/Modules` is absent (CLAUDE.md "Guards"); grep the log for
// `GS.PA1 call shape` and `GS.PA2 phases` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// `GS.PA1`. SwiftUI's call shapes typecheck from an external module — the modifier with and without
/// a trigger, with and without `animation:`, on a legacy `Box`, on proposal content in an `HStack`,
/// and the `PhaseAnimator` view in both forms — and a legacy `Self`-returning decoration written
/// **after** the animator does not (divergence 120's rule).
///
/// Mutations: rename `trigger:` (the positive fails); make the modifier return `Self`-typed content
/// (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func phaseAnimatorTypechecksWithSwiftUIsCallShape() throws {
    let positive = try typecheckFile("""
        enum Beat { case rest, swell, ring }
        @MainActor func tree(_ taps: Int) -> some Element {
            Column {
                Box().frame(width: Pixels(20), height: Pixels(20))
                    .phaseAnimator([Beat.rest, .swell, .ring]) { content, beat in
                        content.scaleEffect(beat == .swell ? 1.2 : 1)
                    } animation: { beat in
                        beat == .ring ? .linear(duration: 0.2) : .default
                    }
                Box().frame(width: Pixels(20), height: Pixels(20))
                    .phaseAnimator([0.0, 1.0], trigger: taps) { content, x in
                        content.offset(x: Pixels(Float(x)))
                    }
                HStack {
                    ProposalText("b").phaseAnimator([false, true], trigger: taps) { content, on in
                        content.opacity(on ? 1 : 0.5)
                    } animation: { _ in nil }
                }
                PhaseAnimator([0, 1, 2], trigger: taps) { p in
                    Text("c\\(p)")
                } animation: { _ in .default }
                PhaseAnimator([0, 1]) { p in Text("d\\(p)") }
            }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree(_ taps: Int) -> some Element {
            Column {
                Box().frame(width: Pixels(20), height: Pixels(20))
                    .phaseAnimator([0.0, 1.0], trigger: taps) { content, x in
                        content.offset(x: Pixels(Float(x)))
                    }
                    .onClick {}
            }
        }
        """, importing: "MetalUI")
    print("""
        GS.PA1 call shape: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
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

/// `GS.PA2`. The phases are `Equatable`, as SwiftUI's: an enum with a payload-free case list
/// compiles; a phase type that is not `Equatable` does not.
///
/// Mutation: drop the `Equatable` constraint (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func phaseAnimatorPhasesMustBeEquatable() throws {
    let positive = try typecheckFile("""
        struct Pose: Equatable { var angle = 0.0 }
        @MainActor func tree() -> some ElementGroup {
            Box().phaseAnimator([Pose(), Pose(angle: 4)]) { content, pose in
                content.rotationEffect(.degrees(pose.angle))
            }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        struct Pose { var angle = 0.0 }
        @MainActor func tree() -> some ElementGroup {
            Box().phaseAnimator([Pose(), Pose(angle: 4)]) { content, pose in
                content.rotationEffect(.degrees(pose.angle))
            }
        }
        """, importing: "MetalUI")
    print("""
        GS.PA2 phases: positive succeeded=\(positive.succeeded); negative succeeded=\(negative.succeeded) \
        messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 """
                 an Equatable phase must compile and a non-Equatable one must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 negative:
                 \(negative.output)
                 """)
}
