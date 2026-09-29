#if os(macOS)
import Testing
import CoreFoundation
import Darwin
import MetalUICore
@testable import MetalUISDL

// The main run loop and HIToolbox's wake (record §61 §9). SDL on macOS reads
// events through `-[NSApplication nextEventMatchingMask:…]` but never calls
// `-[NSApplication run]`, so AppKit never installs its event-queue signal
// block (`NSUpdateCycleInitialize`, reached only from `run`). Without it,
// HIToolbox's event thread wakes the main thread by queueing a block that
// calls `CFRunLoopStop` on the main run loop — harmless inside SDL's own
// loop, fatal to a host whose OUTERMOST loop is `CFRunLoopRun`: Swift
// Testing's main executor returns from it and `exit(0)`s, so the SDL test
// target lost its last tests and its summary line while exiting 0.

/// Makes the loss loud if it ever comes back by another route: an `atexit`
/// check that the process is not exiting because the main run loop RETURNED.
/// Swift Testing's own exit is called from a job the main run loop is running
/// (its current mode is set); an exit after `CFRunLoopRun` returned finds no
/// current mode, and turns the silent `exit(0)` into `exit(1)` with a message.
/// Armed by every test here that initialises SDL video.
@MainActor func armMainRunLoopExitCheck() {
    guard !mainRunLoopExitCheckArmed else { return }
    mainRunLoopExitCheckArmed = true
    installMainRunLoopExitCheck()
}

/// Nonisolated, so the C callback carries no main-actor isolation check to
/// trap on at exit.
private func installMainRunLoopExitCheck() {
    atexit {
        guard pthread_main_np() != 0, CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) == nil else { return }
        fputs("error: the main run loop returned and the process is exiting before the test run finished "
              + "(record §61 §9) — failing instead of exiting 0\n", stderr)
        _exit(1)
    }
}
@MainActor private var mainRunLoopExitCheckArmed = false

/// Window-server traffic (a window opened, drawn to and dropped) never stops
/// the main run loop: each nested run below ends by timing out, never
/// `.stopped`. Before the fix 25 to 35 of the forty runs read `.stopped` —
/// the same stop that, reaching Swift Testing's outermost loop, ended the
/// process.
@MainActor
@Test func windowServerTrafficNeverStopsTheMainRunLoop() throws {
    armMainRunLoopExitCheck()
    let platform = try SDLPlatform(hiddenWindows: true)
    var results: [CFRunLoopRunResult] = []
    for index in 0..<40 {
        do {
            let window = try platform.openSDLWindow(title: "run loop \(index)",
                                                    size: Size(width: Pixels(50), height: Pixels(50)))
            platform.pumpEvents()
            _ = window.renderer
        }
        results.append(CFRunLoopRunInMode(.defaultMode, 0.05, false))
    }
    try #require(results.count == 40)
    let stopped = results.filter { $0 == .stopped }.count
    #expect(stopped == 0, "the main run loop was stopped \(stopped) times in 40 runs")
}
#endif
