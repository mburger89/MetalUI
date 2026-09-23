import Testing
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIPortableText

// `PortableText.emit`'s mask corner radii, `order` and `layer` — the three
// things `Frame.draw` stamps on a glyph from the frame's state
// (`activeClipRadii`, `order: 0`, `activeLayer`) that `emit` had no way to
// take, so a caller could neither round a text clip nor lift a run above a
// sibling's rects (record §28, "Open").

private let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 400, height: 100))
private let white = MUIHsla(h: 0, s: 0, l: 1, a: 1)
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)

private func emitHamburg(into scene: inout Scene, maskCornerRadii: MUICorners? = nil,
                         order: UInt32? = nil, layer: Int? = nil) throws {
    let font = try PortableFont(data: fontBytes(notoSans), size: 17)
    let atlas = GlyphAtlas(width: 256, height: 256)
    atlas.beginFrame()
    defer { atlas.endFrame() }
    // Each argument is passed only when given, so the defaults are exercised
    // by the same helper that exercises the values.
    switch (maskCornerRadii, order, layer) {
    case (nil, nil, nil):
        try PortableText.emit("Hamburg", font: font, origin: (10, 30), scaleFactor: 2,
                              color: white, contentMask: mask, into: &scene, atlas: atlas)
    case let (radii, order, layer):
        try PortableText.emit("Hamburg", font: font, origin: (10, 30), scaleFactor: 2,
                              color: white, contentMask: mask,
                              maskCornerRadii: radii ?? square,
                              order: order ?? 0, layer: layer ?? 0,
                              into: &scene, atlas: atlas)
    }
}

/// A full-size rect at `layer`/`order`, inserted after the glyphs.
private func insertRect(into scene: inout Scene, order: UInt32 = 0, layer: Int = 0) {
    scene.insert(MUIRect(bounds: mask, contentMask: mask, maskCornerRadii: square,
                         background: white, borderColor: white, cornerRadii: square,
                         borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: order, _reserved: 0), layer: layer)
}

private func kinds(_ scene: Scene) -> [PrimitiveKind] {
    var finalized = scene
    finalized.finalize()
    return finalized.drawList.map(\.kind)
}

@Test func theMaskCornerRadiiReachEveryEmittedGlyph() throws {
    let radii = MUICorners(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
    var scene = Scene()
    try emitHamburg(into: &scene, maskCornerRadii: radii)
    try #require(scene.glyphs.count == 7)
    for glyph in scene.glyphs {
        #expect(glyph.maskCornerRadii.topLeft == 1)
        #expect(glyph.maskCornerRadii.topRight == 2)
        #expect(glyph.maskCornerRadii.bottomRight == 3)
        #expect(glyph.maskCornerRadii.bottomLeft == 4)
    }
}

@Test func theOrderReachesEveryEmittedGlyph() throws {
    var scene = Scene()
    try emitHamburg(into: &scene, order: 9)
    try #require(scene.glyphs.count == 7)
    #expect(scene.glyphs.allSatisfy { $0.order == 9 })
}

/// The defaults are `Frame.draw`'s: a square mask, `order: 0`, layer 0 — so
/// every caller written before these parameters existed draws exactly as it
/// did, and `PT-H`'s pins cannot move.
@Test func theDefaultsAreASquareMaskOrderZeroAndLayerZero() throws {
    var scene = Scene()
    try emitHamburg(into: &scene)
    try #require(scene.glyphs.count == 7)
    for glyph in scene.glyphs {
        #expect(glyph.order == 0)
        #expect(glyph.maskCornerRadii.topLeft == 0 && glyph.maskCornerRadii.topRight == 0
                && glyph.maskCornerRadii.bottomRight == 0 && glyph.maskCornerRadii.bottomLeft == 0)
    }
    // Layer 0: a rect inserted afterwards at layer 0 paints after the text.
    insertRect(into: &scene)
    #expect(kinds(scene) == [.glyph, .rect])
}

/// The layer is the one parameter a glyph does not carry — `Scene` keeps it in
/// a side table — so it is observable only as paint order: text on layer 1
/// paints after a rect inserted later on layer 0, which is what lifting a
/// subtree (`Frame.pushLayer`) needs.
@Test func aHigherLayerPaintsAfterALaterRectOnALowerLayer() throws {
    var lifted = Scene()
    try emitHamburg(into: &lifted, layer: 1)
    insertRect(into: &lifted)
    #expect(kinds(lifted) == [.rect, .glyph])
}

/// Within one layer, a higher `order` paints after a later-inserted rect at a
/// lower one.
@Test func aHigherOrderPaintsAfterALaterRectWithALowerOrder() throws {
    var ordered = Scene()
    try emitHamburg(into: &ordered, order: 5)
    insertRect(into: &ordered, order: 1)
    #expect(kinds(ordered) == [.rect, .glyph])
}
