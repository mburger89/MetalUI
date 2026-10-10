import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIPortableText
@testable import MetalUI
@testable import MetalUISDL
import SDLBridge

// Lifecycle modifiers on SDL (spec `2026-10-03-lifecycle-design.md` §5.3
// tests 10.2 and 10.3; rulings `LC-E`, `LC-J`, `LC-O` lane 2). Lifecycle lives
// entirely in `MetalUI` (spec §3.8: no new platform requirement), so these pin
// that the SDL platform reaches it through the same two doors AppKit does —
// `App.openWindow`'s first `drawFrameIfNeeded` (and every display-link tick
// after it) and the platform window's `onClose`. A real hidden `SDLPlatform`
// window; nothing here fakes SDL.

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

/// `SDLPlatform`, forwarded unchanged, remembering the windows `App` opens
/// through it — so a test can push SDL events at a window `App` owns.
@MainActor
private final class RecordingSDLPlatform: Platform {
    let base: SDLPlatform
    private(set) var opened: [SDLWindow] = []
    init(_ base: SDLPlatform) { self.base = base }
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = try base.openSDLWindow(title: title, size: size)
        opened.append(window)
        return window
    }
    func run() { base.run() }
    func setApplicationIcon(_ images: [ImageTexture]) { base.setApplicationIcon(images) }
    func setMenuBar(_ menuBar: PlatformMenuBar) { base.setMenuBar(menuBar) }
    // The app-shell requirements (ruling `AS-H` item 4), forwarded unchanged.
    var onTerminateRequest: (() -> CloseRequestReply)? {
        get { base.onTerminateRequest }
        set { base.onTerminateRequest = newValue }
    }
    func replyToTerminateRequest(_ shouldTerminate: Bool) { base.replyToTerminateRequest(shouldTerminate) }
    func terminate() { base.terminate() }
    var onOpenURLs: (([String]) -> Void)? {
        get { base.onOpenURLs }
        set { base.onOpenURLs = newValue }
    }
}

/// An `App` over a hidden-window `SDLPlatform`, drawing text with the
/// portable text system (required off macOS, `XP-B`).
@MainActor
private func lifecycleApp() throws -> (RecordingSDLPlatform, App) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = RecordingSDLPlatform(try SDLPlatform(hiddenWindows: true))
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    return (platform, app)
}

@MainActor
private final class LifecycleLog {
    var entries: [String] = []
}

/// A 30 × 10 box whose `onAppear` widens it to 70 — the write the first frame
/// must present (`F1`). Read back by its aspect ratio (3 before, 7 after), so
/// the window's scale factor does not enter.
private struct Widening: Component {
    let log: LifecycleLog
    @State var width: Float = 30

    var content: some ElementGroup {
        Box().frame(width: Pixels(width), height: Pixels(10)).background(.accent)
            .onAppear { log.entries.append("appear"); width = 70 }
            .onDisappear { log.entries.append("disappear") }
    }
}

/// Whether an `SDLPlatform` window can present a frame here. **Not under SDL's
/// `offscreen` video driver**, which CI's Linux image sets
/// (`Backends/SDL/linux/Dockerfile`, `SDL_VIDEO_DRIVER=offscreen`): there a
/// window never gets a swapchain drawable (`beginFrame()` answered `nil` on
/// ten consecutive loop passes, measured in that image) and its display link
/// never runs, so no window frame builds and no `onAppear` can run. Tests
/// 10.2 and 10.3 need a presented frame; they run on macOS and on Windows CI,
/// and are skipped there (record §76 §12).
private let windowsPresentFrames = ProcessInfo.processInfo.environment["SDL_VIDEO_DRIVER"] != "offscreen"

/// **10.2** (`LC-E` items 2–3, probe `F1`). An `SDLPlatform` window's first
/// frame — the `drawFrameIfNeeded` `App.openWindow` runs — runs the
/// `onAppear` after the build, outside every phase, and its `@State` write is
/// presented in that same frame by the settle build: the scene holds the
/// 70-wide box and not the 30-wide one, two builds ran, and the window is
/// clean. Then the loop's ticks run it no more.
///
/// Mutation: delete the drain call (`if drainLifecycle() { … }`) in
/// `Window.drawFrameIfNeeded`.
@MainActor
@Test(.enabled(if: windowsPresentFrames, "the offscreen video driver presents no window frame"))
func anOnAppearRunsInAnSDLWindowsFirstFrame() throws {
    let (platform, app) = try lifecycleApp()
    let log = LifecycleLog()
    let window = try app.openWindow(title: "lifecycle 10.2", size: Size(width: Pixels(200), height: Pixels(100))) {
        Column { Widening(log: log) }
    }
    #expect(log.entries == ["appear"], "the first frame ran the onAppear: \(log.entries)")
    let ratios = window.lastScene.rects.filter { $0.bounds.size.height > 0 }
        .map { $0.bounds.size.width / $0.bounds.size.height }
    #expect(ratios.contains(7) && !ratios.contains(3), "the write is presented in the first frame: \(ratios)")
    #expect(window.lastDrawBuildCount == 2, "the settle build")
    #expect(!window.needsRedraw, "and the window is clean")

    platform.base.run(maxIterations: 4)
    #expect(log.entries == ["appear"], "the loop's ticks run nothing more: \(log.entries)")
}

/// **10.3** (`LC-J` item 1, probe `W3`). Closing an `SDLPlatform` window —
/// SDL's close event reaching `SDLWindow.onClose`, which `App` set — runs the
/// present element's `onDisappear` once, and a second close event runs
/// nothing.
///
/// Mutation: remove the `window?.runDisappearancesForClose()` call from
/// `App.openWindow`'s `onClose` closure.
@MainActor
@Test(.enabled(if: windowsPresentFrames, "the offscreen video driver presents no window frame"))
func closingAnSDLWindowRunsItsOnDisappear() throws {
    let (platform, app) = try lifecycleApp()
    let log = LifecycleLog()
    try app.openWindow(title: "lifecycle 10.3", size: Size(width: Pixels(200), height: Pixels(100))) {
        Column { Widening(log: log) }
    }
    try #require(log.entries == ["appear"])
    let sdlWindow = try #require(platform.opened.first)
    platform.base.pumpEvents()   // whatever opening the window queued

    func close() {
        var event = MUIEvent(); event.kind = UInt32(MUI_EVENT_CLOSE); event.window_id = sdlWindow.id
        #expect(mui_push_event(&event))
        platform.base.pumpEvents()
    }
    close()
    #expect(log.entries == ["appear", "disappear"], "the close ran the onDisappear once: \(log.entries)")
    close()
    #expect(log.entries == ["appear", "disappear"], "a second close runs nothing: \(log.entries)")
}
