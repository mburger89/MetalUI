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

/// **G3.2 (record 230: SF Symbols are offered, assets are not) - `Image` has a system-name initialiser but no asset one.**
/// `Image(systemName:)` compiles from a plain import; `Image("name")` (an asset name) does not; **control**:
/// `Image(decorative:scale:)` over an `ImageBitmap`, resizable, with an interpolation, compiles - so the failure is about
/// the initialiser, not a broken fixture.
///
/// Mutations: **MG3b** `init(systemName:)` deleted (the second arm stops compiling); **MG3c** an `init(_ name: String)`
/// added (the asset arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anImageHasASystemNameButNoAssetInitialiser() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() {
            let bitmap = ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255])
            _ = Image(decorative: bitmap, scale: 2).resizable().interpolation(.none)
        }
        """, importing: "MetalUI")
    let systemName = try typecheckFile("""
        @MainActor public func ok() { _ = Image(systemName: "star") }
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
    #expect(systemName.succeeded, "Image(systemName:) must compile from a plain import:\n\(systemName.output)")
    #expect(!asset.succeeded, "Image(_: String) must not compile:\n\(asset.output)")
    #expect(asset.messages.contains("systemName") || asset.messages.contains("decorative"),
            "rejected, but not for the initialiser:\n\(asset.output)")
}

/// **SYM-B - every symbol spelling compiles from a plain import**: `Image(systemName:)`, `Image.symbolRenderingMode(_:)`, the
/// `imageScale`, `symbolRenderingMode` and `symbolVariant` modifiers, `Image.Scale`'s cases, `SymbolRenderingMode`'s three
/// cases, `SymbolVariants`' statics, chains and `contains`, and the `imageScale` and `symbolVariants` environment values.
/// **Negatives**: `.palette` is not offered (`SYM-M`); `symbolRenderingMode` is no public environment key. Mutation: **MS2**
/// one modifier made `internal` (the first arm stops compiling).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everySymbolSpellingCompilesFromAPlainImport() throws {
    let positive = try typecheckFile("""
        @MainActor public func ok(_ values: EnvironmentValues) {
            let scales: [Image.Scale] = [.small, .medium, .large]
            let modes: [SymbolRenderingMode] = [.monochrome, .hierarchical, .multicolor]
            let variants: [SymbolVariants] = [.none, .fill, .circle, .square, .rectangle, .slash, .circle.fill, .slash.fill.circle]
            _ = (scales, modes, variants, variants[0].contains(.fill), values.imageScale, values.symbolVariants)
            _ = Image(systemName: "star").symbolRenderingMode(.hierarchical).resizable()
            _ = Image(systemName: "star").imageScale(.large).symbolVariant(.circle.fill).symbolRenderingMode(.multicolor)
            _ = Image(systemName: "star").symbolRenderingMode(nil)
        }
        """, importing: "MetalUI")
    let palette = try typecheckFile("""
        @MainActor public func bad() { _ = Image(systemName: "star").symbolRenderingMode(.palette) }
        """, importing: "MetalUI")
    let key = try typecheckFile("""
        @MainActor public func bad(_ values: EnvironmentValues) { _ = values.symbolRenderingMode }
        """, importing: "MetalUI")
    print("SYM-B spellings: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; palette succeeded=\(palette.succeeded); key succeeded=\(key.succeeded)")
    try #require(positive.succeeded, "every symbol spelling must compile:\n\(positive.output)")
    #expect(!palette.succeeded && palette.messages.contains("palette"), "`.palette` must not exist:\n\(palette.output)")
    #expect(!key.succeeded && key.messages.contains("symbolRenderingMode"), "no public environment key:\n\(key.output)")
}
