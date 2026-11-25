import Testing
import MetalUIShaderTypes
@testable import MetalUIScene

// G52 (record 422): the arrays a scene allocates are sized to classes, not to the exact count. A streamed reply paints a few
// glyphs more every frame, and an array reserved at its exact count is a slightly larger request than the block malloc kept from
// the frame before, so its large-block cache never serves it and every frame leaves one more `Malloc Large (empty)` region.

private func glyph(_ id: Float, order: MUIUInt) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: id, y: 0), size: MUISize(width: 8, height: 12)),
             atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 8, height: 12)),
             contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1000, height: 1000)),
             maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: order, transform: 0)
}

private func rect(_ id: Float, order: MUIUInt) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: id, y: 0), size: MUISize(width: 10, height: 10)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1000, height: 1000)),
            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: order, shape: 0)
}

/// A finalized scene of `glyphs` glyphs and `rects` rectangles in emission order.
private func finalized(glyphs: Int, rects: Int = 0) -> Scene {
    var scene = Scene()
    for i in 0..<rects { scene.insert(rect(Float(i), order: MUIUInt(i))) }
    for i in 0..<glyphs { scene.insert(glyph(Float(i), order: MUIUInt(rects + i))) }
    scene.finalize()
    return scene
}

@Test func aCapacityClassIsAtMostAnEighthAboveTheCountAndExactBelowAKibiElement() {
    for count in [0, 1, 1023] { #expect(steadyCapacity(count) == count, "\(count)") }
    for count in [1024, 1025, 3000, 40_000, 40_960, 500_000] {
        let rounded = steadyCapacity(count)
        #expect(rounded >= count && rounded * 8 <= count * 9 + 8, "\(count) -> \(rounded)")
    }
    #expect(steadyCapacity(40_000) == steadyCapacity(40_700), "one class across a two percent step")
    #expect(steadyCapacity(40_960) == 40_960 && steadyCapacity(40_961) == 45_056, "classes are four-Ki steps there")
}

/// Mutation: `finalize` reserving the permuted arrays at the exact count again (the capacities then differ by whole pages).
@Test func aSceneAFewHundredGlyphsLargerFinalizesIntoTheSameCapacities() {
    let a = finalized(glyphs: 40_000, rects: 3_000)
    let b = finalized(glyphs: 40_700, rects: 3_050)
    #expect(a.glyphs.count != b.glyphs.count)
    #expect(a.glyphs.capacity == b.glyphs.capacity, "glyphs \(a.glyphs.capacity) against \(b.glyphs.capacity)")
    #expect(a.rects.capacity == b.rects.capacity, "rects \(a.rects.capacity) against \(b.rects.capacity)")
}

/// Mutation: `reserveCapacity(rects:glyphs:)` at the exact count.
@Test func aReserveForAFewHundredMoreGlyphsIsTheSameRequest() {
    var a = Scene(), b = Scene()
    a.reserveCapacity(rects: 3_000, glyphs: 40_000)
    b.reserveCapacity(rects: 3_050, glyphs: 40_700)
    #expect(a.glyphs.capacity == b.glyphs.capacity, "glyphs \(a.glyphs.capacity) against \(b.glyphs.capacity)")
    #expect(a.rects.capacity == b.rects.capacity, "rects \(a.rects.capacity) against \(b.rects.capacity)")
    #expect(a.glyphs.isEmpty && a.rects.isEmpty, "reserve only")
}

/// A scene whose emission order is not its draw order still sorts: the already-ordered shortcut must not skip it.
/// Mutation: the order check answering `true` always.
@Test func aSceneEmittedOutOfOrderIsStillSortedByLayerThenOrder() {
    var scene = Scene()
    scene.insert(glyph(0, order: 5)); scene.insert(glyph(1, order: 2)); scene.insert(rect(2, order: 9))
    scene.insert(glyph(3, order: 2), layer: -1)
    scene.finalize()
    #expect(scene.glyphs.map { $0.bounds.origin.x } == [3, 1, 0], "layer -1 first, then by order")
    #expect(scene.drawList.map(\.kind) == [.glyph, .rect] && scene.drawList.map(\.count) == [3, 1], "\(scene.drawList)")
}
