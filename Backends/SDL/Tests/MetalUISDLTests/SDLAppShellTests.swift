import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// App shell on SDL, lane 1, tests 1.12–1.17 (rulings `AS-B` item 6, `AS-C`
// item 8, `AS-D` item 5, `AS-E` item 6, `AS-G` item 5, `AS-J` item 2, `AS-L`;
// spec `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.1). A real
// hidden `SDLPlatform` window; events go through SDL's own queue
// (`mui_push_event`, `mui_push_raw_drop_event` with the C-exported
// `mui_sdl_event_drop_*` types — never an SDL enum's `rawValue` in Swift, which
// is `Int32` on Windows). None needs a presented frame, so none is gated on
// the offscreen driver: the display link here is the test's own tick closure,
// which `run(maxIterations:)` calls whatever the driver. Red before: the file
// does not compile at `cd0b143`.

@MainActor
private func shellPlatform() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI app shell test",
                                            size: Size(width: Pixels(200), height: Pixels(100)))
    platform.pumpEvents()   // whatever opening the window queued
    return (platform, window)
}

private func push(_ kind: Int32, window: UInt32 = 0, sourceLocation: SourceLocation = #_sourceLocation) {
    var event = MUIEvent(); event.kind = UInt32(kind); event.window_id = window
    #expect(mui_push_event(&event), "push kind \(kind)", sourceLocation: sourceLocation)
}

private func pushDrop(_ type: UInt32, _ window: UInt32, _ data: String? = nil,
                      sourceLocation: SourceLocation = #_sourceLocation) {
    let pushed = data.map { $0.withCString { mui_push_raw_drop_event(type, window, 0, 0, $0) } }
        ?? mui_push_raw_drop_event(type, window, 0, 0, nil)
    #expect(pushed, "push drop type \(type)", sourceLocation: sourceLocation)
}

/// **1.12** (`AS-B` item 6). A close request — `SDL_EVENT_WINDOW_CLOSE_REQUESTED`
/// through SDL's queue — asks `onCloseRequest`: `false` keeps the window in
/// the platform and fires no `onClose`; `true` closes it, `onClose` once.
///
/// Mutation: ignore the handler → red.
@MainActor
@Test func sdlACloseRequestAsksTheWindowAndAVetoKeepsItOpen() throws {
    let (platform, window) = try shellPlatform()
    var asked = 0, closed = 0, answer = false
    window.onCloseRequest = { asked += 1; return answer }
    window.onClose = { closed += 1 }
    push(Int32(MUI_EVENT_CLOSE), window: window.id)
    platform.pumpEvents()
    #expect(asked == 1)
    #expect(platform.openWindowCount == 1 && closed == 0, "a vetoed close keeps the window")
    answer = true
    push(Int32(MUI_EVENT_CLOSE), window: window.id)
    platform.pumpEvents()
    #expect(asked == 2)
    #expect(platform.openWindowCount == 0 && closed == 1, "an allowed close closes it, onClose once")
}

/// **1.13** (`AS-L`). After `SDLPlatform`'s initialisation
/// `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE` reads `"0"`, so a vetoed WM close of
/// the last visible window sends no `SDL_EVENT_QUIT`. (A pushed close never
/// reaches SDL's quit logic, so the behaviour itself is human check AS10.)
///
/// Mutation: remove the hint → red.
@MainActor
@Test func sdlInitTurnsOffQuitOnLastWindowClose() throws {
    _ = try shellPlatform()
    let hint = mui_quit_on_last_window_close_hint().map { String(cString: $0) }
    #expect(hint == "0", "the hint: \(hint ?? "unset")")
}

/// **1.14** (`AS-C` item 8). `SDL_EVENT_QUIT` asks `onTerminateRequest`:
/// `.cancel` keeps the loop running (all three passes tick), `.now` stops it
/// after the pass that saw the quit, `.later` runs on until
/// `replyToTerminateRequest(true)`; `false` keeps it running.
///
/// Mutation: QUIT calls `stop()` unconditionally → red.
@MainActor
@Test func sdlQuitAsksOnTerminateRequest() throws {
    let (platform, window) = try shellPlatform()
    var ticks = 0, asked = 0
    var onTick: (Int) -> Void = { _ in }
    window.startDisplayLink { _ in ticks += 1; onTick(ticks) }

    var answer = CloseRequestReply.cancel
    platform.onTerminateRequest = { asked += 1; return answer }
    push(Int32(MUI_EVENT_QUIT))
    platform.run(maxIterations: 3)
    #expect(asked == 1 && ticks == 3, "a cancelled quit keeps the loop running: asked \(asked), ticks \(ticks)")

    ticks = 0; asked = 0; answer = .now
    push(Int32(MUI_EVENT_QUIT))
    platform.run(maxIterations: 3)
    #expect(asked == 1 && ticks == 1, "an approved quit stops the loop: asked \(asked), ticks \(ticks)")

    ticks = 0; asked = 0; answer = .later
    onTick = { tick in
        if tick == 2 { platform.replyToTerminateRequest(false) }
        if tick == 3 { platform.replyToTerminateRequest(true) }
    }
    push(Int32(MUI_EVENT_QUIT))
    platform.run(maxIterations: 6)
    #expect(asked == 1 && ticks == 3, "a deferred quit ends at the approving reply: asked \(asked), ticks \(ticks)")

    ticks = 0; onTick = { _ in }
    platform.replyToTerminateRequest(true)
    platform.run(maxIterations: 2)
    #expect(ticks == 2, "a reply with nothing pending does nothing: ticks \(ticks)")
}

/// **1.15** (`AS-B` item 6). `close()` hides the window, removes it from the
/// platform and fires `onClose` once; a second `close()` runs nothing; the
/// handler is not asked.
///
/// Mutation: `close()` leaves the window in the platform → red.
@MainActor
@Test func sdlCloseHidesRemovesAndFiresOnCloseOnce() throws {
    let (platform, window) = try shellPlatform()
    var closed = 0, asked = 0
    window.onClose = { closed += 1 }
    window.onCloseRequest = { asked += 1; return false }
    window.close()
    #expect(closed == 1 && platform.openWindowCount == 0, "closed, removed, onClose once")
    #expect(!mui_window_is_shown(window.rawHandle), "hidden")
    #expect(asked == 0, "close() asks nobody")
    window.close()
    #expect(closed == 1, "a second close runs nothing")
}

/// **1.16** (`AS-G` item 5). Files dropped on the application — SDL's Cocoa
/// `openFile:` and URL events, `SDL_EVENT_DROP_FILE` with window id 0 — are
/// collected until their `DROP_COMPLETE` and delivered as one `onOpenURLs`
/// call: a path as a `file://` URL string, a string with a scheme as is.
/// Before a handler they park; on a window's id a drop still reaches the
/// window as `.drop`.
///
/// Mutation: route window-0 drops to a window → red.
@MainActor
@Test func sdlAFileDroppedOnTheAppIsAnOpenURL() throws {
    let (platform, window) = try shellPlatform()
    var dropped: [String] = []
    window.onInput = { event in
        if case .drop(let drop) = event { dropped.append("\(drop)".components(separatedBy: "(").first ?? "") }
        return true
    }
    var opened: [[String]] = []
    platform.onOpenURLs = { opened.append($0) }
    pushDrop(mui_sdl_event_drop_file, 0, "/tmp/a b.mcgraph")
    pushDrop(mui_sdl_event_drop_file, 0, "metalcreator://doc/1")
    pushDrop(mui_sdl_event_drop_complete, 0)
    platform.pumpEvents()
    #expect(opened == [["file:///tmp/a%20b.mcgraph", "metalcreator://doc/1"]], "one call: \(opened)")
    #expect(dropped.isEmpty, "no window saw the application's drop: \(dropped)")

    pushDrop(mui_sdl_event_drop_file, window.id, "/tmp/c")
    pushDrop(mui_sdl_event_drop_complete, window.id)
    platform.pumpEvents()
    #expect(opened.count == 1, "a drop on a window is not an open")
    #expect(dropped.contains("performed"), "it is the window's drop: \(dropped)")

    let (parking, _) = try shellPlatform()
    pushDrop(mui_sdl_event_drop_file, 0, "/tmp/d")
    pushDrop(mui_sdl_event_drop_complete, 0)
    parking.pumpEvents()
    var late: [[String]] = []
    parking.onOpenURLs = { late.append($0) }
    #expect(late == [["file:///tmp/d"]], "parked until a handler is set: \(late)")
}

/// **1.17** (`AS-D` item 5, `AS-E` item 6, `AS-J` item 2). SDL has no edited
/// marker, represented file or hidden title bar: each call is recorded and
/// otherwise a no-op — the title is never altered behind the app's back,
/// `setTitleBarStyle` answers `false`, the insets read zero,
/// `performTitleBarPress` is recorded and answers `false`.
///
/// Mutation: append `" *"` to the title on edited → red.
@MainActor
@Test func sdlDocumentEditedRepresentedPathAndTitleBarStyleAreRecordedNoOps() throws {
    let (_, window) = try shellPlatform()
    let title = window.title
    window.setDocumentEdited(true)
    window.setRepresentedFilePath("/tmp/x.mcgraph")
    window.setRepresentedFilePath(nil)
    #expect(window.title == title, "the title is untouched: \(window.title)")
    #expect(window.documentEditedCalls == [true])
    #expect(window.representedPaths == ["/tmp/x.mcgraph", nil])
    #expect(window.setTitleBarStyle(.hidden) == false, "SDL keeps its system decoration")
    #expect(window.titleBarStyles == [.hidden])
    #expect(window.titleBarInsets == Edges(all: Pixels(0)))
    #expect(window.performTitleBarPress(clickCount: 1) == false)
    #expect(window.titleBarPresses == [1])
}
