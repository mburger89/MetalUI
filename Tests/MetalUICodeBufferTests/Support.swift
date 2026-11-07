@testable import MetalUICodeBuffer

/// A seeded generator, so a failing random run replays.
struct SplitMix64: RandomNumberGenerator {
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

/// A document of `count` DISTINCT lines mixing ASCII, 2-, 3- and 4-byte scalars, ZWJ emoji and flags, tabs,
/// CRLF endings and, in the middle, one line of about 20 KB. Distinct on purpose: a fixture of equal lines
/// would let a content-keyed cache collapse and hide per-line work.
func fixtureText(lines count: Int, longLine: Bool = true) -> String {
    var lines = [String]()
    lines.reserveCapacity(count)
    for i in 0..<count {
        switch i % 8 {
        case 0: lines.append("func f\(i)(x: Int) -> Int { return x &+ \(i) }")
        case 1: lines.append("    let café\(i) = \"naïve é ü \(i)\"")
        case 2: lines.append("// 日本語のコメント \(i) テキスト")
        case 3: lines.append("😀 emoji \(i) 𝒳𝒴 end")
        case 4: lines.append("family 👨‍👩‍👧‍👦 \(i) flag 🇩🇪")
        case 5: lines.append("\tindented\twith\ttabs \(i)\r")
        case 6: lines.append("x\(i)")
        default: lines.append("/* block \(i) ★ */")
        }
    }
    if longLine && count > 2 { lines[count / 2] = (0..<2400).map { "w\($0)é " }.joined() }
    return lines.joined(separator: "\n")
}

/// The text pieces random edits insert.
let insertionPool: [String] = [
    "", "a", "xyz", "é", "日本", "😀", "👨‍👩‍👧‍👦", "\n", "\r\n", "\r", "line one\nline two\n", "\t", "  ",
    "x\r\ny", String(repeating: "abc日", count: 300),
]

/// A model of the buffer: the plain bytes, with oracle versions of every conversion.
struct Oracle {
    var bytes: [UInt8]
    init(_ text: String) { bytes = Array(text.utf8) }

    var string: String { String(decoding: bytes, as: UTF8.self) }

    mutating func replace(_ r: Range<Int>, _ text: String) { bytes.replaceSubrange(r, with: Array(text.utf8)) }

    /// A random scalar boundary.
    func boundary(_ rng: inout SplitMix64) -> Int {
        var o = Int.random(in: 0...bytes.count, using: &rng)
        while o < bytes.count && bytes[o] & 0xC0 == 0x80 { o += 1 }
        return o
    }

    func scalars(upTo o: Int) -> Int { String(decoding: bytes[0..<o], as: UTF8.self).unicodeScalars.count }
    func utf16(upTo o: Int) -> Int { String(decoding: bytes[0..<o], as: UTF8.self).utf16.count }
    func point(_ o: Int) -> CodePoint {
        var row = 0, start = 0
        for i in 0..<o where bytes[i] == 0x0A { row += 1; start = i + 1 }
        return CodePoint(row: row, column: o - start)
    }
    /// The lines without terminators, split on `\n` bytes (a Swift `Character` split would treat CRLF as one).
    var rows: [String] {
        var out: [String] = []
        var start = 0
        for i in 0...bytes.count where i == bytes.count || bytes[i] == 0x0A {
            var end = i
            if i < bytes.count, end > start, bytes[end - 1] == 0x0D { end -= 1 }
            out.append(String(decoding: bytes[start..<end], as: UTF8.self))
            start = i + 1
        }
        return out
    }
    var longestLineScalars: Int {
        var best = 0, start = 0
        for i in 0...bytes.count where i == bytes.count || bytes[i] == 0x0A {
            best = max(best, String(decoding: bytes[start..<i], as: UTF8.self).unicodeScalars.count)
            start = i + 1
        }
        return best
    }
}

/// Everything the snapshot reports, compared with the oracle; returns the first difference, or nil.
func firstDifference(_ snap: CodeSnapshot, _ oracle: Oracle, _ rng: inout SplitMix64, probes: Int = 6) -> String? {
    if snap.utf8Count != oracle.bytes.count { return "utf8Count \(snap.utf8Count) vs \(oracle.bytes.count)" }
    if snap.text != oracle.string { return "text differs" }
    if snap.scalarCount != oracle.scalars(upTo: oracle.bytes.count) { return "scalarCount" }
    if snap.utf16Count != oracle.utf16(upTo: oracle.bytes.count) { return "utf16Count" }
    if snap.lineCount != oracle.rows.count { return "lineCount \(snap.lineCount) vs \(oracle.rows.count)" }
    if snap.longestLineScalars != oracle.longestLineScalars { return "longestLine \(snap.longestLineScalars) vs \(oracle.longestLineScalars)" }
    for _ in 0..<probes {
        let o = oracle.boundary(&rng)
        if snap.scalarOffset(ofUTF8: o) != oracle.scalars(upTo: o) { return "scalarOffset(ofUTF8: \(o))" }
        if snap.utf16Offset(ofUTF8: o) != oracle.utf16(upTo: o) { return "utf16Offset(ofUTF8: \(o))" }
        if snap.utf8Offset(ofScalar: oracle.scalars(upTo: o)) != o { return "utf8Offset(ofScalar:) at \(o)" }
        if snap.utf8Offset(ofUTF16: oracle.utf16(upTo: o)) != o { return "utf8Offset(ofUTF16:) at \(o)" }
        let p = oracle.point(o)
        if snap.point(at: o) != p { return "point(at: \(o)) \(snap.point(at: o)) vs \(p)" }
        if snap.offset(of: p) != o { return "offset(of: \(p))" }
        let row = p.row
        if snap.line(row) != oracle.rows[row] { return "line(\(row))" }
    }
    return nil
}
