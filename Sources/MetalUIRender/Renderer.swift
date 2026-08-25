import Metal
import MetalUICore
import MetalUIShaderTypes
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

    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue

    private let rectPipeline: any MTLRenderPipelineState
    private let unitVertexBuffer: any MTLBuffer

    public init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.commandQueue = queue

        let library = try ShaderLibrary.make(device: device)
        guard let vertexFn = library.makeFunction(name: "rect_vertex") else {
            throw RendererError.functionMissing("rect_vertex")
        }
        guard let fragmentFn = library.makeFunction(name: "rect_fragment") else {
            throw RendererError.functionMissing("rect_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = Self.pixelFormat
        // Premultiplied source-over, matching the shader's premultiplied output.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.rectPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

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
        encoder.setRenderPipelineState(rectPipeline)

        var viewport = MUISize(width: Float(view.viewport.width),
                               height: Float(view.viewport.height))
        // Passed through uninterpreted: the renderer never reads or composes it,
        // so a stereo backend's per-eye matrices work without a renderer change.
        var projection = view.projection

        // NOTE (M0 limitation): `setVertexBytes`/`setFragmentBytes` copy into a
        // 4 KB inline argument buffer. `MUIRect` is 104 bytes, so anything past
        // roughly 39 rects is silently truncated — the draw would read garbage
        // rather than fail. M0 draws one rect, so this holds; Milestone 1 must
        // move the rect array to an `MTLBuffer` before scenes grow.
        encoder.setVertexBuffer(unitVertexBuffer, offset: 0,
                                index: Int(MUIRectBufferVertices.rawValue))
        encoder.setVertexBytes(scene.rects,
                               length: MemoryLayout<MUIRect>.stride * scene.rects.count,
                               index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride,
                               index: Int(MUIRectBufferViewport.rawValue))
        encoder.setVertexBytes(&projection, length: MemoryLayout<simd_float4x4>.stride,
                               index: Int(MUIRectBufferProjection.rawValue))
        encoder.setFragmentBytes(scene.rects,
                                 length: MemoryLayout<MUIRect>.stride * scene.rects.count,
                                 index: Int(MUIRectBufferRects.rawValue))

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: scene.rects.count)
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
