import Metal
import MetalUIShaderTypes

/// The constants one blur pass reads (`BackdropBlurPass` in `shaders.metal`):
/// the source rectangle in the source texture, the Gaussian's σ at this level
/// and its axis. 32 bytes: an `int4` aligns the struct to 16.
struct BackdropBlurPass {
    var src: SIMD4<Int32>
    var sigma: Float
    var horizontal: Int32
}

/// The pipelines of a material's backdrop (rulings `BB-A`, `BB-D`, `BB-S`): the
/// blur passes, the blurred quad, its flat-tint fallback (`BB-I`) and the copy
/// of the frame target to the drawable (`BB-C`). The pass pipelines write
/// without blending; the two quad pipelines composite premultiplied
/// source-over exactly as the rect pipeline does.
@MainActor
final class BackdropPipelines {
    /// The fragment buffer index of a blurred quad's `(origin, uvScale)` constant.
    static let drawConstantsIndex = 5

    let downsample: any MTLRenderPipelineState
    let gaussian: any MTLRenderPipelineState
    let copy: any MTLRenderPipelineState
    let blurred: any MTLRenderPipelineState
    let flat: any MTLRenderPipelineState

    init(device: any MTLDevice, library: any MTLLibrary) throws {
        func make(vertex: String, fragment: String, blend: Bool) throws -> any MTLRenderPipelineState {
            guard let vertexFn = library.makeFunction(name: vertex) else { throw RendererError.functionMissing(vertex) }
            guard let fragmentFn = library.makeFunction(name: fragment) else { throw RendererError.functionMissing(fragment) }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Renderer.pixelFormat
            if blend {
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        downsample = try make(vertex: "backdrop_pass_vertex", fragment: "backdrop_downsample_fragment", blend: false)
        gaussian = try make(vertex: "backdrop_pass_vertex", fragment: "backdrop_gaussian_fragment", blend: false)
        copy = try make(vertex: "backdrop_pass_vertex", fragment: "backdrop_copy_fragment", blend: false)
        blurred = try make(vertex: "backdrop_vertex", fragment: "backdrop_fragment", blend: true)
        flat = try make(vertex: "backdrop_vertex", fragment: "backdrop_flat_fragment", blend: true)
    }
}

/// One window's backdrop resources (spec 3.2, `BB-C`, `BB-K`): the frame
/// target a backdrop frame renders into, and the pool of blur textures. Per
/// window, not on the shared ``Renderer`` (a copy per window, as the surface
/// table is), `bgra8Unorm` — never `_sRGB`, §7.8 — render target + shader
/// read, private.
///
/// **The pool is a free list by size.** `acquire` hands out a free texture of
/// the size or makes one (counted in ``texturesMade``); `release` returns it.
/// Reuse inside one command buffer is safe because Metal orders tracked
/// resources by encoding order. A steady frame acquires exactly what the last
/// one released, so it makes none; a size no frame acquired is dropped at the
/// frame's end, and a frame with no backdrop at all drops everything
/// (``releaseAll()``, `BB-S`).
@MainActor
final class BackdropFrameState {
    private struct Key: Hashable { var width: Int; var height: Int }

    private var frame: (any MTLTexture)?
    private var free: [Key: [any MTLTexture]] = [:]
    private var usedThisFrame: Set<Key> = []
    /// Textures made since the last ``beginFrame()``.
    private(set) var texturesMade = 0

    /// Whether a frame target exists.
    var hasFrameTarget: Bool { frame != nil }

    func beginFrame() {
        texturesMade = 0
        usedThisFrame.removeAll(keepingCapacity: true)
    }

    private static func makeTexture(_ device: any MTLDevice, width: Int, height: Int) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: min(width, 16384), height: min(height, 16384), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// The frame target at `width × height`, replaced on a size change; `nil`
    /// when it cannot be made.
    func frameTarget(device: any MTLDevice, width: Int, height: Int) -> (any MTLTexture)? {
        if let frame, frame.width == width, frame.height == height { return frame }
        frame = nil
        guard let made = Self.makeTexture(device, width: width, height: height) else { return nil }
        texturesMade += 1
        frame = made
        return made
    }

    /// A blur texture of `width × height`, or `nil` when it cannot be made (or
    /// `failing`, the test hook of test 2.7).
    func acquire(device: any MTLDevice, width: Int, height: Int, failing: Bool) -> (any MTLTexture)? {
        if failing { return nil }
        let key = Key(width: width, height: height)
        usedThisFrame.insert(key)
        if let texture = free[key]?.popLast() { return texture }
        guard let made = Self.makeTexture(device, width: width, height: height) else { return nil }
        texturesMade += 1
        return made
    }

    func release(_ texture: any MTLTexture) {
        free[Key(width: texture.width, height: texture.height), default: []].append(texture)
    }

    /// Drops the free textures of every size this frame did not acquire.
    func endFrame() {
        for key in free.keys where !usedThisFrame.contains(key) { free[key] = nil }
    }

    /// Drops the frame target and the pool (a frame with no backdrop).
    func releaseAll() {
        frame = nil
        free.removeAll()
    }
}
