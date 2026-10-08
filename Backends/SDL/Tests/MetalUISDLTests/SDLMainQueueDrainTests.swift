import Foundation
import Testing

// The SDL main-queue drain (gap 10), lane 1, tests 1.18–1.20 (ruling `SV-H`;
// spec `docs/superpowers/specs/2026-10-04-platform-services-design.md` §6.1).
// **The loop runs in a process of its own** — the `MainQueueDrainCheck`
// executable, top-level code, the shape `B2` measured: a Swift Testing test is
// itself a main-actor job, and inside one the drain starves every main-actor
// task (`J1`), so the test could not tell a working loop from a broken one.
// The executable is found beside this test product in the build directory; its
// absence **fails**, never skips (`swift build` builds it; CI and the
// container recipe run `swift build` before `swift test`).

/// The build directory's `MainQueueDrainCheck`, searched for beside every
/// candidate this process knows about: its own executable, the `.xctest`
/// bundles loaded (macOS), and any `.xctest` path on its command line.
private func drainCheckExecutable() -> URL? {
    var directories: [URL] = []
    if let main = Bundle.main.executableURL { directories.append(main.deletingLastPathComponent()) }
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        directories.append(URL(fileURLWithPath: bundle.bundlePath).deletingLastPathComponent())
    }
    for argument in CommandLine.arguments where argument.contains(".xctest") {
        var url = URL(fileURLWithPath: argument)
        while url.pathComponents.count > 1, !url.lastPathComponent.hasSuffix(".xctest") {
            url.deleteLastPathComponent()
        }
        directories.append(url.deletingLastPathComponent())
    }
    #if os(Windows)
    let name = "MainQueueDrainCheck.exe"
    #else
    let name = "MainQueueDrainCheck"
    #endif
    for directory in directories {
        let candidate = directory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    return nil
}

/// Runs the check in `mode` and returns its standard output, or `nil` with an
/// issue recorded when it cannot be found or exits abnormally. Bounded: the
/// check's loop is bounded by an iteration count, and its own exit ends it.
private func runDrainCheck(_ mode: String) throws -> String {
    let executable = try #require(drainCheckExecutable(),
                                  "MainQueueDrainCheck not found beside the test product — run `swift build` first")
    let process = Process()
    process.executableURL = executable
    process.arguments = [mode]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    print("SV-H MainQueueDrainCheck \(mode): status=\(process.terminationStatus) output=\(text)")
    #expect(process.terminationStatus == 0, "the check exited abnormally: \(text)")
    return text
}

/// **1.18** (`SV-H` items 1–3, `B2`). A main-actor `Task` created from
/// top-level code before `SDLPlatform.run()` runs, and resumes after a yield,
/// while the SDL loop runs.
///
/// Mutation **M1.18**: delete the drain line in `run(maxIterations:)` — red in
/// the Linux container; whether macOS reddens is recorded (SDL's Cocoa pump
/// may drain the queue itself).
@Test func theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode() throws {
    let output = try runDrainCheck("task")
    #expect(output.contains("task ran=true resumed=true"), "\(output)")
}

/// **1.19** (`SV-H` item 3, `SV-G` item 3). A task awaiting a dialog's answer
/// resumes when the answer arrives from another thread: the hook completes the
/// dialog off the main thread, the loop's pump delivers it, and the awaiting
/// task prints the paths it was handed.
///
/// Mutation **M1.19**: delete the drain line (red on Linux).
@Test func aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask() throws {
    let output = try runDrainCheck("dialog")
    #expect(output.contains("dialog paths=[/tmp/drain check.json]"), "\(output)")
}

/// **1.20** (`SV-H` item 3). The check's product path resolves — its failure
/// is the instrument's, not the loop's.
@Test func theDrainCheckExecutableIsFound() {
    #expect(drainCheckExecutable() != nil, "MainQueueDrainCheck not found — run `swift build` first")
}

// MARK: - `.task` under the SDL loop (ruling `PX-L` item 2; spec tests 3.20, 3.21)

/// Whether an `SDLPlatform` window presents a frame here — not under SDL's
/// `offscreen` video driver, which CI's Linux image sets (the same gate as
/// `SDLLifecycleTests`' tests 10.2 and 10.3).
private let windowsPresentFrames = ProcessInfo.processInfo.environment["SDL_VIDEO_DRIVER"] != "offscreen"

/// **3.20** (`PX-F`, `PX-L` item 2). A `.task` on an `App` window's root,
/// under `SDLPlatform`, starts with the first frame, progresses through three
/// yields while the loop runs, removes its own content and is cancelled by
/// the next frame's lifecycle drain. Gated off the offscreen driver: it needs
/// a presented frame (`PX-R` item 4 — no CI job runs it; its macOS line is in
/// record §80).
///
/// Mutation **M3.20**: delete the disappearance cancel (`cancelled=false`, a
/// loop that ends by its bound); `Task` for `Task.immediate` — recorded in
/// `PX-U`.
@Test(.enabled(if: windowsPresentFrames, "the offscreen video driver presents no window frame"))
func aTaskModifierProgressesAndIsCancelledUnderSDLPlatform() throws {
    let output = try runDrainCheck("task-modifier")
    #expect(output.contains("task started=true steps=3 cancelled=true"), "\(output)")
}

/// **3.20b** (ruling `TF-C`). 3.20's tree and line with every window
/// rendering into an offscreen target (`SDLPlatform`'s `package`
/// `offscreenRenderers`), so frames build and the lifecycle drain runs with no
/// presented frame: ungated, it runs `.task`'s start, progress and cancel
/// under the SDL loop in CI's Linux image. Red before, in the image: the mode
/// over the swapchain path prints `task started=false steps=0
/// cancelled=false` (the separating arm). The test process creates no
/// `SDLPlatform` (the check executable does, unarmed by its header).
///
/// Mutations **MT3.1** (delete the disappearance cancel: `cancelled=false`),
/// **MT3.2** (`SDLPlatform` ignores `offscreenRenderers`: `started=false` in
/// the image), **MT3.3** (delete `drainMainQueue()`'s calls in
/// `SDLPlatform.run`: `steps=0` in the image) — recorded in `TF-` and record §84.
@Test func aTaskModifierProgressesAndIsCancelledUnderSDLWithoutAPresentedFrame() throws {
    let output = try runDrainCheck("task-modifier-offscreen")
    #expect(output.contains("task started=true steps=3 cancelled=true"), "\(output)")
}

/// **3.21** (`PX-G`, `SV-H`, `PX-L` item 2). A main-actor `Task.immediate`
/// started from top-level code before the loop — what `.task`'s start does —
/// resumes three times and sees the cancellation a later display-link tick
/// issues. Needs no frame: ungated, it runs in the Linux container.
///
/// Mutation **M3.21**: delete `drainMainQueue()`'s calls in `SDLPlatform.run`
/// — the container prints `steps=0` (`SV-H`'s separating run); the macOS
/// result is recorded in `PX-U`.
@Test func anImmediateMainActorTaskResumesAndSeesItsCancellationUnderTheSDLLoop() throws {
    let output = try runDrainCheck("immediate-task")
    #expect(output.contains("task started=true steps=3 cancelled=true"), "\(output)")
}
