import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture
import SDLBridge

// Backdrop blur on the SDL GPU renderer (rulings BB-A, BB-C, BB-D, BB-E, BB-I,
// BB-J, BB-R, BB-S; spec `2026-10-10-backdrop-blur-design.md` §3, §5, tests
// 3.3 and 3.5). `SDLWindowRenderer` draws a scene holding backdrops into a
// frame target in segments, blurs each record's region (downsample pyramid +
// separable Gaussian, `replay.hlsl`), draws the quad over it and blits the
// frame target to the target — the structure the Metal renderer has. Every
// expected pixel is computed from the SCENE and a reference Float
// implementation of the algorithm kept in this file (`BackdropBlurReference`
// is `package` access of the root package; this is another package), and the
// Metal renderer's own pixels are held against these by the replay-parity
// fixtures (frames 9-11 of `swift run Replay --portable --record`). No test
// creates an `SDLPlatform`, but every helper arms the run-loop exit check
// (record §61 §9): the offscreen renderer initialises SDL video. Nothing here
// needs a presented window frame, so nothing is gated on the video driver.

private func mb(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
private let wide = mb(0, 0, 4096, 4096)
private let red = MUIHsla(h: 0, s: 1, l: 0.5, a: 1)
private let blue = MUIHsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1)
private let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)
private let clear = MUIHsla(h: 0, s: 0, l: 0, a: 0)

private func solid(_ b: MUIBounds, _ color: MUIHsla) -> MUIRect {
    MUIRect(bounds: b, contentMask: wide, maskCornerRadii: square, background: color, borderColor: clear,
            cornerRadii: square, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0)
}

private func backdrop(_ b: MUIBounds, tint: MUIHsla = clear, sigma: Float = 16, opacity: Float = 1,
                      mask: MUIBounds = wide, shape: UInt32 = 0, radii: MUICorners = square) -> MUIBackdrop {
    MUIBackdrop(bounds: b, contentMask: mask, maskCornerRadii: square, cornerRadii: radii, tint: tint,
                order: 0, shape: shape, sigma: sigma, opacity: opacity)
}

/// `(r, g, b, a)` of a BGRA readback.
private func px(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

/// Red left of `edge`, blue right of it, over `width × height`, premultiplied floats.
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

// MARK: - The reference (the algorithm of `BackdropBlurReference`, re-stated)

/// The downsample level count: the smallest `L ≥ 0` with `sigma / 2^L ≤ 4`, at most 6.
private func levels(sigma: Float) -> Int {
    var level = 0
    var s = sigma
    while s > 4, level < 6 { s *= 0.5; level += 1 }
    return level
}

private func downsample(_ src: [Float], _ width: Int, _ height: Int) -> (pixels: [Float], width: Int, height: Int) {
    let w = (width + 1) / 2, h = (height + 1) / 2
    var out = [Float](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let y0 = min(2 * y, height - 1), y1 = min(2 * y + 1, height - 1)
        let x0 = min(2 * x, width - 1), x1 = min(2 * x + 1, width - 1)
        for c in 0..<4 {
            let a = src[(y0 * width + x0) * 4 + c] + src[(y0 * width + x1) * 4 + c]
            let b = src[(y1 * width + x0) * 4 + c] + src[(y1 * width + x1) * 4 + c]
            out[(y * w + x) * 4 + c] = (a + b) * 0.25
        }
    } }
    return (out, w, h)
}

private func gaussian(_ src: [Float], _ width: Int, _ height: Int, sigma: Float) -> [Float] {
    let radius = sigma > 0 ? Int((3 * sigma).rounded(.up)) : 0
    var weights = [Float](repeating: 0, count: radius + 1)
    var total: Float = 0
    for i in 0...radius {
        weights[i] = Float(exp(-Double(i * i) / (2 * Double(sigma) * Double(sigma))))
        total += i == 0 ? weights[i] : 2 * weights[i]
    }
    weights = weights.map { $0 / total }
    func pass(_ input: [Float], horizontal: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: input.count)
        for y in 0..<height { for x in 0..<width { for c in 0..<4 {
            var sum = weights[0] * input[(y * width + x) * 4 + c]
            if radius > 0 { for i in 1...radius {
                let (ax, ay, bx, by) = horizontal
                    ? (max(x - i, 0), y, min(x + i, width - 1), y)
                    : (x, max(y - i, 0), x, min(y + i, height - 1))
                sum += weights[i] * (input[(ay * width + ax) * 4 + c] + input[(by * width + bx) * 4 + c])
            } }
            out[(y * width + x) * 4 + c] = sum
        } } }
        return out
    }
    return pass(pass(src, horizontal: true), horizontal: false)
}

private func blurred(_ pixels: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
    let level = levels(sigma: sigma)
    var current = pixels
    var w = width, h = height
    for _ in 0..<level { (current, w, h) = downsample(current, w, h) }
    current = gaussian(current, w, h, sigma: sigma / Float(1 << level))
    if level == 0 { return current }
    var out = [Float](repeating: 0, count: pixels.count)
    let scale = Float(1 << level)
    for py in 0..<height {
        let fy = (Float(py) + 0.5) / scale - 0.5
        let y0f = fy.rounded(.down), ty = fy - y0f
        let y0 = min(max(Int(y0f), 0), h - 1), y1 = min(max(Int(y0f) + 1, 0), h - 1)
        for px in 0..<width {
            let fx = (Float(px) + 0.5) / scale - 0.5
            let x0f = fx.rounded(.down), tx = fx - x0f
            let x0 = min(max(Int(x0f), 0), w - 1), x1 = min(max(Int(x0f) + 1, 0), w - 1)
            for c in 0..<4 {
                let top = current[(y0 * w + x0) * 4 + c] * (1 - tx) + current[(y0 * w + x1) * 4 + c] * tx
                let bottom = current[(y1 * w + x0) * 4 + c] * (1 - tx) + current[(y1 * w + x1) * 4 + c] * tx
                out[(py * width + px) * 4 + c] = top * (1 - ty) + bottom * ty
            }
        }
    }
    return out
}

/// `c·o·(T + (1−Ta)·B)` over an opaque destination, per pixel: `tint` a gray
/// `l` with alpha `a`.
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

private func maxLevelsOff(_ pixels: [UInt8], width: Int, expected: [Float]) -> Float {
    var worst: Float = 0
    for p in 0..<(expected.count / 4) {
        let got = px(pixels, p % width, p / width, width: width)
        for c in 0..<4 { worst = max(worst, abs(Float(got[c]) - expected[p * 4 + c] * 255)) }
    }
    return worst
}

// MARK: - Harness

@MainActor
private func offscreenRenderer(_ width: Int, _ height: Int) throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

@MainActor
private func draw(_ renderer: SDLWindowRenderer, _ scene: Scene, width: Int, height: Int,
                  surfaces: [SurfaceDrawRequest] = [], atlas: GlyphAtlas = GlyphAtlas(width: 16, height: 16)) throws -> [UInt8] {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: atlas, surfaces: surfaces))
    return try renderer.readPixels(width: width, height: height)
}

private func replayPixels(_ scene: Scene, width: Int, height: Int) throws -> [UInt8] {
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory,
                                   driver: SDLWindowRenderer.defaultDriver)
    return try replayer.render(scene, atlas: GlyphAtlas(width: 16, height: 16), width: width, height: height,
                               projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
}

// MARK: - Tests

/// **3.3** (`BB-A`, `BB-D`, `BB-R`, `BB-S`). A backdrop over a red|blue step
/// reads, within three levels, the reference blur of the step composited under
/// the tint — at σ = 16, 52 and 104 device pixels (52 pt at scales 1 and 2) —
/// the counters read what the Metal renderer's do for the same scene (one
/// split, one blur, `L + 2` passes, one frame-target copy), a second frame
/// makes no texture, and the replay path draws the same pixels. Mutations:
/// skip the HLSL downsample; change one tap weight.
@Test(arguments: [Float(16), 52, 104]) @MainActor
func sdlOffscreenBackdropEqualsTheReferenceAndCountsMatchMetal(sigma: Float) throws {
    let (w, h) = (200, 40)
    let renderer = try offscreenRenderer(w, h)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), sigma: sigma))
    scene.finalize()
    let pixels = try draw(renderer, scene, width: w, height: h)
    let step = stepPixels(width: w, height: h, edge: 100)
    let expected = composite(blurred: blurred(step, width: w, height: h, sigma: sigma), destination: step,
                             grayTint: 0.5, alpha: 0.3, opacity: 1)
    let off = maxLevelsOff(pixels, width: w, expected: expected)
    #expect(off <= 3, "σ \(sigma): worst channel \(off) levels off the reference")
    let mid = px(pixels, 100, 20, width: w)
    #expect(mid[0] > 20 && mid[2] > 20, "σ \(sigma): a step reads both colours at the edge: \(mid)")

    let level = levels(sigma: sigma)
    #expect(renderer.lastBackdropSplits == 1)
    #expect(renderer.lastBackdropBlurs == 1)
    #expect(renderer.lastBackdropPasses == level + 2, "L downsamples and the two Gaussians (BB-S)")
    #expect(renderer.lastFrameTargetCopies == 1)
    #expect(renderer.lastBackdropTexturesMade > 0, "the first frame makes the frame target and the pool")

    let again = try draw(renderer, scene, width: w, height: h)
    #expect(again == pixels)
    #expect(renderer.lastBackdropTexturesMade == 0, "a steady frame makes no texture")
    #expect(try replayPixels(scene, width: w, height: h) == pixels, "the window renderer is the replay path's frame")
}

/// **3.3b** (`BB-C`). A scene with no backdrop takes the old path: every
/// counter 0 and no frame target; forced through the frame target by the
/// package hook it draws the same pixels, so the equality is the blit's
/// exactness and the counters are what tell the paths apart. Mutation: route
/// every scene through the frame target.
@Test @MainActor func aSceneWithoutBackdropsTakesTheOldPath() throws {
    let (w, h) = (64, 32)
    let renderer = try offscreenRenderer(w, h)
    var scene = stepScene(width: w, height: h, edge: 20)
    scene.finalize()
    let old = try draw(renderer, scene, width: w, height: h)
    #expect(renderer.lastBackdropSplits == 0 && renderer.lastBackdropBlurs == 0 && renderer.lastBackdropPasses == 0
            && renderer.lastFrameTargetCopies == 0 && renderer.lastBackdropTexturesMade == 0)
    #expect(!renderer.hasBackdropFrameTarget)
    renderer.routesEveryFrameThroughTheFrameTarget = true
    let forced = try draw(renderer, scene, width: w, height: h)
    #expect(renderer.lastFrameTargetCopies == 1 && renderer.hasBackdropFrameTarget)
    #expect(forced == old, "the frame target and its blit are exact")
}

/// **3.3c** (`BB-E`). Two side-by-side backdrops with no other primitive
/// between them are one run (one split, two blurs); two that overlap are two
/// runs (two splits); `L + 2` passes a record either way.
@Test @MainActor func splitsCountRunsAndBlursCountRecords() throws {
    let (w, h) = (200, 40)
    let renderer = try offscreenRenderer(w, h)
    var apart = stepScene(width: w, height: h, edge: 100)
    apart.insert(backdrop(mb(0, 0, 90, 40), sigma: 16))
    apart.insert(backdrop(mb(110, 0, 90, 40), sigma: 16))
    apart.finalize()
    _ = try draw(renderer, apart, width: w, height: h)
    #expect(renderer.lastBackdropSplits == 1 && renderer.lastBackdropBlurs == 2)
    #expect(renderer.lastBackdropPasses == 2 * (levels(sigma: 16) + 2))

    var overlapping = stepScene(width: w, height: h, edge: 100)
    overlapping.insert(backdrop(mb(0, 0, 120, 40), sigma: 16))
    overlapping.insert(backdrop(mb(80, 0, 120, 40), sigma: 16))
    overlapping.finalize()
    _ = try draw(renderer, overlapping, width: w, height: h)
    #expect(renderer.lastBackdropSplits == 2 && renderer.lastBackdropBlurs == 2)
}

/// **3.3d** (`BB-I`). When a blur texture cannot be made the record draws its
/// flat tint over the sharp backdrop — today's pixels: `T + (1 − Ta)·step`.
/// Mutation: draw nothing on failure.
@Test @MainActor func aFailedBlurTextureDrawsTheFlatTint() throws {
    let (w, h) = (200, 40)
    let renderer = try offscreenRenderer(w, h)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), sigma: 52))
    scene.finalize()
    renderer.backdropPoolFailsAllocation = true
    let pixels = try draw(renderer, scene, width: w, height: h)
    let step = stepPixels(width: w, height: h, edge: 100)
    let expected = composite(blurred: step, destination: step, grayTint: 0.5, alpha: 0.3, opacity: 1)
    #expect(maxLevelsOff(pixels, width: w, expected: expected) <= 2, "the sharp backdrop under the flat tint")
    #expect(renderer.lastBackdropBlurs == 0 && renderer.lastBackdropPasses == 0)
    renderer.backdropPoolFailsAllocation = false
    let blurredPixels = try draw(renderer, scene, width: w, height: h)
    #expect(blurredPixels != pixels)
    #expect(renderer.lastBackdropBlurs == 1)
}

/// **3.3e** (`BB-A`). The shape and clip: pixels outside an ellipse backdrop's
/// shape are the sharp backdrop, and a clip narrower than the bounds cuts the
/// quad. Mutations: ignore the shape bits; ignore `contentMask`.
@Test @MainActor func pixelsOutsideTheShapeAndTheClipAreUntouched() throws {
    let (w, h) = (200, 80)
    let renderer = try offscreenRenderer(w, h)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(40, 0, 120, 80), sigma: 16, shape: UInt32(MUIShapeEllipse.rawValue)))
    scene.finalize()
    let pixels = try draw(renderer, scene, width: w, height: h)
    // The bounds' corner is outside the ellipse: the step's own red, sharp.
    #expect(px(pixels, 42, 2, width: w) == [255, 0, 0, 255])
    #expect(px(pixels, 99, 40, width: w)[2] > 0, "inside the ellipse the step is blurred: blue leaks left of the edge")

    var clipped = stepScene(width: w, height: h, edge: 100)
    clipped.insert(backdrop(mb(0, 0, 200, 80), sigma: 16, mask: mb(0, 0, 100, 80)))
    clipped.finalize()
    let cut = try draw(renderer, clipped, width: w, height: h)
    #expect(px(cut, 150, 40, width: w) == [0, 0, 255, 255], "right of the clip the step is sharp")
    #expect(px(cut, 99, 40, width: w)[2] > 0, "left of it, blurred")
}

/// **3.3f** (`BB-G`). `opacity` 0.5 is a half-weight composite of the blurred
/// layer over the SHARP backdrop (probe `O`), not a half-alpha tint.
/// Mutation: multiply the tint's alpha instead.
@Test @MainActor func opacityHalfIsAHalfWeightCompositeOverTheSharpBackdrop() throws {
    let (w, h) = (200, 40)
    let renderer = try offscreenRenderer(w, h)
    var scene = stepScene(width: w, height: h, edge: 100)
    scene.insert(backdrop(mb(0, 0, 200, 40), tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), sigma: 16, opacity: 0.5))
    scene.finalize()
    let pixels = try draw(renderer, scene, width: w, height: h)
    let step = stepPixels(width: w, height: h, edge: 100)
    let expected = composite(blurred: blurred(step, width: w, height: h, sigma: 16), destination: step,
                             grayTint: 0.5, alpha: 0.3, opacity: 0.5)
    #expect(maxLevelsOff(pixels, width: w, expected: expected) <= 3)
}

// MARK: - A GPU surface under the backdrop (3.5)

@MainActor private func surfaceRequest(_ target: SurfaceTarget, source: OpaquePointer) -> SurfaceDrawRequest {
    SurfaceDrawRequest(target: target, scaleFactor: 1, time: 0, policy: .onDemand, value: nil) { ctx in
        ctx.clear(red: 0, green: 0, blue: 0, alpha: 1)
        guard let sdl = ctx as? SDLGPUDrawContext else { return }
        #expect(sdl.blitForTesting(from: source, width: 2, height: 2))
    }
}

/// **3.5** (`BB-C`, spec §3.2). A GPU surface drawn BEFORE a backdrop in scene
/// order is blurred by it — its red|blue / green|white quadrants (a 2 × 2
/// texture blitted nearest into the surface target) read the reference blur of
/// those pixels; the same two primitives in the other order leave the
/// quadrants sharp. The MetalCreator case. Mutation: draw the backdrop run
/// before the surface run.
@Test @MainActor func sdlBackdropBlursAGPUSurfaceUnderIt() throws {
    let (w, h) = (60, 40)
    let renderer = try offscreenRenderer(w, h)
    let quadrants: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255, 0, 255, 0, 255, 255, 255, 255, 255]
    let source = try #require(renderer.makeTestTexture(rgba: quadrants, width: 2, height: 2))
    defer { renderer.releaseTestTexture(source) }
    let target = SurfaceTarget(id: SurfaceID(rawValue: 7), width: 40, height: 40)
    let box = mb(10, 0, 40, 40)
    func quad() -> MUIImage {
        MUIImage(bounds: box, contentMask: wide, maskCornerRadii: square, opacity: 1, texture: 0, filter: 0, order: 0)
    }
    var above = Scene()
    above.insert(solid(mb(0, 0, 60, 40), black))
    above.insert(quad(), surface: target)
    above.insert(backdrop(mb(0, 0, 60, 40), sigma: 16))
    above.finalize()
    let blurredPixels = try draw(renderer, above, width: w, height: h, surfaces: [surfaceRequest(target, source: source)])
    // The scene's pixels by construction: black, then the four quadrants.
    var scenePixels = [Float](repeating: 0, count: w * h * 4)
    let colours: [[Float]] = [[1, 0, 0], [0, 0, 1], [0, 1, 0], [1, 1, 1]]
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        scenePixels[i + 3] = 1
        if x >= 10 && x < 50 {
            let c = colours[(y / 20) * 2 + (x - 10) / 20]
            scenePixels[i] = c[0]; scenePixels[i + 1] = c[1]; scenePixels[i + 2] = c[2]
        }
    } }
    let reference = blurred(scenePixels, width: w, height: h, sigma: 16)
    #expect(maxLevelsOff(blurredPixels, width: w, expected: reference) <= 3)
    #expect(px(blurredPixels, 20, 10, width: w) != [255, 0, 0, 255], "the surface's red quadrant is blurred")

    var below = Scene()
    below.insert(solid(mb(0, 0, 60, 40), black))
    below.insert(backdrop(mb(0, 0, 60, 40), sigma: 16))
    below.insert(quad(), surface: target)
    below.finalize()
    let sharp = try draw(renderer, below, width: w, height: h, surfaces: [surfaceRequest(target, source: source)])
    #expect(px(sharp, 20, 10, width: w) == [255, 0, 0, 255], "a surface drawn after the backdrop stays sharp")
    #expect(px(sharp, 40, 30, width: w) == [255, 255, 255, 255])
}

/// **3.3g** (`BB-D`). The bridge derives the level count from a record's own
/// sigma (`mui_backdrop_levels`), so it is `BackdropBlurReference.levels`
/// restated in C and must agree with it at every threshold: the smallest `L`
/// with `σ / 2^L ≤ 4`, at most `MUIBackdropBlurMaxLevel`. Mutation: change the
/// `≤ 4` to `< 4` or the cap.
@Test func theBridgeLevelsAreTheReferencesLevels() {
    #expect(Int(MUIBackdropBlurMaxLevel) == 6)
    for sigma: Float in [0, 1, 4, 4.01, 8, 8.5, 16, 52, 104, 128, 255.9, 256, 256.1, 512, 10_000] {
        #expect(Int(mui_backdrop_levels(sigma)) == levels(sigma: sigma), "σ \(sigma)")
    }
}
