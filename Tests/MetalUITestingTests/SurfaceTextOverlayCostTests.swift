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

@Test @MainActor func measureTheOverlayCost() throws {
    for (n, distinct) in [(0, true), (20, true), (100, true), (20, false), (100, false)] {
        let model = CameraModel()
        let counting = CountingTextSystem(harnessTextSystem())
        let window = try overlayWindow(labels: n, distinct: distinct, model: model, counting: counting)
        for _ in 0..<2 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() } // warm
        counting.reset()
        window.resetFrameWork()
        for _ in 0..<5 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
        let w = window.frameWork
        let sum = w.dropFirst().reduce(w[0], +)
        print("C23 n=\(n) distinct=\(distinct) per-frame: builds=\(sum.builds / 5) measureCalls=\(sum.layoutMeasureCalls / 5) hits=\(sum.layoutCacheHits / 5) misses=\(sum.layoutCacheMisses / 5) glyphs=\(sum.glyphs / 5) atlasUpload=\(sum.atlasUploadPixels / 5) | textSystem measure=\(counting.measures / 5) place=\(counting.places / 5) styled=\(counting.styledMeasures / 5) layOut=\(counting.layouts / 5) raster=\(counting.rasters / 5)")
    }
}
