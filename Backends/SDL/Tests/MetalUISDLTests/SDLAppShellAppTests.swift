import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
@testable import MetalUI
@_spi(Checks) @testable import MetalUISDL
import SDLBridge

// App shell on SDL at the `App` level, lane 3, tests 3.1–3.3 (rulings `AS-B`
// item 6, `AS-C` items 2 and 8, `AS-G` items 2 and 5, `AS-K`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.3). An `App` over
// a real `SDLPlatform` with hidden windows that **render offscreen**
// (`offscreenRenderers`, `TF-C`), so each window's first frame builds — its
// `.onAppear`/`.onDisappear` presence and its `.onOpenURL` list exist — under
// every video driver, CI's Linux image's `offscreen` included: none of these
// is gated. Events go through SDL's own queue (`mui_push_event`,
// `mui_push_raw_drop_event` with the C-exported `mui_sdl_event_drop_*` types —
// never an SDL enum's `rawValue`, which is `Int32` on Windows). Lanes 1 and 2
// built the behaviour, so these arrive green; each is shown able to fail by
// the mutation its doc comment names (record §87).

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

/// `SDLPlatform`, forwarded unchanged, remembering the windows `App` opens and
/// the termination calls `App` makes — so a test can push SDL events at a
/// window `App` owns and see how `App` answered the platform.
@MainActor
private final class ShellRecordingPlatform: Platform {
    let base: SDLPlatform
    private(set) var opened: [SDLWindow] = []
    private(set) var replies: [Bool] = []
    private(set) var terminateCalls = 0
    init(_ base: SDLPlatform) { self.base = base }
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = try base.openSDLWindow(title: title, size: size)
        opened.append(window)
        return window
    }
    func run() { base.run() }
    func setApplicationIcon(_ images: [ImageTexture]) { base.setApplicationIcon(images) }
    func setMenuBar(_ menuBar: PlatformMenuBar) { base.setMenuBar(menuBar) }
    var onTerminateRequest: (() -> CloseRequestReply)? {
        get { base.onTerminateRequest }
        set { base.onTerminateRequest = newValue }
    }
    func replyToTerminateRequest(_ shouldTerminate: Bool) {
        replies.append(shouldTerminate)
        base.replyToTerminateRequest(shouldTerminate)
    }
    func terminate() {
        terminateCalls += 1
        base.terminate()
    }
    var onOpenURLs: (([String]) -> Void)? {
        get { base.onOpenURLs }
        set { base.onOpenURLs = newValue }
    }
}

/// An `App` over a hidden-window, offscreen-rendering `SDLPlatform`, drawing
/// text with the portable text system (required off macOS, `XP-B`).
@MainActor
private func shellApp() throws -> (ShellRecordingPlatform, App) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = ShellRecordingPlatform(try SDLPlatform(hiddenWindows: true, offscreenRenderers: true))
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    platform.base.pumpEvents()
    return (platform, app)
}

@MainActor
private final class ShellLog {
    var entries: [String] = []
}

/// Opens a window whose root holds one box logging its `onDisappear` as
/// `"<name> disappeared"`, and answers it with its `SDLWindow`.
@MainActor
private func openLoggedWindow(_ app: App, _ platform: ShellRecordingPlatform, _ name: String,
                              _ log: ShellLog) throws -> (Window, SDLWindow) {
    let window = try app.openWindow(title: name, size: Size(width: Pixels(120), height: Pixels(80))) {
        Column {
            Box().frame(width: Pixels(20), height: Pixels(20)).background(.accent)
                .onDisappear { log.entries.append("\(name) disappeared") }
        }
    }
    platform.base.pumpEvents()
    return (window, try #require(platform.opened.last))
}

private func push(_ kind: Int32, window: UInt32 = 0, sourceLocation: SourceLocation = #_sourceLocation) {
    var event = MUIEvent(); event.kind = UInt32(kind); event.window_id = window
    #expect(mui_push_event(&event), "push kind \(kind)", sourceLocation: sourceLocation)
}

/// **3.1** (`AS-C` items 2 and 8, `AS-K`). With no `App.onTerminateRequest`,
/// `SDL_EVENT_QUIT` asks each window in turn: A answers `.later`, so the quit
/// waits on A — the loop runs on (both windows open after five passes) and
/// nobody has answered the platform. A's `replyToCloseRequest(true)` closes A
/// and resumes the walk: B (no handler) closes, the platform is answered
/// `true` once, the next `run(maxIterations:)` ends with no window, and each
/// window's `onDisappear` ran once.
///
/// Mutation: the walk never resumes on the reply → red.
@MainActor
@Test func anSDLAppAsksOnQuitAndEndsOnTheWindowsReply() throws {
    let (platform, app) = try shellApp()
    let log = ShellLog()
    let (a, _) = try openLoggedWindow(app, platform, "A", log)
    let (b, _) = try openLoggedWindow(app, platform, "B", log)
    var asked = 0
    a.onCloseRequest = { asked += 1; return .later }

    push(Int32(MUI_EVENT_QUIT))
    platform.base.run(maxIterations: 5)
    #expect(asked == 1 && a.isCloseRequestPending, "the quit asked A, which deferred")
    #expect(platform.base.openWindowCount == 2, "the loop ran on with both windows")
    #expect(platform.replies.isEmpty && platform.terminateCalls == 0 && log.entries.isEmpty)

    a.replyToCloseRequest(true)
    #expect(platform.base.openWindowCount == 0, "A closed and the walk closed B")
    #expect(platform.replies == [true] && platform.terminateCalls == 0, "replies \(platform.replies)")
    #expect(log.entries == ["A disappeared", "B disappeared"], "\(log.entries)")
    platform.base.run(maxIterations: 5)
    #expect(platform.base.openWindowCount == 0)
    #expect(log.entries.count == 2, "each onDisappear once")
    withExtendedLifetime((a, b)) {}
}

/// **3.2** (`AS-B` items 2 and 6, `AS-C` item 5). `SDL_EVENT_WINDOW_CLOSE_REQUESTED`
/// on the only window asks its `onCloseRequest`: `.cancel` keeps the window
/// and the app (no `onDisappear`, no terminate); `.now` closes it, its
/// `onDisappear` runs once, and the last window's close ends the app asking
/// nobody (`terminate()` once).
@MainActor
@Test func anSDLWindowCloseVetoKeepsTheAppRunning() throws {
    let (platform, app) = try shellApp()
    let log = ShellLog()
    let (window, sdl) = try openLoggedWindow(app, platform, "A", log)
    // A box: the handler is a main-actor closure, and a captured local
    // mutated after capture warns on Linux.
    @MainActor final class Script { var answer = CloseRequestReply.cancel; var asked = 0 }
    let script = Script()
    window.onCloseRequest = { script.asked += 1; return script.answer }

    push(Int32(MUI_EVENT_CLOSE), window: sdl.id)
    platform.base.pumpEvents()
    #expect(script.asked == 1 && platform.base.openWindowCount == 1, "a vetoed close keeps the window")
    #expect(log.entries.isEmpty && platform.terminateCalls == 0)

    script.answer = .now
    push(Int32(MUI_EVENT_CLOSE), window: sdl.id)
    platform.base.pumpEvents()
    #expect(script.asked == 2 && platform.base.openWindowCount == 0, "an allowed close closes it")
    #expect(log.entries == ["A disappeared"] && platform.terminateCalls == 1, "\(log.entries)")
    #expect(platform.replies.isEmpty, "the last close asks nobody and answers nothing")
}

/// **3.3** (`AS-G` items 2 and 5). A file dropped on the application — SDL's
/// `SDL_EVENT_DROP_FILE` on window 0, then its `DROP_COMPLETE` — reaches the
/// window's `.onOpenURL` as a file URL, and a URL string as itself; the app's
/// catch-all hears nothing while a window handles it.
@MainActor
@Test func anSDLAppDeliversAnAppLevelFileDropToOnOpenURL() throws {
    let (platform, app) = try shellApp()
    var opened: [String] = [], caughtAll: [String] = []
    app.onOpenURL = { caughtAll.append($0.absoluteString) }
    let window = try app.openWindow(title: "Doc", size: Size(width: Pixels(120), height: Pixels(80))) {
        Column {
            Box().frame(width: Pixels(20), height: Pixels(20))
                .onOpenURL { opened.append($0.absoluteString) }
        }
    }
    platform.base.pumpEvents()
    for (type, data) in [(mui_sdl_event_drop_file, "/tmp/a b.mcgraph"), (mui_sdl_event_drop_file, "metalcreator://doc/1")] {
        #expect(data.withCString { mui_push_raw_drop_event(type, 0, 0, 0, $0) })
    }
    #expect(mui_push_raw_drop_event(mui_sdl_event_drop_complete, 0, 0, 0, nil))
    platform.base.pumpEvents()
    #expect(opened == ["file:///tmp/a%20b.mcgraph", "metalcreator://doc/1"], "\(opened)")
    #expect(caughtAll.isEmpty, "\(caughtAll)")
    withExtendedLifetime(window) {}
}
