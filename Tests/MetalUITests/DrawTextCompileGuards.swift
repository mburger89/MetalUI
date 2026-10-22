import Testing
import MetalUITestSupport

// Round 2 item 5 (`DT-D`, `DT-F`; record 141): whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a
// PLAIN `import MetalUI` — a `@testable` test cannot prove what an external module can write.
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**; grep the log for
// `DT-D drawText` / `DT-F sink` to know these ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G12a** (`DT-D`). `drawText` compiles from a plain import on `any GPUSurfaceContext` and on
/// `MetalDrawContext`, with every parameter. Mutation once red: make `drawText` `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func drawTextCompilesFromAPlainImport() throws {
    let result = try typecheckFile("""
        import MetalUICore

        struct Label: Component {
            @Environment(\\.textMeasurer) var measurer
            var content: some ElementGroup {
                let resolved = measurer.resolve(Text("12.5 mm"))
                GPUSurface(redraw: .onDemand) { (context: any GPUSurfaceContext) in
                    context.drawText(resolved, at: Point(x: Pixels(4), y: Pixels(3)))
                    context.drawText(resolved, at: Point(x: Pixels(4), y: Pixels(3)), anchor: .topLeading,
                                     width: Pixels(60), color: Color(red: 0.2, green: 0.4, blue: 0.6))
                }
                .frame(width: Pixels(80), height: Pixels(40))
            }
        }

        #if canImport(Metal)
        @MainActor func onMetal(_ context: MetalDrawContext, _ resolved: TextMeasurer.ResolvedText) {
            context.drawText(resolved, at: Point(x: Pixels(1), y: Pixels(2)), anchor: .bottomTrailing)
        }
        #endif
        """, importing: "MetalUI")
    print("DT-D drawText: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "drawText must compile from a plain import:\n\(result.output)")
}

/// **G12b** (`DT-F`). The sink and its context hook are `package`: a plain import cannot name them.
/// Mutation once red: make `SurfaceTextSink` `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSurfaceTextSinkIsUnreachableFromAPlainImport() throws {
    let result = try typecheckFile("""
        import MetalUIPlatform
        import MetalUIScene

        @MainActor func forge(_ atlas: GlyphAtlas) -> SurfaceTextSink {
            SurfaceTextSink(atlas: atlas)
        }
        """, importing: "MetalUI")
    print("DT-F sink: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    try #require(!result.succeeded, "a plain import must not reach the sink, or this guard cannot fail")
    #expect(result.messages.contains("SurfaceTextSink") || result.messages.contains("inaccessible")
            || result.messages.contains("package"), "refused FOR the sink:\n\(result.output)")
}
