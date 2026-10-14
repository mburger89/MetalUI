// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

/// A failure of an SDL_GPU call, carrying SDL's own message.
public struct SDLGPUError: Error, CustomStringConvertible, Sendable {
    /// What was being attempted and SDL's `SDL_GetError()` text.
    public let description: String
    init(_ operation: String) {
        let detail = String(cString: SDL_GetError())
        description = detail.isEmpty ? operation : "\(operation): \(detail)"
    }
}

/// An app's `SDL_GPUDevice` (rulings `GA-A`, `GA-D`): either **owned**, made by
/// ``make(debug:preferring:)`` with no window, or **borrowed**, a view of the
/// window renderer's device taken from a surface draw's context. Named after
/// SDL_GPU, so its documentation applies; ``raw`` is always the escape hatch.
///
/// Threads (ruling `GA-E`): creation and release take one lock; a batch is
/// recorded and submitted on the device's worker thread; its fence is awaited
/// on a second thread. A buffer must not be used while another thread releases
/// it: batches retain what they touch until their fence signals.
public final class SDLGPUDevice: @unchecked Sendable {
    /// The `SDL_GPUDevice *`.
    public let raw: OpaquePointer
    private let owned: Bool
    private let videoInitialised: Bool
    /// Guards creation and release (the headers promise neither thread safe).
    private let lock = NSLock()
    private let workerLock = NSLock()
    private var _submitWorker: SDLGPUWorker?
    private var _waiterWorker: SDLGPUWorker?

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var failure = ""
    nonisolated(unsafe) static var destroyedCount = 0

    /// The reason the last ``make(debug:preferring:)`` returned `nil`, naming
    /// the driver asked for and SDL's message (empty before any failure).
    public static var lastFailure: String {
        stateLock.lock(); defer { stateLock.unlock() }
        return failure
    }

    /// SDL's Cocoa video backend initialises only on the main thread ("No
    /// available video device" elsewhere), and a compute caller is usually off
    /// it, so macOS hops there for the one call.
    private static func onMainThreadIfCocoa<T>(_ body: () -> T) -> T {
        #if os(macOS)
        if !Thread.isMainThread { return DispatchQueue.main.sync(execute: body) }
        #endif
        return body()
    }

    /// Gives back this device's reference to the video subsystem (never
    /// `SDL_Quit`, ruling `RS-D`); on macOS off the main thread, queued there.
    private static func quitVideo() {
        #if os(macOS)
        if !Thread.isMainThread {
            DispatchQueue.main.async { SDL_QuitSubSystem(SDL_INIT_VIDEO) }
            return
        }
        #endif
        SDL_QuitSubSystem(SDL_INIT_VIDEO)
    }

    private static func fail(_ message: String) {
        stateLock.lock(); failure = message; stateLock.unlock()
    }

    /// A standalone device that owns its `SDL_GPUDevice` and destroys it when
    /// the last reference goes (ruling `GA-D`). It asks SDL for the shader
    /// formats this build ships (SPIR-V, DXIL, MSL), so the app's blobs choose
    /// the driver; `driver` names one (`"metal"`, `"vulkan"`, `"direct3d12"`)
    /// and `debug` turns on the driver's validation. Answers `nil` with
    /// ``lastFailure`` when no GPU or driver answers; it never traps.
    public static func make(debug: Bool = false, preferring driver: String? = nil) -> SDLGPUDevice? {
        // Vulkan loads its library through the video subsystem; Metal and D3D12
        // need nothing. Initialising the subsystem (reference counted, never
        // SDL_Quit: ruling RS-D) is harmless where it is not needed.
        let video = onMainThreadIfCocoa { SDL_InitSubSystem(SDL_INIT_VIDEO) }
        let videoFailure = video ? "" : "; SDL_InitSubSystem(VIDEO): \(String(cString: SDL_GetError()))"
        let formats = SDL_GPUShaderFormat(UInt32(SDL_GPU_SHADERFORMAT_SPIRV) | UInt32(SDL_GPU_SHADERFORMAT_DXIL)
                                          | UInt32(SDL_GPU_SHADERFORMAT_MSL))
        guard let device = SDL_CreateGPUDevice(formats, debug, driver) else {
            let asked = driver.map { "driver \"\($0)\"" } ?? "any driver"
            fail("SDL_CreateGPUDevice(\(asked)) failed: \(String(cString: SDL_GetError()))\(videoFailure)")
            if video { quitVideo() }
            return nil
        }
        return SDLGPUDevice(raw: device, owned: true, videoInitialised: video)
    }

    /// A view of the window renderer's device taken from a surface draw's
    /// context (ruling `GA-D`). Not owned and never destroyed; valid for the
    /// renderer's life, so keep it no longer than the window.
    @MainActor public convenience init(borrowing context: SDLGPUDrawContext) {
        self.init(borrowingRaw: context.device)
    }

    init(borrowingRaw raw: OpaquePointer) {
        self.raw = raw
        owned = false
        videoInitialised = false
    }

    private init(raw: OpaquePointer, owned: Bool, videoInitialised: Bool) {
        self.raw = raw
        self.owned = owned
        self.videoInitialised = videoInitialised
    }

    deinit {
        _submitWorker?.stop()
        _waiterWorker?.stop()
        guard owned else { return }
        SDL_DestroyGPUDevice(raw)
        if videoInitialised { Self.quitVideo() }
        Self.stateLock.lock(); Self.destroyedCount += 1; Self.stateLock.unlock()
    }

    /// The driver SDL chose: `"metal"`, `"vulkan"` or `"direct3d12"`.
    public var driver: String { String(cString: SDL_GetGPUDeviceDriver(raw)) }

    // MARK: Threads

    var submitWorker: SDLGPUWorker {
        workerLock.lock(); defer { workerLock.unlock() }
        if let worker = _submitWorker { return worker }
        let worker = SDLGPUWorker(name: "MetalUISDLGPU.submit")
        _submitWorker = worker
        return worker
    }

    var waiterWorker: SDLGPUWorker {
        workerLock.lock(); defer { workerLock.unlock() }
        if let worker = _waiterWorker { return worker }
        let worker = SDLGPUWorker(name: "MetalUISDLGPU.waiter")
        _waiterWorker = worker
        return worker
    }

    /// Runs a creation call under the device lock.
    func create<T>(_ body: (OpaquePointer) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(raw)
    }

    /// Runs a release call under the device lock.
    func release(_ body: (OpaquePointer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(raw)
    }

    // MARK: Resources

    /// A GPU buffer (`SDL_CreateGPUBuffer`), or `nil` when SDL refuses.
    public func makeBuffer(size: Int, usage: SDLGPUBufferUsage) -> SDLGPUBuffer? {
        guard size > 0, size <= Int(UInt32.max) else { return nil }
        var info = SDL_GPUBufferCreateInfo()
        info.usage = SDL_GPUBufferUsageFlags(usage.rawValue)
        info.size = UInt32(size)
        guard let buffer = create({ SDL_CreateGPUBuffer($0, &info) }) else { return nil }
        return SDLGPUBuffer(raw: buffer, size: size, device: self)
    }

    /// A transfer buffer (`SDL_CreateGPUTransferBuffer`), or `nil`.
    public func makeTransferBuffer(size: Int, direction: SDLGPUTransferDirection) -> SDLGPUTransferBuffer? {
        guard size > 0, size <= Int(UInt32.max) else { return nil }
        var info = SDL_GPUTransferBufferCreateInfo()
        info.usage = direction == .upload ? SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD : SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD
        info.size = UInt32(size)
        guard let buffer = create({ SDL_CreateGPUTransferBuffer($0, &info) }) else { return nil }
        return SDLGPUTransferBuffer(raw: buffer, size: size, direction: direction, device: self)
    }

    /// A compute pipeline from a library blob (`SDL_CreateGPUComputePipeline`),
    /// its counts and thread sizes taken from the blob's reflection (ruling
    /// `GA-F`), or `nil` when SDL refuses (the message is `SDL_GetError()`).
    public func makeComputePipeline(_ blob: SDLGPUShaderBlob) -> SDLGPUComputePipeline? {
        var info = SDL_GPUComputePipelineCreateInfo()
        info.format = SDL_GPUShaderFormat(blob.format)
        info.num_samplers = UInt32(blob.samplers)
        info.num_readonly_storage_textures = UInt32(blob.readOnlyStorageTextures)
        info.num_readonly_storage_buffers = UInt32(blob.readOnlyStorageBuffers)
        info.num_readwrite_storage_textures = UInt32(blob.readWriteStorageTextures)
        info.num_readwrite_storage_buffers = UInt32(blob.readWriteStorageBuffers)
        info.num_uniform_buffers = UInt32(blob.uniformBuffers)
        info.threadcount_x = UInt32(blob.threadCount.x)
        info.threadcount_y = UInt32(blob.threadCount.y)
        info.threadcount_z = UInt32(blob.threadCount.z)
        let pipeline: OpaquePointer? = blob.bytes.withUnsafeBufferPointer { code in
            blob.entryPoint.withCString { entry in
                info.code = code.baseAddress
                info.code_size = code.count
                info.entrypoint = entry
                return create { SDL_CreateGPUComputePipeline($0, &info) }
            }
        }
        guard let pipeline else { return nil }
        return SDLGPUComputePipeline(raw: pipeline, device: self)
    }

    // MARK: Batches

    /// Records one command buffer on the device's worker thread, submits it
    /// there (`SDL_SubmitGPUCommandBufferAndAcquireFence`) and returns the
    /// batch's fence (ruling `GA-E`). The closure runs off the calling thread;
    /// the buffer it receives is valid only inside it. A batch is its own
    /// submission: it adds none to a window's frame. A pass left open at the
    /// closure's end cancels the buffer and throws.
    public func submitBatch(_ record: @escaping @Sendable (SDLGPUCommandBuffer) -> Void) async throws -> SDLGPUFence {
        let gate = SDLGPUFence.waiterGate
        return try await withCheckedThrowingContinuation { continuation in
            submitWorker.enqueue { [self] in
                guard let handle = SDL_AcquireGPUCommandBuffer(raw) else {
                    continuation.resume(throwing: SDLGPUError("SDL_AcquireGPUCommandBuffer"))
                    return
                }
                let commandBuffer = SDLGPUCommandBuffer(raw: handle, device: self)
                record(commandBuffer)
                commandBuffer.isOpen = false
                guard commandBuffer.openPasses == 0 else {
                    SDL_CancelGPUCommandBuffer(handle)
                    continuation.resume(throwing: SDLGPUError("a batch ended with \(commandBuffer.openPasses) pass(es) not ended"))
                    return
                }
                guard let fence = SDL_SubmitGPUCommandBufferAndAcquireFence(handle) else {
                    continuation.resume(throwing: SDLGPUError("SDL_SubmitGPUCommandBufferAndAcquireFence"))
                    return
                }
                let result = SDLGPUFence(raw: fence, device: self, retained: commandBuffer.retained)
                result.startWaiting(gate: gate)
                continuation.resume(returning: result)
            }
        }
    }

    /// Copies `bytes` into `buffer` at `offset` through a transfer buffer and
    /// returns once the GPU has finished. `false` when the range does not fit
    /// or SDL refuses.
    public func upload(_ bytes: [UInt8], to buffer: SDLGPUBuffer, at offset: Int = 0) async -> Bool {
        guard !bytes.isEmpty, offset >= 0, offset + bytes.count <= buffer.size,
              let transfer = makeTransferBuffer(size: bytes.count, direction: .upload),
              let memory = transfer.map() else { return false }
        bytes.withUnsafeBytes { memory.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
        transfer.unmap()
        guard let fence = try? await submitBatch({ commandBuffer in
            commandBuffer.copy(transfer, to: buffer, destinationOffset: offset, size: bytes.count)
        }) else { return false }
        await fence.wait()
        return true
    }

    /// Copies `range` of `buffer` to the CPU: a copy pass into a download
    /// transfer buffer, the fence, then the map (ruling `GA-G`). `nil` when the
    /// range does not fit or SDL refuses.
    public func download(_ buffer: SDLGPUBuffer, range: Range<Int>) async -> [UInt8]? {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= buffer.size,
              let transfer = makeTransferBuffer(size: range.count, direction: .download) else { return nil }
        guard let fence = try? await submitBatch({ commandBuffer in
            commandBuffer.copy(buffer, range: range, to: transfer)
        }) else { return nil }
        await fence.wait()
        guard let memory = transfer.map() else { return nil }
        defer { transfer.unmap() }
        return Array(UnsafeRawBufferPointer(start: memory, count: range.count))
    }

    /// Blocks until the device is idle (`SDL_WaitForGPUIdle`). Never call it
    /// from a surface draw (ruling `GA-I`).
    public func waitForIdle() { _ = SDL_WaitForGPUIdle(raw) }
}
#endif
