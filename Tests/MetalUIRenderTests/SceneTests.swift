import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func rect(order: UInt32, x: Float) -> MUIRect {
    MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(1), height: ScaledPixels(1))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            background: .white, borderColor: .black,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: order)
}

@Test func sceneStartsEmptyAndClears() {
    var s = Scene()
    #expect(s.isEmpty)
    s.insert(rect(order: 0, x: 0))
    #expect(!s.isEmpty)
    s.clear()
    #expect(s.isEmpty)
}

@Test func finalizeSortsByOrder() {
    var s = Scene()
    s.insert(rect(order: 2, x: 20))
    s.insert(rect(order: 0, x: 0))
    s.insert(rect(order: 1, x: 10))
    s.finalize()
    #expect(s.rects.map(\.order) == [0, 1, 2])
}

@Test func finalizeIsStableForEqualOrders() {
    // A regression tripwire, not a test of the current comparator: Swift's sort
    // is stable at every size measured (checked up to 5000 elements, with and
    // without a tiebreaker), so no element count can make this fail today. It
    // exists to fail loudly if the sort is ever swapped for a non-stable one.
    let count = 40
    var s = Scene()
    for i in 0..<count {
        s.insert(rect(order: 1, x: Float(i)))
    }
    s.finalize()
    // Insertion order must survive: painters at the same order layer in sequence.
    #expect(s.rects.map(\.bounds.origin.x) == (0..<count).map { Float($0) })
}

/// 1.3 — `isEmpty` reads all three arrays (ruling TE-AF item 4).
/// `Renderer.encode` returns early on an empty scene, so a scene holding only
/// an image that read as empty would draw nothing with no error — the hazard
/// `aSceneHoldingOnlyAGlyphIsNotEmpty` names for glyphs. `clear()` empties
/// the images and the textures they sample too.
@Test func aSceneHoldingOnlyAnImageIsNotEmpty() {
    var s = Scene()
    let texture = ImageTexture(width: 1, height: 1, premultipliedRGBA: [0, 0, 0, 255])
    s.insert(MUIImage(bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                     size: Size(width: ScaledPixels(1), height: ScaledPixels(1))),
                      contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                          size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
                      opacity: 1, filter: .linear, order: 0),
             texture: texture)
    #expect(!s.isEmpty)
    s.clear()
    #expect(s.isEmpty)
    #expect(s.images.isEmpty && s.textures.isEmpty)
}

private func record(_ tx: Float) -> MUITransform {
    MUITransform(a: 0, b: 1, c: -1, d: 0, tx: tx, ty: 0, pixelScale: 1, _reserved: 0,
                 outerMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 100, height: 100)),
                 outerMaskRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0))
}

/// 1.10 (ruling GX-F) — a transform is carried once and named from 1: rects
/// under T, T, none, U leave the table [T, U] and the packed words naming
/// 1, 1, 0, 2 above the shape byte; a glyph and an image name theirs in
/// `transform` and above the filter byte. `finalize()` (twice) permutes the
/// primitives and never the table; `clear()` empties it.
@Test func theTransformTableIsCarriedOnceAndIndexedFromOne() {
    var s = Scene()
    let t = record(10), u = record(20)
    s.insert(rect(order: 0, x: 0), transform: t)
    s.insert(rect(order: 0, x: 1), transform: t)
    s.insert(rect(order: 0, x: 2))
    s.insert(rect(order: 0, x: 3), transform: u)
    s.insert(MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1, height: 1)),
                      atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1, height: 1)),
                      contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1, height: 1)),
                      maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                      color: MUIHsla(h: 0, s: 0, l: 0, a: 1), order: 0, transform: 0), transform: u)
    let texture = ImageTexture(width: 1, height: 1, premultipliedRGBA: [0, 0, 0, 255])
    s.insert(MUIImage(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1, height: 1)),
                      contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1, height: 1)),
                      maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                      opacity: 1, texture: 0, filter: 1, order: 0), texture: texture, transform: t)
    func check(_ label: String) {
        #expect(s.transforms.map(\.tx) == [10, 20], "\(label): table")
        #expect(s.rects.map { $0.shape >> 8 } == [1, 1, 0, 2], "\(label): rect indices")
        #expect(s.rects.map { $0.shape & 0xFF } == [0, 0, 0, 0], "\(label): rect shapes")
        #expect(s.glyphs.map(\.transform) == [2], "\(label): glyph")
        #expect(s.images.map(\.filter) == [1 | 1 << 8], "\(label): image")
    }
    check("inserted")
    s.finalize(); check("finalized")
    s.finalize(); check("finalized twice")
    s.clear()
    #expect(s.transforms.isEmpty)
}

/// 1.11 — a transform is per instance, so two rects under different
/// transforms are still one run (one draw call).
@Test func aTransformNeverBreaksARun() {
    var s = Scene()
    s.insert(rect(order: 0, x: 0), transform: record(10))
    s.insert(rect(order: 0, x: 1), transform: record(20))
    s.insert(rect(order: 0, x: 2))
    s.finalize()
    #expect(s.drawList.map { "\($0.kind) \($0.start)+\($0.count)" } == ["rect 0+3"])
}
