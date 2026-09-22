import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender
@testable import MetalUIScene  // DrawRun/AtlasSlot memberwise inits (PS-F)
// `@testable` so this file can build an `AtlasSlot` directly (its init is
// internal to `MetalUIText`) without pulling in CoreText/font rasterization
// just to exercise the `MUIGlyph` converter below.
@testable import MetalUIText

@Test func rectConvertsFromCoreTypes() {
    // Every field carries a distinct value so a transposition inside any
    // converter reddens the test instead of passing silently.
    let r = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(10), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(30), height: ScaledPixels(40))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(1), y: ScaledPixels(2)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(200))),
        // Distinct from `cornerRadii` below, so a converter that passed
        // `cornerRadii` for both would still redden this.
        maskCornerRadii: Corners(topLeft: ScaledPixels(12), topRight: ScaledPixels(13),
                                 bottomRight: ScaledPixels(14), bottomLeft: ScaledPixels(15)),
        background: Hsla(h: 0.5, s: 0.4, l: 0.3, a: 0.2),
        borderColor: .white,
        cornerRadii: Corners(topLeft: ScaledPixels(3), topRight: ScaledPixels(4),
                             bottomRight: ScaledPixels(5), bottomLeft: ScaledPixels(6)),
        borderWidths: Edges(top: ScaledPixels(7), right: ScaledPixels(8),
                            bottom: ScaledPixels(9), left: ScaledPixels(11)),
        order: 3)

    #expect(r.bounds.origin.x == 10)
    #expect(r.bounds.origin.y == 20)
    #expect(r.bounds.size.width == 30)
    #expect(r.bounds.size.height == 40)

    // Distinct from bounds: catches MUIRect.init passing `bounds` twice.
    #expect(r.contentMask.origin.x == 1)
    #expect(r.contentMask.origin.y == 2)
    #expect(r.contentMask.size.width == 100)
    #expect(r.contentMask.size.height == 200)

    #expect(r.background.h == 0.5)
    #expect(r.background.s == 0.4)
    #expect(r.background.l == 0.3)
    #expect(r.background.a == 0.2)

    #expect(r.borderColor.h == 0)
    #expect(r.borderColor.s == 0)
    #expect(r.borderColor.l == 1)
    #expect(r.borderColor.a == 1)

    #expect(r.maskCornerRadii.topLeft == 12)
    #expect(r.maskCornerRadii.topRight == 13)
    #expect(r.maskCornerRadii.bottomRight == 14)
    #expect(r.maskCornerRadii.bottomLeft == 15)

    #expect(r.cornerRadii.topLeft == 3)
    #expect(r.cornerRadii.topRight == 4)
    #expect(r.cornerRadii.bottomRight == 5)
    #expect(r.cornerRadii.bottomLeft == 6)

    #expect(r.borderWidths.top == 7)
    #expect(r.borderWidths.right == 8)
    #expect(r.borderWidths.bottom == 9)
    #expect(r.borderWidths.left == 11)

    #expect(r.order == 3)
    #expect(r._reserved == 0)
}

/// The `MUIGlyph` converter's own `contentMask`/`bounds` differential.
///
/// `bounds` and `contentMask` are the same type and adjacent in the argument
/// list, so a converter that silently passed `bounds` for both would still
/// compile and would agree with every other assertion. This is
/// `docs/practices/verifying-tests-can-fail.md`'s shape 1, named there almost
/// verbatim after `MUIRect`'s own converter had exactly this bug — and
/// `Frame.draw` is `MUIGlyph`'s only production caller of this init, so a
/// silent `bounds`-for-`contentMask` swap here would clip every glyph the
/// framework ever draws to its own bounding box now that Task 5 makes masks
/// real, with nothing else in the suite noticing (every other test that
/// touches `contentMask` builds `MUIGlyph` through the raw C struct init,
/// bypassing this converter entirely).
@Test func glyphConvertsFromCoreTypes() {
    // Distinct from `bounds` in every component, which is the whole point.
    let slot = AtlasSlot(x: 5, y: 6, width: 7, height: 8)
    let g = MUIGlyph(
        bounds: Bounds(origin: Point(x: ScaledPixels(10), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(30), height: ScaledPixels(40))),
        slot: slot,
        contentMask: Bounds(origin: Point(x: ScaledPixels(1), y: ScaledPixels(2)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(200))),
        maskCornerRadii: Corners(topLeft: ScaledPixels(12), topRight: ScaledPixels(13),
                                 bottomRight: ScaledPixels(14), bottomLeft: ScaledPixels(15)),
        color: Hsla(h: 0.5, s: 0.4, l: 0.3, a: 0.2),
        order: 3)

    #expect(g.bounds.origin.x == 10)
    #expect(g.bounds.origin.y == 20)
    #expect(g.bounds.size.width == 30)
    #expect(g.bounds.size.height == 40)

    #expect(g.atlasBounds.origin.x == 5)
    #expect(g.atlasBounds.origin.y == 6)
    #expect(g.atlasBounds.size.width == 7)
    #expect(g.atlasBounds.size.height == 8)

    // Catches `MUIGlyph.init` passing `bounds` for `contentMask`.
    #expect(g.contentMask.origin.x == 1)
    #expect(g.contentMask.origin.y == 2)
    #expect(g.contentMask.size.width == 100)
    #expect(g.contentMask.size.height == 200)

    #expect(g.maskCornerRadii.topLeft == 12)
    #expect(g.maskCornerRadii.topRight == 13)
    #expect(g.maskCornerRadii.bottomRight == 14)
    #expect(g.maskCornerRadii.bottomLeft == 15)

    #expect(g.color.h == 0.5)
    #expect(g.color.s == 0.4)
    #expect(g.color.l == 0.3)
    #expect(g.color.a == 0.2)

    #expect(g.order == 3)
    #expect(g._reserved == 0)
}

@Test func bufferIndicesAreStable() {
    // These are contract with the shader; changing them silently breaks binding.
    #expect(MUIRectBufferVertices.rawValue == 0)
    #expect(MUIRectBufferRects.rawValue == 1)
    #expect(MUIRectBufferViewport.rawValue == 2)
    #expect(MUIRectBufferProjection.rawValue == 3)

    #expect(MUIProbeBufferOut.rawValue == 0)
    #expect(MUIProbeBufferRect.rawValue == 1)
}
