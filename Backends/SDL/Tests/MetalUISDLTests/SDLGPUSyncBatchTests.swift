import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU
@testable import MetalUISDL

// The synchronous render batch MetalCreator's XP-G22 asked for (rulings SY-A
// ... SY-G; spec tests Y1-Y8): `submitBatchSynchronously` records and submits
// a batch from the main actor outside a draw and returns once it is submitted.
// The red-first state of each pin is a compile failure (the verb is absent);
// the mutation each must redden is on its doc comment.

/// A 16 x 16 render target.
private func target(_ device: SDLGPUDevice, size: Int = 16) throws -> SDLGPUTexture {
    try #require(device.makeTexture(SDLGPUTextureDescription(
        width: size, height: size, format: .r8g8b8a8Unorm, usage: [.sampler, .colorTarget])))
}

/// A batch recording one clear pass of `color` into `texture`.
private func clear(_ texture: SDLGPUTexture, _ color: (Float, Float, Float, Float))
    -> @Sendable (SDLGPUCommandBuffer) -> Void {
    { commandBuffer in
        guard let pass = commandBuffer.beginRenderPass(color: SDLGPUColorAttachment(
            texture: texture, loadOp: .clear,
            clearColor: (red: color.0, green: color.1, blue: color.2, alpha: color.3))) else { return }
        pass.end()
    }
}

/// Whether every texel of `bytes` is `expected` (each channel within one step).
private func everyTexel(_ bytes: [UInt8]?, is expected: [UInt8]) -> Bool {
    guard let bytes, bytes.count % 4 == 0, !bytes.isEmpty else { return false }
    return stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
        (0..<4).allSatisfy { abs(Int(bytes[offset + $0]) - Int(expected[$0])) <= 1 }
    }
}

/// What a background thread or a record closure leaves for the test to read.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _thread: Thread?
    private var _fence: SDLGPUFence?
    private var _error: Error?
    let started = DispatchSemaphore(value: 0)
    let done = DispatchSemaphore(value: 0)
    var thread: Thread? { lock.lock(); defer { lock.unlock() }; return _thread }
    var fence: SDLGPUFence? { lock.lock(); defer { lock.unlock() }; return _fence }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return _error }
    func set(thread: Thread) { lock.lock(); _thread = thread; lock.unlock() }
    func set(fence: SDLGPUFence?, error: Error?) { lock.lock(); _fence = fence; _error = error; lock.unlock() }
    /// Waits are in synchronous helpers: Swift 6 refuses a semaphore wait in an async body.
    func awaitDone(seconds: Double) -> DispatchTimeoutResult { done.wait(timeout: .now() + seconds) }
    func awaitStarted() { started.wait() }
}

private func waitFor(_ semaphore: DispatchSemaphore, seconds: Double) {
    _ = semaphore.wait(timeout: .now() + seconds)
}

@MainActor @Suite(.serialized) struct SDLGPUSyncBatchTests {
    /// **Y1.** A clear pass submitted by `submitBatchSynchronously` and read by
    /// `downloadSynchronously` gives every texel the clear colour, on the main
    /// actor with no `await` after the texture exists. Mutation: `record` is not
    /// called by the shared recorder (the texture reads zeros).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousBatchRendersATextureTheMainActorReadsWithoutAwaiting() throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try target(device)
        _ = try device.submitBatchSynchronously(clear(texture, (1, 0, 0.5, 1)))
        MainActor.assertIsolated()
        let pixels = device.downloadSynchronously(texture)
        #expect(pixels?.count == 16 * 16 * 4)
        #expect(everyTexel(pixels, is: [255, 0, 128, 255]), "every texel is the clear colour")
    }

    /// **Y2.** With the waiter held on its gate a background thread's call
    /// returns (the batch is submitted, not finished) and the fence is not
    /// signalled; after the gate opens and `waitBlocking()` it is. Mutation: the
    /// verb waits on the fence before returning (the call blocks on the gate
    /// and the timeout reddens).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousBatchReturnsOnceSubmittedNotOnceFinished() throws {
        let device = try GPUTestSupport.requireDevice()
        let gate = DispatchSemaphore(value: 0)
        device.waiterGate = gate
        let box = Box()
        let thread = Thread {
            do { box.set(fence: try device.submitBatchSynchronously { _ in }, error: nil) } catch { box.set(fence: nil, error: error) }
            box.done.signal()
        }
        thread.start()
        let returned = box.awaitDone(seconds: 20)
        device.waiterGate = nil
        let fence = box.fence
        let signalledOnReturn = fence?.isSignalled
        gate.signal()   // always release the waiter, even when the verb never returned
        #expect(returned == .success, "the verb returned while the fence was held")
        #expect(box.error == nil)
        #expect(signalledOnReturn == false, "returned before the GPU finished: the fence is unsignalled")
        let held = try #require(fence)
        held.waitBlocking()
        #expect(held.isSignalled)
    }

    /// **Y3.** Two synchronous batches clearing green then blue into one
    /// texture with no wait between, then a download: every texel is blue,
    /// twenty times with alternating colours. Mutation: the verb enqueues on the
    /// waiter worker instead of the submit worker (FIFO order against the
    /// download's job is lost).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aDownloadIssuedRightAfterReadsTheBatchsOutput() throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try target(device)
        for round in 0..<20 {
            let (first, second): ((Float, Float, Float, Float), (Float, Float, Float, Float)) = round % 2 == 0
                ? ((0, 1, 0, 1), (0, 0, 1, 1)) : ((0, 0, 1, 1), (0, 1, 0, 1))
            _ = try device.submitBatchSynchronously(clear(texture, first))
            _ = try device.submitBatchSynchronously(clear(texture, second))
            let expected: [UInt8] = second.2 == 1 ? [0, 0, 255, 255] : [0, 255, 0, 255]
            #expect(everyTexel(device.downloadSynchronously(texture), is: expected), "round \(round) reads the last batch")
        }
    }

    /// **Y4.** The record closure runs on the device's submit worker, never on
    /// the caller. Mutation: `record` invoked inline on the caller.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theRecordClosureRunsOnTheSubmitWorker() throws {
        let device = try GPUTestSupport.requireDevice()
        let box = Box()
        let fence = try device.submitBatchSynchronously { _ in box.set(thread: Thread.current) }
        fence.waitBlocking()
        let recorded = try #require(box.thread)
        #expect(recorded === device.submitWorker.thread)
        #expect(!recorded.isMainThread)
        #expect(Thread.isMainThread, "the caller is still on the main thread")
    }

    #if DEBUG
    /// **Y5** (`GA-I`, `GA-R`). The verb called while the calling thread is
    /// marked as drawing traps naming it. Mutation: its `assertNotInsideDraw`
    /// line removed.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousBatchInsideADrawTrapsInDebug() async throws {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            SDLGPUWindowGuard.enterSimulatedDrawForTesting()
            _ = try device.submitBatchSynchronously { _ in }
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("SDLGPUDevice.submitBatchSynchronously was called inside a surface draw"),
                "the trap names the verb: \(stderr)")
    }
    #endif

    /// **Y6** (`GB-L`). The verb called from the device's own submit worker, and
    /// from its waiter worker, is a `precondition` naming the verb in every
    /// build. Mutation: the `preconditionNotOnOwnWorker` line removed (the child
    /// deadlocks on its own queue and fails on its timeout).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aSynchronousBatchOnTheDevicesOwnWorkerIsRefused() async throws {
        let submit = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            let done = DispatchSemaphore(value: 0)
            device.submitWorker.enqueue { _ = try? device.submitBatchSynchronously { _ in }; done.signal() }
            waitFor(done, seconds: 20)
        }
        let submitText = String(decoding: submit?.standardErrorContent ?? [], as: UTF8.self)
        #expect(submitText.contains("SDLGPUDevice.submitBatchSynchronously was called on the device's own"),
                "the submit-worker arm names the verb: \(submitText)")
        let waiter = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let device = try #require(await MainActor.run { GPUTestSupport.available ? SDLGPUDevice.make() : nil })
            let done = DispatchSemaphore(value: 0)
            device.waiterWorker.enqueue { _ = try? device.submitBatchSynchronously { _ in }; done.signal() }
            waitFor(done, seconds: 20)
        }
        let waiterText = String(decoding: waiter?.standardErrorContent ?? [], as: UTF8.self)
        #expect(waiterText.contains("SDLGPUDevice.submitBatchSynchronously was called on the device's own"),
                "the waiter-worker arm names the verb: \(waiterText)")
    }

    /// **Y7** (`GA-E`). Eight fences waited on end signalled; eight dropped
    /// unawaited are still released after their signal; no fence is released
    /// early and no wait is made off the waiter thread. Mutation: the verb skips
    /// `startWaiting` (fences never signal, the bounded waits time out); second,
    /// `startWaiting` replaced by an immediate release (`unsignalledReleaseCount`
    /// rises).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func everySynchronousFenceIsReleasedOnceAfterItsSignal() throws {
        let device = try GPUTestSupport.requireDevice()
        let before = (SDLGPUFence.unsignalledReleaseCount, SDLGPUFence.foreignThreadWaitCount)
        let fences = try (0..<8).map { _ in try device.submitBatchSynchronously { _ in } }
        let box = Box()
        let thread = Thread {
            for fence in fences { fence.waitBlocking() }
            box.done.signal()
        }
        thread.start()
        #expect(box.awaitDone(seconds: 30) == .success, "every fence signals")
        #expect(fences.allSatisfy(\.isSignalled))
        for _ in 0..<8 { _ = try device.submitBatchSynchronously { _ in } }
        device.waitForIdle()
        let probe = try device.submitBatchSynchronously { _ in }   // FIFO after the eight: its signal orders the waiter
        let waiting = Box()
        let poll = Thread { probe.waitBlocking(); waiting.done.signal() }
        poll.start()
        #expect(waiting.awaitDone(seconds: 30) == .success)
        #expect(SDLGPUFence.unsignalledReleaseCount == before.0, "no fence released before its signal")
        #expect(SDLGPUFence.foreignThreadWaitCount == before.1, "no wait on the GPU off the waiter thread")
    }

    /// **Y8.** A record that begins a pass and never ends it makes the verb
    /// throw an `SDLGPUError` naming the open pass; a following good batch still
    /// returns a fence and renders. Mutation: the `openPasses == 0` check
    /// removed from the shared recorder.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aBatchThatLeavesAPassOpenThrowsAndTheNextOneStillWorks() throws {
        let device = try GPUTestSupport.requireDevice()
        let texture = try target(device)
        let thrown = #expect(throws: SDLGPUError.self) {
            _ = try device.submitBatchSynchronously { commandBuffer in
                _ = commandBuffer.beginRenderPass(color: SDLGPUColorAttachment(texture: texture))
            }
        }
        #expect(thrown?.description.contains("not ended") == true, "names the open pass: \(String(describing: thrown))")
        _ = try device.submitBatchSynchronously(clear(texture, (1, 0, 0.5, 1)))
        #expect(everyTexel(device.downloadSynchronously(texture), is: [255, 0, 128, 255]))
    }
}
