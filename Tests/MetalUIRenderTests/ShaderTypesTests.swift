import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

@Test func rectConvertsFromCoreTypes() {
    let r = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(10), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(30), height: ScaledPixels(40))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: Hsla(h: 0.5, s: 0.4, l: 0.3, a: 1),
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(6)),
        borderWidths: Edges(all: ScaledPixels(2)),
        order: 3)

    #expect(r.bounds.origin.x == 10)
    #expect(r.bounds.size.height == 40)
    #expect(r.cornerRadii.bottomLeft == 6)
    #expect(r.borderWidths.top == 2)
    #expect(r.background.h == 0.5)
    #expect(r.borderColor.l == 1)
    #expect(r.order == 3)
}

@Test func bufferIndicesAreStable() {
    // These are contract with the shader; changing them silently breaks binding.
    #expect(MUIRectBufferVertices.rawValue == 0)
    #expect(MUIRectBufferRects.rawValue == 1)
    #expect(MUIRectBufferViewport.rawValue == 2)
}
