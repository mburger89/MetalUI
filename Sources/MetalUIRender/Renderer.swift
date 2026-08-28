import Metal
import MetalUICore
import MetalUIShaderTypes
import MetalUIText
import simd

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

    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue

    private let rectPipeline: any MTLRenderPipelineState
    private let glyphPipeline: any MTLRenderPipelineState
    private let unitVertexBuffer: any MTLBuffer

    /// The GPU copy of a ``MetalUIText/GlyphAtlas``, maintained by
    /// ``upload(_:)``. `nil` until the first upload; a scene carrying glyphs is
    /// then drawn against whatever was uploaded last.
    private(set) var atlasTexture: (any MTLTexture)?

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

    /// Encode one view's worth of the scene into an existing command buffer.
    public func encode(_ scene: Scene,
                       view: SurfaceView,
                       in commandBuffer: any MTLCommandBuffer) throws {
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

        guard !scene.isEmpty else { return }

        encoder.setViewport(view.viewport)

        var viewport = MUISize(width: Float(view.viewport.width),
                               height: Float(view.viewport.height))
        // Passed through uninterpreted: the renderer never reads or composes it,
        // so a stereo backend's per-eye matrices work without a renderer change.
        var projection = view.projection

        // Each pipeline is guarded by its own array being non-empty, not by
        // `scene.isEmpty`. A glyph-only scene reaches here — a `Text` with no
        // background is an ordinary element — and `makeBuffer(bytes:length: 0)`
        // returns nil, so an unguarded rect encode would throw
        // `bufferAllocationFailed` on a scene that is perfectly well formed.
        if !scene.rects.isEmpty {
            try encodeRects(scene.rects, into: encoder,
                            viewport: &viewport, projection: &projection)
        }
        // After every rect, whatever the orders say — see `Scene.finalize`.
        if !scene.glyphs.isEmpty {
            try encodeGlyphs(scene.glyphs, into: encoder,
                             viewport: &viewport, projection: &projection)
        }
    }

    private func encodeRects(_ rects: [MUIRect],
                             into encoder: any MTLRenderCommandEncoder,
                             viewport: inout MUISize,
                             projection: inout simd_float4x4) throws {
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
                              projection: inout simd_float4x4) throws {
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
        encoder.setFragmentTexture(atlasTexture,
                                   index: Int(MUIGlyphTextureAtlas.rawValue))

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: glyphs.count)
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
        let needsFullUpload = existing == nil
            || existing!.width != atlas.width
            || existing!.height != atlas.height

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
                return
            }
            texture = made
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

        // **`replace` mutates a texture a previous frame may still be reading.**
        // See the hazard note at the call site (`Window.drawFrameIfNeeded`): the
        // live path commits without waiting, and this is the only persistent
        // CPU-mutated GPU resource in the renderer. Nothing in this repo can
        // observe it, because the only other caller (`renderOffscreen`) waits.
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
        try encode(scene, view: view, in: commandBuffer)
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
