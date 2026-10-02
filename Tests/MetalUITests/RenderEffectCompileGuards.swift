import Testing
import MetalUITestSupport

// Paths, shadows and transforms, lane 2, guard G2.1 (ruling `GX-H`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import —
// a `@testable` test cannot prove what an external module can write
// (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `GX-H spellings` to know it ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1** (`GX-H`). The render-effect spellings compile under a plain
/// `import MetalUI` on both vocabularies — `rotationEffect(_:anchor:)`, the
/// three `scaleEffect` forms, both `offset` forms, `Angle`'s constructors and
/// arithmetic — and an exhaustive `switch` over `LayoutModifier` names the three
/// new cases. **Negative**: `transformEffect` is not offered (spec §9).
///
/// Mutation once red (**MG2.1**): one spelling made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theRenderEffectSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import MetalUICore
        import MetalUILayout

        @MainActor func proposal() -> some ProposalElementGroup {
            VStack {
                Color(.accent).frame(width: Pixels(40), height: Pixels(20))
                    .rotationEffect(.degrees(30), anchor: .topLeading)
                    .scaleEffect(2)
                    .scaleEffect(SizeD(width: 2, height: 0.5), anchor: .bottom)
                    .scaleEffect(x: -1)
                    .offset(x: Pixels(3), y: Pixels(4))
                    .offset(Size(width: Pixels(1), height: Pixels(2)))
                Color(.separator).rotationEffect(Angle(radians: 1) + .degrees(10) * 2)
            }
        }

        @MainActor func legacy() -> some StyledElement {
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .rotationEffect(-Angle.degrees(45))
                .scaleEffect(0.5, anchor: .center)
                .scaleEffect(SizeD(width: 1, height: 2))
                .scaleEffect(x: 2, y: 1)
                .offset(x: Pixels(5))
                .offset(Size(width: Pixels(0), height: Pixels(1)))
        }

        func describe(_ m: LayoutModifier) -> String {
            switch m {
            case .rotationEffect(let a, let anchor): return "\\(a.degrees) \\(anchor.x)"
            case .scaleEffect(let x, let y, _): return "\\(x) \\(y)"
            case .offset(let x, let y): return "\\(x.value) \\(y.value)"
            default: return ""
            }
        }

        let ordered = Angle.zero < Angle.radians(1)
        """, importing: "MetalUI")
    let transformEffect = try typecheckFile("""
        @MainActor func tree() -> some ProposalElementGroup {
            Color(.accent).transformEffect(.identity)
        }
        """, importing: "MetalUI")

    print("""
        GX-H spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        transformEffect succeeded=\(transformEffect.succeeded) messages=[\(transformEffect.messages)]
        """)

    try #require(spellings.succeeded && !transformEffect.succeeded,
                 """
                 the spellings must compile and transformEffect must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 transformEffect:
                 \(transformEffect.output)
                 """)
    #expect(transformEffect.messages.contains("transformEffect"),
            "refused FOR transformEffect:\n\(transformEffect.output)")
}
