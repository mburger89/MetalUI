// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

/// How a buffer is used (`SDL_GPUBufferUsageFlags`, ruling `GA-A`: SDL's names).
public struct SDLGPUBufferUsage: OptionSet, Sendable {
    /// The `SDL_GPUBufferUsageFlags` bits.
    public let rawValue: UInt32
    /// Wraps raw `SDL_GPU_BUFFERUSAGE_*` bits.
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    /// `SDL_GPU_BUFFERUSAGE_VERTEX`.
    public static let vertex = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_VERTEX))
    /// `SDL_GPU_BUFFERUSAGE_INDEX`.
    public static let index = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_INDEX))
    /// `SDL_GPU_BUFFERUSAGE_INDIRECT`.
    public static let indirect = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_INDIRECT))
    /// `SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ`: read as a storage buffer in graphics stages.
    public static let graphicsStorageRead = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ))
    /// `SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ`: read as a storage buffer in a compute pass.
    public static let computeStorageRead = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ))
    /// `SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE`: bound read-write to a compute pass.
    public static let computeStorageWrite = SDLGPUBufferUsage(rawValue: UInt32(SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE))
}

/// Which way a transfer buffer moves data (`SDL_GPUTransferBufferUsage`).
public enum SDLGPUTransferDirection: Sendable {
    /// CPU writes, then a copy pass uploads (`SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD`).
    case upload
    /// A copy pass downloads, then the CPU reads (`SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD`).
    case download
}

/// An `SDL_GPUBuffer`, released when the last reference goes. A command batch
/// retains every buffer it touches until its fence has signalled (ruling `GA-E`).
public final class SDLGPUBuffer: @unchecked Sendable {
    /// The `SDL_GPUBuffer *` (the escape hatch, ruling `GA-A`).
    public let raw: OpaquePointer
    /// The size in bytes the buffer was made with.
    public let size: Int
    let device: SDLGPUDevice

    init(raw: OpaquePointer, size: Int, device: SDLGPUDevice) {
        self.raw = raw
        self.size = size
        self.device = device
    }

    deinit { device.release { SDL_ReleaseGPUBuffer($0, raw) } }
}

/// An `SDL_GPUTransferBuffer`: host-visible memory a copy pass moves to or from
/// a buffer. Map it, fill or read it, unmap it.
public final class SDLGPUTransferBuffer: @unchecked Sendable {
    /// The `SDL_GPUTransferBuffer *`.
    public let raw: OpaquePointer
    /// The size in bytes the buffer was made with.
    public let size: Int
    /// The direction it was made for.
    public let direction: SDLGPUTransferDirection
    let device: SDLGPUDevice

    init(raw: OpaquePointer, size: Int, direction: SDLGPUTransferDirection, device: SDLGPUDevice) {
        self.raw = raw
        self.size = size
        self.direction = direction
        self.device = device
    }

    /// The buffer's memory (`SDL_MapGPUTransferBuffer`), or `nil` when SDL
    /// refuses. Not thread safe against another use of this same buffer (SDL's
    /// header, ruling `GA-E`); unmap before submitting the copy that reads it.
    public func map() -> UnsafeMutableRawPointer? {
        SDL_MapGPUTransferBuffer(device.raw, raw, false)
    }

    /// Ends a mapping (`SDL_UnmapGPUTransferBuffer`).
    public func unmap() { SDL_UnmapGPUTransferBuffer(device.raw, raw) }

    deinit { device.release { SDL_ReleaseGPUTransferBuffer($0, raw) } }
}
#endif
