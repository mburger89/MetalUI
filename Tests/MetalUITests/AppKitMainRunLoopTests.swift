import MetalUITestSupport
import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

@MainActor private final class QuietSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

/// Window-server traffic must never stop the test process's main run loop (record 304). A process that has
/// not run `-[NSApplication run]` has no `CGEventQueue` enqueue-signal block, so HIToolbox's event thread
/// queues `CFRunLoopStop(main)` for each burst of events; a stop that reaches Swift Testing's outermost
/// `CFRunLoopRun` ends the whole run with exit 0 and no summary line. `installAppKitEventSignal()` (called by
/// every AppKit test helper) swaps that for a wake. Here: open real windows, pump a nested run, and expect it
/// to time out rather than be stopped. Mutation: have `installAppKitEventSignal()` return without calling the
/// setter → the first expectation fails (the pump alone reports a stop only after the long unfiltered
/// sequence of tests that precedes the real failure, so the setter's presence is the pin).
@MainActor
@Test func windowServerTrafficNeverStopsTheMainRunLoop() throws {
    #expect(installAppKitEventSignal(), "HIToolbox's _SetCGEventQueueEnqueueSignalBlock exists; without it the workaround is inert")
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    var stopped = 0
    for _ in 0..<20 {
        let platform = AppKitPlatform(device: device, accessibilitySignal: { QuietSignal() })
        let window = try platform.openWindow(title: "run-loop \(UUID().uuidString)",
                                             size: Size(width: Pixels(200), height: Pixels(100)))
        let nsWindow = try #require((window as? AppKitWindow)?.window)
        for step in 0..<4 {   // moves, resizes and key changes: the traffic the event thread sees
            nsWindow.setFrameOrigin(NSPoint(x: 40 + 15 * step, y: 40 + 10 * step))
            nsWindow.setContentSize(NSSize(width: 200 + 10 * step, height: 100))
            nsWindow.makeKeyAndOrderFront(nil)
            if CFRunLoopRunInMode(.defaultMode, 0.03, false) == .stopped { stopped += 1 }
        }
        window.close()
        if CFRunLoopRunInMode(.defaultMode, 0.02, false) == .stopped { stopped += 1 }
    }
    #expect(stopped == 0, "the main run loop was stopped \(stopped) times by window-server traffic")
}
