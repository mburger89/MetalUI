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
