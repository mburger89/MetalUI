// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUIPlatform
import SDLBridge

// The clipboard's items on SDL (rulings `CP-C`, `CP-D`, `CP-F`). SDL holds **one mime set per clipboard** (probe
// `docs/probes/sdl-clipboard-update.c`): item 0 goes out under its ordinary mimes, so another application pastes the first
// item as before; when more than one item is written a private mime (`ClipboardItemPack`) also carries every item's
// representations for MetalUI-to-MetalUI (divergence 715). `.later` representations are realised at write: the data callback
// is pure C (`CB-H`), and a Swift export closure cannot run there (divergence 716). A one-item write adds no pack, so it is
// byte for byte `CB-H`'s box.

extension SDLWindow {
    /// The identifier the pack's mime reads as; `clipboardTypeIdentifiers()` never lists it.
    static let clipboardPackIdentifier = "com.metalui.clipboard-items"

    public func writeClipboard(items: [ClipboardItem]) -> Bool {
        let realised: [[ClipboardRepresentation]] = items.map { item in
            item.payloads.compactMap { payload in
                let bytes: [UInt8]
                switch payload.bytes {
                case .now(let value): bytes = value
                case .later(let export): bytes = export()   // realised at write on SDL (`CP-F`)
                }
                return bytes.isEmpty ? nil : ClipboardRepresentation(type: payload.type, bytes: bytes)   // `CB-I`
            }
        }.filter { !$0.isEmpty }
        guard var representations = realised.first else { return false }
        if realised.count > 1,
           let pack = ClipboardItemPack.encode(realised.map { item in
               item.map { ClipboardItemPack.Entry(identifier: $0.type.identifier, bytes: $0.bytes) }
           }) {
            representations.append(ClipboardRepresentation(type: PasteboardType(identifier: Self.clipboardPackIdentifier),
                                                           bytes: pack))
        }
        return writeClipboard(representations)
    }

    /// The items of a well-formed pack on the clipboard; `nil` when there is none or it is malformed
    /// (`ClipboardItemPack.decode` never traps), and the single native item stands.
    private func packedItems() -> [[ClipboardItemPack.Entry]]? {
        var size = 0
        guard let data = mui_clipboard_get(ClipboardItemPack.mime, &size) else { return nil }
        defer { mui_free(data) }
        guard let items = ClipboardItemPack.decode(Array(UnsafeRawBufferPointer(start: data, count: size))),
              !items.isEmpty else { return nil }
        return items
    }

    public func clipboardItems() -> [[String]] {
        if let items = packedItems() { return items.map { $0.map(\.identifier) } }
        let identifiers = clipboardTypeIdentifiers()
        return identifiers.isEmpty ? [] : [identifiers]
    }

    public func readClipboard(item: Int, identifier: String) -> [UInt8]? {
        guard let items = packedItems() else { return item == 0 ? readClipboard(identifier: identifier) : nil }
        guard items.indices.contains(item) else { return nil }
        return items[item].first { $0.identifier == identifier }?.bytes
    }
}
#endif
