#if canImport(AppKit)
// Its own file so AppKit's names (its `AccessibilityRequest` among them) stay
// out of SDLPlatform.swift's type lookup.
import AppKit

extension SDLPlatform {
    /// Runs `-[NSApplication run]` once, stopping it at once, so AppKit
    /// installs its event-queue signal blocks (`NSUpdateCycleInitialize`,
    /// reached only from `run`; record §61 §9). SDL reads events through
    /// `nextEventMatchingMask` and never calls `run`, and without those blocks
    /// HIToolbox's event thread wakes the main thread by queueing a
    /// `CFRunLoopStop` of the main run loop — harmless inside ``run()``, but a
    /// host whose outermost loop is `CFRunLoopRun` (an `async` main, Swift
    /// Testing's executor) returns from it and exits. Skipped when AppKit is
    /// already running (`NSApp.isRunning`: its own `run` installed them).
    static func installAppKitEventSignal() {
        guard !appKitEventSignalInstalled, let app = NSApp, !app.isRunning else { return }
        appKitEventSignalInstalled = true
        let main = CFRunLoopGetMain()
        CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue) {
            app.stop(nil)
            // `stop` takes effect after the next event; post one so `run`
            // returns now rather than at the next real event.
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                             timestamp: 0, windowNumber: 0, context: nil,
                                             subtype: 0, data1: 0, data2: 0) {
                app.postEvent(wake, atStart: true)
            }
        }
        CFRunLoopWakeUp(main)
        app.run()
    }
}

@MainActor private var appKitEventSignalInstalled = false
#endif
