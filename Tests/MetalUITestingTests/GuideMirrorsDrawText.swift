import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// DT lane 1 — the mirror of the `drawText` block of `docs/guides/drawing-and-gpu.md` (item DT; `DT-A`, `DG-C`,
// `DG-D`): copied BY HAND between the `// guide:` and `// end guide` markers, byte for byte, so the ordinary build
// compiles it on every platform; `GuideDocCheck.swift` compares it with the guide. Below it, the test the guide pins.
// Mutation: delete the `context.drawText` line from the block (the sink records nothing).

// guide: drawing-and-gpu #9
/// A gauge whose label is part of the surface: drawn into the target, over the app's own fill.
struct DrawingGauge: Component {
    let reading: Int
    @Environment(\.textMeasurer) var measurer

    var content: some ElementGroup {
        let label = measurer.resolve(Text("\(reading) mm"))
        GPUSurface(redraw: .onDemand, value: reading) { context in
            context.clear(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
            context.drawText(label, at: Point(x: Pixels(8), y: Pixels(6)), anchor: .topLeading)
        }
        .frame(width: Pixels(120), height: Pixels(40))
    }
}
// end guide

/// A surface context with a real sink and the clear recorded, so the guide's closure can run headless.
@MainActor private final class GuideContext: GPUSurfaceContext, SurfaceTextSinkProviding {
    let sink: SurfaceTextSink
    var order: [String] = []
    init(atlas: GlyphAtlas) { sink = SurfaceTextSink(atlas: atlas) }
    var pixelSize: Size<DevicePixels> { Size(width: DevicePixels(120), height: DevicePixels(40)) }
    var scaleFactor: Float { 1 }
    var time: Double { 0 }
    var frameIndex: UInt64 { 0 }
    var isNewTarget: Bool { true }
    var textSink: SurfaceTextSink? { sink }
    func clear(red: Float, green: Float, blue: Float, alpha: Float) { order.append("clear") }
}

/// The guide's gauge records its label after the app's own clear: the headless renderer keeps the request,
/// the test runs the closure on a context of its own, and the sink holds the label's glyphs (a `Text` of the
/// same string draws as many) with the clear first. Mutation: delete the `drawText` line from the block.
@Test @MainActor func theDrawingGuideASurfaceDrawsItsOwnLabel() throws {
    let window = try harnessWindow { VStack { DrawingGauge(reading: 12) } }
    window.tick()
    let request = try #require(window.platformWindow.headlessRenderer.lastSurfaceRequests.first,
                               "the surface asked for a draw")
    let context = GuideContext(atlas: GlyphAtlas(width: 512, height: 512))
    context.sink.beginSurface(request.target.id)
    request.draw(context)
    let control = try harnessWindow { VStack { Text("12 mm") } }
    #expect(context.order == ["clear"], "the app's own fill ran")
    #expect(!context.sink.glyphs.isEmpty, "the label was recorded")
    #expect(context.sink.glyphs.count == control.scene.glyphs.count,
            "as many sprites as a Text of the string: \(context.sink.glyphs.count) vs \(control.scene.glyphs.count)")
}
