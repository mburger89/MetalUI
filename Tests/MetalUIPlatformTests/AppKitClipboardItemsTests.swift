import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// AppKit's clipboard items and lazy providers (rulings `CP-C`, `CP-D`, `CP-F`; spec tests 2.9-2.11). Every test passes the
// window a **private named `NSPasteboard`** (`CB-K`), never `.general`.

@MainActor
private func itemsWindow() throws -> (AppKitWindow, NSPasteboard) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try #require(try platform.openWindow(title: "CP items", size: Size(width: Pixels(200), height: Pixels(100)))
        as? AppKitWindow)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.metalui.tests.items.\(UUID().uuidString)"))
    window.pasteboard = pasteboard
    return (window, pasteboard)
}

private let graphType = PasteboardType(identifier: "com.example.metalui.graph", conformsTo: ["public.data"])
private let textType = PasteboardType(identifier: "public.utf8-plain-text")

private func item(_ n: Int) -> ClipboardItem {
    ClipboardItem(payloads: [ClipboardPayload(type: graphType, bytes: .now(Array("graph\(n)".utf8))),
                             ClipboardPayload(type: textType, bytes: .now(Array("text\(n)".utf8)))])
}

@MainActor private final class Calls { var count = 0; var mainThread: [Bool] = [] }

/// 2.9 — N items are written as N `NSPasteboardItem`s, listed by item and read by `(item, identifier)`; a second write
/// replaces them all. **Mutation:** `clearContents()` once per item (leaves one item).
@Test @MainActor func nItemsAreWrittenListedByItemAndReadByItemAndIdentifier() throws {
    let (window, pasteboard) = try itemsWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    #expect(window.writeClipboard(items: [item(0), item(1), item(2)]))
    #expect(pasteboard.pasteboardItems?.count == 3)
    let listed = window.clipboardItems()
    #expect(listed.count == 3)
    #expect(listed.allSatisfy { $0.contains("com.example.metalui.graph") && $0.contains(NSPasteboard.PasteboardType.string.rawValue) },
            "\(listed)")
    for n in 0..<3 {
        #expect(window.readClipboard(item: n, identifier: "com.example.metalui.graph") == Array("graph\(n)".utf8))
        #expect(window.readClipboard(item: n, identifier: NSPasteboard.PasteboardType.string.rawValue) == Array("text\(n)".utf8))
    }
    #expect(window.readClipboard(item: 3, identifier: "com.example.metalui.graph") == nil, "past the end")
    #expect(window.readClipboard(item: 1, identifier: "com.example.absent") == nil)
    #expect(window.readClipboard(identifier: "com.example.metalui.graph") == Array("graph0".utf8), "the single-type read is item 0")

    #expect(window.writeClipboard(items: [item(7)]))
    #expect(window.clipboardItems().count == 1, "a write replaces every item")
    #expect(!window.writeClipboard(items: []))
    #expect(window.clipboardItems().count == 1, "an empty write keeps the clipboard")
}

/// 2.10 — a `.later` representation is exported by the consumer's read, not at write; a read from a detached thread while the
/// main thread spins its run loop completes and the closure ran on the main thread. **Mutation:** the off-main hop dropped
/// (the closure runs on the reader's thread). "Provider retained by nobody" survives: the pasteboard retains it (`CP-O`).
@Test @MainActor func aLazyRepresentationIsExportedByTheReadEvenFromAnotherThread() throws {
    let (window, pasteboard) = try itemsWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    let calls = Calls()
    let lazyItem = ClipboardItem(payloads: [
        ClipboardPayload(type: graphType, bytes: .later { calls.count += 1; calls.mainThread.append(Thread.isMainThread); return [4, 5, 6] }),
        ClipboardPayload(type: textType, bytes: .now(Array("t".utf8)))])
    #expect(window.writeClipboard(items: [lazyItem]))
    #expect(calls.count == 0, "nothing exported at write")
    #expect(window.clipboardItems().first?.contains("com.example.metalui.graph") == true, "listed without exporting")
    #expect(calls.count == 0)
    #expect(window.readClipboard(item: 0, identifier: "com.example.metalui.graph") == [4, 5, 6])
    #expect(calls.count == 1 && calls.mainThread == [true], "exported once by the main-thread read")

    // A second lazy item read from another thread.
    let other = ClipboardItem(payloads: [
        ClipboardPayload(type: graphType, bytes: .later { calls.count += 1; calls.mainThread.append(Thread.isMainThread); return [8] })])
    #expect(window.writeClipboard(items: [other]))
    let before = calls.count
    final class Box: @unchecked Sendable { var data: Data?; var done = false }
    let box = Box()
    let name = pasteboard.name
    Thread.detachNewThread {
        let board = NSPasteboard(name: name)
        box.data = board.data(forType: NSPasteboard.PasteboardType("com.example.metalui.graph"))
        box.done = true
    }
    let deadline = Date().addingTimeInterval(20)
    while !box.done && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    #expect(box.done, "the detached read completed while the main thread spun (no hang)")
    #expect(box.data == Data([8]))
    #expect(calls.count == before + 1 && calls.mainThread.last == true, "the closure ran on the main thread")
}

/// 2.11 — none of this touches the general pasteboard. **Mutation:** write to `.general`.
@Test @MainActor func theItemsPathNeverTouchesTheGeneralPasteboard() throws {
    let general = NSPasteboard.general.changeCount
    let (window, pasteboard) = try itemsWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    #expect(window.writeClipboard(items: [item(0), item(1)]))
    _ = window.clipboardItems()
    _ = window.readClipboard(item: 1, identifier: "com.example.metalui.graph")
    #expect(window.writeClipboard(items: [ClipboardItem(payloads: [ClipboardPayload(type: graphType, bytes: .later { [1] })])]))
    #expect(NSPasteboard.general.changeCount == general)
}
