import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// Drag and drop on AppKit, lane 2, tests 2.1–2.9 (rulings `DN-K`, `DN-L`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §6.4). A real
// `AppKitPlatform` window, a real `Window` over it, and a drag delivered through
// the `NSDraggingDestination` methods of its own `MetalHostView` with the
// probe's `FakeDrag` (`docs/probes/swiftui-drag-and-drop.swift`, group `R`) —
// valid for MetalUI, which resolves from `draggingLocation` alone. Each test
// closes its window.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class ALog {
    var entries: [String] = []
}

/// The probe's fake `NSDraggingInfo`: a location in WINDOW coordinates
/// (AppKit's bottom-left origin) and a pasteboard.
private final class FakeDrag: NSObject, NSDraggingInfo {
    let window: NSWindow
    var location: NSPoint
    let pb: NSPasteboard
    var mask: NSDragOperation = .every
    init(window: NSWindow, location: NSPoint, pb: NSPasteboard) {
        self.window = window; self.location = location; self.pb = pb
    }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { mask }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 7 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

/// A pasteboard of its own, released by the caller.
@MainActor private func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("MetalUI-dnd-\(UUID().uuidString)"))
}

/// A real 400 × 200 AppKit window over `content`, one frame drawn.
@MainActor private func appKitWindow<Root: Element>(
    _ content: @escaping @MainActor () -> Root
) throws -> (Window, AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "DnD \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let window = Window(platformWindow: platformWindow, startsDisplayLink: false, content: content)
    window.drawFrameIfNeeded()
    return (window, appKit, nsWindow)
}

/// A 200 × 200 box beside a 200 × 200 `T` destination at the right half,
/// logging `T=<bool>` and `drop(<items>)@<location>`.
@MainActor private func pair<T: Transferable>(_ type: T.Type, _ log: ALog) -> some Element {
    Row {
        Box().frame(width: px(200), height: px(200))
        Box().frame(width: px(200), height: px(200)).dropDestination(for: T.self, action: { items, at in
            log.entries.append("drop(\(items))@(\(at.x.value), \(at.y.value))"); return true
        }, isTargeted: { log.entries.append("T=\($0)") })
    }
}

/// The window point AppKit reports for MetalUI's top-left point `(x, y)` in a
/// 200-pt-tall content view: the same x, `200 − y`.
private func windowPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 200 - y) }

// MARK: - 2.1

/// **2.1** (`DN-L`). The host view registers, once, for `public.item`,
/// `public.data`, `public.url`, `public.file-url` and `public.utf8-plain-text`.
/// Mutation **M2a** (register none).
@Test @MainActor func theHostViewRegistersForDraggedTypes() throws {
    let (window, appKit, nsWindow) = try appKitWindow { Box() }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let registered = Set(appKit.hostView.registeredDraggedTypes.map(\.rawValue))
    #expect(registered == ["public.item", "public.data", "public.url", "public.file-url",
                           "public.utf8-plain-text"], "DN-L: \(registered)")
}

// MARK: - 2.2–2.5: drops in

/// **2.2** (`DN-L`). A Finder file drag over a `URL` destination: entering
/// answers `.copy` and targets it; the drop answers `true` and the action gets
/// the file URL at the destination-local point, y flipped from AppKit's
/// bottom-left window coordinates.
/// Mutation **M2b** (skip the y flip).
@Test @MainActor func aFinderFileDropReachesAURLDestination() throws {
    let log = ALog()
    let (window, appKit, nsWindow) = try appKitWindow { pair(URL.self, log) }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let pb = scratchPasteboard()
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
    try #require(pb.types?.contains(.fileURL) == true, "set up: a file URL on the pasteboard: \(pb.types ?? [])")
    let info = FakeDrag(window: nsWindow, location: windowPoint(330, 140), pb: pb)
    let host = appKit.hostView
    #expect(host.draggingEntered(info) == .copy, "an accepting destination answers copy")
    #expect(log.entries == ["T=true"])
    #expect(host.draggingUpdated(info) == .copy, "and keeps answering it")
    #expect(host.prepareForDragOperation(info))
    #expect(host.performDragOperation(info), "the drop is taken")
    #expect(log.entries == ["T=true", "T=false", "drop([file:///tmp/a.txt])@(130.0, 140.0)"],
            "the file URL at the destination-local, top-left point: \(log.entries)")
}

/// **2.3** (`R3`, `DN-L`). A string over a `URL` destination: no operation,
/// never targeted, and the drop is refused.
/// Mutation **M2c** (answer `.copy` unconditionally).
@Test @MainActor func aStringDropOnAURLDestinationAnswersNoOperation() throws {
    let log = ALog()
    let (window, appKit, nsWindow) = try appKitWindow { pair(URL.self, log) }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let pb = scratchPasteboard()
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.setString("hello", forType: .string)
    let info = FakeDrag(window: nsWindow, location: windowPoint(330, 140), pb: pb)
    #expect(appKit.hostView.draggingEntered(info) == [], "R3: no operation")
    #expect(appKit.hostView.draggingUpdated(info) == [], "R3: still none")
    #expect(!appKit.hostView.performDragOperation(info), "refused")
    #expect(log.entries == [], "never targeted, never dropped")
}

/// **2.4** (`R1`, `DN-L`). Leaving the window un-targets.
/// Mutation **M2d** (ignore `draggingExited`).
@Test @MainActor func draggingExitedUnTargets() throws {
    let log = ALog()
    let (window, appKit, nsWindow) = try appKitWindow { pair(String.self, log) }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let pb = scratchPasteboard()
    defer { pb.releaseGlobally() }
    pb.clearContents()
    pb.setString("hello", forType: .string)
    let info = FakeDrag(window: nsWindow, location: windowPoint(330, 140), pb: pb)
    #expect(appKit.hostView.draggingEntered(info) == .copy)
    appKit.hostView.draggingExited(info)
    #expect(log.entries == ["T=true", "T=false"], "R1: \(log.entries)")
}

/// Counts every read a pasteboard makes of a promised item (AppKit calls back
/// on the reading thread — the main thread here).
private final class CountingProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    var reads: [String] = []
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        reads.append(type.rawValue)
        if type == .string { item.setString("x", forType: .string) }
        else { item.setData(Data([0x89, 0x50]), forType: type) }
    }
}

/// **2.5** (`DN-L`, `DN-C`). An item promising `public.png` and
/// `public.utf8-plain-text` dropped on a `String` destination is read once,
/// for the type the destination imports — nothing while hovering.
/// Mutation **M2e** (eager `data(forType:)` for every type).
@Test @MainActor func onlyTheImportedTypeIsReadFromThePasteboard() throws {
    let log = ALog()
    let (window, appKit, nsWindow) = try appKitWindow { pair(String.self, log) }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let pb = scratchPasteboard()
    defer { pb.releaseGlobally() }
    let provider = CountingProvider()
    let item = NSPasteboardItem()
    item.setDataProvider(provider, forTypes: [.png, .string])
    pb.clearContents()
    try #require(pb.writeObjects([item]), "set up: the promise is written")
    let info = FakeDrag(window: nsWindow, location: windowPoint(330, 140), pb: pb)
    #expect(appKit.hostView.draggingEntered(info) == .copy)
    #expect(provider.reads == [], "hovering reads nothing")
    #expect(appKit.hostView.performDragOperation(info))
    #expect(provider.reads == ["public.utf8-plain-text"], "one read, the imported type: \(provider.reads)")
    #expect(log.entries.last == "drop([\"x\"])@(130.0, 140.0)", "\(log.entries)")
}

// MARK: - 2.6–2.7: the conversions

/// **2.6** (`DN-L`). A pasteboard type carries its `UTType` supertypes.
/// Mutation **M2f** (empty `conformsTo`).
@Test @MainActor func pasteboardTypesCarryTheirUTTypeSupertypes() {
    let png = AppKitDragAndDrop.pasteboardType("public.png")
    #expect(png.identifier == "public.png")
    #expect(Set(png.conformsTo).isSuperset(of: ["public.image", "public.data"]), "\(png.conformsTo)")
    #expect(!png.conformsTo.contains("public.png"), "never itself")
    let fileURL = AppKitDragAndDrop.pasteboardType("public.file-url")
    #expect(fileURL.conformsTo.contains("public.url"), "\(fileURL.conformsTo)")
    let text = AppKitDragAndDrop.pasteboardType("public.utf8-plain-text")
    #expect(text.satisfies("public.plain-text") && text.satisfies("public.text"), "\(text.conformsTo)")
}

/// **2.7** (`DN-K` item 2). A dragging item for the window's edge carries every
/// representation's bytes on one pasteboard item, and an image: a file URL's
/// is the workspace icon's size, a string's a non-empty badge.
/// Mutation **M2g** (write the first representation only).
@Test @MainActor func anExternalDragItemCarriesEveryRepresentationAndAnImage() throws {
    let url = PasteboardType(identifier: "public.url", conformsTo: ["public.data", "public.item"])
    let fileURL = PasteboardType(identifier: "public.file-url",
                                 conformsTo: ["public.url", "public.data", "public.item"])
    let path = "file:///tmp/a.txt"
    let fileItem = AppKitDragAndDrop.draggingItem(for: [DragRepresentation(type: url, bytes: Array(path.utf8)),
                                                        DragRepresentation(type: fileURL, bytes: Array(path.utf8))],
                                                  at: NSPoint(x: 10, y: 20))
    let pasteboardItem = try #require(fileItem.item as? NSPasteboardItem, "a pasteboard item")
    #expect(pasteboardItem.data(forType: NSPasteboard.PasteboardType("public.url")) == Data(path.utf8))
    #expect(pasteboardItem.data(forType: .fileURL) == Data(path.utf8), "every representation")
    let icon = NSWorkspace.shared.icon(forFile: "/tmp/a.txt").size
    #expect(fileItem.draggingFrame.size == icon, "a file URL drags its workspace icon: \(fileItem.draggingFrame)")
    #expect(fileItem.imageComponents?.isEmpty == false, "with an image")

    let text = PasteboardType(identifier: "public.utf8-plain-text",
                              conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])
    let textItem = AppKitDragAndDrop.draggingItem(for: [DragRepresentation(type: text, bytes: Array("Apple".utf8))],
                                                  at: NSPoint(x: 10, y: 20))
    #expect((textItem.item as? NSPasteboardItem)?.string(forType: .string) == "Apple")
    #expect(textItem.draggingFrame.width > 0 && textItem.draggingFrame.height > 0, "a badge")
    #expect(textItem.imageComponents?.isEmpty == false, "with an image")
}

// MARK: - 2.8–2.9: drags out

/// **2.8** (`DN-K`, `DN-X` item 1). With no `mouseDragged` seen the host view
/// cannot start a session: `false`, and nothing is started. After one, `true`,
/// and the session starter receives one item and that event. **A real
/// `NSDraggingSession` is never started here**: measured, AppKit starts one
/// headless and its tracking loop then never returns when the run loop spins
/// (scratch `headless-drag.swift`, killed after 15 s) — so the starter is
/// injected and the real hand-off is human check N3.
/// Mutation **M2h** (return `true` with no event).
@Test @MainActor func beginExternalDragNeedsADragEvent() throws {
    let (window, appKit, nsWindow) = try appKitWindow { Box() }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    var started: [([NSDraggingItem], NSEvent)] = []
    appKit.startDraggingSession = { items, event in started.append((items, event)) }
    let text = PasteboardType(identifier: "public.utf8-plain-text")
    let representations = [DragRepresentation(type: text, bytes: Array("s".utf8))]
    #expect(!appKit.beginExternalDrag(representations, at: Point(x: px(410), y: px(10))),
            "no drag event seen: false")
    #expect(started.isEmpty, "nothing started")

    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 50, y: 50),
                                                modifierFlags: [], timestamp: 1,
                                                windowNumber: nsWindow.windowNumber, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1))
    appKit.hostView.mouseDragged(with: event)
    #expect(appKit.beginExternalDrag(representations, at: Point(x: px(410), y: px(10))), "after one: true")
    try #require(started.count == 1, "one session started")
    #expect(started[0].0.count == 1, "one dragging item")
    #expect(started[0].1 === event, "from the last drag event")
}

/// **2.9** (`P6b`, `DN-K` item 2). The host view's `NSDraggingSource` offers
/// `.copy` within the application and outside it.
/// Mutation **M2i** (`.move`).
@Test @MainActor func theSourceOffersCopyInBothContexts() throws {
    let (window, appKit, nsWindow) = try appKitWindow { Box() }
    defer { nsWindow.close(); withExtendedLifetime(window) {} }
    let session = NSDraggingSession()
    #expect(appKit.hostView.draggingSession(session, sourceOperationMaskFor: .withinApplication) == .copy)
    #expect(appKit.hostView.draggingSession(session, sourceOperationMaskFor: .outsideApplication) == .copy)
}
