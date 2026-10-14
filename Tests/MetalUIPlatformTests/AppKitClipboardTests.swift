import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// The AppKit pasteboard (rulings `CB-D`, `CB-E`, `CB-K`; spec test 3.2). Every test passes the
// window a **private named `NSPasteboard`** and releases it, so no test touches the user's
// clipboard; the last one proves `.general` did not move.

@MainActor
private func clipboardWindow() throws -> (AppKitWindow, NSPasteboard) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try #require(try platform.openWindow(title: "CB", size: Size(width: Pixels(200), height: Pixels(100)))
        as? AppKitWindow)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.metalui.tests.\(UUID().uuidString)"))
    window.pasteboard = pasteboard
    return (window, pasteboard)
}

private let graphType = PasteboardType(identifier: "com.example.metalui.graph", conformsTo: ["public.data"])
private let textType = PasteboardType(identifier: "public.utf8-plain-text")

/// 3.2a — a write puts one item with every representation on the pasteboard, in order; the types
/// list and read back as the bytes written; a second write replaces everything, and a text-field
/// write (`writeClipboard(_ text:)`) replaces the custom types too.
/// Mutation: write to `.general`; skip `clearContents()`.
@Test @MainActor func aWriteListsReadsAndReplacesOnAPrivatePasteboard() throws {
    let (window, pasteboard) = try clipboardWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    #expect(window.writeClipboard([ClipboardRepresentation(type: graphType, bytes: [1, 2, 3]),
                                   ClipboardRepresentation(type: textType, bytes: Array("graph".utf8))]))
    let types = window.clipboardTypeIdentifiers()
    #expect(types.contains("com.example.metalui.graph") && types.contains(NSPasteboard.PasteboardType.string.rawValue))
    #expect(window.readClipboard(identifier: "com.example.metalui.graph") == [1, 2, 3])
    #expect(window.readClipboard() == "graph", "the text view is the string type")
    #expect(window.readClipboard(identifier: "com.example.absent") == nil)

    #expect(window.writeClipboard([ClipboardRepresentation(type: graphType, bytes: [9])]))
    #expect(window.readClipboard(identifier: "com.example.metalui.graph") == [9])
    #expect(window.readClipboard() == nil, "the earlier text is gone: a write replaces everything")

    window.writeClipboard("plain")
    #expect(window.readClipboard(identifier: "com.example.metalui.graph") == nil, "text replaces custom types")
    #expect(window.readClipboard() == "plain")

    #expect(!window.writeClipboard([]), "nothing to write: false")
    #expect(window.readClipboard() == "plain", "and the contents are kept")
}

/// 3.2b — the Edit menu's items follow `setClipboardCommands` (no caret): Copy, Cut and Paste
/// each enable on their own bit; the other Edit items stay disabled. Mutation: ignore the bits.
@Test @MainActor func validateMenuItemFollowsSetClipboardCommands() throws {
    let (window, pasteboard) = try clipboardWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    func enabled(_ selector: Selector) -> Bool {
        window.hostView.validateMenuItem(NSMenuItem(title: "x", action: selector, keyEquivalent: ""))
    }
    #expect(!enabled(#selector(MetalHostView.copy(_:))) && !enabled(#selector(MetalHostView.cut(_:)))
            && !enabled(#selector(MetalHostView.paste(_:))))
    window.setClipboardCommands([.copy])
    #expect(enabled(#selector(MetalHostView.copy(_:))))
    #expect(!enabled(#selector(MetalHostView.cut(_:))) && !enabled(#selector(MetalHostView.paste(_:))))
    window.setClipboardCommands([.cut, .paste])
    #expect(!enabled(#selector(MetalHostView.copy(_:))))
    #expect(enabled(#selector(MetalHostView.cut(_:))) && enabled(#selector(MetalHostView.paste(_:))))
    #expect(!enabled(#selector(MetalHostView.undo(_:))), "undo is not a clipboard command")
    window.setClipboardCommands([])
    #expect(!enabled(#selector(MetalHostView.paste(_:))))
}

/// 3.2c — none of the above touched the user's general pasteboard.
@Test @MainActor func theGeneralPasteboardIsNeverTouched() throws {
    let before = NSPasteboard.general.changeCount
    let (window, pasteboard) = try clipboardWindow()
    defer { pasteboard.releaseGlobally(); window.close() }
    _ = window.writeClipboard([ClipboardRepresentation(type: graphType, bytes: [1])])
    window.writeClipboard("t")
    _ = window.readClipboard()
    #expect(NSPasteboard.general.changeCount == before)
}
