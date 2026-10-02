import Testing
import MetalUITestSupport

// MetalView lane 2, guard G2.1 (rulings `MV-A` item 2, `MV-F` item 4; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §8). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN `import MetalUI` — a
// `@testable` test cannot prove what an external module can write (practices
// shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MV-A MetalView spellings` to know
// this one ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1** (`MV-A` item 2, `MV-F` item 4). `MetalView(redraw:draw:)` and
/// `MetalView(redraw:value:draw:)` compile from a plain `import MetalUI` (which
/// re-exports `MetalUIRender`, so `MetalDrawContext` is visible) with app code
/// importing `Metal` itself to encode: the typed context's `device`,
/// `commandBuffer`, `target`, `renderPassDescriptor(loadAction:clearColor:)`
/// and the portable members, under the proposal modifiers. **Negative**: app
/// code cannot construct a `MetalDrawContext` — only the renderer hands one
/// out, so a draw cannot be handed a forged buffer or target.
///
/// Mutation once red: misspell `renderPassDescriptor` in the positive fixture.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theMetalViewSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import Metal
        import MetalUICore

        @MainActor func encode(_ ctx: MetalDrawContext) {
            let device: any MTLDevice = ctx.device
            let target: any MTLTexture = ctx.target
            let pass = ctx.renderPassDescriptor(loadAction: .clear,
                                                clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1))
            if let encoder = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                encoder.endEncoding()
            }
            let size: Size<DevicePixels> = ctx.pixelSize
            if ctx.isNewTarget || size.width.value > 0 || ctx.time > 0 || ctx.frameIndex > 0
                || ctx.scaleFactor > 1 || target.width > 0 || device.name.isEmpty {
                ctx.clear(red: 0, green: 0, blue: 0, alpha: 0)
            }
            _ = ctx.renderPassDescriptor()
        }

        @MainActor func tree(version: Int) -> some ProposalElementGroup {
            HStack {
                MetalView(redraw: .continuous) { ctx in encode(ctx) }
                    .clipShape(RoundedRectangle(cornerRadius: Pixels(12)))
                    .onTapGesture {}
                MetalView(value: version) { _ in }.frame(width: Pixels(40), height: Pixels(30))
                MetalView { _ in }
            }
        }
        """, importing: "MetalUI")
    let forged = try typecheckFile("""
        import Metal
        import MetalUICore

        @MainActor func forge(_ device: any MTLDevice, _ buffer: any MTLCommandBuffer,
                              _ texture: any MTLTexture) -> MetalDrawContext {
            MetalDrawContext(device: device, commandBuffer: buffer, target: texture,
                             pixelSize: Size(width: DevicePixels(1), height: DevicePixels(1)),
                             scaleFactor: 1, time: 0, frameIndex: 0, isNewTarget: true)
        }
        """, importing: "MetalUI")

    print("""
        MV-A MetalView spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        forged succeeded=\(forged.succeeded) messages=[\(forged.messages)]
        """)

    try #require(spellings.succeeded && !forged.succeeded,
                 """
                 the spellings must compile and a forged context must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 forged:
                 \(forged.output)
                 """)
    #expect(forged.messages.contains("MetalDrawContext") || forged.messages.contains("initializer"),
            "refused FOR the initialiser:\n\(forged.output)")
}
