import Testing
import Metal
import simd
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3])  // r, g, b, a
}

/// The single most load-bearing constant on this branch, and the one nothing
/// else in the suite can catch.
///
/// Spec 7.8 composites in gamma-encoded sRGB. `bgra8Unorm` blends on the stored
/// gamma-encoded values; an `_sRGB` target makes the hardware decode to linear
/// before blending and re-encode after — which is linear compositing, the exact
/// opposite of the decision. Flipping this constant does not fail any other
/// test: `renderOffscreen` reads the same constant, so the offscreen target
/// flips with it, and nothing in M0 blends translucent over opaque, which is
/// the only thing that distinguishes the two. The damage would surface a
/// milestone later as wrong text rendering (thin, washed light-on-dark;
/// heavy dark-on-light) rather than as a red test here.
///
/// The real guard, once M1 has an alpha-blending path: draw 50%-alpha white
/// over opaque black and read back the centre. Gamma compositing (this format)
/// gives roughly 128; linear compositing (`_sRGB`) gives roughly 188. That is
/// not implementable in M0 — the scene has no translucent-over-opaque path to
/// drive — so it is recorded here rather than written.
@Test @MainActor func drawableFormatIsGammaEncodedNotSRGB() {
    #expect(Renderer.pixelFormat == .bgra8Unorm)
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

    // Probes straddling every edge. Centre-only probes cannot tell a correctly
    // placed rect from a displaced or resized one: both of those mutations pass
    // the two checks above. These pin origin and size on both axes.
    // The rect spans x and y in [20, 80); pixel centres sit at +0.5.
    #expect(bgra(pixels, 21, 50, width: 100).3 > 200)   // just inside left
    #expect(bgra(pixels, 18, 50, width: 100).3 < 40)    // just outside left
    #expect(bgra(pixels, 78, 50, width: 100).3 > 200)   // just inside right
    #expect(bgra(pixels, 82, 50, width: 100).3 < 40)    // just outside right
    #expect(bgra(pixels, 50, 21, width: 100).3 > 200)   // just inside top
    #expect(bgra(pixels, 50, 18, width: 100).3 < 40)    // just outside top
    #expect(bgra(pixels, 50, 78, width: 100).3 > 200)   // just inside bottom
    #expect(bgra(pixels, 50, 82, width: 100).3 < 40)    // just outside bottom
}

/// White and black are symmetric under a red/blue swap, so the rest of this
/// file would pass with the BGRA readback or `hsla_to_srgba` channels
/// transposed. This asserts an asymmetric colour, channel by channel.
@Test @MainActor func channelsAreNotTransposed() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    func fill(_ color: Hsla) throws -> (UInt8, UInt8, UInt8, UInt8) {
        var scene = Scene()
        scene.insert(MUIRect(
            bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            background: color, borderColor: color,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
        scene.finalize()
        let pixels = try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))
        return bgra(pixels, 50, 50, width: 100)
    }

    let red = try fill(.rgb(0xFF0000))
    #expect(red.0 > 200)   // r
    #expect(red.1 < 40)    // g
    #expect(red.2 < 40)    // b
    #expect(red.3 > 200)

    let blue = try fill(.rgb(0x0000FF))
    #expect(blue.0 < 40)   // r
    #expect(blue.1 < 40)   // g
    #expect(blue.2 > 200)  // b
    #expect(blue.3 > 200)
}

/// The `projection` on `SurfaceView` exists so a stereo backend can hand the
/// renderer per-eye matrices (spec 3.2). If the shader ignored it, both eyes
/// would render identically -- so this asserts the pixels actually move.
@Test @MainActor func projectionMatrixMovesTheRenderedRect() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(20), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(60), height: ScaledPixels(60))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white, borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let size = Size(width: DevicePixels(100), height: DevicePixels(100))

    // Identity: the rect covers x in [20, 80).
    let identity = try renderer.renderOffscreen(scene, size: size)
    #expect(bgra(identity, 30, 50, width: 100).3 > 200)
    #expect(bgra(identity, 90, 50, width: 100).3 < 40)

    // NDC spans [-1, 1] across 100px, so +0.4 in x translates by +20px.
    let translate = simd_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                            SIMD4<Float>(0, 1, 0, 0),
                                            SIMD4<Float>(0, 0, 1, 0),
                                            SIMD4<Float>(0.4, 0, 0, 1)))
    let shifted = try renderer.renderOffscreen(scene, size: size, projection: translate)

    // Both probes flip: the rect now covers x in [40, 100).
    #expect(bgra(shifted, 30, 50, width: 100).3 < 40)
    #expect(bgra(shifted, 90, 50, width: 100).3 > 200)
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
