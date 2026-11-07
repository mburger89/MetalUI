/// A reader of a buffer's edit stream. Each `drain()` returns the events since the previous one (or since
/// the cursor was made), so a consumer that wakes on `CodeBuffer.version` collects exactly what it missed.
/// The buffer holds cursors weakly and keeps its log back to the slowest live one, up to a byte cap
/// (`CV-E`); a cursor that falls past the cap gets a snapshot instead.
@MainActor
public final class CodeEditCursor {
    private weak var buffer: CodeBuffer?
    /// The version up to which this cursor has drained.
    public private(set) var version: UInt64

    init(buffer: CodeBuffer, version: UInt64) {
        self.buffer = buffer
        self.version = version
    }

    func setVersion(_ v: UInt64) { version = v }

    /// The events since the last drain, oldest first, or `.resync` with a snapshot when the log no longer
    /// reaches back that far. Afterwards the cursor is at the buffer's current version.
    public func drain() -> CodeEditBatch {
        guard let buffer else { return .edits([]) }
        return buffer.drain(self)
    }
}
