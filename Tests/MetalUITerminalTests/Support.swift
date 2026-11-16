@testable import MetalUITerminal

/// A small deterministic generator (SplitMix64) so every random test is reproducible from its seed.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension TerminalEmulator {
    func feed(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { feed($0) }
    }
    func feed(_ string: String) { feed(Array(string.utf8)) }

    /// The text of the screen's rows, top to bottom.
    var screenLines: [String] {
        let top = firstRow + scrollbackCount
        return (0..<rowCount).map { rowText(top + $0) ?? "<nil>" }
    }
    /// The retained scrollback, oldest first.
    var historyLines: [String] {
        (firstRow..<(firstRow + scrollbackCount)).map { rowText($0) ?? "<nil>" }
    }
    /// Cursor in viewport coordinates, from a fresh publish.
    var cursorPosition: (row: Int, col: Int, pending: Bool) {
        let c = publishSnapshot().cursor
        return (c.row, c.col, c.pendingWrap)
    }
    /// Everything an observer or the next byte could depend on.
    var fullState: String {
        let c = publishSnapshot()
        return [historyLines.joined(separator: "|"), screenLines.joined(separator: "|"),
                "\(c.cursor)", "\(c.modes)", "\(firstRow)", parser.stateDescription].joined(separator: "\n")
    }
}

/// Records every parser callback as a string; printed runs are split into one event per scalar, so a recording
/// does not depend on how the input was chunked.
final class Recorder: VTParserHandler {
    var events: [String] = []
    func printASCII(_ bytes: UnsafeBufferPointer<UInt8>) {
        for b in bytes { events.append("print \(Unicode.Scalar(b))") }
    }
    func print(_ scalar: Unicode.Scalar) { events.append("print \(scalar)") }
    func execute(_ code: UInt8) { events.append("exec \(code)") }
    func csi(_ p: CSIParameters, final: UInt8) {
        events.append("csi \(Unicode.Scalar(final)) v=\(p.values) sub=\(p.isSub.map { $0 ? 1 : 0 }) "
                      + "prefix=\(p.prefix) i=\(p.intermediates)")
    }
    func esc(intermediates: [UInt8], final: UInt8) { events.append("esc \(Unicode.Scalar(final)) i=\(intermediates)") }
    func osc(_ payload: [UInt8]) { events.append("osc \(String(decoding: payload, as: UTF8.self))") }
    func dcs(_ p: CSIParameters, final: UInt8, payload: [UInt8]) {
        events.append("dcs \(Unicode.Scalar(final)) v=\(p.values) i=\(p.intermediates) \(String(decoding: payload, as: UTF8.self))")
    }
    func apc(_ payload: [UInt8]) { events.append("apc \(String(decoding: payload, as: UTF8.self))") }
}

func parse(_ bytes: [UInt8], cap: Int = 4096) -> [String] {
    var parser = VTParser(payloadCap: cap)
    let recorder = Recorder()
    bytes.withUnsafeBufferPointer { parser.feed($0, recorder) }
    return recorder.events
}

func parse(_ text: String, cap: Int = 4096) -> [String] { parse(Array(text.utf8), cap: cap) }

let ESC = "\u{1B}"
let BEL = "\u{07}"
let ST = "\u{1B}\\"

/// The bytes of a mixed stream that exercises every parser state; the chunking tests slice it.
let mixedCorpus: [[UInt8]] = [
    Array("hello\r\nworld\(ESC)[2;3Hxy\(ESC)[Kz\(ESC)[?25l\(ESC)[?25h\(ESC)[1;38:2::10:20:30mcol\(ESC)[0m".utf8),
    Array("\(ESC)]0;a window title\(BEL)after\(ESC)]8;;http://x.example\(ST)link\(ESC)]8;;\(ST)".utf8),
    Array("\(ESC)P1;2$qpayload\u{0A}here\(ST)dcs-done\(ESC)_Gapc-data\(ST)\(ESC)Xsos\(ST)tail".utf8),
    Array("caf\u{E9} \u{4E2D}\u{6587} e\u{301} \u{1F600} end\r\n".utf8),
    [0x61, 0xE2, 0x82, 0x62, 0xF0, 0x9F, 0x98, 0x41, 0xFF, 0xC0, 0x80, 0xED, 0xA0, 0x80, 0x43],
    [0xC2, 0x9B, 0x31, 0x3B, 0x32, 0x48, 0xC2, 0x9D, 0x30, 0x3B, 0x74, 0xC2, 0x9C, 0xC2, 0x85, 0x9B, 0x68],
    Array("\(ESC)[1\u{18}H\(ESC)[2\u{1A}H\(ESC)]x\u{18}y\(ESC)[1\(ESC)[3Aq\(ESC)(0\(ESC)#8\(ESC)7\(ESC)8".utf8),
    Array("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\r\n\t\tb\u{08}\u{08}c\(ESC)[3D\(ESC)[2C\(ESC)[9A\(ESC)[9B\(ESC)[;4H".utf8),
]
