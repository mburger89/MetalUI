// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

// Graphics into a texture or a surface target (ruling `GA-H`): samplers,
// pipelines built from library shaders, and render passes. Names follow
// SDL_GPU's, so SDL's documentation applies; every wrapper keeps `raw`.

/// Texture filtering (`SDL_GPUFilter`).
public enum SDLGPUFilter: Sendable {
    /// `SDL_GPU_FILTER_NEAREST`.
    case nearest
    /// `SDL_GPU_FILTER_LINEAR`.
    case linear
    var sdl: SDL_GPUFilter { self == .nearest ? SDL_GPU_FILTER_NEAREST : SDL_GPU_FILTER_LINEAR }
}

/// What ``SDLGPUDevice/makeSampler(_:)`` is asked for (`SDL_GPUSamplerCreateInfo`).
public struct SDLGPUSamplerDescription: Sendable {
    /// Filter when minifying.
    public var minFilter: SDLGPUFilter
    /// Filter when magnifying.
    public var magFilter: SDLGPUFilter
    /// Filter between mip levels (`SDL_GPUSamplerMipmapMode`).
    public var mipmapFilter: SDLGPUFilter
    /// `true` repeats the texture past its edge, `false` clamps to the edge.
    public var repeats: Bool
    /// The highest mip level sampled (`max_lod`).
    public var maxLevel: Float

    /// A clamping sampler of `filter` that reaches every mip level.
    public init(filter: SDLGPUFilter = .linear, mipmapFilter: SDLGPUFilter = .linear, repeats: Bool = false,
                maxLevel: Float = 1000) {
        minFilter = filter
        magFilter = filter
        self.mipmapFilter = mipmapFilter
        self.repeats = repeats
        self.maxLevel = maxLevel
    }
}

/// An `SDL_GPUSampler`, released with its last reference.
public final class SDLGPUSampler: @unchecked Sendable {
    /// The `SDL_GPUSampler *`.
    public let raw: OpaquePointer
    let device: SDLGPUDevice

    init(raw: OpaquePointer, device: SDLGPUDevice) {
        self.raw = raw
        self.device = device
    }

    deinit { device.release { SDL_ReleaseGPUSampler($0, raw) } }
}

/// The primitive topology of a pipeline (`SDL_GPUPrimitiveType`).
public enum SDLGPUPrimitiveType: Sendable {
    /// `SDL_GPU_PRIMITIVETYPE_TRIANGLELIST`.
    case triangleList
    /// `SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP`.
    case triangleStrip
    /// `SDL_GPU_PRIMITIVETYPE_LINELIST`.
    case lineList
    /// `SDL_GPU_PRIMITIVETYPE_POINTLIST`.
    case pointList

    var sdl: SDL_GPUPrimitiveType {
        switch self {
        case .triangleList: return SDL_GPU_PRIMITIVETYPE_TRIANGLELIST
        case .triangleStrip: return SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP
        case .lineList: return SDL_GPU_PRIMITIVETYPE_LINELIST
        case .pointList: return SDL_GPU_PRIMITIVETYPE_POINTLIST
        }
    }
}

/// Which faces a pipeline culls (`SDL_GPUCullMode`).
public enum SDLGPUCullMode: Sendable {
    /// `SDL_GPU_CULLMODE_NONE`.
    case none
    /// `SDL_GPU_CULLMODE_FRONT`.
    case front
    /// `SDL_GPU_CULLMODE_BACK`.
    case back

    var sdl: SDL_GPUCullMode {
        switch self {
        case .none: return SDL_GPU_CULLMODE_NONE
        case .front: return SDL_GPU_CULLMODE_FRONT
        case .back: return SDL_GPU_CULLMODE_BACK
        }
    }
}

/// The depth comparison (`SDL_GPUCompareOp`).
public enum SDLGPUCompareOp: Sendable {
    /// `SDL_GPU_COMPAREOP_LESS`: the nearer fragment wins.
    case less
    /// `SDL_GPU_COMPAREOP_LESS_OR_EQUAL`.
    case lessOrEqual
    /// `SDL_GPU_COMPAREOP_GREATER`.
    case greater
    /// `SDL_GPU_COMPAREOP_ALWAYS`: no test.
    case always

    var sdl: SDL_GPUCompareOp {
        switch self {
        case .less: return SDL_GPU_COMPAREOP_LESS
        case .lessOrEqual: return SDL_GPU_COMPAREOP_LESS_OR_EQUAL
        case .greater: return SDL_GPU_COMPAREOP_GREATER
        case .always: return SDL_GPU_COMPAREOP_ALWAYS
        }
    }
}

/// A pipeline's depth test, always against a ``SDLGPUTextureFormat/d32Float`` target.
public struct SDLGPUDepthState: Sendable {
    /// The comparison a fragment must pass.
    public var compare: SDLGPUCompareOp
    /// Whether a passing fragment writes its depth.
    public var write: Bool
    /// A depth test; `LESS` with writes is the usual one.
    public init(compare: SDLGPUCompareOp = .less, write: Bool = true) {
        self.compare = compare
        self.write = write
    }
}

/// How a pipeline blends into its colour target.
public enum SDLGPUBlend: Sendable {
    /// No blending: the fragment replaces the texel.
    case none
    /// Premultiplied source-over, `src + dst * (1 - src.a)`: what a `GPUSurface`'s
    /// target is composited as (`MV-D`).
    case premultipliedAlpha
}

/// The format of a vertex attribute (`SDL_GPUVertexElementFormat`).
public enum SDLGPUVertexFormat: Sendable {
    /// `SDL_GPU_VERTEXELEMENTFORMAT_FLOAT`.
    case float
    /// `SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2`.
    case float2
    /// `SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3`.
    case float3
    /// `SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4`.
    case float4

    var sdl: SDL_GPUVertexElementFormat {
        switch self {
        case .float: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT
        case .float2: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2
        case .float3: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3
        case .float4: return SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4
        }
    }
}

/// One vertex buffer slot (`SDL_GPUVertexBufferDescription`).
public struct SDLGPUVertexBufferDescription: Sendable {
    /// The slot ``SDLGPURenderPass/bindVertexBuffers(_:firstSlot:offsets:)`` binds.
    public var slot: Int
    /// Bytes from one element to the next.
    public var pitch: Int
    /// `true` advances per instance, `false` per vertex.
    public var perInstance: Bool
    /// A slot description; per vertex by default.
    public init(slot: Int, pitch: Int, perInstance: Bool = false) {
        self.slot = slot
        self.pitch = pitch
        self.perInstance = perInstance
    }
}

/// One vertex attribute (`SDL_GPUVertexAttribute`).
public struct SDLGPUVertexAttribute: Sendable {
    /// The shader's input location (`TEXCOORDn` in HLSL).
    public var location: Int
    /// The slot it is read from.
    public var bufferSlot: Int
    /// Its format.
    public var format: SDLGPUVertexFormat
    /// Byte offset inside the slot's element.
    public var offset: Int
    /// An attribute.
    public init(location: Int, bufferSlot: Int = 0, format: SDLGPUVertexFormat, offset: Int) {
        self.location = location
        self.bufferSlot = bufferSlot
        self.format = format
        self.offset = offset
    }
}

/// What ``SDLGPUDevice/makeGraphicsPipeline(_:)`` is asked for: the fields of
/// `SDL_GPUGraphicsPipelineCreateInfo` an app sets, with defaults for the rest
/// (one colour target, no depth, no blend, no cull, counter-clockwise front).
public struct SDLGPUGraphicsPipelineDescription: Sendable {
    /// The vertex stage from the shader library.
    public var vertex: SDLGPUShaderBlob
    /// The fragment stage from the shader library.
    public var fragment: SDLGPUShaderBlob
    /// Vertex buffer slots (none: the shader reads `SV_VertexID` or storage buffers).
    public var vertexBuffers: [SDLGPUVertexBufferDescription]
    /// Vertex attributes.
    public var vertexAttributes: [SDLGPUVertexAttribute]
    /// The topology.
    public var primitiveType: SDLGPUPrimitiveType
    /// Which faces are culled.
    public var cullMode: SDLGPUCullMode
    /// The colour target's format; `b8g8r8a8Unorm`, a surface target's.
    public var colorFormat: SDLGPUTextureFormat
    /// Blending into the colour target.
    public var blend: SDLGPUBlend
    /// The colour (and depth) target's sample count.
    public var sampleCount: SDLGPUSampleCount
    /// The depth test, or `nil` for a pipeline with no depth target.
    public var depth: SDLGPUDepthState?

    /// A description over two library stages.
    public init(vertex: SDLGPUShaderBlob, fragment: SDLGPUShaderBlob,
                vertexBuffers: [SDLGPUVertexBufferDescription] = [], vertexAttributes: [SDLGPUVertexAttribute] = [],
                primitiveType: SDLGPUPrimitiveType = .triangleList, cullMode: SDLGPUCullMode = .none,
                colorFormat: SDLGPUTextureFormat = .b8g8r8a8Unorm, blend: SDLGPUBlend = .none,
                sampleCount: SDLGPUSampleCount = .one, depth: SDLGPUDepthState? = nil) {
        self.vertex = vertex
        self.fragment = fragment
        self.vertexBuffers = vertexBuffers
        self.vertexAttributes = vertexAttributes
        self.primitiveType = primitiveType
        self.cullMode = cullMode
        self.colorFormat = colorFormat
        self.blend = blend
        self.sampleCount = sampleCount
        self.depth = depth
    }
}

/// An `SDL_GPUGraphicsPipeline`, released with its last reference.
public final class SDLGPUGraphicsPipeline: @unchecked Sendable {
    /// The `SDL_GPUGraphicsPipeline *`.
    public let raw: OpaquePointer
    /// What it was made from.
    public let description: SDLGPUGraphicsPipelineDescription
    let device: SDLGPUDevice

    init(raw: OpaquePointer, description: SDLGPUGraphicsPipelineDescription, device: SDLGPUDevice) {
        self.raw = raw
        self.description = description
        self.device = device
    }

    deinit { device.release { SDL_ReleaseGPUGraphicsPipeline($0, raw) } }
}

/// What a render pass does with a target's contents when it begins (`SDL_GPULoadOp`).
public enum SDLGPULoadOp: Sendable {
    /// `SDL_GPU_LOADOP_LOAD`: keep what is there.
    case load
    /// `SDL_GPU_LOADOP_CLEAR`.
    case clear
    /// `SDL_GPU_LOADOP_DONT_CARE`.
    case dontCare

    var sdl: SDL_GPULoadOp {
        switch self {
        case .load: return SDL_GPU_LOADOP_LOAD
        case .clear: return SDL_GPU_LOADOP_CLEAR
        case .dontCare: return SDL_GPU_LOADOP_DONT_CARE
        }
    }
}

/// What a render pass does with its results (`SDL_GPUStoreOp`).
public enum SDLGPUStoreOp: Sendable {
    /// `SDL_GPU_STOREOP_STORE`.
    case store
    /// `SDL_GPU_STOREOP_DONT_CARE`.
    case dontCare
    /// `SDL_GPU_STOREOP_RESOLVE`: resolve a multisample target into its
    /// ``SDLGPUColorAttachment/resolveTexture`` and discard the samples.
    case resolve
    /// `SDL_GPU_STOREOP_RESOLVE_AND_STORE`: resolve and keep the samples.
    case resolveAndStore

    var sdl: SDL_GPUStoreOp {
        switch self {
        case .store: return SDL_GPU_STOREOP_STORE
        case .dontCare: return SDL_GPU_STOREOP_DONT_CARE
        case .resolve: return SDL_GPU_STOREOP_RESOLVE
        case .resolveAndStore: return SDL_GPU_STOREOP_RESOLVE_AND_STORE
        }
    }
}

/// A render pass's colour target (`SDL_GPUColorTargetInfo`).
public struct SDLGPUColorAttachment {
    /// The target: an app texture, or a surface draw's ``SDLGPUFrameView/target``.
    public var texture: SDLGPUTexture
    /// What happens to its contents at the start; `clear` by default.
    public var loadOp: SDLGPULoadOp
    /// The clear colour, premultiplied for a surface target.
    public var clearColor: (red: Float, green: Float, blue: Float, alpha: Float)
    /// What happens to the results; `store` by default.
    public var storeOp: SDLGPUStoreOp
    /// The single-sample texture a `resolve` store writes (it may be a surface target).
    public var resolveTexture: SDLGPUTexture?

    /// A colour attachment.
    public init(texture: SDLGPUTexture, loadOp: SDLGPULoadOp = .clear,
                clearColor: (red: Float, green: Float, blue: Float, alpha: Float) = (0, 0, 0, 0),
                storeOp: SDLGPUStoreOp = .store, resolveTexture: SDLGPUTexture? = nil) {
        self.texture = texture
        self.loadOp = loadOp
        self.clearColor = clearColor
        self.storeOp = storeOp
        self.resolveTexture = resolveTexture
    }
}

/// A render pass's depth target (`SDL_GPUDepthStencilTargetInfo`, depth only).
public struct SDLGPUDepthAttachment {
    /// A ``SDLGPUTextureFormat/d32Float`` texture with the depth-target usage.
    public var texture: SDLGPUTexture
    /// What happens to its contents at the start; `clear` by default.
    public var loadOp: SDLGPULoadOp
    /// The clear depth; 1 is the far plane.
    public var clearDepth: Float
    /// What happens to the results; `dontCare` by default (a depth buffer
    /// needed only inside one pass).
    public var storeOp: SDLGPUStoreOp

    /// A depth attachment.
    public init(texture: SDLGPUTexture, loadOp: SDLGPULoadOp = .clear, clearDepth: Float = 1,
                storeOp: SDLGPUStoreOp = .dontCare) {
        self.texture = texture
        self.loadOp = loadOp
        self.clearDepth = clearDepth
        self.storeOp = storeOp
    }
}

extension SDLGPUDevice {
    /// A sampler (`SDL_CreateGPUSampler`), or `nil` when SDL refuses.
    public func makeSampler(_ description: SDLGPUSamplerDescription) -> SDLGPUSampler? {
        var info = SDL_GPUSamplerCreateInfo()
        info.min_filter = description.minFilter.sdl
        info.mag_filter = description.magFilter.sdl
        info.mipmap_mode = description.mipmapFilter == .nearest ? SDL_GPU_SAMPLERMIPMAPMODE_NEAREST
                                                                : SDL_GPU_SAMPLERMIPMAPMODE_LINEAR
        let address = description.repeats ? SDL_GPU_SAMPLERADDRESSMODE_REPEAT : SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
        info.address_mode_u = address
        info.address_mode_v = address
        info.address_mode_w = address
        info.min_lod = 0
        info.max_lod = description.maxLevel
        guard let sampler = create({ SDL_CreateGPUSampler($0, &info) }) else { return nil }
        return SDLGPUSampler(raw: sampler, device: self)
    }

    /// A graphics pipeline over two library stages (`SDL_CreateGPUShader` twice,
    /// then `SDL_CreateGPUGraphicsPipeline`; the shaders are released at once,
    /// which SDL allows), or `nil` when SDL refuses (the message is
    /// `SDL_GetError()`: a stage of the wrong kind, a sample count the driver
    /// lacks, a count that does not match the shader).
    public func makeGraphicsPipeline(_ description: SDLGPUGraphicsPipelineDescription) -> SDLGPUGraphicsPipeline? {
        guard let vertex = makeShader(description.vertex, stage: SDL_GPU_SHADERSTAGE_VERTEX) else { return nil }
        defer { release { SDL_ReleaseGPUShader($0, vertex) } }
        guard let fragment = makeShader(description.fragment, stage: SDL_GPU_SHADERSTAGE_FRAGMENT) else { return nil }
        defer { release { SDL_ReleaseGPUShader($0, fragment) } }

        let buffers = description.vertexBuffers.map { buffer -> SDL_GPUVertexBufferDescription in
            var value = SDL_GPUVertexBufferDescription()
            value.slot = UInt32(buffer.slot)
            value.pitch = UInt32(buffer.pitch)
            value.input_rate = buffer.perInstance ? SDL_GPU_VERTEXINPUTRATE_INSTANCE : SDL_GPU_VERTEXINPUTRATE_VERTEX
            value.instance_step_rate = 0
            return value
        }
        let attributes = description.vertexAttributes.map { attribute -> SDL_GPUVertexAttribute in
            var value = SDL_GPUVertexAttribute()
            value.location = UInt32(attribute.location)
            value.buffer_slot = UInt32(attribute.bufferSlot)
            value.format = attribute.format.sdl
            value.offset = UInt32(attribute.offset)
            return value
        }
        var blend = SDL_GPUColorTargetBlendState()
        if description.blend == .premultipliedAlpha {
            blend.enable_blend = true
            blend.src_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            blend.dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
            blend.color_blend_op = SDL_GPU_BLENDOP_ADD
            blend.src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE
            blend.dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
            blend.alpha_blend_op = SDL_GPU_BLENDOP_ADD
        }
        var color = SDL_GPUColorTargetDescription()
        color.format = description.colorFormat.sdl
        color.blend_state = blend

        var info = SDL_GPUGraphicsPipelineCreateInfo()
        info.vertex_shader = vertex
        info.fragment_shader = fragment
        info.primitive_type = description.primitiveType.sdl
        info.rasterizer_state.fill_mode = SDL_GPU_FILLMODE_FILL
        info.rasterizer_state.cull_mode = description.cullMode.sdl
        info.rasterizer_state.front_face = SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE
        info.multisample_state.sample_count = description.sampleCount.sdl
        if let depth = description.depth {
            info.depth_stencil_state.enable_depth_test = true
            info.depth_stencil_state.enable_depth_write = depth.write
            info.depth_stencil_state.compare_op = depth.compare.sdl
            info.target_info.has_depth_stencil_target = true
            info.target_info.depth_stencil_format = SDLGPUTextureFormat.d32Float.sdl
        }
        info.target_info.num_color_targets = 1

        let pipeline: OpaquePointer? = buffers.withUnsafeBufferPointer { bufferPointer in
            attributes.withUnsafeBufferPointer { attributePointer in
                withUnsafePointer(to: &color) { colorPointer in
                    info.vertex_input_state.vertex_buffer_descriptions = bufferPointer.baseAddress
                    info.vertex_input_state.num_vertex_buffers = UInt32(bufferPointer.count)
                    info.vertex_input_state.vertex_attributes = attributePointer.baseAddress
                    info.vertex_input_state.num_vertex_attributes = UInt32(attributePointer.count)
                    info.target_info.color_target_descriptions = colorPointer
                    return create { SDL_CreateGPUGraphicsPipeline($0, &info) }
                }
            }
        }
        guard let pipeline else { return nil }
        return SDLGPUGraphicsPipeline(raw: pipeline, description: description, device: self)
    }

    /// One `SDL_GPUShader` from a library blob, its counts from the reflection.
    private func makeShader(_ blob: SDLGPUShaderBlob, stage: SDL_GPUShaderStage) -> OpaquePointer? {
        var info = SDL_GPUShaderCreateInfo()
        info.format = SDL_GPUShaderFormat(blob.format)
        info.stage = stage
        info.num_samplers = UInt32(blob.samplers)
        info.num_storage_textures = UInt32(blob.readOnlyStorageTextures)
        info.num_storage_buffers = UInt32(blob.readOnlyStorageBuffers)
        info.num_uniform_buffers = UInt32(blob.uniformBuffers)
        return blob.bytes.withUnsafeBufferPointer { code in
            blob.entryPoint.withCString { entry in
                info.code = code.baseAddress
                info.code_size = code.count
                info.entrypoint = entry
                return create { SDL_CreateGPUShader($0, &info) }
            }
        }
    }
}

extension SDLGPUCommandBuffer {
    /// Begins a render pass into `color` (and `depth`) with SDL_GPU's own
    /// semantics (`SDL_BeginGPURenderPass`): one colour target, one optional
    /// depth target. End it with ``SDLGPURenderPass/end()`` before the batch's
    /// closure — or a surface draw — returns. `nil` when SDL refuses.
    public func beginRenderPass(color: SDLGPUColorAttachment, depth: SDLGPUDepthAttachment? = nil) -> SDLGPURenderPass? {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        var colorInfo = SDL_GPUColorTargetInfo()
        colorInfo.texture = color.texture.raw
        colorInfo.clear_color = SDL_FColor(r: color.clearColor.red, g: color.clearColor.green,
                                           b: color.clearColor.blue, a: color.clearColor.alpha)
        colorInfo.load_op = color.loadOp.sdl
        colorInfo.store_op = color.storeOp.sdl
        colorInfo.resolve_texture = color.resolveTexture?.raw
        var depthInfo = SDL_GPUDepthStencilTargetInfo()
        if let depth {
            depthInfo.texture = depth.texture.raw
            depthInfo.clear_depth = depth.clearDepth
            depthInfo.load_op = depth.loadOp.sdl
            depthInfo.store_op = depth.storeOp.sdl
            depthInfo.stencil_load_op = SDL_GPU_LOADOP_DONT_CARE
            depthInfo.stencil_store_op = SDL_GPU_STOREOP_DONT_CARE
        }
        let pass = depth == nil
            ? SDL_BeginGPURenderPass(raw, &colorInfo, 1, nil)
            : SDL_BeginGPURenderPass(raw, &colorInfo, 1, &depthInfo)
        guard let pass else { return nil }
        retained.append(color.texture)
        if let resolve = color.resolveTexture { retained.append(resolve) }
        if let depth { retained.append(depth.texture) }
        notePassBegan()
        return SDLGPURenderPass(raw: pass, commandBuffer: self)
    }

    /// Counts a pass opened; a surface draw's buffer reports it to the window
    /// guard (ruling `GA-I`).
    func notePassBegan() {
        openPasses += 1
        if isFrame { SDLGPUWindowGuard.passBegan() }
    }

    /// Counts a pass ended.
    func notePassEnded() {
        openPasses -= 1
        if isFrame { SDLGPUWindowGuard.passEnded() }
    }
}

/// A render pass (`SDL_GPURenderPass`). Bind a pipeline, then its resources,
/// then draw; End it with ``end()``. Every resource bound is retained until the
/// buffer's fence signals (a batch) or the draw returns (a surface).
public struct SDLGPURenderPass {
    /// The `SDL_GPURenderPass *`.
    public let raw: OpaquePointer
    let commandBuffer: SDLGPUCommandBuffer

    /// Binds a pipeline (`SDL_BindGPUGraphicsPipeline`).
    public func bind(_ pipeline: SDLGPUGraphicsPipeline) {
        SDL_BindGPUGraphicsPipeline(raw, pipeline.raw)
        commandBuffer.retained.append(pipeline)
    }

    /// Binds vertex buffers from `firstSlot` (`SDL_BindGPUVertexBuffers`); their
    /// usage must include ``SDLGPUBufferUsage/vertex``. `offsets` default to 0.
    public func bindVertexBuffers(_ buffers: [SDLGPUBuffer], firstSlot: Int = 0, offsets: [Int]? = nil) {
        var bindings = buffers.enumerated().map { index, buffer -> SDL_GPUBufferBinding in
            var binding = SDL_GPUBufferBinding()
            binding.buffer = buffer.raw
            binding.offset = UInt32(offsets?[index] ?? 0)
            return binding
        }
        bindings.withUnsafeMutableBufferPointer {
            SDL_BindGPUVertexBuffers(raw, UInt32(firstSlot), $0.baseAddress, UInt32($0.count))
        }
        commandBuffer.retained.append(contentsOf: buffers)
    }

    /// Binds read-only storage buffers to the vertex stage from `firstSlot`
    /// (`SDL_BindGPUVertexStorageBuffers`); their usage must include
    /// ``SDLGPUBufferUsage/graphicsStorageRead``.
    public func bindVertexStorageBuffers(_ buffers: [SDLGPUBuffer], firstSlot: Int = 0) {
        var handles: [OpaquePointer?] = buffers.map { $0.raw }
        handles.withUnsafeMutableBufferPointer {
            SDL_BindGPUVertexStorageBuffers(raw, UInt32(firstSlot), $0.baseAddress, UInt32($0.count))
        }
        commandBuffer.retained.append(contentsOf: buffers)
    }

    /// Binds texture-and-sampler pairs to the fragment stage from `firstSlot`
    /// (`SDL_BindGPUFragmentSamplers`); the textures need the sampler usage.
    public func bindFragmentSamplers(_ pairs: [(texture: SDLGPUTexture, sampler: SDLGPUSampler)], firstSlot: Int = 0) {
        var bindings = pairs.map { pair -> SDL_GPUTextureSamplerBinding in
            var binding = SDL_GPUTextureSamplerBinding()
            binding.texture = pair.texture.raw
            binding.sampler = pair.sampler.raw
            return binding
        }
        bindings.withUnsafeMutableBufferPointer {
            SDL_BindGPUFragmentSamplers(raw, UInt32(firstSlot), $0.baseAddress, UInt32($0.count))
        }
        for pair in pairs {
            commandBuffer.retained.append(pair.texture)
            commandBuffer.retained.append(pair.sampler)
        }
    }

    /// Pushes uniform data to a vertex uniform slot (`SDL_PushGPUVertexUniformData`).
    public func pushVertexUniform(_ bytes: [UInt8], at slot: Int) {
        bytes.withUnsafeBytes {
            SDL_PushGPUVertexUniformData(commandBuffer.raw, UInt32(slot), $0.baseAddress, UInt32($0.count))
        }
    }

    /// Pushes uniform data to a fragment uniform slot (`SDL_PushGPUFragmentUniformData`).
    public func pushFragmentUniform(_ bytes: [UInt8], at slot: Int) {
        bytes.withUnsafeBytes {
            SDL_PushGPUFragmentUniformData(commandBuffer.raw, UInt32(slot), $0.baseAddress, UInt32($0.count))
        }
    }

    /// Draws `instanceCount` instances of `vertexCount` vertices
    /// (`SDL_DrawGPUPrimitives`); the shader reads `SV_InstanceID`.
    public func draw(vertexCount: Int, instanceCount: Int = 1, firstVertex: Int = 0, firstInstance: Int = 0) {
        SDL_DrawGPUPrimitives(raw, UInt32(vertexCount), UInt32(instanceCount), UInt32(firstVertex), UInt32(firstInstance))
    }

    /// Ends the pass (`SDL_EndGPURenderPass`); a surface draw that returns with
    /// a pass open traps in a debug build (ruling `GA-I`).
    public func end() {
        SDL_EndGPURenderPass(raw)
        commandBuffer.notePassEnded()
    }
}
#endif
