/// An incremental UTF-8 decoder. An invalid sequence yields U+FFFD and never consumes the next valid byte: the
/// byte that broke the sequence is handed back to be decoded afresh (`TRM-G`). A sequence cut off by the end of a
/// chunk waits for its continuation.
struct UTF8Decoder {
    enum Step {
        /// More bytes are needed.
        case more
        /// A scalar was completed.
        case scalar(UInt32)
        /// The sequence was invalid; emit U+FFFD. `reprocess` says the byte was not part of it and must be
        /// decoded again from the idle state.
        case invalid(reprocess: Bool)
    }

    private var value: UInt32 = 0
    private var needed: UInt8 = 0
    private var lower: UInt8 = 0x80
    private var upper: UInt8 = 0xBF

    /// Whether a sequence is half decoded.
    var isPending: Bool { needed != 0 }

    mutating func reset() { needed = 0 }

    mutating func step(_ b: UInt8) -> Step {
        if needed == 0 {
            switch b {
            case 0x00...0x7F: return .scalar(UInt32(b))
            case 0xC2...0xDF: start(b & 0x1F, 1)
            case 0xE0: start(b & 0x0F, 2, lower: 0xA0)
            case 0xE1...0xEC, 0xEE...0xEF: start(b & 0x0F, 2)
            case 0xED: start(b & 0x0F, 2, upper: 0x9F)
            case 0xF0: start(b & 0x07, 3, lower: 0x90)
            case 0xF1...0xF3: start(b & 0x07, 3)
            case 0xF4: start(b & 0x07, 3, upper: 0x8F)
            default: return .invalid(reprocess: false)
            }
            return .more
        }
        guard b >= lower && b <= upper else {
            needed = 0
            return .invalid(reprocess: true)
        }
        lower = 0x80
        upper = 0xBF
        value = (value << 6) | UInt32(b & 0x3F)
        needed -= 1
        return needed == 0 ? .scalar(value) : .more
    }

    private mutating func start(_ bits: UInt8, _ more: UInt8, lower: UInt8 = 0x80, upper: UInt8 = 0xBF) {
        value = UInt32(bits)
        needed = more
        self.lower = lower
        self.upper = upper
    }
}
