#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import MetalUICore
import MetalUIPlatform

// Drag and drop on AppKit (rulings `DN-K`, `DN-L`, `DN-X`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §3.6). Drops in:
// `MetalHostView` is the window's one `NSDraggingDestination` and maps each
// callback onto `InputEvent.drop` (`DN-L`). Drags out: the host view is the
// `NSDraggingSource` of the session `AppKitWindow.beginExternalDrag` starts at
// the window's edge (`DN-K`).

/// The pure conversions between AppKit's pasteboard and MetalUI's seam.
@MainActor
enum AppKitDragAndDrop {
    /// The types `MetalHostView` registers for once, at creation (`DN-L`):
    /// SwiftUI's destination view registers `public.data|public.item`
    /// (`R0b`–`R0e`); the three concrete types make a Finder file, a URL and
    /// text arrive whatever the source declares first.
    static let registeredTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType(UTType.item.identifier),
        NSPasteboard.PasteboardType(UTType.data.identifier),
        .URL, .fileURL, .string,
    ]

    /// `identifier` with its `UTType` supertypes as `conformsTo` — every one,
    /// transitively, never `identifier` itself; none for a type `UTType` does
    /// not know (`DN-L`).
    static func pasteboardType(_ identifier: String) -> PasteboardType {
        let supertypes = UTType(identifier)?.supertypes.map(\.identifier).filter { $0 != identifier } ?? []
        return PasteboardType(identifier: identifier, conformsTo: supertypes.sorted())
    }

    /// Each pasteboard item as a `DropItem` whose types are its own, in its
    /// order, and whose `load` reads `data(forType:)` **only when asked** — the
    /// importer asks only for a type its destination imports (`DN-L`), so a
    /// Finder drag of a large image reads nothing it does not deliver.
    static func dropItems(from pasteboard: NSPasteboard) -> [DropItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let box = PasteboardItemBox(item)
            return DropItem(types: item.types.map { pasteboardType($0.rawValue) }) { identifier in
                box.item.data(forType: NSPasteboard.PasteboardType(identifier)).map { Array($0) }
            }
        }
    }

    /// One dragging item for a drag leaving the window (`DN-K` item 2): one
    /// `NSPasteboardItem` carrying every representation, framed at `position`
    /// (the host view's own top-left points) with AppKit's picture of the
    /// payload — a file URL's workspace icon, else a badge with its text —
    /// because MetalUI's renderer draws into a drawable, not an `NSImage`.
    static func draggingItem(for representations: [DragRepresentation], at position: NSPoint) -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        for representation in representations {
            pasteboardItem.setData(Data(representation.bytes),
                                   forType: NSPasteboard.PasteboardType(representation.type.identifier))
        }
        let image = picture(of: representations)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(NSRect(origin: position, size: image.size), contents: image)
        return item
    }

    /// The workspace icon of a file URL representation, else a rounded badge
    /// drawing the payload's text (its first UTF-8 representation, or its
    /// type's identifier).
    static func picture(of representations: [DragRepresentation]) -> NSImage {
        if let file = representations.first(where: { $0.type.identifier == UTType.fileURL.identifier }),
           let url = URL(string: String(decoding: file.bytes, as: UTF8.self)), url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let text = representations.first { $0.type.satisfies(UTType.plainText.identifier) || $0.type.satisfies(UTType.url.identifier) }
            .map { String(decoding: $0.bytes, as: UTF8.self) }
            ?? representations.first?.type.identifier ?? ""
        let label = NSAttributedString(string: String(text.prefix(40)), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        let size = NSSize(width: ceil(label.size().width) + 16, height: ceil(label.size().height) + 8)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            label.draw(at: NSPoint(x: 8, y: 4))
            return true
        }
    }

    /// The operations MetalUI's drag offers: `.copy` within the application
    /// and outside it (`P6b`: SwiftUI's session ends with operation copy).
    static func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation { .copy }
}

/// A pasteboard item handed to a `@Sendable` loader that only ever runs on the
/// main actor (`DropItem.load` is `@MainActor`).
private final class PasteboardItemBox: @unchecked Sendable {
    let item: NSPasteboardItem
    init(_ item: NSPasteboardItem) { self.item = item }
}

extension MetalHostView: NSDraggingSource {
    /// The location in this flipped view — MetalUI's top-left points.
    private func dropPosition(_ sender: any NSDraggingInfo) -> Point<Pixels> {
        let p = convert(sender.draggingLocation, from: nil)
        return Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    /// `.copy` when a destination under the pointer accepts, else none —
    /// whatever the source's operation mask (`R10`).
    private func operation(accepting: Bool) -> NSDragOperation { accepting ? .copy : [] }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let items = AppKitDragAndDrop.dropItems(from: sender.draggingPasteboard)
        return operation(accepting: onInput?(.drop(.entered(position: dropPosition(sender), items: items))) ?? false)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation(accepting: onInput?(.drop(.moved(position: dropPosition(sender)))) ?? false)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        _ = onInput?(.drop(.exited))
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let items = AppKitDragAndDrop.dropItems(from: sender.draggingPasteboard)
        return onInput?(.drop(.performed(position: dropPosition(sender), items: items))) ?? false
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        AppKitDragAndDrop.sourceOperationMask(for: context)
    }
}
#endif
