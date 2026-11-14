#if os(macOS)
import Foundation

/// Keeps HIToolbox from stopping the test process's main run loop (record 304).
///
/// Swift Testing's outermost loop is `CFRunLoopRun`, and its return ends the process with exit 0 and no summary
/// line. A process that never ran `-[NSApplication run]` has no `CGEventQueue` enqueue-signal block, so
/// HIToolbox's event thread wakes the main thread by queueing `CFRunLoopStop(main)` (`SignalMainThread`)
/// whenever a real window sees window-server traffic; one that lands outside a nested run ends the run
/// mid-suite. Calling `-[NSApplication run]` once and stopping it, as the earlier workaround did, installs the
/// block on older systems and **nothing** on this one (macOS 27: `_SetCGEventQueueEnqueueSignalBlock` was
/// never called, and the unfiltered run still died). This installs a block that only wakes the loop.
///
/// Call it before opening any real `NSWindow` in a test (every helper that builds an `AppKitPlatform` or
/// `AppKitWindow` does). Idempotent. Test-only: it reaches a private HIToolbox symbol through `dlsym`, which
/// shipped code must not.
@discardableResult
public func installAppKitEventSignal() -> Bool { installed }

/// Whether HIToolbox's private setter exists and was called (`false`: the guard test fails, the workaround is inert).
private let installed: Bool = {
    // `RTLD_DEFAULT` is `(void *)-2`.
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_SetCGEventQueueEnqueueSignalBlock") else {
        return false
    }
    typealias Setter = @convention(c) (@escaping @convention(block) () -> Void) -> Void
    unsafeBitCast(symbol, to: Setter.self)({ CFRunLoopWakeUp(CFRunLoopGetMain()) })
    return true
}()
#endif
