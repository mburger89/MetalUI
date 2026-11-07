// A growing Markdown document (rulings BM-C, BM-D): the blocks before the last
// top-level block are final and never touched again; the last block is re-parsed
// from its first line on every append.

/// Storage for the bytes of the last top-level block. A class so a copied document shares it until one copy
/// appends, and the copy that must diverge is *counted* (`MarkdownParseStats.bytesCopied`).
final class MarkdownTailStorage: @unchecked Sendable {
    var bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }
}

/// A Markdown document that grows by appending text, such as a chat reply streaming in token by token.
///
/// `append(_:)` costs time proportional to the length of the *last top-level block* plus the appended text,
/// whatever came before: every top-level block that starts before the last one is final, because at the
/// first line of the last block no container is open and nothing in a later complete line can reach back
/// into an earlier block (`BM-C`). One exception, found by streaming a corpus a scalar at a time: while the
/// text ends in a line with no newline whose bytes so far are only block-structure characters (`-`, `#`,
/// `|`, digits, spaces and the like), more text on that line can still turn what it starts into a
/// continuation of the block above, so that block is parsed again too until the line gets a letter or a
/// newline. The result always equals parsing the whole text at once, with the same block ids (`BM-D`).
///
/// The parse is cmark-gfm's block structure (CommonMark 0.31 plus GFM tables), not SwiftUI's: SwiftUI has no
/// block Markdown. Copying a document is cheap; the copy that appends next pays for the last block only.
public struct MarkdownDocument: Sendable {
    private var finalBlocks: [MarkdownBlock] = []
    private var tailBlocks: [MarkdownBlock] = []
    private var tail = MarkdownTailStorage([])
    /// Increases by one on every ``append(_:)`` that adds text.
    public private(set) var version: Int = 0

    /// An empty document.
    public init() {}

    /// A document holding the blocks of `text`.
    public init(parsing text: String) {
        self.init()
        append(text)
    }

    /// The document's top-level blocks, in order. Building the array is O(number of blocks); a block's `id`
    /// is its index.
    public var blocks: [MarkdownBlock] { finalBlocks + tailBlocks }

    /// Appends `text` and updates the blocks. Only the last top-level block is parsed again.
    public mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        if !isKnownUniquelyReferenced(&tail) {
            MarkdownParseStats.bytesCopied += tail.bytes.count
            tail = MarkdownTailStorage(tail.bytes)
        }
        tail.bytes.append(contentsOf: text.utf8)
        version += 1
        let parsed = BlockParser.parse(tail.bytes)
        let base = finalBlocks.count
        // Blocks before `keep` are final. Normally that is the last block; while the input ends in a line that
        // is still only block-structure characters, what that line starts (a block, a table that splits the
        // paragraph above it) may yet turn out to continue or reshape the block before it, so that block
        // stays in the tail too (BM-C).
        var keep = max(parsed.count - 1, 0)
        if keep > 0, Self.lastLineIsProvisional(tail.bytes) { keep -= 1 }
        for i in 0..<keep { finalBlocks.append(MarkdownBlock(id: base + i, kind: parsed[i].kind)) }
        MarkdownParseStats.blocksFinalized += keep
        tailBlocks = (keep..<parsed.count).map { MarkdownBlock(id: base + $0, kind: parsed[$0].kind) }
        let cut = parsed.isEmpty ? Self.lastLineStart(tail.bytes) : parsed[keep].start
        if cut > 0 { tail.bytes.removeSubrange(0..<cut) }
    }

    /// Offset of the first byte after the last line terminator (the input's length when it ends in one).
    static func lastLineStart(_ bytes: [UInt8]) -> Int {
        var i = bytes.count
        while i > 0, bytes[i - 1] != 10, bytes[i - 1] != 13 { i -= 1 }
        return i
    }

    /// True when the input ends in a line with no terminator whose bytes so far are all block-structure
    /// characters (spaces, tabs, `# > * + - _ = | : . ) ~` and digits), or that opens a backtick fence: more
    /// text on that line can still change what block it starts, so the block before it must stay in the tail.
    /// Once a line holds any other byte every decision taken from its start is final.
    static func lastLineIsProvisional(_ bytes: [UInt8]) -> Bool {
        let start = lastLineStart(bytes)
        if start >= bytes.count { return false }
        var firstNonspace = start
        while firstNonspace < bytes.count, bytes[firstNonspace] == 32 || bytes[firstNonspace] == 9 { firstNonspace += 1 }
        if firstNonspace < bytes.count, bytes[firstNonspace] == 96 { return true }
        for i in start..<bytes.count {
            switch bytes[i] {
            case 32, 9, 35, 62, 42, 43, 45, 95, 61, 124, 58, 46, 41, 126, 96, 48...57: continue
            default: return false
            }
        }
        return true
    }

    /// The blocks of `text` parsed in one pass with no tail re-parse: the reference the streaming path must equal.
    package static func parseWhole(_ text: String) -> [MarkdownBlock] {
        let parsed = BlockParser.parse(Array(text.utf8))
        return parsed.enumerated().map { MarkdownBlock(id: $0.offset, kind: $0.element.kind) }
    }
}
