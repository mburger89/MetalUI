import Testing
@testable import MetalUITerminal

/// Decodes `bytes` and returns the scalars; a final ASCII sentinel forces a pending sequence to resolve.
private func decode(_ bytes: [UInt8]) -> [UInt32] {
    var decoder = UTF8Decoder()
    var out: [UInt32] = []
    var i = 0
    let all = bytes + [0x5A]
    while i < all.count {
        switch decoder.step(all[i]) {
        case .more: i += 1
        case .scalar(let v): out.append(v); i += 1
        case .invalid(let reprocess):
            out.append(0xFFFD)
            if !reprocess { i += 1 }
        }
    }
    out.removeLast()  // the sentinel
    return out
}

@Suite struct UTF8DecoderTests {
    struct Case: Sendable, CustomStringConvertible {
        var bytes: [UInt8]
        var expect: [UInt32]
        var description: String { bytes.map { String($0, radix: 16) }.joined(separator: " ") }
    }

    static let cases: [Case] = [
        Case(bytes: [0x41], expect: [0x41]),
        Case(bytes: [0xC3, 0xA9], expect: [0xE9]),
        Case(bytes: [0xE2, 0x82, 0xAC], expect: [0x20AC]),
        Case(bytes: [0xF0, 0x9F, 0x98, 0x80], expect: [0x1F600]),
        Case(bytes: [0xF4, 0x8F, 0xBF, 0xBF], expect: [0x10FFFF]),
        // Lone continuation, overlong forms, surrogates, beyond U+10FFFF, never-valid bytes.
        Case(bytes: [0x80], expect: [0xFFFD]),
        Case(bytes: [0xBF, 0x41], expect: [0xFFFD, 0x41]),
        Case(bytes: [0xC0, 0x80], expect: [0xFFFD, 0xFFFD]),
        Case(bytes: [0xC1, 0xBF], expect: [0xFFFD, 0xFFFD]),
        Case(bytes: [0xE0, 0x80, 0x80], expect: [0xFFFD, 0xFFFD, 0xFFFD]),
        Case(bytes: [0xE0, 0x9F, 0xBF], expect: [0xFFFD, 0xFFFD, 0xFFFD]),
        Case(bytes: [0xF0, 0x80, 0x80, 0x80], expect: [0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD]),
        Case(bytes: [0xED, 0xA0, 0x80], expect: [0xFFFD, 0xFFFD, 0xFFFD]),
        Case(bytes: [0xF4, 0x90, 0x80, 0x80], expect: [0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD]),
        Case(bytes: [0xF5], expect: [0xFFFD]),
        Case(bytes: [0xFF, 0xFE], expect: [0xFFFD, 0xFFFD]),
        // A truncated sequence yields one U+FFFD and never eats the byte that broke it.
        Case(bytes: [0xE2, 0x82, 0x41], expect: [0xFFFD, 0x41]),
        Case(bytes: [0xF0, 0x9F, 0x98, 0x41], expect: [0xFFFD, 0x41]),
        Case(bytes: [0xC3, 0x1B], expect: [0xFFFD, 0x1B]),
        Case(bytes: [0xE2, 0xC3, 0xA9], expect: [0xFFFD, 0xE9]),
        Case(bytes: [0xE2, 0x82, 0xE2, 0x82, 0xAC], expect: [0xFFFD, 0x20AC]),
    ]

    @Test(arguments: cases) func table(_ c: Case) { #expect(decode(c.bytes) == c.expect) }

    @Test func agreesWithTheStandardLibraryOnRandomBytes() {
        var rng = SeededRandom(seed: 0xDEC0DE)
        let interesting: [UInt8] = [0x00, 0x41, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xC2, 0xDF, 0xE0,
                                    0xE1, 0xED, 0xEF, 0xF0, 0xF4, 0xF5, 0xFF]
        for _ in 0..<3_000 {
            let length = Int.random(in: 0...12, using: &rng)
            let bytes: [UInt8] = (0..<length).map { _ in
                guard Bool.random(using: &rng) else { return UInt8.random(in: 0...255, using: &rng) }
                guard let byte = interesting.randomElement(using: &rng) else { preconditionFailure("the list is not empty") }
                return byte
            }
            // The standard library replaces each maximal invalid subpart with one U+FFFD, as the decoder must.
            let reference = String(decoding: bytes, as: UTF8.self).unicodeScalars.map(\.value)
            #expect(decode(bytes) == reference, "bytes \(bytes)")
        }
    }

    @Test func aSequenceSplitAcrossFeedsCompletes() {
        var decoder = UTF8Decoder()
        guard case .more = decoder.step(0xE2), case .more = decoder.step(0x82) else { Issue.record("not pending"); return }
        #expect(decoder.isPending)
        guard case .scalar(let v) = decoder.step(0xAC) else { Issue.record("not complete"); return }
        #expect(v == 0x20AC)
        #expect(!decoder.isPending)
    }

    @Test func printedInvalidInputIsReplacementCharactersOnTheScreen() {
        let emulator = TerminalEmulator(cols: 20, rows: 2)
        emulator.feed([0x61, 0xE2, 0x82, 0x62, 0xFF, 0x63, 0xC0, 0x80])
        #expect(emulator.screenLines[0] == "a\u{FFFD}b\u{FFFD}c\u{FFFD}\u{FFFD}")
    }
}
