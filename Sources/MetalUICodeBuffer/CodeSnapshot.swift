/// An immutable view of a buffer's text at one version. Taking one is O(1); later edits to the buffer
/// never change it (the tree is copy-on-write), and it is `Sendable`, so a parser can read it on another
/// thread while the user keeps typing.
///
/// Offsets are UTF-8 bytes unless a name says otherwise. Every conversion is O(log n) plus one chunk.
public struct CodeSnapshot: Sendable {
    let rope: Rope
    /// The buffer's version when this snapshot was taken.
    public let version: UInt64

    init(rope: Rope, version: UInt64) {
        self.rope = rope
        self.version = version
    }

    /// The number of bytes.
    public var utf8Count: Int { rope.summary.utf8 }
    /// The number of Unicode scalars.
    public var scalarCount: Int { rope.summary.scalars }
    /// The number of UTF-16 code units.
    public var utf16Count: Int { rope.summary.utf16 }
    /// The number of lines: one more than the number of `\n`, so an empty text has one.
    public var lineCount: Int { rope.summary.newlines + 1 }
    /// The scalar count of the longest line, not counting its `\n`.
    public var longestLineScalars: Int { rope.summary.longestLine }

    /// The whole text.
    public var text: String { text(in: 0..<utf8Count) }

    /// The text in `range`, clamped to the text. Both ends must be on scalar boundaries.
    public func text(in range: Range<Int>) -> String {
        let lo = max(0, min(range.lowerBound, utf8Count))
        let hi = max(lo, min(range.upperBound, utf8Count))
        var bytes = [UInt8]()
        bytes.reserveCapacity(hi - lo)
        rope.forEachSlice(lo, hi) { bytes.append(contentsOf: $0); return true }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The bytes of `range`, clamped to the text.
    public func utf8(in range: Range<Int>) -> [UInt8] {
        let lo = max(0, min(range.lowerBound, utf8Count))
        let hi = max(lo, min(range.upperBound, utf8Count))
        var bytes = [UInt8]()
        bytes.reserveCapacity(hi - lo)
        rope.forEachSlice(lo, hi) { bytes.append(contentsOf: $0); return true }
        return bytes
    }

    /// The bytes of line `row` without its terminator: the `\n`, and the `\r` before it when the line ends
    /// in CRLF. Empty when `row` is out of range.
    public func lineRange(_ row: Int) -> Range<Int> {
        guard row >= 0, row < lineCount else { return utf8Count..<utf8Count }
        let start = rope.lineStart(row: row)
        guard row + 1 < lineCount else { return start..<utf8Count }
        var end = rope.lineStart(row: row + 1) - 1
        if end > start, rope.byte(at: end - 1) == 0x0D { end -= 1 }
        return start..<end
    }

    /// The text of line `row` without its terminator; empty when `row` is out of range.
    public func line(_ row: Int) -> String { text(in: lineRange(row)) }

    /// The byte offset of `point`. A row past the last is clamped to it, a column past the end of its row
    /// to the row's end (before the `\n`).
    public func offset(of point: CodePoint) -> Int {
        let row = max(0, min(point.row, lineCount - 1))
        let start = rope.lineStart(row: row)
        let end = row + 1 < lineCount ? rope.lineStart(row: row + 1) - 1 : utf8Count
        return start + max(0, min(point.column, end - start))
    }

    /// The row and byte column of `offset`, clamped to the text.
    public func point(at offset: Int) -> CodePoint {
        let s = rope.prefix(utf8: max(0, min(offset, utf8Count)))
        return CodePoint(row: s.newlines, column: s.lastLineBytes)
    }

    /// The number of scalars before byte `offset`.
    public func scalarOffset(ofUTF8 offset: Int) -> Int { rope.prefix(utf8: max(0, min(offset, utf8Count))).scalars }
    /// The byte offset of scalar `scalar`.
    public func utf8Offset(ofScalar scalar: Int) -> Int { rope.utf8Offset(ofScalar: min(scalar, scalarCount)) }
    /// The number of UTF-16 code units before byte `offset`.
    public func utf16Offset(ofUTF8 offset: Int) -> Int { rope.prefix(utf8: max(0, min(offset, utf8Count))).utf16 }
    /// The byte offset of UTF-16 unit `unit`; a unit inside a surrogate pair rounds down to the scalar.
    public func utf8Offset(ofUTF16 unit: Int) -> Int { rope.utf8Offset(ofUTF16: min(unit, utf16Count)) }

    /// The byte at `offset`, which must be below `utf8Count`.
    public func byte(at offset: Int) -> UInt8 { rope.byte(at: offset) }

    /// Whether `offset` is between scalars (not inside a multi-byte one).
    public func isScalarBoundary(_ offset: Int) -> Bool {
        offset == 0 || offset == utf8Count || (offset > 0 && offset < utf8Count && !isContinuation(rope.byte(at: offset)))
    }

    /// The ranges `query` matches, left to right and not overlapping, at most `limit` of them (`CV-H`).
    /// O(n) per call: run it when the query changes, never per frame. Matching is bytewise, so a match
    /// always starts and ends on a scalar boundary.
    public func ranges(of query: String, options: CodeFindOptions = [], limit: Int? = nil) -> [Range<Int>] {
        let fold = options.contains(.caseInsensitive)
        @inline(__always) func f(_ b: UInt8) -> UInt8 { fold && b >= 0x41 && b <= 0x5A ? b | 0x20 : b }
        let q = query.utf8.map(f)
        if q.isEmpty || (limit ?? 1) <= 0 { return [] }
        var fail = [Int](repeating: 0, count: q.count)
        var k = 0
        for i in 1..<max(q.count, 1) where i < q.count {
            while k > 0 && q[i] != q[k] { k = fail[k - 1] }
            if q[i] == q[k] { k += 1 }
            fail[i] = k
        }
        let whole = options.contains(.wholeWord)
        func isWord(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b >= 0x80
        }
        var results: [Range<Int>] = []
        var state = 0
        var pos = 0
        rope.forEachSlice(0, utf8Count) { buffer in
            for raw in buffer {
                let c = f(raw)
                while state > 0 && (state == q.count || q[state] != c) { state = fail[state - 1] }
                if q[state] == c { state += 1 }
                pos += 1
                if state == q.count {
                    let start = pos - q.count
                    let ok = !whole
                        || ((start == 0 || !isWord(rope.byte(at: start - 1))) && (pos == utf8Count || !isWord(rope.byte(at: pos))))
                    if ok {
                        results.append(start..<pos)
                        state = 0
                        if let limit, results.count >= limit { return false }
                    }
                }
            }
            return true
        }
        return results
    }
}
