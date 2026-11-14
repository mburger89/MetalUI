import Testing
import Foundation
import Metal
import simd
import MetalUICore
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// Backdrop memory (`BB-U`): a frame whose backdrop regions are a small part of the window draws into region-sized
// targets instead of a full-size frame target, and a window that draws no frame for a while frees its backdrop
// textures. Every pixel claim is "equal to the frame-target path, byte for byte" (`backdropRegionTargetsDisabled`).

/// A field, a material over it and a glass over the material (two runs: the glass overlaps the material, `BB-E`),
/// plus a glass lens elsewhere; the regions are a few percent of the frame.
private func memoryScene(width: Int, height: Int, runs: Int = 2, block: Int = 7) -> Scene {
    var scene = Scene()
    for rect in glassField(width: width, height: height, block: block).rects { scene.insert(rect) }
    var material = glassRecord(glassBounds(40, 30, 120, 36), tint: glassGray(0.5, alpha: 0.2), radius: 8, sigma: 18)
    material.glassFlags = 0
    scene.insert(material)
    if runs >= 2 {
        scene.insert(glassRecord(glassBounds(70, 40, 100, 30), tint: glassGray(0.8, alpha: 0.1), radius: 10, sigma: 6,
                                 lensRim: true, lensDepth: 6, band: 6, rim: 1))
    }
    // Content between the runs (drawn over the material, under the glass) and after the last run.
    scene.insert(glassSolid(glassBounds(90, 36, 12, 12), glassRedHSLA))
    scene.insert(glassRecord(glassBounds(200, 150, 90, 40), tint: glassGray(0.3, alpha: 0.2), radius: 12, sigma: 10,
                             lensRim: true, lensDepth: 5, band: 5, rim: 1))
    scene.insert(glassSolid(glassBounds(220, 160, 20, 10), glassGray(1)))
    scene.finalize()
    return scene
}

@MainActor private func renderer() throws -> Renderer {
    try Renderer(device: try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware"))
}

/// **M.1** (`BB-U`). A frame whose regions are a small part of the window draws into region targets and is byte for
/// byte the frame-target frame: the blurs, the lens, the content between and after the runs, and a glass over a
/// material (the second region holds the first's quad). Mutations: drop the viewport shift of a region target;
/// leave out the earlier run's quads from the later regions; read the region target at the frame origin.
@Test @MainActor func regionTargetsDrawTheFrameTargetFrameByteForByte() throws {
    let (w, h) = (320, 240)
    let scene = memoryScene(width: w, height: h)
    let regionRenderer = try renderer()
    let regionPixels = try regionRenderer.renderOffscreen(scene, size: glassTargetSize(w, h))
    #expect(regionRenderer.lastBackdropRegionTargets == 3, "three records, three region targets")
    #expect(regionRenderer.lastFrameTargetCopies == 0 && !regionRenderer.hasBackdropFrameTarget, "no frame target, no copy")
    #expect(regionRenderer.lastBackdropSplits == 3 || regionRenderer.lastBackdropSplits == 2)

    let framePixels = try { () throws -> [UInt8] in
        let r = try renderer()
        r.backdropRegionTargetsDisabled = true
        let pixels = try r.renderOffscreen(scene, size: glassTargetSize(w, h))
        #expect(r.lastBackdropRegionTargets == 0 && r.lastFrameTargetCopies == 1 && r.hasBackdropFrameTarget)
        return pixels
    }()
    #expect(regionPixels == framePixels, "region targets and the frame target draw the same bytes")
    // The scene is not trivially flat: the glass changed pixels inside its region.
    let plain = Scene()
    var bare = plain
    for rect in glassField(width: w, height: h, block: 7).rects { bare.insert(rect) }
    bare.finalize()
    #expect(try renderer().renderOffscreen(bare, size: glassTargetSize(w, h)) != regionPixels)
}

/// **M.2** (`BB-U`). The regions' textures are all a region frame holds: no texture of the frame's size, a resident
/// total a fraction of one frame target, and a steady frame makes none (`BB-S`). Mutation: acquire the frame target
/// anyway.
@Test @MainActor func aRegionFrameHoldsRegionsOnlyAndASteadyFrameMakesNoTextures() throws {
    let (w, h) = (1280, 800)
    let scene = memoryScene(width: w, height: h, block: 64)
    let r = try renderer()
    let state = BackdropFrameState()
    let device = r.device
    let target = try #require({ () -> (any MTLTexture)? in
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget; d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }())
    func frame() throws {
        let cb = try #require(r.commandQueue.makeCommandBuffer())
        let view = SurfaceView(colorTexture: target, viewport: MTLViewport(originX: 0, originY: 0, width: Double(w),
                                                                          height: Double(h), znear: 0, zfar: 1))
        try r.encode(scene, view: view, in: cb, surfaces: [:], backdropState: state)
        cb.commit(); cb.waitUntilCompleted()
    }
    try frame()
    #expect(r.lastBackdropTexturesMade > 0)
    let frameBytes = w * h * 4
    let resident = state.residentTextures
    #expect(!resident.contains { $0.label == "frame" }, "no frame target")
    #expect(resident.map(\.bytes).reduce(0, +) < frameBytes / 8, "the regions' textures are well under one frame target: \(resident.map(\.bytes).reduce(0, +)) B")
    try frame()
    #expect(r.lastBackdropTexturesMade == 0, "a steady frame makes no texture")
    #expect(r.lastBackdropRegionTargets == 3)
}

/// **M.3** (`BB-U`). The region path is for few runs and small regions; past either the frame target draws as before.
/// Mutation: remove each guard.
@Test @MainActor func bigRegionsAndManyRunsTakeTheFrameTarget() throws {
    let (w, h) = (320, 240)
    // A region covering more than a quarter of the frame.
    var big = Scene()
    for rect in glassField(width: w, height: h, block: 10).rects { big.insert(rect) }
    big.insert(glassRecord(glassBounds(0, 0, 300, 200), tint: glassGray(0.5, alpha: 0.2), sigma: 10))
    big.finalize()
    let r = try renderer()
    _ = try r.renderOffscreen(big, size: glassTargetSize(w, h))
    #expect(r.lastBackdropRegionTargets == 0 && r.lastFrameTargetCopies == 1, "a large region takes the frame target")
    // Five stacked backdrops, each over the one before: five runs.
    var many = Scene()
    for rect in glassField(width: w, height: h, block: 10).rects { many.insert(rect) }
    for k in 0..<5 {
        many.insert(glassRecord(glassBounds(10 + Float(k) * 8, 10 + Float(k) * 6, 40, 24), tint: glassGray(0.5, alpha: 0.1), sigma: 4))
    }
    many.finalize()
    _ = try r.renderOffscreen(many, size: glassTargetSize(w, h))
    #expect(r.lastBackdropSplits == 5)
    #expect(r.lastBackdropRegionTargets == 0 && r.lastFrameTargetCopies == 1, "more than \(Renderer.regionTargetRunLimit) runs take the frame target")
}

/// **M.4** (`BB-U`). A window renderer owns its backdrop state, so two windows on one renderer neither share a frame
/// target nor drop each other's pool; a window that draws no frame for `idleReleaseDelay` frees its backdrop
/// textures, and its next frame makes them again with the same pixels; frames that keep coming never free them.
/// Mutations: pass `nil` for the state again (windows share); never start the watcher; start it but never release.
@MainActor private final class OffscreenSurface: RenderSurface {
    let texture: any MTLTexture
    let size: Int
    init(device: any MTLDevice, width: Int, height: Int) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = .renderTarget; d.storageMode = .shared
        texture = try #require(device.makeTexture(descriptor: d)); size = width
    }
    func nextFrame() throws -> SurfaceFrame {
        SurfaceFrame(views: [SurfaceView(colorTexture: texture, viewport: MTLViewport(
            originX: 0, originY: 0, width: Double(texture.width), height: Double(texture.height), znear: 0, zfar: 1))],
                     scaleFactor: 1)
    }
    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer) {}
    func pixels() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4,
                                                      from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0) }
        return out
    }
}

@MainActor private func draw(_ window: MetalWindowRenderer, _ scene: Scene, _ atlas: GlyphAtlas) throws {
    #expect(window.beginFrame() != nil)
    #expect(window.finishFrame(scene: scene, atlas: atlas, surfaces: []))
    let cb = window.renderer.commandQueue.makeCommandBuffer()!
    cb.commit(); cb.waitUntilCompleted()   // the queue is in order: the frame's buffer is done by now
}

@Test @MainActor func aWindowFreesItsBackdropTexturesWhenIdleAndMakesThemAgainWithTheSamePixels() async throws {
    let (w, h) = (320, 240)
    let shared = try renderer()
    let atlas = GlyphAtlas(width: 64, height: 64)
    let a = MetalWindowRenderer(renderer: shared, surface: try OffscreenSurface(device: shared.device, width: w, height: h))
    let b = MetalWindowRenderer(renderer: shared, surface: try OffscreenSurface(device: shared.device, width: w, height: h))
    a.idleReleaseDelay = .milliseconds(500); b.idleReleaseDelay = .milliseconds(500)
    let scene = memoryScene(width: w, height: h)
    try draw(a, scene, atlas)
    let first = (a.surface as! OffscreenSurface).pixels()
    #expect(a.backdropState.isResident)
    // Another window on the same renderer does not touch this one's textures.
    try draw(b, scene, atlas)
    try draw(a, scene, atlas)
    #expect(shared.lastBackdropTexturesMade == 0, "a's second frame made no texture although b drew in between")
    #expect(a.backdropState !== b.backdropState)
    // Frames that keep coming keep the textures.
    for _ in 0..<8 {
        try await Task.sleep(for: .milliseconds(20))
        try draw(a, scene, atlas)
        #expect(a.backdropState.isResident && shared.lastBackdropTexturesMade == 0, "continuous frames make no texture and free none")
    }
    // Then nothing is drawn: the watcher frees a's textures.
    try await Task.sleep(for: .milliseconds(1500))
    #expect(!a.backdropState.isResident, "an idle window holds no backdrop texture")
    #expect(a.backdropState.residentTextures.isEmpty)
    try draw(a, scene, atlas)
    #expect(shared.lastBackdropTexturesMade > 0, "the next frame makes them again")
    #expect((a.surface as! OffscreenSurface).pixels() == first, "and draws the same pixels")
}
