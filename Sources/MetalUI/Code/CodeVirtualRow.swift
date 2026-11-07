import MetalUICodeBuffer

/// A mark in the gutter beside a virtual line: a short text drawn where a buffer row's number is, such as
/// `"+"`, `"-"` or `"~"` beside the removed lines of a diff.
public struct CodeGutterMarker: Hashable, Sendable {
    /// The text, right-aligned in the line-number column.
    public var text: String
    /// Its colour; `nil` uses the theme's gutter colour.
    public var color: Color?

    /// A marker showing `text` in `color`.
    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }
}

/// Read-only lines shown between buffer rows (`CV-S`): the removed lines of an inline diff, a blame or
/// diagnostic note, or **filler** (blank lines) that keeps two views of a side-by-side diff aligned.
///
/// A virtual row is not text of the buffer: it has no line number, cannot be selected, copied or edited,
/// scrolls with the buffer, and follows the buffer's edits like a line decoration (its anchor row moves with
/// the newlines above it). Give them with ``CodeDecorations/setVirtualRows(_:asOf:)``.
public struct CodeVirtualRow: Sendable {
    /// Where the lines sit: before or after a buffer row (0-based).
    public enum Anchor: Hashable, Sendable {
        /// Between the row before `line` and `line`; `line == lineCount` is after the last row.
        case before(line: Int)
        /// Between `line` and the row after it.
        case after(line: Int)

        /// The gap position: the number of buffer rows above the lines.
        var gap: Int {
            switch self {
            case .before(let line): return max(0, line)
            case .after(let line): return max(0, line) + 1
            }
        }

        var isAfter: Bool {
            if case .after = self { return true }
            return false
        }
    }

    /// Where the lines sit, as of the `asOf` version they are given at.
    public var anchor: Anchor
    /// The lines shown, one display row each. A line is its text up to the first line break.
    public var lines: [String]
    /// Colours per line: `styleRuns[i]` colours the UTF-8 byte ranges of `lines[i]` (offsets from that line's
    /// start). Missing entries mean no colour. Runs of one line must not overlap; a later overlap is cut.
    public var styleRuns: [[CodeStyleRun]]
    /// A bar in the gutter beside the lines; `nil` draws none.
    public var gutterBar: Color?
    /// A tint across the lines' full width; `nil` draws none.
    public var background: Color?
    /// A marker drawn in the number column of every line; `nil` draws none.
    public var gutterMarker: CodeGutterMarker?
    /// An app-defined identifier handed back in the ``CodeGutterHit`` of a click or context menu on this
    /// row's gutter bar (the removed hunk's id, say); `nil` for none.
    public var tag: UInt64?

    /// Virtual lines at `anchor`.
    public init(anchor: Anchor, lines: [String], styleRuns: [[CodeStyleRun]] = [], gutterBar: Color? = nil,
                background: Color? = nil, gutterMarker: CodeGutterMarker? = nil, tag: UInt64? = nil) {
        self.tag = tag
        self.anchor = anchor
        self.lines = lines
        self.styleRuns = styleRuns
        self.gutterBar = gutterBar
        self.background = background
        self.gutterMarker = gutterMarker
    }

    /// `count` blank lines at `anchor`, optionally tinted: the filler that aligns the rows of one side of a
    /// side-by-side diff with the other.
    public static func filler(_ count: Int, at anchor: Anchor, background: Color? = nil, gutterBar: Color? = nil) -> CodeVirtualRow {
        CodeVirtualRow(anchor: anchor, lines: Array(repeating: "", count: max(0, count)), gutterBar: gutterBar, background: background)
    }
}
