import CoreText
import Testing
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIPortableText
@testable import MetalUIText

// `PortableText.emitLines` (LB-H) end to end, through the atlas, and `emit`'s
// share of LB-I's glyph substitutions. Placement against the Apple path over
// the whole wrap corpus is `everyWrapCorpusCasePlacesTheSameGlyphsAsMetalUIsApplePath`;
// this file checks what that test cannot see — the sprites that reach the
// `Scene`, and the parameters.

private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
private let paragraph = "The quick brown fox jumps over the lazy dog.\nAffix the waffle: AV To."

/// `emitLines`' sprites, and the Apple path's for the same paragraph — the
/// Apple half with `Frame.draw`'s arithmetic, as `emitBothWays` does it.
private func bothWays(_ text: String, file: String, size: Double, width: Double?, scale: Float)
    throws -> (portable: [EmittedGlyph], apple: [EmittedGlyph], paragraph: PortableParagraph) {
    let oracle = try OracleFont(file)
    let portableFont = try oracle.portable(size: size)
    var scene = Scene()
    let portableAtlas = GlyphAtlas(width: 2048, height: 2048)
    portableAtlas.beginFrame()
    let emitted = try PortableText.emitLines(text, font: portableFont, origin: emissionOrigin,
                                             wrappingAt: width, scaleFactor: scale, color: inkColor,
                                             contentMask: contentMask, into: &scene, atlas: portableAtlas)
    portableAtlas.endFrame()
    let portable = scene.glyphs.map {
        EmittedGlyph(originX: $0.bounds.origin.x, originY: $0.bounds.origin.y,
                     width: $0.bounds.size.width, height: $0.bounds.size.height,
                     slotX: Int($0.atlasBounds.origin.x), slotY: Int($0.atlasBounds.origin.y),
                     slotWidth: Int($0.atlasBounds.size.width), slotHeight: Int($0.atlasBounds.size.height))
    }

    let appleFont = oracle.apple(size: size)
    let placed = Shaper.shape(text, font: appleFont, wrappingAt: width)
        .placedGlyphs(at: emissionOrigin, font: appleFont, scaleFactor: scale)
    let appleAtlas = GlyphAtlas(width: 2048, height: 2048)
    appleAtlas.beginFrame()
    var apple: [EmittedGlyph] = []
    for glyph in placed {
        guard let packed = appleAtlas.packed(for: glyph.key, rasterize: {
            GlyphRaster.rasterize(glyph: glyph.key.glyph, font: glyph.font,
                                  subpixelVariant: glyph.key.subpixelVariant,
                                  scaleFactor: glyph.key.scaleFactor)
        }) else { continue }
        guard packed.slot.width > 0, packed.slot.height > 0 else { continue }
        apple.append(EmittedGlyph(originX: Float(glyph.pixelX + packed.left),
                                  originY: Float(glyph.baselineY - packed.top),
                                  width: Float(packed.slot.width), height: Float(packed.slot.height),
                                  slotX: packed.slot.x, slotY: packed.slot.y,
                                  slotWidth: packed.slot.width, slotHeight: packed.slot.height))
    }
    appleAtlas.endFrame()
    return (portable, apple, emitted)
}

/// Every sprite's position and size equal to the Apple path's, over several
/// lines — the placement oracle's result carried through the atlas.
@Test func aWrappedParagraphLandsWhereMetalUIsApplePathDrawsIt() throws {
    for file in fontFiles {
        for (size, width, scale) in [(13.0, 120.0, Float(2)), (17, 90, 1), (26, 200, 2)] {
            let (portable, apple, emitted) = try bothWays(paragraph, file: file, size: size,
                                                           width: width, scale: scale)
            try #require(emitted.lines.count >= 3, "\(file) \(size)pt: the case must wrap")
            try #require(portable.count == apple.count, "\(file) \(size)pt: sprite counts")
            for (p, a) in zip(portable, apple) {
                #expect(p.originX == a.originX && p.originY == a.originY
                        && p.width == a.width && p.height == a.height,
                        note("\(file) \(size)pt x\(scale): (\(p.originX), \(p.originY)) \(p.width)x\(p.height)"
                             + " vs (\(a.originX), \(a.originY)) \(a.width)x\(a.height)"))
            }
        }
    }
}

/// The returned lines are `lines`' and the height is `ShapedText.totalHeight`'s
/// rule — spelled here from CoreText, not from `PortableFontMetrics`.
@Test func emitLinesReturnsTheLinesAndTheirTotalHeight() throws {
    let oracle = try OracleFont("NotoSans-Regular.ttf")
    let font = try oracle.portable(size: 13)
    var scene = Scene()
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    atlas.beginFrame()
    let emitted = try PortableText.emitLines(paragraph, font: font, origin: (0, 0), wrappingAt: 100,
                                             scaleFactor: 1, color: inkColor, contentMask: contentMask,
                                             into: &scene, atlas: atlas)
    atlas.endFrame()
    #expect(emitted.lines == (try PortableText.lines(paragraph, font: font, wrappingAt: 100)))
    let shaped = Shaper.shape(paragraph, font: oracle.apple(size: 13), wrappingAt: 100)
    try #require(emitted.lines.count == shaped.lines.count)
    #expect(emitted.height == shaped.totalHeight)
}

@Test func emitLinesStampsItsMaskOrderAndLayerOnEveryGlyph() throws {
    let font = try OracleFont("NotoSans-Regular.ttf").portable(size: 13)
    let radii = MUICorners(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
    var scene = Scene()
    let atlas = GlyphAtlas(width: 1024, height: 1024)
    atlas.beginFrame()
    try PortableText.emitLines(paragraph, font: font, origin: (0, 0), wrappingAt: 100, scaleFactor: 1,
                               color: inkColor, contentMask: contentMask, maskCornerRadii: radii,
                               order: 7, layer: 1, into: &scene, atlas: atlas)
    atlas.endFrame()
    try #require(scene.glyphs.count > 40)
    #expect(scene.glyphs.allSatisfy { $0.order == 7 && $0.maskCornerRadii.bottomLeft == 4 })
    // Layer 1: a rect inserted afterwards on layer 0 still paints first.
    scene.insert(MUIRect(bounds: contentMask, contentMask: contentMask, maskCornerRadii: square,
                         background: inkColor, borderColor: inkColor, cornerRadii: square,
                         borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, _reserved: 0), layer: 0)
    scene.finalize()
    #expect(scene.drawList.first?.kind == .rect)
}

/// `emit` draws what CoreText draws for a newline: nothing visible, rather
/// than `.notdef`'s box. (A soft hyphen is not checked here: HarfBuzz already
/// shapes it as the inkless space glyph, so no sprite count can see its drop —
/// only `everyWrapCorpusCasePlacesTheSameGlyphsAsMetalUIsApplePath`, which
/// compares glyph ids, does.)
@Test func emitDrawsNoGlyphForANewline() throws {
    let font = try OracleFont("NotoSans-Regular.ttf").portable(size: 17)
    func sprites(_ text: String) throws -> Int {
        var scene = Scene()
        let atlas = GlyphAtlas(width: 1024, height: 1024)
        atlas.beginFrame()
        defer { atlas.endFrame() }
        try PortableText.emit(text, font: font, origin: (0, 20), scaleFactor: 1, color: inkColor,
                              contentMask: contentMask, into: &scene, atlas: atlas)
        return scene.glyphs.count
    }
    #expect(try sprites("Ready\n") == sprites("Ready"))
    #expect(try sprites("a\u{2029}\tb\r") == sprites("ab"))
}
