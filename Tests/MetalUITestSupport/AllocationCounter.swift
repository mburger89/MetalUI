#if canImport(Darwin)
import Darwin

// PA-J: the one thread-filtered allocation counter of the test targets that count a kernel's heap work.
// libmalloc's `malloc_logger` is process-wide, so it counts only allocations made on the thread that asked
// (Swift Testing runs a main-actor test on a pool thread, and the runtime's own threads allocate too).
// Pins built on it are differential (N elements against 5N), never absolute numbers.

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// `MALLOC_LOG_TYPE_ALLOCATE` from libmalloc.
private let mallocLogTypeAllocate: UInt32 = 2

nonisolated(unsafe) private var allocationsSeen = 0
nonisolated(unsafe) private var countedThread: pthread_t?
nonisolated(unsafe) private var chainedLogger: MallocLogger?

/// Runs inside malloc on every thread; must not allocate.
nonisolated(unsafe) private let countingLogger: MallocLogger = { type, a1, a2, a3, result, skip in
    if type & mallocLogTypeAllocate != 0,
       let thread = countedThread, pthread_equal(thread, pthread_self()) != 0 {
        allocationsSeen += 1
    }
    chainedLogger?(type, a1, a2, a3, result, skip)
}

/// The heap allocations `body` makes on the calling thread, or `nil` when libmalloc no longer exports its logger
/// (a caller `#require`s a value: replace the instrument, do not skip it). Not re-entrant, and no test may run
/// another counter at once (`--no-parallel`).
public func countAllocations(_ body: () -> Void) -> Int? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
    let slot = symbol.assumingMemoryBound(to: MallocLogger?.self)
    _ = countingLogger
    _ = mallocLogTypeAllocate
    chainedLogger = slot.pointee
    allocationsSeen = 0
    countedThread = pthread_self()
    slot.pointee = countingLogger
    body()
    slot.pointee = chainedLogger
    countedThread = nil
    return allocationsSeen
}

/// Runs `body` on a second thread and answers the allocations the **calling** thread made meanwhile (the
/// separating arm of the counter's own test: a foreign thread's allocations are not counted).
public func countAllocationsIgnoringAnotherThread(_ foreign: @escaping @Sendable () -> Void) -> Int? {
    countAllocations {
        let thread = Thread(foreign)
        thread.join()
    }
}

private final class Thread: @unchecked Sendable {
    private var handle: pthread_t?
    private let work: @Sendable () -> Void
    init(_ work: @escaping @Sendable () -> Void) {
        self.work = work
        let box = Unmanaged.passRetained(self).toOpaque()
        pthread_create(&handle, nil, { raw in
            let me = Unmanaged<Thread>.fromOpaque(raw).takeRetainedValue()
            me.work()
            return nil
        }, box)
    }
    func join() { if let handle { pthread_join(handle, nil) } }
}
#endif
