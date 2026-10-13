import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C23 step 1 (GT-A): what N world-anchored `Text` overlays over a `GPUSurface`
// cost per camera frame, counted at the text-system seam and in `FrameWork`.

/// A text system that counts the calls the frame makes, forwarding to a real one.
@MainActor final class CountingTextSystem: TextSystem {
    let base: any TextSystem
    var measures = 0, places = 0, layouts = 0, styledMeasures = 0, rasters = 0
    init(_ base: any TextSystem) { self.base = base }
    func reset() { measures = 0; places = 0; layouts = 0; styledMeasures = 0; rasters = 0 }
    func resolveFont(_ d: FontDescriptor) -> FontKey { base.resolveFont(d) }
    func fontMetrics(_ f: FontKey) -> TextFontMetrics { base.fontMetrics(f) }
    func measure(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions) -> TextMeasurement {
        measures += 1; return base.measure(s, font: font, wrappingAt: w, options: options)
    }
    func placeGlyphs(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        places += 1; return base.placeGlyphs(s, font: font, wrappingAt: w, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func caretOffsets(_ s: String, font: FontKey) -> [Double] { base.caretOffsets(s, font: font) }
    func lineRanges(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(s, font: font, wrappingAt: w, options: options)
    }
    func measure(_ t: StyledText, wrappingAt w: Double?, options: TextLayoutOptions) -> StyledTextMeasurement {
        styledMeasures += 1; return base.measure(t, wrappingAt: w, options: options)
    }
    func layOut(_ t: StyledText, wrappingAt w: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        layouts += 1; return base.layOut(t, wrappingAt: w, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ f: FontKey) -> TextDecorationMetrics { base.decorationMetrics(f) }
    func rasterize(_ k: GlyphKey) -> GlyphImage { rasters += 1; return base.rasterize(k) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

@MainActor final class CameraModel { var phase: Float = 0 }

@MainActor private func overlayWindow(labels n: Int, distinct: Bool, model: CameraModel,
                                      counting: CountingTextSystem) throws -> TestWindow {
    try TestWindow(size: sz(800, 600), textSystem: { counting }) {
        ZStack(alignment: .topLeading) {
            GPUSurface(redraw: .onDemand, value: model.phase) { _ in }
            ForEach(Array(0..<n), id: \.self) { i in
                Text(distinct ? "\(i).5 mm" : "12.5 mm")
                    .offset(x: Pixels(Float(i % 10) * 70 + model.phase), y: Pixels(Float(i / 10) * 20 + model.phase * 0.5))
            }
        }
    }
}

/// 1.10 — the C23 baseline (`GT-A`), for C14 to re-take: N moving `Text` labels
/// over a `GPUSurface` cost, per camera frame, one build, N + 1 leaf measures,
/// 2N text-system measures and N `placeGlyphs`, and no atlas upload, raster or
/// texture. **Expected to change when C14 lands; the change is the result.**
/// Mutation: a doubled `ForEach` reddens it.
@Test(arguments: [20, 100]) @MainActor func theOverlayCostIsLinearAndCounted(labels n: Int) throws {
    let model = CameraModel()
    let counting = CountingTextSystem(harnessTextSystem())
    let window = try overlayWindow(labels: n, distinct: true, model: model, counting: counting)
    for _ in 0..<2 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() } // warm
    counting.reset()
    window.resetFrameWork()
    let frames = 5
    for _ in 0..<frames { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
    let w = window.frameWork
    let sum = w.dropFirst().reduce(w[0], +)
    try #require(w.count == frames)
    #expect(sum.builds == frames)
    // Re-taken by C14 lane 1 (`IV-E`, GT-F): the labels' `.offset` registers no
    // layout node, so the frame is signature-identical to the last and the layout
    // memo answers it whole. What remains is paint's one seam measure and one
    // `placeGlyphs` per label (before: n + 1 leaf measures, 2n seam measures).
    #expect(sum.layoutMeasureCalls == 0)
    #expect(sum.layoutCacheHits == 0)
    #expect(sum.layoutCacheMisses == 0)
    #expect(sum.layoutMemoRootHits == frames)
    if !layoutMemoVerifying { #expect(counting.measures == frames * n) }
    #expect(counting.places == frames * n)
    #expect(sum.atlasUploadPixels == 0)
    #expect(sum.rasterizedPixels == 0)
    #expect(sum.newTextures == 0)
}
