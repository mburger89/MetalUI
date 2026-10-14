import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU

// Compute on an app's own device (rulings GA-D, GA-E, GA-G; spec §6 C1-C4, C8,
// C10). A device is made per test, so the suite is serialized, and it runs on
// the main actor like every other SDL test: Vulkan's device creation raced when
// two tests made one at once in the Linux image (`make()` answered nil), and the
// main actor is the serialization the other SDL tests already have. C9
// (`SDLGPUWindowDeviceTests.swift`) is an extension of this suite for the same
// reason.
//
// The append kernel (`AppShaders/append.comp.hlsl`): 1024 threads, thread `i`
// with `v = i * 7 % 13 < 5` claims a slot by InterlockedAdd on word 0 of a
// read-write byte-address buffer and writes `i` to word `1 + slot`.

private let threadCount = 1024
private let bufferBytes = 4 * (threadCount + 1)
private let expectedAppended = (0..<threadCount).filter { ($0 * 7) % 13 < 5 }

/// Runs the append kernel on `device` into a fresh zeroed buffer and returns
/// the buffer and the batch's fence.
///
/// `gate` holds the **kernel batch's** fence unsignalled (the upload before it
/// is not held): the waiter thread blocks on it until the test signals.
private func dispatchAppend(on device: SDLGPUDevice, groups: Int = 16,
                            holding gate: DispatchSemaphore? = nil) async throws
    -> (buffer: SDLGPUBuffer, fence: SDLGPUFence) {
    let library = try SDLGPUShaderLibrary(directory: GPUTestSupport.compiledShaders)
    let pipeline = try #require(device.makeComputePipeline(try library.compute("append", for: device)))
    let buffer = try #require(device.makeBuffer(size: bufferBytes, usage: [.computeStorageRead, .computeStorageWrite]))
    let zeros = [UInt8](repeating: 0, count: bufferBytes)
    try #require(await device.upload(zeros, to: buffer))
    device.waiterGate = gate
    defer { device.waiterGate = nil }
    let fence = try await device.submitBatch { commandBuffer in
        guard let pass = commandBuffer.beginComputePass(readWrite: [buffer]) else { return }
        pass.bind(pipeline)
        pass.push(uniform: GPUTestSupport.bytes(of: [UInt32(threadCount), 0, 0, 0]), at: 0)
        pass.dispatch(x: groups, y: 1, z: 1)
        pass.end()
    }
    return (buffer, fence)
}

private func ownedDevice() throws -> SDLGPUDevice {
    try GPUTestSupport.requireDevice()
}

@MainActor @Suite(.serialized) struct SDLGPUComputeTests {
    /// `METALUI_REQUIRE_GPU=1` (the Linux and Windows jobs) makes a missing GPU
    /// a failure, so a skip cannot hide a regression (spec §4).
    @Test func aRequiredGPUIsPresent() {
        guard GPUTestSupport.required else { return }
        #expect(GPUTestSupport.available, "METALUI_REQUIRE_GPU=1 but \(SDLGPUDevice.lastFailure)")
    }

    /// **C1.** The kernel appends exactly the threads whose predicate holds:
    /// the counter equals the CPU's count and the sorted payload equals the CPU
    /// list. The download runs ten times: a read before the fence is zeros.
    ///
    /// Mutations: the shader's `< 5` to `< 6` (rebuild the blobs; count red);
    /// `download` skipping its fence wait (zeros read); the dispatch halved.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func anAtomicAppendKernelEmitsExactlyTheThreadsThatPass() async throws {
        let device = try GPUTestSupport.requireDevice()
        let (buffer, fence) = try await dispatchAppend(on: device)
        await fence.wait()
        for round in 0..<10 {
            let bytes = try #require(await device.download(buffer, range: 0..<bufferBytes))
            let words = GPUTestSupport.words(from: bytes)
            #expect(Int(words[0]) == expectedAppended.count, "round \(round): counter \(words[0])")
            let payload = words[1...].prefix(Int(words[0])).sorted()
            let samePayload = payload == expectedAppended.map(UInt32.init)
            #expect(samePayload, "round \(round): \(payload.count) payload words differ from the CPU list")
        }
    }

    /// **C2.** Uploaded bytes come back; a ranged download is exactly the
    /// range. Mutation: the download copies from offset 0 whatever the range.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aStorageBufferRoundTripsUploadedBytes() async throws {
        let device = try GPUTestSupport.requireDevice()
        let buffer = try #require(device.makeBuffer(size: 4096, usage: [.computeStorageRead]))
        let pattern = (0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) }
        try #require(await device.upload(pattern, to: buffer))
        #expect(try #require(await device.download(buffer, range: 0..<4096)) == pattern)
        #expect(try #require(await device.download(buffer, range: 100..<300)) == Array(pattern[100..<300]))
        let tail = [UInt8](repeating: 0xEE, count: 16)
        try #require(await device.upload(tail, to: buffer, at: 4000))
        #expect(try #require(await device.download(buffer, range: 3996..<4020))
                == Array(pattern[3996..<4000]) + tail + Array(pattern[4016..<4020]))
    }

    /// **C3.** The fence is awaited on the waiter thread, not the main actor.
    /// The waiter is held at a gate the main actor opens only after its own
    /// counter has advanced three times across `await`s, so a `wait()` that
    /// blocked the main actor would never see the counter move; the hook counts
    /// `SDL_WaitForGPUFences` calls made off the device's waiter thread.
    ///
    /// Mutation: `wait()` calls the blocking wait inline on the caller → the
    /// main-thread count is 1.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func theFenceIsAwaitedOffTheMainActor() async throws {
        let device = try GPUTestSupport.requireDevice()
        let gate = DispatchSemaphore(value: 0)
        SDLGPUFence.foreignThreadWaitCount = 0
        let (_, fence) = try await dispatchAppend(on: device, holding: gate)
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let advancing = Task { @MainActor in
            while counter.value < 3 { counter.value += 1; await Task.yield() }
            gate.signal()
        }
        await fence.wait()
        await advancing.value
        #expect(counter.value == 3)
        #expect(fence.isSignalled)
        #expect(SDLGPUFence.foreignThreadWaitCount == 0, "SDL_WaitForGPUFences ran off the waiter thread")
    }

    /// **C4.** Cancelling a task that awaits a fence does not release the fence
    /// before it signals: the waiter holds the release. The gate keeps the
    /// fence unsignalled across the cancel.
    ///
    /// Mutation: release in `wait()`'s cancellation handler → the count is 1.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aFenceIsNeverReleasedBeforeItSignals() async throws {
        let device = try GPUTestSupport.requireDevice()
        let gate = DispatchSemaphore(value: 0)
        SDLGPUFence.unsignalledReleaseCount = 0
        let (_, fence) = try await dispatchAppend(on: device, holding: gate)
        let waiting = Task { await fence.wait() }
        waiting.cancel()
        #expect(!fence.isSignalled, "the gate holds the waiter")
        gate.signal()
        await waiting.value
        await fence.wait()
        #expect(fence.isSignalled)
        #expect(SDLGPUFence.unsignalledReleaseCount == 0)
    }

    /// **C8.** No GPU is a named failure, not a trap: an unknown driver name
    /// makes `make` answer `nil` and `lastFailure` names it.
    /// Mutation: `make` force-unwraps the SDL call (traps).
    @Test func aMissingGPUIsNamedNotTrapped() {
        #expect(SDLGPUDevice.make(preferring: "no-such-driver") == nil)
        #expect(SDLGPUDevice.lastFailure.contains("no-such-driver"), "\(SDLGPUDevice.lastFailure)")
    }

    /// **C10.** A borrowed device is not destroyed with its wrapper; an owned
    /// one is, once. The count is of this device's own handle: a fence of an
    /// earlier test may still be releasing its device on the waiter thread, so a
    /// process-wide count would race. Mutation: `deinit` destroys regardless of
    /// ownership (the borrowed wrapper's drop destroys the owner's device).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func aBorrowedDeviceIsNotDestroyed() throws {
        var owner: SDLGPUDevice? = try ownedDevice()
        let handle = try #require(owner).raw
        let before = SDLGPUDevice.destroyCount(of: handle)
        var borrowed: SDLGPUDevice? = SDLGPUDevice(borrowingRaw: try #require(owner).raw)
        #expect(borrowed?.makeBuffer(size: 16, usage: [.computeStorageRead]) != nil)
        borrowed = nil
        #expect(SDLGPUDevice.destroyCount(of: handle) == before, "dropping a borrowed wrapper destroyed the device")
        #expect(owner?.makeBuffer(size: 16, usage: [.computeStorageRead]) != nil, "the device still works")
        owner = nil
        #expect(SDLGPUDevice.destroyCount(of: handle) == before + 1)
    }
}
