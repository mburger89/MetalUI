import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// The AppKit clipboard change check (ruling `CP-G`; spec test 1.8). `NSPasteboard` posts nothing, so the window compares
// `changeCount` on becoming key, at a mouse-down and at a key-down, and after its own write. Every test uses a **private
// named pasteboard** (`CB-K`), never `.general`.

@MainActor
private func changeWindow() throws -> (AppKitWindow, NSPasteboard, Counter) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try #require(try platform.openWindow(title: "CP", size: Size(width: Pixels(200), height: Pixels(100)))
        as? AppKitWindow)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.metalui.tests.change.\(UUID().uuidString)"))
    window.pasteboard = pasteboard
    window.notificationCenter = NotificationCenter()   // a private centre: AppKit's own observers never see our posts
    let counter = Counter()
    window.setClipboardChangeHandler { counter.count += 1 }
    return (window, pasteboard, counter)
}

@MainActor private final class Counter { var count = 0 }

private func foreignWrite(_ pasteboard: NSPasteboard, _ text: String) {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

private func keyDown() -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0))
}

/// 1.8b — a foreign write fires the handler exactly once at becoming key, at a mouse-down and at a key-down, and an unchanged
/// `changeCount` never does. **Mutation:** compare against the wrong count (the count at install, never updated) or fire every poll.
@Test @MainActor func aForeignWriteFiresTheHandlerAtBecomingKeyAMouseDownAndAKeyDown() throws {
    let (window, pasteboard, counter) = try changeWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    let nsWindow = try #require(window.window)
    func becomeKey() { window.notificationCenter.post(name: NSWindow.didBecomeKeyNotification, object: nsWindow) }

    becomeKey()
    #expect(counter.count == 0, "nothing changed since the handler was installed")
    foreignWrite(pasteboard, "one")
    becomeKey()
    #expect(counter.count == 1, "becoming key sees the foreign write")
    becomeKey()
    #expect(counter.count == 1, "the same changeCount again: no call")

    foreignWrite(pasteboard, "two")
    _ = window.hostView.onInput?(.mouseDown(MouseEvent(position: Point(x: Pixels(5), y: Pixels(5)))))
    #expect(counter.count == 2, "a mouse-down sees it")
    _ = window.hostView.onInput?(.mouseDown(MouseEvent(position: Point(x: Pixels(5), y: Pixels(5)))))
    #expect(counter.count == 2)

    foreignWrite(pasteboard, "three")
    _ = window.hostView.onInput?(keyDown())
    #expect(counter.count == 3, "a key-down sees it")
    _ = window.hostView.onInput?(.mouseMoved(MouseEvent(position: Point(x: Pixels(5), y: Pixels(5)))))
    foreignWrite(pasteboard, "four")
    _ = window.hostView.onInput?(.mouseMoved(MouseEvent(position: Point(x: Pixels(5), y: Pixels(5)))))
    #expect(counter.count == 3, "a pointer move is not a poll point")
}

/// 1.8c — the window's own write calls the handler once and the next poll does not call it again; removing the handler stops
/// every call. **Mutation:** skip `noteClipboardWrite` (the next poll would report the own write).
@Test @MainActor func anOwnWriteCallsTheHandlerOnceAndARemovedHandlerNever() throws {
    let (window, pasteboard, counter) = try changeWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    let type = PasteboardType(identifier: "com.example.cp")
    #expect(window.writeClipboard(items: [ClipboardItem(payloads: [ClipboardPayload(type: type, bytes: .now([1]))])]))
    #expect(counter.count == 1)
    window.pollClipboardChange()
    #expect(counter.count == 1, "the own write is not reported again")
    window.writeClipboard("text")
    #expect(counter.count == 2, "a text write is a change too")
    window.setClipboardChangeHandler(nil)
    foreignWrite(pasteboard, "x")
    window.pollClipboardChange()
    #expect(counter.count == 2)
}
