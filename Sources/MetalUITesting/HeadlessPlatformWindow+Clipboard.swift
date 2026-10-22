import MetalUI
import MetalUIPlatform

// The headless window's clipboard (rulings `CB-K`, `CP-E`, `CP-F`, `CP-G`; `HT-X` item 1: an honest
// answer to every requirement). One store of items; the text-only and the typed single-item
// requirements are views of it.

extension HeadlessPlatformWindow {
    /// The plain-text type, as the text view of the store writes it.
    private static let textType = PasteboardType(
        identifier: "public.utf8-plain-text",
        conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])

    /// Item 0's representations, most preferred first (`CB-K`). A `.later` one is exported by the read
    /// (and counted in ``clipboardExportCount``).
    public var clipboardRepresentations: [ClipboardRepresentation] {
        guard let first = clipboardStore.first else { return [] }
        return first.payloads.map { ClipboardRepresentation(type: $0.type, bytes: realise($0.bytes)) }
    }

    /// The clipboard's plain text, a view of item 0's `public.utf8-plain-text` representation (`CB-K`):
    /// reading decodes its bytes as UTF-8; setting replaces the whole store with that one item, `nil`
    /// clears it.
    public var clipboard: String? {
        get {
            clipboardRepresentations.first { $0.type.identifier == "public.utf8-plain-text" }
                .map { String(decoding: $0.bytes, as: UTF8.self) }
        }
        set {
            replaceClipboard(with: newValue.map {
                [ClipboardItem(payloads: [ClipboardPayload(type: Self.textType, bytes: .now(Array($0.utf8)))])]
            } ?? [])
        }
    }

    /// The identifiers of the types each stored item holds (`CP-E`).
    public var clipboardItemTypes: [[String]] { clipboardItems() }

    /// Reads ``clipboard``.
    public func readClipboard() -> String? { clipboard }

    /// Replaces ``clipboard``.
    public func writeClipboard(_ text: String) { clipboard = text }

    /// Replaces the store with one item of `representations`; `false` (the store unchanged) when there
    /// are none.
    public func writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool {
        guard !representations.isEmpty else { return false }
        replaceClipboard(with: [ClipboardItem(payloads: representations.map {
            ClipboardPayload(type: $0.type, bytes: .now($0.bytes))
        })])
        return true
    }

    /// Item 0's identifiers, in order.
    public func clipboardTypeIdentifiers() -> [String] { clipboardStore.first?.payloads.map(\.type.identifier) ?? [] }

    /// Item 0's bytes stored as `identifier`.
    public func readClipboard(identifier: String) -> [UInt8]? { readClipboard(item: 0, identifier: identifier) }

    /// Replaces the store with `items`, an item with no payload dropped; `false` (the store unchanged)
    /// when none remains. With ``Options/clipboardExportsLazily`` `false` every `.later` is exported now.
    public func writeClipboard(items: [ClipboardItem]) -> Bool {
        let kept = items.filter { !$0.payloads.isEmpty }
        guard !kept.isEmpty else { return false }
        let stored = options.clipboardExportsLazily ? kept : kept.map { item in
            ClipboardItem(payloads: item.payloads.map { ClipboardPayload(type: $0.type, bytes: .now(realise($0.bytes))) })
        }
        replaceClipboard(with: stored)
        return true
    }

    /// Each stored item's identifiers, most preferred first.
    public func clipboardItems() -> [[String]] {
        clipboardStore.map { $0.payloads.map(\.type.identifier) }
    }

    /// Item `item`'s bytes as `identifier`; exports a `.later` representation (once per read). A representation
    /// that exports zero bytes reads `nil`, as on AppKit (divergence 716).
    public func readClipboard(item: Int, identifier: String) -> [UInt8]? {
        guard clipboardStore.indices.contains(item),
              let payload = clipboardStore[item].payloads.first(where: { $0.type.identifier == identifier })
        else { return nil }
        let bytes = realise(payload.bytes)
        return bytes.isEmpty ? nil : bytes
    }

    /// Keeps `handler`; ``replaceClipboard(with:)`` calls it on a change (`CP-G`).
    public func setClipboardChangeHandler(_ handler: (@MainActor () -> Void)?) {
        clipboardChangeHandler = handler
    }

    /// Replaces the store and calls the change handler once when the contents differ (`CP-G`): same
    /// items by type list and `.now` bytes is no change, a `.later` always is.
    func replaceClipboard(with items: [ClipboardItem]) {
        let changed = !Self.sameContents(clipboardStore, items)
        clipboardStore = items
        if changed { clipboardChangeHandler?() }
    }

    private func realise(_ bytes: ClipboardBytes) -> [UInt8] {
        switch bytes {
        case .now(let value): return value
        case .later(let export):
            clipboardExportCount += 1
            return export()
        }
    }

    private static func sameContents(_ lhs: [ClipboardItem], _ rhs: [ClipboardItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.payloads.count == right.payloads.count else { return false }
            for (a, b) in zip(left.payloads, right.payloads) {
                guard a.type.identifier == b.type.identifier, case .now(let x) = a.bytes, case .now(let y) = b.bytes, x == y else { return false }
            }
        }
        return true
    }
}
