import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// EV-AB (amended by EV-AF): an SDL window's control active state is tracked by
// its platform from SDL's focus events — `.key` for the focused window,
// `.active` for another window of the same platform while one of its windows
// has focus, `.inactive` when none does — and recomputed once after
// `pumpEvents()` drains, so a switch between two own windows reports no
// transient. Events go through SDL's own queue and the real translation path.

@MainActor
private func twoHiddenWindows() throws -> (SDLPlatform, SDLWindow, SDLWindow) {
    let platform = try SDLPlatform(hiddenWindows: true)
    let a = try platform.openSDLWindow(title: "control state A", size: Size(width: Pixels(120), height: Pixels(80)))
    let b = try platform.openSDLWindow(title: "control state B", size: Size(width: Pixels(120), height: Pixels(80)))
    platform.pumpEvents()   // drain whatever opening the windows queued
    return (platform, a, b)
}

private func pushFocus(_ kind: Int, _ windowID: UInt32) {
    var event = MUIEvent()
    event.kind = UInt32(kind); event.window_id = windowID
    #expect(mui_push_event(&event), "push kind \(kind) for window \(windowID)")
}

/// T2.1. Each window's callback log is exact: no transient and no call for an
/// unchanged state.
@MainActor
@Test func focusEventsMakeAWindowKeyItsSiblingActiveAndNeitherInactive() throws {
    let (platform, a, b) = try twoHiddenWindows()
    // A hidden window has no focus; if a window manager gave it one, say so
    // rather than asserting a false sequence.
    try #require(a.controlActiveState == .inactive && b.controlActiveState == .inactive,
                 "a hidden window started with focus: A \(a.controlActiveState), B \(b.controlActiveState)")
    var logA: [ControlActiveState] = [], logB: [ControlActiveState] = []
    a.onControlActiveStateChange = { logA.append($0) }
    b.onControlActiveStateChange = { logB.append($0) }

    pushFocus(MUI_EVENT_FOCUS_GAINED, a.id)
    platform.pumpEvents()
    #expect(a.controlActiveState == .key)
    #expect(b.controlActiveState == .active)

    // A switch between two own windows, drained by one pump.
    pushFocus(MUI_EVENT_FOCUS_LOST, a.id)
    pushFocus(MUI_EVENT_FOCUS_GAINED, b.id)
    platform.pumpEvents()
    #expect(a.controlActiveState == .active)
    #expect(b.controlActiveState == .key)

    pushFocus(MUI_EVENT_FOCUS_LOST, b.id)
    platform.pumpEvents()
    #expect(a.controlActiveState == .inactive)
    #expect(b.controlActiveState == .inactive)

    // A pump with nothing queued changes nothing, so it calls nothing.
    platform.pumpEvents()

    #expect(logA == [.key, .active, .inactive])
    #expect(logB == [.active, .key, .inactive])
}

/// T2.2. A focus event for a window the platform does not own changes
/// nothing, and a closed window's focus is forgotten.
@MainActor
@Test func focusTrackingIgnoresWindowsThePlatformDoesNotOwnAndForgetsAClosedOne() throws {
    let (platform, a, b) = try twoHiddenWindows()
    try #require(a.controlActiveState == .inactive && b.controlActiveState == .inactive,
                 "a hidden window started with focus")
    var calls = 0
    a.onControlActiveStateChange = { _ in calls += 1 }
    b.onControlActiveStateChange = { _ in calls += 1 }

    // An id neither window has (SDL ids are small positive integers).
    let foreign = max(a.id, b.id) + 1000
    pushFocus(MUI_EVENT_FOCUS_GAINED, foreign)
    platform.pumpEvents()
    #expect(a.controlActiveState == .inactive)
    #expect(b.controlActiveState == .inactive)
    #expect(calls == 0)

    pushFocus(MUI_EVENT_FOCUS_GAINED, a.id)
    platform.pumpEvents()
    try #require(a.controlActiveState == .key && b.controlActiveState == .active)

    // A leaves the platform's windows the way a closed window does.
    var close = MUIEvent(); close.kind = UInt32(MUI_EVENT_CLOSE); close.window_id = a.id
    #expect(mui_push_event(&close))
    platform.pumpEvents()
    #expect(platform.openWindowCount == 1)
    #expect(b.controlActiveState == .inactive)
}

/// T2.3. SDL's own scale and pixel-size events reach `onResize`, which is how
/// `displayScale` follows a move between displays (EV-AA). Pins a path that
/// predates EV-AA and that nothing pinned.
@MainActor
@Test func aScaleOrPixelSizeChangeReachesOnResize() throws {
    let (platform, a, _) = try twoHiddenWindows()
    var scales: [Float] = []
    a.onResize = { _, scale in scales.append(scale) }

    #expect(mui_push_raw_window_event(mui_sdl_event_window_display_scale_changed, a.id))
    platform.pumpEvents()
    #expect(scales == [a.scaleFactor], "display scale changed")

    #expect(mui_push_raw_window_event(mui_sdl_event_window_pixel_size_changed, a.id))
    platform.pumpEvents()
    #expect(scales == [a.scaleFactor, a.scaleFactor], "pixel size changed")
}
