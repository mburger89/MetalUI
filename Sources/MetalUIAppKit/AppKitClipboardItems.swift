import AppKit
import MetalUIPlatform

// The clipboard's items on AppKit (rulings `CP-C`, `CP-D`, `CP-E`, `CP-F`): N `NSPasteboardItem`s in one
// `writeObjects`, `.later` representations through a retained data provider, and per-item listing and reads.
// One item keeps the earlier answers (`pasteboard.types`, `pasteboard.data(forType:)`) so every `CB-` pin holds.

/// The bytes a hop to the main thread produced (written by the main thread, read after the semaphore).
private final class ExportResult: @unchecked Sendable { var bytes: [UInt8] = [] }

/// Supplies the bytes of an item's `.later` representations when a consumer reads them (`CP-F`). The pasteboard
/// does not retain a provider: the window keeps the last write's providers (`AppKitWindow.clipboardProviders`).
/// A reader on another thread hops to the main thread for the export through a **run-loop block** (not
/// `DispatchQueue.main.sync`: a main-actor caller sitting in a main-queue block while it spins the run loop would
/// never get the queue back, measured by test 2.10); a main-thread reader runs it in place.
final class AppKitClipboardProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let exports: [String: @MainActor () -> [UInt8]]

    init(exports: [String: @MainActor () -> [UInt8]]) { self.exports = exports }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard let export = exports[type.rawValue] else { return }
        let bytes: [UInt8]
        if Thread.isMainThread {
            bytes = MainActor.assumeIsolated { export() }
        } else {
            let result = ExportResult()
            let done = DispatchSemaphore(value: 0)
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                result.bytes = MainActor.assumeIsolated { export() }
                done.signal()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
            done.wait()
            bytes = result.bytes
        }
        if !bytes.isEmpty { item.setData(Data(bytes), forType: type) }   // zero bytes: no data (divergence 716)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

extension AppKitWindow {
    /// Replaces the pasteboard with one `NSPasteboardItem` per item that holds a representation, in order
    /// (`CP-C`); a `.later` representation is registered with a provider, so the closure runs when a consumer
    /// reads it (`CP-F`); zero-byte `.now` ones are dropped (`CB-I`). `false`, the pasteboard untouched, when
    /// nothing remains.
    func writeClipboard(items: [ClipboardItem]) -> Bool {
        var objects: [NSPasteboardItem] = []
        var providers: [AppKitClipboardProvider] = []
        for item in items {
            let object = NSPasteboardItem()
            var lazy: [String: @MainActor () -> [UInt8]] = [:]
            var order: [NSPasteboard.PasteboardType] = []
            var wrote = false
            for payload in item.payloads {
                let type = NSPasteboard.PasteboardType(payload.type.identifier)
                switch payload.bytes {
                case .now(let bytes):
                    guard !bytes.isEmpty else { continue }
                    wrote = object.setData(Data(bytes), forType: type) || wrote
                case .later(let export):
                    lazy[type.rawValue] = export
                    order.append(type)
                }
            }
            if !lazy.isEmpty {
                let provider = AppKitClipboardProvider(exports: lazy)
                for type in order { wrote = object.setDataProvider(provider, forTypes: [type]) || wrote }
                providers.append(provider)
            }
            if wrote { objects.append(object) }
        }
        guard !objects.isEmpty else { return false }
        pasteboard.clearContents()
        let written = pasteboard.writeObjects(objects)
        clipboardProviders = providers   // after the clear: it finished the previous write's providers
        noteClipboardWrite()
        return written
    }

    /// The identifiers each pasteboard item holds, most preferred first (`CP-D`). One item, or none, answers
    /// as the single-type list does.
    func clipboardItems() -> [[String]] {
        let items = pasteboard.pasteboardItems ?? []
        if items.count > 1 { return items.map { $0.types.map(\.rawValue) } }
        let identifiers = clipboardTypeIdentifiers()
        return identifiers.isEmpty ? [] : [identifiers]
    }

    /// Item `item`'s bytes stored as `identifier`; `nil` when the item or the type is absent or the bytes empty.
    func readClipboard(item: Int, identifier: String) -> [UInt8]? {
        let items = pasteboard.pasteboardItems ?? []
        guard items.count > 1 else { return item == 0 ? readClipboard(identifier: identifier) : nil }
        guard items.indices.contains(item) else { return nil }
        return items[item].data(forType: NSPasteboard.PasteboardType(identifier)).map { Array($0) }
    }

    func setClipboardChangeHandler(_ handler: (@MainActor () -> Void)?) {
        clipboardChangeHandler = handler
        lastClipboardChangeCount = handler == nil ? nil : pasteboard.changeCount
    }
}
