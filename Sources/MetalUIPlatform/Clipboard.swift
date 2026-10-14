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
