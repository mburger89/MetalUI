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
    /// As ``init(_:)``, naming `context` (the description's key fields) when SDL
    /// left its error string empty (some drivers do; ruling `GB-G`).
    init(_ operation: String, context: String) {
        let detail = String(cString: SDL_GetError())
        description = detail.isEmpty ? "\(operation) failed (SDL gave no message; \(context))" : "\(operation): \(detail)"
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
    private let failureLock = NSLock()
    private var _lastPipelineFailure: String?
    /// Test hook: the next batches' waiter thread blocks on this before it waits
    /// on the GPU, so a test can hold a fence unsignalled across a cancel or a
    /// main-actor advance. Per device, so a test on one device never holds
    /// another's fences. `nil` in production.
    nonisolated(unsafe) var waiterGate: DispatchSemaphore?
    private var _submitWorker: SDLGPUWorker?
    private var _waiterWorker: SDLGPUWorker?

    private static let stateLock = NSLock()
    private static let makeLock = NSLock()
    nonisolated(unsafe) private static var failure = ""
    /// Test seam (WG-H): called by `make` once it is inside its critical section, before the video init.
    nonisolated(unsafe) static var testingMakeEntered: (@Sendable () -> Void)?
    /// Test hook: how many times each owned `SDL_GPUDevice *` (by address) was destroyed.
    nonisolated(unsafe) static var destroyedByHandle: [UInt: Int] = [:]

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
    ///
    /// **Threads** (ruling `DL-G`, measured by `SDLGPUDeviceInfoTests` D7 and D8).
    /// SDL's `SDL_Init` documentation says `SDL_INIT_VIDEO` "should be
    /// initialized on the main thread" and `SDL_InitSubSystem` should "only be
    /// called on the main thread"; `SDL_CreateGPUDevice` states no thread rule.
    /// `make` takes one lock, so concurrent calls are safe, and on macOS it runs
    /// the video init on the main thread itself (the caller must not block the
    /// main thread waiting for `make`). On Linux and Windows it initialises video
    /// on the calling thread. **Recommended:** initialise video on the main thread
    /// first (an app's `SDLPlatform` does; a headless tool calls `make` once on the
    /// main thread before starting workers), so a later `make` off the main thread
    /// only retains the subsystem. An engine-owned device made off the main thread
    /// beside a window renderer's device works (D7: macOS and Linux lavapipe).
    public static func make(debug: Bool = false, preferring driver: String? = nil) -> SDLGPUDevice? {
        // Two threads creating a device at once raced inside Vulkan's loader in
        // the Linux image; one lock makes `make` safe against itself.
        makeLock.lock(); defer { makeLock.unlock() }
        testingMakeEntered?()
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

    static func destroyCount(of raw: OpaquePointer) -> Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return destroyedByHandle[UInt(bitPattern: raw)] ?? 0
    }

    deinit {
        _submitWorker?.stop()
        _waiterWorker?.stop()
        guard owned else { return }
        SDL_DestroyGPUDevice(raw)
        if videoInitialised { Self.quitVideo() }
        Self.stateLock.lock(); Self.destroyedByHandle[UInt(bitPattern: raw), default: 0] += 1; Self.stateLock.unlock()
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
    /// `GA-F`), or `nil` when SDL refuses. The reason is
    /// ``lastPipelineFailure`` (ruling `GB-G`); ``compileComputePipeline(_:)``
    /// throws it.
    public func makeComputePipeline(_ blob: SDLGPUShaderBlob) -> SDLGPUComputePipeline? {
        do { return try compileComputePipeline(blob) } catch {
            recordPipelineFailure(String(describing: error))
            return nil
        }
    }

    /// The throwing form of ``makeComputePipeline(_:)`` (ruling `GB-G`): throws
    /// an ``SDLGPUError`` naming the compute stage with `SDL_GetError()`'s text
    /// read on the failing call's thread, or the blob's key fields when SDL gave
    /// none.
    public func compileComputePipeline(_ blob: SDLGPUShaderBlob) throws -> SDLGPUComputePipeline {
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
        let result: (OpaquePointer?, SDLGPUError?) = blob.bytes.withUnsafeBufferPointer { code in
            blob.entryPoint.withCString { entry in
                info.code = code.baseAddress
                info.code_size = code.count
                info.entrypoint = entry
                return create { handle in
                    guard let pipeline = SDL_CreateGPUComputePipeline(handle, &info) else {
                        return (nil, SDLGPUError("compute pipeline \(blob.name) (SDL_CreateGPUComputePipeline)",
                                                 context: "compute stage, blob \(blob.name), \(blob.bytes.count) bytes, format \(blob.format)"))
                    }
                    return (pipeline, nil)
                }
            }
        }
        guard let pipeline = result.0 else { throw result.1 ?? SDLGPUError("compute pipeline \(blob.name)") }
        return SDLGPUComputePipeline(raw: pipeline, device: self)
    }

    /// The reason the last ``makeGraphicsPipeline(_:)`` or
    /// ``makeComputePipeline(_:)`` on this device returned `nil` (ruling
    /// `GB-G`), or `nil` before any failure. A later success does **not** clear
    /// it; the throwing ``compileGraphicsPipeline(_:)`` and
    /// ``compileComputePipeline(_:)`` are the authoritative form.
    public var lastPipelineFailure: String? {
        failureLock.lock(); defer { failureLock.unlock() }
        return _lastPipelineFailure
    }

    func recordPipelineFailure(_ reason: String) {
        failureLock.lock(); _lastPipelineFailure = reason; failureLock.unlock()
    }

    /// `precondition` that the caller is not one of this device's own worker
    /// threads (ruling `GB-I` 2): a blocking verb there waits on itself.
    func preconditionNotOnOwnWorker(_ verb: String) {
        let current = Thread.current
        workerLock.lock()
        let own = (_submitWorker?.thread.map { $0 === current } ?? false)
            || (_waiterWorker?.thread.map { $0 === current } ?? false)
        workerLock.unlock()
        precondition(!own, "\(verb) was called on the device's own worker thread, where it would wait on itself (GB-F)")
    }

    // MARK: Batches

    /// Records one command buffer on the device's worker thread, submits it
    /// there (`SDL_SubmitGPUCommandBufferAndAcquireFence`) and returns the
    /// batch's fence (ruling `GA-E`). The closure runs off the calling thread;
    /// the buffer it receives is valid only inside it. A batch is its own
    /// submission: it adds none to a window's frame. A pass left open at the
    /// closure's end cancels the buffer and throws.
    public func submitBatch(_ record: @escaping @Sendable (SDLGPUCommandBuffer) -> Void) async throws -> SDLGPUFence {
        SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUDevice.submitBatch")
        let gate = waiterGate
        return try await withCheckedThrowingContinuation { continuation in
            submitWorker.enqueue { [self] in
                continuation.resume(with: recordAndSubmit(record, gate: gate))
            }
        }
    }

    /// Records one command buffer and submits it with a fence (ruling `SY-A`):
    /// the one job body behind ``submitBatch(_:)`` and
    /// ``submitBatchSynchronously(_:)``. **Run only on ``submitWorker``**: a
    /// buffer is recorded and submitted on the thread that acquired it.
    func recordAndSubmit(_ record: @Sendable (SDLGPUCommandBuffer) -> Void,
                         gate: DispatchSemaphore?) -> Result<SDLGPUFence, SDLGPUError> {
        guard let handle = SDL_AcquireGPUCommandBuffer(raw) else {
            return .failure(SDLGPUError("SDL_AcquireGPUCommandBuffer"))
        }
        let commandBuffer = SDLGPUCommandBuffer(raw: handle, device: self)
        record(commandBuffer)
        commandBuffer.isOpen = false
        guard commandBuffer.openPasses == 0 else {
            SDL_CancelGPUCommandBuffer(handle)
            return .failure(SDLGPUError("a batch ended with \(commandBuffer.openPasses) pass(es) not ended"))
        }
        guard let fence = SDL_SubmitGPUCommandBufferAndAcquireFence(handle) else {
            return .failure(SDLGPUError("SDL_SubmitGPUCommandBufferAndAcquireFence"))
        }
        let result = SDLGPUFence(raw: fence, device: self, retained: commandBuffer.retained)
        result.startWaiting(gate: gate)
        return .success(result)
    }

    /// As ``submitBatch(_:)`` for code that cannot `await` (ruling `SY-B`): a
    /// viewport click that must render an ID pass and read one pixel on the main
    /// actor. The closure is recorded and submitted on the device's submit
    /// worker (never on the caller) by the same recorder `submitBatch` uses
    /// (`SDL_AcquireGPUCommandBuffer`, `SDL_SubmitGPUCommandBufferAndAcquireFence`),
    /// and the fence is released after its signal whether or not anyone awaits it
    /// (`GA-E`). **The calling thread blocks only until the buffer is submitted,
    /// never until it finishes**: the fence is normally unsignalled, and
    /// ``SDLGPUFence/waitBlocking()`` or ``downloadSynchronously(_:region:)``
    /// (whose job the one FIFO submit worker orders after this batch) is where
    /// the caller waits for the GPU. Throws an ``SDLGPUError`` when acquiring,
    /// ending (a pass left open) or submitting fails.
    ///
    /// Rules are `GB-F`'s (ruling `SY-C`): legal on the main actor outside a
    /// surface draw; a debug trap inside one (`GA-I`); a precondition failure on
    /// the device's own worker threads. The closure runs while the caller is
    /// blocked, so it must not wait for the caller: **a closure that hops to the
    /// main actor and waits deadlocks, and nothing detects it.**
    public func submitBatchSynchronously(_ record: @escaping @Sendable (SDLGPUCommandBuffer) -> Void) throws -> SDLGPUFence {
        SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUDevice.submitBatchSynchronously")
        preconditionNotOnOwnWorker("SDLGPUDevice.submitBatchSynchronously")
        let gate = waiterGate
        let submitted = Submitted()
        submitWorker.enqueue { [self] in
            submitted.finish(recordAndSubmit(record, gate: gate))
        }
        return try submitted.await().get()
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
    public func waitForIdle() {
        SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUDevice.waitForIdle")
        _ = SDL_WaitForGPUIdle(raw)
    }
}
#endif
