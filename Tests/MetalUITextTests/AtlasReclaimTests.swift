import Testing
@testable import MetalUIText

/// A tiny helper so every test builds an identical rasterized image without
/// depending on CoreText — reclaim policy is arithmetic on generations and areas,
/// not on glyph shapes, so a hand-built bitmap is the right oracle here.
private func img() -> GlyphImage {
    GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
}

// MARK: - The between-frames guard

@Test func reclaimingDuringFrameConstructionTraps() async {
    await #expect(processExitsWith: .failure) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.reclaim()
    }
}

/// The positive control (ruling CS-C). Without it the test above passes when
/// `reclaim` traps unconditionally.
@Test func reclaimingBetweenFramesDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.endFrame()
        atlas.reclaim()
    }
}

private func key(_ glyph: UInt16, variant: Int = 0) -> GlyphKey {
    GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
             glyph: glyph, size: 13, subpixelVariant: variant, scaleFactor: 2)
}

/// `GL-A`: a reclaim empties the packer, so a key packed before it is rasterized
/// again and lands where a fresh atlas would put it, and the generation a
/// holder of a rect checks has advanced. Mutation: `reclaim` that keeps
/// `placed` (the key is a hit, `rasterizedAgain` stays false).
@Test func aReclaimForgetsEveryGlyphAndAdvancesTheLayoutGeneration() throws {
    let atlas = GlyphAtlas(width: 128, height: 128)
    atlas.beginFrame()
    _ = atlas.slot(for: key(1), rasterize: { img() })
    let second = try #require(atlas.slot(for: key(2), rasterize: { img() }))
    atlas.endFrame()
    try #require(second.x == 8)
    #expect(atlas.layoutGeneration == 0)

    atlas.reclaim()
    #expect(atlas.layoutGeneration == 1)
    #expect(atlas.reclaimCount == 1)
    #expect(atlas.pixels.allSatisfy { $0 == 0 }, "a reclaim leaves no old pixel behind")
    #expect(atlas.dirtyRects.count == 1 && atlas.dirtyRect?.width == 128 && atlas.dirtyRect?.height == 128,
            "every pixel changed, so the whole atlas is dirty")

    var rasterizedAgain = false
    atlas.beginFrame()
    let again = atlas.slot(for: key(2), rasterize: { rasterizedAgain = true; return img() })
    atlas.endFrame()
    #expect(rasterizedAgain)
    #expect(again?.x == 0 && again?.y == 0, "the first glyph after a reclaim takes the first slot, as in a fresh atlas")
}

/// `GL-A` policy: only an atlas three quarters through its rows **and** a
/// quarter stale asks for a rebuild. An atlas full of glyphs the last frame used
/// has nothing to give back (a rebuild would only rasterize them all again);
/// one full of glyphs the last frame did not use does. Mutation: drop the stale
/// clause (the live atlas below asks) or the rows clause (the early stale one
/// asks).
@Test func anAtlasWantsAReclaimOnlyWhenItIsNearlyFullOfStaleGlyphs() throws {
    let atlas = GlyphAtlas(width: 64, height: 64)
    // Frame 1 fills 4 of 8 shelves with distinct 64x8 glyphs: half full, all live.
    atlas.beginFrame()
    for glyph in 0..<4 { _ = atlas.slot(for: key(UInt16(glyph)), rasterize: { GlyphImage(width: 64, height: 8, bytes: [UInt8](repeating: 9, count: 512)) }) }
    atlas.endFrame()
    #expect(!atlas.wantsReclaim, "half the rows")
    // Frame 2 touches only glyph 0 and adds two more shelves: 6 of 8 rows = 75%.
    atlas.beginFrame()
    for glyph in [0, 4, 5] { _ = atlas.slot(for: key(UInt16(glyph)), rasterize: { GlyphImage(width: 64, height: 8, bytes: [UInt8](repeating: 9, count: 512)) }) }
    atlas.endFrame()
    // Packed 6 x 512; the last frame used 3 x 512 = half: stale >= a quarter.
    #expect(atlas.wantsReclaim, "three quarters of the rows, half of it stale")

    // The same rows, all live: nothing to give back.
    let live = GlyphAtlas(width: 64, height: 64)
    live.beginFrame()
    for glyph in 0..<6 { _ = live.slot(for: key(UInt16(glyph)), rasterize: { GlyphImage(width: 64, height: 8, bytes: [UInt8](repeating: 9, count: 512)) }) }
    live.endFrame()
    #expect(!live.wantsReclaim, "three quarters of the rows, every glyph used by the last frame")
}

/// `GL-A`: a whitespace glyph is forgotten by a reclaim like any other.
@Test func aWhitespaceGlyphIsRasterizedAgainAfterAReclaim() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let blank = { GlyphImage(width: 0, height: 0, bytes: []) }
    atlas.beginFrame()
    _ = atlas.slot(for: key(3), rasterize: blank)
    atlas.endFrame()
    atlas.reclaim()
    var again = false
    atlas.beginFrame()
    _ = atlas.slot(for: key(3), rasterize: { again = true; return blank() })
    atlas.endFrame()
    #expect(again)
}

// MARK: - Growth (`GL-B`)

/// `GL-B`: a glyph that does not fit doubles the atlas instead of being dropped,
/// every earlier slot keeps its place and its pixels, and the whole atlas is
/// dirty so a renderer re-creates its texture. Mutation: `growAndPlace` returns
/// nil (the glyph is dropped and the counter moves), or `resize` copies rows at
/// the old stride (the first glyph's pixels are wrong).
@Test func aFullAtlasGrowsInPlaceAndKeepsEarlierSlots() throws {
    let atlas = GlyphAtlas(width: 16, height: 16, maximumExtent: 64)
    let first = try #require(atlas.slot(for: key(1), rasterize: {
        GlyphImage(width: 16, height: 16, bytes: (0..<256).map { UInt8($0) })
    }), "fills the 16x16 atlas")
    atlas.clearDirtyRect()
    let second = try #require(atlas.slot(for: key(2), rasterize: {
        GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 200, count: 256))
    }), "does not fit in 16x16; fits after one doubling")
    #expect(atlas.width == 32 && atlas.height == 32 && atlas.growCount == 1)
    #expect(atlas.droppedGlyphs == 0)
    #expect((first.x, first.y, first.width, first.height) == (0, 0, 16, 16), "growth moved nothing")
    #expect((second.x, second.y) == (16, 0), "the open shelf continued into the new width")
    for row in 0..<16 {
        let start = row * 32
        #expect(Array(atlas.pixels[start..<(start + 16)]) == (0..<16).map { UInt8(row * 16 + $0) },
                "row \(row) of the first glyph survived the new stride")
    }
    #expect(atlas.layoutGeneration == 0, "growth does not invalidate a rect")
    #expect(atlas.dirtyRect?.width == 32 && atlas.dirtyRect?.height == 32, "a renderer must re-upload all of it")
}

/// `GL-C`/`GL-E`: past the cap a glyph is dropped, counted every time it is
/// asked for, and not cached. Mutation: no increment (counter 0), or a cached
/// nil (the second request does not rasterize).
@Test func pastTheCapAGlyphIsDroppedAndCounted() {
    let atlas = GlyphAtlas(width: 16, height: 16, maximumExtent: 32)
    func big() -> GlyphImage { GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 1, count: 256)) }
    for glyph in 1...4 { _ = atlas.slot(for: key(UInt16(glyph)), rasterize: big) }
    #expect(atlas.width == 32 && atlas.growCount == 1)
    var rasterized = 0
    #expect(atlas.slot(for: key(5), rasterize: { rasterized += 1; return big() }) == nil)
    #expect(atlas.slot(for: key(5), rasterize: { rasterized += 1; return big() }) == nil)
    #expect(atlas.droppedGlyphs == 2 && rasterized == 2, "counted per request, never cached")
}

/// `GL-C`: an atlas made without a maximum never grows, so every user that
/// predates growth keeps its geometry.
@Test func anAtlasMadeWithoutAMaximumNeverGrows() {
    let atlas = GlyphAtlas(width: 16, height: 16)
    _ = atlas.slot(for: key(1), rasterize: { GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 1, count: 256)) })
    #expect(atlas.slot(for: key(2), rasterize: { GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 1, count: 256)) }) == nil)
    #expect(atlas.width == 16 && atlas.growCount == 0 && atlas.droppedGlyphs == 1)
}

/// `GL-A`: a refusal while older frames hold room asks for a rebuild; one with
/// nothing stale does not (so the window's one-more-frame request cannot loop).
@Test func aDropAsksForARebuildOnlyWhenOlderGlyphsHoldRoom() {
    func big() -> GlyphImage { GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 1, count: 256)) }
    let stale = GlyphAtlas(width: 16, height: 16)
    stale.beginFrame(); _ = stale.slot(for: key(1), rasterize: big); stale.endFrame()
    stale.beginFrame(); _ = stale.slot(for: key(2), rasterize: big)
    #expect(stale.droppedGlyphs == 1 && stale.reclaimRequested, "glyph 1 is from an older frame")
    stale.endFrame()
    stale.reclaim()
    #expect(!stale.reclaimRequested)

    let live = GlyphAtlas(width: 16, height: 16)
    live.beginFrame(); _ = live.slot(for: key(1), rasterize: big); _ = live.slot(for: key(2), rasterize: big)
    #expect(live.droppedGlyphs == 1 && !live.reclaimRequested, "everything packed is this frame's: a rebuild cannot help")
    live.endFrame()
}

/// `GL-B`: a reclaim sizes the atlas for the last frame's working set, back down
/// to the starting size when it is small.
@Test func aReclaimShrinksAGrownAtlasToTheWorkingSet() {
    let atlas = GlyphAtlas(width: 16, height: 16, maximumExtent: 64)
    func big() -> GlyphImage { GlyphImage(width: 16, height: 16, bytes: [UInt8](repeating: 1, count: 256)) }
    atlas.beginFrame()
    for glyph in 1...6 { _ = atlas.slot(for: key(UInt16(glyph)), rasterize: big) }
    atlas.endFrame()
    #expect(atlas.width == 64)
    // Frame 2 uses one glyph; the reclaim after it needs 3 x 256 = 768 pixels: 32 x 32, not 64 x 64.
    atlas.beginFrame(); _ = atlas.slot(for: key(1), rasterize: big); atlas.endFrame()
    atlas.reclaim()
    #expect(atlas.width == 32 && atlas.height == 32 && atlas.pixels.count == 1024)
}

// MARK: - The re-entrancy guard

/// `beginFrame` mirrors `LayoutTree.beginLayout`'s shape exactly, including
/// its re-entrancy guard: a nested `beginFrame` would advance
/// `currentGeneration` while the outer frame's slots are still being stamped
/// with the old one, silently mis-stamping them as older than they are.
@Test func beginningAFrameTwiceInARowTraps() async {
    await #expect(processExitsWith: .failure) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.beginFrame()
    }
}

@Test func endingAFrameThenBeginningAnotherDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.endFrame()
        atlas.beginFrame()
    }
}

// MARK: - One dictionary, generation folded into the value

/// **A cache hit hashes its key once.** `packed(for:rasterize:)` runs for every
/// glyph of every visible `Text` on every built frame, and its hit path used to
/// be a `placed[key]` read followed by a `lastUsedGeneration[key] = …` write
/// into a second dictionary keyed on the same `GlyphKey` — two full hashes of a
/// `String`-bearing key per glyph, the second feeding only
/// the old eviction method, which had no production caller. The generation now
/// lives in `placed`'s value and the hit re-stamps it through
/// `index(forKey:)`, `ShapingCache.shaped`'s pattern.
///
/// Structural, because a hash count is not observable from outside the type.
/// What it pins: exactly ONE stored dictionary is keyed on `GlyphKey`, and that
/// dictionary's value carries the generation a later hit re-stamped. The
/// behaviour the rebuild policy reads is pinned separately, by
/// `anAtlasWantsAReclaimOnlyWhenItIsNearlyFullOfStaleGlyphs` above.
@Test func theGenerationLivesInTheOneDictionaryThatHoldsTheGlyph() throws {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 7, size: 13, subpixelVariant: 0, scaleFactor: 2)
    atlas.beginFrame()
    _ = atlas.slot(for: key, rasterize: { img() })
    atlas.endFrame()
    atlas.beginFrame()
    atlas.endFrame()
    atlas.beginFrame()
    _ = atlas.slot(for: key, rasterize: { img() })   // a hit, in generation 3
    atlas.endFrame()
    try #require(atlas.currentGeneration == 3)

    let glyphKeyed = Mirror(reflecting: atlas).children.filter {
        String(describing: type(of: $0.value)).hasPrefix("Dictionary<GlyphKey,")
    }
    try #require(glyphKeyed.count == 1,
                 "dictionaries keyed on GlyphKey: \(glyphKeyed.map { $0.label ?? "?" })")

    let entries = Array(Mirror(reflecting: glyphKeyed[0].value).children)
    try #require(entries.count == 1)
    let pair = Array(Mirror(reflecting: entries[0].value).children)
    let value = try #require(pair.first { $0.label == "value" }?.value)
    let stamped = Mirror(reflecting: value).children.first { $0.label == "generation" }?.value as? Int
    #expect(stamped == 3, "the hit did not re-stamp the entry's own generation")
}
