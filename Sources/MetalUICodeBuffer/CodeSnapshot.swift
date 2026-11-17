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
        return lineRanges(rows: row..<(row + 1))[0]
    }

    /// ``lineRange(_:)`` of every row in `rows` (clamped to the text's rows), in order: one seek to the first
    /// row and a forward scan, so a window of N rows costs O(depth + N) rope nodes, not N seeks (`CV-AH`).
    package func lineRanges(rows: Range<Int>) -> [Range<Int>] {
        let lo = max(0, rows.lowerBound), hi = min(lineCount, rows.upperBound)
        guard lo < hi else { return [] }
        let wanted = hi - lo
        var result = [Range<Int>]()
        result.reserveCapacity(wanted)
        var position = rope.lineStart(row: lo)
        var rowStart = position
        var previousWasCR = false
        rope.forEachSlice(position, utf8Count) { bytes in
            for byte in bytes {
                if byte == 0x0A {
                    result.append(rowStart..<(previousWasCR ? position - 1 : position))
                    if result.count == wanted { return false }
                    rowStart = position + 1
                    previousWasCR = false
                } else {
                    previousWasCR = byte == 0x0D
                }
                position += 1
            }
            return true
        }
        if result.count < wanted { result.append(rowStart..<utf8Count) }   // the last row has no terminator
        return result
    }

    /// The text of line `row` without its terminator; empty when `row` is out of range.
    public func line(_ row: Int) -> String { text(in: lineRange(row)) }

    /// The byte offset of `point`. A row past the last is clamped to it, a column past the end of its row
    /// to the row's end (before the `\n`).
    public func offset(of point: CodePoint) -> Int {
        let row = max(0, min(point.row, lineCount - 1))
        let start = rope.lineStart(row: row)
        var end = utf8Count
        if row + 1 < lineCount {   // up to the row's `\n`, one forward scan from its start
            var position = start
            rope.forEachSlice(start, utf8Count) { bytes in
                for byte in bytes {
                    if byte == 0x0A { end = position; return false }
                    position += 1
                }
                return true
            }
        }
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
        if (limit ?? 1) <= 0 { return [] }
        var results: [Range<Int>] = []
        scan(query, options: options, in: 0..<utf8Count) { match in
            results.append(match)
            if let limit, results.count >= limit { return true }
            return false
        }
        return results
    }

    /// The first match of `query` that starts at or after `offset`, wrapping to the text's start, for which
    /// `accept` is true (`CV-BJ`); `nil` when there is none. One forward scan of the text after `offset`, then of
    /// the text before it (a match may straddle `offset` only on the wrapped pass), so O(n) and never per frame.
    package func firstRange(of query: String, options: CodeFindOptions = [], from offset: Int,
                            accept: (Range<Int>) -> Bool = { _ in true }) -> Range<Int>? {
        let from = max(0, min(offset, utf8Count))
        let wrapEnd = min(utf8Count, from + query.utf8.count - 1)
        var found: Range<Int>?
        for window in [from..<utf8Count, 0..<wrapEnd] where found == nil && window.lowerBound < window.upperBound {
            scan(query, options: options, in: window) { match in
                if accept(match) { found = match; return true }
                return false
            }
        }
        return found
    }

    /// Calls `visit` with each match inside `window`, left to right and not overlapping, until it returns true.
    /// A whole-word check reads the bytes just outside the window.
    private func scan(_ query: String, options: CodeFindOptions, in window: Range<Int>, visit: (Range<Int>) -> Bool) {
        let fold = options.contains(.caseInsensitive)
        @inline(__always) func f(_ b: UInt8) -> UInt8 { fold && b >= 0x41 && b <= 0x5A ? b | 0x20 : b }
        let q = query.utf8.map(f)
        if q.isEmpty { return }
        var fail = [Int](repeating: 0, count: q.count)
        var k = 0
        for i in 1..<max(q.count, 1) where i < q.count {
            while k > 0 && q[i] != q[k] { k = fail[k - 1] }
            if q[i] == q[k] { k += 1 }
            fail[i] = k
        }
        let whole = options.contains(.wholeWord)
        var state = 0
        var pos = window.lowerBound
        rope.forEachSlice(window.lowerBound, window.upperBound) { buffer in
            for raw in buffer {
                let c = f(raw)
                while state > 0 && (state == q.count || q[state] != c) { state = fail[state - 1] }
                if q[state] == c { state += 1 }
                pos += 1
                if state == q.count {
                    let start = pos - q.count
                    let ok = !whole
                        || ((start == 0 || !Self.isWordByte(rope.byte(at: start - 1))) && (pos == utf8Count || !Self.isWordByte(rope.byte(at: pos))))
                    if ok {
                        state = 0
                        if visit(start..<pos) { return false }
                    }
                }
            }
            return true
        }
    }

    /// Whether `b` is part of a word for `.wholeWord` and the selection helpers: an ASCII letter, digit or `_`, or
    /// any byte of a non-ASCII scalar (`CV-BJ`).
    package static func isWordByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b >= 0x80
    }

    /// The bytes of the word touching `offset` (a run of word bytes ending at or starting at it), or `nil`.
    package func wordRange(at offset: Int) -> Range<Int>? {
        let o = max(0, min(offset, utf8Count))
        var lo = o, hi = o
        while lo > 0, Self.isWordByte(rope.byte(at: lo - 1)) { lo -= 1 }
        while hi < utf8Count, Self.isWordByte(rope.byte(at: hi)) { hi += 1 }
        return lo < hi ? lo..<hi : nil
    }
}
