// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

/// A rectangle of one mip level of a texture, in texels from the top left
/// (ruling `GB-F`), the region ``SDLGPUDevice/downloadSynchronously(_:region:)``
/// reads (`SDL_GPUTextureRegion` without the texture, layer and depth).
public struct SDLGPUTextureRegion: Sendable, Equatable {
    /// Left edge in texels.
    public var x: Int
    /// Top edge in texels.
    public var y: Int
    /// Width in texels.
    public var width: Int
    /// Height in texels.
    public var height: Int
    /// The mip level the rectangle is in.
    public var mipLevel: Int

    /// A region of mip level `mipLevel` (default 0).
    public init(x: Int, y: Int, width: Int, height: Int, mipLevel: Int = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.mipLevel = mipLevel
    }
}

/// What a blocking verb's worker job hands back to the calling thread (rulings
/// `GB-F`, `SY-D`): the job's `Result`, then a signal.
final class Submitted: @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var result: Result<SDLGPUFence, SDLGPUError>?

    /// Records the outcome and wakes the caller; called once, on the worker.
    func finish(_ outcome: Result<SDLGPUFence, SDLGPUError>) {
        result = outcome
        ready.signal()
    }

    /// Blocks until the worker finished. A plain method so Swift 6 accepts the wait.
    func await() -> Result<SDLGPUFence, SDLGPUError> {
        ready.wait()
        return result!
    }
}

extension SDLGPUDevice {
    /// Reads `region` of a texture (default: all of level 0) to the CPU as
    /// tightly packed rows and **blocks the calling thread** until the GPU has
    /// finished (ruling `GB-F`): a copy pass in one batch on the device's submit
    /// worker, then ``SDLGPUFence/waitBlocking()``. Legal on the main actor
    /// outside a surface draw (Metal's `waitUntilCompleted` parity) at the cost of
    /// a stalled frame, so a picking readback should prefer ``download(_:mipLevel:)``;
    /// inside a draw it traps in a debug build (`GA-I`), and on the device's own
    /// worker threads it is a precondition failure. `nil` for a multisampled or
    /// depth texture, a region that is empty or outside the level, or when SDL
    /// refuses. Needs no usage flag beyond what ``download(_:mipLevel:)`` needs.
    public func downloadSynchronously(_ texture: SDLGPUTexture, region: SDLGPUTextureRegion? = nil) -> [UInt8]? {
        SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUDevice.downloadSynchronously")
        preconditionNotOnOwnWorker("SDLGPUDevice.downloadSynchronously")
        let description = texture.description
        let region = region ?? SDLGPUTextureRegion(x: 0, y: 0, width: description.width, height: description.height)
        let bytesPerTexel = description.format.bytesPerTexel
        guard description.sampleCount == .one, bytesPerTexel > 0,
              region.mipLevel >= 0, region.mipLevel < description.levelCount else { return nil }
        let levelWidth = max(1, description.width >> region.mipLevel)
        let levelHeight = max(1, description.height >> region.mipLevel)
        guard region.width > 0, region.height > 0, region.x >= 0, region.y >= 0,
              region.x <= levelWidth - region.width, region.y <= levelHeight - region.height else { return nil }
        let byteCount = region.width * region.height * bytesPerTexel
        guard let transfer = makeTransferBuffer(size: byteCount, direction: .download) else { return nil }

        let submitted = Submitted()
        submitWorker.enqueue { [self] in
            guard let handle = SDL_AcquireGPUCommandBuffer(raw) else { submitted.finish(.failure(SDLGPUError("SDL_AcquireGPUCommandBuffer"))); return }
            let commandBuffer = SDLGPUCommandBuffer(raw: handle, device: self)
            if let pass = SDL_BeginGPUCopyPass(handle) {
                var from = SDL_GPUTextureRegion()
                from.texture = texture.raw
                from.mip_level = UInt32(region.mipLevel)
                from.x = UInt32(region.x)
                from.y = UInt32(region.y)
                from.w = UInt32(region.width)
                from.h = UInt32(region.height)
                from.d = 1
                var to = SDL_GPUTextureTransferInfo(transfer_buffer: transfer.raw, offset: 0, pixels_per_row: 0, rows_per_layer: 0)
                SDL_DownloadFromGPUTexture(pass, &from, &to)
                SDL_EndGPUCopyPass(pass)
                commandBuffer.retained.append(texture)
                commandBuffer.retained.append(transfer)
            }
            commandBuffer.isOpen = false
            guard let fence = SDL_SubmitGPUCommandBufferAndAcquireFence(handle) else {
                submitted.finish(.failure(SDLGPUError("SDL_SubmitGPUCommandBufferAndAcquireFence"))); return
            }
            let result = SDLGPUFence(raw: fence, device: self, retained: commandBuffer.retained)
            result.startWaiting(gate: nil)
            submitted.finish(.success(result))
        }
        guard case .success(let fence) = submitted.await() else { return nil }
        fence.waitBlocking()
        guard let memory = transfer.map() else { return nil }
        defer { transfer.unmap() }
        return Array(UnsafeRawBufferPointer(start: memory, count: byteCount))
    }
}
#endif
