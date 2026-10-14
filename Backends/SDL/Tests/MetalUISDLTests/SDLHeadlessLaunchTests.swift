import Foundation
import Testing
import MetalUICore
import SDLBridge
@_spi(Checks) @testable import MetalUISDL

// A supported headless launch (item S8; rulings `IC-J`...`IC-M`, `IC-P`; spec
// `docs/superpowers/specs/2026-10-14-cursors-headless-design.md` tests 18-21).
// `SDLPlatform(options: .headless)` hides every window and renders every
// window into an offscreen target, so an app's smoke test builds frames and
// runs its `.task` with no display. Every helper that creates an `SDLPlatform`
// arms the main-run-loop exit check on macOS.

@MainActor
private func platform(_ options: SDLPlatform.Options) throws -> SDLPlatform {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLPlatform(options: options)
}

/// **18** (`IC-J`). A `.headless` platform never shows its window and renders
/// offscreen; `.default` shows and presents.
///
/// Mutations: `.headless` with `rendersOffscreen` false (the offscreen
/// expectation reddens); `.headless` with `hidesWindows` false (the show stub
/// records an issue).
@MainActor
@Test func headlessOptionsHideWindowsAndRenderOffscreen() throws {
    #expect(SDLPlatform.Options.headless.hidesWindows)
    #expect(SDLPlatform.Options.headless.rendersOffscreen)
    #expect(!SDLPlatform.Options.default.hidesWindows)
    #expect(!SDLPlatform.Options.default.rendersOffscreen)

    let platform = try platform(.headless)
    #expect(platform.options == .headless)
    platform.showWindow = { _ in
        Issue.record("a headless platform showed its window")
        return true
    }
    let window = try platform.openSDLWindow(title: "IC-18", size: Size(width: 64, height: 64))
    #expect(!mui_window_is_shown(window.rawHandle))
    #expect(platform.options.rendersOffscreen, "a headless platform's window must render offscreen")
}

/// **19** (`IC-K`). The environment convenience reads exactly `"1"`.
///
/// Mutation: accept any non-empty value (`"0"` and `"true"` redden).
@Test func theEnvironmentConvenienceReadsOnlyTheValueOne() {
    typealias Options = SDLPlatform.Options
    #expect(Options.headlessIfRequested(environment: ["METALUI_SDL_HEADLESS": "1"]) == .headless)
    for value in ["0", "true", "", "yes", " 1", "11"] {
        #expect(Options.headlessIfRequested(environment: ["METALUI_SDL_HEADLESS": value]) == .default,
                "\(value.debugDescription) must not request headless")
    }
    #expect(Options.headlessIfRequested(environment: [:]) == .default)
    #expect(Options.headlessIfRequested(environment: ["OTHER": "1"]) == .default)
}

/// **21** (`IC-L`). The SPI spelling forwards to `init(options:)` field for field.
///
/// Mutation: the SPI init ignores `offscreenRenderers` (the second and third
/// cases redden; `MainQueueDrainCheck`'s offscreen mode reddens in the image).
@MainActor
@Test func theSPIInitialiserStillForwards() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let both = try SDLPlatform(hiddenWindows: true, offscreenRenderers: true)
    #expect(both.options == .headless)
    let offscreenOnly = try SDLPlatform(hiddenWindows: false, offscreenRenderers: true)
    #expect(offscreenOnly.options == SDLPlatform.Options(hidesWindows: false, rendersOffscreen: true))
    let hiddenOnly = try SDLPlatform(hiddenWindows: true)
    #expect(hiddenOnly.options == SDLPlatform.Options(hidesWindows: true, rendersOffscreen: false))
}

// MARK: - 20: the recipe in a process of its own

private func launchCheckExecutable() -> URL? {
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
    let name = "HeadlessLaunchCheck.exe"
    #else
    let name = "HeadlessLaunchCheck"
    #endif
    for directory in directories {
        let candidate = directory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    return nil
}

/// **20** (`IC-M`, `IC-P`). `HeadlessLaunchCheck` is the documented recipe,
/// written against public API with a plain import. It runs a `.task` in the
/// first frame and exits 0. The check bounds itself by loop iterations; this
/// test owns the child and, on a generous deadline, terminates that child only
/// and fails. Ungated: it runs in the Linux image under
/// `SDL_VIDEO_DRIVER=offscreen`.
///
/// Mutation: `.headless` without offscreen renderers (the check ends at its
/// iteration bound with `task ran=false`).
@Test func aHeadlessAppRunsItsTaskAndExits() throws {
    let executable = try #require(launchCheckExecutable(),
                                  "HeadlessLaunchCheck not found beside the test product - run `swift build` first")
    let process = Process()
    process.executableURL = executable
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let deadline = Date().addingTimeInterval(120)
    var timedOut = false
    while process.isRunning {
        if Date() > deadline { timedOut = true; process.terminate(); break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    print("IC-M HeadlessLaunchCheck: status=\(process.terminationStatus) timedOut=\(timedOut) output=\(text)")
    #expect(!timedOut, "the check outlived its deadline: \(text)")
    #expect(process.terminationStatus == 0, "the check exited abnormally: \(text)")
    #expect(text.contains("task ran=true"), "\(text)")
}
