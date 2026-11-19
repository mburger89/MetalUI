import MetalUITestSupport
import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// TI-A on AppKit: the host view is an `NSTextInputClient`. The input context's
// callbacks are driven directly, as the context drives them, and real
// `NSEvent`s go through `keyDown(with:)`.

@MainActor
private func hostWindow() throws -> (AppKitWindow, MetalHostView, EventLog) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    installAppKitEventSignal()
    let platform = AppKitPlatform(device: device)
    let window = try #require(try platform.openWindow(title: "TI", size: Size(width: Pixels(300), height: Pixels(100)))
        as? AppKitWindow)
    let log = EventLog()
    window.onInput = { log.events.append($0); return true }
    return (window, window.hostView, log)
}

@MainActor
private final class EventLog {
    var events: [InputEvent] = []
    var described: [String] {
        events.map {
            switch $0 {
            case .textInput(let text): "text(\(text))"
            case .textComposition(let c): "compose(\(c.text),\(c.selection))"
            case .keyDown(let key): "key(\(key.charactersIgnoringModifiers.unicodeScalars.map { String($0.value, radix: 16) }.joined()))"
            case .mouseDragged: "drag"
            default: "other"
            }
        }
    }
}

@MainActor
private func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [],
                      in window: AppKitWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                  windowNumber: 0, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
}

private let caret = Bounds(origin: Point(x: Pixels(40), y: Pixels(10)), size: Size(width: Pixels(1), height: Pixels(16)))

@MainActor
@Test func theInputContextsCallbacksBecomeTextEvents() throws {
    let (_, view, log) = try hostWindow()
    view.setMarkedText(NSAttributedString(string: "にほ"), selectedRange: NSRange(location: 2, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(view.hasMarkedText() && view.markedRange() == NSRange(location: 0, length: 2))
    view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(!view.hasMarkedText() && view.markedRange().location == NSNotFound)
    // `unmarkText` commits what is marked; with nothing marked it sends nothing.
    view.setMarkedText("ka", selectedRange: NSRange(location: 1, length: 1),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    view.unmarkText()
    view.unmarkText()
    #expect(log.described == ["compose(にほ,2..<2)", "text(日本)", "compose(ka,1..<2)", "text(ka)"])
}

@MainActor
@Test func keysGoThroughTheInputContextOnlyWhileTextInputIsOn() throws {
    let (window, view, log) = try hostWindow()
    // Off: a letter is a plain key.
    view.keyDown(with: try keyEvent("a", keyCode: 0, in: window))
    #expect(log.described == ["key(61)"])
    log.events = []
    window.setTextInputArea(caret)
    #expect(view.textInputCaret == caret)
    // On: a letter is text; an arrow is declined by the context and comes back
    // as the key it was; a command key never goes to the context.
    view.keyDown(with: try keyEvent("a", keyCode: 0, in: window))
    view.keyDown(with: try keyEvent("\u{f702}", keyCode: 123, modifiers: [.numericPad, .function], in: window))
    view.keyDown(with: try keyEvent("c", keyCode: 8, modifiers: .command, in: window))
    #expect(log.described == ["text(a)", "key(f702)", "key(63)"])
    log.events = []
    window.setTextInputArea(nil)
    view.keyDown(with: try keyEvent("a", keyCode: 0, in: window))
    #expect(log.described == ["key(61)"], "off again")
}

/// `TRM-BM`: with the keypad hint on, a keypad key (virtual key code 87, a `5` on the numeric keypad) skips the input
/// context and is a key event with `isKeypad`; off, it is text like any key; the main-row 5 and a ⌘-keypad key are
/// unchanged either way. Mutation: ignore `rawKeypadKeys` in `keyDown` (the "on" row is text), or drop the key-code
/// test (the main-row 5 becomes a key).
@MainActor
@Test func theKeypadHintMakesKeypadKeysKeysNotText() throws {
    let (window, view, log) = try hostWindow()
    func describe() -> [String] {
        log.events.map {
            switch $0 {
            case .textInput(let text): "text(\(text))"
            case .keyDown(let key): "key(\(key.characters),\(key.isKeypad ? "kp" : "-"))"
            default: "other"
            }
        }
    }
    window.setTextInputArea(caret)
    view.keyDown(with: try keyEvent("5", keyCode: 87, modifiers: .numericPad, in: window))
    #expect(describe() == ["text(5)"], "hint off: text: \(describe())")
    log.events = []
    window.setRawKeypadKeys(true)
    #expect(view.rawKeypadKeys)
    view.keyDown(with: try keyEvent("5", keyCode: 87, modifiers: .numericPad, in: window))
    view.keyDown(with: try keyEvent("5", keyCode: 23, in: window))
    view.keyDown(with: try keyEvent("5", keyCode: 87, modifiers: [.numericPad, .command], in: window))
    #expect(describe() == ["key(5,kp)", "text(5)", "key(5,kp)"], "hint on: \(describe())")
    log.events = []
    window.setRawKeypadKeys(false)
    view.keyDown(with: try keyEvent("5", keyCode: 87, modifiers: .numericPad, in: window))
    #expect(describe() == ["text(5)"], "off again: \(describe())")
}

@MainActor
@Test func stoppingTextInputDropsAnUnfinishedComposition() throws {
    let (window, view, _) = try hostWindow()
    window.setTextInputArea(caret)
    view.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    window.setTextInputArea(nil)
    #expect(!view.hasMarkedText())
}

@MainActor
@Test func theCandidateWindowGoesAtTheCaretOnScreen() throws {
    let (window, view, _) = try hostWindow()
    #expect(view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil) == .zero)
    window.setTextInputArea(caret)
    let rect = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
    let expected = try #require(view.window).convertToScreen(
        view.convert(NSRect(x: 40, y: 10, width: 1, height: 16), to: nil))
    #expect(rect == expected && rect.size == NSSize(width: 1, height: 16))
}

@Test func anInputMethodsUTF16RangeBecomesCharacterOffsets() {
    let text = "a😀b\u{65}\u{301}"   // a, emoji (2 units), b, e + combining acute (2 units, 1 Character)
    #expect(MetalHostView.characterRange(NSRange(location: 1, length: 2), in: text) == 1..<2)
    #expect(MetalHostView.characterRange(NSRange(location: 3, length: 0), in: text) == 2..<2)
    // Inside a grapheme rounds down to its start; past the end clamps.
    #expect(MetalHostView.characterRange(NSRange(location: 2, length: 0), in: text) == 1..<1)
    #expect(MetalHostView.characterRange(NSRange(location: 4, length: 9), in: text) == 3..<4)
    #expect(MetalHostView.characterRange(NSRange(location: NSNotFound, length: 0), in: text) == 4..<4)
}

@MainActor
@Test func aDragIsItsOwnEvent() throws {
    let (window, view, log) = try hostWindow()
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 5, y: 5),
                                                modifierFlags: [], timestamp: 0,
                                                windowNumber: 0, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1))
    _ = window
    view.mouseDragged(with: event)
    #expect(log.described == ["drag"])
}

/// The real system clipboard, restored afterwards.
@MainActor
@Test func theClipboardIsTheGeneralPasteboard() throws {
    let (window, _, _) = try hostWindow()
    let saved = NSPasteboard.general.string(forType: .string)
    defer {
        NSPasteboard.general.clearContents()
        if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }
    window.writeClipboard("MetalUI TI-A \(UUID())")
    let read = window.readClipboard()
    #expect(read == NSPasteboard.general.string(forType: .string) && read?.hasPrefix("MetalUI TI-A") == true)
}

// MARK: - SecureField (ruling `SCF-B`, record 393)

@MainActor
private final class HoldLog {
    var calls: [String] = []
}

@MainActor
private func secureWindow() throws -> (AppKitWindow, MetalHostView, EventLog, HoldLog) {
    let (window, view, log) = try hostWindow()
    let holds = HoldLog()
    window.secureEventInput = SecureEventInput(enable: { holds.calls.append("on") },
                                               disable: { holds.calls.append("off") })
    return (window, view, log, holds)
}

/// Secure keyboard entry is held exactly while a secure field is focused in a key window: focus is one enable, a repeat
/// is none, resigning key releases and becoming key takes it again, blur releases, and a close releases once — a second
/// close or blur releases nothing more. **Mutation:** `windowWillClose` skips `refreshSecureEventInput()` (the close
/// leaves the hold on).
@MainActor
@Test func secureEventInputIsBalancedAcrossFocusKeyWindowAndClose() throws {
    let (window, _, _, holds) = try secureWindow()
    window.setSecureTextInput(true)
    window.setSecureTextInput(true)
    #expect(holds.calls == ["on"], "a repeated request is one hold")
    window.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
    #expect(holds.calls == ["on", "off"])
    window.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
    #expect(holds.calls == ["on", "off", "on"])
    window.setSecureTextInput(false)
    window.setSecureTextInput(false)
    #expect(holds.calls == ["on", "off", "on", "off"])
    window.setSecureTextInput(true)
    window.close()
    #expect(holds.calls == ["on", "off", "on", "off", "on", "off"], "the close released the hold")
    #expect(window.secureEventInput.held == 0)
    window.setSecureTextInput(false)
    #expect(holds.calls.count == 6, "nothing is released twice")
}

/// What a key types into a secure field, with no input context: its characters when all are printable, nothing for a
/// function key, a control character or a ⌃-key (those are keys). **Mutation:** `isPrintable` answers `true` (the arrow's
/// private-use code is typed as text). The input context routes a plain key in a test window exactly as the bypass does,
/// so the `keyDown(with:)` branch itself cannot be told from it headlessly; it is the human check `SCF4`.
@MainActor
@Test func aSecureFieldTypesPrintableCharactersAndKeepsTheRestAsKeys() throws {
    let (window, _, _, _) = try secureWindow()
    #expect(MetalHostView.secureTypedText(try keyEvent("a", keyCode: 0, in: window)) == "a")
    #expect(MetalHostView.secureTypedText(try keyEvent("\u{b4}", keyCode: 14, modifiers: [.option], in: window)) == "\u{b4}")
    #expect(MetalHostView.secureTypedText(try keyEvent("\u{f702}", keyCode: 123, in: window)) == nil)
    #expect(MetalHostView.secureTypedText(try keyEvent("\r", keyCode: 36, in: window)) == nil)
    #expect(MetalHostView.secureTypedText(try keyEvent("\u{7f}", keyCode: 51, in: window)) == nil)
    #expect(MetalHostView.secureTypedText(try keyEvent("k", keyCode: 40, modifiers: [.control], in: window)) == nil)
}

/// A secure field takes no input method: marked text from the input context is dropped, a key reaches the window as
/// text or a key, and the Edit menu's Cut and Copy are off while Paste stays on. **Mutation:** the Cut/Copy `if` in
/// `validateMenuItem` is disabled.
@MainActor
@Test func aSecureFieldBypassesTheInputMethodAndDisablesCutAndCopy() throws {
    let (window, view, log, _) = try secureWindow()
    window.setTextInputArea(caret)
    window.setSecureTextInput(true)
    view.keyDown(with: try keyEvent("a", keyCode: 0, in: window))
    view.keyDown(with: try keyEvent("\u{f702}", keyCode: 123, in: window))
    // ⌥E is a dead key to the input context (marked text); a secure field types its character.
    view.keyDown(with: try keyEvent("\u{b4}", keyCode: 14, modifiers: [.option], in: window))
    #expect(log.described == ["text(a)", "key(f702)", "text(\u{b4})"])
    #expect(!view.hasMarkedText())
    view.setMarkedText(NSAttributedString(string: "にほ"), selectedRange: NSRange(location: 2, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(!view.hasMarkedText() && log.events.count == 3, "marked text from the input context is dropped")

    let copy = NSMenuItem(title: "Copy", action: #selector(MetalHostView.copy(_:)), keyEquivalent: "c")
    let cut = NSMenuItem(title: "Cut", action: #selector(MetalHostView.cut(_:)), keyEquivalent: "x")
    let paste = NSMenuItem(title: "Paste", action: #selector(MetalHostView.paste(_:)), keyEquivalent: "v")
    #expect(!view.validateMenuItem(copy) && !view.validateMenuItem(cut))
    #expect(view.validateMenuItem(paste))
    window.setSecureTextInput(false)
    #expect(view.validateMenuItem(copy) && view.validateMenuItem(cut), "a plain field copies and cuts")
}
