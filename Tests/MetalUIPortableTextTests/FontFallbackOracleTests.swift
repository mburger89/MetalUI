import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// FB-A/FB-B: font fallback against CoreText given the same cascade. Source
// Sans 3 is the requested face and Noto Sans the one fallback — on the Apple
// side through `kCTFontCascadeListAttribute`, on the portable side through the
// resolver's registration order. The characters are ones Noto Sans draws and
// Source Sans 3 does not (1,018 of U+0020…U+2FFF, measured), inside Latin
// text, wrapped at many widths.

let fallbackStrings = [
    "Ƃƃ Source Ƅƅ Sans",
    "The ƈƉ fallback ƍƎ inside ƒ words",
    "ǄǅǆǇǈǉǊǋǌ digraphs and ǞǟǠǡ letters",
    "mixed: Ɠ at the start, ƞ in the middle, Ʀ at the end Ʀ",
    "Ƣƣ Ƥƥ Ʀ Ƨƨ Ʃ ƪ ƫ Ƭƭ Ʈ Ưư Ʊ Ʋ Ƴƴ Ƶƶ Ʒ Ƹƹ ƺ ƻ Ƽƽ ƾ ƿ",
    "no fallback at all here",
]

@MainActor
func appleCascade(size: Double) throws -> ResolvedFont {
    func descriptor(_ file: String) throws -> CTFontDescriptor {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts").appendingPathComponent(file)
        return try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
    }
    let primary = try descriptor("SourceSans3-Regular.otf")
    let cascaded = CTFontDescriptorCreateCopyWithAttributes(primary, [
        kCTFontCascadeListAttribute: [try descriptor("NotoSans-Regular.ttf")]] as CFDictionary)
    return ResolvedFont(ctFont: CTFontCreateWithFontDescriptor(cascaded, CGFloat(size), nil))
}

func portableCascade(size: Double) throws -> PortableFont {
    let resolver = try PortableFontResolver(defaultFont: fontBytes("SourceSans3-Regular.otf"))
    try resolver.register(fontBytes("NotoSans-Regular.ttf"))
    return try resolver.resolve(family: nil, size: size)
}

struct FallbackPlaced: Equatable, CustomStringConvertible {
    let face: String, id: UInt16, pixelX: Int, variant: Int, baselineY: Int
    var description: String { "\(face.prefix(4))#\(id)@\(pixelX).\(variant),\(baselineY)" }
}

@MainActor
func fallbackDifferences() throws -> (cases: Int, fallbackGlyphs: Int, differences: [String]) {
    var cases = 0, fallbackGlyphs = 0
    var differences: [String] = []
    for size in [11.0, 13, 17, 26] {
        let apple = try appleCascade(size: size), portable = try portableCascade(size: size)
        for width in [nil] + stride(from: 20.0, through: 300, by: 7).map({ Optional($0) }) {
            for text in fallbackStrings {
                cases += 1
                let a = Shaper.shape(text, font: apple, wrappingAt: width)
                    .placedGlyphs(at: (3.3, 7.6), font: apple, scaleFactor: 2)
                    .map { FallbackPlaced(face: $0.key.font.postScriptName, id: $0.key.glyph, pixelX: $0.pixelX,
                                          variant: $0.key.subpixelVariant, baselineY: $0.baselineY) }
                let p = try PortableText.placements(text, font: portable, origin: (3.3, 7.6), wrappingAt: width,
                                                    scaleFactor: 2).placements.map {
                    let split = GlyphImage.subpixelPlacement(forDeviceX: $0.deviceX)
                    return FallbackPlaced(face: $0.font.key.postScriptName, id: $0.id, pixelX: split.pixelX,
                                          variant: split.variant, baselineY: $0.baselineY)
                }
                fallbackGlyphs += a.filter { $0.face == "NotoSans-Regular" }.count
                if a != p {
                    let i = (0..<min(a.count, p.count)).first { a[$0] != p[$0] } ?? min(a.count, p.count)
                    differences.append("\(size)pt w=\(width.map { "\($0)" } ?? "nil") \(text.debugDescription): "
                        + "\(a.count) vs \(p.count) glyphs; first difference at \(i): apple \(i < a.count ? "\(a[i])" : "-") portable \(i < p.count ? "\(p[i])" : "-")")
                }
            }
        }
    }
    return (cases, fallbackGlyphs, differences)
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_FALLBACK_MEASURE"] == "1"))
func measureFallbackDifferences() throws {
    let (cases, glyphs, differences) = try fallbackDifferences()
    print("FALLBACK cases=\(cases) fallbackGlyphs=\(glyphs) differences=\(differences.count)")
    for line in differences.prefix(30) { print("FALLBACK \(line)") }
}

/// Measured: 1,008 cases, 7,728 glyphs from the fallback face, 0 differing —
/// glyph ids, faces, device pixel, subpixel variant, baseline.
@MainActor
@Test func fallbackPlacesEveryGlyphAsCoreTextsCascadeDoes() throws {
    let (cases, fallbackGlyphs, differences) = try fallbackDifferences()
    try #require(cases == 1008)
    #expect(fallbackGlyphs > 5000, "the corpus must reach the fallback")
    #expect(differences.isEmpty, "\(differences.count) differ; first: \(differences.first ?? "")")
}

/// The control: without a cascade the portable side draws `.notdef` where
/// CoreText falls back, so the equality above is the cascade's doing.
@MainActor
@Test func withoutACascadeEveryFallbackStringDiffers() throws {
    let apple = try appleCascade(size: 13)
    let bare = try PortableFont(data: fontBytes("SourceSans3-Regular.otf"), size: 13)
    for text in fallbackStrings {
        let a = Shaper.shape(text, font: apple, wrappingAt: nil).placedGlyphs(at: (0, 0), font: apple, scaleFactor: 1)
        let p = try PortableText.placements(text, font: bare, origin: (0, 0), wrappingAt: nil, scaleFactor: 1).placements
        let needsFallback = a.contains { $0.key.font.postScriptName == "NotoSans-Regular" }
        #expect(needsFallback == (a.map(\.key.glyph) != p.map(\.id)), "\(text)")
    }
}

/// Through the text system: a fallback glyph is keyed on, and rasterized
/// from, the fallback face.
@MainActor
@Test func theTextSystemRasterizesAFallbackGlyphFromItsOwnFace() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes("SourceSans3-Regular.otf"))
    try resolver.register(fontBytes("NotoSans-Regular.ttf"))
    let system = PortableTextSystem(resolver: resolver)
    let font = system.resolveFont(family: nil, size: 17)
    let glyphs = system.placeGlyphs("aƂ", font: font, wrappingAt: nil, origin: (0, 20), scaleFactor: 1)
    try #require(glyphs.count == 2)
    #expect(glyphs[0].key.font.postScriptName == "SourceSans3-Regular")
    #expect(glyphs[1].key.font.postScriptName == "NotoSans-Regular")
    #expect(!system.rasterize(glyphs[1].key).isEmpty)
}
