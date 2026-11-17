/// A 7-bit character set a G0-G3 slot can hold (`TRM-AC`).
enum Charset: UInt8 {
    /// US ASCII (final `B`, and any set the emulator does not know).
    case ascii
    /// DEC special graphics, the line-drawing set (final `0`).
    case decGraphics
    /// The UK set (final `A`): `#` shows the pound sign.
    case uk

    /// DEC special graphics for 0x5F through 0x7E (underscore is shown as a blank).
    private static let graphics: [UInt32] = [
        0x20, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0xB0, 0xB1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C,
        0x2514, 0x253C, 0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534, 0x252C, 0x2502, 0x2264,
        0x2265, 0x3C0, 0x2260, 0xA3, 0xB7,
    ]

    /// The scalar a printable ASCII byte stands for in this set.
    func translate(_ byte: UInt8) -> Unicode.Scalar {
        switch self {
        case .ascii:
            return Unicode.Scalar(byte)
        case .uk:
            return byte == 0x23 ? "\u{A3}" : Unicode.Scalar(byte)
        case .decGraphics:
            guard byte >= 0x5F && byte <= 0x7E else { return Unicode.Scalar(byte) }
            return Unicode.Scalar(Self.graphics[Int(byte - 0x5F)]) ?? Unicode.Scalar(byte)
        }
    }
}

/// What DECSC saves and DECRC restores (`TRM-AA`).
struct SavedCursor {
    var row: Int
    var col: Int
    var pendingWrap: Bool
    var pen: TerminalAttributes
    var originMode: Bool
    var charsets: [Charset]
    var glSet: Int
}
