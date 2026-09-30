import Testing
import MetalUITestSupport

// Plan task 13, lane 3, guard 3.19 (ruling `AN-AE` as amended by `AN-AH`
// item 1). Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN
// import — a `@testable` test cannot prove what an external module can spell
// (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AN-AE unsupported` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **3.19.** The unsupported transitions are **absent**, not inert:
/// `AnyTransition.blurReplace` does not compile from a plain import, while the
/// positive controls — `.opacity`, `.scale` and `.scale(scale:anchor:)`, and a
/// `.transition(_:)` on an element — do. The surface doc on `AnyTransition`
/// lists `.blurReplace` among the unsupported spellings; this guard keeps the
/// list honest, since a declared-but-inert `blurReplace` would compile and do
/// nothing.
///
/// Mutation **MG3.19**: add `public static let blurReplace = AnyTransition.opacity`
/// (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theUnsupportedTransitionsDoNotCompile() throws {
    let supported = try typecheckFile("""
        @MainActor func probe() -> [AnyTransition] {
            [.opacity, .scale, .scale(scale: 0.5, anchor: .topLeading), .identity, .slide,
             .move(edge: .leading), .offset(x: Pixels(3), y: Pixels(4)), .push(from: .top),
             .asymmetric(insertion: .opacity, removal: .scale), .opacity.combined(with: .slide)]
        }
        @MainActor func tree(_ flag: Bool) -> some Element {
            Column { if flag { Box().transition(.opacity) } }
        }
        """, importing: "MetalUI")
    let blur = try typecheckFile("""
        @MainActor func probe() -> AnyTransition { .blurReplace }
        """, importing: "MetalUI")

    print("""
        AN-AE unsupported: supported succeeded=\(supported.succeeded) \
        messages=[\(supported.messages)]; blurReplace succeeded=\(blur.succeeded) \
        messages=[\(blur.messages)]
        """)

    try #require(supported.succeeded && !blur.succeeded,
                 """
                 the supported spellings must compile and `.blurReplace` must not, or \
                 this guard cannot fail:
                 supported:
                 \(supported.output)
                 blurReplace:
                 \(blur.output)
                 """)
    #expect(blur.messages.contains("blurReplace"),
            "the negative must be refused FOR blurReplace:\n\(blur.output)")
}
