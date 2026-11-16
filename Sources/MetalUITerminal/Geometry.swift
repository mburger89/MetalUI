/// The size of a terminal grid in cells.
///
/// The initializer clamps to at least 2 columns by 1 row (`TRM-B`), so a size is always a grid the emulator can
/// lay a wide character on.
public struct TerminalSize: Hashable, Sendable {
    /// The number of columns, at least 2.
    public var cols: Int
    /// The number of rows, at least 1.
    public var rows: Int

    /// Creates a size, clamping to at least 2 columns by 1 row.
    public init(cols: Int, rows: Int) {
        self.cols = max(2, cols)
        self.rows = max(1, rows)
    }
}

/// A cell position in absolute rows.
///
/// `row` counts lines since the start of the session and is stable across scrolling; rows below
/// ``TerminalEmulator/firstRow`` have been evicted from scrollback.
public struct TerminalPosition: Hashable, Comparable, Sendable {
    /// The absolute line number since the start.
    public var row: Int
    /// The column, from 0.
    public var col: Int

    /// Creates a position.
    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    /// Orders by row, then column.
    public static func < (lhs: TerminalPosition, rhs: TerminalPosition) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.col < rhs.col
    }
}

/// A span between two positions in absolute rows.
public struct TerminalRange: Hashable, Sendable {
    /// The first position of the range.
    public var lowerBound: TerminalPosition
    /// The last position of the range.
    public var upperBound: TerminalPosition

    /// Creates a range from its two ends.
    public init(lowerBound: TerminalPosition, upperBound: TerminalPosition) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

/// A selection over absolute rows: reading order (`linear`) or a rectangle (`block`).
public enum TerminalSelection: Hashable, Sendable {
    /// A selection that runs through the rows between its ends.
    case linear(TerminalRange)
    /// A rectangular selection between its ends' corners.
    case block(TerminalRange)
}
