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
