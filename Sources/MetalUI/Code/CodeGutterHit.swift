/// What a click or a context menu on a ``CodeView``'s gutter bar or marker hit (`CV-AB`, `CV-AP`): the line range,
/// the app's tag, the owner and whether it belongs to a line decoration, a virtual row or a gutter marker.
public struct CodeGutterHit: Equatable, Sendable {
    /// Where the bar comes from.
    public enum Source: Equatable, Sendable {
        /// A ``CodeLineDecoration``'s gutter bar over buffer rows.
        case lineDecoration
        /// A ``CodeVirtualRow``'s gutter bar beside its read-only lines (a diff's removed lines).
        case virtualRow
        /// A ``CodeLineDecoration/gutterMarker`` on a buffer row (`CV-AP`): `lines` is that one row.
        case gutterMarker
    }

    /// The buffer lines the bar spans (0-based). For a virtual row, its anchor line as a one-line range.
    public var lines: Range<Int>
    /// The ``CodeLineDecoration/tag`` or ``CodeVirtualRow/tag`` of the bar; `nil` if it had none.
    public var tag: UInt64?
    /// Whether a line decoration's bar, a virtual row's bar or a line decoration's marker was hit.
    public var source: Source
    /// The display row that was hit (a buffer row's, or a virtual line's, in the view's row order).
    public var displayRow: Int
    /// The owner of the decoration, virtual row or marker that was hit (`CV-AO`); `nil` for the default owner. Output
    /// only: a hit is made by the view.
    public var owner: CodeDecorationOwner?

    /// A hit.
    public init(lines: Range<Int>, tag: UInt64?, source: Source, displayRow: Int, owner: CodeDecorationOwner? = nil) {
        self.lines = lines
        self.tag = tag
        self.source = source
        self.displayRow = displayRow
        self.owner = owner
    }
}
