// SDL's clipboard items (rulings CP-C, CP-D, CP-F; spec tests 2.12-2.15). SDL holds one mime set per clipboard: item 0 goes
// out under its native mimes (so another application pastes it), and when more than one item is written a private pack mime
// (`ClipboardItemPack`) carries all of them for MetalUI-to-MetalUI. Another process reading it is human check CP3.
import Dispatch
import Foundation
import MetalUIPlatform
import MetalUICore
import SDLBridge
import Testing
@testable import MetalUISDL

/// `ClipboardItemPack.mime`: the pack is `package` API of the root package, which this package cannot spell.
private let packMime = "application/x-com.metalui.clipboard-items"

@MainActor
private func itemsWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI clipboard items test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    mui_clipboard_clear()
    return (platform, window)
}

private let graph = PasteboardType(identifier: "com.acme.graph")
private let text = PasteboardType(identifier: "public.utf8-plain-text")

private func item(_ n: Int) -> ClipboardItem {
    ClipboardItem(payloads: [ClipboardPayload(type: graph, bytes: .now(Array("graph\(n)".utf8))),
                             ClipboardPayload(type: text, bytes: .now(Array("text\(n)".utf8)))])
}

@MainActor private final class Calls { var count = 0 }

@Suite(.serialized)
@MainActor
struct SDLClipboardItemsTests {
    /// 2.12: one item writes no pack, and its listing is `CB-`'s. Mutation: always write the pack.
    @Test func oneItemWritesNoPack() throws {
        let (platform, window) = try itemsWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard(items: [item(0)]))
        #expect(!mui_clipboard_has(packMime), "a one-item write is byte for byte CB-H's box")
        #expect(window.clipboardTypeIdentifiers() == ["com.acme.graph", "public.utf8-plain-text"])
        #expect(window.clipboardItems() == [["com.acme.graph", "public.utf8-plain-text"]])
    }

    /// 2.13: three items write item 0 natively plus the pack; a read by `(2, id)` returns item 2's bytes, a native read item 0's,
    /// and the pack's mime is not listed as a type. Mutation: skip the pack (`(2, id)` reads nil), or list the pack's type.
    @Test func threeItemsWriteItemZeroNativelyAndThePackForTheRest() throws {
        let (platform, window) = try itemsWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard(items: [item(0), item(1), item(2)]))
        #expect(mui_clipboard_has(packMime))
        #expect(window.readClipboard(identifier: "com.acme.graph") == Array("graph0".utf8), "a native read is item 0")
        #expect(window.readClipboard() == "text0")
        #expect(window.clipboardTypeIdentifiers() == ["com.acme.graph", "public.utf8-plain-text"], "the pack is not a type")
        #expect(window.clipboardItems() == Array(repeating: ["com.acme.graph", "public.utf8-plain-text"], count: 3))
        for n in 0..<3 {
            #expect(window.readClipboard(item: n, identifier: "com.acme.graph") == Array("graph\(n)".utf8))
            #expect(window.readClipboard(item: n, identifier: "public.utf8-plain-text") == Array("text\(n)".utf8))
        }
        #expect(window.readClipboard(item: 3, identifier: "com.acme.graph") == nil)
        // A later single-item write replaces the pack.
        #expect(window.writeClipboard(items: [item(9)]))
        #expect(window.clipboardItems().count == 1)
        #expect(window.readClipboard(item: 1, identifier: "com.acme.graph") == nil)
    }

    /// 2.14: a malformed pack is ignored and the native single item is used. Mutation: trust a bad pack (it decodes `nil` and the
    /// listing is empty, or it traps).
    @Test func aMalformedPackFallsBackToTheSingleItem() throws {
        let (platform, window) = try itemsWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        let mimes = ["application/x-com.acme.graph", packMime]
        let names: [UnsafeMutablePointer<CChar>?] = mimes.map { duplicateCString($0) }
        defer { names.forEach { free($0) } }
        let native: [UInt8] = Array("native".utf8)
        let garbage: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        var wrote = false
        native.withUnsafeBufferPointer { a in
            garbage.withUnsafeBufferPointer { b in
                let constNames: [UnsafePointer<CChar>?] = names.map { UnsafePointer($0) }
                let pointers: [UnsafePointer<UInt8>?] = [a.baseAddress, b.baseAddress]
                let sizes: [Int] = [native.count, garbage.count]
                wrote = mui_clipboard_set(constNames, pointers, sizes, 2)
            }
        }
        #expect(wrote)
        #expect(mui_clipboard_has(packMime))
        #expect(window.clipboardItems() == [["com.acme.graph"]], "one item from the native mimes")
        #expect(window.readClipboard(item: 0, identifier: "com.acme.graph") == native)
        #expect(window.readClipboard(item: 1, identifier: "com.acme.graph") == nil)
    }

    /// 2.15: `.later` is realised at write on SDL (`CP-F`). Mutation: skip the realise (the exporter is never called and the
    /// representation is dropped).
    @Test func aLaterRepresentationIsExportedAtWrite() throws {
        let (platform, window) = try itemsWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        let calls = Calls()
        let lazyItem = ClipboardItem(payloads: [ClipboardPayload(type: graph, bytes: .later { calls.count += 1; return [4, 5] })])
        #expect(window.writeClipboard(items: [lazyItem, item(1)]))
        #expect(calls.count == 1, "exported by the write itself")
        #expect(window.readClipboard(item: 0, identifier: "com.acme.graph") == [4, 5])
        #expect(window.readClipboard(identifier: "com.acme.graph") == [4, 5])
        #expect(calls.count == 1, "reads do not export again")
    }
}

/// `strdup`, spelled `_strdup` where the UCRT deprecates the POSIX name.
private func duplicateCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    #if os(Windows)
    _strdup(string)
    #else
    strdup(string)
    #endif
}
