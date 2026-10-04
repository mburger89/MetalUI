import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Platform services on SDL, lane 1, tests 1.10–1.17 (rulings `SV-B`, `SV-E`,
// `SV-G`, `SV-J` item 2, `SV-M`, `SV-N` item 7, `SV-AB`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §6.1). A real
// hidden `SDLPlatform` window. A dialog's answer is completed by the bridge's
// test hook, `mui_test_complete_dialog`, which runs **the same callback** SDL
// would, from a thread of its own (`SV-G` item 3) — so the thread hop is tested
// without a real dialog. Only 1.12 calls SDL's real dialog, and only where it
// cannot wait on a human (CI's Linux image).

@MainActor
private func presentationWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI presentation test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()   // drain whatever opening the window queued
    return (platform, window)
}

private func fileResults(_ events: [InputEvent]) -> [FileDialogResultEvent] {
    events.compactMap { if case .fileDialogResult(let r) = $0 { r } else { nil } }
}

/// Pumps until `done` holds, waiting at most `limit` times for an event (each
/// wait bounded by `mui_wait_event`'s 20 ms timeout — the loop's own wait, not
/// a sleep); answers whether `done` held.
@MainActor
private func pump(_ platform: SDLPlatform, limit: Int = 100, until done: () -> Bool) -> Bool {
    for _ in 0..<limit {
        platform.pumpEvents()
        if done() { return true }
        platform.waitForEvent(timeoutMilliseconds: 20)
    }
    platform.pumpEvents()
    return done()
}

/// **1.10** (`SV-G` items 2–3). A dialog answered on another thread arrives as
/// one `.fileDialogResult` on the main thread, through `pumpEvents()`, with the
/// paths intact (spaces and non-ASCII included).
///
/// Mutation **M1.10**: not pushing `MUI_EVENT_DIALOG` from the callback (the
/// result is queued and never dispatched).
@MainActor
@Test func sdlDialogResultFromAnotherThreadArrivesAsInput() throws {
    let (platform, window) = try presentationWindow()
    var events: [InputEvent] = []
    window.onInput = { events.append($0); return true }
    let paths = ["/tmp/a keymap.json", "/tmp/thème.json"]
    #expect(mui_test_complete_dialog(window.id, 41, paths.joined(separator: "\n"), Int32(paths.count)))
    #expect(pump(platform) { !fileResults(events).isEmpty }, "the answer never arrived")
    platform.pumpEvents()
    #expect(fileResults(events) == [FileDialogResultEvent(token: 41, outcome: .chosen(paths))])
}

/// **1.11** (`SV-G` item 1). An empty file list is a cancel; a `NULL` one a
/// failure carrying `SDL_GetError()`'s text.
///
/// Mutation **M1.11**: swap the two branches.
@MainActor
@Test func sdlCancelledAndFailedDialogsMapTheirOutcomes() throws {
    let (platform, window) = try presentationWindow()
    var events: [InputEvent] = []
    window.onInput = { events.append($0); return true }
    #expect(mui_test_complete_dialog(window.id, 42, "", 0))
    #expect(pump(platform) { fileResults(events).count == 1 })
    #expect(mui_test_complete_dialog(window.id, 43, nil, -1))
    #expect(pump(platform) { fileResults(events).count == 2 })
    let results = fileResults(events)
    try #require(results.count == 2)
    #expect(results[0] == FileDialogResultEvent(token: 42, outcome: .cancelled))
    #expect(results[1] == FileDialogResultEvent(token: 43, outcome: .failed("test dialog failure")))
}

/// Whether SDL's real dialog can run here without waiting on a human (`SV-AB`):
/// the offscreen video driver (CI's Linux image), no `zenity` on `PATH` and no
/// session bus — so neither of SDL's Linux back ends (the XDG portal over
/// D-Bus, zenity) can show one.
private let realDialogCannotShow: Bool = {
    let environment = ProcessInfo.processInfo.environment
    guard environment["SDL_VIDEO_DRIVER"] == "offscreen", environment["DBUS_SESSION_BUS_ADDRESS"] == nil else {
        return false
    }
    #if os(Linux)
    let path = environment["PATH"] ?? ""
    return !path.split(separator: ":").contains { dir in
        FileManager.default.isExecutableFile(atPath: "\(dir)/zenity")
    }
    #else
    return false
    #endif
}()

/// **1.12** (`SV-G` item 4, `SV-AB`). In CI's Linux image SDL's real
/// `SDL_ShowOpenFileDialog` answers — measured there first — with a failure,
/// within a bounded number of pumps.
///
/// Mutation **M1.12**: answer `false` from `presentFileDialog` without calling
/// SDL (no event ever arrives).
@MainActor
@Test(.enabled(if: realDialogCannotShow, "only where no real dialog can show (the offscreen driver, no zenity, no bus)"))
func sdlDialogInTheLinuxImageAnswersItsRecordedOutcome() throws {
    let (platform, window) = try presentationWindow()
    var events: [InputEvent] = []
    window.onInput = { events.append($0); return true }
    #expect(window.presentFileDialog(PlatformFileDialog(token: 44, kind: .open(allowsMultipleSelection: false),
                                                        allowedTypes: [])))
    #expect(pump(platform, limit: 250) { !fileResults(events).isEmpty }, "no answer within the bound")
    let results = fileResults(events)
    try #require(results.count == 1, "\(results)")
    print("SV-AB real dialog in this environment: \(results[0].outcome)")
    guard case .failed = results[0].outcome else {
        Issue.record("expected a failure here, got \(results[0].outcome)")
        return
    }
}

/// **1.13** (`SV-E`, divergence 129). One filter per type with extensions,
/// named by the identifier, its extensions joined by `;`; a type without
/// extensions contributes none, and a list with none passes `NULL` (every
/// file).
///
/// Mutation **M1.13**: emit `"*"` for a type without extensions.
@Test func sdlFiltersCarryExtensionsAndATypeWithoutOneFiltersNothing() {
    let json = PlatformFileType(identifier: "public.json", conformsTo: ["public.text"], filenameExtensions: ["json"])
    let text = PlatformFileType(identifier: "public.plain-text", conformsTo: ["public.text"],
                                filenameExtensions: ["txt", "text"])
    let data = PlatformFileType(identifier: "public.data")
    let filters = SDLWindow.dialogFilters([json, data, text])
    #expect(filters.map(\.name) == ["public.json", "public.plain-text"])
    #expect(filters.map(\.pattern) == ["json", "txt;text"])
    #expect(SDLWindow.dialogFilters([data]).isEmpty)
    #expect(SDLWindow.dialogFilters([]).isEmpty)
}

/// **1.14** (`SV-J` item 2). SDL declines every alert — `Window` draws its own.
///
/// Mutation **M1.14**: answer `true`.
@MainActor
@Test func sdlPresentAlertDeclines() throws {
    let (_, window) = try presentationWindow()
    #expect(!window.presentAlert(PlatformAlert(token: 1, title: "T", message: nil,
                                               buttons: [PlatformAlertButton(title: "OK")])))
}

/// **1.15** (`SV-M`). The limits reach SDL, read back: the minimum rounded up,
/// the maximum down, `nil` (and an unbounded axis) as 0, SDL's "no limit".
///
/// Mutation **M1.15**: swap the rounding.
@MainActor
@Test func sdlContentSizeLimitsReachSDLAndClamp() throws {
    let (_, window) = try presentationWindow()
    window.setContentSizeLimits(minimum: Size(width: Pixels(100.2), height: Pixels(80.7)),
                                maximum: Size(width: Pixels(600.8), height: Pixels(.greatestFiniteMagnitude)))
    var minW: Int32 = -1, minH: Int32 = -1, maxW: Int32 = -1, maxH: Int32 = -1
    mui_window_size_limits(window.rawHandle, &minW, &minH, &maxW, &maxH)
    #expect([minW, minH, maxW, maxH] == [101, 81, 600, 0])
    window.setContentSizeLimits(minimum: nil, maximum: nil)
    mui_window_size_limits(window.rawHandle, &minW, &minH, &maxW, &maxH)
    #expect([minW, minH, maxW, maxH] == [0, 0, 0, 0])
}

/// **1.16** (`SV-N` item 7). A raw `SDL_EVENT_WINDOW_MOUSE_LEAVE` through SDL's
/// own queue — its type from the C-exported constant, never an SDL enum's
/// `rawValue` (`Int32` on Windows) — becomes `.pointerExited`.
///
/// Mutation **M1.16**: drop the bridge's mapping.
@MainActor
@Test func sdlMouseLeaveDeliversPointerExited() throws {
    let (platform, window) = try presentationWindow()
    var exits = 0
    window.onInput = { if case .pointerExited = $0 { exits += 1 }; return true }
    #expect(mui_push_raw_window_event(mui_sdl_event_window_mouse_leave, window.id))
    platform.pumpEvents()
    #expect(exits == 1)
}

/// **1.17** (`SV-G` item 5). SDL cannot close its dialog: after
/// `dismissPresentation(token:)` the late answer is still delivered as input —
/// the platform's half of the contract (`Window` ignores it, spec 2.4). No
/// mutation owed: a contract with no code path to break.
@MainActor
@Test func sdlDismissPresentationForgetsAndALateResultStillArrives() throws {
    let (platform, window) = try presentationWindow()
    var events: [InputEvent] = []
    window.onInput = { events.append($0); return true }
    window.dismissPresentation(token: 45)
    #expect(mui_test_complete_dialog(window.id, 45, "/tmp/late.json", 1))
    #expect(pump(platform) { !fileResults(events).isEmpty })
    #expect(fileResults(events) == [FileDialogResultEvent(token: 45, outcome: .chosen(["/tmp/late.json"]))])
}
