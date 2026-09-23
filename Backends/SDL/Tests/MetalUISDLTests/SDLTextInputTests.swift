import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// TI-A on SDL: text and editing events through SDL's own queue, the key-down
// SDL also sends for a typed character dropped while text input is on, drags,
// and the clipboard.

@MainActor
private func hiddenWindow() throws -> (SDLPlatform, SDLWindow) {
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI text input test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    return (platform, window)
}

private let caret = Bounds(origin: Point(x: Pixels(40), y: Pixels(10)), size: Size(width: Pixels(1), height: Pixels(16)))

@MainActor
private func describe(_ events: [InputEvent]) -> [String] {
    events.map {
        switch $0 {
        case .textInput(let text): "text(\(text))"
        case .textComposition(let c): "compose(\(c.text),\(c.selection))"
        case .keyDown(let key): "key(\(key.charactersIgnoringModifiers.unicodeScalars.map { String($0.value, radix: 16) }.joined()))"
        case .mouseDragged(let m): "drag(\(Int(m.position.x.value)))"
        case .mouseMoved(let m): "move(\(Int(m.position.x.value)))"
        default: "other"
        }
    }
}

@MainActor
@Test func textAndCompositionArriveOnlyWhileTextInputIsOn() throws {
    let (platform, window) = try hiddenWindow()
    platform.pumpEvents()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    func push(_ kind: Int, text: String? = nil, start: Int32 = 0, length: Int32 = 0,
              keycode: UInt32 = 0, modifiers: Int = 0) {
        var event = MUIEvent()
        event.kind = UInt32(kind); event.window_id = window.id
        event.start = start; event.length = length; event.keycode = keycode; event.modifiers = UInt32(modifiers)
        if let text {
            text.withCString { event.text = $0; #expect(mui_push_event(&event)) }
        } else {
            #expect(mui_push_event(&event))
        }
    }
    // Off: text events are dropped and every key is a key.
    push(MUI_EVENT_TEXT_INPUT, text: "x")
    push(MUI_EVENT_KEY_DOWN, keycode: 0x61)
    platform.pumpEvents()
    #expect(describe(received) == ["key(61)"])
    received = []

    window.setTextInputArea(caret)
    #expect(window.textInputCaret == caret)
    push(MUI_EVENT_KEY_DOWN, keycode: 0x61)                       // dropped: SDL sends the text too
    push(MUI_EVENT_TEXT_INPUT, text: "a")
    push(MUI_EVENT_TEXT_EDITING, text: "にほん", start: 1, length: 2)
    push(MUI_EVENT_TEXT_EDITING, text: "", start: 0, length: 0)
    push(MUI_EVENT_KEY_DOWN, keycode: 0x4000_0050)                // left arrow: still a key
    push(MUI_EVENT_KEY_DOWN, keycode: 0x08)                       // backspace: still a key
    push(MUI_EVENT_KEY_DOWN, keycode: 0x63, modifiers: MUI_MOD_CONTROL)   // ctrl-c: a shortcut, a key
    platform.pumpEvents()
    #expect(describe(received) == ["text(a)", "compose(にほん,1..<3)", "compose(,0..<0)",
                                   "key(f702)", "key(7f)", "key(63)"])
    received = []
    window.setTextInputArea(nil)
    push(MUI_EVENT_KEY_DOWN, keycode: 0x61)
    platform.pumpEvents()
    #expect(describe(received) == ["key(61)"], "off again")
}

@Test func anEditingSelectionInCodePointsBecomesCharacterOffsets() {
    // "e" + combining acute is two code points and one Character.
    let text = "e\u{301}xy"
    #expect(SDLKeys.composition(text, start: 2, length: 1) == TextComposition(text: text, selection: 1..<2))
    #expect(SDLKeys.composition(text, start: 1, length: 0) == TextComposition(text: text, selection: 0..<0),
            "inside a grapheme rounds down")
    #expect(SDLKeys.composition(text, start: 3, length: 9) == TextComposition(text: text, selection: 2..<3))
    #expect(SDLKeys.composition(text, start: -1, length: 0) == TextComposition(text: text, selection: 3..<3),
            "no selection: the caret at the end")
    #expect(SDLKeys.composition("", start: 0, length: 0) == .none)
}

@Test func onlyAPrintableUnmodifiedKeyIsText() {
    #expect(SDLWindow.producesText(keycode: 0x61, modifiers: []))
    #expect(SDLWindow.producesText(keycode: 0x20, modifiers: .shift))
    #expect(!SDLWindow.producesText(keycode: 0x61, modifiers: .control))
    #expect(!SDLWindow.producesText(keycode: 0x61, modifiers: .command))
    #expect(!SDLWindow.producesText(keycode: 0x08, modifiers: []), "backspace")
    #expect(!SDLWindow.producesText(keycode: 0x0D, modifiers: []), "return")
    #expect(!SDLWindow.producesText(keycode: 0x7F, modifiers: []), "delete")
    #expect(!SDLWindow.producesText(keycode: 0x4000_0050, modifiers: []), "an arrow")
}

@MainActor
@Test func motionWithTheButtonHeldIsADrag() throws {
    let (platform, window) = try hiddenWindow()
    platform.pumpEvents()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    for (kind, x) in [(MUI_EVENT_MOUSE_MOVE, Float(5)), (MUI_EVENT_MOUSE_DRAG, 9)] {
        var event = MUIEvent(); event.kind = UInt32(kind); event.window_id = window.id; event.x = x
        #expect(mui_push_event(&event))
    }
    platform.pumpEvents()
    #expect(describe(received) == ["move(5)", "drag(9)"])
}

@MainActor
@Test func theClipboardRoundTrips() throws {
    let (_, window) = try hiddenWindow()
    let saved = window.readClipboard()
    defer { if let saved { window.writeClipboard(saved) } }
    window.writeClipboard("MetalUI TI-A clipboard")
    #expect(window.readClipboard() == "MetalUI TI-A clipboard")
}
