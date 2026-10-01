#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import MetalUICore
import MetalUIPlatform

// Drag and drop on AppKit (rulings `DN-K`, `DN-L`; spec
// `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md` §3.6). Lane 2's
// red stub: every conversion answers nothing.

/// The pure conversions between AppKit's pasteboard and MetalUI's seam.
@MainActor
enum AppKitDragAndDrop {
    /// The types `MetalHostView` registers for once, at creation (`DN-L`).
    static let registeredTypes: [NSPasteboard.PasteboardType] = []

    /// `identifier` with its `UTType` supertypes as `conformsTo`.
    static func pasteboardType(_ identifier: String) -> PasteboardType {
        PasteboardType(identifier: identifier)
    }

    /// Each pasteboard item as a `DropItem` whose `load` reads lazily.
    static func dropItems(from pasteboard: NSPasteboard) -> [DropItem] { [] }

    /// One dragging item carrying every representation, and an image.
    static func draggingItem(for representations: [DragRepresentation], at position: NSPoint) -> NSDraggingItem {
        NSDraggingItem(pasteboardWriter: NSPasteboardItem())
    }

    /// The operations MetalUI's drag offers in `context` (`P6b`).
    static func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation { [] }
}

extension MetalHostView: NSDraggingSource {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {}
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        AppKitDragAndDrop.sourceOperationMask(for: context)
    }
}
#endif
