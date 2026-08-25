import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

@Test func rectConvertsFromCoreTypes() {
    // Every field carries a distinct value so a transposition inside any
    // converter reddens the test instead of passing silently.
    let r = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(10), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(30), height: ScaledPixels(40))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(1), y: ScaledPixels(2)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(200))),
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

@Test func bufferIndicesAreStable() {
    // These are contract with the shader; changing them silently breaks binding.
    #expect(MUIRectBufferVertices.rawValue == 0)
    #expect(MUIRectBufferRects.rawValue == 1)
    #expect(MUIRectBufferViewport.rawValue == 2)
    #expect(MUIRectBufferProjection.rawValue == 3)

    #expect(MUIProbeBufferOut.rawValue == 0)
    #expect(MUIProbeBufferRect.rawValue == 1)
}
