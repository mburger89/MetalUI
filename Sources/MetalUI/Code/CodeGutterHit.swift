/// What a click or a context menu on a ``CodeView``'s gutter bar hit (`CV-AB`): the bar's line range, the
/// app's tag and whether the bar belongs to a line decoration or to a virtual row.
public struct CodeGutterHit: Equatable, Sendable {
    /// Where the bar comes from.
    public enum Source: Equatable, Sendable {
        /// A ``CodeLineDecoration``'s gutter bar over buffer rows.
        case lineDecoration
        /// A ``CodeVirtualRow``'s gutter bar beside its read-only lines (a diff's removed lines).
        case virtualRow
    }

    /// The buffer lines the bar spans (0-based). For a virtual row, its anchor line as a one-line range.
    public var lines: Range<Int>
    /// The ``CodeLineDecoration/tag`` or ``CodeVirtualRow/tag`` of the bar; `nil` if it had none.
    public var tag: UInt64?
    /// Whether a line decoration or a virtual row was hit.
    public var source: Source
    /// The display row that was hit (a buffer row's, or a virtual line's, in the view's row order).
    public var displayRow: Int

    /// A hit.
    public init(lines: Range<Int>, tag: UInt64?, source: Source, displayRow: Int) {
        self.lines = lines
        self.tag = tag
        self.source = source
        self.displayRow = displayRow
    }
}
