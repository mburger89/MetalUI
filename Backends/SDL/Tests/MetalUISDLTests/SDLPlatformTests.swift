import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// SP-A…SP-C: the SDL platform. Events are pushed into SDL's own queue and come
// out through the real translation path; nothing here fakes SDL.

/// The keys `Keymap.namedKeys` binds, as SDL reports them, reach MetalUI as
/// the characters AppKit would have given (SP-C).
@Test func sdlKeysSpellWhatKeymapBinds() {
    let expected: [(UInt32, String)] = [
        (0x20, " "), (0x09, "\t"), (0x0D, "\r"), (0x1B, "\u{1b}"), (0x08, "\u{7f}"),
        (0x4000_0052, "\u{f700}"), (0x4000_0051, "\u{f701}"), (0x4000_0050, "\u{f702}"), (0x4000_004F, "\u{f703}"),
        (0x4000_004A, "\u{f729}"), (0x4000_004D, "\u{f72b}"), (0x4000_004B, "\u{f72c}"), (0x4000_004E, "\u{f72d}"),
        (0x4000_003A, "\u{f704}"), (0x4000_0045, "\u{f70f}"),
    ]
    for (keycode, character) in expected {
        #expect(SDLKeys.characters(forKeycode: keycode, modifiers: []).ignoringModifiers == character,
                "keycode \(String(keycode, radix: 16))")
    }
    #expect(SDLKeys.characters(forKeycode: 0x61, modifiers: []) == ("a", "a"))
    #expect(SDLKeys.characters(forKeycode: 0x61, modifiers: .shift) == ("a", "A"))
    #expect(SDLKeys.characters(forKeycode: 0x31, modifiers: .command) == ("1", "1"))
    // A key with no character (a bare modifier) reports none.
    #expect(SDLKeys.characters(forKeycode: 0x4000_00E1, modifiers: []) == ("", ""))
}

@Test func aWheelLineIsTenPoints() {
    let delta = SDLKeys.scrollDelta(x: 0.5, y: -2)
    #expect(delta.x.value == 5 && delta.y.value == -20)
}

@MainActor
private func hiddenWindow() throws -> (SDLPlatform, SDLWindow) {
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI SDL test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    return (platform, window)
}

@MainActor
@Test func aWindowHasItsSizeTitleScaleAndAnSDLRenderer() throws {
    let (_, window) = try hiddenWindow()
    #expect(window.contentSize.width.value == 320 && window.contentSize.height.value == 200)
    #expect(window.scaleFactor >= 1)
    #expect(window.title == "MetalUI SDL test")
    window.title = "Renamed"
    #expect(window.title == "Renamed")
    #expect(window.renderer is SDLWindowRenderer)
}

@MainActor
@Test func sdlEventsArriveAsMetalUIInput() throws {
    let (platform, window) = try hiddenWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    func push(_ kind: Int, x: Float = 0, y: Float = 0, dx: Float = 0, dy: Float = 0,
              clicks: Int32 = 0, keycode: UInt32 = 0, modifiers: Int = 0) {
        var event = MUIEvent()
        event.kind = UInt32(kind); event.window_id = window.id
        event.x = x; event.y = y; event.dx = dx; event.dy = dy; event.clicks = clicks
        event.keycode = keycode; event.modifiers = UInt32(modifiers)
        #expect(mui_push_event(&event))
    }
    platform.pumpEvents()   // drain whatever opening the window queued
    received.removeAll()
    push(MUI_EVENT_MOUSE_MOVE, x: 10, y: 20)
    push(MUI_EVENT_MOUSE_DOWN, x: 11, y: 21, clicks: 2)
    push(MUI_EVENT_MOUSE_UP, x: 11, y: 21, clicks: 2)
    push(MUI_EVENT_WHEEL, x: 30, y: 40, dx: 0, dy: -1)
    push(MUI_EVENT_KEY_DOWN, keycode: 0x4000_0052, modifiers: MUI_MOD_SHIFT)
    push(MUI_EVENT_KEY_UP, keycode: 0x61)
    platform.pumpEvents()

    try #require(received.count == 6, "\(received)")
    guard case .mouseMoved(let move) = received[0] else { Issue.record("\(received[0])"); return }
    #expect(move.position.x.value == 10 && move.position.y.value == 20)
    guard case .mouseDown(let down) = received[1] else { Issue.record("\(received[1])"); return }
    #expect(down.position.x.value == 11 && down.clickCount == 2)
    guard case .mouseUp = received[2] else { Issue.record("\(received[2])"); return }
    guard case .scrollWheel(let wheel) = received[3] else { Issue.record("\(received[3])"); return }
    #expect(wheel.delta.y.value == -10 && wheel.position.x.value == 30)
    guard case .keyDown(let key) = received[4] else { Issue.record("\(received[4])"); return }
    #expect(key.charactersIgnoringModifiers == "\u{f700}" && key.modifiers == .shift)
    guard case .keyUp(let up) = received[5] else { Issue.record("\(received[5])"); return }
    #expect(up.characters == "a")
}

@MainActor
@Test func resizeThemeAndCloseReachTheWindow() throws {
    let (platform, window) = try hiddenWindow()
    platform.pumpEvents()
    var resized = 0, appearances = 0, closed = 0
    window.onResize = { _, _ in resized += 1 }
    window.onAppearanceChange = { _ in appearances += 1 }
    window.onClose = { closed += 1 }
    for kind in [MUI_EVENT_RESIZE, MUI_EVENT_THEME, MUI_EVENT_CLOSE] {
        var event = MUIEvent(); event.kind = UInt32(kind); event.window_id = window.id
        #expect(mui_push_event(&event))
    }
    platform.pumpEvents()
    #expect(resized >= 1 && appearances == 1 && closed == 1)
}

/// `run()` ticks a running display link, not a paused one, and returns once
/// the last window closes.
@MainActor
@Test func theRunLoopTicksLinksAndEndsWhenTheLastWindowCloses() throws {
    let (platform, window) = try hiddenWindow()
    let (_, paused) = (platform, try platform.openSDLWindow(title: "paused", size: Size(width: Pixels(50), height: Pixels(50))))
    var ticks = 0, pausedTicks = 0
    paused.startDisplayLink { _ in pausedTicks += 1 }
    paused.setDisplayLinkPaused(true)
    window.startDisplayLink { _ in
        ticks += 1
        if ticks == 3 {
            for id in [window.id, paused.id] {
                var event = MUIEvent(); event.kind = UInt32(MUI_EVENT_CLOSE); event.window_id = id
                _ = mui_push_event(&event)
            }
        }
    }
    // A budget, so a loop that never ends fails here instead of hanging.
    platform.run(maxIterations: 200)
    #expect(platform.openWindowCount == 0, "the loop ended because the windows closed")
    #expect(ticks == 3)
    #expect(pausedTicks == 0)
}
