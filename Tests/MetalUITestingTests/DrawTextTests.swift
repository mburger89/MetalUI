import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Round 2 item 5 (`DT-A`...`DT-J`, record 141): `GPUSurfaceContext.drawText`, text drawn into a GPU
// surface. Portable: a `HeadlessWindowRenderer` never runs a surface draw (`DT-F`), so these tests call
// `drawText` on a `package` fake context that holds a real `SurfaceTextSink` and compare the sink's
// `MUIGlyph` records with the records a `TestWindow` frame's scene holds for the same `Text`. Noto Sans
// through `harnessWindow`, so a literal agrees on every platform.

@MainActor private final class ResolvedBox {
    var value: TextMeasurer.ResolvedText?
}

/// Resolves `text` through the measurer at its reading point while its body builds.
private struct Capturing: Component {
    let box: ResolvedBox
    let text: Text
    @Environment(\.textMeasurer) var measurer
    var content: some ElementGroup {
        let _ = box.value = measurer.resolve(text)
        Box().frame(width: 1, height: 1)
    }
}

/// A surface context with a real sink and nothing else (the portable twin of `MetalDrawContext`).
@MainActor private struct SinkContext: GPUSurfaceContext, SurfaceTextSinkProviding {
    let sink: SurfaceTextSink?
    var scale: Float = 1
    var pixelSize = Size(width: DevicePixels(400), height: DevicePixels(300))
    var scaleFactor: Float { scale }
    var time = 0.0
    var frameIndex: UInt64 = 0
    var isNewTarget = true
    package var textSink: SurfaceTextSink? { sink }
    func clear(red: Float, green: Float, blue: Float, alpha: Float) {}
}

@MainActor private func makeSink() -> SurfaceTextSink {
    let sink = SurfaceTextSink(atlas: GlyphAtlas(width: 1024, height: 1024))
    sink.beginSurface(SurfaceID(rawValue: 1))
    return sink
}

private let unbounded = Size(width: Pixels.infinity, height: Pixels.infinity)

private let long = "alpha beta gamma delta epsilon zeta eta theta"

/// (x, y, w, h, atlas w, atlas h) of a glyph record: the destination and the slot's size.
private func shape(_ g: MUIGlyph) -> [Float] {
    [g.bounds.origin.x, g.bounds.origin.y, g.bounds.size.width, g.bounds.size.height,
     g.atlasBounds.size.width, g.atlasBounds.size.height]
}

private func colour(_ g: MUIGlyph) -> [Float] { [g.color.h, g.color.s, g.color.l, g.color.a] }

/// The glyph records of a window frame holding one `Text`, the `Text`'s frame (points) and a resolved copy.
@MainActor private func textFrame(_ text: Text, scaleFactor: Float = 1, colorScheme: ColorScheme = .light)
    throws -> (glyphs: [MUIGlyph], frame: Bounds<Pixels>, resolved: TextMeasurer.ResolvedText) {
    let box = ResolvedBox()
    let window = try harnessWindow(colorScheme: colorScheme, scaleFactor: scaleFactor) {
        VStack(spacing: 0) {
            Capturing(box: box, text: text)
            text.id("t")
        }
    }
    window.tick()
    return (window.scene.glyphs, try window.frame(ofID: "t"), try #require(box.value))
}

/// **1** (`DT-C`). The glyph records `drawText` records are the records a `Text` at the same device
/// position emits: destination rects and slot sizes, glyph for glyph, at scale 1 and 2.
/// Mutation: place with a rounded-point origin instead of the `Text.paint` call's `origin`/`scaleFactor`.
@Test @MainActor func drawTextEmitsTheGlyphRecordsATextEmitsAtTheSameDevicePosition() throws {
    for scale: Float in [1, 2] {
        let (glyphs, frame, resolved) = try textFrame(Text(long), scaleFactor: scale)
        try #require(!glyphs.isEmpty, "set up: the window drew glyphs")
        let sink = makeSink()
        SinkContext(sink: sink, scale: scale).drawText(resolved, at: frame.origin, anchor: .topLeading,
                                                         width: nil)
        // The `Capturing` box is 1 x 1 and draws no glyph, so the window's glyphs are the `Text`'s.
        #expect(sink.glyphs.count == glyphs.count, "scale \(scale): \(sink.glyphs.count) vs \(glyphs.count)")
        #expect(sink.glyphs.map(shape) == glyphs.map(shape), "scale \(scale): the same sprites")
        #expect(sink.glyphs.map(colour) == glyphs.map(colour), "scale \(scale): the same colour")
        #expect(sink.batches.map(\.range) == [0..<sink.glyphs.count], "one batch for the one surface")
    }
}

/// **1b** (`DT-C`). A fractional point keeps its fraction: the sub-pixel part of the origin reaches
/// `placeGlyphs` (as `Text.paint`'s origin does), so two points half a device pixel apart record different
/// sprites. Mutation: place with a rounded-point origin.
@Test @MainActor func aFractionalPointKeepsItsSubPixelPhase() throws {
    let (_, frame, resolved) = try textFrame(Text(long), scaleFactor: 2)
    func sprites(dx: Float) -> [[Float]] {
        let sink = makeSink()
        SinkContext(sink: sink, scale: 2).drawText(
            resolved, at: Point(x: Pixels(frame.origin.x.value + dx), y: frame.origin.y),
            anchor: .topLeading, width: nil)
        return sink.glyphs.map(shape)
    }
    let whole = sprites(dx: 0), half = sprites(dx: 0.25)
    #expect(!whole.isEmpty && whole.count == half.count, "set up: same glyph count")
    #expect(whole != half, "a quarter point (half a device pixel at scale 2) moves the sprites")
}

/// **2** (`DT-D`, probe B). Every anchor places the layout box at the point: the ink's top-left moves by
/// the anchor's fraction of the measured size. Mutation: swap the anchor's x and y fractions.
@Test @MainActor func everyAnchorPlacesTheLayoutBoxAtThePoint() throws {
    let (_, _, resolved) = try textFrame(Text("Gauge 42"))
    let size = resolved.measure(in: unbounded)
    try #require(size.width != size.height, "set up: a non-square box separates x from y")
    let origin = Point(x: Pixels(100), y: Pixels(60))
    func first(_ anchor: UnitPoint) -> MUIGlyph? {
        let sink = makeSink()
        SinkContext(sink: sink).drawText(resolved, at: origin, anchor: anchor, width: nil)
        return sink.glyphs.first
    }
    let base = try #require(first(.topLeading))
    let anchors: [UnitPoint] = [.topLeading, .top, .topTrailing, .leading, .center, .trailing,
                                .bottomLeading, .bottom, .bottomTrailing]
    for anchor in anchors {
        let g = try #require(first(anchor))
        let dx = Float(anchor.x) * size.width.value, dy = Float(anchor.y) * size.height.value
        #expect(abs((base.bounds.origin.x - g.bounds.origin.x) - dx) <= 1, "x of \(anchor): \(dx)")
        #expect(abs((base.bounds.origin.y - g.bounds.origin.y) - dy) <= 1, "y of \(anchor): \(dy)")
    }
}

/// **3** (`DT-D`, probe C). A finite `width` wraps (lines and height equal a `Text` framed that wide) and
/// nil is unbounded (one line). Mutation: ignore `width`.
@Test @MainActor func aFiniteWidthWrapsAndNilIsUnbounded() throws {
    let (_, frame, resolved) = try textFrame(Text(long))
    let line = resolved.measure(in: unbounded).height.value
    func rows(_ width: Pixels?) -> Int {
        let sink = makeSink()
        SinkContext(sink: sink).drawText(resolved, at: frame.origin, anchor: .topLeading, width: width)
        // A glyph's top varies with its ink; two lines are a line height apart, so split at gaps over half of it.
        let tops = sink.glyphs.map(\.bounds.origin.y).sorted()
        return 1 + zip(tops, tops.dropFirst()).filter { $1 - $0 > line * 0.45 }.count
    }
    #expect(rows(nil) == 1, "unbounded is one line")
    let narrow = rows(Pixels(60))
    #expect(narrow >= 3, "a 60 pt width wraps: \(narrow) rows of \(line) pt")
    let measured = resolved.measure(in: Size(width: Pixels(60), height: .infinity))
    #expect(measured.height.value >= line * 2, "set up: the measure wraps too")
    #expect(narrow == Int((measured.height.value / line).rounded()), "as many rows as the measured lines")
}

/// **4** (`DT-J`). The colour is the resolved foreground at the reading point's theme and scheme unless
/// `color:` overrides it. A token colour under a dark scheme equals the dark `Text`'s record.
/// Mutation: resolve against the default (light) theme.
@Test @MainActor func theColourIsTheResolvedForegroundUnlessOverridden() throws {
    let dark = try textFrame(Text("Tone"), colorScheme: .dark)
    let light = try textFrame(Text("Tone"), colorScheme: .light)
    try #require(colour(try #require(dark.glyphs.first)) != colour(try #require(light.glyphs.first)),
                 "set up: the token resolves differently by scheme")
    let sink = makeSink()
    SinkContext(sink: sink).drawText(dark.resolved, at: dark.frame.origin, anchor: .topLeading)
    #expect(sink.glyphs.map(colour) == dark.glyphs.map(colour), "the dark scheme's own foreground")

    let tint = Color(red: 0.2, green: 0.6, blue: 0.4)
    let expected = try textFrame(Text("Tone").foregroundColor(tint), colorScheme: .dark)
    let overridden = makeSink()
    SinkContext(sink: overridden).drawText(dark.resolved, at: dark.frame.origin, anchor: .topLeading, color: tint)
    #expect(overridden.glyphs.map(colour) == expected.glyphs.map(colour), "an explicit colour wins")
}

/// **5a** (`DT-E`). A rich resolved text traps naming the ruling. Mutation: replace the precondition by a
/// silent return.
@Test @MainActor func aRichResolvedTextTrapsNamingDTE() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let box = ResolvedBox()
            guard let window = try? harnessWindow({ VStack { Capturing(box: box, text: Text("a **b** c")) } }) else { return }
            window.tick()
            guard let resolved = box.value else { return }
            SinkContext(sink: makeSink()).drawText(resolved, at: Point(x: Pixels(0), y: Pixels(0)))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("DT-E"), "the trap names the ruling: \(stderr)")
}

/// **5b** (`DT-F`). A context with no sink traps naming the ruling. Mutation: replace the precondition by
/// a silent return.
@Test @MainActor func aContextWithoutASinkTrapsNamingDTF() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let box = ResolvedBox()
            guard let window = try? harnessWindow({ VStack { Capturing(box: box, text: Text("x")) } }) else { return }
            window.tick()
            guard let resolved = box.value else { return }
            SinkContext(sink: nil).drawText(resolved, at: Point(x: Pixels(0), y: Pixels(0)))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("DT-F"), "the trap names the ruling: \(stderr)")
}

/// **6** (`DT-F`). The headless renderer records a surface request and never runs its draw: no text is
/// recorded and `lastSurfaceRequests` is the one request. Mutation: run the draw in `finishFrame`.
@Test @MainActor func aHeadlessRendererRecordsButNeverRunsASurfaceDraw() throws {
    final class Ran { var count = 0 }
    let ran = Ran()
    let window = try harnessWindow {
        GPUSurface(redraw: .continuous) { _ in ran.count += 1 }.frame(width: Pixels(40), height: Pixels(20))
    }
    window.tick()
    #expect(ran.count == 0, "a headless frame never runs the app's draw")
    #expect(window.platformWindow.headlessRenderer.lastSurfaceRequests.count == 1, "but it records the request")
}
