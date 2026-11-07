/// What a stretch of UTF-8 text adds up to. Every node of the rope stores one for its subtree, so a
/// conversion between units is one descent (`CV-B`).
///
/// A "line" here is a run between `\n` bytes; the `\r` of a CRLF belongs to the line it ends. The
/// three line fields exist so two summaries combine without looking at the text again: the longest
/// line of `a + b` can span the join, which needs `a`'s last line and `b`'s first.
struct Summary: Equatable, Sendable {
    /// Bytes.
    var utf8 = 0
    /// UTF-16 code units (scalars plus the number of four-byte scalars).
    var utf16 = 0
    /// Unicode scalars.
    var scalars = 0
    /// `\n` bytes.
    var newlines = 0
    /// Scalars before the first `\n` (all of them when there is none).
    var firstLine = 0
    /// Scalars after the last `\n` (all of them when there is none).
    var lastLine = 0
    /// Bytes after the last `\n` (all of them when there is none).
    var lastLineBytes = 0
    /// Scalars in the longest line, not counting its `\n`.
    var longestLine = 0

    static let zero = Summary()

    /// Appends the summary of the text that follows this one.
    mutating func append(_ b: Summary) {
        longestLine = max(longestLine, b.longestLine, lastLine + b.firstLine)
        if newlines == 0 { firstLine += b.firstLine }
        if b.newlines == 0 {
            lastLine += b.lastLine
            lastLineBytes += b.lastLineBytes
        } else {
            lastLine = b.lastLine
            lastLineBytes = b.lastLineBytes
        }
        utf8 += b.utf8
        utf16 += b.utf16
        scalars += b.scalars
        newlines += b.newlines
    }

    /// The summary of a run of UTF-8 bytes.
    static func of(_ bytes: UnsafeBufferPointer<UInt8>) -> Summary {
        var s = Summary()
        var current = 0
        var currentBytes = 0
        var seenNewline = false
        for b in bytes {
            if b & 0xC0 != 0x80 {
                s.scalars += 1
                s.utf16 += b >= 0xF0 ? 2 : 1
                if b == 0x0A {
                    s.newlines += 1
                    if !seenNewline { s.firstLine = current; seenNewline = true }
                    s.longestLine = max(s.longestLine, current)
                    current = 0
                    currentBytes = 0
                    continue
                }
                current += 1
            }
            currentBytes += 1
        }
        if !seenNewline { s.firstLine = current }
        s.lastLine = current
        s.lastLineBytes = currentBytes
        s.longestLine = max(s.longestLine, current)
        s.utf8 = bytes.count
        return s
    }

    static func of(_ bytes: ContiguousArray<UInt8>, upTo n: Int) -> Summary {
        bytes.withUnsafeBufferPointer { Summary.of(UnsafeBufferPointer(rebasing: $0[0..<n])) }
    }
}

/// A summary squeezed into 14 bytes: a chunk is at most `Rope.maxChunk` bytes, so every count fits a
/// `UInt16`. Storing these (not `Summary`) is what keeps the per-chunk bookkeeping near 0.2 of the text
/// (`CV-B`).
struct ChunkSummary: Equatable, Sendable {
    var utf16: UInt16
    var scalars: UInt16
    var newlines: UInt16
    var firstLine: UInt16
    var lastLine: UInt16
    var lastLineBytes: UInt16
    var longestLine: UInt16

    init(_ s: Summary) {
        utf16 = UInt16(s.utf16)
        scalars = UInt16(s.scalars)
        newlines = UInt16(s.newlines)
        firstLine = UInt16(s.firstLine)
        lastLine = UInt16(s.lastLine)
        lastLineBytes = UInt16(s.lastLineBytes)
        longestLine = UInt16(s.longestLine)
    }
}

/// A leaf item: a run of whole scalars, never split inside a scalar or between the `\r` and `\n` of a
/// CRLF. The array is never mutated after it is made, so a chunk is safe to share between snapshots.
struct Chunk: Sendable {
    var bytes: ContiguousArray<UInt8>
    var compact: ChunkSummary
    var count: Int { bytes.count }

    init(_ bytes: ContiguousArray<UInt8>) {
        self.bytes = bytes
        compact = ChunkSummary(Summary.of(bytes, upTo: bytes.count))
    }

    var summary: Summary {
        Summary(utf8: bytes.count, utf16: Int(compact.utf16), scalars: Int(compact.scalars),
                newlines: Int(compact.newlines), firstLine: Int(compact.firstLine),
                lastLine: Int(compact.lastLine), lastLineBytes: Int(compact.lastLineBytes),
                longestLine: Int(compact.longestLine))
    }
}

/// Node-visit counter for the complexity pins (`CV-B`): one increment per node a rope operation enters.
/// Plain memory behind a raw pointer, so concurrent snapshot readers cannot trip exclusivity checking;
/// the count is only meaningful in a single-threaded test.
package enum RopeStats {
    nonisolated(unsafe) private static let counter: UnsafeMutablePointer<Int> = {
        let p = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        p.initialize(to: 0)
        return p
    }()

    /// How many rope nodes operations have entered since the process started (or since the last reset).
    package static var nodesVisited: Int {
        get { counter.pointee }
        set { counter.pointee = newValue }
    }

    @inline(__always) static func visit() { counter.pointee &+= 1 }
}
