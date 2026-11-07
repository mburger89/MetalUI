import Testing
import Metal
import MetalUICore
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// R4-5 PR B, a filter over a group texture (rulings `GF-E`, `GF-C`; record 219; probe
// `docs/probes/swiftui-group-filter.swift`). Renderer level: hand-built scenes with one filtered group quad over a white
// background; every expected pixel is computed from the scene and `BackdropBlurReference`, never from the renderer's own
// output (the `BB-` rule). The content varies on both axes (an L of two rects), so a pass on one axis, or the two
// swapped, cannot agree with the reference.

private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)
private let blue = Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1)

private func box(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<ScaledPixels> {
    Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(y)), size: Size(width: ScaledPixels(w), height: ScaledPixels(h)))
}

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: Hsla, order: UInt32) -> MUIRect {
    MUIRect(bounds: box(x, y, w, h), contentMask: box(-1000, -1000, 4000, 4000), background: color, borderColor: .transparent,
            cornerRadii: Corners(all: ScaledPixels(0)), borderWidths: Edges(all: ScaledPixels(0)), order: order)
}

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int = 200) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private func near(_ a: [Int], _ b: [Int], _ tolerance: Int = 1) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

private func background() -> MUIRect { rect(0, 0, 200, 200, .white, order: 0) }

/// The L: a red 20 x 10 bar over a blue 10 x 20 bar, `at` (x, y) in the parent's coordinates.
private func lScene(at origin: (Float, Float)) -> Scene {
    var inner = Scene()
    inner.insert(rect(origin.0, origin.1, 20, 10, red, order: 0))
    inner.insert(rect(origin.0, origin.1 + 10, 10, 20, blue, order: 1))
    inner.finalize()
    return inner
}

/// The L as premultiplied floats over a `width x height` box whose origin is `box` in the parent's coordinates.
private func lPixels(width: Int, height: Int, origin: (Int, Int), boxOrigin: (Int, Int)) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    func fill(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ c: (Float, Float, Float)) {
        for y in (y0 - boxOrigin.1)..<(y0 - boxOrigin.1 + h) { for x in (x0 - boxOrigin.0)..<(x0 - boxOrigin.0 + w) {
            let i = (y * width + x) * 4
            out[i] = c.0; out[i + 1] = c.1; out[i + 2] = c.2; out[i + 3] = 1
        } }
    }
    fill(origin.0, origin.1, 20, 10, (1, 0, 0))
    fill(origin.0, origin.1 + 10, 10, 20, (0, 0, 1))
    return out
}

private func quad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, filter: ImageFilter, opacity: Float = 1) -> MUIImage {
    MUIImage(bounds: box(x, y, w, h), contentMask: box(x, y, w, h), opacity: opacity, filter: filter, order: 1)
}

private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

/// The worst channel difference, in levels, between the renderer's pixels over `region` and `blurred` (premultiplied floats
/// of the box at `boxOrigin`) composited over white.
private func worst(_ pixels: [UInt8], blurred: [Float], boxOrigin: (Int, Int), width: Int, height: Int) -> Int {
    var worst = 0
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        let a = blurred[i + 3]
        let got = pixel(pixels, x + boxOrigin.0, y + boxOrigin.1)
        for c in 0..<3 {
            let want = Int(((blurred[i + c] + (1 - a)) * 255).rounded())
            worst = max(worst, abs(got[c] - want))
        }
    } }
    return worst
}

/// **R1** (`GF-E`). A blurred group (sigma 2, L = 0) equals the reference Gaussian of the L over transparent, composited
/// over white, within 3 levels, and the blur is visible at all. Mutations: the horizontal pass skipped; the axes swapped;
/// the pad removed by the caller (the L's edge clamped into the box).
@Test @MainActor func aBlurredGroupMatchesTheReferenceGaussian() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(quad(20, 20, 64, 64, filter: .nearest), group: lScene(at: (30, 30)),
                 filter: Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size200)
    let blurred = BackdropBlurReference.blur(lPixels(width: 64, height: 64, origin: (30, 30), boxOrigin: (20, 20)),
                                             width: 64, height: 64, sigma: 2)
    let off = worst(pixels, blurred: blurred, boxOrigin: (20, 20), width: 64, height: 64)
    #expect(off <= 3, "worst channel \(off) levels off the reference")
    let edge = pixel(pixels, 40, 31)   // the red bar's right edge region
    #expect(edge[1] > 20 && edge[1] < 235, "the edge is blurred, not sharp: \(edge)")
    #expect(renderer.lastFilteredGroups == 1 && renderer.lastFilterPasses == 2, "L + 2 passes: \(renderer.lastFilterPasses)")
}

/// **R2** (`GF-E`, `BB-R`). A large sigma (12: L = 2) read through a linear quad over a box of whole 2^L sides lands on the
/// reference's `(p + 1/2) / 2^L - 1/2` texel coordinate, within 3 levels. Mutations: the quad filtered `.nearest`;
/// a downsample skipped.
@Test @MainActor func aLargeSigmaBlurReadsAtBBR() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(quad(20, 20, 100, 100, filter: .linear), group: lScene(at: (60, 60)),
                 filter: Scene.GroupFilter(kind: .blur, sigma: 12, tint: .zero))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size200)
    let blurred = BackdropBlurReference.blur(lPixels(width: 100, height: 100, origin: (60, 60), boxOrigin: (20, 20)),
                                             width: 100, height: 100, sigma: 12)
    let off = worst(pixels, blurred: blurred, boxOrigin: (20, 20), width: 100, height: 100)
    #expect(off <= 3, "worst channel \(off) levels off the reference")
    #expect(renderer.lastFilterPasses == 4, "L = 2 downsamples and two Gaussians: \(renderer.lastFilterPasses)")
}

/// **R3** (`GF-E`). A shadow group draws the tint times the group's alpha and not the content: sigma 0, the premultiplied
/// tint (0.5, 0, 0, 0.5) over a red/blue content reads (255, 128, 128) inside either bar and white outside. Mutations: the
/// tint pass returning the texel (the content's own colours); the tint's alpha ignored; r and b swapped.
@Test @MainActor func aShadowGroupIsTintedAndOffset() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(quad(20, 20, 64, 64, filter: .nearest), group: lScene(at: (30, 30)),
                 filter: Scene.GroupFilter(kind: .shadow, sigma: 0, tint: SIMD4<Float>(0.5, 0, 0, 0.5)))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size200)
    #expect(near(pixel(pixels, 35, 34), [255, 128, 128, 255]), "inside the red bar: \(pixel(pixels, 35, 34))")
    #expect(near(pixel(pixels, 33, 50), [255, 128, 128, 255]), "inside the blue bar: \(pixel(pixels, 33, 50))")
    #expect(near(pixel(pixels, 60, 60), [255, 255, 255, 255]), "outside: \(pixel(pixels, 60, 60))")
    #expect(renderer.lastFilterPasses == 1, "one tint pass: \(renderer.lastFilterPasses)")
}

/// **R4** (`GF-E`). A steady frame makes no texture and every pass is counted: sigma 12 on a shadow is L + 2 + 1 = 5 passes,
/// the second frame makes no texture and reads the same pixels. Mutation: an intermediate not released.
@Test @MainActor func aFilteredGroupSteadyFrameMakesNoTexture() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(background())
    scene.insert(quad(20, 20, 100, 100, filter: .linear), group: lScene(at: (60, 60)),
                 filter: Scene.GroupFilter(kind: .shadow, sigma: 12, tint: SIMD4<Float>(0, 0, 0, 0.5)))
    scene.finalize()
    let first = try renderer.renderOffscreen(scene, size: size200)
    #expect(renderer.lastFilterPasses == 5, "passes: \(renderer.lastFilterPasses)")
    #expect(renderer.lastGroupTexturesMade > 0, "set up: the first frame made textures")
    let second = try renderer.renderOffscreen(scene, size: size200)
    #expect(renderer.lastGroupTexturesMade == 0, "steady: \(renderer.lastGroupTexturesMade)")
    #expect(first == second, "same pixels")
}

/// **R5** (`GF-E`). A filter whose intermediate cannot be allocated degrades by name: a blur draws the unfiltered target
/// (the L stays sharp), a shadow draws nothing; both counted. Mutation: the two fallbacks swapped.
@Test @MainActor func aFilterAllocationFailureDegradesByName() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    renderer.filterPoolFailsAllocation = true
    func scene(_ filter: Scene.GroupFilter) -> Scene {
        var scene = Scene()
        scene.insert(background())
        scene.insert(quad(20, 20, 64, 64, filter: .nearest), group: lScene(at: (30, 30)), filter: filter)
        scene.finalize()
        return scene
    }
    let blur = try renderer.renderOffscreen(scene(Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero)), size: size200)
    #expect(near(pixel(blur, 35, 34), [255, 0, 0, 255]), "the unfiltered L: \(pixel(blur, 35, 34))")
    #expect(near(pixel(blur, 51, 32), [255, 255, 255, 255]), "sharp edge: \(pixel(blur, 51, 32))")
    #expect(renderer.lastFilterAllocationFailures == 1, "counted: \(renderer.lastFilterAllocationFailures)")
    let shadow = try renderer.renderOffscreen(scene(Scene.GroupFilter(kind: .shadow, sigma: 0, tint: SIMD4<Float>(0, 0, 0, 1))), size: size200)
    #expect(near(pixel(shadow, 35, 34), [255, 255, 255, 255]), "nothing drawn: \(pixel(shadow, 35, 34))")
    #expect(renderer.lastFilterAllocationFailures == 1, "counted: \(renderer.lastFilterAllocationFailures)")
}

/// **R6** (`GF-C`, `GF-E`; divergence 167). A surface inside a filtered group resolves its target from the `surfaces:`
/// dictionary: a red 20 x 20 target blurred with sigma 2 is red at its centre, soft at its edge. Mutation: the lookup
/// returns nil (white remains).
@Test @MainActor func aSurfaceInsideAGroupResolvesItsTarget() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 20, height: 20, mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    descriptor.storageMode = .shared
    let target = try #require(device.makeTexture(descriptor: descriptor))
    let bytes = [UInt8]((0..<400).flatMap { _ in [UInt8(0), 0, 255, 255] })
    bytes.withUnsafeBytes { target.replace(region: MTLRegionMake2D(0, 0, 20, 20), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 80) }
    var inner = Scene()
    let id = SurfaceID(rawValue: 1)
    inner.insert(MUIImage(bounds: box(40, 40, 20, 20), contentMask: box(-1000, -1000, 4000, 4000), opacity: 1, filter: .nearest, order: 0),
                 surface: SurfaceTarget(id: id, width: 20, height: 20))
    inner.finalize()
    var scene = Scene()
    scene.insert(background())
    scene.insert(quad(20, 20, 64, 64, filter: .nearest), group: inner, filter: Scene.GroupFilter(kind: .blur, sigma: 2, tint: .zero))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size200, surfaces: [id: target])
    #expect(near(pixel(pixels, 50, 50), [255, 0, 0, 255], 2), "the target, at its centre: \(pixel(pixels, 50, 50))")
    let edge = pixel(pixels, 40, 50)
    #expect(edge[1] > 20 && edge[1] < 235, "blurred at the edge: \(edge)")
}

/// **GF-C.** `finalize()` permutes the filters with their groups: two groups inserted out of draw order keep each its own
/// filter, and `clear()` drops them. Mutation: `groupFilters` not permuted (the filters swap).
@Test func finalizeKeepsEachGroupsFilter() {
    var scene = Scene()
    let blur = Scene.GroupFilter(kind: .blur, sigma: 3, tint: .zero)
    let shadow = Scene.GroupFilter(kind: .shadow, sigma: 5, tint: SIMD4<Float>(0, 0, 0, 1))
    var later = quad(0, 0, 10, 10, filter: .nearest); later.order = 5
    var earlier = quad(0, 0, 10, 10, filter: .nearest); earlier.order = 2
    scene.insert(later, group: lScene(at: (1, 1)), filter: blur)
    scene.insert(earlier, group: lScene(at: (2, 2)), filter: shadow)
    scene.finalize()
    #expect(scene.groupFilters == [shadow, blur], "the order-2 shadow first: \(scene.groupFilters)")
    #expect(scene.groupScenes[0].rects[0].bounds.origin.x == 2, "the groups moved with them")
    scene.clear()
    #expect(scene.groupFilters.isEmpty && scene.isEmpty)
}

/// **GF-C.** `allSurfaceTargets()` lists the root's targets, then each group's, each id once. Mutation: the root's only.
@Test func allSurfaceTargetsWalksTheGroupScenes() {
    let a = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 4, height: 4)
    let b = SurfaceTarget(id: SurfaceID(rawValue: 2), width: 8, height: 8)
    func surfaceScene(_ targets: [SurfaceTarget], nested: [Scene] = []) -> Scene {
        var scene = Scene()
        for t in targets { scene.insert(quad(0, 0, 4, 4, filter: .nearest), surface: t) }
        for n in nested { scene.insert(quad(0, 0, 4, 4, filter: .nearest), group: n) }
        scene.finalize()
        return scene
    }
    let root = surfaceScene([a], nested: [surfaceScene([b, a])])
    #expect(root.surfaceTargets == [a], "the root holds one")
    #expect(root.allSurfaceTargets() == [a, b], "both, each once: \(root.allSurfaceTargets().map(\.id.rawValue))")
}
