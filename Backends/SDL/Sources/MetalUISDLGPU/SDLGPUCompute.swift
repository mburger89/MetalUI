// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

/// An `SDL_GPUComputePipeline` (ruling `GA-A`), released with its last reference.
public final class SDLGPUComputePipeline: @unchecked Sendable {
    /// The `SDL_GPUComputePipeline *`.
    public let raw: OpaquePointer
    let device: SDLGPUDevice

    init(raw: OpaquePointer, device: SDLGPUDevice) {
        self.raw = raw
        self.device = device
    }

    deinit { device.release { SDL_ReleaseGPUComputePipeline($0, raw) } }
}

/// The command buffer of one batch (``SDLGPUDevice/submitBatch(_:)``). It is
/// **thread-confined** — recorded only inside the batch's closure, on the
/// worker thread — and has no submit: the batch submits (ruling `GA-E`). Every
/// resource a call names is retained until the batch's fence signals.
public final class SDLGPUCommandBuffer {
    /// The `SDL_GPUCommandBuffer *`.
    public let raw: OpaquePointer
    let device: SDLGPUDevice
    var retained: [AnyObject] = []
    var openPasses = 0
    var isOpen = true

    init(raw: OpaquePointer, device: SDLGPUDevice) {
        self.raw = raw
        self.device = device
    }

    /// Begins a compute pass with `buffers` bound read-write (their usage must
    /// include ``SDLGPUBufferUsage/computeStorageWrite``; SDL binds them when the
    /// pass begins). End it before the batch's closure returns.
    public func beginComputePass(readWrite buffers: [SDLGPUBuffer]) -> SDLGPUComputePass? {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        var bindings = buffers.map { buffer -> SDL_GPUStorageBufferReadWriteBinding in
            var binding = SDL_GPUStorageBufferReadWriteBinding()
            binding.buffer = buffer.raw
            binding.cycle = false
            return binding
        }
        let pass = bindings.withUnsafeMutableBufferPointer {
            SDL_BeginGPUComputePass(raw, nil, 0, $0.baseAddress, UInt32($0.count))
        }
        guard let pass else { return nil }
        retained.append(contentsOf: buffers)
        openPasses += 1
        return SDLGPUComputePass(raw: pass, commandBuffer: self)
    }

    /// Copies `size` bytes from a transfer buffer to a buffer in a copy pass of
    /// its own (`SDL_UploadToGPUBuffer`).
    public func copy(_ source: SDLGPUTransferBuffer, sourceOffset: Int = 0,
                     to destination: SDLGPUBuffer, destinationOffset: Int = 0, size: Int) {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        guard let pass = SDL_BeginGPUCopyPass(raw) else { return }
        var from = SDL_GPUTransferBufferLocation(transfer_buffer: source.raw, offset: UInt32(sourceOffset))
        var to = SDL_GPUBufferRegion(buffer: destination.raw, offset: UInt32(destinationOffset), size: UInt32(size))
        SDL_UploadToGPUBuffer(pass, &from, &to, false)
        SDL_EndGPUCopyPass(pass)
        retained.append(source)
        retained.append(destination)
    }

    /// Copies `range` of a buffer to a transfer buffer in a copy pass of its own
    /// (`SDL_DownloadFromGPUBuffer`); read the transfer buffer after the fence.
    public func copy(_ source: SDLGPUBuffer, range: Range<Int>,
                     to destination: SDLGPUTransferBuffer, destinationOffset: Int = 0) {
        precondition(isOpen, "a command buffer is recorded only inside its batch (GA-E)")
        guard let pass = SDL_BeginGPUCopyPass(raw) else { return }
        var from = SDL_GPUBufferRegion(buffer: source.raw, offset: UInt32(range.lowerBound), size: UInt32(range.count))
        var to = SDL_GPUTransferBufferLocation(transfer_buffer: destination.raw, offset: UInt32(destinationOffset))
        SDL_DownloadFromGPUBuffer(pass, &from, &to)
        SDL_EndGPUCopyPass(pass)
        retained.append(source)
        retained.append(destination)
    }

    /// Zeroes `range` of `buffer` (an upload of zeros: SDL_GPU has no clear),
    /// for an append counter before a dispatch (ruling `GA-G`).
    public func clear(_ buffer: SDLGPUBuffer, range: Range<Int>) {
        guard !range.isEmpty, let zeros = device.makeTransferBuffer(size: range.count, direction: .upload),
              let memory = zeros.map() else { return }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: range.count)
        zeros.unmap()
        copy(zeros, to: buffer, destinationOffset: range.lowerBound, size: range.count)
    }
}

/// A compute pass (`SDL_GPUComputePass`) of a batch. End it with ``end()``.
public struct SDLGPUComputePass {
    /// The `SDL_GPUComputePass *`.
    public let raw: OpaquePointer
    let commandBuffer: SDLGPUCommandBuffer

    /// Binds a pipeline (`SDL_BindGPUComputePipeline`).
    public func bind(_ pipeline: SDLGPUComputePipeline) {
        SDL_BindGPUComputePipeline(raw, pipeline.raw)
        commandBuffer.retained.append(pipeline)
    }

    /// Binds read-only storage buffers from `firstSlot` (`SDL_BindGPUComputeStorageBuffers`);
    /// their usage must include ``SDLGPUBufferUsage/computeStorageRead``.
    public func bind(readOnly buffers: [SDLGPUBuffer], firstSlot: Int = 0) {
        var handles: [OpaquePointer?] = buffers.map { $0.raw }
        handles.withUnsafeMutableBufferPointer {
            SDL_BindGPUComputeStorageBuffers(raw, UInt32(firstSlot), $0.baseAddress, UInt32($0.count))
        }
        commandBuffer.retained.append(contentsOf: buffers)
    }

    /// Pushes uniform data to a compute uniform slot (`SDL_PushGPUComputeUniformData`);
    /// later dispatches in the buffer see it.
    public func push(uniform bytes: [UInt8], at slot: Int) {
        bytes.withUnsafeBytes {
            SDL_PushGPUComputeUniformData(commandBuffer.raw, UInt32(slot), $0.baseAddress, UInt32($0.count))
        }
    }

    /// Dispatches `x * y * z` thread groups (`SDL_DispatchGPUCompute`).
    public func dispatch(x: Int, y: Int, z: Int) {
        SDL_DispatchGPUCompute(raw, UInt32(x), UInt32(y), UInt32(z))
    }

    /// Ends the pass (`SDL_EndGPUComputePass`); every pass must be ended before
    /// the batch's closure returns.
    public func end() {
        SDL_EndGPUComputePass(raw)
        commandBuffer.openPasses -= 1
    }
}
#endif
