import Testing
import MetalUICore
import MetalUIScene
@testable import MetalUI

// `GL-D`: the raster key of a glyph leaf names its atlas rect, and two rebuilds can put different glyphs at equal
// rects, so the key carries `GlyphAtlas.layoutGeneration` beside it.

/// The same leaf keyed against the same rect before and after the atlas is rebuilt must key differently. Mutation:
/// drop `key.add(glyphAtlas.layoutGeneration)` from the glyph case of `Frame.keyLeaf` (the keys are equal).
@Test @MainActor func aGlyphLeafKeyChangesWhenTheAtlasIsRebuilt() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let frame = Frame(contentSize: Size(width: Pixels(64), height: Pixels(64)), scaleFactor: 1, glyphAtlas: atlas)
    let key = GlyphKey(font: FontKey(resolvedPostScriptName: "Key-Test", size: 13, variations: [],
                                     matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
                       glyph: 1, size: 13, subpixelVariant: 0, scaleFactor: 1)
    let slot = try #require(atlas.slot(for: key, rasterize: {
        GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
    }))
    func scaled(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
        Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)),
               size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
    }
    let zero = ScaledPixels(0)
    let glyph = MUIGlyph(bounds: scaled(0, 0, 8, 8), slot: slot, contentMask: scaled(0, 0, 64, 64),
                         maskCornerRadii: Corners(topLeft: zero, topRight: zero, bottomRight: zero, bottomLeft: zero),
                         color: Hsla(h: 0, s: 0, l: 1, a: 1), order: 0)
    let leaf = [CapturedPrimitive.glyph(glyph, layer: 0, innerMask: false)]

    func rasterKey() -> RasterKey {
        var key = RasterKey()
        var retained: [AnyObject] = []
        frame.keyLeaf(leaf, into: &key, retained: &retained)
        return key
    }
    let before = rasterKey()
    #expect(before == rasterKey(), "the same atlas generation keys the same leaf identically")
    atlas.reclaim()
    #expect(before != rasterKey(), "the same rect in a rebuilt atlas is a different key")
}
