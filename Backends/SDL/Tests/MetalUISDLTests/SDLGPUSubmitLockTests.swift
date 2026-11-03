import Foundation
import Testing
import MetalUISDLGPU
@testable import MetalUISDLGPU
@testable import MetalUISDL

// XP-G37 (rulings GA-S, GA-E): SDL's Vulkan submit may defragment device memory
// and re-point every live buffer's container; a release on another thread
// races it (SIGSEGV in VULKAN_Submit, lavapipe, SDL 3.4.16). Every submit and
// map/unmap therefore runs under the device lock.

@Suite(.serialized)
struct SDLGPUSubmitLockTests {
    /// **L1** (`GA-S`). Every submit (batch, synchronous batch, synchronous
    /// download) and every map finds the device lock held. Mutation: remove the
    /// lock from `SDLGPUDevice.submitWithFence` (reddens the submit counts) or
    /// from `mapTransfer` (reddens the map counts); recorded in record 195.
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func submitAndMapRunUnderTheDeviceLock() async throws {
        let device = try GPUTestSupport.requireDevice()
        let before = (SDLGPUDevice.submitLockedCount, SDLGPUDevice.submitUnlockedCount,
                      SDLGPUDevice.mapLockedCount, SDLGPUDevice.mapUnlockedCount)

        let fence = try await device.submitBatch { _ in }
        await fence.wait()
        _ = try device.submitBatchSynchronously { _ in }
        device.waitForIdle()
        let texture = try #require(device.makeTexture(SDLGPUTextureDescription(
            width: 4, height: 4, format: .r8g8b8a8Unorm, usage: [.sampler, .colorTarget])))
        _ = try #require(device.downloadSynchronously(texture))
        let transfer = try #require(device.makeTransferBuffer(size: 64, direction: .upload))
        let memory = try #require(transfer.map())
        memory.storeBytes(of: 7, as: UInt8.self)
        transfer.unmap()

        #expect(SDLGPUDevice.submitLockedCount - before.0 >= 3, "batch, synchronous batch and download submitted under the lock")
        #expect(SDLGPUDevice.submitUnlockedCount == before.1, "no submit without the device lock")
        #expect(SDLGPUDevice.mapLockedCount - before.2 >= 2, "the download's map and the direct map ran under the lock")
        #expect(SDLGPUDevice.mapUnlockedCount == before.3, "no map without the device lock")
    }

    /// **L2** (`GA-S`). Pin, probabilistic: one thread submits in a loop while
    /// others create and drop mixed-size storage and transfer buffers to
    /// fragment allocations. Without the fix this crashed `VULKAN_Submit` on
    /// Linux lavapipe (record 195 reports the attempts); passing proves only
    /// that this run did not crash. `METALUI_SUBMIT_STRESS_SECONDS` sets the
    /// duration (default 5).
    @Test(.enabled(if: GPUTestSupport.available, GPUTestSupport.skipReason))
    func submitAgainstConcurrentReleaseDoesNotCrash() throws {
        let device = try GPUTestSupport.requireDevice()
        let seconds = Double(ProcessInfo.processInfo.environment["METALUI_SUBMIT_STRESS_SECONDS"] ?? "") ?? 5
        let deadline = Date().addingTimeInterval(seconds)
        let group = DispatchGroup()
        let submits = Counter()
        group.enter()
        Thread {
            while Date() < deadline {
                if (try? device.submitBatchSynchronously { _ in }) != nil { submits.add() }
            }
            group.leave()
        }.start()
        for seed in 0..<3 {
            group.enter()
            Thread {
                var state = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
                var storage: [SDLGPUBuffer] = []
                var transfers: [SDLGPUTransferBuffer] = []
                func next() -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int(state >> 33) }
                while Date() < deadline {
                    let size = 1024 << (next() % 13)   // 1 KiB ... 4 MiB: fills 16 MiB allocations and leaves holes no later request fits (SDL marks an allocation for defragmentation only then)
                    if next() % 2 == 0 {
                        if let b = device.makeBuffer(size: size, usage: [.computeStorageRead, .computeStorageWrite]) { storage.append(b) }
                    } else if let t = device.makeTransferBuffer(size: size, direction: next() % 2 == 0 ? .upload : .download) {
                        if let m = t.map() { m.storeBytes(of: 1, as: UInt8.self); t.unmap() }
                        transfers.append(t)
                    }
                    if storage.count > 40 { storage.remove(at: next() % storage.count) }
                    if transfers.count > 40 { transfers.remove(at: next() % transfers.count) }
                }
                group.leave()
            }.start()
        }
        #expect(group.wait(timeout: .now() + seconds + 120) == .success, "every thread finished")
        #expect(submits.value > 0, "the submit loop ran")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
