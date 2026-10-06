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
import MetalUICore
import MetalUIPlatform
import MetalUISDL
import SDLBridge

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
