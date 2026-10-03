import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Menus, popovers and tooltips, lane 1, tests S3.1–S3.2 (rulings `MN-B` item 3,
// `MN-G` item 1, `MN-AC` item 1, `MN-AD`; spec §3.11). Every pointer event
// goes through SDL's own queue — a raw SDL event pushed by
// `mui_push_raw_mouse_event`, its type, button and mask taken from the
// C-exported `mui_sdl_*` constants, never an SDL enum's `rawValue` in Swift
// (`Int32` on Windows) — then `translate` and `SDLWindow.handle`.

@MainActor
private func menuInputWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI menu input test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()   // drain whatever opening the window queued
    return (platform, window)
}

private func describe(_ event: InputEvent) -> String {
    func at(_ m: MouseEvent) -> String {
        "(\(Int(m.position.x.value)),\(Int(m.position.y.value)))\(m.modifiers.contains(.control) ? "^" : "")"
    }
    switch event {
    case .mouseDown(let m): return "down\(at(m))"
    case .mouseUp(let m): return "up\(at(m))"
    case .mouseMoved(let m): return "move\(at(m))"
    case .mouseDragged(let m): return "drag\(at(m))"
    case .rightMouseDown(let m): return "rdown\(at(m))"
    case .rightMouseUp(let m): return "rup\(at(m))"
    case .keyDown(let k): return "key[\(k.charactersIgnoringModifiers.unicodeScalars.map { String($0.value, radix: 16) }.joined())]"
    default: return "other"
    }
}

/// **S3.1** (`MN-B` item 3, `MN-AD`). The right button arrives as
/// `.rightMouseDown`/`.rightMouseUp` at its position; motion with only the
/// right button held is a `.mouseMoved` (not a primary drag); the left button
/// is unchanged. Mutation: keep dropping every button but the left.
@MainActor
@Test func aRightButtonEventBecomesARightMouseDownAndUp() throws {
    let (platform, window) = try menuInputWindow()
    var received: [String] = []
    window.onInput = { received.append(describe($0)); return true }
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_down, window.id, mui_sdl_button_right, 0, 30, 40))
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_motion, window.id, 0, mui_sdl_button_rmask, 35, 45))
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_up, window.id, mui_sdl_button_right, 0, 35, 45))
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_down, window.id, mui_sdl_button_left, 0, 50, 60))
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_up, window.id, mui_sdl_button_left, 0, 50, 60))
    platform.pumpEvents()
    #expect(received == ["rdown(30,40)", "move(35,45)", "rup(35,45)", "down(50,60)", "up(50,60)"])
}

/// **S3.2** (`MN-G` item 1). `SDLK_APPLICATION` (`0x40000065`) is AppKit's
/// `NSMenuFunctionKey` (`U+F735`), the key `ContextMenuKeys` reads; F10 stays
/// `U+F70D`. Mutation: drop the Menu key's row.
@MainActor
@Test func theApplicationKeyIsTheMenuFunctionKey() throws {
    #expect(SDLKeys.characters(forKeycode: 0x4000_0065, modifiers: []).ignoringModifiers == "\u{f735}")
    #expect(SDLKeys.characters(forKeycode: 0x4000_0043, modifiers: .shift).ignoringModifiers == "\u{f70d}")
    let (platform, window) = try menuInputWindow()
    var received: [String] = []
    window.onInput = { received.append(describe($0)); return true }
    var event = MUIEvent()
    event.kind = UInt32(MUI_EVENT_KEY_DOWN); event.window_id = window.id; event.keycode = 0x4000_0065
    #expect(mui_push_event(&event))
    platform.pumpEvents()
    #expect(received == ["key[f735]"], "the Menu key reaches the window as U+F735")
}
