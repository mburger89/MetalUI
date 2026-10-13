import Testing
import MetalUITextSystem
@testable import MetalUIPortableText

// GT-E: the portable system caches the origin-free `[LaidOutLine]` per
// `MeasureKey` (string, font, width, options) under the two-frame lifetime of
// its measurements, so a label that only moves is shaped once. Plain text only
// (GT-H): the styled layout is unchanged.

@MainActor
private func makeSystem() throws -> (PortableTextSystem, FontKey) {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
    let system = PortableTextSystem(resolver: resolver)
    return (system, system.resolveFont(FontDescriptor(family: nil, size: 14)))
}

private typealias Glyph = (key: GlyphKey, x: Int, y: Int)

@MainActor
private func glyphs(_ system: PortableTextSystem, _ font: FontKey, _ text: String = "12.5 mm",
                    width: Double? = nil, options: TextLayoutOptions = TextLayoutOptions(),
                    at origin: (x: Double, y: Double), scale: Float = 1) -> [Glyph] {
    system.placeGlyphs(text, font: font, wrappingAt: width, options: options, origin: origin,
                       scaleFactor: scale).map { ($0.key, $0.pixelX, $0.baselineY) }
}

private func same(_ a: [Glyph], _ b: [Glyph]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.x == $1.x && $0.y == $1.y }
}

/// 2.1
@MainActor
@Test func aMovingTextShapesOnce() throws {
    let (system, font) = try makeSystem()
    system.beginFrame()
    for index in 0..<100 {
        _ = glyphs(system, font, at: (x: Double(index) * 3.37, y: Double(index) * 1.21))
    }
    #expect(system.layOutCount == 1, "100 placements at 100 origins shape once")
}

/// 2.2
@MainActor
@Test func aCachedLayoutPlacesAsAFreshOneDoes() throws {
    let (cached, font) = try makeSystem()
    let origins: [(x: Double, y: Double)] = [(0, 0), (10.3, 20.7), (-4.25, 3.5), (99.99, 0.01)]
    var compared = 0
    for scale: Float in [1, 2] {
        cached.beginFrame()
        for text in ["12.5 mm", "Hamburg office"] {
            for origin in origins {
                let (fresh, freshFont) = try makeSystem()
                try #require(freshFont == font, "set up: one font key on both systems")
                fresh.beginFrame()
                let expected = glyphs(fresh, freshFont, text, at: origin, scale: scale)
                let actual = glyphs(cached, font, text, at: origin, scale: scale)
                try #require(!expected.isEmpty)
                #expect(same(actual, expected), "\(text) at \(origin) scale \(scale)")
                compared += 1
            }
        }
    }
    try #require(compared == 16)
    #expect(cached.layOutCount == 2, "two strings, shaped once each across origins and scales")
}

/// 2.3
@MainActor
@Test func measureThenPlaceShapesOnce() throws {
    let (system, font) = try makeSystem()
    system.beginFrame()
    _ = system.measure("12.5 mm", font: font, wrappingAt: nil, options: TextLayoutOptions())
    _ = glyphs(system, font, at: (x: 5, y: 5))
    #expect(system.layOutCount == 1, "measure then place")

    let (second, secondFont) = try makeSystem()
    second.beginFrame()
    _ = second.lineRanges("12.5 mm", font: secondFont, wrappingAt: nil, options: TextLayoutOptions())
    _ = glyphs(second, secondFont, at: (x: 5, y: 5))
    #expect(second.layOutCount == 1, "line ranges then place")
}

/// 2.4
@MainActor
@Test func theLayoutCacheForgetsAfterTwoFrames() throws {
    let (system, font) = try makeSystem()
    system.beginFrame()
    _ = glyphs(system, font, at: (x: 0, y: 0))
    system.endFrame()
    system.beginFrame()
    system.endFrame()
    system.beginFrame()
    _ = glyphs(system, font, at: (x: 0, y: 0))
    system.endFrame()
    #expect(system.layOutCount == 2, "unused for two frames, the next use shapes again")

    // Used every frame, it survives.
    let (steady, steadyFont) = try makeSystem()
    for index in 0..<5 {
        steady.beginFrame()
        _ = glyphs(steady, steadyFont, at: (x: Double(index), y: 0))
        steady.endFrame()
    }
    #expect(steady.layOutCount == 1, "a label used every frame is shaped once")
}

/// 2.5
@MainActor
@Test func widthAndOptionsAreInTheKey() throws {
    let (system, font) = try makeSystem()
    system.beginFrame()
    let text = "a long label that wraps onto several lines of text"
    _ = glyphs(system, font, text, width: 80, at: (x: 0, y: 0))
    _ = glyphs(system, font, text, width: 80, at: (x: 9, y: 9))
    #expect(system.layOutCount == 1)
    _ = glyphs(system, font, text, width: 120, at: (x: 0, y: 0))
    #expect(system.layOutCount == 2, "a different width is a second shape")
    _ = glyphs(system, font, text, width: 80, options: TextLayoutOptions(maxLines: 1), at: (x: 0, y: 0))
    #expect(system.layOutCount == 3, "a different maxLines is a third")
    _ = glyphs(system, font, text, width: 80, options: TextLayoutOptions(alignment: .center), at: (x: 0, y: 0))
    #expect(system.layOutCount == 4, "a different alignment is a fourth (options are the key)")
}
