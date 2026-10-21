import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU
@testable import MetalUISDL

// The readback and failure-reason gaps MetalCreator's xp-3 asked for (rulings
// GB-F, GB-G, GB-I, GB-L; spec tests S1-S5, P1-P3, plus S6): a synchronous
// texture download and a blocking fence wait for the main actor outside a draw,
// and the reason a pipeline was refused. The red-first state of each is a
// compile failure (the API is absent); the mutation each pin must redden is on
// its doc comment.

private func library() throws -> SDLGPUShaderLibrary {
    try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
}

/// A 16 x 16 `r8g8b8a8Unorm` texture holding a byte gradient, uploaded and ready.
private func gradientTexture(_ device: SDLGPUDevice) async throws -> (SDLGPUTexture, [UInt8]) {
    let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
        width: 16, height: 16, format: .r8g8b8a8Unorm, usage: [.sampler, .colorTarget])))
    let bytes = (0..<(16 * 16 * 4)).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 8) }
    try #require(await device.upload(bytes, to: texture))
    return (texture, bytes)
}

/// Flags a background thread sets, read from the test (a closure cannot capture a var).
private final class Flags: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let returned = DispatchSemaphore(value: 0)
    /// Waits are in synchronous helpers: Swift 6 refuses a semaphore wait in an async body.
    func awaitStart() { started.wait() }
    func awaitReturn(seconds: Double) -> DispatchTimeoutResult { returned.wait(timeout: .now() + seconds) }
}

private func waitFor(_ semaphore: DispatchSemaphore, seconds: Double) {
    _ = semaphore.wait(timeout: .now() + seconds)
}

/// The same blob with its code cut to a quarter: every driver refuses it.
private func truncated(_ blob: SDLGPUShaderBlob) -> SDLGPUShaderBlob {
    SDLGPUShaderBlob(
        name: blob.name, stage: blob.stage, bytes: Array(blob.bytes.prefix(max(4, (blob.bytes.count / 4) & ~3))),
        format: blob.format, entryPoint: blob.entryPoint, samplers: blob.samplers,
        readOnlyStorageTextures: blob.readOnlyStorageTextures, readOnlyStorageBuffers: blob.readOnlyStorageBuffers,
        readWriteStorageTextures: blob.readWriteStorageTextures, readWriteStorageBuffers: blob.readWriteStorageBuffers,
        uniformBuffers: blob.uniformBuffers, threadCount: blob.threadCount)
}

@MainActor @Suite(.serialized) struct SDLGPUReadbackAndFailureTests {
    /// **S1.** From the main actor, outside a draw, `downloadSynchronously` of a
    /// 16 x 16 texture returns every byte, and of the region (3, 5, 4, 2) the
    /// tightly packed rows of that rectangle. Mutation: the region's origin is
    /// ignored (the copy starts at 0, 0).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousDownloadReturnsTheRegionFromTheMainActor() async throws {
        let device = try GPUTestSupport.requireDevice()
        let (texture, bytes) = try await gradientTexture(device)
        MainActor.assertIsolated()
        #expect(device.downloadSynchronously(texture) == bytes, "the whole level")
        let region = SDLGPUTextureRegion(x: 3, y: 5, width: 4, height: 2)
        var expected: [UInt8] = []
        for row in 5..<7 { expected += bytes[(row * 16 + 3) * 4..<(row * 16 + 7) * 4] }
        #expect(device.downloadSynchronously(texture, region: region) == expected, "the sub-rectangle")
    }

    /// **S2.** With the waiter thread held on its gate, a background thread in
    /// `waitBlocking` does not return; once the gate opens it does, the fence is
    /// signalled, no fence was released before its signal and no wait was made
    /// off the waiter thread. Mutation: `waitBlocking` returns at once.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func waitBlockingReturnsOnlyAfterTheSignalAndReleasesNothingEarly() async throws {
        let device = try GPUTestSupport.requireDevice()
        let gate = DispatchSemaphore(value: 0)
        device.waiterGate = gate
        let fence = try await device.submitBatch { _ in }
        device.waiterGate = nil
        let before = (SDLGPUFence.unsignalledReleaseCount, SDLGPUFence.foreignThreadWaitCount)
        let flags = Flags()
        let thread = Thread {
            flags.started.signal()
            fence.waitBlocking()
            flags.returned.signal()
        }
        thread.start()
        flags.awaitStart()
        #expect(flags.awaitReturn(seconds: 0.3) == .timedOut, "still blocked while the fence is unsignalled")
        #expect(!fence.isSignalled)
        gate.signal()
        #expect(flags.awaitReturn(seconds: 30) == .success, "returns once the batch signalled")
        #expect(fence.isSignalled)
        #expect(SDLGPUFence.unsignalledReleaseCount == before.0, "no fence released before its signal")
        #expect(SDLGPUFence.foreignThreadWaitCount == before.1, "waitBlocking never waits on the GPU itself")
    }

    #if DEBUG
    /// **S3** (`GA-I`, `GA-R`). `downloadSynchronously` called while the calling
    /// thread is marked as drawing traps naming the verb. Mutation: its
    /// `assertNotInsideDraw` line removed.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousDownloadInsideADrawTrapsInDebug() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
                width: 4, height: 4, format: .r8g8b8a8Unorm, usage: [.sampler, .colorTarget])))
            SDLGPUWindowGuard.enterSimulatedDrawForTesting()
            _ = device.downloadSynchronously(texture)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("SDLGPUDevice.downloadSynchronously was called inside a surface draw"),
                "the trap names the verb: \(stderr)")
    }

    /// **S4.** The same for `SDLGPUFence.waitBlocking`; the fence is made before
    /// the mark. Mutation: the `assertNotInsideDraw` line removed from it.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aBlockingWaitInsideADrawTrapsInDebug() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            let fence = try await device.submitBatch { _ in }
            SDLGPUWindowGuard.enterSimulatedDrawForTesting()
            fence.waitBlocking()
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("SDLGPUFence.waitBlocking was called inside a surface draw"),
                "the trap names the verb: \(stderr)")
    }
    #endif

    /// **S6** (`GB-I` 2). `waitBlocking` called on the device's own waiter thread
    /// (it would wait on itself) is a `precondition` naming the verb, in every
    /// build. Mutation: the worker-thread check removed (the child hangs and the
    /// test fails on its timeout).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aBlockingWaitOnTheDevicesOwnWorkerIsRefused() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            let fence = try await device.submitBatch { _ in }
            let done = DispatchSemaphore(value: 0)
            device.waiterWorker.enqueue { fence.waitBlocking(); done.signal() }
            waitFor(done, seconds: 20)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("SDLGPUFence.waitBlocking was called on the device's own"),
                "the precondition names the verb: \(stderr)")
    }

    /// **S5.** A region outside the level, one of zero size or a negative origin,
    /// a level that does not exist, a depth texture and a multisampled one are
    /// all `nil`, never a trap. Mutation: the bounds check removed (the outside
    /// region reaches SDL and is not `nil`, or traps).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousDownloadRefusesWhatItCannotRead() async throws {
        let device = try GPUTestSupport.requireDevice()
        let (texture, _) = try await gradientTexture(device)
        #expect(device.downloadSynchronously(texture, region: .init(x: 14, y: 0, width: 4, height: 2)) == nil, "past the right edge")
        #expect(device.downloadSynchronously(texture, region: .init(x: 0, y: 15, width: 2, height: 2)) == nil, "past the bottom")
        #expect(device.downloadSynchronously(texture, region: .init(x: -1, y: 0, width: 2, height: 2)) == nil, "negative origin")
        #expect(device.downloadSynchronously(texture, region: .init(x: 0, y: 0, width: 0, height: 2)) == nil, "zero width")
        #expect(device.downloadSynchronously(texture, region: .init(x: 0, y: 0, width: 2, height: 0)) == nil, "zero height")
        #expect(device.downloadSynchronously(texture, region: .init(x: 0, y: 0, width: 2, height: 2, mipLevel: 1)) == nil,
                "a level the texture does not have")
        if let depth = device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 8, format: .d32Float, usage: [.depthStencilTarget])) {
            #expect(device.downloadSynchronously(depth) == nil, "a depth texture")
        }
        if let multisampled = device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 8, format: .r8g8b8a8Unorm, usage: [.colorTarget], sampleCount: .four)) {
            #expect(device.downloadSynchronously(multisampled) == nil, "a multisampled texture")
        }
    }

    private func graphicsDescription(_ device: SDLGPUDevice, brokenFragment: Bool) throws -> SDLGPUGraphicsPipelineDescription {
        let library = try library()
        let fragment = try library.fragment("flat", for: device)
        return SDLGPUGraphicsPipelineDescription(
            vertex: try library.vertex("fullscreen", for: device),
            fragment: brokenFragment ? truncated(fragment) : fragment, colorFormat: .r8g8b8a8Unorm)
    }

    /// **P1.** A fragment stage with its code cut short: `compileGraphicsPipeline`
    /// throws an error whose text is non-empty and names the fragment stage;
    /// `makeGraphicsPipeline` stays `nil` and `lastPipelineFailure` is then
    /// non-empty (and `nil` before the first failure). Mutation: the reason is
    /// dropped (an empty message, or `lastPipelineFailure` never set).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aRefusedGraphicsPipelineSaysWhy() throws {
        let device = try GPUTestSupport.requireDevice()
        let broken = try graphicsDescription(device, brokenFragment: true)
        #expect(device.lastPipelineFailure == nil)
        do {
            _ = try device.compileGraphicsPipeline(broken)
            Issue.record("a truncated fragment stage compiled")
        } catch let error as SDLGPUError {
            #expect(!error.description.isEmpty)
            #expect(error.description.contains("fragment shader"), "names the stage: \(error)")
        }
        #expect(device.makeGraphicsPipeline(broken) == nil)
        let reason = try #require(device.lastPipelineFailure)
        #expect(!reason.isEmpty && reason.contains("fragment shader"), "recorded: \(reason)")
    }

    /// **P2.** The compute twin, with the append kernel's code cut short.
    /// Mutation: as P1.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aRefusedComputePipelineSaysWhy() throws {
        let device = try GPUTestSupport.requireDevice()
        let broken = truncated(try library().compute("append", for: device))
        do {
            _ = try device.compileComputePipeline(broken)
            Issue.record("a truncated compute stage compiled")
        } catch let error as SDLGPUError {
            #expect(!error.description.isEmpty)
            #expect(error.description.contains("compute"), "names the stage: \(error)")
        }
        #expect(device.makeComputePipeline(broken) == nil)
        let reason = try #require(device.lastPipelineFailure)
        #expect(reason.contains("compute"), "recorded: \(reason)")
    }

    /// **P3.** The optional spellings keep their signatures and succeed on a good
    /// description; a later success does not clear `lastPipelineFailure` (`GB-G`).
    /// Mutation: `makeGraphicsPipeline` made throwing, or its result type changed
    /// (a compile failure), or a success clearing the record.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theOptionalPipelineVerbsKeepTheirSpelling() throws {
        let device = try GPUTestSupport.requireDevice()
        _ = device.makeGraphicsPipeline(try graphicsDescription(device, brokenFragment: true))
        let good = try graphicsDescription(device, brokenFragment: false)
        let optional: SDLGPUGraphicsPipeline? = device.makeGraphicsPipeline(good)
        #expect(optional != nil)
        _ = try device.compileGraphicsPipeline(good)
        let computeBlob = try library().compute("append", for: device)
        let compute: SDLGPUComputePipeline? = device.makeComputePipeline(computeBlob)
        #expect(compute != nil)
        #expect(device.lastPipelineFailure != nil, "a success does not clear the last failure")
    }
}
