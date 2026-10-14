// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation

/// A dedicated serial thread (ruling `GA-E`): a command buffer is recorded and
/// submitted on the thread that acquired it, and a fence is waited on a thread
/// whose blocking cannot starve the cooperative pool or stall the main actor.
/// A `Thread`, not a task: a blocking `SDL_WaitForGPUFences` would otherwise
/// occupy one of the pool's few threads.
final class SDLGPUWorker: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [@Sendable () -> Void] = []
    private var stopping = false
    /// The thread jobs run on (read by the fence hook to tell a wait made here
    /// from one made on the caller's thread).
    private(set) var thread: Thread?

    init(name: String) {
        let thread = Thread { [self] in run() }
        thread.name = name
        self.thread = thread
        thread.start()
    }

    /// Queues `job` after every earlier one.
    func enqueue(_ job: @escaping @Sendable () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    /// Ends the thread once the queue has drained. The thread holds the worker
    /// until then, so the owner must call this (a worker has no `deinit` end).
    func stop() {
        condition.lock()
        stopping = true
        condition.signal()
        condition.unlock()
    }

    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty && !stopping { condition.wait() }
            guard !jobs.isEmpty else { condition.unlock(); return }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }
}
#endif
