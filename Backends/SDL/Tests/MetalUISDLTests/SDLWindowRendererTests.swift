import Foundation
import Testing
import MetalUIPortableText
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture

// RS-D: `SDLWindowRenderer` draws a frame exactly as the replay path does —
// the path `PortableReplay` holds to the Metal renderer's pixels in CI on
// Metal, Vulkan and Direct3D 12 — while keeping its atlas between frames.

private let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Tests/Fonts/NotoSans-Regular.ttf")

private let width = 240, height = 120

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
private func color(_ h: Float, _ s: Float, _ l: Float, _ a: Float = 1) -> MUIHsla { MUIHsla(h: h, s: s, l: l, a: a) }

/// Rects, a rounded clip and text, emitted into `atlas`.
private func scene(_ text: String, atlas: GlyphAtlas) throws -> Scene {
    var scene = Scene()
    let mask = bounds(0, 0, Float(width), Float(height))
    scene.insert(MUIRect(bounds: mask, contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.6, 0.2, 0.15), borderColor: color(0, 0, 0),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIRect(bounds: bounds(10.5, 10.25, 120, 60), contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.3, 0.7, 0.5, 0.8), borderColor: color(0.1, 0.8, 0.7),
                         cornerRadii: corners(12), borderWidths: MUIEdges(top: 3, right: 3, bottom: 3, left: 3),
                         order: 0, shape: 0))
    let font = try PortableFont(data: [UInt8](Data(contentsOf: fontURL)), size: 17)
    atlas.beginFrame()
    try PortableText.emitLines(text, font: font, origin: (16.3, 70.6), wrappingAt: 200, scaleFactor: 1,
                               color: color(0.55, 0.1, 0.95), contentMask: mask, into: &scene, atlas: atlas)
    atlas.endFrame()
    scene.finalize()
    return scene
}

/// An ellipse fill and band, two images (linear and nearest, one of them
/// under a rounded mask and at half opacity) over a background rect.
private func imageScene(_ first: ImageTexture, _ second: ImageTexture) -> Scene {
    var scene = Scene()
    let mask = bounds(0, 0, Float(width), Float(height))
    scene.insert(MUIRect(bounds: mask, contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.6, 0.2, 0.15), borderColor: color(0, 0, 0),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIRect(bounds: bounds(8.5, 8.25, 90, 50), contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.3, 0.7, 0.5), borderColor: color(0.1, 0.8, 0.7),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 9, right: 9, bottom: 9, left: 9),
                         order: 0, shape: MUIUInt(MUIShapeEllipse.rawValue)))
    scene.insert(MUIImage(bounds: bounds(110, 10, 60, 40), contentMask: mask,
                          maskCornerRadii: corners(0), opacity: 1, texture: 0,
                          filter: MUIUInt(MUIImageFilterNearest.rawValue), order: 0), texture: first)
    scene.insert(MUIImage(bounds: bounds(120.25, 60.5, 100, 50), contentMask: bounds(120, 60, 100, 50),
                          maskCornerRadii: corners(14), opacity: 0.5, texture: 0,
                          filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 0), texture: second)
    scene.finalize()
    return scene
}

private let checker = ImageTexture(width: 2, height: 2, straightRGBA: [255, 0, 0, 255, 0, 0, 255, 255,
                                                                         0, 255, 0, 255, 255, 255, 0, 128])
private let ramp = ImageTexture(width: 3, height: 1, straightRGBA: [255, 255, 255, 255, 0, 0, 0, 255,
                                                                      40, 200, 90, 200])

/// BGRA at (x, y) as (r, g, b, a).
private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
    let i = (y * width + x) * 4
    return [pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3]]
}

/// S1.2 — a frame with the ellipse kind and images draws in
/// `SDLWindowRenderer` exactly as the replay path (the one `PortableReplay`
/// holds to Metal) draws it, and the images are really there: the nearest
/// image's top-left texel fills its top-left quarter.
@MainActor
@Test func anImageFrameIsTheReplayPathsFrame() throws {
    let frame = imageScene(checker, ramp)
    let atlas = GlyphAtlas(width: 16, height: 16)
    let expected = try replayPixels(frame, atlas: atlas)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    try #require(renderer.beginFrame() == 1)
    try #require(renderer.finishFrame(scene: frame, atlas: atlas))
    let drawn = try renderer.readPixels(width: width, height: height)
    #expect(rgba(drawn, 120, 15) == [255, 0, 0, 255], "the nearest image's red texel")
    #expect(rgba(drawn, 160, 15) == [0, 0, 255, 255], "and its blue one")
    #expect(drawn == expected)
}

/// S1.2 — the window renderer keeps one GPU texture per `ImageTexture`
/// identity across frames, uploads it once, and releases what a frame no
/// longer references (`TE-AF` item 3), as the Metal renderer does.
@MainActor
@Test func imageTexturesPersistAndAreReleasedWhenAbsent() throws {
    let atlas = GlyphAtlas(width: 16, height: 16)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    let other = ImageTexture(width: 1, height: 1, straightRGBA: [9, 9, 9, 255])
    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: imageScene(checker, ramp), atlas: atlas))
    #expect(renderer.cachedTextureIdentities == [ObjectIdentifier(checker), ObjectIdentifier(ramp)])
    #expect(renderer.textureUploadCount == 2)
    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: imageScene(checker, ramp), atlas: atlas))
    #expect(renderer.textureUploadCount == 2, "cached textures are not uploaded again")
    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: imageScene(checker, other), atlas: atlas))
    #expect(renderer.cachedTextureIdentities == [ObjectIdentifier(checker), ObjectIdentifier(other)], "ramp is released")
    #expect(renderer.textureUploadCount == 3)
    #expect(renderer.textureReleaseCount == 1, "exactly ramp, once")
    let drawn = try renderer.readPixels(width: width, height: height)
    #expect(drawn == (try replayPixels(imageScene(checker, other), atlas: atlas)))
    #expect(renderer.textureReleaseCount == 1)
    #expect(renderer.unsignaledFenceReleaseCount == 0)
}

/// Record §61 §10 — back-to-back offscreen frames with no readback between
/// them never release the previous frame's fence before the GPU signals it.
/// SDL returns a released fence to its pool while the submitted command
/// buffer still points at it; the next submission re-arms the same fence, so
/// Direct3D 12 cleaned the newer frame early — resetting its allocator and
/// destroying its buffers mid-flight — and the debug layer broke in
/// `D3D12_INTERNAL_DestroyBuffer` (run 36588257167).
@MainActor
@Test func backToBackFramesNeverReleaseAnUnsignaledFence() throws {
    let atlas = GlyphAtlas(width: 256, height: 256)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    let frame = try scene("Many frames, no readback", atlas: atlas)
    for _ in 0..<32 {
        try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: frame, atlas: atlas))
    }
    #expect(renderer.unsignaledFenceReleaseCount == 0)
    #expect(try renderer.readPixels(width: width, height: height) == (try replayPixels(frame, atlas: atlas)))
}

private func replayPixels(_ scene: Scene, atlas: GlyphAtlas) throws -> [UInt8] {
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory,
                                   driver: SDLWindowRenderer.defaultDriver)
    return try replayer.render(scene, atlas: atlas, width: width, height: height,
                               projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
}

@MainActor
@Test func aWindowRendererFrameIsTheReplayPathsFrame() throws {
    let atlas = GlyphAtlas(width: 256, height: 256)
    let frame = try scene("Kerning AV To, wrapped text", atlas: atlas)
    let expected = try replayPixels(frame, atlas: atlas)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    try #require(renderer.beginFrame() == 1)
    try #require(renderer.finishFrame(scene: frame, atlas: atlas))
    let drawn = try renderer.readPixels(width: width, height: height)
    try #require(expected.count == drawn.count)
    #expect(Set(drawn).count > 8, "the frame must draw something")
    #expect(drawn == expected)
}

/// The atlas texture outlives the frame: a second frame with nothing new to
/// upload draws the same pixels, and one after new glyphs were packed draws
/// the replay path's pixels for that frame — the upload happened.
@MainActor
@Test func theAtlasPersistsAndUpdatesAcrossFrames() throws {
    let atlas = GlyphAtlas(width: 256, height: 256)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    let first = try scene("First frame", atlas: atlas)
    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: first, atlas: atlas))
    #expect(atlas.dirtyRect == nil, "finishing a frame clears the atlas' dirty rect, as the Metal renderer does")
    let firstPixels = try renderer.readPixels(width: width, height: height)

    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: first, atlas: atlas))
    #expect(try renderer.readPixels(width: width, height: height) == firstPixels)

    let second = try scene("Quiz jumps: new glyphs", atlas: atlas)
    try #require(atlas.dirtyRect != nil, "the second frame must pack new glyphs")
    try #require(renderer.beginFrame() != nil && renderer.finishFrame(scene: second, atlas: atlas))
    let drawn = try renderer.readPixels(width: width, height: height)
    #expect(drawn == (try replayPixels(second, atlas: atlas)))
    #expect(drawn != firstPixels)
}

@MainActor
@Test func finishingWithoutBeginningDrawsNothing() throws {
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    #expect(!renderer.finishFrame(scene: Scene(), atlas: GlyphAtlas(width: 16, height: 16)))
}

/// A rect, a glyph run and an image under transforms (ruling GX-F): the bar
/// local (20, 50, 100, 20) turned a quarter about (70, 60) (screen x 60…80,
/// y 10…110), the text turned 17°, the image turned a quarter.
private func transformedScene(atlas: GlyphAtlas) throws -> Scene {
    var scene = Scene()
    let mask = bounds(0, 0, Float(width), Float(height))
    func record(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ tx: Float, _ ty: Float) -> MUITransform {
        MUITransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty, pixelScale: abs(a * d - b * c).squareRoot(), _reserved: 0,
                     outerMask: mask, outerMaskRadii: corners(0))
    }
    scene.insert(MUIRect(bounds: mask, contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.6, 0.2, 0.15), borderColor: color(0, 0, 0),
                         cornerRadii: corners(0), borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    scene.insert(MUIRect(bounds: bounds(20, 50, 100, 20), contentMask: mask, maskCornerRadii: corners(0),
                         background: color(0.3, 0.7, 0.5), borderColor: color(0.1, 0.8, 0.7),
                         cornerRadii: corners(6), borderWidths: MUIEdges(top: 2, right: 2, bottom: 2, left: 2),
                         order: 0, shape: 0), transform: record(0, 1, -1, 0, 130, -10))
    var text = Scene()
    let font = try PortableFont(data: [UInt8](Data(contentsOf: fontURL)), size: 15)
    atlas.beginFrame()
    try PortableText.emit("Turned", font: font, origin: (120.5, 40.25), scaleFactor: 1,
                          color: color(0.55, 0.1, 0.95), contentMask: mask, into: &text, atlas: atlas)
    atlas.endFrame()
    let (s, c) = (Float(0.29237170472273677), Float(0.9563047559630354))   // 17°
    for glyph in text.glyphs {
        scene.insert(glyph, transform: record(c, s, -s, c, 150 - c * 150 + s * 40, 40 - s * 150 - c * 40))
    }
    scene.insert(MUIImage(bounds: bounds(150, 70, 60, 20), contentMask: mask, maskCornerRadii: corners(0),
                          opacity: 1, texture: 0, filter: MUIUInt(MUIImageFilterLinear.rawValue), order: 0),
                 texture: checker, transform: record(0, 1, -1, 0, 260, -100))
    scene.finalize()
    return scene
}

/// S1.2 (ruling GX-F) — a transformed frame draws in `SDLWindowRenderer`
/// exactly as the replay path draws it, and the transform is really applied:
/// the turned bar covers (70, 15), outside its untransformed bounds.
@MainActor
@Test func aTransformedFrameIsTheReplayPathsFrame() throws {
    let atlas = GlyphAtlas(width: 256, height: 256)
    let frame = try transformedScene(atlas: atlas)
    try #require(frame.transforms.count == 3, "bar, text, image")
    let expected = try replayPixels(frame, atlas: atlas)
    let renderer = try SDLWindowRenderer(offscreenWidth: width, height: height)
    try #require(renderer.beginFrame() == 1)
    try #require(renderer.finishFrame(scene: frame, atlas: atlas))
    let drawn = try renderer.readPixels(width: width, height: height)
    #expect(rgba(drawn, 70, 15) == rgba(drawn, 70, 60), "the turned bar reaches (70, 15)")
    #expect(rgba(drawn, 25, 60) != rgba(drawn, 70, 60), "and leaves its old bounds")
    #expect(drawn == expected)
}

/// S1.3 (ruling GX-S item 7) — `replay_render` refuses a run whose record
/// names a transform past the table, per kind and at the exact boundary:
/// `transformedScene`'s rects name entry 1, its glyphs 2, its image 3, so
/// each kind's runs alone render with exactly that many records and are
/// refused with one fewer. (`mui_renderer_finish` runs the same
/// `transforms_valid`; a `Scene` cannot build such a record — `insert`
/// always writes the index it assigns — so that call site is defensive and
/// pinned only through this one.)
@MainActor
@Test func aRecordNamingAMissingTransformIsRefused() throws {
    let atlas = GlyphAtlas(width: 256, height: 256)
    let frame = try transformedScene(atlas: atlas)
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory,
                                   driver: SDLWindowRenderer.defaultDriver)
    let full = try ReplayFixture(scene: frame, atlas: atlas, width: UInt32(width), height: UInt32(height),
                                 projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                                 reference: [UInt8](repeating: 0, count: width * height * 4))
    try #require(full.transformCount == 3)
    let stride = Int(ReplayFixture.transformStride)
    for (kind, index) in [(FixtureRun.Kind.rect, 1), (.glyph, 2), (.image, 3)] {
        let runs = full.runs.filter { $0.kind == kind }
        try #require(!runs.isEmpty, "\(kind) has runs")
        var exact = full
        exact.transforms = Array(full.transforms.prefix(index * stride))
        #expect(throws: Never.self, "\(kind) with \(index) records renders") {
            _ = try replayer.render(exact, runs: runs)
        }
        var short = full
        short.transforms = Array(full.transforms.prefix((index - 1) * stride))
        let error = #expect(throws: ReplayError.self, "\(kind) with \(index - 1) records is refused") {
            _ = try replayer.render(short, runs: runs)
        }
        #expect(error?.description.contains("names a missing transform") == true, "\(String(describing: error))")
    }
}
