import Testing
import MetalUITestSupport

// C27 lane A, guards 3-4 (ruling `MT-B`, `MT-C`). Whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import. **A guard skips silently
// when `.build/<triple>/debug/Modules` is absent**; grep the log for
// `MT-B tint read` to know it ran.

private let tintSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Guard 3** (`MT-B`). `Material.tint(in:)` is spellable from an external module.
/// Mutation once red: narrow the method to `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), tintSkipReason))
func materialTintInIsReachableFromAPlainImport() throws {
    let r = try typecheckFile("""
        import MetalUI

        func read(_ scheme: ColorScheme) -> Color {
            Material.regularMaterial.tint(in: scheme)
        }
        """, importing: "MetalUI")
    print("MT-B tint read: succeeded=\(r.succeeded) messages=[\(r.messages)]")
    try #require(r.succeeded, "the public read must compile:\n\(r.output)")
}

/// **Guard 4** (`MT-C`). A material takes no colour and cannot be constructed from
/// outside; the positive control (the read) compiles in the same file shape.
/// Mutation once red: add a public `Material.tint(_:)`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), tintSkipReason))
func aMaterialCannotTakeAColourOrBeConstructed() throws {
    let control = try typecheckFile("""
        import MetalUI

        func read() -> Color { Material.bar.tint(in: .dark) }
        """, importing: "MetalUI")
    let tinted = try typecheckFile("""
        import MetalUI

        func make() -> Material { Material.bar.tint(Color.red) }
        """, importing: "MetalUI")
    let built = try typecheckFile("""
        import MetalUI

        func make() -> Material { Material(kind: .bar) }
        """, importing: "MetalUI")
    print("""
        MT-C material surface: control succeeded=\(control.succeeded); \
        tinted succeeded=\(tinted.succeeded) messages=[\(tinted.messages)]; \
        built succeeded=\(built.succeeded) messages=[\(built.messages)]
        """)
    try #require(control.succeeded && !tinted.succeeded && !built.succeeded,
                 "control compiles, both refused spellings do not, or this guard cannot fail:\n\(control.output)\n\(tinted.output)\n\(built.output)")
}
