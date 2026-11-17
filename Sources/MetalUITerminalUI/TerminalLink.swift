import MetalUITerminal

/// What the view asks the host about the cell under the pointer while ⌘ is held (`TRM-BA`; Phase 5.5 wires it, so
/// the type is frozen now and the view sends nothing yet).
public struct TerminalLinkQuery: Sendable, Equatable {
    /// The pointer's phase over a link.
    public enum Phase: Sendable, Equatable {
        /// The pointer moved onto another cell with ⌘ held: answer a target to underline and show a pointing hand.
        case hover
        /// The pointer left the cell, ⌘ was released or the view lost the pointer.
        case exit
        /// ⌘-click: open the target.
        case activate
    }

    /// The cell, in absolute rows.
    public var cell: TerminalPosition
    /// The text of the cell's row, trailing blanks trimmed, so the host can scan for a URL or path.
    public var rowText: String
    /// What happened.
    public var phase: Phase

    /// A query.
    public init(cell: TerminalPosition, rowText: String, phase: Phase) {
        self.cell = cell
        self.rowText = rowText
        self.phase = phase
    }
}

/// A link the host found in a row (`TRM-BA`).
public struct TerminalLinkTarget: Sendable, Equatable {
    /// The columns of the link on the queried row.
    public var columns: Range<Int>
    /// What the host wants back on activation (a URL, a path with a line).
    public var payload: String

    /// A target.
    public init(columns: Range<Int>, payload: String) {
        self.columns = columns
        self.payload = payload
    }
}
