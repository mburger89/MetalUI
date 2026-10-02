import Testing
import MetalUITestSupport

// MetalView lane 1, guards G1.1–G1.2 (rulings `MV-A`, `MV-F` item 1; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §8). Both fixtures
// are whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import
// — a `@testable` test cannot prove what an external module can write
// (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MV-A spellings`/`MV-F requirement`
// to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// **G1.1** (`MV-A`, `MV-G` item 1). The portable spellings compile under a
/// plain `import MetalUI`: `GPUSurface(redraw:draw:)` and
/// `GPUSurface(redraw:value:draw:)` in a proposal stack under the proposal
/// modifiers, `RedrawPolicy`'s two cases, and the context's portable members.
/// **Negative**: an `id:` parameter — the spec's sketch had one; identity is
/// structural and `.id(_:)` already works (`MV-A` item 3).
///
/// Mutation once red: misspell `RedrawPolicy.continuous` in the fixture.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theGPUSurfaceSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import MetalUICore

        @MainActor func draw(_ ctx: any GPUSurfaceContext) {
            let size: Size<DevicePixels> = ctx.pixelSize
            let seconds: Double = ctx.time
            let frame: UInt64 = ctx.frameIndex
            if ctx.isNewTarget || size.width.value > 0 || seconds > 0 || frame > 0 || ctx.scaleFactor > 1 {
                ctx.clear(red: 0, green: 0, blue: 0.2, alpha: 1)
            }
        }

        @MainActor func tree(version: Int) -> some ProposalElementGroup {
            HStack {
                GPUSurface(redraw: .continuous) { ctx in draw(ctx) }
                    .clipShape(RoundedRectangle(cornerRadius: Pixels(12)))
                    .onTapGesture {}
                GPUSurface(value: version) { _ in }.frame(width: Pixels(40), height: Pixels(30))
                GPUSurface { _ in }
            }
        }

        let policies: [RedrawPolicy] = [.onDemand, .continuous]
        """, importing: "MetalUI")
    let withID = try typecheckFile("""
        @MainActor func tree() -> some ProposalElementGroup {
            GPUSurface(id: "viewport") { _ in }
        }
        """, importing: "MetalUI")

    print("""
        MV-A spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        withID succeeded=\(withID.succeeded) messages=[\(withID.messages)]
        """)

    try #require(spellings.succeeded && !withID.succeeded,
                 """
                 the spellings must compile and an id: parameter must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 withID:
                 \(withID.output)
                 """)
    #expect(withID.messages.contains("id"), "refused FOR the id: label:\n\(withID.output)")
}

/// A `WindowRenderer` conformer with `beginFrame` and whatever `finishFrame`
/// the caller splices in.
private func renderer(member: String) -> String {
    """
    import MetalUIScene

    @MainActor
    final class Conformer: WindowRenderer {
        func beginFrame() -> Float? { nil }
    \(member)
    }
    """
}

/// **G1.2** (`MV-F` item 1). `WindowRenderer.finishFrame(scene:atlas:surfaces:)`
/// has **no default implementation** (`EV-AB`'s reason): a renderer that
/// implements only the old `finishFrame(scene:atlas:)` fails to compile rather
/// than drawing a blank viewport. **Positive control**: the same conformer
/// with the three-argument member — `MV-K` item 3's migration spelling —
/// compiles.
///
/// Mutation once red: a protocol-extension default in a scratch copy (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aWindowRendererWithoutTheSurfacesFinishFrameDoesNotCompile() throws {
    let without = try typecheckFile(renderer(member: """
            func finishFrame(scene: Scene, atlas: GlyphAtlas) -> Bool { true }
        """), importing: "MetalUIPlatform")
    let with = try typecheckFile(renderer(member: """
            func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool { true }
        """), importing: "MetalUIPlatform")

    print("""
        MV-F requirement: without succeeded=\(without.succeeded) \
        messages=[\(without.messages)]; with succeeded=\(with.succeeded) \
        messages=[\(with.messages)]
        """)

    try #require(with.succeeded && !without.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("finishFrame"),
            "the negative must be refused FOR finishFrame:\n\(without.output)")
}
