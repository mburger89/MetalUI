import MetalUIScene
import MetalUITextSystem
import Testing
@testable import MetalUIText

/// `G50` (record 415): what one placed glyph weighs. A streamed message of N glyphs costs N times this
/// in the placement memo and again in the per-frame glyph array, on every frame its text changes, so
/// the stride is the lever on `phys_footprint` for a long transcript. Each bound is the measured size
/// after the fix with a little room; before it, `FontKey` 88, `GlyphKey` 128, `PlacedGlyph` 264,
/// `TextGlyph` 144.
@Test func aFontKeyIsAReferenceAndTwoWords() {
    #expect(MemoryLayout<FontKey>.stride <= 24, "FontKey: \(MemoryLayout<FontKey>.stride)")
}

@Test func aGlyphKeyAndATextGlyphStayUnderAHalfOfWhatTheyWere() {
    #expect(MemoryLayout<GlyphKey>.stride <= 64, "GlyphKey: \(MemoryLayout<GlyphKey>.stride)")
    #expect(MemoryLayout<TextGlyph>.stride <= 80, "TextGlyph: \(MemoryLayout<TextGlyph>.stride)")
}

@Test func aPlacedGlyphStaysUnderAThirdOfItsFormerSize() {
    #expect(MemoryLayout<PlacedGlyph>.stride <= 96, "PlacedGlyph: \(MemoryLayout<PlacedGlyph>.stride)")
}

/// The font is one reference per run (a line of one font is one run), not a copy per glyph.
@MainActor
@Test func theGlyphsOfOneRunShareOneFontBox() {
    let (_, font, shaped) = footprintShape(prose(60), width: 200)
    let placed = shaped.placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 2)
    #expect(placed.count > 100)
    let boxes = Set(placed.map { ObjectIdentifier($0.placedFont) })
    #expect(boxes.count <= shaped.lines.count, "\(boxes.count) font boxes for \(shaped.lines.count) lines of \(placed.count) glyphs")
    #expect(placed[0].font.key == font.key)
}

@MainActor
private func footprintShape(_ string: String, width: Double) -> (cache: ShapingCache, font: ResolvedFont, shaped: ShapedText) {
    let cache = ShapingCache()
    let font = cache.resolveFont(FontDescriptor(size: 13))
    return (cache, font, cache.shaped(string, font: font, wrappingAt: width, options: TextLayoutOptions()))
}

private func prose(_ words: Int) -> String { (0..<words).map { "token\($0)" }.joined(separator: " ") }

@Test func aCapacityClassIsAtMostAQuarterAboveTheCount() {
    for count in [1, 63, 64, 65, 100, 1000, 3000, 14_000, 70_000] {
        let rounded = GlyphCapacity.rounded(count)
        #expect(rounded >= count && rounded * 4 <= count * 5 + 4, "\(count) -> \(rounded)")
    }
    #expect(GlyphCapacity.rounded(1000) == GlyphCapacity.rounded(1020), "one class across a two percent step")
}

/// The placement memo of a text a few glyphs longer is the same request to malloc, so a freed one is reusable.
@MainActor
@Test func aTextAFewGlyphsLongerReservesItsPlacementMemoAtTheSameCapacity() {
    let (_, font, shortShaped) = footprintShape(prose(300), width: 400)
    let (_, _, longShaped) = footprintShape(prose(300) + " token300 token301", width: 400)
    let short = shortShaped.placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 2)
    let long = longShaped.placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 2)
    #expect(long.count > short.count)
    #expect(shortShaped.placement.memo.capacity == longShaped.placement.memo.capacity,
            "\(shortShaped.placement.memo.capacity) vs \(longShaped.placement.memo.capacity)")
}

/// `placeGlyphs` writes into the block the call before it returned, while that text keeps growing.
@MainActor
@Test func aGrowingTextIsPlacedIntoTheSameGlyphArrayEveryFrame() {
    let system = CoreTextTextSystem()
    let font = system.resolveFont(FontDescriptor(size: 13))
    func place(_ words: Int) -> Int {
        system.placeGlyphs(prose(words), font: font, wrappingAt: 400, options: TextLayoutOptions(),
                           origin: (x: 0, y: 0), scaleFactor: 2).count
    }
    #expect(place(400) > 0)
    #expect(system.glyphBuffer.reuses == 0)
    for words in 401...440 { _ = place(words) }
    #expect(system.glyphBuffer.reuses >= 35, "reused \(system.glyphBuffer.reuses) of 40")
    // The text shrinks to a tenth: the big block is let go instead of held.
    let before = system.glyphBuffer.reuses
    _ = place(20)
    #expect(system.glyphBuffer.reuses == before, "a ten-times-smaller text kept the large block")
}
