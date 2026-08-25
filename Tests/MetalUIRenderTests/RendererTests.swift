import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3])  // r, g, b, a
}

@Test @MainActor func rendererDrawsAFilledRectWhereExpected() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(20), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(60), height: ScaledPixels(60))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let inside = bgra(pixels, 50, 50, width: 100)
    #expect(inside.0 > 200 && inside.1 > 200 && inside.2 > 200)   // white fill
    #expect(inside.3 > 200)                                        // opaque

    let outside = bgra(pixels, 5, 5, width: 100)
    #expect(outside.3 < 40)                                        // cleared, transparent
}

@Test @MainActor func cornerRadiusRoundsTheCorners() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white, borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(30)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    // The extreme corner is outside a 30pt radius; the centre is inside.
    #expect(bgra(pixels, 1, 1, width: 100).3 < 40)
    #expect(bgra(pixels, 50, 50, width: 100).3 > 200)
}

@Test @MainActor func borderPaintsADistinctColorAtTheEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .black,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(10)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let onBorder = bgra(pixels, 5, 50, width: 100)
    #expect(onBorder.0 > 200)                       // white border

    let inField = bgra(pixels, 50, 50, width: 100)
    #expect(inField.0 < 40 && inField.3 > 200)      // black fill, still opaque
}
