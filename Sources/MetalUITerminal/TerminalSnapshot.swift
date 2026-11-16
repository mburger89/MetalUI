/// One damaged viewport row of a snapshot.
public struct TerminalDamagedRow: Sendable {
    /// The viewport row.
    public let index: Int
    /// The row's content; an undamaged row would share storage with the previous snapshot's.
    public let row: TerminalRow
}

/// What changed in the viewport since the previous publish, and the state needed to draw it.
public struct TerminalSnapshot: Sendable {
    /// Strictly increases on every publish that changes anything.
    public let version: UInt64
    /// The grid size.
    public let size: TerminalSize
    /// How far the viewport is scrolled back from the live bottom; 0 is live.
    public let viewportOffset: Int
    /// The rows that changed since the previous publish, by viewport index.
    public let damagedRows: [TerminalDamagedRow]
    /// True when every row is listed: the first publish, and after resize, reflow, an alternate-screen switch
    /// and a viewport scroll.
    public let isFullFrame: Bool
    /// The cursor, in viewport coordinates.
    public let cursor: TerminalCursor
    /// The modes in force.
    public let modes: TerminalModes
    /// The selection, if any.
    public let selection: TerminalSelection?
    /// The hyperlink targets by id (``TerminalAttributes/hyperlink``).
    public let links: [UInt32: String]
}
