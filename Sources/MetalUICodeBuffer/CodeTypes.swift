/// A position in a buffer as a row and a column. Both count from 0 and the column counts UTF-8 bytes from
/// the start of the row, the unit tree-sitter's `TSPoint` uses.
public struct CodePoint: Hashable, Comparable, Sendable {
    /// The row, counting `\n` bytes before the position.
    public var row: Int
    /// The column, in UTF-8 bytes from the start of the row.
    public var column: Int

    /// A point at `row` and `column`.
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Whether `a` comes before `b`: by row, then by column.
    public static func < (a: CodePoint, b: CodePoint) -> Bool {
        a.row != b.row ? a.row < b.row : a.column < b.column
    }
}

/// Names one transaction: a group of edits that undo reverts together. Ids are never reused within a buffer.
public struct CodeTransactionID: Hashable, Sendable {
    /// The id's number, increasing in the order transactions begin.
    public let rawValue: UInt64

    /// An id with this number.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// A selection as an anchor and a head, in UTF-8 byte offsets. The head is the end that moves; when it is
/// before the anchor the selection runs backwards. A selection with equal ends is a caret.
public struct CodeSelection: Hashable, Sendable {
    /// The end that stays put while the selection grows.
    public var anchor: Int
    /// The end that moves, and where the caret is drawn.
    public var head: Int

    /// A selection from `anchor` to `head`.
    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    /// A caret at `offset`.
    public init(caret offset: Int) {
        anchor = offset
        head = offset
    }

    /// The selected bytes, ordered.
    public var range: Range<Int> { min(anchor, head)..<max(anchor, head) }

    /// Whether the selection is a caret.
    public var isEmpty: Bool { anchor == head }
}

/// A replacement for the bytes in `range`, in the coordinates of the text before any of a group of edits.
public struct CodeTextEdit: Sendable {
    /// The UTF-8 byte range to replace.
    public var range: Range<Int>
    /// What replaces it.
    public var text: String

    /// An edit replacing `range` with `text`.
    public init(range: Range<Int>, text: String) {
        self.range = range
        self.text = text
    }
}

/// Where an edit came from. Undo and redo name the transaction they revert or reapply.
public enum CodeEditOrigin: Hashable, Sendable {
    /// The user typed. Consecutive typing at the caret is one undo step.
    case typing
    /// The user pasted.
    case paste
    /// The user deleted. Consecutive backspaces or forward deletes are one undo step.
    case deletion
    /// Undo reverted the transaction.
    case undo(CodeTransactionID)
    /// Redo reapplied the transaction.
    case redo(CodeTransactionID)
    /// Something outside the editor changed the text (a file reload, an agent's patch); not undoable.
    case external
    /// Code changed the text.
    case programmatic
}

/// One replacement the buffer made, reported in the coordinates of the text just before it.
public struct CodeEdit: Sendable {
    /// The buffer's version after this event. It rises by exactly 1 per event and is never reused.
    public let version: UInt64
    /// The transaction the event belongs to.
    public let transaction: CodeTransactionID
    /// Where the event came from.
    public let origin: CodeEditOrigin
    /// The replaced bytes, before the event.
    public let range: Range<Int>
    /// The replaced Unicode scalars, before the event.
    public let scalarRange: Range<Int>
    /// Where the replaced range starts, before the event.
    public let startPoint: CodePoint
    /// Where the replaced range ended, before the event.
    public let oldEndPoint: CodePoint
    /// Where the inserted text ends, after the event.
    public let newEndPoint: CodePoint
    /// What replaced the range.
    public let newText: String

    /// An event with these fields.
    public init(version: UInt64, transaction: CodeTransactionID, origin: CodeEditOrigin, range: Range<Int>,
                scalarRange: Range<Int>, startPoint: CodePoint, oldEndPoint: CodePoint, newEndPoint: CodePoint,
                newText: String) {
        self.version = version
        self.transaction = transaction
        self.origin = origin
        self.range = range
        self.scalarRange = scalarRange
        self.startPoint = startPoint
        self.oldEndPoint = oldEndPoint
        self.newEndPoint = newEndPoint
        self.newText = newText
    }
}

/// What a cursor hands back: the events since its last drain, or, when the log no longer reaches back that
/// far, a snapshot to start over from.
public enum CodeEditBatch: Sendable {
    /// Every event since the last drain, oldest first (possibly none).
    case edits([CodeEdit])
    /// The cursor fell too far behind; read the whole text from this snapshot.
    case resync(CodeSnapshot)
}

/// Why a buffer refused an edit.
public enum CodeBufferError: Error, Sendable, Equatable {
    /// The buffer's version is not the one the caller expected; `current` is the buffer's.
    case stale(current: UInt64)
    /// The buffer is read-only.
    case readOnly
    /// A range is out of bounds, inside a scalar, or overlaps another edit of the same call.
    case invalidRange
}

/// How an offset sitting exactly at an insertion point moves when text is inserted there.
public enum CodeBias: Sendable {
    /// Stay in front of the inserted text.
    case before
    /// Move behind the inserted text.
    case after
}

/// The line ending a file uses; Return inserts it.
public enum CodeLineEnding: Sendable {
    /// `\n`.
    case lf
    /// `\r\n`.
    case crlf

    /// The ending as text.
    public var text: String { self == .lf ? "\n" : "\r\n" }
}

/// What a find matches.
public struct CodeFindOptions: OptionSet, Sendable {
    /// The option bits.
    public let rawValue: Int

    /// Options with these bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ASCII letters match regardless of case; other scalars match exactly.
    public static let caseInsensitive = CodeFindOptions(rawValue: 1)
    /// A match must not touch a word character on either side. A word character is an ASCII letter,
    /// digit or underscore, or any non-ASCII scalar.
    public static let wholeWord = CodeFindOptions(rawValue: 2)
}
