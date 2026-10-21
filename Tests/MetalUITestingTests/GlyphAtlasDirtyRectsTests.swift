import MetalUIScene
import MetalUITesting
import Testing

// Lane 3 of C14-f (`RG-H`, `RG-I`; record 128): the glyph atlas keeps a short list of dirty rects,
// one per shelf run, instead of one bounding box, so two first-use glyphs on distant shelves upload
// their own areas and not the span between them. Portable (no Metal): the atlas and the headless
// renderer's counter.

private func fontKey() -> FontKey {
    FontKey(resolvedPostScriptName: "Dirty-Rects-Test", size: 13, variations: [],
            matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
}

private func key(_ i: Int) -> GlyphKey {
    GlyphKey(font: fontKey(), glyph: UInt16(i), size: 13, subpixelVariant: 0, scaleFactor: 1)
}

private func image(_ w: Int, _ h: Int, from first: Int = 1) -> GlyphImage {
    GlyphImage(width: w, height: h, bytes: (0..<(w * h)).map { UInt8(truncatingIfNeeded: first + $0) })
}

/// Packs `w x h` as glyph `i` and answers its slot.
@discardableResult
private func pack(_ atlas: GlyphAtlas, _ i: Int, _ w: Int, _ h: Int) throws -> AtlasSlot {
    try #require(atlas.slot(for: key(i), rasterize: { image(w, h, from: i) }))
}

private func area(_ rects: [(x: Int, y: Int, width: Int, height: Int)]) -> Int {
    rects.reduce(0) { $0 + $1.width * $1.height }
}

/// Two first-use glyphs on distant shelves in one frame, after a clean atlas: a 4 x 4 at
/// (60, 4) on shelf 1 and a 60 x 4 at (0, 34) on shelf 2. Own areas 16 + 240 = 256; the span
/// (0, 4, 64, 34) is 2176.
private func distantAtlas() throws -> GlyphAtlas {
    let atlas = GlyphAtlas(width: 64, height: 64)
    try pack(atlas, 1, 60, 4)      // (0, 0)
    try pack(atlas, 2, 60, 30)     // shelf 1 at (0, 4)
    atlas.clearDirtyRect()
    let a = try pack(atlas, 3, 4, 4)
    #expect((a.x, a.y) == (60, 4), "the fixture's first glyph ends shelf 1")
    let b = try pack(atlas, 4, 60, 4)
    #expect((b.x, b.y) == (0, 34), "the fixture's second glyph opens shelf 2")
    return atlas
}

/// **13** - the headless renderer counts the sum of the rects' areas, not the span. Red at 99b21a1c
/// (2176). Mutation: `markDirty` back to the bounding box.
@Test @MainActor func twoGlyphsOnDistantShelvesCountTheirOwnAreasNotTheSpan() throws {
    let atlas = try distantAtlas()
    let renderer = HeadlessWindowRenderer()
    #expect(renderer.finishFrame(scene: Scene(), atlas: atlas, surfaces: []))
    #expect(renderer.lastAtlasUploadPixels == 256, "own areas 16 + 240, not the 2176-texel span")
    #expect(atlas.dirtyRects.isEmpty && atlas.dirtyRect == nil, "the upload cleared both")
    #expect(renderer.finishFrame(scene: Scene(), atlas: atlas, surfaces: []))
    #expect(renderer.lastAtlasUploadPixels == 0)
}

/// **14** - slots x-adjacent on one shelf merge into one rect (height the max); the next shelf is a
/// second rect. Mutation: drop the adjacency merge (count 2 on the first line).
@Test func adjacentSlotsOnOneShelfMergeIntoOneRect() throws {
    let atlas = GlyphAtlas(width: 32, height: 32)
    try pack(atlas, 1, 4, 4)       // (0, 0)
    try pack(atlas, 2, 4, 6)       // (4, 0)
    try pack(atlas, 3, 4, 2)       // (8, 0)
    let rects = atlas.dirtyRects
    try #require(rects.count == 1, "three x-adjacent slots on one shelf are one rect, got \(rects)")
    #expect(rects[0] == (x: 0, y: 0, width: 12, height: 6))
    try pack(atlas, 4, 24, 4)      // does not fit at x = 12: shelf 2 at y = 6
    let next = atlas.dirtyRects
    try #require(next.count == 2, "a new shelf is a second rect, got \(next)")
    #expect(next[1] == (x: 0, y: 6, width: 24, height: 4))
}

/// **15** - the ninth rect collapses the list to its bounding rect and it stays one growing union
/// until cleared (`RG-I`). Mutation: raise the cap to 16.
@Test func theNinthRectCollapsesToTheBoundingRect() throws {
    let atlas = GlyphAtlas(width: 16, height: 40)
    for i in 0..<8 { try pack(atlas, i + 1, 16, 2) }          // one full shelf each: 8 rects
    #expect(atlas.dirtyRects.count == 8, "the cap is eight, got \(atlas.dirtyRects.count)")
    try pack(atlas, 9, 16, 2)
    let collapsed = atlas.dirtyRects
    try #require(collapsed.count == 1, "the ninth collapses to one rect, got \(collapsed)")
    #expect(collapsed[0] == (x: 0, y: 0, width: 16, height: 18))
    try pack(atlas, 10, 16, 2)
    try #require(atlas.dirtyRects.count == 1, "a collapsed list stays one growing union (RG-I)")
    #expect(atlas.dirtyRects[0] == (x: 0, y: 0, width: 16, height: 20))
    atlas.clearDirtyRect()
    #expect(atlas.dirtyRects.isEmpty && atlas.dirtyRect == nil)
    try pack(atlas, 11, 16, 2)
    #expect(atlas.dirtyRects.count == 1, "cleared: the list starts again")
    try pack(atlas, 12, 16, 2)
    #expect(atlas.dirtyRects.count == 2, "and grows as a list again after the clear")
}

/// **16** - `dirtyRect` stays the union of `dirtyRects`. Mutation: return only the last rect.
@Test func dirtyRectIsTheUnionOfDirtyRects() throws {
    let atlas = try distantAtlas()
    try #require(atlas.dirtyRects.count == 2, "two distant shelves are two rects, got \(atlas.dirtyRects)")
    let union = try #require(atlas.dirtyRect)
    #expect(union == (x: 0, y: 4, width: 64, height: 34))
    #expect(atlas.dirtyRects[0] == (x: 60, y: 4, width: 4, height: 4))
    #expect(atlas.dirtyRects[1] == (x: 0, y: 34, width: 60, height: 4))
}
