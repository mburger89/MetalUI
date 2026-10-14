// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

/// The completion of one submitted batch (ruling `GA-E`). It is waited for on
/// the device's **waiter thread**, which `SDL_WaitForGPUFences`-blocks there
/// and releases the SDL fence only after it signals (the fence rule: never
/// release an unsignalled fence). `wait()` merely suspends until that thread
/// reports, so the main actor is never blocked and cancelling the awaiting task
/// changes nothing about the release.
public final class SDLGPUFence: @unchecked Sendable {
    private let device: SDLGPUDevice
    private var raw: OpaquePointer?
    private let lock = NSLock()
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Every resource the batch touched, kept alive until the fence signals.
    private var retained: [AnyObject]

    /// Test hook: fences released before their signal (always 0).
    nonisolated(unsafe) static var unsignalledReleaseCount = 0
    /// Test hook: blocking waits made on a thread other than the device's
    /// waiter thread (always 0).
    nonisolated(unsafe) static var foreignThreadWaitCount = 0
    private static let hookLock = NSLock()

    init(raw: OpaquePointer, device: SDLGPUDevice, retained: [AnyObject]) {
        self.raw = raw
        self.device = device
        self.retained = retained
    }

    /// Queues the wait on the waiter thread. Called once, at submission, so
    /// every fence is released after its signal whether or not anyone awaits it.
    func startWaiting(gate: DispatchSemaphore?) {
        device.waiterWorker.enqueue { [self] in
            _ = gate?.wait(timeout: .now() + 30)
            blockingWait()
            finish()
        }
    }

    /// Whether the GPU has finished the batch.
    public var isSignalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return signalled
    }

    /// Suspends until the batch has finished on the GPU. The wait happens on the
    /// waiter thread; cancelling the calling task neither ends the wait nor
    /// releases the fence early (it signals, then the waiter releases it).
    public func wait() async {
        SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUFence.wait")
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if signalled {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            // Nothing to do: the waiter thread owns the wait and the release.
        }
    }

    /// `SDL_WaitForGPUFences` on one fence; counts a call off the waiter thread.
    private func blockingWait() {
        if Thread.current !== device.waiterWorker.thread {
            Self.hookLock.lock(); Self.foreignThreadWaitCount += 1; Self.hookLock.unlock()
        }
        guard let handle = raw else { return }
        var fence: OpaquePointer? = handle
        _ = withUnsafePointer(to: &fence) { SDL_WaitForGPUFences(device.raw, true, $0, 1) }
    }

    /// The one place an SDL fence is released; counts a release made before the signal.
    private func releaseFence(_ fence: OpaquePointer) {
        if !isSignalled {
            Self.hookLock.lock(); Self.unsignalledReleaseCount += 1; Self.hookLock.unlock()
        }
        device.release { SDL_ReleaseGPUFence($0, fence) }
    }

    /// Marks the batch finished, releases the SDL fence (it has signalled) and
    /// the batch's resources, then resumes the awaiting tasks.
    private func finish() {
        lock.lock()
        signalled = true
        let toResume = waiters
        waiters = []
        let fence = raw
        raw = nil
        let resources = retained
        retained = []
        lock.unlock()
        if let fence { releaseFence(fence) }
        _ = resources
        for waiter in toResume { waiter.resume() }
    }
}
#endif
