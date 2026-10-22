// The clipboard beyond text (rulings `CB-D`, `CB-E`; spec
// `docs/superpowers/specs/2026-10-14-clipboard-types-design.md`). The seam types
// `PlatformWindow` trades in, and the one pure table that maps an identifier to
// the mime type SDL's clipboard is keyed by. Foundation-free.

/// One representation of an outgoing clipboard item: its type and its bytes
/// (ruling `CB-E`). Handed to `PlatformWindow.writeClipboard(_:)-([ClipboardRepresentation])`.
public struct ClipboardRepresentation: Sendable, Equatable {
    /// The representation's type; its `identifier` is the pasteboard type on AppKit
    /// and maps to a mime type on SDL (`ClipboardMime`).
    public var type: PasteboardType
    /// The payload exported as `type`.
    public var bytes: [UInt8]

    /// A representation of `bytes` as `type`.
    public init(type: PasteboardType, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }
}

/// What the focus chain can currently do with the clipboard (ruling `CB-E`,
/// `CB-G`): sent to the platform after a frame, on change only, so AppKit's Edit
/// menu can enable Cut, Copy and Paste without a frame to read.
public struct ClipboardCommands: OptionSet, Sendable {
    /// The raw bits.
    public let rawValue: Int
    /// A raw value.
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// A `cuttable` is on the focus chain.
    public static let cut = ClipboardCommands(rawValue: 1 << 0)
    /// A `copyable` is on the focus chain.
    public static let copy = ClipboardCommands(rawValue: 1 << 1)
    /// A `pasteDestination` is on the focus chain.
    public static let paste = ClipboardCommands(rawValue: 1 << 2)
}

/// The pure identifier-to-mime table of the SDL clipboard (ruling `CB-D`),
/// portable so a macOS test pins what Linux and Windows run.
package enum ClipboardMime {
    /// Built-in identifiers and the mime types they map to.
    private static let table: [(identifier: String, mime: String)] = [
        ("public.utf8-plain-text", "text/plain;charset=utf-8"),
        ("public.plain-text", "text/plain"),
        ("public.json", "application/json"),
        ("public.url", "text/uri-list"),
        ("public.data", "application/octet-stream"),
    ]
    private static let customPrefix = "application/x-"
    private static let foreignPrefix = "mime:"

    /// The mime type `identifier` is written and read as. Built-ins by the
    /// table; `mime:<m>` is the foreign mime `m` (when that reads back as the
    /// same identifier); every other identifier is `application/x-` plus the
    /// identifier with each byte outside `[a-z0-9.+-]` percent-encoded `%xx`
    /// (lower-case hex), so the mime is all lower case.
    package static func mime(forIdentifier identifier: String) -> String {
        if let entry = table.first(where: { $0.identifier == identifier }) { return entry.mime }
        if identifier.hasPrefix(foreignPrefix) {
            let foreign = String(identifier.dropFirst(foreignPrefix.count))
            if !foreign.isEmpty, foreign == foreign.lowercased(),
               self.identifier(forMime: foreign) == identifier { return foreign }
        }
        var out = customPrefix
        for byte in identifier.utf8 {
            if (byte >= 0x61 && byte <= 0x7a) || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2e || byte == 0x2b || byte == 0x2d {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = Array("0123456789abcdef".unicodeScalars)
                out.unicodeScalars.append("%")
                out.unicodeScalars.append(hex[Int(byte >> 4)])
                out.unicodeScalars.append(hex[Int(byte & 0x0f)])
            }
        }
        return out
    }

    /// The identifier a platform mime type reads as: the table's, a decoded
    /// `application/x-` one, else `mime:` plus the mime (a foreign type is
    /// listed and readable, never dropped). The mime is compared as given for
    /// the table and case-insensitively for the text types.
    package static func identifier(forMime mime: String) -> String {
        if let entry = table.first(where: { $0.mime == mime }) { return entry.identifier }
        let lowered = mime.lowercased()
        if lowered == "text/plain;charset=utf-8" || lowered == "text/plain; charset=utf-8" {
            return "public.utf8-plain-text"
        }
        if mime.hasPrefix(customPrefix) {
            let rest = Array(mime.utf8.dropFirst(customPrefix.utf8.count))
            var bytes: [UInt8] = []
            var index = 0
            while index < rest.count {
                if rest[index] == 0x25, index + 2 < rest.count, let high = hexValue(rest[index + 1]),
                   let low = hexValue(rest[index + 2]) {
                    bytes.append(UInt8(high << 4 | low))
                    index += 3
                } else {
                    bytes.append(rest[index])
                    index += 1
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        return foreignPrefix + mime
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 0x30...0x39: return Int(byte) - 0x30
        case 0x61...0x66: return Int(byte) - 0x61 + 10
        case 0x41...0x46: return Int(byte) - 0x41 + 10
        default: return nil
        }
    }
}

// MARK: Items (ruling `CP-E`, `CP-F`; spec `2026-10-22-clipboard-extras-design.md`)

/// The bytes of one outgoing clipboard representation (rulings `CP-E`, `CP-F`):
/// already encoded, or encoded when a consumer reads.
public enum ClipboardBytes {
    /// The encoded bytes.
    case now([UInt8])
    /// A closure the platform runs when a consumer reads the representation (AppKit,
    /// headless) or at write time (SDL, `CP-F`); it runs on the main actor.
    case later(@MainActor () -> [UInt8])
}

/// One representation of an outgoing item: its type and its ``ClipboardBytes``
/// (ruling `CP-E`).
public struct ClipboardPayload {
    /// The representation's type; its `identifier` is the pasteboard type on AppKit
    /// and maps to a mime type on SDL (`ClipboardMime`).
    public var type: PasteboardType
    /// The payload exported as `type`.
    public var bytes: ClipboardBytes

    /// A payload of `bytes` as `type`.
    public init(type: PasteboardType, bytes: ClipboardBytes) {
        self.type = type
        self.bytes = bytes
    }
}

/// One outgoing clipboard item: its representations, most preferred first (ruling
/// `CP-E`). `PlatformWindow.writeClipboard(items:)` takes several.
public struct ClipboardItem {
    /// The item's representations, most preferred first.
    public var payloads: [ClipboardPayload]

    /// An item of `payloads`.
    public init(payloads: [ClipboardPayload]) { self.payloads = payloads }
}

/// The framed pack SDL carries several items in under one private mime (rulings
/// `CP-C`, `CP-D`): a magic, the item count, then per item its representation
/// count and, per representation, a length-prefixed UTF-8 type identifier and
/// length-prefixed bytes. Portable and Foundation-free; **decoding is bounds-checked
/// and answers `nil` on any violation, never traps.**
package enum ClipboardItemPack {
    /// The mime the pack is written under (`ClipboardMime`'s custom spelling of
    /// `com.metalui.clipboard-items`).
    package static let mime = "application/x-com.metalui.clipboard-items"
    package static let maxItems = 1024
    package static let maxRepresentationsPerItem = 1024
    package static let maxNameBytes = 1 << 20
    package static let maxTotalBytes = 64 << 20
    private static let magic: [UInt8] = [0x4d, 0x55, 0x49, 0x50]  // "MUIP"

    /// One decoded representation.
    package struct Entry: Equatable {
        package var identifier: String
        package var bytes: [UInt8]
        package init(identifier: String, bytes: [UInt8]) {
            self.identifier = identifier
            self.bytes = bytes
        }
    }

    /// The pack for `items`; `nil` when a limit would be exceeded.
    package static func encode(_ items: [[Entry]]) -> [UInt8]? {
        guard items.count <= maxItems else { return nil }
        var out = magic
        func put(_ value: Int) {
            out.append(UInt8(truncatingIfNeeded: value))
            out.append(UInt8(truncatingIfNeeded: value >> 8))
            out.append(UInt8(truncatingIfNeeded: value >> 16))
            out.append(UInt8(truncatingIfNeeded: value >> 24))
        }
        put(items.count)
        for item in items {
            guard item.count <= maxRepresentationsPerItem else { return nil }
            put(item.count)
            for entry in item {
                let name = Array(entry.identifier.utf8)
                guard name.count <= maxNameBytes else { return nil }
                put(name.count)
                out.append(contentsOf: name)
                put(entry.bytes.count)
                out.append(contentsOf: entry.bytes)
                guard out.count <= maxTotalBytes else { return nil }
            }
        }
        return out
    }

    /// The items a pack holds; `nil` when it is malformed or over a limit.
    package static func decode(_ bytes: [UInt8]) -> [[Entry]]? {
        guard bytes.count <= maxTotalBytes, bytes.count >= 8, Array(bytes[0..<4]) == magic else { return nil }
        var cursor = 4
        func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard count >= 0, count <= bytes.count - cursor else { return nil }
            defer { cursor += count }
            return bytes[cursor..<(cursor + count)]
        }
        func u32() -> Int? {
            guard let slice = take(4) else { return nil }
            var value = 0
            for (shift, byte) in slice.enumerated() { value |= Int(byte) << (8 * shift) }
            return value
        }
        guard let itemCount = u32(), itemCount <= maxItems else { return nil }
        var items: [[Entry]] = []
        for _ in 0..<itemCount {
            guard let count = u32(), count <= maxRepresentationsPerItem else { return nil }
            var item: [Entry] = []
            for _ in 0..<count {
                guard let nameLength = u32(), nameLength <= maxNameBytes, let name = take(nameLength),
                      let dataLength = u32(), let data = take(dataLength) else { return nil }
                item.append(Entry(identifier: String(decoding: name, as: UTF8.self), bytes: Array(data)))
            }
            items.append(item)
        }
        return cursor == bytes.count ? items : nil
    }
}
