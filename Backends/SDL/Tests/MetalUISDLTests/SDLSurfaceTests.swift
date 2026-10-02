import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import ReplayFixture

// MetalView on the SDL GPU renderer (rulings MV-E, MV-F, MV-H; spec
// `2026-10-01-metal-view-design.md` §4's SDL paragraph and §8's lane 3). A
// surface's content is app-defined GPU work, so every test draws a KNOWN fill
// through the portable `ctx.clear` (MV-H item 4) and reads the composite back
// from an offscreen `SDLWindowRenderer`. Compositing is an `Image`'s (MV-D,
// probe arms C1–C3); the target is the bounds × scale (D1). No `SDLPlatform`
// is created here, but every helper still arms the run-loop exit check
// (record §61 §9): the offscreen renderer initialises SDL video.

/// The Metal renderer's parity literal, copied from `SurfaceParity`
/// (`Tests/MetalUIRenderTests/SurfaceCompositingTests.swift`, test 2.11 —
/// another package, so it cannot be imported): a black 40 × 40 rect,
/// surface A (texel (200, 100, 40, 255), radius-6 mask, opacity 0.5) and
/// surface B (opaque blue). Over opaque black every expected channel is an
/// exact integer, so no GPU rounding enters it.
private enum SurfaceParity {
    static let side = 40
    static let maskRadius: Float = 6
    static let opacityA: Float = 0.5
    static let texelA: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (200, 100, 40, 255)
    static let texelB: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 255, 255)
    static let expected: [(x: Int, y: Int, rgba: [Int])] = [
        (10, 10, [100, 50, 20, 255]),  // A's centre: half A over black
        (0, 0, [0, 0, 0, 255]),        // A's corner, outside the radius-6 mask
        (30, 30, [0, 0, 255, 255]),    // B's centre
        (30, 10, [0, 0, 0, 255])       // neither quad
    ]
}

/// The offscreen target: the parity square plus a 20-point strip on its right
/// holding one ordinary image, so the scene has a texture ahead of the
/// surfaces and a forgotten texture-index offset binds the wrong one (M3b).
private let width = 60, height = 40

private let green = ImageTexture(width: 1, height: 1, straightRGBA: [0, 255, 0, 255])

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func corners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
private let black = MUIHsla(h: 0, s: 0, l: 0, a: 1)

private func background(_ scene: inout Scene) {
    let all = bounds(0, 0, Float(width), Float(height))
    scene.insert(MUIRect(bounds: all, contentMask: all, maskCornerRadii: corners(0),
                         background: black, borderColor: black, cornerRadii: corners(0),
                         borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0))
}

private func quad(_ box: MUIBounds, radius: Float = 0, opacity: Float = 1, order: MUIUInt) -> MUIImage {
    MUIImage(bounds: box, contentMask: box, maskCornerRadii: corners(radius), opacity: opacity, texture: 0,
             filter: MUIUInt(MUIImageFilterLinear.rawValue), order: order)
}

private let targetA = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 20, height: 20)
private let targetB = SurfaceTarget(id: SurfaceID(rawValue: 2), width: 20, height: 20)

/// `SurfaceParity`'s scene (the green image strip first, so it holds texture 0).
private func parityScene() -> Scene {
    var scene = Scene()
    background(&scene)
    scene.insert(quad(bounds(40, 0, 20, 40), order: 1), texture: green)
    scene.insert(quad(bounds(0, 0, 20, 20), radius: SurfaceParity.maskRadius, opacity: SurfaceParity.opacityA,
                      order: 2), surface: targetA)
    scene.insert(quad(bounds(20, 20, 20, 20), order: 3), surface: targetB)
    scene.finalize()
    return scene
}

/// A scene with one surface quad, `target`, over the black background.
private func oneSurfaceScene(_ target: SurfaceTarget, at box: MUIBounds = bounds(0, 0, 20, 20)) -> Scene {
    var scene = Scene()
    background(&scene)
    scene.insert(quad(box, order: 1), surface: target)
    scene.finalize()
    return scene
}

private func backgroundOnly() -> Scene {
    var scene = Scene()
    background(&scene)
    scene.finalize()
    return scene
}

/// A request whose draw clears `target` to `texel` (premultiplied, opaque).
@MainActor
private func clearing(_ target: SurfaceTarget, _ texel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
                      policy: RedrawPolicy = .onDemand, time: Double = 0,
                      draw extra: @escaping @MainActor (any GPUSurfaceContext) -> Void = { _ in })
    -> SurfaceDrawRequest {
    SurfaceDrawRequest(target: target, scaleFactor: 1, time: time, policy: policy, value: nil) { ctx in
        ctx.clear(red: Float(texel.r) / 255, green: Float(texel.g) / 255, blue: Float(texel.b) / 255,
                  alpha: Float(texel.a) / 255)
        extra(ctx)
    }
}

@MainActor
private func offscreenRenderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

@MainActor
private func frame(_ renderer: SDLWindowRenderer, _ scene: Scene, _ surfaces: [SurfaceDrawRequest],
                   atlas: GlyphAtlas = GlyphAtlas(width: 16, height: 16)) throws {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: atlas, surfaces: surfaces))
}

/// BGRA at (x, y) as (r, g, b, a).
private func rgba(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

private func close(_ a: [Int], _ b: [Int], within tolerance: Int) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

/// **3.1** (`MV-D`, `MV-H` item 4; probe C1–C3). Two surfaces cleared by a
/// test callback to `SurfaceParity`'s texels composite on SDL exactly as on
/// the Metal renderer: masked by the quad's rounded content mask, scaled by its
/// opacity, premultiplied source-over — the same four literal pixels within
/// `ParityTolerance.outsideGlyphs` (one UNORM step: a uniform target samples
/// to its own texel under any filter weight, so `insideGlyphs`' sub-texel
/// reason does not arise). The image ahead of them still draws.
///
/// Mutations **M3a** (the surface quads not appended to the image array) and
/// **M3b** (the texture-index offset forgotten — A then binds the image's
/// green texture).
@MainActor
@Test func anSDLSurfaceFillMatchesTheMetalParityLiteral() throws {
    let renderer = try offscreenRenderer()
    let scene = parityScene()
    try #require(scene.drawList.map(\.kind) == [.rect, .image, .surface, .surface], "set up: two surface runs")
    try frame(renderer, scene, [clearing(targetA, SurfaceParity.texelA), clearing(targetB, SurfaceParity.texelB)])
    let pixels = try renderer.readPixels(width: width, height: height)
    for (x, y, expected) in SurfaceParity.expected {
        #expect(close(rgba(pixels, x, y), expected, within: ParityTolerance.outsideGlyphs),
                "(\(x), \(y)) read \(rgba(pixels, x, y)), expected \(expected)")
    }
    #expect(rgba(pixels, 50, 20) == [0, 255, 0, 255], "the ordinary image still draws")
}

/// **3.2** (`MV-F` item 3, `MV-G` item 2). A surface's draw runs inside the
/// frame — recorded into the frame's command buffer before MetalUI's pass —
/// so its fill is composited on the very first frame; an `.onDemand` surface
/// with an unchanged request is not drawn again and the second frame shows the
/// same pixels from the kept target.
///
/// Mutations **M3c** (draws run after `mui_renderer_finish`: the first frame
/// shows the background) and **M3d** (the table replaced every frame: two
/// targets, two draws).
@MainActor
@Test func anSDLSurfaceIsDrawnBeforeTheSceneAndKeptAcrossFrames() throws {
    let renderer = try offscreenRenderer()
    let red: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (255, 0, 0, 255)
    let scene = oneSurfaceScene(targetA)
    try frame(renderer, scene, [clearing(targetA, red)])
    let first = try renderer.readPixels(width: width, height: height)
    #expect(rgba(first, 10, 10) == [255, 0, 0, 255], "drawn and composited on the first frame")
    #expect(rgba(first, 30, 30) == [0, 0, 0, 255], "outside the quad")

    try frame(renderer, scene, [clearing(targetA, red)])
    let second = try renderer.readPixels(width: width, height: height)
    #expect(renderer.surfaceDraws == 1, "an unchanged .onDemand request is not drawn again")
    #expect(renderer.surfaceTargetsCreated == 1, "and its target is reused")
    #expect(second == first, "the kept target still shows the first frame's fill")
}

/// **3.3** (`MV-E` item 1, `MV-G` item 4). A target no frame references is
/// released through the bridge at that frame; coming back is a new target,
/// drawn again.
///
/// Mutation **M3e**: the table's `release` closure does nothing (no
/// `mui_renderer_release_texture`, no count).
@MainActor
@Test func anSDLSurfaceTargetIsReleasedWhenNoLongerReferenced() throws {
    let renderer = try offscreenRenderer()
    let blue: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = (0, 0, 255, 255)
    try frame(renderer, oneSurfaceScene(targetA), [clearing(targetA, blue)])
    try #require(renderer.surfaceTargetsCreated == 1)
    #expect(renderer.surfaceTargetsReleased == 0)

    try frame(renderer, backgroundOnly(), [])
    #expect(renderer.surfaceTargetsReleased == 1, "the unreferenced target is released")
    #expect(rgba(try renderer.readPixels(width: width, height: height), 10, 10) == [0, 0, 0, 255])

    try frame(renderer, oneSurfaceScene(targetA), [clearing(targetA, blue)])
    #expect(renderer.surfaceTargetsCreated == 2, "coming back is a new target")
    #expect(renderer.surfaceDraws == 2, "drawn again")
    #expect(rgba(try renderer.readPixels(width: width, height: height), 10, 10) == [0, 0, 255, 255])
}

/// **3.4** (`MV-H` item 2, `MV-L` item 4; the fence rule, CLAUDE.md
/// "Renderer", record §61 §10). Back-to-back offscreen frames, no readback
/// between them, each holding a NEW surface (a new target created, cleared and
/// drawn, the last one released): every frame submits exactly ONE command
/// buffer — the surfaces ride the frame's own — and no frame releases a fence
/// the GPU has not signalled.
///
/// Mutations **M3f** (a new target's clear submitted in its own command
/// buffer: the submission clause) and **M3f′** (`retire_fence` →
/// `release_fence` in `mui_renderer_finish`: the fence clause, and the
/// existing `backToBackFramesNeverReleaseAnUnsignaledFence`).
@MainActor
@Test func surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence() throws {
    let renderer = try offscreenRenderer()
    let atlas = GlyphAtlas(width: 16, height: 16)
    var perFrame: [Int] = []
    for index in 1...16 {
        let target = SurfaceTarget(id: SurfaceID(rawValue: UInt64(index)), width: 20, height: 20)
        let shade = UInt8(index * 15)
        let before = renderer.submissionCount
        try frame(renderer, oneSurfaceScene(target), [clearing(target, (shade, 0, 0, 255))], atlas: atlas)
        perFrame.append(renderer.submissionCount - before)
    }
    try #require(perFrame.count == 16)
    #expect(perFrame.allSatisfy { $0 == 1 }, "submissions per frame: \(perFrame)")
    #expect(renderer.unsignaledFenceReleaseCount == 0)
    #expect(renderer.surfaceTargetsCreated == 16 && renderer.surfaceTargetsReleased == 15)
    #expect(rgba(try renderer.readPixels(width: width, height: height), 10, 10) == [240, 0, 0, 255],
            "the last frame's new surface")
}

/// **3.5** (`MV-F` item 4). The draw gets an `SDLGPUDrawContext` carrying the
/// renderer's device, THE FRAME'S OWN command buffer (the one
/// `mui_renderer_finish` submits) and the target, at the target's device-pixel
/// size, with the request's scale and time, the renderer's finished-frame
/// count, and `isNewTarget` true on creation, false after.
///
/// Mutation **M3g**: the context carries a freshly acquired command buffer.
@MainActor
@Test func theSDLDrawContextCarriesTheFramesCommandBufferAndTarget() throws {
    let renderer = try offscreenRenderer()
    let target = SurfaceTarget(id: SurfaceID(rawValue: 7), width: 30, height: 12)
    var seen: [(context: SDLGPUDrawContext, frameBuffer: OpaquePointer?)] = []
    func request(time: Double) -> SurfaceDrawRequest {
        clearing(target, (0, 255, 0, 255), policy: .continuous, time: time) { ctx in
            if let sdl = ctx as? SDLGPUDrawContext { seen.append((sdl, renderer.frameCommandBuffer)) }
        }
    }
    let scene = oneSurfaceScene(target, at: bounds(0, 0, 30, 12))
    try frame(renderer, scene, [request(time: 1.5)])
    try frame(renderer, scene, [request(time: 1.75)])
    try #require(seen.count == 2, "a .continuous surface draws on both frames, with an SDL context")
    for (context, frameBuffer) in seen {
        #expect(context.commandBuffer == frameBuffer, "the frame's own command buffer")
        #expect(context.pixelSize == Size(width: DevicePixels(30), height: DevicePixels(12)))
        #expect(context.scaleFactor == 1)
    }
    #expect(seen[0].context.target == seen[1].context.target, "one kept target")
    #expect(seen[0].context.device == seen[1].context.device)
    #expect(seen.map(\.context.isNewTarget) == [true, false])
    #expect(seen.map(\.context.time) == [1.5, 1.75])
    #expect(seen.map(\.context.frameIndex) == [0, 1])
    #expect(rgba(try renderer.readPixels(width: width, height: height), 15, 6) == [0, 255, 0, 255])
}
