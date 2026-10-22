import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import MetalUIPortableText
@testable import MetalUI
@testable import MetalUISDL
import SDLBridge

// Round 2 item 5, lane 2 (`DT-A`, `DT-B`, `DT-G`; record 141): `drawText` on the SDL GPU renderer. A surface's
// draw calls `drawText` on the `SDLGPUDrawContext` the renderer hands it; the call records glyph sprites into
// the frame's `SurfaceTextSink`, and `mui_renderer_finish` runs one load-op pass per surface that recorded text
// after the atlas copy pass and before the scene's pass. The target is read back through the composite (a
// full-window surface quad over an opaque black background) from an offscreen `SDLWindowRenderer`, the
// existing readback of `SDLSurfaceTests`. No test sleeps; no presented window is needed, so the Linux image
// (lavapipe) runs all of them. Every helper arms the run-loop exit check (record §61 §9).

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

private let width = 96, height = 48

private let target = SurfaceTarget(id: SurfaceID(rawValue: 1), width: width, height: height)
private let otherTarget = SurfaceTarget(id: SurfaceID(rawValue: 2), width: width, height: height)

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
private let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)

private func background(_ scene: inout Scene) {
    let all = bounds(0, 0, Float(width), Float(height))
    scene.insert(MUIRect(bounds: all, contentMask: all, maskCornerRadii: corners(0),
                         background: black, borderColor: black, cornerRadii: corners(0),
                         borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0))
}

private func quad(_ box: MUIBounds, order: MUIUInt) -> MUIImage {
    MUIImage(bounds: box, contentMask: box, maskCornerRadii: corners(0), opacity: 1, texture: 0,
             filter: MUIUInt(MUIImageFilterLinear.rawValue), order: order)
}

/// Black background, then (optionally) glyphs the scene holds itself, then the surface quads over the whole window.
private func scene(surfaces: [SurfaceTarget], glyphs: [MUIGlyph] = []) -> Scene {
    var scene = Scene()
    background(&scene)
    for glyph in glyphs { scene.insert(glyph) }
    for (index, surface) in surfaces.enumerated() {
        scene.insert(quad(bounds(0, 0, Float(width), Float(height)), order: MUIUInt(index + 1)), surface: surface)
    }
    scene.finalize()
    return scene
}

/// The scene with glyphs only, no surface (the direct oracle).
private func glyphScene(_ glyphs: [MUIGlyph]) -> Scene {
    var scene = Scene()
    background(&scene)
    for glyph in glyphs { scene.insert(glyph) }
    scene.finalize()
    return scene
}

@MainActor
private func offscreenRenderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

@MainActor
private func frame(_ renderer: SDLWindowRenderer, _ scene: Scene, _ surfaces: [SurfaceDrawRequest],
                   atlas: GlyphAtlas) throws {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: atlas, surfaces: surfaces))
}

private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// A `ResolvedText` over the portable text system, as the frame's `@Environment(\.textMeasurer)` makes one.
@MainActor
private func resolved(_ string: String) throws -> TextMeasurer.ResolvedText {
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    var environment = EnvironmentValues()
    environment.textSystemBox = TextSystemBox(PortableTextSystem(resolver: resolver))
    return TextMeasurer(box: environment.textSystemBox, environment: environment).resolve(Text(string))
}

@MainActor private final class Captured {
    var glyphs: [MUIGlyph] = []
    var insideDraw = false
}

/// A request whose draw runs `body` (premultiplied draws first), then `drawText` of `text` at `point`.
@MainActor
private func labelling(_ surface: SurfaceTarget, _ text: TextMeasurer.ResolvedText, at point: Point<Pixels>,
                       captured: Captured = Captured(), value: Int = 0,
                       before body: @escaping @MainActor (any GPUSurfaceContext) -> Void = { _ in })
    -> SurfaceDrawRequest {
    SurfaceDrawRequest(target: surface, scaleFactor: 1, time: 0, policy: .onDemand, value: value) { ctx in
        body(ctx)
        captured.insideDraw = SDLGPUWindowGuard.isInsideDraw
        ctx.drawText(text, at: point, anchor: .topLeading)
        captured.glyphs = (ctx as? SDLGPUDrawContext)?.textSink?.glyphs ?? []
    }
}

private func inkCount(_ pixels: [UInt8], where condition: (Int, Int) -> Bool = { _, _ in true }) -> Int {
    var count = 0
    for y in 0..<height { for x in 0..<width where condition(x, y) && rgba(pixels, x, y)[0...2].contains(where: { $0 != 0 }) { count += 1 } }
    return count
}

/// **14** (`DT-C`, `DT-G`). The surface's text reads back equal to the same glyph records drawn directly by the
/// scene, over a scene that holds glyphs of its own so the text range starts past zero. Mutation: the text
/// pass's `first_instance` is 0 (the pass draws the scene's own glyph, not the surface's).
@MainActor
@Test func anSDLSurfaceTextReadsBackEqualToTheSameGlyphsDrawnDirectly() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    // The scene's own glyph: "Wq", captured from a first frame on a renderer of its own.
    let own = Captured()
    let first = try offscreenRenderer()
    try frame(first, scene(surfaces: [target]), [labelling(target, try resolved("Wq"), at: Point(x: px(4), y: px(28)), captured: own)],
              atlas: atlas)
    try #require(!own.glyphs.isEmpty, "set up: the first frame recorded glyphs")

    let mine = Captured()
    let renderer = try offscreenRenderer()
    try frame(renderer, scene(surfaces: [target], glyphs: own.glyphs),
              [labelling(target, try resolved("Hg 42"), at: Point(x: px(4), y: px(3)), captured: mine)], atlas: atlas)
    try #require(!mine.glyphs.isEmpty, "set up: the draw recorded glyphs")
    let viaSurface = try renderer.readPixels(width: width, height: height)

    let direct = try offscreenRenderer()
    // The surface path draws the scene's glyph over the composite; the oracle draws every record in the scene.
    try frame(direct, glyphScene(mine.glyphs + own.glyphs), [], atlas: atlas)
    let oracle = try direct.readPixels(width: width, height: height)
    try #require(inkCount(oracle) > 0, "set up: the direct scene drew ink")

    var worst = 0
    var differing = 0
    for i in 0..<viaSurface.count where viaSurface[i] != oracle[i] {
        differing += 1
        worst = max(worst, abs(Int(viaSurface[i]) - Int(oracle[i])))
    }
    #expect(worst <= 1, "\(differing) bytes differ, worst delta \(worst) (one UNORM step is rounding)")
    #expect(inkCount(viaSurface, where: { _, y in y < 24 }) > 0, "the surface's own label is in the top half")
    #expect(renderer.lastTextPasses == 1)
}

/// **15** (`DT-B`). A glyph first inserted by a surface draw is uploaded before the text pass: on a first frame
/// the whole atlas moves and the readback is not blank; on a second frame a new glyph moves only dirty rects
/// (fewer bytes than the atlas) and still shows. Mutation: the text pass encoded before the atlas copy pass
/// (the first frame's glyphs are blank).
@MainActor
@Test func aGlyphInsertedByASurfaceDrawIsUploadedBeforeTheTextPassOnSDL() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let renderer = try offscreenRenderer()
    let scene = scene(surfaces: [target])
    try frame(renderer, scene, [labelling(target, try resolved("Hg"), at: Point(x: px(4), y: px(3)))], atlas: atlas)
    #expect(renderer.lastAtlasBytes == 512 * 512, "a new atlas texture takes the whole atlas")
    let firstPixels = try renderer.readPixels(width: width, height: height)
    #expect(inkCount(firstPixels) > 0, "the first frame's text is not blank")

    // A different label on the same surface (a new `value:` redraws it), glyphs the atlas has not seen.
    try frame(renderer, scene, [labelling(target, try resolved("Zx#"), at: Point(x: px(40), y: px(3)), value: 1)], atlas: atlas)
    #expect(renderer.lastAtlasBytes > 0 && renderer.lastAtlasBytes < 512 * 512, "dirty rects only: \(renderer.lastAtlasBytes)")
    let secondPixels = try renderer.readPixels(width: width, height: height)
    #expect(inkCount(secondPixels, where: { x, _ in x >= 40 }) > 0, "the new glyphs are uploaded before they are drawn")
}

/// **16** (`DT-A`). The text is drawn over the app's own pass: the app clears opaque red, then `drawText`; red
/// survives away from the ink and ink is on top of it. Mutation: the text pass's load op is `CLEAR` (the red is
/// gone).
@MainActor
@Test func textIsDrawnOverTheAppsOwnPassOnSDL() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let renderer = try offscreenRenderer()
    try frame(renderer, scene(surfaces: [target]),
              [labelling(target, try resolved("Hg 42"), at: Point(x: px(4), y: px(3))) { ctx in
                  ctx.clear(red: 1, green: 0, blue: 0, alpha: 1)
              }], atlas: atlas)
    let pixels = try renderer.readPixels(width: width, height: height)
    #expect(rgba(pixels, 90, 44) == [255, 0, 0, 255], "the app's red survives away from the text")
    let inked = (0..<height).flatMap { y in (0..<width).map { x in rgba(pixels, x, y) } }.filter { $0 != [255, 0, 0, 255] }
    #expect(!inked.isEmpty, "the text is drawn on top of the red")
}

/// **17** (`DT-G`). One text pass per surface that recorded text, none for a frame without: the C recorder
/// reads 0, 1 and 2. Mutation: always run a (empty) pass.
@MainActor
@Test func anSDLFrameWithNoSurfaceTextRunsNoTextPass() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let text = try resolved("Hg")
    let renderer = try offscreenRenderer()
    let plain = SurfaceDrawRequest(target: target, scaleFactor: 1, time: 0, policy: .onDemand, value: nil) { ctx in
        ctx.clear(red: 0, green: 0, blue: 1, alpha: 1)
    }
    try frame(renderer, scene(surfaces: [target]), [plain], atlas: atlas)
    #expect(renderer.lastTextPasses == 0, "a surface frame with no text runs no text pass")
    try frame(renderer, glyphScene([]), [], atlas: atlas)
    #expect(renderer.lastTextPasses == 0, "a frame with no surface runs none")
    try frame(renderer, scene(surfaces: [target, otherTarget]),
              [labelling(target, text, at: Point(x: px(4), y: px(3)), value: 1),
               labelling(otherTarget, text, at: Point(x: px(4), y: px(3)))], atlas: atlas)
    #expect(renderer.lastTextPasses == 2, "one pass per surface that recorded text")
    #expect(renderer.submissionCount > 0)
}

/// **18** (`DT-G`). The bridge refuses a text range its glyph buffer does not hold: a hand-built finish with one
/// glyph record and a range of one is accepted (control), a range of one over no records is refused and the
/// frame is not submitted. Mutation: the bounds check dropped from `mui_renderer_finish`.
@MainActor
@Test func aSurfaceTextRangeOutsideTheGlyphBufferIsRefused() throws {
    let renderer = try offscreenRenderer()
    let bridge = renderer.bridgeRenderer
    let surface = try #require(mui_renderer_create_target(bridge, 16, 16))
    defer { mui_renderer_release_texture(bridge, surface) }
    let atlas = [UInt8](repeating: 0, count: 16 * 16)
    let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    let record = [UInt8](repeating: 0, count: 88)

    func finish(glyphs: [UInt8], range: ReplaySurfaceText) -> Bool {
        var begun: (UInt32, UInt32) = (0, 0)
        guard mui_renderer_begin(bridge, &begun.0, &begun.1) == 1 else { return false }
        let texts = [range]
        return glyphs.withUnsafeBytes { glyphBytes in
            atlas.withUnsafeBufferPointer { pixels in
                texts.withUnsafeBufferPointer { textBuffer in
                    identity.withUnsafeBufferPointer { matrix in
                        mui_renderer_finish(bridge, nil, 0, glyphBytes.baseAddress, UInt32(glyphBytes.count), nil, 0, nil, 0,
                                            nil, 0, nil, 0, nil, 0, nil, 0, pixels.baseAddress, 16, 16, nil, 0,
                                            textBuffer.baseAddress, UInt32(textBuffer.count), matrix.baseAddress)
                    }
                }
            }
        }
    }
    #expect(finish(glyphs: record, range: ReplaySurfaceText(target: surface, start: 0, count: 1, width: 16, height: 16)),
            "control: a range inside the records is drawn")
    #expect(mui_renderer_last_text_passes(bridge) == 1)
    #expect(!finish(glyphs: [], range: ReplaySurfaceText(target: surface, start: 0, count: 1, width: 16, height: 16)),
            "a range over no records is refused")
}

/// **19** (`DT-A`, `GA-H`). `drawText` inside a draw trips none of the draw guard's checks: the draw is inside the
/// guard's window while the call runs, the call opens no typed pass, and the guard is off after the frame.
/// Mutation: none beyond the two existing guard pins (`SDLGPUContractTests`), which stay green.
@MainActor
@Test func drawTextInsideADrawDoesNotTripTheDrawGuard() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let captured = Captured()
    let renderer = try offscreenRenderer()
    try frame(renderer, scene(surfaces: [target]),
              [labelling(target, try resolved("Hg"), at: Point(x: px(4), y: px(3)), captured: captured)], atlas: atlas)
    #expect(captured.insideDraw, "set up: the call ran inside the guard's window")
    #expect(!captured.glyphs.isEmpty)
    #expect(!SDLGPUWindowGuard.isInsideDraw, "the guard is off once the draw returned")
}
