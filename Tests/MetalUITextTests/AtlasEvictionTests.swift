import Testing
@testable import MetalUIText

/// A tiny helper so every test builds an identical rasterized image without
/// depending on CoreText — eviction ordering is arithmetic on generations,
/// not on glyph shapes, so a hand-built bitmap is the right oracle here.
private func img() -> GlyphImage {
    GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
}

// MARK: - The between-frames guard (task 6 brief, verbatim)

@Test func evictingDuringFrameConstructionTraps() async {
    await #expect(processExitsWith: .failure) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.evictUnusedSince(0)
    }
}

/// The positive control (ruling CS-C). Without it the test above passes when
/// `evictUnusedSince` traps unconditionally.
@Test func evictingBetweenFramesDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.endFrame()
        atlas.evictUnusedSince(0)
    }
}

@Test func aGlyphUsedThisFrameSurvivesEviction() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 7, size: 13, subpixelVariant: 0, scaleFactor: 2)
    atlas.beginFrame()
    let slot = atlas.slot(for: key, rasterize: {
        GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
    })
    atlas.endFrame()
    atlas.evictUnusedSince(atlas.currentGeneration)
    var rasterizedAgain = false
    atlas.beginFrame()
    let again = atlas.slot(for: key, rasterize: {
        rasterizedAgain = true
        return GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
    })
    atlas.endFrame()
    #expect(rasterizedAgain == false)
    #expect(slot?.x == again?.x && slot?.y == again?.y)
}

// MARK: - The discriminator TX-I asks for

/// **TX-I: "reddens exactly the tests written for it" is not sufficient.**
/// `aGlyphUsedThisFrameSurvivesEviction` above only checks that a glyph the
/// current frame touched survives — an `evictUnusedSince` that evicts
/// **nothing at all** passes it trivially, and passes the two trap tests too,
/// since neither reads `placed`. This is the test that requires eviction to
/// have actually happened: a glyph untouched since an older generation must
/// be gone, forcing a re-rasterize, while one touched in the intervening
/// frame must not be.
@Test func aGlyphUnusedSinceAnOlderGenerationIsEvicted() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let keyA = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                        glyph: 7, size: 13, subpixelVariant: 0, scaleFactor: 2)
    let keyB = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                        glyph: 9, size: 13, subpixelVariant: 0, scaleFactor: 2)

    // Frame 1: only A is drawn.
    atlas.beginFrame()
    _ = atlas.slot(for: keyA, rasterize: { img() })
    atlas.endFrame()

    // Frame 2: only B is drawn. A is not referenced by this frame's scene.
    atlas.beginFrame()
    _ = atlas.slot(for: keyB, rasterize: { img() })
    atlas.endFrame()

    // Evict anything not used since the frame that just ended: A's last use
    // (generation 1) predates it, B's (generation 2) does not.
    atlas.evictUnusedSince(atlas.currentGeneration)

    var aRasterizedAgain = false
    atlas.beginFrame()
    _ = atlas.slot(for: keyA, rasterize: { aRasterizedAgain = true; return img() })
    atlas.endFrame()
    #expect(aRasterizedAgain == true)

    var bRasterizedAgain = false
    atlas.beginFrame()
    _ = atlas.slot(for: keyB, rasterize: { bRasterizedAgain = true; return img() })
    atlas.endFrame()
    #expect(bRasterizedAgain == false)
}

/// A glyph re-touched in a later frame must not be evicted just because it
/// was *also* placed long ago — `evictUnusedSince` reads the most recent
/// stamp, not the first one. Without this a packer that only ever recorded a
/// key's *first* generation would evict every long-lived glyph (labels,
/// titles — exactly the text least likely to change) on the very next sweep.
@Test func repeatedUseInLaterFramesKeepsAGlyphAlive() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 5, size: 13, subpixelVariant: 0, scaleFactor: 2)

    atlas.beginFrame()
    _ = atlas.slot(for: key, rasterize: { img() })
    atlas.endFrame()

    for _ in 0..<5 {
        atlas.beginFrame()
        _ = atlas.slot(for: key, rasterize: { img() })
        atlas.endFrame()
    }

    atlas.evictUnusedSince(atlas.currentGeneration)

    var rasterizedAgain = false
    atlas.beginFrame()
    _ = atlas.slot(for: key, rasterize: { rasterizedAgain = true; return img() })
    atlas.endFrame()
    #expect(rasterizedAgain == false)
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
