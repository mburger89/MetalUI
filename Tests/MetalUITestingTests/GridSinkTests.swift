import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import Testing

// Terminal phase 5.1 (`TRM-AU`, `TRM-AV`; record 347): what the grid sink records. Portable: the sink is a plain
// object over a `GlyphAtlas`, so these tests read its `MUIGlyph` records and the atlas bytes directly. The
// pixels they stand for are read back by `GridSinkMetalTests` (macOS) and `SDLGridSinkTests` (SDL).

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let red = MUIHsla(h: 0, s: 1, l: 0.5, a: 1)
private let blue = MUIHsla(h: 2.0 / 3, s: 1, l: 0.5, a: 1)

@MainActor private func makeSink(atlas: GlyphAtlas = GlyphAtlas(width: 64, height: 64)) -> SurfaceTextSink {
    let sink = SurfaceTextSink(atlas: atlas)
    sink.beginSurface(SurfaceID(rawValue: 1))
    return sink
}

/// **1** (`TRM-AU`). A rect is one glyph instance: its destination is the rect, its mask defaults to the rect
/// (an explicit clip replaces it), its colour is the colour, and its source is the solid slot's inner square.
/// Mutation: record the destination as the slot's size.
@Test @MainActor func aRectIsOneGlyphInstanceOverTheSolidSlot() throws {
    let sink = makeSink()
    #expect(sink.fillRect(box(3, 5, 17, 9), color: red))
    #expect(sink.fillRect(box(0, 0, 8, 8), color: blue, clip: box(2, 2, 4, 4)))
    #expect(sink.glyphs.count == 2)
    let slot = try #require(sink.solidSlot)
    let first = sink.glyphs[0]
    #expect([first.bounds.origin.x, first.bounds.origin.y, first.bounds.size.width, first.bounds.size.height]
            == [3, 5, 17, 9])
    #expect([first.contentMask.origin.x, first.contentMask.size.width] == [3, 17], "the mask is the rect itself")
    #expect([first.color.h, first.color.s, first.color.l, first.color.a] == [0, 1, 0.5, 1])
    #expect([first.atlasBounds.origin.x, first.atlasBounds.origin.y] == [Float(slot.x + 1), Float(slot.y + 1)])
    #expect([first.atlasBounds.size.width, first.atlasBounds.size.height] == [2, 2])
    #expect(sink.glyphs[1].contentMask.origin.x == 2 && sink.glyphs[1].contentMask.size.width == 4, "an explicit clip")
    #expect(first.transform == 0)
    #expect(sink.batches.map(\.range) == [0..<2], "one batch")
}

/// **2** (`TRM-AU`). The solid slot is a fully covered square and the sampled square keeps a one-texel margin
/// inside it: the linear filter's footprint (the sampled square grown by one texel) never leaves the slot, and
/// every texel of that footprint is full coverage in the atlas bytes. Mutation: `solidInset` 0 (the footprint
/// then reaches the neighbours).
@Test @MainActor func theSolidSlotIsFullCoverageUnderTheWholeFilterFootprint() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    // A neighbour packed first, so the solid slot is not at the atlas origin and a bleed would read ink.
    _ = atlas.packed(for: GlyphKey(font: FontKey(resolvedPostScriptName: "N", size: 1, variations: [],
                                                 matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
                                   glyph: 1, size: 1, subpixelVariant: 0, scaleFactor: 1),
                     rasterize: { GlyphImage(width: 5, height: 5, bytes: [UInt8](repeating: 7, count: 25)) })
    let sink = makeSink(atlas: atlas)
    sink.fillRect(box(0, 0, 4, 4), color: red)
    let slot = try #require(sink.solidSlot)
    let g = sink.glyphs[0]
    let minX = Int(g.atlasBounds.origin.x) - 1, maxX = Int(g.atlasBounds.origin.x + g.atlasBounds.size.width) + 1
    let minY = Int(g.atlasBounds.origin.y) - 1, maxY = Int(g.atlasBounds.origin.y + g.atlasBounds.size.height) + 1
    #expect(minX >= slot.x && minY >= slot.y && maxX <= slot.x + slot.width && maxY <= slot.y + slot.height,
            "the footprint \(minX)..<\(maxX) x \(minY)..<\(maxY) is inside the slot \(slot)")
    for y in slot.y..<(slot.y + slot.height) {
        for x in slot.x..<(slot.x + slot.width) where atlas.pixels[y * atlas.width + x] != 255 {
            Issue.record("texel \(x),\(y) of the solid slot is \(atlas.pixels[y * atlas.width + x])")
        }
    }
}

/// **3** (`TRM-AU`). The solid slot is packed once: any number of rects, in any number of sinks over the same
/// atlas, share one slot and one rasterization. Mutation: key the slot per call.
@Test @MainActor func theSolidSlotIsPackedOncePerAtlas() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let a = makeSink(atlas: atlas), b = makeSink(atlas: atlas)
    for i in 0..<10 { a.fillRect(box(Float(i), 0, 1, 1), color: red) }
    b.fillRect(box(0, 0, 1, 1), color: blue)
    #expect(Set(a.glyphs.map { [$0.atlasBounds.origin.x, $0.atlasBounds.origin.y] }
                + b.glyphs.map { [$0.atlasBounds.origin.x, $0.atlasBounds.origin.y] }).count == 1)
    #expect(a.solidSlot == b.solidSlot)
    #expect(atlas.pixels.filter { $0 == 255 }.count == SurfaceTextSink.solidSide * SurfaceTextSink.solidSide,
            "one square of coverage in the atlas")
}

/// **4** (`TRM-AU`). Rects and glyphs interleave in call order inside the surface's one batch; a second surface
/// opens its own. Mutation: record rects into a batch of their own.
@Test @MainActor func rectsAndGlyphsKeepCallOrderInTheSurfacesBatch() throws {
    let sink = makeSink()
    let glyph = MUIGlyph(bounds: box(0, 0, 3, 3), atlasBounds: box(0, 0, 3, 3), contentMask: box(0, 0, 9, 9),
                         maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                         color: red, order: 0, transform: 0)
    sink.fillRect(box(0, 0, 9, 9), color: blue)
    sink.append(glyph)
    sink.fillRect(box(1, 1, 2, 2), color: red)
    sink.beginSurface(SurfaceID(rawValue: 2))
    sink.fillRect(box(0, 0, 2, 2), color: red)
    #expect(sink.batches.map(\.range) == [0..<3, 3..<4])
    #expect(sink.batches.map(\.target.rawValue) == [1, 2])
    #expect(sink.glyphs[1].atlasBounds.size.width == 3, "the glyph sits between the two rects")
    #expect(sink.glyphs[0].atlasBounds.size.width == 2 && sink.glyphs[2].atlasBounds.size.width == 2)
}

/// **5** (`TRM-AU`). An atlas with no room for the solid square records nothing and says so, rather than
/// recording an instance over texels that are another glyph's. Mutation: record over the origin slot anyway.
@Test @MainActor func aFullAtlasRecordsNoRect() throws {
    let sink = makeSink(atlas: GlyphAtlas(width: 3, height: 3))
    #expect(sink.fillRect(box(0, 0, 4, 4), color: red) == false)
    #expect(sink.glyphs.isEmpty && sink.batches.isEmpty)
    #expect(sink.solidSlot == nil)
}
