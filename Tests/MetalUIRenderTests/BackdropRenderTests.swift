import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// Backdrop blur, lane 2, tests 2.1-2.12 (rulings `BB-A`, `BB-C`, `BB-D`, `BB-E`,
// `BB-I`, `BB-R`, `BB-S`; spec `docs/superpowers/specs/2026-10-10-backdrop-blur-design.md`
// §3, §5). The Metal renderer draws a scene holding backdrops into a frame target
// in segments, blurs each record's region (downsample pyramid + separable
// Gaussian), draws the quad over it and copies the frame target to the
// drawable. Every expected pixel is computed from the SCENE (the backdrop
// pixels are known by construction) and `BackdropBlurReference`, never from
// the renderer's own output.

private func mb(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
private let wide = mb(0, 0, 4096, 4096)
private let red = MUIHsla(h: 0, s: 1, l: 0.5, a: 1)
private let blue = MUIHsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1)
private let white = MUIHsla(h: 0, s: 0, l: 1, a: 1)
private let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)
private let clear = MUIHsla(h: 0, s: 0, l: 0, a: 0)

private func solid(_ b: MUIBounds, _ color: MUIHsla, mask: MUIBounds = wide) -> MUIRect {
    MUIRect(bounds: b, contentMask: mask, maskCornerRadii: square, background: color, borderColor: clear,
            cornerRadii: square, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0)
}

private func backdrop(_ b: MUIBounds, tint: MUIHsla = clear, sigma: Float = 16, opacity: Float = 1,
                      mask: MUIBounds = wide, shape: UInt32 = 0) -> MUIBackdrop {
    MUIBackdrop(bounds: b, contentMask: mask, maskCornerRadii: square, cornerRadii: square, tint: tint,
                order: 0, shape: shape, sigma: sigma, opacity: opacity)
}

private func size(_ w: Int, _ h: Int) -> Size<DevicePixels> {
    Size(width: DevicePixels(Int32(w)), height: DevicePixels(Int32(h)))
}

/// `(r, g, b, a)` of a BGRA readback.
private func px(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// The backdrop pixels the step scene holds, premultiplied floats (r, g, b, a):
/// red left of `edge`, blue right of it, over `width × height`.
private func stepPixels(width: Int, height: Int, edge: Int) -> [Float] {
    var out = [Float](repeating: 0, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        if x < edge { out[i] = 1 } else { out[i + 2] = 1 }
        out[i + 3] = 1
    } }
    return out
}

private func stepScene(width: Int, height: Int, edge: Int) -> Scene {
    var scene = Scene()
    scene.insert(solid(mb(0, 0, Float(edge), Float(height)), red))
    scene.insert(solid(mb(Float(edge), 0, Float(width - edge), Float(height)), blue))
    return scene
}

/// The largest per-channel distance, in 8-bit levels, between a readback
/// region and `expected` (premultiplied floats, `rw × rh` at (`rx`, `ry`)).
private func maxLevelsOff(_ pixels: [UInt8], width: Int, region rx: Int, _ ry: Int, _ rw: Int, _ rh: Int,
                          expected: [Float]) -> Float {
    var worst: Float = 0
    for y in 0..<rh { for x in 0..<rw {
        let got = px(pixels, rx + x, ry + y, width: width)
        let e = (y * rw + x) * 4
        for (c, g) in got.enumerated() {
            worst = max(worst, abs(Float(g) - expected[e + c] * 255))
        }
    } }
    return worst
}

/// Source-over of the record's output `c·o·(T + (1−Ta)·B)` over an opaque
/// destination, per pixel, in floats. `tint` is a gray `l` with alpha `a`.
private func composite(blurred: [Float], destination: [Float], grayTint l: Float, alpha a: Float, opacity o: Float) -> [Float] {
    var out = blurred
    for p in 0..<(blurred.count / 4) {
        let i = p * 4
        var src = [Float](repeating: 0, count: 4)
        for c in 0..<3 { src[c] = o * (l * a + (1 - a) * blurred[i + c]) }
        src[3] = o * (a + (1 - a) * blurred[i + 3])
        for c in 0..<4 { out[i + c] = src[c] + (1 - src[3]) * destination[i + c] }
    }
    return out
}

@MainActor private func makeRenderer() throws -> Renderer {
    try Renderer(device: try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware"))
}

/// **2.1** (`BB-A`, `BB-D`, `BB-R`). A backdrop over a red|blue step reads, within three levels,
/// the reference blur of the step composited under the tint — at σ = 16, 52 and 104
/// device pixels (52 pt at scales 1 and 2). Mutations: halve σ in the shaders
/// (`sigma * 0.5` in the pass constants); skip the blur pass (draw the sharp
/// backdrop).
@Test(arguments: [Float(16), 52, 104]) @MainActor func aBackdropOverAStepEqualsTheReferenceWithinTolerance(sigma: Float) throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), sigma: sigma))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    let step = stepPixels(width: w, height: h, edge: 100)
    let blurred = BackdropBlurReference.blur(step, width: w, height: h, sigma: sigma)
    let expected = composite(blurred: blurred, destination: step, grayTint: 0.5, alpha: 0.3, opacity: 1)
    let off = maxLevelsOff(pixels, width: w, region: 0, 0, w, h, expected: expected)
    #expect(off <= 3, "σ \(sigma): worst channel \(off) levels off the reference")
    // The blur is visible at all: the step pixel is neither pure red nor pure blue.
    let mid = px(pixels, 100, 20, width: w)
    #expect(mid[0] > 20 && mid[2] > 20, "σ \(sigma): a step reads both colours at the edge: \(mid)")
}

/// A shader-readable 200×40 texture of 4-pixel red and blue stripes.
@MainActor private func stripeTexture(_ device: any MTLDevice, width: Int, height: Int) throws -> any MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    d.usage = [.shaderRead, .renderTarget]
    d.storageMode = .shared
    let texture = try #require(device.makeTexture(descriptor: d))
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        let isRed = (x / 4) % 2 == 0
        bytes[i] = isRed ? 0 : 255        // b
        bytes[i + 1] = 0                  // g
        bytes[i + 2] = isRed ? 255 : 0    // r
    } }
    bytes.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                            withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
    return texture
}

/// **2.2** (`BB-C`, spec §3.2). A GPU surface drawn BEFORE a backdrop in scene
/// order is blurred by it (stripes -> purple); the same two primitives in the
/// other order leave the stripes sharp (scene order is the semantics).
/// Mutation: emit the backdrop run before the surface run (insert order
/// reversed in the encoder's segmenting).
@Test @MainActor func theBackdropBlursAGPUSurfaceBeneathIt() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    let target = SurfaceTarget(id: SurfaceID(rawValue: 7), width: w, height: h)
    let texture = try stripeTexture(renderer.device, width: w, height: h)
    func quad() -> MUIImage {
        MUIImage(bounds: mb(0, 0, 200, 40), contentMask: wide, maskCornerRadii: square, opacity: 1,
                 texture: 0, filter: 0, order: 0)
    }
    var above = Scene()
    above.insert(solid(mb(0, 0, 200, 40), black))
    above.insert(quad(), surface: target)
    above.insert(backdrop(mb(0, 0, 200, 40), sigma: 52))
    above.finalize()
    let blurredPixels = try renderer.renderOffscreen(above, size: size(w, h), surfaces: [target.id: texture])
    let centre = px(blurredPixels, 100, 20, width: w)
    #expect(abs(centre[0] - 128) <= 6 && centre[1] == 0 && abs(centre[2] - 128) <= 6,
            "stripes under a backdrop read purple: \(centre)")
    // Against the reference of the surface's pixels.
    var stripes = [Float](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        if (x / 4) % 2 == 0 { stripes[i] = 1 } else { stripes[i + 2] = 1 }
        stripes[i + 3] = 1
    } }
    let reference = BackdropBlurReference.blur(stripes, width: w, height: h, sigma: 52)
    #expect(maxLevelsOff(blurredPixels, width: w, region: 0, 0, w, h, expected: reference) <= 3)

    var below = Scene()
    below.insert(solid(mb(0, 0, 200, 40), black))
    below.insert(backdrop(mb(0, 0, 200, 40), sigma: 52))
    below.insert(quad(), surface: target)
    below.finalize()
    let sharp = try renderer.renderOffscreen(below, size: size(w, h), surfaces: [target.id: texture])
    #expect(px(sharp, 1, 20, width: w) == [255, 0, 0, 255] && px(sharp, 5, 20, width: w) == [0, 0, 255, 255],
            "a surface drawn after the backdrop stays sharp")
}

/// **2.3** (`BB-C`). A scene with no backdrop takes the old path: every counter
/// 0, no frame target made, and the pixels equal the same scene forced through
/// the frame target by the package test hook (so the equality is the copy's
/// exactness, and the counters are what tell the paths apart). Mutation: route
/// every scene through the frame target.
@Test @MainActor func aSceneWithoutBackdropsTakesTheOldPathByteForByte() throws {
    let renderer = try makeRenderer()
    var scene = stepScene(width: 64, height: 32, edge: 20)
    scene.finalize()
    let old = try renderer.renderOffscreen(scene, size: size(64, 32))
    #expect(renderer.lastBackdropSplits == 0 && renderer.lastBackdropBlurs == 0 && renderer.lastBackdropPasses == 0
            && renderer.lastFrameTargetCopies == 0 && renderer.lastBackdropTexturesMade == 0,
            "every counter is 0 on the old path")
    #expect(!renderer.hasBackdropFrameTarget, "no frame target exists on the old path")
    renderer.routesEveryFrameThroughTheFrameTarget = true
    let forced = try renderer.renderOffscreen(scene, size: size(64, 32))
    #expect(renderer.lastFrameTargetCopies == 1, "the forced path copies once")
    #expect(forced == old, "the frame target and the copy draw are exact")
}

/// **2.4** (`BB-E`, `BB-S`). Splits count backdrop runs and blurs count records;
/// the passes are `L + 2` per record (L downsamples and the two Gaussian
/// passes; `BB-S`). Adjacent non-overlapping records share a run (1 split, 2
/// blurs); another kind between them splits (2); overlapping records split (2).
/// σ 16 has L = 2 (4 passes a record). Mutation: count per record.
@Test @MainActor func splitsCountRunsAndBlursCountRecords() throws {
    let renderer = try makeRenderer()
    func counters(_ build: (inout Scene) -> Void) throws -> (splits: Int, blurs: Int, passes: Int, copies: Int) {
        var scene = Scene()
        scene.insert(solid(mb(0, 0, 200, 40), red))
        build(&scene)
        scene.finalize()
        _ = try renderer.renderOffscreen(scene, size: size(200, 40))
        return (renderer.lastBackdropSplits, renderer.lastBackdropBlurs, renderer.lastBackdropPasses, renderer.lastFrameTargetCopies)
    }
    let adjacent = try counters {
        $0.insert(backdrop(mb(0, 0, 50, 40))); $0.insert(backdrop(mb(60, 0, 50, 40)))
    }
    #expect(adjacent == (1, 2, 8, 1), "adjacent: \(adjacent)")
    let interleaved = try counters {
        $0.insert(backdrop(mb(0, 0, 50, 40)))
        $0.insert(solid(mb(0, 0, 4, 4), blue))
        $0.insert(backdrop(mb(60, 0, 50, 40)))
    }
    #expect(interleaved == (2, 2, 8, 1), "interleaved: \(interleaved)")
    let overlapping = try counters {
        $0.insert(backdrop(mb(0, 0, 80, 40))); $0.insert(backdrop(mb(40, 0, 80, 40)))
    }
    #expect(overlapping == (2, 2, 8, 1), "overlapping: \(overlapping)")
    let none = try counters { _ in }
    #expect(none == (0, 0, 0, 0), "no backdrop: \(none)")
}

/// **2.5** (`BB-H`). The record's shape masks the quad: an ellipse leaves the
/// pixels outside the ellipse (the bounds' corner) exactly the sharp backdrop
/// and blurs the inside. Mutation: ignore the shape SDF (draw the box).
@Test @MainActor func pixelsOutsideTheShapeAreUntouched() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(70, 0, 60, 40), tint: MUIHsla(h: 0, s: 0, l: 1, a: 1), sigma: 16,
                          shape: UInt32(MUIShapeEllipse.rawValue)))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(px(pixels, 71, 1, width: w) == [255, 0, 0, 255], "the corner of the bounds is outside the ellipse: \(px(pixels, 71, 1, width: w))")
    #expect(px(pixels, 128, 38, width: w) == [0, 0, 255, 255], "the opposite corner too")
    #expect(px(pixels, 100, 20, width: w) == [255, 255, 255, 255], "the centre is the opaque white tint")
}

/// **2.6** (`BB-A`). Opacity is the half-weight composite of the (blurred,
/// tinted) layer over the SHARP backdrop: tint white α 0.5 at opacity 0.5 over
/// the step edge equals `o·(T + (1−Ta)·B) + (1 − o)·F` within three levels, and
/// is far from the tint-alpha-multiply spelling. Mutation: multiply `tint.a`
/// by the opacity instead of the result.
@Test @MainActor func opacityHalfIsAHalfWeightCompositeOverTheSharpBackdrop() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 1, a: 0.5), sigma: 16, opacity: 0.5))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    let step = stepPixels(width: w, height: h, edge: 100)
    let blurred = BackdropBlurReference.blur(step, width: w, height: h, sigma: 16)
    let expected = composite(blurred: blurred, destination: step, grayTint: 1, alpha: 0.5, opacity: 0.5)
    let off = maxLevelsOff(pixels, width: w, region: 0, 0, w, h, expected: expected)
    #expect(off <= 3, "worst channel \(off) levels off o·(T+(1−Ta)·B) over the sharp backdrop")
    // The separating pixel: just right of the edge, blue is sharp underneath.
    let e = (20 * w + 101) * 4
    #expect(abs(Float(px(pixels, 101, 20, width: w)[2]) - expected[e + 2] * 255) <= 3)
}

/// **2.7** (`BB-I`). A record whose blur textures cannot be allocated draws
/// the flat tint over the sharp backdrop: the pixels equal an ordinary rect of
/// the tint (alpha × opacity). Mutation: draw nothing on failure.
@Test @MainActor func aFailedBlurTextureDrawsTheFlatTint() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    let tint = MUIHsla(h: 0.1, s: 0.8, l: 0.5, a: 0.6)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(30, 5, 100, 30), tint: tint, sigma: 52, opacity: 0.8))
    scene.finalize()
    renderer.backdropPoolFailsAllocation = true
    let failed = try renderer.renderOffscreen(scene, size: size(w, h))
    renderer.backdropPoolFailsAllocation = false
    var flat = stepScene(width: w, height: h, edge: 100)
    var flatTint = tint
    flatTint.a *= 0.8
    flat.insert(solid(mb(30, 5, 100, 30), flatTint))
    flat.finalize()
    let old = try renderer.renderOffscreen(flat, size: size(w, h))
    var worst = 0
    for i in 0..<failed.count { worst = max(worst, abs(Int(failed[i]) - Int(old[i]))) }
    #expect(worst <= 1, "the fallback is today's flat tint: worst byte \(worst)")
    let blurredPixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(blurredPixels != failed, "and the blurred frame differs, so the hook is what failed it")
}

/// **2.8** (`BB-E`). Nested backdrops blur twice: the second sees the first in
/// the frame target. Mutation: blur both records from one snapshot.
@Test @MainActor func nestedBackdropsBlurTwice() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), sigma: 16))
    scene.insert(backdrop(mb(0, 0, 200, 40), sigma: 16))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    let step = stepPixels(width: w, height: h, edge: 100)
    let once = BackdropBlurReference.blur(step, width: w, height: h, sigma: 16)
    let twice = BackdropBlurReference.blur(once, width: w, height: h, sigma: 16)
    #expect(maxLevelsOff(pixels, width: w, region: 0, 0, w, h, expected: twice) <= 4, "twice")
    #expect(maxLevelsOff(pixels, width: w, region: 0, 0, w, h, expected: once) > 8, "and not once")
}

/// **2.9** (`BB-H`). The content mask cuts the quad: with a tint over the
/// whole step and a mask over the left half, the right half is the sharp
/// backdrop and the left half is tinted. Mutation: ignore `contentMask`.
@Test @MainActor func theClipCutsTheBackdropQuad() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 1, a: 1), sigma: 16, mask: mb(0, 0, 100, 40)))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(px(pixels, 150, 20, width: w) == [0, 0, 255, 255], "outside the mask: the sharp backdrop")
    #expect(px(pixels, 50, 20, width: w) == [255, 255, 255, 255], "inside the mask: the tint")
}

/// **2.10** (`BB-E`, `BB-K`). A steady frame makes no textures; a resize makes
/// the frame target once and nothing else (the region is unchanged). Mutation:
/// allocate the pool's textures per frame.
@Test @MainActor func aSteadyFrameMakesNoTexturesAndAResizeMakesTheFrameTargetOnce() throws {
    let renderer = try makeRenderer()
    func scene() -> Scene {
        var s = stepScene(width: 160, height: 40, edge: 80)
        s.insert(backdrop(mb(20, 0, 100, 40), sigma: 52))
        s.finalize()
        return s
    }
    _ = try renderer.renderOffscreen(scene(), size: size(160, 40))
    let first = renderer.lastBackdropTexturesMade
    #expect(first > 1, "the first frame makes the frame target and the pool: \(first)")
    _ = try renderer.renderOffscreen(scene(), size: size(160, 40))
    #expect(renderer.lastBackdropTexturesMade == 0, "a steady frame makes none")
    var wider = stepScene(width: 240, height: 40, edge: 80)
    wider.insert(backdrop(mb(20, 0, 100, 40), sigma: 52))
    wider.finalize()
    _ = try renderer.renderOffscreen(wider, size: size(240, 40))
    #expect(renderer.lastBackdropTexturesMade == 1, "a resize makes the frame target once: \(renderer.lastBackdropTexturesMade)")
}

/// **2.11** (`BB-C`). The drawable stays `framebufferOnly`: the frame target
/// and the copy draw exist so the layer never has to be sampled. A source
/// guard on `MetalLayerSurface`. Mutation: set it to `false`.
@Test func theDrawableStaysFramebufferOnly() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/MetalUIAppKit/MetalLayerSurface.swift"), encoding: .utf8)
    #expect(source.contains("layer.framebufferOnly = true"))
    #expect(!source.contains("framebufferOnly = false"))
}

/// **2.12** (`BB-H`, `GX-F`). A rotated backdrop lands where its transform puts
/// it, and stays inside its clip: a 90-degree turn of a horizontal bar about
/// the target's centre is a vertical bar; the pixel the unrotated bar would
/// have covered stays the sharp backdrop. Mutation: skip the transform index.
@Test @MainActor func aClippedTransformedBackdropStaysInsideItsClip() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    // x' = cx + cy - y, y' = cy - cx + x about (100, 20): (x, y) -> (120 - y, x - 80).
    let turn = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 120, ty: -80, pixelScale: 1, _reserved: 0,
                            outerMask: mb(0, 0, 200, 40), outerMaskRadii: square)
    scene.insert(backdrop(mb(60, 10, 80, 20), tint: MUIHsla(h: 0, s: 0, l: 1, a: 1), sigma: 16, mask: mb(0, 0, 300, 300)),
                 transform: turn)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(px(pixels, 100, 5, width: w) == [255, 255, 255, 255], "inside the rotated bar: \(px(pixels, 100, 5, width: w))")
    #expect(px(pixels, 70, 20, width: w) == [255, 0, 0, 255], "where the unrotated bar was: the sharp backdrop: \(px(pixels, 70, 20, width: w))")
    #expect(px(pixels, 100, 38, width: w) == [255, 255, 255, 255], "the bar reaches the bottom edge: x 90..110, y -20..60 clamped")
}

/// **2.12b** (`BB-H`, `GX-F`). The transform's outer mask cuts a backdrop in the
/// fragment, in screen space: the same 90-degree turn as 2.12 with an outer mask
/// of x 0..100 only (the frame is 200 wide). Derived before the run: the turned
/// bar covers x 90..110, y 0..40 (clamped), so x 95 is inside both (tint white,
/// alpha 1 -> white) and x 105 is inside the bar but outside the outer mask (the
/// sharp backdrop, blue right of the edge at 100). Mutation: force
/// `transformIndex = 0` at the first `b.shape >> 8` in `backdrop_coverage`.
@Test @MainActor func aTransformsOuterMaskSmallerThanTheFrameCutsABackdrop() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 100)
    let turn = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 120, ty: -80, pixelScale: 1, _reserved: 0,
                            outerMask: mb(0, 0, 100, 40), outerMaskRadii: square)
    scene.insert(backdrop(mb(60, 10, 80, 20), tint: white, sigma: 16, mask: mb(0, 0, 300, 300)), transform: turn)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(px(pixels, 95, 5, width: w) == [255, 255, 255, 255], "inside bar and outer mask: \(px(pixels, 95, 5, width: w))")
    #expect(px(pixels, 105, 5, width: w) == [0, 0, 255, 255],
            "inside the bar, outside the outer mask: the sharp backdrop: \(px(pixels, 105, 5, width: w))")
}

/// **2.12c** (`BB-H`, `GX-F`). A backdrop under a 2x scale antialiases its edge
/// at the screen pixel, not the local one: local rect (10, 5, 40, 10) under
/// `x' = 2x, y' = 2y` (`pixelScale` 2) covers screen x 20..100, y 10..30 on whole
/// pixels. Derived before the run: a pixel centre is 0.5 screen px from the edge,
/// coverage `saturate(0.5 - d)` with `d` in screen px is exactly 1 inside and 0
/// outside, so (20, 20) and (30, 10) are white and (19, 20) and (30, 9) are the
/// sharp red backdrop; at scale 1 they would read 0.75 and 0.25. Mutation:
/// force `transformIndex = 0` at the first `b.shape >> 8` in `backdrop_coverage`.
@Test @MainActor func aScaledBackdropAntialiasesAtTheScreenPixel() throws {
    let renderer = try makeRenderer()
    let (w, h) = (200, 40)
    var scene = stepScene(width: w, height: h, edge: 150)
    let twice = MUITransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0, pixelScale: 2, _reserved: 0,
                             outerMask: mb(0, 0, 200, 40), outerMaskRadii: square)
    scene.insert(backdrop(mb(10, 5, 40, 10), tint: white, sigma: 16, mask: mb(0, 0, 300, 300)), transform: twice)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size(w, h))
    #expect(px(pixels, 20, 20, width: w) == [255, 255, 255, 255], "first pixel inside the left edge: \(px(pixels, 20, 20, width: w))")
    #expect(px(pixels, 19, 20, width: w) == [255, 0, 0, 255], "last pixel outside it: \(px(pixels, 19, 20, width: w))")
    #expect(px(pixels, 30, 10, width: w) == [255, 255, 255, 255], "first row inside the top edge: \(px(pixels, 30, 10, width: w))")
    #expect(px(pixels, 30, 9, width: w) == [255, 0, 0, 255], "last row outside it: \(px(pixels, 30, 9, width: w))")
}
