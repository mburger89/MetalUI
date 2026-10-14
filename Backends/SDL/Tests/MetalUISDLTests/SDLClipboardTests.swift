// SDL's typed clipboard (item S3, rulings CB-D, CB-H, CB-I, CB-L; spec tests 4.1
// and 4.2). A real SDL clipboard round trip in one process: SDL holds our data
// callback with no X11/Wayland server needed on the dummy and offscreen drivers.
// What cannot be tested here, another process reading it, is human check CB2.
import Dispatch
import Foundation
import MetalUIPlatform
import MetalUICore
import SDLBridge
import Testing
@testable import MetalUISDL

@MainActor
private func clipboardWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI clipboard test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    mui_clipboard_clear()
    return (platform, window)
}

private let graph = PasteboardType(identifier: "com.acme.graph")
private let text = PasteboardType(identifier: "public.utf8-plain-text")

private func rep(_ type: PasteboardType, _ string: String) -> ClipboardRepresentation {
    ClipboardRepresentation(type: type, bytes: Array(string.utf8))
}

@Suite(.serialized)
@MainActor
struct SDLClipboardTests {
    /// 4.1: set, has, get, types, text fallback, absent, replace and clear.
    @Test func aCustomTypeAndItsTextFallbackRoundTripThroughSDL() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard([rep(graph, "{nodes}"), rep(text, "nodes")]))
        #expect(window.clipboardTypeIdentifiers() == ["com.acme.graph", "public.utf8-plain-text"])
        #expect(window.readClipboard(identifier: "com.acme.graph") == Array("{nodes}".utf8))
        #expect(window.readClipboard(identifier: "public.utf8-plain-text") == Array("nodes".utf8))
        #expect(window.readClipboard() == "nodes", "the text-only path reads the fallback")
        #expect(window.readClipboard(identifier: "com.acme.absent") == nil)
        #expect(mui_clipboard_has("application/x-com.acme.graph"))
        #expect(!mui_clipboard_has("application/x-com.acme.absent"))
        mui_clipboard_clear()
        #expect(window.clipboardTypeIdentifiers() == [])
        #expect(window.readClipboard(identifier: "com.acme.graph") == nil)
        #expect(window.readClipboard() == nil)
    }

    /// 4.1: a replace runs the old cleanup exactly once, a clear the last one,
    /// and no box is left alive (the leak pin, `CB-H`).
    @Test func theCleanupRunsOnceForEveryBoxAndNoBoxLeaks() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        let cleaned = mui_clipboard_cleanup_count()
        let live = mui_clipboard_live_count()
        #expect(window.writeClipboard([rep(graph, "one")]))
        #expect(mui_clipboard_live_count() == live + 1)
        #expect(window.writeClipboard([rep(graph, "two"), rep(text, "t")]))
        #expect(mui_clipboard_cleanup_count() == cleaned + 1, "the replaced box was cleaned once")
        #expect(mui_clipboard_live_count() == live + 1)
        #expect(window.readClipboard(identifier: "com.acme.graph") == Array("two".utf8))
        window.writeClipboard("plain")
        #expect(mui_clipboard_cleanup_count() == cleaned + 2, "a text write replaces the typed box")
        #expect(window.readClipboard(identifier: "com.acme.graph") == nil)
        #expect(window.writeClipboard([rep(graph, "three")]))
        mui_clipboard_clear()
        mui_clipboard_clear()
        #expect(mui_clipboard_cleanup_count() == cleaned + 3, "a second clear frees nothing twice")
        #expect(mui_clipboard_live_count() == live)
    }

    /// `CB-I`: zero-byte representations are dropped; nothing left is a no-op
    /// returning false that keeps the clipboard's contents.
    @Test func emptyRepresentationsAreDroppedAndAnAllEmptyWriteKeepsTheClipboard() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard([rep(graph, "kept")]))
        let cleaned = mui_clipboard_cleanup_count()
        #expect(!window.writeClipboard([ClipboardRepresentation(type: graph, bytes: [])]))
        #expect(!window.writeClipboard([]))
        #expect(mui_clipboard_cleanup_count() == cleaned)
        #expect(window.readClipboard(identifier: "com.acme.graph") == Array("kept".utf8))
        #expect(window.writeClipboard([ClipboardRepresentation(type: graph, bytes: []), rep(text, "t")]))
        #expect(window.clipboardTypeIdentifiers() == ["public.utf8-plain-text"])
    }

    /// `CB-I`: no size cap; 8 MiB survives byte for byte.
    @Test func eightMebibytesRoundTrip() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        let big = (0..<(8 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) }
        #expect(window.writeClipboard([ClipboardRepresentation(type: graph, bytes: big)]))
        #expect(window.readClipboard(identifier: "com.acme.graph") == big)
    }

    /// `CB-D`: two identifiers that map to one mime keep the first.
    @Test func twoRepresentationsOfOneMimeKeepTheFirst() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard([rep(graph, "first"), rep(graph, "second")]))
        #expect(window.clipboardTypeIdentifiers() == ["com.acme.graph"])
        #expect(window.readClipboard(identifier: "com.acme.graph") == Array("first".utf8))
    }

    /// `CB-D`: a mixed-case identifier is written as a lower-case mime and read back as itself.
    @Test func aMixedCaseIdentifierRoundTripsThroughItsMime() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        let mixed = PasteboardType(identifier: "Com.Acme.Graph")
        #expect(window.writeClipboard([rep(mixed, "x")]))
        #expect(window.clipboardTypeIdentifiers() == ["Com.Acme.Graph"])
        #expect(window.readClipboard(identifier: "Com.Acme.Graph") == Array("x".utf8))
        #expect(window.readClipboard(identifier: "com.acme.graph") == nil)
    }

    /// `CB-E`: SDL has no native Edit menu; the commands are recorded only.
    @Test func setClipboardCommandsRecords() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        window.setClipboardCommands([.copy, .paste])
        #expect(window.clipboardCommands == [.copy, .paste])
    }

    /// 4.2 (`CB-H`): the data callback is pure, so it needs no main actor. The
    /// request is served from a detached thread while the main actor is blocked
    /// in a bounded wait (not a sleep); a callback that hopped to the main queue
    /// would time out, red, not hang.
    @Test func theCallbackNeedsNoMainActor() throws {
        let (platform, window) = try clipboardWindow()
        withExtendedLifetime(platform) {}
        defer { mui_clipboard_clear() }
        #expect(window.writeClipboard([rep(graph, "payload-bytes")]))
        let done = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Thread.detachNewThread {
            box.size = mui_clipboard_callback_probe("application/x-com.acme.graph")
            done.signal()
        }
        let outcome = done.wait(timeout: .now() + 10)
        #expect(outcome == .success, "the callback was served while the main actor was blocked")
        #expect(box.size == "payload-bytes".utf8.count)
    }
}

private final class ResultBox: @unchecked Sendable { var size = -1 }
