import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// MetalView lane 2, test 2.11 and the shared surface parity literal (rulings
// `MV-C` item 2, `MV-D`, `MV-H` item 4; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §4, §8). A surface
// run is drawn by the IMAGE pipeline with its target bound as the texture: no
// new shader struct, no shader change. Renderer level — the target textures
// are hand-filled here, standing in for the app's draw (`MV-C` item 4: a
// surface's content is app-defined, so parity is a known fill).

/// **The surface parity literal** (`MV-H` item 4) — lane 3's
/// `anSDLSurfaceFillMatchesTheMetalParityLiteral` (`Backends/SDL`, a separate
/// package that cannot import this file) copies this scene and these pixels
/// byte for byte and cites this constant; change both together.
///
/// The scene, 40 × 40 device pixels, in insertion order:
/// 1. an opaque black `MUIRect` over the whole 40 × 40;
/// 2. surface **A** (`SurfaceID(1)`, a 20 × 20 target whose every texel is the
///    premultiplied opaque colour (r 200, g 100, b 40, a 255)), quad bounds
///    (0, 0, 20, 20), content mask the same with corner radius 6, opacity 0.5;
/// 3. surface **B** (`SurfaceID(2)`, a 20 × 20 target of opaque blue
///    (0, 0, 255, 255)), quad bounds (20, 20, 20, 20), square mask, opacity 1.
///
/// Derived before the run, premultiplied source-over in gamma space (`MV-D`,
/// §7.8): A's centre is 0.5 × (200, 100, 40, 255) over opaque black =
/// (100, 50, 20, 255) — every channel an exact integer, so no rounding
/// ambiguity; A's corner pixel (0, 0) lies outside the radius-6 mask and reads
/// the black background; B's centre is blue; (30, 10) is covered by neither
/// quad and reads black.
enum SurfaceParity {
    static let side = 40
    static let maskRadius: Float = 6
    static let opacityA: Float = 0.5
    /// A's texel, straight = premultiplied (opaque), as (r, g, b, a).
    static let texelA: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (200, 100, 40, 255)
    /// B's texel.
    static let texelB: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 255, 255)
    /// The four pixels, (x, y) → (r, g, b, a).
    static let expected: [(x: Int, y: Int, rgba: [Int])] = [
        (10, 10, [100, 50, 20, 255]),  // A's centre: half A over black
        (0, 0, [0, 0, 0, 255]),        // A's corner, outside the radius-6 mask
        (30, 30, [0, 0, 255, 255]),    // B's centre
        (30, 10, [0, 0, 0, 255])       // neither quad
    ]
}

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
    Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)),
           size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
}

private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// A `side × side` shader-readable texture whose every texel is `texel`
/// (written as BGRA, the target format).
@MainActor
private func filledTarget(_ device: any MTLDevice, side: Int,
                          _ texel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) throws -> any MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let bytes = [UInt8]((0..<(side * side)).flatMap { _ in [texel.b, texel.g, texel.r, texel.a] })
    bytes.withUnsafeBytes { raw in
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: side * 4)
    }
    return texture
}

/// **2.11** (`MV-C` item 2, `MV-D`, `MV-H` item 4). A surface run samples ITS
/// target through the image pipeline — masked by the quad's rounded content
/// mask, scaled by its opacity, premultiplied source-over — and each run binds
/// its own target (`finalize()` breaks the run where the target changes):
/// `renderOffscreen(_:size:surfaces:)` over ``SurfaceParity``'s scene reads
/// exactly its four literal pixels. A surface run whose target has no texture
/// in the map draws nothing (the headless `renderFrame` case, `MV-H` item 5).
///
/// Mutation **M2m**: offset the run's target index by one (modulo the target
/// count — A's run binds B's texture and B's binds A's).
@Test @MainActor func aSurfaceRunSamplesItsTargetThroughTheImagePipeline() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = Float(SurfaceParity.side)
    let a = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 20, height: 20)
    let b = SurfaceTarget(id: SurfaceID(rawValue: 2), width: 20, height: 20)

    var scene = Scene()
    scene.insert(MUIRect(bounds: box(0, 0, side, side), contentMask: box(0, 0, side, side),
                         background: .black, borderColor: .transparent,
                         cornerRadii: Corners(all: ScaledPixels(0)), borderWidths: Edges(all: ScaledPixels(0)),
                         order: 0))
    scene.insert(MUIImage(bounds: box(0, 0, 20, 20), contentMask: box(0, 0, 20, 20),
                          maskCornerRadii: Corners(all: ScaledPixels(SurfaceParity.maskRadius)),
                          opacity: SurfaceParity.opacityA, filter: .linear, order: 1), surface: a)
    scene.insert(MUIImage(bounds: box(20, 20, 20, 20), contentMask: box(20, 20, 20, 20),
                          opacity: 1, filter: .linear, order: 2), surface: b)
    scene.finalize()
    try #require(scene.drawList.map(\.kind) == [.rect, .surface, .surface], "set up: two surface runs")

    let size = Size(width: DevicePixels(Int32(SurfaceParity.side)), height: DevicePixels(Int32(SurfaceParity.side)))
    let textures: [SurfaceID: any MTLTexture] = [
        a.id: try filledTarget(device, side: 20, SurfaceParity.texelA),
        b.id: try filledTarget(device, side: 20, SurfaceParity.texelB)
    ]
    let pixels = try renderer.renderOffscreen(scene, size: size, surfaces: textures)
    for (x, y, expected) in SurfaceParity.expected {
        #expect(rgba(pixels, x, y, width: SurfaceParity.side) == expected, "(\(x), \(y))")
    }

    // No texture for A: its run draws nothing, B's still draws.
    let partial = try renderer.renderOffscreen(scene, size: size, surfaces: [b.id: textures[b.id]!])
    #expect(rgba(partial, 10, 10, width: SurfaceParity.side) == [0, 0, 0, 255], "A unbound: the background")
    #expect(rgba(partial, 30, 30, width: SurfaceParity.side) == [0, 0, 255, 255], "B still drawn")
}
