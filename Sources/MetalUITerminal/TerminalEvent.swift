import Foundation

/// Something the emulator tells its owner besides the grid (frozen signature, `TRM-B`, `TRM-C`).
///
/// Every case is emitted from Phase 1.4 on (`TRM-AE`, `TRM-AF`).
public enum TerminalEvent: Sendable, Equatable {
    /// The window title (OSC 0/2), capped at 256 characters.
    case title(String)
    /// The working directory (OSC 7): a `file` URL whose host is empty, `localhost` or this machine's.
    case workingDirectory(URL)
    /// BEL.
    case bell
    /// An OSC 8 hyperlink; the id keys ``TerminalSnapshot/links``; raised once per new link.
    case hyperlink(id: UInt32, uri: String)
    /// Bytes the emulator MUST have written to the child: DA1/DA2, DSR/CPR and DECRQM answers and the OSC 10/11 colour query
    /// answers (only when the owner set the theme colours, `TRM-AF`). The owner
    /// writes them to the pty; a host that drops one stalls vim and less.
    case reply([UInt8])
}
