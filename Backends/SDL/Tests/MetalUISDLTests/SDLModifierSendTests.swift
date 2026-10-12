import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Input follow-ups, lane 2, tests 4.1 and 4.2 (ruling `IF-I`; spec
// `docs/superpowers/specs/2026-10-10-input-followups-design.md` §3). The
// events go through SDL's own queue (`mui_push_event`), then `translate` and
// `SDLWindow.handle`; the `MUI_MOD_*` bits are the C-exported constants. None
// needs a presented frame, so none is gated on the offscreen driver.

@MainActor
private func modifierWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI modifier send test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()   // drain whatever opening the window queued
    return (platform, window)
}

@MainActor
private func push(kind: Int, window: SDLWindow, modifiers: UInt32, keycode: UInt32 = 0) {
    var event = MUIEvent()
    event.kind = UInt32(kind)
    event.window_id = window.id
    event.modifiers = modifiers
    event.keycode = keycode
    #expect(mui_push_event(&event), "push kind \(kind)")
}

/// **4.1** (`IF-I`). A window that gains focus is told the modifiers held at
/// that moment: SDL's focus-gained event carries them and the platform sends
/// `.modifiersChanged` to the window; losing focus sends nothing.
/// Mutation: drop the field in `SDLBridge.c` (the event carries none).
@MainActor
@Test func aFocusGainedCarriesTheModifiersHeld() throws {
    let (platform, window) = try modifierWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    push(kind: Int(MUI_EVENT_FOCUS_GAINED), window: window, modifiers: UInt32(MUI_MOD_COMMAND | MUI_MOD_SHIFT))
    platform.pumpEvents()
    var modifiers: [Modifiers] = []
    for case .modifiersChanged(let m) in received { modifiers.append(m) }
    #expect(modifiers == [[.command, .shift]], "\(modifiers)")
    received = []
    push(kind: Int(MUI_EVENT_FOCUS_LOST), window: window, modifiers: 0)
    platform.pumpEvents()
    #expect(received.isEmpty, "losing focus sends no modifiers: \(received.count)")
}

/// **4.2** (`IF-I`). A modifier key's own key event reaches the window with
/// the modifiers it sets — the shape of SDL, which sends no `flagsChanged`
/// (⌘ is `SDLK_LGUI`, `0x400000E3`).
@MainActor
@Test func anSDLKeyEventForAModifierKeyReachesTheWindow() throws {
    let (platform, window) = try modifierWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    push(kind: Int(MUI_EVENT_KEY_DOWN), window: window, modifiers: UInt32(MUI_MOD_COMMAND), keycode: 0x4000_00E3)
    push(kind: Int(MUI_EVENT_KEY_UP), window: window, modifiers: 0, keycode: 0x4000_00E3)
    platform.pumpEvents()
    var seen: [String] = []
    for event in received {
        switch event {
        case .keyDown(let key): seen.append("down \(key.modifiers.contains(.command))")
        case .keyUp(let key): seen.append("up \(key.modifiers.contains(.command))")
        default: seen.append("other")
        }
    }
    #expect(seen == ["down true", "up false"], "\(seen)")
}
