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

@Test func aPlacedGlyphStaysUnderHalfOfItsFormerSize() {
    #expect(MemoryLayout<PlacedGlyph>.stride <= 136, "PlacedGlyph: \(MemoryLayout<PlacedGlyph>.stride)")
}
