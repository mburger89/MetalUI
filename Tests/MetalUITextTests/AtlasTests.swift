import Testing
import CoreText
@testable import MetalUIText

/// A fresh resolve per access rather than a stored global: `ResolvedFont` holds
/// a `CTFont` and is deliberately not `Sendable`, so a file-scope
/// `private let font = …` does not compile under Swift 6 (ruling TX-A; the same
/// fix Tasks 2 and 3 made).
private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

private func img(_ w: Int, _ h: Int) -> GlyphImage {
    GlyphImage(width: w, height: h, bytes: [UInt8](repeating: 255, count: w * h))
}

/// A bitmap whose every byte is a function of its position, so that a blit
/// which transposes rows and columns, uses the wrong stride, or lands one row
/// out cannot produce the expected bytes by accident. `img` above is uniform
/// and could not see any of that — taxonomy shape 1.
private func rampImage(_ w: Int, _ h: Int, from first: Int) -> GlyphImage {
    GlyphImage(width: w, height: h,
               bytes: (0..<(w * h)).map { UInt8(first + $0) })
}

private func glyph(_ character: UniChar, in resolved: ResolvedFont) -> CGGlyph {
    var g = CGGlyph(0)
    var ch = character
    let ok = CTFontGetGlyphsForCharacters(resolved.ctFont, &ch, &g, 1)
    #expect(ok)
    return g
}

private func inkBounds(_ image: GlyphImage) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    var minX = image.width, maxX = -1, minY = image.height, maxY = -1
    for y in 0..<image.height {
        for x in 0..<image.width where image.bytes[y * image.width + x] > 0 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return maxX < 0 ? nil : (minX, maxX, minY, maxY)
}

// MARK: - The packer

@Test func twoGlyphsNeverOverlapInTheAtlas() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    var slots: [AtlasSlot] = []
    for i in 0..<20 {
        let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                           glyph: CGGlyph(i), size: 13, subpixelVariant: 0, scaleFactor: 2)
        if let s = atlas.slot(for: key, rasterize: { img(9 + i % 5, 12) }) { slots.append(s) }
    }
    #expect(slots.count == 20)
    for (i, a) in slots.enumerated() {
        for b in slots[(i + 1)...] {
            let disjoint = a.x + a.width <= b.x || b.x + b.width <= a.x
                        || a.y + a.height <= b.y || b.y + b.height <= a.y
            #expect(disjoint)
        }
    }
}

/// **The test above cannot fail for the mutation the plan aims at it, and this
/// one can.** Its twenty images are all 12 tall, so a packer that opens the
/// next shelf below the *current glyph* rather than below the tallest glyph on
/// the shelf — the plan's mutation 1 — produces byte-identical output. Uniform
/// values on both sides of an assertion, taxonomy shape 1.
///
/// It is also the discriminator ruling TX-I asks for. Disjointness alone is
/// satisfied by a packer that stacks every glyph in its own row and by one that
/// runs off the bottom of the atlas, so this asserts three further things a
/// shelf packer owes: every slot lies **inside** the atlas, several slots
/// **share** a shelf, and the shelf origins are where the rule puts them.
///
/// Widths cycle 20, 11, 17 and heights cycle 6, 14, 9 in a 64x64 atlas, so the
/// arithmetic is hand-derivable and every clause bites: 20 + 11 + 17 = 48 fits
/// across, a fourth glyph at 68 does not, and each shelf is 14 tall because of
/// its *middle* glyph — not its first and not its last.
@Test func theShelfPackerPlacesGlyphsOfMixedHeightsOnSharedShelves() {
    let atlas = GlyphAtlas(width: 64, height: 64)
    let widths = [20, 11, 17]
    let heights = [6, 14, 9]
    var slots: [AtlasSlot] = []
    for i in 0..<12 {
        let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                           glyph: CGGlyph(i), size: 13, subpixelVariant: 0, scaleFactor: 2)
        if let s = atlas.slot(for: key, rasterize: { img(widths[i % 3], heights[i % 3]) }) {
            slots.append(s)
        }
    }
    #expect(slots.count == 12)

    // Derived by hand from the shelf rule, not read off the implementation:
    // three glyphs per shelf at x = 0, 20, 31; shelves at y = 0, 14, 28, 42,
    // each 14 tall because the 14-tall middle glyph sets the shelf's height.
    let expected: [(Int, Int, Int, Int)] = [
        (0, 0, 20, 6), (20, 0, 11, 14), (31, 0, 17, 9),
        (0, 14, 20, 6), (20, 14, 11, 14), (31, 14, 17, 9),
        (0, 28, 20, 6), (20, 28, 11, 14), (31, 28, 17, 9),
        (0, 42, 20, 6), (20, 42, 11, 14), (31, 42, 17, 9),
    ]
    for (i, slot) in slots.enumerated() {
        #expect(slot.x == expected[i].0)
        #expect(slot.y == expected[i].1)
        #expect(slot.width == expected[i].2)
        #expect(slot.height == expected[i].3)
    }

    for a in slots {
        #expect(a.x >= 0 && a.y >= 0)
        #expect(a.x + a.width <= 64)
        #expect(a.y + a.height <= 64)
    }
    for (i, a) in slots.enumerated() {
        for b in slots[(i + 1)...] {
            let disjoint = a.x + a.width <= b.x || b.x + b.width <= a.x
                        || a.y + a.height <= b.y || b.y + b.height <= a.y
            #expect(disjoint)
        }
    }
    // Four shelves for twelve glyphs. A column-stacker gives twelve.
    #expect(Set(slots.map(\.y)).count == 4)
}

@Test func theSameKeyReturnsTheSameSlotWithoutRasterizingTwice() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
    var rasterCount = 0
    let first = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) })
    let second = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) })
    #expect(rasterCount == 1)
    #expect(first?.x == second?.x && first?.y == second?.y)
}

/// **The five key components each matter.** §6.1 names them; this asserts none
/// is decorative. Dropping any one collapses two distinct glyph images onto one
/// slot, which paints the wrong glyph.
@Test func everyComponentOfTheGlyphKeyDiscriminates() {
    let f13 = FontResolver.resolve(family: nil, size: 13).key
    let f26 = FontResolver.resolve(family: nil, size: 26).key
    let base = GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(base != GlyphKey(font: f26, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 43, size: 13, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 26, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 1, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 1))
}

/// Inequality alone would be satisfied by a key that hashes everything into one
/// bucket and compares by identity. The atlas keys a **dictionary**, so what it
/// actually needs is that five distinct keys occupy five distinct entries — and
/// that two keys spelled the same way occupy one.
@Test func distinctGlyphKeysOccupyDistinctAtlasEntries() {
    let f13 = FontResolver.resolve(family: nil, size: 13).key
    let f26 = FontResolver.resolve(family: nil, size: 26).key
    let keys = [
        GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2),
        GlyphKey(font: f26, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2),
        GlyphKey(font: f13, glyph: 43, size: 13, subpixelVariant: 0, scaleFactor: 2),
        GlyphKey(font: f13, glyph: 42, size: 26, subpixelVariant: 0, scaleFactor: 2),
        GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 1, scaleFactor: 2),
        GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 1),
    ]
    #expect(Set(keys).count == 6)

    let atlas = GlyphAtlas(width: 128, height: 128)
    var rasterCount = 0
    for key in keys { _ = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) }) }
    #expect(rasterCount == 6)
    for key in keys { _ = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) }) }
    #expect(rasterCount == 6)
}

@Test func aGlyphTooLargeForTheAtlasReturnsNilRatherThanCorrupting() {
    let atlas = GlyphAtlas(width: 32, height: 32)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 1, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(atlas.slot(for: key, rasterize: { img(64, 64) }) == nil)
}

/// A refusal must cost nothing. A packer that advanced its cursor before
/// discovering it had no room would leave a hole behind every rejected glyph,
/// and one that cached the `nil` would keep refusing a key that eviction had
/// since made room for.
@Test func aRefusedGlyphLeavesTheAtlasUsable() {
    let atlas = GlyphAtlas(width: 32, height: 32)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 1, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(atlas.slot(for: key, rasterize: { img(64, 64) }) == nil)
    #expect(atlas.dirtyRect == nil)

    // The next glyph still starts at the origin: the refusal moved nothing.
    let next = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                        glyph: 2, size: 13, subpixelVariant: 0, scaleFactor: 2)
    let slot = atlas.slot(for: next, rasterize: { img(10, 12) })
    #expect(slot?.x == 0)
    #expect(slot?.y == 0)

    // And the refused key is not remembered as a failure: asked again with a
    // bitmap that fits, it packs.
    var rasterCount = 0
    let retry = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(8, 8) })
    #expect(rasterCount == 1)
    #expect(retry?.x == 10)
    #expect(retry?.y == 0)
}

/// A whitespace glyph has no ink and no pixels. It must still resolve, because
/// a space is the commonest glyph in a paragraph and a `nil` there would read
/// as "the atlas is full" at every call site.
@Test func aGlyphWithNoInkGetsAnEmptySlotRatherThanNilOrSpace() {
    let atlas = GlyphAtlas(width: 32, height: 32)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 3, size: 13, subpixelVariant: 0, scaleFactor: 2)
    var rasterCount = 0
    let slot = atlas.slot(for: key, rasterize: { rasterCount += 1; return .empty })
    #expect(slot?.width == 0)
    #expect(slot?.height == 0)
    #expect(atlas.dirtyRect == nil)

    // Cached like any other glyph, so a paragraph of spaces rasterizes once.
    _ = atlas.slot(for: key, rasterize: { rasterCount += 1; return .empty })
    #expect(rasterCount == 1)

    // And it consumed no room: the next real glyph is still at the origin.
    let next = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                        glyph: 4, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(atlas.slot(for: next, rasterize: { img(6, 6) })?.x == 0)
}

// MARK: - The pixels

/// **The briefed tests never read `pixels`, so all five pass against an atlas
/// that returns coordinates and writes nothing** — which paints blank text.
/// This asserts the bytes land at the slot that was handed back, with the
/// stride and the row order the type documents.
///
/// The bitmaps are position-dependent ramps rather than solid 255, so a blit
/// that transposes, mis-strides or lands a row out cannot pass by accident.
///
/// It pins the blit, not the packing: the coordinates it reads come from
/// `slot(for:)` itself, so a packer that placed everything at the origin would
/// still satisfy it. `theShelfPackerPlacesGlyphsOfMixedHeightsOnSharedShelves`
/// is the independent oracle for the geometry; this one is for the copy.
@Test func theBytesLandAtTheSlotTheAtlasHandedBack() {
    let atlas = GlyphAtlas(width: 16, height: 8)
    let fontKey = FontResolver.resolve(family: nil, size: 13).key

    let a = rampImage(3, 2, from: 10)      // 10 11 12 / 13 14 15
    let b = rampImage(2, 2, from: 70)      // 70 71 / 72 73
    let slotA = atlas.slot(for: GlyphKey(font: fontKey, glyph: 1, size: 13,
                                         subpixelVariant: 0, scaleFactor: 2),
                           rasterize: { a })
    let slotB = atlas.slot(for: GlyphKey(font: fontKey, glyph: 2, size: 13,
                                         subpixelVariant: 0, scaleFactor: 2),
                           rasterize: { b })
    #expect(slotA?.x == 0 && slotA?.y == 0)
    #expect(slotB?.x == 3 && slotB?.y == 0)

    func pixel(_ x: Int, _ y: Int) -> UInt8 { atlas.pixels[y * 16 + x] }
    for row in 0..<2 {
        for column in 0..<3 {
            #expect(pixel(column, row) == a.bytes[row * 3 + column])
        }
    }
    for row in 0..<2 {
        for column in 0..<2 {
            #expect(pixel(3 + column, row) == b.bytes[row * 2 + column])
        }
    }
    // Nothing outside the two slots was touched.
    #expect(pixel(5, 0) == 0)
    #expect(pixel(0, 2) == 0)
    #expect(atlas.pixels.count == 16 * 8)
}

/// The dirty rect is the union of what was written since the last clear — the
/// one region a renderer has to re-upload.
///
/// The oracle is the slots, computed independently: the union of (0,0,3,2),
/// (3,0,4,2) and (0,2,3,2) is (0,0,7,4).
@Test func theDirtyRectIsTheUnionOfWhatWasWrittenAndClears() {
    let atlas = GlyphAtlas(width: 8, height: 8)
    let fontKey = FontResolver.resolve(family: nil, size: 13).key
    func key(_ i: Int) -> GlyphKey {
        GlyphKey(font: fontKey, glyph: CGGlyph(i), size: 13, subpixelVariant: 0, scaleFactor: 2)
    }

    #expect(atlas.dirtyRect == nil)

    _ = atlas.slot(for: key(1), rasterize: { img(3, 2) })          // (0,0,3,2)
    #expect(atlas.dirtyRect?.x == 0)
    #expect(atlas.dirtyRect?.y == 0)
    #expect(atlas.dirtyRect?.width == 3)
    #expect(atlas.dirtyRect?.height == 2)

    _ = atlas.slot(for: key(2), rasterize: { img(4, 2) })          // (3,0,4,2)
    _ = atlas.slot(for: key(3), rasterize: { img(3, 2) })          // wraps to (0,2,3,2)
    #expect(atlas.dirtyRect?.x == 0)
    #expect(atlas.dirtyRect?.y == 0)
    #expect(atlas.dirtyRect?.width == 7)
    #expect(atlas.dirtyRect?.height == 4)

    atlas.clearDirtyRect()
    #expect(atlas.dirtyRect == nil)

    // A cache hit writes nothing, so it must not dirty anything either — else
    // the renderer re-uploads on every frame that draws the same text.
    _ = atlas.slot(for: key(1), rasterize: { Issue.record("a hit must not rasterize"); return img(3, 2) })
    #expect(atlas.dirtyRect == nil)
}

// MARK: - Rasterization

/// Rasterization goes through CoreText, and a rendered glyph is not blank.
@Test func aRasterizedGlyphHasInk() {
    let f = FontResolver.resolve(family: nil, size: 13)
    var glyph = CGGlyph(0)
    var ch: UniChar = 0x48   // "H"
    #expect(CTFontGetGlyphsForCharacters(f.ctFont, &ch, &glyph, 1))
    let image = GlyphRaster.rasterize(glyph: glyph, font: f, subpixelVariant: 0, scaleFactor: 2)
    #expect(image.bytes.contains { $0 > 0 })
}

/// "Has ink somewhere" is satisfied by a bitmap of the wrong size, by one whose
/// glyph is drawn a long way from where the bearings say it is, and by one that
/// clips the antialiased edge — none of which any test in this repo can see
/// once it reaches a texture (spec §4.2). The ink's own position inside the
/// bitmap is the check that can be made headlessly.
///
/// Both halves are asserted. **Nothing clipped:** the outermost row and column
/// on every side are empty, which is what `GlyphRaster.inkPadding` buys.
/// **Nothing wasted:** the ink reaches within two pixels of every edge, so the
/// bitmap is tight around the glyph rather than merely large enough.
///
/// Measured for "H" at 13pt, scale 2: CoreText's bounding rect is
/// `(1.168, 0.0, 7.3125, 9.1597)`, the bitmap is 17x21 with `left` 1 and `top`
/// 20, and the ink occupies columns 1...15 of 17 and rows 1...19 of 21 — an
/// inset of exactly 1 on all four sides.
///
/// **It is also the only guard on `setShouldSmoothFonts(false)`**, which is not
/// what it was written for. Turning font smoothing on spreads ink past the
/// outline's bounding box by more than `GlyphRaster.inkPadding` — "H" reaches
/// column 16 of 17 — so the unclipped clause reddens. Recorded here as well as
/// at the setting, because a fix that lands in one file while the claim stays
/// in the other is this milestone's most repeated defect.
@Test func aRasterizedBitmapIsTightAroundItsInkAndDoesNotClipIt() {
    let f = FontResolver.resolve(family: nil, size: 13)
    let image = GlyphRaster.rasterize(glyph: glyph(0x48, in: f), font: f,
                                      subpixelVariant: 0, scaleFactor: 2)
    guard let ink = inkBounds(image) else {
        Issue.record("a rasterized \"H\" has no ink at all")
        return
    }
    #expect(ink.minX >= 1)
    #expect(ink.minY >= 1)
    #expect(ink.maxX <= image.width - 2)
    #expect(ink.maxY <= image.height - 2)

    #expect(ink.minX <= 2)
    #expect(ink.minY <= 2)
    #expect(ink.maxX >= image.width - 3)
    #expect(ink.maxY >= image.height - 3)

    // The bearings describe this bitmap, and a y-down renderer places its top
    // at `baselineY - top`. "H" sits on the baseline with no descender, so its
    // height above the baseline is the bitmap's height less the padding below.
    #expect(image.left == 1)
    #expect(image.top == 20)
}

/// **Subpixel positioning is live, not merely parameterised.** §6.1 rasterizes
/// each glyph at a few fractional x-offsets because without it spacing visibly
/// wobbles during horizontal scroll, and the atlas pays four entries per glyph
/// for it. This asserts it gets four *positions* for them.
///
/// The oracle is the ink's centre of mass in device space —
/// `left + Σ(x · coverage) / Σ coverage` — which is a physical property of the
/// bitmap, computed here and nowhere in the implementation. Comparing bitmaps
/// instead is what a first draft of this test did, and it could not fail for
/// the mutation it existed to catch: **measured**, turning CoreGraphics' font
/// subpixel *quantization* back on collapses the four variants onto two
/// positions (steps 0.000, 0.525, 0.000) and variants 1 and 2 — the pair a
/// byte comparison must use, being the only pair with equal dimensions —
/// straddle the surviving boundary and still differ. The whole suite stayed
/// green.
///
/// Measured as written: centroids 9.134, 9.392, 9.659, 9.908, so steps of
/// 0.258, 0.267 and 0.250 device pixels against the 0.25 the variant count
/// asks for. Switching subpixel positioning off instead gives 0.000, 0.000,
/// 0.000 — one position for all four.
@Test func eachSubpixelVariantMovesTheInkAQuarterOfADevicePixel() {
    let f = FontResolver.resolve(family: nil, size: 13)
    let g = glyph(0x48, in: f)

    func inkCentroidX(_ image: GlyphImage) -> Double {
        var weighted = 0.0
        var total = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let coverage = Double(image.bytes[y * image.width + x])
                weighted += Double(x) * coverage
                total += coverage
            }
        }
        return Double(image.left) + weighted / total
    }

    let centroids = (0..<GlyphRaster.subpixelVariants).map {
        inkCentroidX(GlyphRaster.rasterize(glyph: g, font: f,
                                           subpixelVariant: $0, scaleFactor: 2))
    }
    let step = 1.0 / Double(GlyphRaster.subpixelVariants)
    for i in 1..<centroids.count {
        let moved = centroids[i] - centroids[i - 1]
        #expect(moved > step * 0.6)
        #expect(moved < step * 1.4)
    }
}

/// The scale factor reaches the rasterizer, not only the key. A bitmap
/// rasterized at 1x and served to a 2x display is the "fuzzy text" failure mode
/// spec §4.2 names, and nothing downstream of here can see it.
///
/// Measured for "H" at 13pt: 10x12 at scale 1, 17x21 at scale 2. Asserted as a
/// ratio rather than as the two exact pairs because the padding and the two
/// roundings make it not quite 2x, and pinning 10x12 would pin this font.
@Test func theScaleFactorReachesTheRasterizerNotOnlyTheKey() {
    let f = FontResolver.resolve(family: nil, size: 13)
    let g = glyph(0x48, in: f)
    let one = GlyphRaster.rasterize(glyph: g, font: f, subpixelVariant: 0, scaleFactor: 1)
    let two = GlyphRaster.rasterize(glyph: g, font: f, subpixelVariant: 0, scaleFactor: 2)
    #expect(two.width > one.width)
    #expect(two.height > one.height)
    #expect(Double(two.height) > 1.5 * Double(one.height))
}

/// A space has no outline, so CoreText reports an empty bounding rect. The
/// rasterizer must return an empty image rather than ask `CGContext` for a
/// zero-sized bitmap, which returns nil, or a padded 2x2 one, which would put a
/// blank slot in the atlas for every space in a paragraph.
@Test func aGlyphWithNoOutlineRasterizesEmptyRatherThanTrapping() {
    let f = FontResolver.resolve(family: nil, size: 13)
    let image = GlyphRaster.rasterize(glyph: glyph(0x20, in: f), font: f,
                                      subpixelVariant: 0, scaleFactor: 2)
    #expect(image.isEmpty)
    #expect(image.width == 0)
    #expect(image.height == 0)
    #expect(image.bytes.isEmpty)
}

/// §6.1's "pick nearest". The oracle is the rounding property itself — the
/// returned `pixelX + variant / subpixelVariants` is within half a step of the
/// asked-for position — computed here rather than read off the function.
///
/// The carry is the clause worth naming: a fraction that rounds up to a whole
/// pixel must return the **next** pixel with variant 0, never variant 4, which
/// would index a bitmap that is never rasterized.
@Test func theNearestSubpixelVariantCarriesRatherThanOverflowing() {
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: 10.0) == (10, 0))
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: 10.1) == (10, 0))
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: 10.2) == (10, 1))
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: 10.5) == (10, 2))
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: 10.9) == (11, 0))
    #expect(GlyphRaster.subpixelPlacement(forDeviceX: -0.1) == (0, 0))

    let step = 1.0 / Double(GlyphRaster.subpixelVariants)
    var worst = 0.0
    for i in 0..<10_000 {
        let x = -50 + Double(i) * 0.0137
        let placement = GlyphRaster.subpixelPlacement(forDeviceX: x)
        #expect(placement.variant >= 0 && placement.variant < GlyphRaster.subpixelVariants)
        worst = max(worst, abs(Double(placement.pixelX) + Double(placement.variant) * step - x))
    }
    // Nearest, so at most half a step. Measured: exactly 0.125.
    #expect(worst <= step / 2 + 1e-9)
}
