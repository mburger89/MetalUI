import Metal
import MetalUICore
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

        // The scene's transform table (ruling GX-F), bound beside every
        // pipeline's records for vertex and fragment. An empty table binds
        // one zero record, which index 0 — the only index a scene with no
        // transforms holds — never reads.
        let transformBuffer: any MTLBuffer
        if scene.transforms.isEmpty {
            guard let dummy = device.makeBuffer(length: MemoryLayout<MUITransform>.stride,
                                                options: .storageModeShared) else {
                throw RendererError.bufferAllocationFailed
            }
            transformBuffer = dummy
        } else {
            guard let table = device.makeBuffer(bytes: scene.transforms,
                                                length: MemoryLayout<MUITransform>.stride * scene.transforms.count,
                                                options: .storageModeShared) else {
                throw RendererError.bufferAllocationFailed
            }
            transformBuffer = table
        }

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
                guard let texture = surfaces[target.id] else { continue }
                try encodeImages(quads, texture: texture,
                                 into: encoder, viewport: &viewport, projection: &projection,
                                 transforms: transformBuffer)
            }
        }
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
