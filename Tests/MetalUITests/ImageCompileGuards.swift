import Testing
import MetalUITestSupport

// Compile-time guard for plan task 11, part 2, lane 3 (spec
// `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §8 lane 3,
// G3.2; rulings `TE-AL`, `TE-AQ` item 9). G3.1, the grid anchor's guard, is in
// `GridCompileGuards.swift`.
//
// **`typecheckFile`** — whole-file, Swift 6, a PLAIN `import MetalUI`, as an
// external module writes it (`SA-P`; practices shape 16). **A guard skips
// silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.2 — `Image` has no system-name or asset initialiser** (spec §9: SF
/// Symbols are out of the task's scope, and there is no asset catalog).
/// `Image(systemName:)` and `Image("name")` each fail to compile; **control**:
/// `Image(decorative:scale:)` over an `ImageBitmap`, resizable, with an
/// interpolation, compiles — so the two failures are about the initialisers,
/// not a broken fixture.
///
/// Mutation: **MG3b** an `init(systemName:)` stub added to `Image` (the first
/// arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anImageHasNoSystemNameOrAssetInitialiser() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() {
            let bitmap = ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255])
            _ = Image(decorative: bitmap, scale: 2).resizable().interpolation(.none)
        }
        """, importing: "MetalUI")
    let systemName = try typecheckFile("""
        @MainActor public func bad() { _ = Image(systemName: "star") }
        """, importing: "MetalUI")
    let asset = try typecheckFile("""
        @MainActor public func bad() { _ = Image("star") }
        """, importing: "MetalUI")

    print("""
        G3.2 Image initialisers: control succeeded=\(control.succeeded) messages=[\(control.messages)]; \
        systemName succeeded=\(systemName.succeeded) messages=[\(systemName.messages)]; \
        asset succeeded=\(asset.succeeded) messages=[\(asset.messages)]
        """)

    try #require(control.succeeded, "the positive control must compile:\n\(control.output)")
    #expect(!systemName.succeeded, "Image(systemName:) must not compile:\n\(systemName.output)")
    #expect(systemName.messages.contains("systemName"),
            "rejected, but not for the systemName: initialiser:\n\(systemName.output)")
    #expect(!asset.succeeded, "Image(_: String) must not compile:\n\(asset.output)")
    #expect(asset.messages.contains("Image") || asset.messages.contains("decorative"),
            "rejected, but not for the initialiser:\n\(asset.output)")
}
