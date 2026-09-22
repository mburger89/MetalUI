import Testing
import MetalUITestSupport

// Compile-time guards for `docs/superpowers/specs/2026-09-22-portable-scene-design.md`.
// Moving `FontKey` and `GlyphImage` into `MetalUIScene` (ruling PS-A) put each
// one's only producer in another module, so the initialisers that were
// internal became `package` (PS-D, PS-E). `package` is invisible outside this
// Swift package; these guards pin that an external module still cannot build
// either type by hand.
//
// **Every fixture uses `typecheckFile`** against a PLAIN `import MetalUIText`,
// as an external module writes it; `typecheckFile` compiles with no
// `-package-name`, which is exactly an outside module's view. A `@testable` or
// same-package test sees `package` declarations and cannot demonstrate this
// (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIText not found — guard skipped"

/// **No module outside the package can spell a `FontKey` by hand** (PS-D).
///
/// The negative takes `variations` and `matrix` off a real key, so the only
/// thing it can be refused for is the initialiser itself; the control is the
/// one public path, `init(resolved:)`, in the same file shape.
@Test(.enabled(if: canTypecheck(module: "MetalUIText"), skipReason))
func anExternalModuleCannotSpellAFontKeyByHand() throws {
    let byHand = try typecheckFile("""
        import CoreText
        func probe(_ real: FontKey) -> FontKey {
            FontKey(resolvedPostScriptName: "Helvetica", size: 13,
                    variations: real.variations, matrix: real.matrix)
        }
        """, importing: "MetalUIText")
    let control = try typecheckFile("""
        import CoreText
        func probe() -> FontKey {
            FontKey(resolved: CTFontCreateWithName("Helvetica" as CFString, 13, nil))
        }
        """, importing: "MetalUIText")

    print("""
        PS-D FontKey by hand: byHand succeeded=\(byHand.succeeded) \
        messages=[\(byHand.messages)]; control succeeded=\(control.succeeded) \
        messages=[\(control.messages)]
        """)

    try #require(control.succeeded && !byHand.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 control:
                 \(control.output)
                 byHand:
                 \(byHand.output)
                 """)
    // With the `package` init invisible, the compiler matches the call against
    // `init(resolved:)` and reports the labels as extra arguments; a visible
    // but inaccessible init would say so instead. Either is the initialiser.
    #expect(byHand.messages.contains("extra arguments") || byHand.messages.contains("inaccessible"),
            "the negative must be rejected FOR THE INITIALISER:\n\(byHand.output)")
}

/// **No module outside the package can make a `GlyphImage`** (PS-E): only
/// `GlyphRaster` can make its bytes and bearings agree. The control reads the
/// type's public surface, so the pair disagrees only about construction.
@Test(.enabled(if: canTypecheck(module: "MetalUIText"), skipReason))
func anExternalModuleCannotMakeAGlyphImage() throws {
    let made = try typecheckFile("""
        func probe() -> GlyphImage { GlyphImage(width: 1, height: 1, bytes: [255]) }
        """, importing: "MetalUIText")
    let control = try typecheckFile("""
        func probe(_ image: GlyphImage) -> Int { image.width * image.height + image.left }
        """, importing: "MetalUIText")

    print("""
        PS-E GlyphImage init: made succeeded=\(made.succeeded) \
        messages=[\(made.messages)]; control succeeded=\(control.succeeded) \
        messages=[\(control.messages)]
        """)

    try #require(control.succeeded && !made.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 control:
                 \(control.output)
                 made:
                 \(made.output)
                 """)
    #expect(made.messages.contains("GlyphImage"),
            "the negative must be rejected FOR THE INITIALISER:\n\(made.output)")
}
