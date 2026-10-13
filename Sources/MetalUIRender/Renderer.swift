import Metal
import MetalUICore
import MetalUIPath
import MetalUIScene
// The MetalUICore → shader-struct conversions moved to MetalUIPrimitives (ruling
// XP-A); re-exported so every importer of MetalUIRender still sees them.
@_exported import MetalUIPrimitives
import MetalUIShaderTypes
import MetalUIText
import simd

/// Why a `Renderer` could not be created.
public enum RendererError: Error, CustomStringConvertible {
    case commandQueueUnavailable
    case functionMissing(String)
    case bufferAllocationFailed
    case encoderUnavailable

    public var description: String {
        switch self {
        case .commandQueueUnavailable: "could not create a Metal command queue"
        case .functionMissing(let n):  "shader function missing: \(n)"
        case .bufferAllocationFailed:  "could not allocate a Metal buffer"
        case .encoderUnavailable:      "could not create a Metal command encoder"
        }
    }
}

/// The Metal renderer: pipelines, the glyph atlas texture and image texture
/// cache, and the encoding of a `Scene` into a render pass.
@MainActor
public final class Renderer {
    /// Gamma-encoded sRGB compositing (spec 7.8). NOT `_sRGB`: that format makes
    /// the hardware blend in linear space, which is the opposite of the decision.
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    /// The glyph atlas's texture format. R8: coverage, no colour (spec 7.8 —
    /// "glyph coverage (`r8Unorm`) is used as a blend weight directly,
    /// unmodified"). Not an `_sRGB` view, for the same reason the drawable is
    /// not one: a decode to linear here would be linear compositing entering
    /// through the atlas instead of through the target.
    public static let atlasPixelFormat: MTLPixelFormat = .r8Unorm

    /// The Metal device everything is created on.
    public let device: any MTLDevice
    /// The queue frames are committed on.
    public let commandQueue: any MTLCommandQueue

    private let rectPipeline: any MTLRenderPipelineState
    private let glyphPipeline: any MTLRenderPipelineState
    private let imagePipeline: any MTLRenderPipelineState
    private let unitVertexBuffer: any MTLBuffer
    /// The compiled shader library, kept so the backdrop pipelines can be
    /// built on first use (a renderer that never draws a material never
    /// pays for them).
    private let library: any MTLLibrary
    private var backdropPipelinesCache: BackdropPipelines?

    /// The frame target and blur textures a ``encode(_:view:in:surfaces:)``
    /// without a window's own state uses (`renderOffscreen`); a
    /// ``MetalWindowRenderer`` passes its own, so windows never share a
    /// frame target (spec 3.2).
    let defaultBackdropState = BackdropFrameState()

    // The backdrop counters of the last encode (rulings BB-E, BB-S): plain
    // integers, 0 on every scene without a backdrop. Pins count these, never
    // time.
    /// Backdrop runs of the last frame (each ends a segment of the frame target's pass).
    private(set) var lastBackdropSplits = 0
    /// Backdrop records the last frame blurred.
    private(set) var lastBackdropBlurs = 0
    /// Render passes the blurs took: `L + 2` per record (`BB-S`).
    private(set) var lastBackdropPasses = 0
    /// 1 when the last frame copied the frame target to its drawable, else 0.
    private(set) var lastFrameTargetCopies = 0
    /// Textures (frame target and pool) the last frame had to create; 0 on a steady frame.
    private(set) var lastBackdropTexturesMade = 0
    /// Test hook (`BB-K`, test 2.7): every pool allocation fails, so each record draws its flat tint.
    var backdropPoolFailsAllocation = false
    /// Test hook (test 2.3): route every scene, backdrop or not, through the frame target.
    var routesEveryFrameThroughTheFrameTarget = false
    /// Whether the default state holds a frame target (test 2.3).
    var hasBackdropFrameTarget: Bool { defaultBackdropState.hasFrameTarget }
    /// The one zero `MUITransform` record bound for a scene with no
    /// transforms (every production frame until an effect draws), allocated
    /// once per renderer rather than per frame (ruling GX-S item 12).
    private let zeroTransformBuffer: any MTLBuffer
    /// The transform table the last encode bound — read by
    /// `aSceneWithoutTransformsReusesOneZeroRecord` to pin that the zero
    /// record is not reallocated per frame.
    private(set) var lastBoundTransformBuffer: (any MTLBuffer)?

    /// The GPU copy of a ``MetalUIText/GlyphAtlas``, maintained by
    /// ``upload(_:)``. `nil` until the first upload; a scene carrying glyphs is
    /// then drawn against whatever was uploaded last.
    private(set) var atlasTexture: (any MTLTexture)?

    /// Whether ``atlasTexture`` has been bound into a render command encoder
    /// since it was created.
    ///
    /// **This exists to keep `upload(_:)` from writing to a texture the GPU may
    /// still be reading**, and it is the whole of that guarantee. `Window`
    /// commits a frame's command buffer and does not wait; there is no
    /// semaphore on the live path. So on the next frame, a `texture.replace`
    /// into the same object races the previous frame's sampling of it — and the
    /// atlas is the *only* place that could happen, every other GPU resource
    /// `encode` touches being a fresh per-frame `makeBuffer`.
    ///
    /// The invariant this buys: **a texture is written only while this is
    /// `false`** — that is, only before any command buffer references it. Once
    /// encoded, the object is immutable for the rest of its life and a dirty
    /// upload allocates a replacement instead. The old one stays alive as long
    /// as the in-flight buffer retains it, which is Metal's job and not ours.
    ///
    /// Conservative on purpose: set when the texture is *bound*, not when a
    /// glyph is actually drawn from it. `encodeGlyphs` only runs on a non-empty
    /// glyph array, so the two coincide today; binding is the property that
    /// stays true if that changes.
    private var atlasTextureWasEncoded = false

    /// The GPU copy of each `ImageTexture` a recent scene drew (ruling TE-AF
    /// item 3), keyed by the object's identity **and holding the object**, so
    /// the identifier cannot be reused by a new bitmap while the entry lives.
    /// Uploaded on first sight into a fresh texture that no command buffer has
    /// referenced — so, unlike the atlas, nothing here is ever written while
    /// the GPU may read it — and dropped by ``prepareImageTextures(for:)`` as
    /// soon as a scene stops referencing it: an image stream (a new bitmap
    /// every frame) must not accumulate the way the grow-only atlas does. A
    /// dropped texture an in-flight command buffer still reads stays alive
    /// through that buffer's own retain, which is Metal's job.
    private var imageTextures: [ObjectIdentifier: (source: ImageTexture, gpu: any MTLTexture)] = [:]

    /// How many image textures have been uploaded to the GPU, ever. Test
    /// support for the cache (`TE-AF` item 3).
    private(set) var imageTextureUploadCount = 0

    /// The `ImageTexture` identities with a GPU copy cached right now.
    var cachedImageTextureIdentities: Set<ObjectIdentifier> { Set(imageTextures.keys) }

    /// A renderer on `device`; throws if the queue, shader library or a
    /// pipeline cannot be created.
    public init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.commandQueue = queue

        let library = try ShaderLibrary.make(device: device)
        self.library = library

        /// Both pipelines are premultiplied source-over into the same
        /// gamma-encoded target, and they must stay identical in that respect:
        /// a glyph is composited over the rect behind it by the hardware, so
        /// two different blend configurations would make text's edges depend on
        /// what it was drawn over.
        func makePipeline(vertex: String, fragment: String) throws
            -> any MTLRenderPipelineState {
            guard let vertexFn = library.makeFunction(name: vertex) else {
                throw RendererError.functionMissing(vertex)
            }
            guard let fragmentFn = library.makeFunction(name: fragment) else {
                throw RendererError.functionMissing(fragment)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Self.pixelFormat
            // Premultiplied source-over, matching the shaders' premultiplied output.
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        self.rectPipeline = try makePipeline(vertex: "rect_vertex", fragment: "rect_fragment")
        self.glyphPipeline = try makePipeline(vertex: "glyph_vertex", fragment: "glyph_fragment")
        self.imagePipeline = try makePipeline(vertex: "image_vertex", fragment: "image_fragment")

        // Unit quad as a triangle strip: 4 vertices, no index buffer.
        var unitVertices: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        guard let buffer = device.makeBuffer(
            bytes: &unitVertices,
            length: MemoryLayout<SIMD2<Float>>.stride * unitVertices.count,
            options: .storageModeShared
        ) else { throw RendererError.bufferAllocationFailed }
        self.unitVertexBuffer = buffer
        guard let zero = device.makeBuffer(length: MemoryLayout<MUITransform>.stride,
                                           options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        self.zeroTransformBuffer = zero
    }

    /// Encode one view's worth of the scene into an existing command buffer,
    /// with no app-owned surface targets: every `.surface` run draws nothing.
    public func encode(_ scene: Scene,
                       view: SurfaceView,
                       in commandBuffer: any MTLCommandBuffer) throws {
        try encode(scene, view: view, in: commandBuffer, surfaces: [:])
    }

    /// Encode one view's worth of the scene into an existing command buffer,
    /// binding each `.surface` run's render target from `surfaces` (MetalView,
    /// rulings `MV-C` item 2, `MV-D`): a surface run is drawn by the **image
    /// pipeline** — its quads are `MUIImage` records, masked, faded and
    /// composited premultiplied exactly as an image's — with its target as the
    /// texture. A run whose target has no texture in `surfaces` draws nothing
    /// (a renderer handed a headless `renderFrame` scene, `MV-H` item 5).
    /// `MetalWindowRenderer.finishFrame` passes its per-window table's
    /// textures, after the app's draws.
    public func encode(_ scene: Scene,
                       view: SurfaceView,
                       in commandBuffer: any MTLCommandBuffer,
                       surfaces: [SurfaceID: any MTLTexture]) throws {
        try encode(scene, view: view, in: commandBuffer, surfaces: surfaces, backdropState: nil)
    }

    /// ``encode(_:view:in:surfaces:)`` with the window's own backdrop state
    /// (`nil`: the renderer's default). **A scene with no backdrop record is
    /// encoded by the old single pass into `view`, byte for byte** (`BB-C`);
    /// one with backdrops renders into the state's frame target in segments
    /// and copies it to `view` (``encodeWithBackdrops``).
    func encode(_ scene: Scene,
                view: SurfaceView,
                in commandBuffer: any MTLCommandBuffer,
                surfaces: [SurfaceID: any MTLTexture],
                backdropState: BackdropFrameState?) throws {
        lastBackdropSplits = 0; lastBackdropBlurs = 0; lastBackdropPasses = 0
        lastFrameTargetCopies = 0; lastBackdropTexturesMade = 0
        let state = backdropState ?? defaultBackdropState
        let wantsBackdrops = !scene.isEmpty
            && (!scene.backdrops.isEmpty || routesEveryFrameThroughTheFrameTarget)
        // A projection, a rasterization rate map or a drawable of another
        // format cannot be copied texel for texel: the flat tint (`BB-I`).
        let copyable = view.rasterizationRateMap == nil
            && simd_equal(view.projection, matrix_identity_float4x4)
            && view.colorTexture.pixelFormat == Self.pixelFormat
        if wantsBackdrops, copyable,
           try encodeWithBackdrops(scene, view: view, in: commandBuffer, surfaces: surfaces, state: state) {
            return
        }
        if !wantsBackdrops { state.releaseAll() }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = view.colorTexture
        // RESTRICTION: clearing per view means `encode` cannot be called twice
        // into one texture — the second call erases the first. Spec 3.2's claim
        // that a stereo backend is additive "without the renderer changing"
        // therefore holds only for a two-separate-textures layout. A
        // side-by-side single-texture, two-viewports layout would lose eye 0 to
        // eye 1's clear, and needs a load action the caller can choose.
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // A nil map is a no-op; a stereo backend supplies a real one (spec 3.2).
        pass.rasterizationRateMap = view.rasterizationRateMap

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw RendererError.encoderUnavailable
        }
        defer { encoder.endEncoding() }

        // Before the empty-scene return, so a scene with no images releases
        // every cached texture too.
        let imageTextures = try prepareImageTextures(for: scene)

        guard !scene.isEmpty else { return }
        // **A scene with primitives and no draw list was never finalized.**
        // `finalize()` is what builds `drawList`, and the loop at the foot of
        // this method iterates it — so an unfinalized non-empty scene would
        // encode zero draw calls and paint nothing, silently. Before the draw
        // list existed a forgotten `finalize()` merely left the primitives
        // unsorted; now it is a blank frame, which is a far quieter failure
        // and a public entry point away (`Window` always goes through
        // `Frame.finalizedScene()`, so production cannot reach this).
        precondition(!scene.drawList.isEmpty,
                     "Renderer.encode: the scene holds primitives but its draw list is empty — call Scene.finalize() (or use Frame.finalizedScene()) before encoding, or this frame draws nothing at all.")

        encoder.setViewport(view.viewport)

        var viewport = MUISize(width: Float(view.viewport.width),
                               height: Float(view.viewport.height))
        // Passed through uninterpreted: the renderer never reads or composes it,
        // so a stereo backend's per-eye matrices work without a renderer change.
        var projection = view.projection

        let transformBuffer = try transformTable(for: scene)

        // **One draw per run, pipeline bound only when the kind changes.** This
        // is what makes a rect able to occlude text: before the draw list,
        // `encode` drew every rect and then every glyph regardless of `order`.
        // A run's `count` is always >= 1 (`Scene.finalize` never emits an empty
        // run), so `makeBuffer(bytes:length: 0)` is unreachable here.
        //
        // **Cost, unrecorded until now: `Array(scene.rects[...])` /
        // `Array(scene.glyphs[...])` below copy a fresh array per run.** Before
        // the draw list there were two slices a frame, full stop; now a scene
        // with N rows that alternate rect/glyph — the exact composition this
        // task exists to draw correctly — produces up to 2N runs and therefore
        // 2N array allocations plus 2N `MTLBuffer` allocations in
        // `encodeRects`/`encodeGlyphs`, scaling with how finely the two types
        // interleave in z-order rather than with primitive count. Spec §7.3
        // already names the mitigation: a z-order layout choice, not a change
        // here — the M5 node-graph editor keeps every wire beneath every node
        // body so the whole graph is two runs, and the same discipline (e.g. a
        // list painting all row backgrounds before all row text) keeps this
        // cheap for any caller that wants it to be. Not fixed here because it
        // is a real optimisation (slicing without copying, or batching by kind
        // with a per-instance kind tag) with its own design, not a comment's
        // worth of change.
        for run in scene.drawList {
            try encodeRun(run, of: scene, into: encoder, imageTextures: imageTextures, surfaces: surfaces,
                          viewport: &viewport, projection: &projection, transforms: transformBuffer)
        }
    }

    /// The scene's transform table bound beside every pipeline's records
    /// (ruling GX-F): an empty table binds one zero record, which index 0 —
    /// the only index a scene with no transforms holds — never reads.
    private func transformTable(for scene: Scene) throws -> any MTLBuffer {
        let transformBuffer: any MTLBuffer
        if scene.transforms.isEmpty {
            transformBuffer = zeroTransformBuffer
        } else {
            guard let table = device.makeBuffer(bytes: scene.transforms,
                                                length: MemoryLayout<MUITransform>.stride * scene.transforms.count,
                                                options: .storageModeShared) else {
                throw RendererError.bufferAllocationFailed
            }
            transformBuffer = table
        }
        lastBoundTransformBuffer = transformBuffer
        return transformBuffer
    }

    /// One run of the draw list. A `.backdrop` run reaching here (the old
    /// path: no frame target) draws the flat tint (`BB-I`).
    private func encodeRun(_ run: DrawRun, of scene: Scene,
                           into encoder: any MTLRenderCommandEncoder,
                           imageTextures: [any MTLTexture],
                           surfaces: [SurfaceID: any MTLTexture],
                           viewport: inout MUISize, projection: inout simd_float4x4,
                           transforms transformBuffer: any MTLBuffer) throws {
        switch run.kind {
        case .rect:
            try encodeRects(Array(scene.rects[run.start..<(run.start + run.count)]),
                            into: encoder, viewport: &viewport, projection: &projection,
                            transforms: transformBuffer)
        case .glyph:
            try encodeGlyphs(Array(scene.glyphs[run.start..<(run.start + run.count)]),
                             into: encoder, viewport: &viewport, projection: &projection,
                             transforms: transformBuffer)
        case .image:
            let images = Array(scene.images[run.start..<(run.start + run.count)])
            // One texture per run: `Scene.finalize` breaks a run where it changes.
            try encodeImages(images, texture: imageTextures[Int(images[0].texture)],
                             into: encoder, viewport: &viewport, projection: &projection,
                             transforms: transformBuffer)
        case .surface:
            let quads = Array(scene.surfaces[run.start..<(run.start + run.count)])
            // One target per run: `Scene.finalize` breaks a run where it
            // changes; each quad's `texture` indexes `surfaceTargets`.
            let target = scene.surfaceTargets[Int(quads[0].texture)]
            guard let texture = surfaces[target.id] else { return }
            try encodeImages(quads, texture: texture,
                             into: encoder, viewport: &viewport, projection: &projection,
                             transforms: transformBuffer)
        case .backdrop:
            try encodeRects(scene.backdrops[run.start..<(run.start + run.count)].map(flatTintRect),
                            into: encoder, viewport: &viewport, projection: &projection,
                            transforms: transformBuffer)
        }
    }

    private func backdropPipelines() throws -> BackdropPipelines {
        if let backdropPipelinesCache { return backdropPipelinesCache }
        let made = try BackdropPipelines(device: device, library: library)
        backdropPipelinesCache = made
        return made
    }

    /// The scene rendered into `state`'s frame target in segments, then copied
    /// to `view` (`BB-C`). Segment 0 clears transparent and draws up to the
    /// first backdrop run; at each `.backdrop` run the pass ends, every record
    /// of the run is blurred from the frame target (`BB-D`), and a new segment
    /// (`loadAction .load`) draws the run's quads and what follows. Returns
    /// `false`, having encoded nothing, when the frame target cannot be made
    /// (the caller draws the old path with flat tints, `BB-I`).
    private func encodeWithBackdrops(_ scene: Scene, view: SurfaceView,
                                     in commandBuffer: any MTLCommandBuffer,
                                     surfaces: [SurfaceID: any MTLTexture],
                                     state: BackdropFrameState) throws -> Bool {
        precondition(!scene.drawList.isEmpty,
                     "Renderer.encode: the scene holds primitives but its draw list is empty — call Scene.finalize() (or use Frame.finalizedScene()) before encoding, or this frame draws nothing at all.")
        let pipelines = try backdropPipelines()
        let imageTextures = try prepareImageTextures(for: scene)
        let width = view.colorTexture.width, height = view.colorTexture.height
        state.beginFrame()
        guard let frame = state.frameTarget(device: device, width: width, height: height) else {
            lastBackdropTexturesMade = state.texturesMade
            return false
        }
        func segment(load: MTLLoadAction) throws -> any MTLRenderCommandEncoder {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = frame
            pass.colorAttachments[0].loadAction = load
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                throw RendererError.encoderUnavailable
            }
            encoder.setViewport(view.viewport)
            return encoder
        }
        var viewport = MUISize(width: Float(view.viewport.width), height: Float(view.viewport.height))
        var projection = view.projection
        let transformBuffer = try transformTable(for: scene)

        var encoder = try segment(load: .clear)
        for run in scene.drawList {
            guard run.kind == .backdrop else {
                try encodeRun(run, of: scene, into: encoder, imageTextures: imageTextures, surfaces: surfaces,
                              viewport: &viewport, projection: &projection, transforms: transformBuffer)
                continue
            }
            encoder.endEncoding()
            lastBackdropSplits += 1
            // Every record of the run reads the frame as it stands at the split
            // (a run holds no two overlapping records, `BB-E`).
            var blurred: [(texture: (any MTLTexture)?, draw: SIMD4<Float>)] = []
            for index in run.start..<(run.start + run.count) {
                blurred.append(try blur(record: index, of: scene, from: frame, width: width, height: height,
                                        commandBuffer: commandBuffer, pipelines: pipelines, state: state))
            }
            encoder = try segment(load: .load)
            for (k, index) in (run.start..<(run.start + run.count)).enumerated() {
                encodeBackdrop(scene.backdrops[index], blurred: blurred[k].texture, draw: blurred[k].draw,
                               into: encoder, viewport: &viewport, projection: &projection,
                               transforms: transformBuffer, pipelines: pipelines)
                if let texture = blurred[k].texture { state.release(texture) }
            }
        }
        encoder.endEncoding()

        // The copy draw: `view` is never sampled and stays framebuffer-only.
        let copy = MTLRenderPassDescriptor()
        copy.colorAttachments[0].texture = view.colorTexture
        copy.colorAttachments[0].loadAction = .dontCare
        copy.colorAttachments[0].storeAction = .store
        guard let copyEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: copy) else {
            throw RendererError.encoderUnavailable
        }
        copyEncoder.setRenderPipelineState(pipelines.copy)
        copyEncoder.setFragmentTexture(frame, index: 0)
        copyEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        copyEncoder.endEncoding()
        lastFrameTargetCopies = 1

        state.endFrame()
        lastBackdropTexturesMade = state.texturesMade
        return true
    }

    /// Blurs backdrop `index`'s region of `frame` into a pool texture
    /// (`BB-D`): `L` downsamples, then a horizontal and a vertical Gaussian at
    /// level `L`. The texture and the quad's `(origin, uvScale)` constant
    /// (`BB-R`), or `nil` and a zero constant when the region is empty or a
    /// texture cannot be allocated (the quad then draws its flat tint).
    private func blur(record index: Int, of scene: Scene, from frame: any MTLTexture, width: Int, height: Int,
                      commandBuffer: any MTLCommandBuffer, pipelines: BackdropPipelines,
                      state: BackdropFrameState) throws -> (texture: (any MTLTexture)?, draw: SIMD4<Float>) {
        let none: (texture: (any MTLTexture)?, draw: SIMD4<Float>) = (nil, .zero)
        guard let region = scene.backdropRegion(index, target: (width, height)) else { return none }
        let sigma = scene.backdrops[index].sigma
        let levels = BackdropBlurReference.levels(sigma: sigma, maxLevel: Int(MUIBackdropBlurMaxLevel))

        var held: [any MTLTexture] = []
        func give(back all: [any MTLTexture]) { for texture in all { state.release(texture) } }
        func run(_ pipeline: any MTLRenderPipelineState, source: any MTLTexture, sourceOrigin: (Int, Int),
                 sourceSize: (Int, Int), target: any MTLTexture, sigma: Float, horizontal: Bool) throws {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                throw RendererError.encoderUnavailable
            }
            var constants = BackdropBlurPass(
                src: SIMD4(Int32(sourceOrigin.0), Int32(sourceOrigin.1), Int32(sourceSize.0), Int32(sourceSize.1)),
                sigma: sigma, horizontal: horizontal ? 1 : 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&constants, length: MemoryLayout<BackdropBlurPass>.stride, index: 0)
            encoder.setFragmentTexture(source, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            lastBackdropPasses += 1
        }

        var source = frame
        var origin = (region.x, region.y)
        var (w, h) = (region.width, region.height)
        for _ in 0..<levels {
            let (nw, nh) = ((w + 1) / 2, (h + 1) / 2)
            guard let level = state.acquire(device: device, width: nw, height: nh, failing: backdropPoolFailsAllocation) else {
                give(back: held); return none
            }
            held.append(level)
            try run(pipelines.downsample, source: source, sourceOrigin: origin, sourceSize: (w, h),
                    target: level, sigma: 0, horizontal: false)
            source = level; origin = (0, 0); (w, h) = (nw, nh)
        }
        guard let scratch = state.acquire(device: device, width: w, height: h, failing: backdropPoolFailsAllocation) else {
            give(back: held); return none
        }
        held.append(scratch)
        guard let result = state.acquire(device: device, width: w, height: h, failing: backdropPoolFailsAllocation) else {
            give(back: held); return none
        }
        let levelSigma = sigma / Float(1 << levels)
        try run(pipelines.gaussian, source: source, sourceOrigin: origin, sourceSize: (w, h),
                target: scratch, sigma: levelSigma, horizontal: true)
        try run(pipelines.gaussian, source: scratch, sourceOrigin: (0, 0), sourceSize: (w, h),
                target: result, sigma: levelSigma, horizontal: false)
        give(back: held)
        lastBackdropBlurs += 1
        let scale = Float(1 << levels)
        return (result, SIMD4(Float(region.x), Float(region.y), 1 / (Float(w) * scale), 1 / (Float(h) * scale)))
    }

    /// One backdrop quad: the blurred pipeline with its texture and
    /// constants, or the flat one when `blurred` is `nil`. The record travels
    /// by `setVertexBytes`/`setFragmentBytes` (96 bytes), so no alignment of a
    /// shared buffer's offset is assumed.
    private func encodeBackdrop(_ record: MUIBackdrop, blurred: (any MTLTexture)?, draw: SIMD4<Float>,
                                into encoder: any MTLRenderCommandEncoder,
                                viewport: inout MUISize, projection: inout simd_float4x4,
                                transforms: any MTLBuffer, pipelines: BackdropPipelines) {
        var record = record
        var draw = draw
        encoder.setRenderPipelineState(blurred == nil ? pipelines.flat : pipelines.blurred)
        encoder.setVertexBuffer(unitVertexBuffer, offset: 0, index: Int(MUIRectBufferVertices.rawValue))
        encoder.setVertexBytes(&record, length: MemoryLayout<MUIBackdrop>.stride, index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride, index: Int(MUIRectBufferViewport.rawValue))
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride, index: Int(MUIRectBufferProjection.rawValue))
        encoder.setFragmentBytes(&record, length: MemoryLayout<MUIBackdrop>.stride, index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBuffer(transforms, offset: 0, index: Int(MUIRectBufferTransforms.rawValue))
        encoder.setFragmentBuffer(transforms, offset: 0, index: Int(MUIRectBufferTransforms.rawValue))
        if let blurred {
            encoder.setFragmentBytes(&draw, length: MemoryLayout<SIMD4<Float>>.stride, index: BackdropPipelines.drawConstantsIndex)
            encoder.setFragmentTexture(blurred, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
    }

    private func encodeRects(_ rects: [MUIRect],
                             into encoder: any MTLRenderCommandEncoder,
                             viewport: inout MUISize,
                             projection: inout simd_float4x4,
                             transforms: any MTLBuffer) throws {
        encoder.setRenderPipelineState(rectPipeline)

        // The rect array goes through an `MTLBuffer`, not `setVertexBytes`.
        //
        // **The M0 note this replaces was wrong in both of its numbers, and the
        // correction is the useful part.** It said `setVertexBytes` copies into
        // a 4 KB inline buffer, so "anything past roughly 39 rects is silently
        // truncated — the draw would read garbage rather than fail". Measured on
        // this hardware, with the mutation applied and the count swept: **314
        // rects (32,656 bytes) render correctly and 315 (32,760) abort the
        // process** with a Metal API-validation failure. So the ceiling is an
        // order of magnitude higher than 4 KB, and crossing it is a SIGABRT, not
        // a silent short read. Nothing in the repo had ever run the sweep.
        //
        // Both halves still argue for the buffer: the ceiling is real, it is
        // device-dependent rather than a documented constant, and 315 rects is
        // an ordinary list. The consequence of the correction is that a guard
        // *below* the ceiling proves nothing — `manyRectsAllReachTheGPU` draws
        // 400 for exactly that reason.
        //
        // A fresh buffer per encode rather than one retained and reused: the GPU
        // reads a buffer for as long as its command buffer is in flight, so a
        // reused one would need a ring and a fence to avoid overwriting the
        // frame still being drawn. `MTLCommandBuffer` retains what is bound to
        // it, so this one lives exactly as long as it is read. Pooling is an
        // optimisation for whoever measures the allocation, not a correctness
        // fix.
        let rectsLength = MemoryLayout<MUIRect>.stride * rects.count
        guard let rectBuffer = device.makeBuffer(bytes: rects,
                                                 length: rectsLength,
                                                 options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }

        encoder.setVertexBuffer(unitVertexBuffer, offset: 0,
                                index: Int(MUIRectBufferVertices.rawValue))
        encoder.setVertexBuffer(rectBuffer, offset: 0,
                                index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride,
                               index: Int(MUIRectBufferViewport.rawValue))
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride,
                               index: Int(MUIRectBufferProjection.rawValue))
        encoder.setFragmentBuffer(rectBuffer, offset: 0,
                                  index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBuffer(transforms, offset: 0, index: Int(MUIRectBufferTransforms.rawValue))
        encoder.setFragmentBuffer(transforms, offset: 0, index: Int(MUIRectBufferTransforms.rawValue))

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: rects.count)
    }

    /// Encodes the glyph sprites. **Silently draws nothing when no atlas has
    /// been uploaded**, which is the one branch here that cannot raise an error:
    /// the texture is per-renderer state rather than per-scene data, so a caller
    /// that forgot ``upload(_:)`` has produced a scene the renderer cannot draw
    /// but that is not itself malformed. It is not a throw because that would
    /// make the *first* frame of a window with text fail outright if the paint
    /// pass emitted glyphs before the atlas reached the renderer, and blank text
    /// for one frame is recoverable where a thrown frame is not.
    private func encodeGlyphs(_ glyphs: [MUIGlyph],
                              into encoder: any MTLRenderCommandEncoder,
                              viewport: inout MUISize,
                              projection: inout simd_float4x4,
                              transforms: any MTLBuffer) throws {
        guard let atlasTexture else { return }

        encoder.setRenderPipelineState(glyphPipeline)

        // A fresh buffer per encode, for the reason spelled out above.
        let glyphsLength = MemoryLayout<MUIGlyph>.stride * glyphs.count
        guard let glyphBuffer = device.makeBuffer(bytes: glyphs,
                                                  length: glyphsLength,
                                                  options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }

        encoder.setVertexBuffer(unitVertexBuffer, offset: 0,
                                index: Int(MUIGlyphBufferVertices.rawValue))
        encoder.setVertexBuffer(glyphBuffer, offset: 0,
                                index: Int(MUIGlyphBufferGlyphs.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride,
                               index: Int(MUIGlyphBufferViewport.rawValue))
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride,
                               index: Int(MUIGlyphBufferProjection.rawValue))
        encoder.setFragmentBuffer(glyphBuffer, offset: 0,
                                  index: Int(MUIGlyphBufferGlyphs.rawValue))
        encoder.setVertexBuffer(transforms, offset: 0, index: Int(MUIGlyphBufferTransforms.rawValue))
        encoder.setFragmentBuffer(transforms, offset: 0, index: Int(MUIGlyphBufferTransforms.rawValue))
        encoder.setFragmentTexture(atlasTexture,
                                   index: Int(MUIGlyphTextureAtlas.rawValue))
        // From here the GPU may read this texture at any time until the command
        // buffer completes, and nothing waits for that. See
        // ``atlasTextureWasEncoded``.
        atlasTextureWasEncoded = true

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: glyphs.count)
    }

    /// The GPU texture for each of `scene.textures`, in order, uploading the
    /// ones not cached and releasing every cached one the scene does not
    /// reference (see ``imageTextures``).
    private func prepareImageTextures(for scene: Scene) throws -> [any MTLTexture] {
        var kept: [ObjectIdentifier: (source: ImageTexture, gpu: any MTLTexture)] = [:]
        var result: [any MTLTexture] = []
        result.reserveCapacity(scene.textures.count)
        for source in scene.textures {
            let key = ObjectIdentifier(source)
            if let cached = imageTextures[key] ?? kept[key] {
                kept[key] = cached
                result.append(cached.gpu)
                continue
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: source.width, height: source.height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.bufferAllocationFailed
            }
            source.pixels.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, source.width, source.height),
                                mipmapLevel: 0, withBytes: bytes.baseAddress!,
                                bytesPerRow: source.width * 4)
            }
            imageTextureUploadCount += 1
            kept[key] = (source, texture)
            result.append(texture)
        }
        imageTextures = kept
        return result
    }

    private func encodeImages(_ images: [MUIImage],
                              texture: any MTLTexture,
                              into encoder: any MTLRenderCommandEncoder,
                              viewport: inout MUISize,
                              projection: inout simd_float4x4,
                              transforms: any MTLBuffer) throws {
        encoder.setRenderPipelineState(imagePipeline)
        // A fresh buffer per encode, for the reason `encodeRects` spells out.
        guard let buffer = device.makeBuffer(bytes: images,
                                             length: MemoryLayout<MUIImage>.stride * images.count,
                                             options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        encoder.setVertexBuffer(unitVertexBuffer, offset: 0,
                                index: Int(MUIImageBufferVertices.rawValue))
        encoder.setVertexBuffer(buffer, offset: 0, index: Int(MUIImageBufferImages.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride,
                               index: Int(MUIImageBufferViewport.rawValue))
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride,
                               index: Int(MUIImageBufferProjection.rawValue))
        encoder.setFragmentBuffer(buffer, offset: 0, index: Int(MUIImageBufferImages.rawValue))
        encoder.setVertexBuffer(transforms, offset: 0, index: Int(MUIImageBufferTransforms.rawValue))
        encoder.setFragmentBuffer(transforms, offset: 0, index: Int(MUIImageBufferTransforms.rawValue))
        encoder.setFragmentTexture(texture, index: Int(MUIImageTextureImage.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: images.count)
    }

    /// Brings the GPU's copy of `atlas` up to date, and clears the atlas's dirty
    /// rect because this is the consumer it exists for.
    ///
    /// **Must run before ``encode(_:view:in:)`` of any scene whose `AtlasSlot`s
    /// came from a newly packed glyph**, and it is the caller's job to sequence
    /// that: the renderer cannot tell a slot it has uploaded from one it has
    /// not. The `GlyphAtlas` is the authority on which pixels changed, and it
    /// tracks that across an arbitrary number of `slot(for:)` calls, so uploading
    /// once per frame after scene construction is the intended shape.
    ///
    /// Two cases, and the second is the one that is easy to get wrong:
    ///
    /// - **The texture already matches the atlas's dimensions.** Only
    ///   `dirtyRect` is copied; `nil` means nothing was written and the call is
    ///   a no-op.
    /// - **There is no texture, or it is the wrong size.** A fresh
    ///   `MTLTexture`'s contents are undefined, so the *whole* atlas is copied,
    ///   `dirtyRect` notwithstanding — every previously packed glyph is clean
    ///   from the atlas's point of view and absent from the GPU's. A dirty-rect
    ///   upload here would leave every earlier glyph blank, which is the
    ///   intermittent-blank-run failure spec 4.2 names and nothing in this repo
    ///   can see.
    public func upload(_ atlas: GlyphAtlas) {
        let existing = atlasTexture
        let sizeChanged = existing == nil
            || existing!.width != atlas.width
            || existing!.height != atlas.height
        // **A texture that has been encoded is immutable from here on.** See
        // ``atlasTextureWasEncoded``: writing into it would race the in-flight
        // frame that bound it. Note the `dirtyRect != nil` conjunct — without
        // it, a steady-state frame with nothing to upload would allocate a whole
        // atlas every time, which is the churn this formulation avoids.
        let wouldMutateAnEncodedTexture = atlasTextureWasEncoded
            && atlas.dirtyRect != nil
        let needsFullUpload = sizeChanged || wouldMutateAnEncodedTexture

        let texture: any MTLTexture
        if needsFullUpload {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Self.atlasPixelFormat,
                width: atlas.width, height: atlas.height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let made = device.makeTexture(descriptor: descriptor) else {
                // Nothing to recover to: leaving the previous texture bound
                // would paint the wrong glyphs from a stale atlas, and there is
                // no smaller correct answer than "no text this frame".
                atlasTexture = nil
                atlasTextureWasEncoded = false
                return
            }
            texture = made
            // Never bound; safe to write for exactly as long as that holds.
            atlasTextureWasEncoded = false
        } else {
            texture = existing!
        }

        let region: (x: Int, y: Int, width: Int, height: Int)
        if needsFullUpload {
            region = (0, 0, atlas.width, atlas.height)
        } else if let dirty = atlas.dirtyRect {
            region = dirty
        } else {
            atlasTexture = texture
            return
        }

        // **`texture` is unencoded here, and that is a precondition rather than
        // a coincidence** — `needsFullUpload` made a fresh one if the existing
        // one had ever been bound. Writing to an encoded texture would race the
        // frame still sampling it (``atlasTextureWasEncoded``).
        atlas.pixels.withUnsafeBufferPointer { buffer in
            // `bytesPerRow` stays the ATLAS's width, not the region's: the
            // source rows are slices of a wider bitmap, and Metal walks them by
            // this stride. Passing the region's width would read a diagonal
            // smear out of the atlas.
            let base = buffer.baseAddress! + (region.y * atlas.width + region.x)
            texture.replace(
                region: MTLRegionMake2D(region.x, region.y, region.width, region.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: atlas.width)
        }

        atlas.clearDirtyRect()
        atlasTexture = texture
    }

    /// Render to an offscreen texture and read the pixels back. Test support.
    public func renderOffscreen(_ scene: Scene,
                                size: Size<DevicePixels>,
                                projection: simd_float4x4 = matrix_identity_float4x4
    ) throws -> [UInt8] {
        try renderOffscreen(scene, size: size, surfaces: [:], projection: projection)
    }

    /// Render to an offscreen texture, binding each `.surface` run's target
    /// from `surfaces` (``encode(_:view:in:surfaces:)``), and read the pixels
    /// back. Test support (MetalView, test 2.11).
    public func renderOffscreen(_ scene: Scene,
                                size: Size<DevicePixels>,
                                surfaces: [SurfaceID: any MTLTexture],
                                projection: simd_float4x4 = matrix_identity_float4x4
    ) throws -> [UInt8] {
        let width = Int(size.width.value)
        let height = Int(size.height.value)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.bufferAllocationFailed
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.encoderUnavailable
        }

        let view = SurfaceView(
            colorTexture: texture,
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(width), height: Double(height),
                                  znear: 0, zfar: 1),
            projection: projection)
        try encode(scene, view: view, in: commandBuffer, surfaces: surfaces)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height),
                             mipmapLevel: 0)
        }
        return pixels
    }
}

/// The record's flat tint as a rect: `c * o * T` -- the fallback every renderer
/// draws for a backdrop it cannot blur (ruling BB-I), which is today's
/// `LK-L` flat tint pixel for pixel.
private func flatTintRect(_ b: MUIBackdrop) -> MUIRect {
    var tint = b.tint
    tint.a *= b.opacity
    return MUIRect(bounds: b.bounds, contentMask: b.contentMask, maskCornerRadii: b.maskCornerRadii,
                   background: tint, borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: b.cornerRadii,
                   borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: b.order, shape: b.shape)
}
