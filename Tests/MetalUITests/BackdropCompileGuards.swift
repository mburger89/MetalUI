import Testing
import MetalUITestSupport

// Backdrop blur, lane 1, guard 1.13 (rulings `BB-A`, `BB-L`, `BB-P`; spec
// `docs/superpowers/specs/2026-10-10-backdrop-blur-design.md` §1). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against PLAIN imports: what an
// external module can write. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the
// log for `BB-A primitive kinds` to know it ran.

private let backdropSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.13** (`BB-A`, `BB-L`, `BB-P`). `PrimitiveKind` and `LayoutModifier`
/// each gained a case, which is a public break: an exhaustive `switch` that
/// names the old cases does not compile, and the same switch with the new arm
/// does. The record is spellable from outside (`MUIBackdrop`'s memberwise
/// initialiser, `Scene.insert`, `Scene.backdropRegion`).
///
/// Mutation once red: delete the `.backdrop` arm from the positive fixture
/// (the fixture then fails for exhaustiveness and `try #require` reddens).
@Test(.enabled(if: canTypecheck(module: "MetalUIScene"), backdropSkipReason))
func anExhaustiveSwitchOverPrimitiveKindNeedsABackdropArm() throws {
    let old = try typecheckFile("""
        import MetalUIScene

        func name(_ kind: PrimitiveKind) -> String {
            switch kind {
            case .rect, .glyph, .image, .surface: return "kind"
            }
        }
        """, importing: "MetalUIScene")
    let current = try typecheckFile("""
        import MetalUIScene
        import MetalUIShaderTypes

        func name(_ kind: PrimitiveKind) -> String {
            switch kind {
            case .rect, .glyph, .image, .surface: return "kind"
            case .backdrop: return "backdrop"
            }
        }

        func build() -> Scene.BackdropRegion? {
            var scene = Scene()
            let none = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 10, height: 10))
            let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
            scene.insert(MUIBackdrop(bounds: none, contentMask: none, maskCornerRadii: square, cornerRadii: square,
                                     tint: MUIHsla(h: 0, s: 0, l: 1, a: 0.5), order: 0, shape: 0, sigma: 52,
                                     opacity: 1))
            scene.finalize()
            return scene.backdropRegion(0, target: (width: 100, height: 100))
        }
        """, importing: "MetalUIScene")
    let modifier = try typecheckFile("""
        import MetalUI

        func name(_ m: LayoutModifier) -> String {
            switch m {
            case .backgroundMaterial: return "material"
            default: return "other"
            }
        }
        @MainActor func tree() -> some ProposalElementGroup {
            Color.clear.background(.ultraThinMaterial)
        }
        """, importing: "MetalUI")

    print("""
        BB-A primitive kinds: old succeeded=\(old.succeeded) messages=[\(old.messages)]; \
        current succeeded=\(current.succeeded) messages=[\(current.messages)]; \
        modifier succeeded=\(modifier.succeeded) messages=[\(modifier.messages)]
        """)

    try #require(current.succeeded && modifier.succeeded && !old.succeeded,
                 """
                 the new spellings must compile and the old exhaustive switch must not, \
                 or this guard cannot fail:
                 current:
                 \(current.output)
                 modifier:
                 \(modifier.output)
                 old:
                 \(old.output)
                 """)
    #expect(old.messages.contains("exhaustive"), "refused FOR exhaustiveness:\n\(old.output)")
}
