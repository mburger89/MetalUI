// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
import SDLBridge

public struct SDLRendererError: Error, CustomStringConvertible {
    public let description: String
    init(_ what: String) { description = "\(what): \(String(cString: replay_error()))" }
}

/// No compiled-shader directory where ``SDLWindowRenderer`` looks (ruling
/// `PX-P`): names every directory tried, as `ShaderLibrary` does for the
/// Metal renderer's bundle (`AI-N`).
public struct SDLShaderDirectoryError: Error, CustomStringConvertible {
    /// The directories tried, in order.
    public let candidates: [String]
    public var description: String {
        "no compiled SDL shaders (a directory holding SOURCE.sha256) in any of: "
            + candidates.joined(separator: ", ")
            + " — copy Backends/SDL/Shaders/compiled beside the executable as "
            + "\(SDLWindowRenderer.executableShaderDirectoryName) (docs/packaging.md)"
    }
}

/// The SDL GPU ``WindowRenderer`` (ruling RS-D): MetalUI frames drawn by SDL3's
/// GPU API — Metal on macOS, Vulkan on Linux, Direct3D 12 on Windows — from
/// the same `Scene` bytes and atlas the Metal renderer draws, with the shaders
/// compiled from `Shaders/replay.hlsl`. Draws into a claimed SDL window, or,
/// with none, into an offscreen target ``readPixels()`` returns (how it is
/// tested against the Metal renderer).
@MainActor
public final class SDLWindowRenderer: WindowRenderer {
    private let renderer: OpaquePointer
    private let window: OpaquePointer?
    private let offscreenScaleFactor: Float

    /// The compiled shader stages in this package's source tree
    /// (`Shaders/compiled`), found from this file's path: the backend is built
    /// from source, like everything in this repository. Valid only on the
    /// machine that built the executable (ruling `PX-P`).
    public nonisolated static var bundledShaderDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shaders").appendingPathComponent("compiled").path
    }

    /// The directory beside an executable that a packaged app ships its
    /// shaders in: a copy of `Backends/SDL/Shaders/compiled` (ruling `PX-P`,
    /// `docs/packaging.md`).
    public nonisolated static let executableShaderDirectoryName = "MetalUISDLShaders"

    /// Where the shaders are looked for, in order (ruling `PX-P`):
    /// `MetalUISDLShaders` beside the executable — so a built app can be moved
    /// — then ``bundledShaderDirectory``.
    public nonisolated static func shaderDirectoryCandidates(executableDirectory: String) -> [String] {
        [URL(fileURLWithPath: executableDirectory).appendingPathComponent(executableShaderDirectoryName).path,
         bundledShaderDirectory]
    }

    /// The first of `candidates` holding `SOURCE.sha256` (what
    /// `scripts/compile-shaders.py` writes beside the stages); none throws an
    /// ``SDLShaderDirectoryError`` naming every one.
    public nonisolated static func shaderDirectory(from candidates: [String]) throws -> String {
        guard let found = candidates.first(where: {
            FileManager.default.fileExists(atPath: URL(fileURLWithPath: $0).appendingPathComponent("SOURCE.sha256").path)
        }) else { throw SDLShaderDirectoryError(candidates: candidates) }
        return found
    }

    /// The shader directory a renderer created without one uses: the first of
    /// ``shaderDirectoryCandidates(executableDirectory:)`` for this process's
    /// executable.
    public nonisolated static func defaultShaderDirectory() throws -> String {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
        return try shaderDirectory(from: shaderDirectoryCandidates(
            executableDirectory: executable.deletingLastPathComponent().path))
    }

    /// The SDL GPU driver this platform's shaders are for.
    public nonisolated static var defaultDriver: String {
        #if os(Windows)
        "direct3d12"
        #elseif os(macOS)
        "metal"
        #else
        "vulkan"
        #endif
    }

    /// A renderer drawing into `window` (an `SDL_Window *`).
    /// `shaderDirectory` `nil` is ``defaultShaderDirectory()`` (ruling `PX-P`).
    public init(window: OpaquePointer, driver: String = defaultDriver,
                shaderDirectory: String? = nil) throws {
        let shaderDirectory = try shaderDirectory ?? Self.defaultShaderDirectory()
        guard let renderer = mui_renderer_create(shaderDirectory, driver) else {
            throw SDLRendererError("SDL GPU device")
        }
        guard mui_renderer_claim_window(renderer, UnsafeMutableRawPointer(window)) else {
            let error = SDLRendererError("claiming the window")
            mui_renderer_destroy(renderer)
            throw error
        }
        self.renderer = renderer
        self.window = window
        self.offscreenScaleFactor = 1
    }

    /// A windowless renderer drawing into a `width`×`height` device-pixel
    /// target, reported at `scaleFactor`; `shaderDirectory` `nil` is
    /// ``defaultShaderDirectory()``.
    public init(offscreenWidth width: Int, height: Int, scaleFactor: Float = 1,
                driver: String = defaultDriver, shaderDirectory: String? = nil) throws {
        let shaderDirectory = try shaderDirectory ?? Self.defaultShaderDirectory()
        guard let renderer = mui_renderer_create(shaderDirectory, driver) else {
            throw SDLRendererError("SDL GPU device")
        }
        guard mui_renderer_set_offscreen_size(renderer, UInt32(width), UInt32(height)) else {
            let error = SDLRendererError("offscreen target")
            mui_renderer_destroy(renderer)
            throw error
        }
        self.renderer = renderer
        self.window = nil
        self.offscreenScaleFactor = scaleFactor
    }

    // The renderer is only ever touched on the main actor; deinit is its end.
    nonisolated deinit {
        MainActor.assumeIsolated {
            for entry in textures.values { mui_renderer_release_texture(renderer, entry.handle) }
            for target in surfaceTable.handles { mui_renderer_release_texture(renderer, target) }
            mui_renderer_destroy(renderer)
        }
    }

    /// The GPU copy of each `ImageTexture` a recent frame drew (ruling TE-AF
    /// item 3), as the Metal renderer keeps them: keyed by identity **and
    /// holding the object**, so the identifier cannot be reused while the
    /// entry lives; uploaded once (`mui_renderer_create_texture`, never
    /// written again) and released as soon as a frame's scene stops
    /// referencing it — SDL frees the texture once no submitted frame uses it.
    private var textures: [ObjectIdentifier: (source: ImageTexture, handle: UnsafeMutableRawPointer)] = [:]

    /// This window's app-surface render targets (MetalView, ruling `MV-E`):
    /// the portable lifecycle, **per window** (each `SDLWindowRenderer` is one
    /// window's, and `SurfaceID`s are minted per window), created with
    /// `mui_renderer_create_target` and released with
    /// `mui_renderer_release_texture` — SDL frees a target once no submitted
    /// frame samples it.
    private var surfaceTable = SurfaceTargetTable<UnsafeMutableRawPointer>()
    /// Frames finished, ever — a draw context's `frameIndex`.
    private var finishedFrames: UInt64 = 0

    /// The `ImageTexture` identities with a GPU copy cached right now.
    package var cachedTextureIdentities: Set<ObjectIdentifier> { Set(textures.keys) }
    /// How many image textures have been uploaded, ever.
    package private(set) var textureUploadCount = 0
    /// How many cached image textures a frame has released, ever.
    package private(set) var textureReleaseCount = 0
    /// How many offscreen frames' fences were released before the GPU
    /// signalled them — always 0 (record §61 §10: SDL's Direct3D 12 backend
    /// recycles a released fence while the command buffer still points at it).
    package var unsignaledFenceReleaseCount: Int { Int(mui_renderer_unsignaled_fence_releases(renderer)) }

    /// How many command buffers the renderer has submitted, ever (every
    /// `SDL_Submit…` in `SDLBridge.c`'s renderer functions): an app surface's
    /// draw rides the frame's own buffer and adds none (`MV-L` item 4).
    package var submissionCount: Int { Int(mui_renderer_submission_count(renderer)) }
    /// The frame's `SDL_GPUCommandBuffer *` between `beginFrame()` and
    /// `finishFrame`, `nil` otherwise.
    package var frameCommandBuffer: OpaquePointer? {
        mui_renderer_command_buffer(renderer).map { OpaquePointer($0) }
    }
    /// Surface render targets created, ever — counted here, beside the bridge
    /// call, because `SurfaceTargetTable`'s own counters are `package` to the
    /// root package and do not cross into this one (`MV-L` item 2).
    package private(set) var surfaceTargetsCreated = 0
    /// Surface render targets released, ever.
    package private(set) var surfaceTargetsReleased = 0
    /// Surface draws run, ever.
    package private(set) var surfaceDraws = 0

    /// A sampled `R8G8B8A8_UNORM` texture of straight `rgba` texels, uploaded
    /// in its own submission — a test's blit source (`MV-Q`), released with
    /// ``releaseTestTexture(_:)``. Not a surface target; no counter moves.
    package func makeTestTexture(rgba: [UInt8], width: Int, height: Int) -> OpaquePointer? {
        rgba.withUnsafeBufferPointer {
            mui_renderer_create_texture(renderer, $0.baseAddress, UInt32(width), UInt32(height))
        }.map { OpaquePointer($0) }
    }
    /// Releases a ``makeTestTexture(rgba:width:height:)`` texture.
    package func releaseTestTexture(_ texture: OpaquePointer) {
        mui_renderer_release_texture(renderer, UnsafeMutableRawPointer(texture))
    }

    /// The SDL GPU driver in use (`metal`, `vulkan`, `direct3d12`).
    public var driver: String { String(cString: mui_renderer_driver(renderer)) }

    /// The device-pixel size of the target `beginFrame()` acquired: what a
    /// backdrop's region is clamped to (`Scene.backdropRegion`, ruling `BB-D` 3).
    private var targetSize: (width: Int, height: Int) = (0, 0)

    // The backdrop blur's work in the last frame and its test hooks (rulings
    // BB-E, BB-K, BB-S): the Metal renderer's counters under the same names,
    // kept in the bridge, 0 for a frame without a backdrop run.
    private func backdropCounter(_ index: Int) -> Int {
        var counters: [UInt32] = [0, 0, 0, 0, 0]
        mui_renderer_backdrop_counters(renderer, &counters)
        return Int(counters[index])
    }
    /// Backdrop runs of the last frame (each ends a segment of the frame target's pass).
    package var lastBackdropSplits: Int { backdropCounter(0) }
    /// Backdrop records the last frame blurred.
    package var lastBackdropBlurs: Int { backdropCounter(1) }
    /// Render passes the blurs took: `L + 2` per record (`BB-S`).
    package var lastBackdropPasses: Int { backdropCounter(2) }
    /// 1 when the last frame blitted the frame target to its target, else 0.
    package var lastFrameTargetCopies: Int { backdropCounter(3) }
    /// Textures (frame target and pool) the last frame had to create; 0 on a steady frame.
    package var lastBackdropTexturesMade: Int { backdropCounter(4) }
    /// The atlas bytes the last finished frame moved to the GPU (a test recorder, `RG-H`).
    package var lastAtlasBytes: Int { Int(mui_renderer_last_atlas_bytes(renderer)) }

    /// Whether the renderer holds a frame target.
    package var hasBackdropFrameTarget: Bool { mui_renderer_has_frame_target(renderer) }
    /// Test hook (`BB-K`, test 3.3d): every pool allocation fails, so each record draws its flat tint.
    package var backdropPoolFailsAllocation = false {
        didSet { mui_renderer_set_backdrop_hooks(renderer, backdropPoolFailsAllocation, routesEveryFrameThroughTheFrameTarget) }
    }
    /// Test hook (test 3.3b): route every frame, backdrop or not, through the frame target.
    package var routesEveryFrameThroughTheFrameTarget = false {
        didSet { mui_renderer_set_backdrop_hooks(renderer, backdropPoolFailsAllocation, routesEveryFrameThroughTheFrameTarget) }
    }

    public func beginFrame() -> Float? {
        var width: UInt32 = 0, height: UInt32 = 0
        guard mui_renderer_begin(renderer, &width, &height) == 1 else { return nil }
        targetSize = (Int(width), Int(height))
        if let window { return mui_window_pixel_density(UnsafeMutableRawPointer(window)) }
        return offscreenScaleFactor
    }

    /// Each of `scene.textures`' GPU handles, in order — uploading what is not
    /// cached, releasing what the scene does not reference. `nil` when an
    /// upload failed (the frame is then not drawn).
    private func prepareTextures(for scene: Scene) -> [UnsafeMutableRawPointer]? {
        var kept: [ObjectIdentifier: (source: ImageTexture, handle: UnsafeMutableRawPointer)] = [:]
        var handles: [UnsafeMutableRawPointer] = []
        var failed = false
        for source in scene.textures {
            let key = ObjectIdentifier(source)
            if let cached = textures[key] ?? kept[key] {
                kept[key] = cached
                handles.append(cached.handle)
                continue
            }
            guard let handle = source.pixels.withUnsafeBufferPointer({
                mui_renderer_create_texture(renderer, $0.baseAddress, UInt32(source.width), UInt32(source.height))
            }) else { failed = true; break }
            textureUploadCount += 1
            kept[key] = (source, handle)
            handles.append(handle)
        }
        for (key, entry) in textures where kept[key] == nil {
            mui_renderer_release_texture(renderer, entry.handle)
            textureReleaseCount += 1
        }
        textures = kept
        return failed ? nil : handles
    }

    /// Draws `scene` into the target `beginFrame()` acquired and submits it.
    ///
    /// **App surfaces** (MetalView, rulings `MV-E`, `MV-F`, `MV-H` item 2):
    /// after the image textures are prepared and before `mui_renderer_finish`
    /// begins MetalUI's own pass, the table resolves this frame's targets; each
    /// surface due a draw is cleared first if new, then handed an
    /// ``SDLGPUDrawContext`` over the frame's own command buffer — so its passes
    /// are recorded ahead of the composite that samples them, in the one
    /// submission `mui_renderer_finish` makes (no new submission, so no new
    /// fence: the fence rule holds by construction). The surface quads join the
    /// image array the bridge already uploads — each quad's `texture` offset
    /// by `scene.textures.count`, each `.surface` run an image run starting
    /// `scene.images.count` later — so neither the bridge's draw loop nor the
    /// HLSL changes. A run whose target has no handle (a `create` that failed,
    /// a headless scene's reference) is dropped. A draw is recorded only once
    /// its frame is submitted (`MV-O` item 2's rule on Metal).
    public func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        guard let handles = prepareTextures(for: scene) else { return false }
        guard let commandBuffer = mui_renderer_command_buffer(renderer) else { return false }

        let device = OpaquePointer(mui_renderer_device(renderer)!)
        let toDraw = surfaceTable.update(
            references: scene.surfaceTargets, requests: surfaces,
            create: { target in
                guard let handle = mui_renderer_create_target(renderer, UInt32(target.width), UInt32(target.height))
                else { return nil }
                surfaceTargetsCreated += 1
                return handle
            },
            release: { handle in
                mui_renderer_release_texture(renderer, handle)
                surfaceTargetsReleased += 1
            })
        for (request, target, isNew) in toDraw {
            let context = SDLGPUDrawContext(
                device: device, commandBuffer: OpaquePointer(commandBuffer), target: OpaquePointer(target),
                pixelSize: Size(width: DevicePixels(Int32(request.target.width)),
                                height: DevicePixels(Int32(request.target.height))),
                scaleFactor: request.scaleFactor, time: request.time, frameIndex: finishedFrames,
                isNewTarget: isNew)
            if isNew { context.clear(red: 0, green: 0, blue: 0, alpha: 0) }
            SDLGPUWindowGuard.beginDraw()
            request.draw(context)
            SDLGPUWindowGuard.endDraw()
            surfaceDraws += 1
        }

        // Each surface target's handle, after the image textures' (`nil` where
        // a target has none — no run that reaches the bridge names it).
        let surfaceHandles: [UnsafeMutableRawPointer?] = scene.surfaceTargets.map { surfaceTable.handle(for: $0.id) }
        let textureOffset = UInt32(handles.count)
        var images = scene.images
        images.reserveCapacity(scene.images.count + scene.surfaces.count)
        for var quad in scene.surfaces {
            quad.texture += textureOffset
            images.append(quad)
        }
        // Exhaustive (ruling TE-AF): the old `kind == .glyph ? 1 : 0` drew an
        // image run as rects.
        let runs = scene.drawList.compactMap { run -> ReplayRun? in
            switch run.kind {
            case .rect: return ReplayRun(kind: 0, start: UInt32(run.start), count: UInt32(run.count))
            case .glyph: return ReplayRun(kind: 1, start: UInt32(run.start), count: UInt32(run.count))
            case .image: return ReplayRun(kind: 2, start: UInt32(run.start), count: UInt32(run.count))
            case .surface:
                // One target per run (`finalize()` breaks where it changes).
                let target = Int(scene.surfaces[run.start].texture)
                guard surfaceHandles[target] != nil else { return nil }
                return ReplayRun(kind: 2, start: UInt32(scene.images.count + run.start), count: UInt32(run.count))
            case .backdrop:
                // A segment break: the bridge blurs each record from the frame as it
                // stands and draws its quad (rulings BB-C, BB-D).
                return ReplayRun(kind: 3, start: UInt32(run.start), count: UInt32(run.count))
            }
        }
        // Device-pixel coordinates, as the Metal renderer's surfaces use.
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        // The atlas' dirty rects as x, y, width, height words, one upload each (`RG-H`).
        let atlasRects: [UInt32] = atlas.dirtyRects.flatMap {
            [UInt32($0.x), UInt32($0.y), UInt32($0.width), UInt32($0.height)]
        }
        let optionalHandles: [UnsafeMutableRawPointer?] = handles + surfaceHandles
        // Each record's blurred region: `Scene.backdropRegion`, the one function
        // both renderers call (`BB-D` 3); `width` 0 is "none" (a flat tint).
        let regions: [ReplayRegion] = (0..<scene.backdrops.count).map { index in
            guard let region = scene.backdropRegion(index, target: targetSize) else {
                return ReplayRegion(x: 0, y: 0, width: 0, height: 0)
            }
            return ReplayRegion(x: Int32(region.x), y: Int32(region.y),
                                width: Int32(region.width), height: Int32(region.height))
        }
        let ok = scene.rects.withUnsafeBytes { rects in
            scene.glyphs.withUnsafeBytes { glyphs in
                images.withUnsafeBytes { images in
                  scene.transforms.withUnsafeBytes { transforms in
                   scene.backdrops.withUnsafeBytes { backdrops in
                    regions.withUnsafeBufferPointer { regionBuffer in
                    optionalHandles.withUnsafeBufferPointer { textureBuffer in
                        runs.withUnsafeBufferPointer { runBuffer in
                            atlas.pixels.withUnsafeBufferPointer { pixels in
                              atlasRects.withUnsafeBufferPointer { atlasRectBuffer in
                                identity.withUnsafeBufferPointer { matrix in
                                    mui_renderer_finish(renderer,
                                                        rects.baseAddress, UInt32(rects.count),
                                                        glyphs.baseAddress, UInt32(glyphs.count),
                                                        images.baseAddress, UInt32(images.count),
                                                        transforms.baseAddress, UInt32(transforms.count),
                                                        backdrops.baseAddress, UInt32(backdrops.count),
                                                        regionBuffer.baseAddress, UInt32(regionBuffer.count),
                                                        textureBuffer.baseAddress, UInt32(optionalHandles.count),
                                                        runBuffer.baseAddress, UInt32(runs.count),
                                                        pixels.baseAddress, UInt32(atlas.width), UInt32(atlas.height),
                                                        atlasRectBuffer.baseAddress,
                                                        UInt32(atlasRectBuffer.count / 4), matrix.baseAddress)
                                }
                              }
                            }
                        }
                    }
                    }
                   }
                  }
                }
            }
        }
        // As the Metal renderer does after its upload.
        if ok {
            atlas.clearDirtyRect()
            for drawn in toDraw { surfaceTable.didDraw(drawn.request) }
            finishedFrames += 1
        }
        return ok
    }

    /// The last offscreen frame, BGRA, row-major. Throws for a window renderer.
    public func readPixels(width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard mui_renderer_read_offscreen(renderer, &pixels) else { throw SDLRendererError("readback") }
        return pixels
    }
}

#endif
