// The SDL main-queue drain, checked in a process of its own (ruling `SV-H`
// item 3; spec tests 1.18 and 1.19, `SDLMainQueueDrainTests`). **Top-level
// code** — the shape every MetalUI `main.swift` has and the one probe `B2`
// measured: a Swift Testing test is itself a main-actor job, inside which no
// drain can run main-actor work (`J1`), so the loop is driven from here.
//
// `MainQueueDrainCheck task`: a main-actor `Task` created before the loop runs
// and resumes after a yield; prints `task ran=<Bool> resumed=<Bool>`.
// `MainQueueDrainCheck dialog`: a main-actor `Task` awaits a file dialog's
// answer through `SDLWindow.onInput`; the bridge's test hook answers it from
// another thread (`SV-G` item 3); prints `dialog paths=[…]` (empty when the
// task never resumed). Both bound the loop by an iteration count — a running
// display link makes every pass non-blocking — and stop it as soon as the
// task finishes. Each prints the passes it took.
//
// `.task` (ruling `PX-L` item 2; spec tests 3.20 and 3.21), each printing
// `task started=<Bool> steps=<n> cancelled=<Bool>`:
// `MainQueueDrainCheck task-modifier`: an `App` over this `SDLPlatform` whose
// root's `.task` yields three times, removes its own content and awaits its
// cancellation — which the next frame's lifecycle drain issues. It needs a
// presented frame, so its test is gated off SDL's offscreen driver.
// `MainQueueDrainCheck immediate-task`: top-level code starts
// `Task.immediate { @MainActor in … }` (what the modifier's start does) before
// the loop; it yields three times and awaits a cancellation a later
// display-link tick issues. Needs no frame: it runs in the Linux container.
//
// No `armMainRunLoopExitCheck()` here: that `atexit` check guards a TEST
// process whose outermost loop must not return (record §61 §9); this process
// is meant to exit when its loop returns, and the check would turn that exit
// into a failure. The test process that launches it creates no SDLPlatform.
import Foundation
import Observation
import MetalUICore
import MetalUIPlatform
import MetalUISDL
import SDLBridge
import MetalUI
import MetalUIPortableText

/// What a `.task` check saw, written only on the main actor.
@Observable @MainActor final class TaskCheck {
    var shown = true
    var started = false
    var steps = 0
    var cancelled = false
    var line: String { "task started=\(started) steps=\(steps) cancelled=\(cancelled)" }
}

/// Suspends the calling task until it is cancelled, then records it; the
/// `onCancel` runs inside the `cancel()` call, on the main thread.
@MainActor final class CancelWait {
    var continuation: CheckedContinuation<Void, Never>?
}
@MainActor func awaitCancellation(_ check: TaskCheck) async {
    let wait = CancelWait()
    await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if Task.isCancelled { continuation.resume() } else { wait.continuation = continuation }
        }
    } onCancel: {
        MainActor.assumeIsolated {
            wait.continuation?.resume()
            wait.continuation = nil
        }
    }
    check.cancelled = Task.isCancelled
}

/// The portable text system over the repository's Noto Sans — `App` needs a
/// `TextSystem` off Apple platforms (`XP-B`).
@MainActor func portableTextSystem() throws -> PortableTextSystem {
    let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fonts/NotoSans-Regular.ttf")
    let resolver = try PortableFontResolver(defaultFont: [UInt8](try Data(contentsOf: fonts)))
    return PortableTextSystem(resolver: resolver)
}

let mode = CommandLine.arguments.dropFirst().first ?? "task"
// Generous: under SDL's offscreen driver a pass does almost nothing (no frame
// presents), and on Linux main-queue work enqueued by a pass is serviced some
// passes later (measured in `swift:6.4-noble`: a task created before the loop
// ran and resumed after 36 to 133 passes over two runs, a dialog answer after
// 44 — and once not within 400; on macOS after 2 and 5), so a small bound reads a
// working drain as a broken one. A loop that never drains still ends here.
let iterationLimit = 200_000

let platform = try SDLPlatform(hiddenWindows: true)
let window = try platform.openSDLWindow(title: "MainQueueDrainCheck",
                                        size: Size(width: Pixels(64), height: Pixels(64)))
var iterations = 0
window.startDisplayLink { _ in
    iterations += 1
    if iterations >= iterationLimit { platform.stop() }
}

switch mode {
case "task-modifier":
    let check = TaskCheck()
    let textSystem = try portableTextSystem()
    let app = App(platform: platform, textSystem: { textSystem })
    try app.openWindow(title: "task-modifier", size: Size(width: Pixels(64), height: Pixels(64))) {
        Column {
            if check.shown {
                Box().frame(width: Pixels(20), height: Pixels(20)).background(.accent)
                    .task {
                        check.started = true
                        for _ in 0..<3 {
                            await Task.yield()
                            check.steps += 1
                        }
                        check.shown = false
                        await awaitCancellation(check)
                        platform.stop()
                    }
            }
        }
    }
    app.run()
    print("\(check.line) iterations=\(iterations)")
case "immediate-task":
    let check = TaskCheck()
    let operation: @MainActor () async -> Void = {
        check.started = true
        for _ in 0..<3 {
            await Task.yield()
            check.steps += 1
        }
        await awaitCancellation(check)
        platform.stop()
    }
    let handle: Task<Void, Never>
    if #available(macOS 26.0, *) {
        handle = Task.immediate { @MainActor in await operation() }
    } else {
        handle = Task { @MainActor in await operation() }
    }
    // A later display-link tick issues the cancel, once the task has stepped.
    window.startDisplayLink { _ in
        iterations += 1
        if check.steps == 3, !handle.isCancelled { handle.cancel() }
        if iterations >= iterationLimit { platform.stop() }
    }
    platform.run()
    print("\(check.line) iterations=\(iterations)")
case "dialog":
    var paths: [String] = []
    Task { @MainActor in
        paths = await withCheckedContinuation { continuation in
            window.onInput = { event in
                if case .fileDialogResult(let result) = event, result.token == 7,
                   case .chosen(let chosen) = result.outcome {
                    continuation.resume(returning: chosen)
                }
                return true
            }
            _ = mui_test_complete_dialog(window.id, 7, "/tmp/drain check.json", 1)
        }
        platform.stop()
    }
    platform.run()
    print("dialog paths=[\(paths.joined(separator: ", "))] iterations=\(iterations)")
default:
    var ran = false, resumed = false
    Task { @MainActor in
        ran = true
        await Task.yield()
        resumed = true
        platform.stop()
    }
    platform.run()
    print("task ran=\(ran) resumed=\(resumed) iterations=\(iterations)")
}
