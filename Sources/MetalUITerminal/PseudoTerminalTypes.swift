extension PseudoTerminal {
    /// A signal ``signalGroup(_:)`` can send.
    ///
    /// Windows has no signals: `.interrupt` writes `0x03` to the console input and the others terminate the
    /// child's job (ruling `TRM-E`).
    public enum Signal: Sendable {
        /// `SIGHUP`.
        case hangup
        /// `SIGINT`.
        case interrupt
        /// `SIGTERM`.
        case terminate
        /// `SIGKILL`.
        case kill
    }

    /// How the child ended.
    public enum ExitStatus: Sendable, Equatable {
        /// It called `exit` with this status (on Windows, its exit code reinterpreted as an `Int32`).
        case exited(Int32)
        /// A signal with this number killed it (never produced on Windows).
        case signaled(Int32)
    }
}

/// Why a pty could not be started.
public enum PseudoTerminalError: Error, Sendable, Equatable {
    /// Opening the pty failed (`errno` in `code`; on Windows the `GetLastError` or `HRESULT` of the pipe or pseudo console).
    case openFailed(code: Int32)
    /// Starting the child failed (`errno` in `code`; `ENOENT` for a missing executable; on Windows `GetLastError`).
    case spawnFailed(code: Int32)
    /// The platform cannot do it.
    case unsupported(String)
}
