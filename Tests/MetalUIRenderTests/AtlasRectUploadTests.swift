import Testing
import Metal
import MetalUIScene
import MetalUIText
@testable import MetalUIRender

// Lane 3 of C14-f (`RG-H`): the Metal upload writes one `replace(region:)` per dirty rect, each with
// its own offset into the atlas bytes. A missing offset smears the wrong bytes into a rect.

/// **17** - a first full upload, then two glyphs on distant shelves in one frame, a rect upload,
/// and every texel of the texture equals the atlas. Position-ramp bytes make a missing pointer
/// offset or a wrong stride visible. Mutation: pass the atlas base pointer for every rect (the
/// second rect then holds the first's bytes).
@Test @MainActor func aTwoRectUploadLeavesEveryTexelEqualToTheAtlas() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let font = FontResolver.resolve(family: nil, size: 13)
    func key(_ i: Int) -> GlyphKey {
        GlyphKey(font: font.key, glyph: UInt16(i), size: 13, subpixelVariant: 0, scaleFactor: 1)
    }
    func ramp(_ w: Int, _ h: Int, _ first: Int) -> GlyphImage {
        GlyphImage(width: w, height: h, bytes: (0..<(w * h)).map { UInt8(truncatingIfNeeded: first + 3 * $0 + 1) })
    }
    let atlas = GlyphAtlas(width: 64, height: 64)
    _ = try #require(atlas.slot(for: key(1), rasterize: { ramp(60, 4, 10) }))
    _ = try #require(atlas.slot(for: key(2), rasterize: { ramp(60, 30, 20) }))
    renderer.upload(atlas)                       // a new texture: the whole atlas
    #expect(atlas.dirtyRects.isEmpty)

    let a = try #require(atlas.slot(for: key(3), rasterize: { ramp(4, 4, 30) }))
    let b = try #require(atlas.slot(for: key(4), rasterize: { ramp(60, 4, 40) }))
    try #require((a.x, a.y, b.x, b.y) == (60, 4, 0, 34), "the fixture's two glyphs sit on distant shelves")
    try #require(atlas.dirtyRects.count == 2)
    renderer.upload(atlas)
    #expect(atlas.dirtyRects.isEmpty, "the upload cleared the list")

    let texture = try #require(renderer.atlasTexture)
    var bytes = [UInt8](repeating: 0, count: 64 * 64)
    texture.getBytes(&bytes, bytesPerRow: 64, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
    let wrong = zip(bytes, atlas.pixels).filter { $0 != $1 }.count
    #expect(wrong == 0, "\(wrong) texels differ from the atlas after a two-rect upload")
    #expect(Set(atlas.pixels).count > 8, "the fixture must be non-uniform for a wrong offset to show")
}
