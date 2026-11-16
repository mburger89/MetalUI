/// A terminal grid's size in character cells.
///
/// Frozen by `TRM-B`; the emulator branch declares the same type, so this file
/// is the one both branches share.
public struct TerminalSize: Hashable, Sendable {
    /// The number of columns, at least 2.
    public var cols: Int
    /// The number of rows, at least 1.
    public var rows: Int

    /// Creates a size, clamping to at least 2 x 1.
    public init(cols: Int, rows: Int) {
        self.cols = max(cols, 2)
        self.rows = max(rows, 1)
    }
}
