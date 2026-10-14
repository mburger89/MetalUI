import CoreText
import Foundation
import MetalUITextSystem
import Testing
@testable import MetalUIText

// Hot paths, lane 1 (`HP-A`, `HP-B`, `HP-D`; spec 2026-10-13-hot-paths-design.md section 4).
// Every pin counts work through the per-shape `PlacementBox`, never time. The uncached oracle is a FRESH
// `ShapedText` from `Shaper.shape`: its box is empty, so its first `placedGlyphs` always walks CoreText.

private let paragraph = "The quick brown fox jumps over the lazy dog, and then \u{0645}\u{0631}\u{062D}\u{0628}\u{0627} "
    + "\u{4F60}\u{597D} caf\u{00E9} \u{1F600} again and again until the line wraps"

@MainActor
private func shapedPair(_ string: String, width: Double? = nil, options: TextLayoutOptions = TextLayoutOptions())
    -> (cache: ShapingCache, font: ResolvedFont, shaped: ShapedText) {
    let cache = ShapingCache()
    let font = cache.resolveFont(FontDescriptor(size: 13))
    return (cache, font, cache.shaped(string, font: font, wrappingAt: width, options: options))
}

private func same(_ a: [PlacedGlyph], _ b: [PlacedGlyph]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy {
        $0.key == $1.key && $0.pixelX == $1.pixelX && $0.baselineY == $1.baselineY && $0.font.key == $1.font.key
    }
}

/// Test 1. The runs are read from CoreText once per shape, however often it is placed.
@MainActor
@Test func aSecondPaintOfTheSameTextReadsNoRunsFromCoreText() {
    let (_, font, shaped) = shapedPair(paragraph, width: 200)
    _ = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2)
    _ = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2)
    _ = shaped.placedGlyphs(at: (x: 30.25, y: 20), font: font, scaleFactor: 2)
    #expect(shaped.placement.runReads == 1, "runs read \(shaped.placement.runReads) times")
}

/// Test 2. Placing again at an equal origin and scale computes nothing; two origins alternating thrash
/// the one-entry memo (HP-G item 5), which this pins as the measured miss behaviour.
@MainActor
@Test func aSecondPaintAtTheSameOriginComputesNoPlacements() {
    let (_, font, shaped) = shapedPair(paragraph, width: 200)
    for _ in 0..<3 { _ = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2) }
    #expect(shaped.placement.placementsComputed == 1, "computed \(shaped.placement.placementsComputed) times")
    let (_, font2, thrash) = shapedPair(paragraph, width: 200)
    for _ in 0..<2 {
        _ = thrash.placedGlyphs(at: (x: 10, y: 20), font: font2, scaleFactor: 2)
        _ = thrash.placedGlyphs(at: (x: 10, y: 40), font: font2, scaleFactor: 2)
    }
    #expect(thrash.placement.placementsComputed == 4, "one entry: two alternating origins miss every time")
    #expect(thrash.placement.runReads == 1)
}

/// Test 3. Each of x, y, scale in the key recomputes, and the answer is the uncached walk's.
@MainActor
@Test func aChangedFractionalOriginOrScaleRecomputesPlacement() {
    let (_, font, shaped) = shapedPair(paragraph, width: 200)
    let origins: [(x: Double, y: Double, scale: Float)] = [(10, 20, 1), (10.3, 20, 1), (10.3, 20.4, 1), (10.3, 20.4, 2)]
    for (index, o) in origins.enumerated() {
        let cached = shaped.placedGlyphs(at: (x: o.x, y: o.y), font: font, scaleFactor: o.scale)
        #expect(shaped.placement.placementsComputed == index + 1, "origin \(index) did not recompute")
        let (_, oracleFont, oracle) = shapedPair(paragraph, width: 200)
        #expect(same(cached, oracle.placedGlyphs(at: (x: o.x, y: o.y), font: oracleFont, scaleFactor: o.scale)))
    }
}

/// Test 4. Over strings with fallback faces, bidi, wraps, truncation and alignment, interleaved origins
/// and scales: a cached shape equals a fresh one every time.
@MainActor
@Test func thePlacedGlyphsEqualTheUncachedWalkForEveryOracleString() {
    let strings = [paragraph, "Hello", "", "a\nb\n\nc", "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", "\u{4F60}\u{597D}\u{1F600}",
                   "fi ffl \u{00C5} e\u{0301}"]
    let optionsList = [TextLayoutOptions(), TextLayoutOptions(maxLines: 2), TextLayoutOptions(alignment: .center),
                       TextLayoutOptions(maxLines: 1, truncation: .middle, alignment: .trailing)]
    let origins: [(x: Double, y: Double, scale: Float)] = [(0, 0, 1), (3.5, 7.25, 2), (0, 0, 1), (3.5, 7.26, 3), (3.5, 7.25, 2)]
    for string in strings {
        for options in optionsList {
            let (_, font, shaped) = shapedPair(string, width: 120, options: options)
            for o in origins {
                let cached = shaped.placedGlyphs(at: (x: o.x, y: o.y), font: font, scaleFactor: o.scale)
                let (_, oracleFont, oracle) = shapedPair(string, width: 120, options: options)
                #expect(same(cached, oracle.placedGlyphs(at: (x: o.x, y: o.y), font: oracleFont, scaleFactor: o.scale)),
                        "\(string.prefix(12)) \(options) \(o)")
            }
        }
    }
}

/// Test 5. A warm paint builds no `GlyphKey`.
@MainActor
@Test func aWarmPlainParagraphBuildsNoGlyphKeys() {
    let (_, font, shaped) = shapedPair(paragraph, width: 200)
    let first = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2)
    let built = shaped.placement.keysBuilt
    #expect(built == first.count && built > 0)
    for _ in 0..<3 { _ = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2) }
    #expect(shaped.placement.keysBuilt == built, "\(shaped.placement.keysBuilt - built) keys built on warm paints")
}

private func glyphKey(font: FontKey, glyph: UInt16 = 42, size: Double = 13, variant: Int = 0, scale: Float = 2) -> GlyphKey {
    GlyphKey(font: font, glyph: glyph, size: size, subpixelVariant: variant, scaleFactor: scale)
}

/// Test 6. The stored hash is a function of all five components: keys that differ in one component alone
/// store different hashes (read back, deterministic), equal keys store equal hashes, `hash(into:)` feeds the
/// stored hash, and `==` is settled by the components when a hash is forged to collide.
@MainActor
@Test func aGlyphKeyHashesFromItsStoredHashAndComparesEqualByFields() throws {
    let f13 = FontResolver.resolve(family: nil, size: 13).key
    let f26 = FontResolver.resolve(family: nil, size: 26).key
    let base = glyphKey(font: f13)
    #expect(base.precomputedHash == glyphKey(font: f13).precomputedHash)
    #expect(base == glyphKey(font: f13) && base.hashValue == glyphKey(font: f13).hashValue)
    let varied = [("font", glyphKey(font: f26)), ("glyph", glyphKey(font: f13, glyph: 43)),
                  ("size", glyphKey(font: f13, size: 26)), ("variant", glyphKey(font: f13, variant: 1)),
                  ("scale", glyphKey(font: f13, scale: 1))]
    let offset = try #require(MemoryLayout<GlyphKey>.offset(of: \GlyphKey.precomputedHash))
    for (component, key) in varied {
        #expect(key != base, "\(component)")
        #expect(key.precomputedHash != base.precomputedHash, "\(component) is not in the stored hash")
        var forged = key
        withUnsafeMutableBytes(of: &forged) { $0.storeBytes(of: base.precomputedHash, toByteOffset: offset, as: Int.self) }
        try #require(forged.hashValue == base.hashValue, "\(component): the forgery did not collide")
        #expect(forged != base, "\(component): == answered from the hash")
        #expect(Set([base, forged]).count == 2, "\(component)")
    }
    // -0.0 and 0.0 are equal sizes, so they must hash alike.
    #expect(glyphKey(font: f13, size: 0.0) == glyphKey(font: f13, size: -0.0))
    #expect(glyphKey(font: f13, size: 0.0).precomputedHash == glyphKey(font: f13, size: -0.0).precomputedHash)
}

/// Test 7. A warm atlas frame over a placed paragraph rasterizes nothing and builds no key.
@MainActor
@Test func aWarmAtlasFrameProbesOncePerDistinctGlyphKey() {
    let (cache, font, shaped) = shapedPair(paragraph, width: 200)
    _ = cache
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    var rasterized = 0
    func frame() -> Int {
        let placed = shaped.placedGlyphs(at: (x: 10, y: 20), font: font, scaleFactor: 2)
        for glyph in placed {
            _ = atlas.packed(for: glyph.key, rasterize: {
                rasterized += 1
                return GlyphRaster.rasterize(glyph: glyph.key.glyph, font: glyph.font,
                                             subpixelVariant: glyph.key.subpixelVariant, scaleFactor: glyph.key.scaleFactor)
            })
        }
        return placed.count
    }
    let count = frame()
    let distinct = rasterized
    #expect(distinct > 0 && distinct <= count)
    let built = shaped.placement.keysBuilt
    _ = frame()
    #expect(rasterized == distinct, "a warm frame rasterized \(rasterized - distinct) glyphs")
    #expect(shaped.placement.keysBuilt == built)
}

/// Test 8. A steady rich-text frame lays out and measures zero times; a changed run, origin or scale
/// recomputes exactly once.
@MainActor
@Test func aSteadyRichTextFrameLaysOutAndMeasuresZeroTimes() {
    let system = CoreTextTextSystem()
    let regular = system.resolveFont(FontDescriptor(size: 13))
    let bold = system.resolveFont(FontDescriptor(size: 13, weight: 0.4))
    func text(_ boldText: String) -> StyledText {
        StyledText("Plain \(boldText) and plain", runs: [
            StyledTextRun(length: 6, style: TextRunStyle(font: regular)),
            StyledTextRun(length: boldText.utf16.count, style: TextRunStyle(font: bold)),
            StyledTextRun(length: 10, style: TextRunStyle(font: regular))])
    }
    let options = TextLayoutOptions()
    func shape(_ t: StyledText) -> StyledShapedText {
        system.cache.styled(t, fonts: t.runs.map { system.cache.font(for: $0.style.font)! }, wrappingAt: 90, options: options)
    }
    let t = text("bold")
    let first = system.layOut(t, wrappingAt: 90, options: options, origin: (x: 4, y: 6), scaleFactor: 2)
    let box = shape(t).placement
    let misses = system.cache.misses
    #expect(box.placementsComputed == 1)
    for _ in 0..<3 {
        #expect(system.layOut(t, wrappingAt: 90, options: options, origin: (x: 4, y: 6), scaleFactor: 2) == first)
        _ = system.measure(t, wrappingAt: 90, options: options)
    }
    #expect(box.placementsComputed == 1, "\(box.placementsComputed) placements for one steady origin")
    #expect(system.cache.misses == misses, "a steady frame shaped again")
    _ = system.layOut(t, wrappingAt: 90, options: options, origin: (x: 4.5, y: 6), scaleFactor: 2)
    #expect(box.placementsComputed == 2)
    _ = system.layOut(text("bolder"), wrappingAt: 90, options: options, origin: (x: 4, y: 6), scaleFactor: 2)
    #expect(system.cache.misses == misses + 1)
    #expect(shape(text("bolder")).placement.placementsComputed == 1)
}
