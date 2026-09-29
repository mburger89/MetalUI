import Foundation
import Testing
import MetalUIPortableText
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay

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
    let drawn = try renderer.readPixels(width: width, height: height)
    #expect(drawn == (try replayPixels(imageScene(checker, other), atlas: atlas)))
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
