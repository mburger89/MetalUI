import Testing
import Foundation
import MetalUIHarfBuzz

// Placeholder: the CoreText oracle tests (SH-G, SH-H) replace this.
func fontBytes(_ name: String) throws -> [UInt8] {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fonts/\(name)")
    return [UInt8](try Data(contentsOf: path))
}

@Test func shapingProducesGlyphsAndAdvances() throws {
    let font = try HarfBuzzFont(data: fontBytes("NotoSans-Regular.ttf"), size: 13)
    let run = try HarfBuzzShaper.shape("AV Hi", font: font)
    #expect(run.glyphs.count == 5)
    #expect(run.glyphs.map(\.cluster) == [0, 1, 2, 3, 4])
    #expect(run.glyphs.allSatisfy { $0.id != 0 })
    #expect(run.advance > 0 && !run.isRightToLeft)
    print("SMOKE ids=\(run.glyphs.map(\.id)) advances=\(run.glyphs.map { ($0.xAdvance * 1000).rounded() / 1000 }) total=\(run.advance)")
}
