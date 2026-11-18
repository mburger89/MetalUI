import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Terminal phase 4.2 (`TRM-BJ`): what the SDL backend hands MetalUI for the keys a terminal needs, from SDL's
// (scancode, keycode, modifiers) as X11, Wayland and Win32 report them. The key event's bytes are the root
// package's `TerminalSDLKeysTests`. Each test names the mutation it was shown red against
// (`docs/practices/verifying-tests-can-fail.md`).
//
// SDL values below are SDL 3.4's (SDL_scancode.h, SDL_keycode.h): SDLK_x for a scancode is `0x4000_0000 | scancode`
// except the printable keys, whose keycode is their character.

private func keyEvent(keycode: UInt32, scancode: UInt32, _ modifiers: Modifiers = []) -> KeyEvent {
    SDLKeys.keyEvent(keycode: keycode, scancode: scancode, modifiers: modifiers, isRepeat: false, timestamp: 0)
}

/// **1** Insert and F13-F20 (the function keys the encoder numbers 25..34) arrive as AppKit's function-key
/// characters, not flagged keypad. Mutation: drop the Insert entry from `SDLKeys.named` (Insert's row fails: it
/// arrived empty); shift an F-key's entry by one (its row fails).
@Test func insertAndF13ToF20ArriveAsFunctionKeyCharacters() {
    let insert = keyEvent(keycode: 0x4000_0049, scancode: 73)
    #expect(insert.characters == "\u{f727}" && insert.charactersIgnoringModifiers == "\u{f727}" && !insert.isKeypad)
    for index in 0..<8 {   // SDL_SCANCODE_F13 = 104
        let event = keyEvent(keycode: 0x4000_0000 | UInt32(104 + index), scancode: UInt32(104 + index))
        let expected = String(UnicodeScalar(0xF710 + UInt32(index))!)
        #expect(event.charactersIgnoringModifiers == expected && event.characters == expected && !event.isKeypad,
                "F\(13 + index)")
    }
}

/// **2** Every keypad key, however the platform spelled its keycode (SDLK_KP_*; the plain digit a Windows or X11
/// layout may give with Num Lock on), is the character AppKit reports with `isKeypad`.
/// Mutation: derive `isKeypad` from the keycode range only (the plain-digit rows fail); drop `isKeypad`
/// (every row fails); drop KP_EQUALS or KP_COMMA from `keypadScancodes` (its row fails).
@Test func everyKeypadKeyIsFlaggedWhateverTheKeycode() {
    // (scancode, SDLK_KP_* keycode, character)
    let rows: [(UInt32, UInt32, String)] = [
        (84, 0x4000_0054, "/"), (85, 0x4000_0055, "*"), (86, 0x4000_0056, "-"), (87, 0x4000_0057, "+"),
        (88, 0x4000_0058, "\r"), (89, 0x4000_0059, "1"), (90, 0x4000_005A, "2"), (91, 0x4000_005B, "3"),
        (92, 0x4000_005C, "4"), (93, 0x4000_005D, "5"), (94, 0x4000_005E, "6"), (95, 0x4000_005F, "7"),
        (96, 0x4000_0060, "8"), (97, 0x4000_0061, "9"), (98, 0x4000_0062, "0"), (99, 0x4000_0063, "."),
        (103, 0x4000_0067, "="), (133, 0x4000_0085, ","),
    ]
    for (scancode, keycode, character) in rows {
        let plain = character.unicodeScalars.first!.value
        for (spelling, code) in [("SDLK_KP", keycode), ("plain", plain)] {
            let event = keyEvent(keycode: code, scancode: scancode)
            #expect(event.isKeypad && event.characters == character && event.charactersIgnoringModifiers == character
                    && event.unshiftedKey == character, "\(spelling) \(character.debugDescription)")
        }
    }
    // Shift does not change a keypad key's character (AppKit's keypad is the same).
    #expect(keyEvent(keycode: 0x4000_0059, scancode: 89, .shift).characters == "1")
}

/// **3** With Num Lock off SDL reports the keypad's digits as navigation keys (the scancode stays KP_*): that is
/// End, Insert, Home..., not a keypad key. A main-row digit and Enter are not keypad either.
/// Mutation: flag on the scancode alone (the Num Lock off rows fail).
@Test func aKeypadScancodeThatIsANavigationKeyIsNotKeypad() {
    let rows: [(UInt32, UInt32, String)] = [
        (89, 0x4000_004D, "\u{f72b}"), (98, 0x4000_0049, "\u{f727}"), (95, 0x4000_004A, "\u{f729}"),
        (92, 0x4000_0050, "\u{f702}"), (94, 0x4000_004F, "\u{f703}"), (99, 0x7F, "\u{f728}"),
    ]
    for (scancode, keycode, character) in rows {
        let event = keyEvent(keycode: keycode, scancode: scancode)
        #expect(!event.isKeypad && event.characters == character, "scancode \(scancode): \(event.characters.debugDescription)")
    }
    #expect(!keyEvent(keycode: 0x31, scancode: 30).isKeypad, "main-row 1 (SDL_SCANCODE_1)")
    #expect(!keyEvent(keycode: 0x0D, scancode: 40).isKeypad, "main Return (SDL_SCANCODE_RETURN)")
    #expect(keyEvent(keycode: 0x0D, scancode: 40).characters == "\r")
}

/// **4** ⌃Space and ⌃` are keys, not text: SDL sends no text for them and `producesText` is false with Control, so
/// the key (with its modifier) reaches the encoder. Also ⌃⇧Space, and a plain Space or backtick stays text.
/// Mutation: let Control through `producesText` (the ⌃ rows fail).
@Test func controlSpaceAndControlBacktickAreKeysWithTheirModifier() {
    for (keycode, scancode, character) in [(UInt32(0x20), UInt32(44), " "), (0x60, 53, "`")] {
        let event = keyEvent(keycode: keycode, scancode: scancode, .control)
        #expect(event.characters == character && event.modifiers == .control && !event.isKeypad)
        #expect(!SDLWindow.producesText(keycode: keycode, modifiers: .control, scancode: scancode))
        #expect(!SDLWindow.producesText(keycode: keycode, modifiers: [.control, .shift], scancode: scancode))
        #expect(SDLWindow.producesText(keycode: keycode, modifiers: [], scancode: scancode), "plain: text")
    }
}

/// **5** A keypad character key is text while text input is on (no double delivery: SDL sends the text too);
/// keypad Enter sends no text, so it is a key; with Control it is a key. Mutation: `producesText` false for keypad
/// characters (digits and operators double-deliver; the first row fails).
@Test func aKeypadCharacterKeyIsTextOnlyWhileItWouldBeTyped() {
    for (scancode, keycode) in [(UInt32(89), UInt32(0x4000_0059)), (89, 0x31), (87, 0x4000_0057), (99, 0x4000_0063)] {
        #expect(SDLWindow.producesText(keycode: keycode, modifiers: [], scancode: scancode), "KP \(scancode)/\(keycode)")
        #expect(!SDLWindow.producesText(keycode: keycode, modifiers: .control, scancode: scancode), "ctrl")
    }
    #expect(!SDLWindow.producesText(keycode: 0x4000_0058, modifiers: [], scancode: 88), "keypad Enter is a key")
    #expect(!SDLWindow.producesText(keycode: 0x0D, modifiers: [], scancode: 88), "keypad Enter spelled CR")
    #expect(!SDLWindow.producesText(keycode: 0x4000_004D, modifiers: [], scancode: 89), "End on Num Lock off")
}

/// **6** Through SDL's own queue: the scancode crosses the bridge, a keypad digit with text input on is only the
/// text, KP Enter and Insert arrive as flagged keys. Mutation: leave `scancode` out of `translate` (KP Enter
/// arrives empty and unflagged).
@MainActor @Test func theScancodeCrossesTheBridgeAndAKeypadDigitIsNotDoubleDelivered() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI terminal keys test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    func push(_ kind: Int, keycode: UInt32 = 0, scancode: UInt32 = 0, text: String? = nil) {
        var event = MUIEvent()
        event.kind = UInt32(kind); event.window_id = window.id
        event.keycode = keycode; event.scancode = scancode
        if let text {
            text.withCString { event.text = $0; #expect(mui_push_event(&event)) }
        } else {
            #expect(mui_push_event(&event))
        }
    }
    func describe() -> [String] {
        received.map {
            switch $0 {
            case .textInput(let text): "text(\(text))"
            case .keyDown(let key): "key(\(key.characters.unicodeScalars.map { String($0.value, radix: 16) }.joined()),\(key.isKeypad ? "kp" : "-"))"
            default: "other"
            }
        }
    }
    window.setTextInputArea(Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(1), height: Pixels(16))))
    push(Int(MUI_EVENT_KEY_DOWN), keycode: 0x4000_005D, scancode: 93)   // KP 5: dropped, SDL sends the text
    push(Int(MUI_EVENT_TEXT_INPUT), text: "5")
    push(Int(MUI_EVENT_KEY_DOWN), keycode: 0x4000_0058, scancode: 88)   // KP Enter: a key
    push(Int(MUI_EVENT_KEY_DOWN), keycode: 0x4000_0049, scancode: 73)   // Insert: a key
    platform.pumpEvents()
    #expect(describe() == ["text(5)", "key(d,kp)", "key(f727,-)"], "\(describe())")
    received = []
    window.setTextInputArea(nil)
    push(Int(MUI_EVENT_KEY_DOWN), keycode: 0x4000_005D, scancode: 93)   // text input off: a flagged key
    platform.pumpEvents()
    #expect(describe() == ["key(35,kp)"], "\(describe())")
}
