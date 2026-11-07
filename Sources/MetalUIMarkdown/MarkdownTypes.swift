// The value types of the block parser (ruling BM-A). No imports: this target
// is Foundation-free so its bytes and results are the same on every platform.

/// How a table column's cells are aligned, read from the delimiter row (`:--`, `:-:`, `--:`; plain `---` is
/// `.none`).
///
/// The parse is cmark-gfm's block structure, not SwiftUI's: SwiftUI has no block Markdown.
public enum MarkdownTableAlignment: Hashable, Sendable {
    /// No colon in the column's delimiter cell.
    case none
    /// `:---`.
    case left
    /// `:---:`.
    case center
    /// `---:`.
    case right
}

/// One block of a Markdown document: a stable `id` and what the block is.
///
/// Inline content (emphasis, code spans, links) stays raw Markdown text in a `String`; a view parses it with
/// the inline parser `Text` already uses. The structure is CommonMark 0.31 as cmark-gfm reads it, with GFM
/// tables; link reference definitions, HTML blocks, task-list boxes, footnotes and math are not recognised and
/// appear as paragraph text (ruling `BM-B`).
public struct MarkdownBlock: Hashable, Sendable {
    /// The block's ordinal among its siblings: among the document's top-level blocks, or among the blocks of
    /// its quote or list item. Earlier ordinals never change while a document grows, and a block that changes
    /// kind (a paragraph becoming a setext heading or a table) keeps its ordinal (`BM-D`).
    public var id: Int
    /// What the block is.
    public var kind: Kind

    /// Creates a block with the given ordinal and kind.
    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// The kinds of block.
    public enum Kind: Hashable, Sendable {
        /// A paragraph: its raw inline Markdown. Lines are joined with `"\n"` (a soft break, or a hard break
        /// when the line ends in two spaces or a backslash); each line's leading whitespace is removed and the
        /// text has no trailing whitespace.
        case paragraph(String)
        /// An ATX (`# h`) or setext (`h` over `===`/`---`) heading of `level` 1 through 6, with its raw inline
        /// text (a setext heading may span lines).
        case heading(level: Int, text: String)
        /// A fenced or indented code block. `language` is the first word of a fence's info string (nil when
        /// absent and for indented code); `code` is the lines joined with `"\n"`, without a final newline.
        /// `isClosed` is false for a fence whose closing line has not been seen (it ran to the end of the
        /// input or of its container), which is how a streaming view knows the fence is still open.
        case codeBlock(language: String?, code: String, isClosed: Bool)
        /// A block quote and its blocks.
        case blockQuote([MarkdownBlock])
        /// A bullet or ordered list. `start` is the first item's number (1 for a bullet list); `tight` is
        /// false when a blank line separates items or the blocks of an item; each item is its blocks.
        case list(ordered: Bool, start: Int, tight: Bool, items: [[MarkdownBlock]])
        /// A thematic break (`---`, `***`, `___`).
        case thematicBreak
        /// A GFM table: one alignment per column; the header cells and the body rows, each row padded with
        /// empty cells or cut to the header's column count. Cell text is raw inline Markdown, with `\|`
        /// already unescaped to `|`.
        case table(alignments: [MarkdownTableAlignment], header: [String], rows: [[String]])
    }
}

/// Counters for the complexity pins (`BM-C`): plain memory behind raw pointers, so a test reads work done, not
/// time. Only meaningful in a single-threaded test.
package enum MarkdownParseStats {
    nonisolated(unsafe) private static let counters: UnsafeMutablePointer<Int> = {
        let p = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        p.initialize(repeating: 0, count: 4)
        return p
    }()

    /// Bytes handed to the block parser since the process started (or the last reset).
    package static var bytesScanned: Int {
        get { counters[0] }
        set { counters[0] = newValue }
    }
    /// Bytes compared by a convenience that checks a new source against the previous one (the view, `BM-C`).
    package static var bytesCompared: Int {
        get { counters[1] }
        set { counters[1] = newValue }
    }
    /// Blocks moved from the re-parsed tail into the final blocks.
    package static var blocksFinalized: Int {
        get { counters[2] }
        set { counters[2] = newValue }
    }
    /// Bytes copied because a document's tail storage was shared when an append needed to change it.
    package static var bytesCopied: Int {
        get { counters[3] }
        set { counters[3] = newValue }
    }
    /// Sets every counter to zero.
    package static func reset() {
        counters.update(repeating: 0, count: 4)
    }
}
