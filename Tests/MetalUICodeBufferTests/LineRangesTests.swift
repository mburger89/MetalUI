import Testing
@testable import MetalUICodeBuffer

// `CV-AH` (record 265): a window of rows is one seek and a forward scan.

@MainActor
@Suite(.serialized) struct LineRangesTests {
    /// The per-row answer computed from the text itself, the oracle for `lineRanges`.
    private func oracle(_ text: String) -> [Range<Int>] {
        let bytes = Array(text.utf8)
        var result: [Range<Int>] = []
        var start = 0
        for (i, b) in bytes.enumerated() where b == 0x0A {
            result.append(start..<(i > start && bytes[i - 1] == 0x0D ? i - 1 : i))
            start = i + 1
        }
        result.append(start..<bytes.count)
        return result
    }

    /// The pre-`CV-AH` spelling of `lineRange`: two seeks and a byte probe per row.
    private func oldLineRange(_ snap: CodeSnapshot, _ row: Int) -> Range<Int> {
        let start = snap.rope.lineStart(row: row)
        guard row + 1 < snap.lineCount else { return start..<snap.utf8Count }
        var end = snap.rope.lineStart(row: row + 1) - 1
        if end > start, snap.rope.byte(at: end - 1) == 0x0D { end -= 1 }
        return start..<end
    }

    /// (d) — `lineRanges` equals the per-row oracle and `lineRange`, for edge texts and random texts.
    @Test func lineRangesEqualTheOracleAndPerRowLineRange() {
        var rng = SplitMix64(seed: 0xA11_0C)
        var texts = ["", "\n", "\n\n", "a", "a\n", "\na", "a\r\nb\r\n\r\nc", "\r", "a\r", "\r\n", "x\n\n\ny\n", "é\n😀\r\nz"]
        let pool = ["a", "bc", "\n", "\n", "\r\n", "\r", "é", "😀", " ", "\t"]
        for _ in 0..<60 {
            var t = ""
            for _ in 0..<Int.random(in: 0..<60, using: &rng) { t += pool[Int.random(in: 0..<pool.count, using: &rng)] }
            texts.append(t)
        }
        texts.append(fixtureText(lines: 3000))
        for text in texts {
            let snap = CodeBuffer(text).snapshot()
            let expected = oracle(text)
            #expect(expected.count == snap.lineCount)
            #expect(snap.lineRanges(rows: 0..<snap.lineCount) == expected, "all rows of \(text.debugDescription.prefix(40))")
            for row in 0..<snap.lineCount where row < 40 || row % 97 == 0 {
                #expect(snap.lineRange(row) == expected[row], "row \(row)")
                let hi = min(snap.lineCount, row + Int.random(in: 1..<9, using: &rng))
                #expect(snap.lineRanges(rows: row..<hi) == Array(expected[row..<hi]), "rows \(row)..<\(hi)")
            }
        }
        let snap = CodeBuffer("a\nb").snapshot()
        #expect(snap.lineRanges(rows: -3..<9) == [0..<1, 2..<3], "clamped to the text's rows")
        #expect(snap.lineRanges(rows: 5..<9).isEmpty && snap.lineRanges(rows: 1..<1).isEmpty)
        #expect(snap.lineRange(7) == 3..<3 && snap.lineRange(-1) == 3..<3)
    }

    /// (a) — a window of 60 rows in a 100k-line buffer costs O(depth + rows) nodes, where per-row seeks
    /// cost rows * depth. **Red before:** `lineRanges` as a loop over `lineRange` visits several hundred.
    @Test func aWindowOfRowsCostsOneSeekAndAScan() {
        let snap = CodeBuffer(fixtureText(lines: 100_000)).snapshot()
        let window = 50_000..<50_060
        func visits(_ body: () -> Void) -> Int {
            let before = RopeStats.nodesVisited
            body()
            return RopeStats.nodesVisited - before
        }
        var batch: [Range<Int>] = []
        let batched = visits { batch = snap.lineRanges(rows: window) }
        var perRow: [Range<Int>] = []
        let looped = visits { for row in window { perRow.append(oldLineRange(snap, row)) } }
        #expect(batch == perRow)
        let single = visits { _ = snap.lineRange(50_000) }
        #expect(batched <= single + 20, "batched \(batched), one row \(single)")
        #expect(looped > 4 * batched, "per-row seeks \(looped) against batched \(batched)")
        #expect(single < 30, "a single row stays one seek: \(single)")
    }
}
