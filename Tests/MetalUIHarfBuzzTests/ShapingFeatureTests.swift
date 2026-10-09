import Foundation
import Testing
import MetalUIHarfBuzz

// Rich text, lane 1 (ruling `RT-H` item 3, spec test 1.18): tracking shapes a
// run with the optional ligatures off, through a feature list on
// `HarfBuzzShaper.shape`.

private let notoURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

/// **1.18** (`RT-H` item 3). With `liga`, `clig`, `dlig` and `hlig` off,
/// Noto Sans shapes "office" as one glyph per letter; with no features it
/// ligates (the positive control). Mutation: ignore `features`.
@Test func disablingLigaturesShapesTheLigatureAsSeparateGlyphs() throws {
    let font = try HarfBuzzFont(data: [UInt8](Data(contentsOf: notoURL)), size: 13)
    let ligated = try HarfBuzzShaper.shape("office", font: font, direction: .leftToRight, features: [])
    try #require(ligated.glyphs.count < 6, "set up: Noto Sans ligates office (\(ligated.glyphs.count) glyphs)")
    let separate = try HarfBuzzShaper.shape("office", font: font, direction: .leftToRight,
                                            features: ShapingFeature.ligaturesOff)
    #expect(separate.glyphs.count == 6)
    #expect(separate.glyphs.map(\.cluster) == [0, 1, 2, 3, 4, 5])
}
