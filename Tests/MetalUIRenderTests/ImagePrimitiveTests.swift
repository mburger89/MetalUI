import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// Lane 1 of plan task 11 part 2 (ruling TE-AF): `MUIImage` samples an RGBA8
// texture the `Scene` carries — bilinear with clamped edges by default,
// nearest as a texel read — premultiplied, masked, and cached by the
// renderer per `ImageTexture` identity, released when a frame stops using it.

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3]))
}

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
    Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)),
           size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
}

private func image(_ bounds: Bounds<ScaledPixels>, mask: Bounds<ScaledPixels>,
                   maskRadius: Float = 0, opacity: Float = 1,
                   filter: ImageFilter = .linear) -> MUIImage {
    MUIImage(bounds: bounds, contentMask: mask,
             maskCornerRadii: Corners(all: ScaledPixels(maskRadius)),
             opacity: opacity, filter: filter, order: 0)
}

/// Red then blue, one row: I8's texture.
private let redBlue = ImageTexture(width: 2, height: 1,
                                   straightRGBA: [255, 0, 0, 255, 0, 0, 255, 255])

@MainActor
private func makeRenderer() throws -> Renderer {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    return try Renderer(device: device)
}

@MainActor
private func render(_ scene: Scene, renderer: Renderer? = nil, width: Int, height: Int) throws -> [UInt8] {
    var scene = scene
    scene.finalize()
    return try (renderer ?? makeRenderer()).renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(width)), height: DevicePixels(Int32(height))))
}

/// 1.5 — I8's default row: a 2-texel image over 100 px is exactly bilinear
/// with texel centres at 25 and 75, and clamped outside them. Expected values
/// derived before the run: at pixel x the sample point is `(x + 0.5) / 50 −
/// 0.5` texels from the first centre, clamped to 0…1, and red is 255 × (1 − t).
@Test @MainActor func anImageSamplesBilinearlyWithClampedEdges() throws {
    var scene = Scene()
    scene.insert(image(box(0, 0, 100, 10), mask: box(0, 0, 100, 10)), texture: redBlue)
    let pixels = try render(scene, width: 100, height: 10)
    for x in [0, 10, 24, 25, 37, 49, 50, 62, 74, 75, 90, 99] {
        let t = min(max((Double(x) + 0.5) / 50 - 0.5, 0), 1)
        let expectedRed = Int((255 * (1 - t)).rounded()), expectedBlue = Int((255 * t).rounded())
        let p = pixel(pixels, x, 5, width: 100)
        #expect(abs(p.r - expectedRed) <= 2 && abs(p.b - expectedBlue) <= 2 && p.g == 0 && p.a == 255,
                "x \(x): expected (\(expectedRed), 0, \(expectedBlue)), read \(p)")
    }
}

/// 1.6 — `filter` 1 reads the texel under each pixel: I8 `.none`'s row, the
/// switch between 49 and 50.
@Test @MainActor func aNearestImageReadsTheTexelUnderEachPixel() throws {
    var scene = Scene()
    scene.insert(image(box(0, 0, 100, 10), mask: box(0, 0, 100, 10), filter: .nearest), texture: redBlue)
    let pixels = try render(scene, width: 100, height: 10)
    for x in [0, 25, 49] { #expect(pixel(pixels, x, 5, width: 100) == (255, 0, 0, 255), "x \(x)") }
    for x in [50, 75, 99] { #expect(pixel(pixels, x, 5, width: 100) == (0, 0, 255, 255), "x \(x)") }
}

/// 1.7 — straight (200, 100, 50, 128) is stored premultiplied, (100, 50, 25,
/// 128), and composites source-over white to 100 + 127, 50 + 127, 25 + 127 =
/// (227, 177, 152) — derived before the run. Unpremultiplied it would read
/// (255, 227, 177).
@Test @MainActor func aTranslucentImageCompositesPremultipliedSourceOver() throws {
    let texture = ImageTexture(width: 1, height: 1, straightRGBA: [200, 100, 50, 128])
    #expect(texture.pixels == [100, 50, 25, 128])
    var scene = Scene()
    scene.insert(MUIRect(bounds: box(0, 0, 20, 20), contentMask: box(0, 0, 20, 20),
                         background: .white, borderColor: .transparent,
                         cornerRadii: Corners(all: ScaledPixels(0)), borderWidths: Edges(all: ScaledPixels(0)),
                         order: 0))
    scene.insert(image(box(0, 0, 20, 20), mask: box(0, 0, 20, 20)), texture: texture)
    let p = pixel(try render(scene, width: 20, height: 20), 10, 10, width: 20)
    #expect(abs(p.r - 227) <= 1 && abs(p.g - 177) <= 1 && abs(p.b - 152) <= 1 && p.a == 255, "read \(p)")
}

/// 1.8 — the content mask and its radii cut an image exactly as they cut a
/// rect: a radius-20 mask leaves the corner pixel at the clear colour.
@Test @MainActor func anImageUnderARoundedMaskIsClippedByIt() throws {
    let green = ImageTexture(width: 1, height: 1, straightRGBA: [0, 255, 0, 255])
    var scene = Scene()
    scene.insert(image(box(0, 0, 100, 100), mask: box(0, 0, 100, 100), maskRadius: 20), texture: green)
    let pixels = try render(scene, width: 100, height: 100)
    #expect(pixel(pixels, 0, 0, width: 100) == (0, 0, 0, 0), "outside the rounded mask")
    #expect(pixel(pixels, 1, 1, width: 100) == (0, 0, 0, 0))
    #expect(pixel(pixels, 50, 50, width: 100) == (0, 255, 0, 255), "inside it, the image")
}

/// 1.9 — one GPU texture per `ImageTexture` identity, uploaded on first sight
/// and released when a frame's scene stops referencing it (`TE-AF` item 3).
@Test @MainActor func aTextureTheSceneNoLongerReferencesIsReleased() throws {
    let renderer = try makeRenderer()
    let a = ImageTexture(width: 1, height: 1, straightRGBA: [255, 0, 0, 255])
    let b = ImageTexture(width: 1, height: 1, straightRGBA: [0, 0, 255, 255])
    func frame(_ texture: ImageTexture) throws -> [UInt8] {
        var scene = Scene()
        scene.insert(image(box(0, 0, 4, 4), mask: box(0, 0, 4, 4)), texture: texture)
        scene.insert(image(box(4, 0, 4, 4), mask: box(0, 0, 8, 4)), texture: texture)
        return try render(scene, renderer: renderer, width: 8, height: 4)
    }
    let first = try frame(a)
    #expect(renderer.cachedImageTextureIdentities == [ObjectIdentifier(a)])
    #expect(renderer.imageTextureUploadCount == 1, "two draws of one texture upload it once")
    #expect(pixel(first, 6, 2, width: 8) == (255, 0, 0, 255))
    _ = try frame(a)
    #expect(renderer.imageTextureUploadCount == 1, "a cached texture is not uploaded again")
    let second = try frame(b)
    #expect(renderer.cachedImageTextureIdentities == [ObjectIdentifier(b)], "a is released")
    #expect(renderer.imageTextureUploadCount == 2)
    #expect(pixel(second, 6, 2, width: 8) == (0, 0, 255, 255))
    _ = try frame(a)
    #expect(renderer.imageTextureUploadCount == 3, "a released texture is uploaded once more")
    #expect(renderer.cachedImageTextureIdentities == [ObjectIdentifier(a)])
}
