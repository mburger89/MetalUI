// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

/// The texel formats the typed layer names (`SDL_GPUTextureFormat`, ruling
/// `GA-H`). Any other format is reached through ``SDLGPUTexture/raw`` and SDL
/// itself.
public enum SDLGPUTextureFormat: Sendable {
    /// `SDL_GPU_TEXTUREFORMAT_R8_UNORM`: one 8-bit channel.
    case r8Unorm
    /// `SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM`.
    case r8g8b8a8Unorm
    /// `SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM`: the format of a `GPUSurface`'s target.
    case b8g8r8a8Unorm
    /// `SDL_GPU_TEXTUREFORMAT_R32_UINT`: one 32-bit integer, for an ID pass.
    case r32Uint
    /// `SDL_GPU_TEXTUREFORMAT_D32_FLOAT`: a depth target.
    case d32Float

    var sdl: SDL_GPUTextureFormat {
        switch self {
        case .r8Unorm: return SDL_GPU_TEXTUREFORMAT_R8_UNORM
        case .r8g8b8a8Unorm: return SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
        case .b8g8r8a8Unorm: return SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM
        case .r32Uint: return SDL_GPU_TEXTUREFORMAT_R32_UINT
        case .d32Float: return SDL_GPU_TEXTUREFORMAT_D32_FLOAT
        }
    }

    /// Bytes of one texel (a depth format cannot be downloaded: 0).
    public var bytesPerTexel: Int {
        switch self {
        case .r8Unorm: return 1
        case .r8g8b8a8Unorm, .b8g8r8a8Unorm, .r32Uint: return 4
        case .d32Float: return 0
        }
    }
}

/// Samples per texel (`SDL_GPUSampleCount`). A texture of more than one sample
/// is a render target only: it cannot be sampled, uploaded to or downloaded.
public enum SDLGPUSampleCount: Sendable {
    /// `SDL_GPU_SAMPLECOUNT_1`.
    case one
    /// `SDL_GPU_SAMPLECOUNT_2`.
    case two
    /// `SDL_GPU_SAMPLECOUNT_4`.
    case four
    /// `SDL_GPU_SAMPLECOUNT_8`.
    case eight

    var sdl: SDL_GPUSampleCount {
        switch self {
        case .one: return SDL_GPU_SAMPLECOUNT_1
        case .two: return SDL_GPU_SAMPLECOUNT_2
        case .four: return SDL_GPU_SAMPLECOUNT_4
        case .eight: return SDL_GPU_SAMPLECOUNT_8
        }
    }
}

/// How a texture is used (`SDL_GPUTextureUsageFlags`, ruling `GA-A`: SDL's names).
public struct SDLGPUTextureUsage: OptionSet, Sendable {
    /// The `SDL_GPUTextureUsageFlags` bits.
    public let rawValue: UInt32
    /// Wraps raw `SDL_GPU_TEXTUREUSAGE_*` bits.
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    /// `SDL_GPU_TEXTUREUSAGE_SAMPLER`: sampled by a shader.
    public static let sampler = SDLGPUTextureUsage(rawValue: UInt32(SDL_GPU_TEXTUREUSAGE_SAMPLER))
    /// `SDL_GPU_TEXTUREUSAGE_COLOR_TARGET`: a render pass's colour target (and
    /// what ``SDLGPUCommandBuffer/generateMipmaps(of:)`` needs beside `sampler`).
    public static let colorTarget = SDLGPUTextureUsage(rawValue: UInt32(SDL_GPU_TEXTUREUSAGE_COLOR_TARGET))
    /// `SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET`.
    public static let depthStencilTarget = SDLGPUTextureUsage(rawValue: UInt32(SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET))
}

/// What ``SDLGPUDevice/makeTexture(_:)`` is asked for: a 2D texture (ruling
/// `GA-H`: the list asks for no more).
public struct SDLGPUTextureDescription: Sendable {
    /// Width of mip level 0 in texels.
    public var width: Int
    /// Height of mip level 0 in texels.
    public var height: Int
    /// The texel format.
    public var format: SDLGPUTextureFormat
    /// Samples per texel; more than one makes a render-only multisample texture.
    public var sampleCount: SDLGPUSampleCount
    /// Mip levels (`num_levels`); 1 is no mip chain.
    public var levelCount: Int
    /// What the texture is used for.
    public var usage: SDLGPUTextureUsage

    /// A description; `sampleCount` and `levelCount` default to one.
    public init(width: Int, height: Int, format: SDLGPUTextureFormat, usage: SDLGPUTextureUsage,
                sampleCount: SDLGPUSampleCount = .one, levelCount: Int = 1) {
        self.width = width
        self.height = height
        self.format = format
        self.usage = usage
        self.sampleCount = sampleCount
        self.levelCount = levelCount
    }
}

/// An `SDL_GPUTexture`, released when the last reference goes — **unless it is
/// the borrowed target of a surface draw** (``SDLGPUFrameView/target``), which
/// MetalUI owns and this wrapper never releases.
public final class SDLGPUTexture: @unchecked Sendable {
    /// The `SDL_GPUTexture *` (the escape hatch, ruling `GA-A`).
    public let raw: OpaquePointer
    /// What the texture was made with.
    public let description: SDLGPUTextureDescription
    let device: SDLGPUDevice
    private let owned: Bool

    init(raw: OpaquePointer, description: SDLGPUTextureDescription, device: SDLGPUDevice, owned: Bool) {
        self.raw = raw
        self.description = description
        self.device = device
        self.owned = owned
    }

    /// The bytes of mip level `level` read back by ``SDLGPUDevice/download(_:mipLevel:)``.
    public func byteCount(mipLevel level: Int) -> Int {
        let width = max(1, description.width >> level), height = max(1, description.height >> level)
        return width * height * description.format.bytesPerTexel
    }

    deinit {
        guard owned else { return }
        device.release { SDL_ReleaseGPUTexture($0, raw) }
    }
}

extension SDLGPUDevice {
    /// A 2D texture (`SDL_CreateGPUTexture`), or `nil` when SDL refuses (an
    /// unsupported format, sample count or usage; the message is `SDL_GetError()`).
    public func makeTexture(_ description: SDLGPUTextureDescription) -> SDLGPUTexture? {
        guard description.width > 0, description.height > 0, description.levelCount > 0 else { return nil }
        var info = SDL_GPUTextureCreateInfo()
        info.type = SDL_GPU_TEXTURETYPE_2D
        info.format = description.format.sdl
        info.usage = SDL_GPUTextureUsageFlags(description.usage.rawValue)
        info.width = UInt32(description.width)
        info.height = UInt32(description.height)
        info.layer_count_or_depth = 1
        info.num_levels = UInt32(description.levelCount)
        info.sample_count = description.sampleCount.sdl
        guard let texture = create({ SDL_CreateGPUTexture($0, &info) }) else { return nil }
        return SDLGPUTexture(raw: texture, description: description, device: self, owned: true)
    }

    /// Copies `bytes` (tightly packed rows of mip level `mipLevel`) into the
    /// texture through a transfer buffer and returns once the GPU has finished.
    /// `false` when the byte count is not the level's, the texture is
    /// multisampled or a depth format, or SDL refuses.
    public func upload(_ bytes: [UInt8], to texture: SDLGPUTexture, mipLevel: Int = 0) async -> Bool {
        let description = texture.description
        guard description.sampleCount == .one, description.format.bytesPerTexel > 0,
              mipLevel >= 0, mipLevel < description.levelCount,
              bytes.count == texture.byteCount(mipLevel: mipLevel),
              let transfer = makeTransferBuffer(size: bytes.count, direction: .upload),
              let memory = transfer.map() else { return false }
        bytes.withUnsafeBytes { memory.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
        transfer.unmap()
        guard let fence = try? await submitBatch({ commandBuffer in
            commandBuffer.copy(transfer, to: texture, mipLevel: mipLevel)
        }) else { return false }
        await fence.wait()
        return true
    }

    /// Reads mip level `mipLevel` back to the CPU as tightly packed rows: a copy
    /// pass into a download transfer buffer, the fence, then the map (ruling
    /// `GA-H`: the readback an ID pass is picked from). `nil` for a
    /// multisampled or depth texture, or when SDL refuses.
    public func download(_ texture: SDLGPUTexture, mipLevel: Int = 0) async -> [UInt8]? {
        let description = texture.description
        guard description.sampleCount == .one, description.format.bytesPerTexel > 0,
              mipLevel >= 0, mipLevel < description.levelCount,
              let transfer = makeTransferBuffer(size: texture.byteCount(mipLevel: mipLevel), direction: .download)
        else { return nil }
        guard let fence = try? await submitBatch({ commandBuffer in
            commandBuffer.copy(texture, mipLevel: mipLevel, to: transfer)
        }) else { return nil }
        await fence.wait()
        guard let memory = transfer.map() else { return nil }
        defer { transfer.unmap() }
        return Array(UnsafeRawBufferPointer(start: memory, count: texture.byteCount(mipLevel: mipLevel)))
    }
}

extension SDLGPUCommandBuffer {
    /// Copies a transfer buffer's tightly packed rows into mip level `mipLevel`
    /// of a texture in a copy pass of its own (`SDL_UploadToGPUTexture`).
    public func copy(_ source: SDLGPUTransferBuffer, to destination: SDLGPUTexture, mipLevel: Int = 0) {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        guard let pass = SDL_BeginGPUCopyPass(raw) else { return }
        var from = SDL_GPUTextureTransferInfo(transfer_buffer: source.raw, offset: 0, pixels_per_row: 0, rows_per_layer: 0)
        var to = SDL_GPUTextureRegion()
        to.texture = destination.raw
        to.mip_level = UInt32(mipLevel)
        to.w = UInt32(max(1, destination.description.width >> mipLevel))
        to.h = UInt32(max(1, destination.description.height >> mipLevel))
        to.d = 1
        SDL_UploadToGPUTexture(pass, &from, &to, false)
        SDL_EndGPUCopyPass(pass)
        retained.append(source)
        retained.append(destination)
    }

    /// Copies mip level `mipLevel` of a texture to a transfer buffer in a copy
    /// pass of its own (`SDL_DownloadFromGPUTexture`); read it after the fence.
    public func copy(_ source: SDLGPUTexture, mipLevel: Int = 0, to destination: SDLGPUTransferBuffer) {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        guard let pass = SDL_BeginGPUCopyPass(raw) else { return }
        var from = SDL_GPUTextureRegion()
        from.texture = source.raw
        from.mip_level = UInt32(mipLevel)
        from.w = UInt32(max(1, source.description.width >> mipLevel))
        from.h = UInt32(max(1, source.description.height >> mipLevel))
        from.d = 1
        var to = SDL_GPUTextureTransferInfo(transfer_buffer: destination.raw, offset: 0, pixels_per_row: 0, rows_per_layer: 0)
        SDL_DownloadFromGPUTexture(pass, &from, &to)
        SDL_EndGPUCopyPass(pass)
        retained.append(source)
        retained.append(destination)
    }

    /// Fills the rest of the mip chain of `texture` from level 0
    /// (`SDL_GenerateMipmapsForGPUTexture`). The texture needs both
    /// ``SDLGPUTextureUsage/sampler`` and ``SDLGPUTextureUsage/colorTarget``;
    /// call it outside any pass.
    public func generateMipmaps(of texture: SDLGPUTexture) {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        SDL_GenerateMipmapsForGPUTexture(raw, texture.raw)
        retained.append(texture)
    }
}
#endif
