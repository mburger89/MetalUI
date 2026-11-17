import Foundation

/// Something the emulator tells its owner besides the grid (frozen signature, `TRM-B`, `TRM-C`).
///
/// Phase 1.3 emits `.reply` and `.bell`; `.title`, `.workingDirectory` and `.hyperlink` are declared so the
/// type is the frozen one and are emitted from Phase 1.4 (OSC) on.
public enum TerminalEvent: Sendable, Equatable {
    /// The window title (OSC 0/2), capped at 256 characters. Not emitted before Phase 1.4.
    case title(String)
    /// The working directory (OSC 7). Not emitted before Phase 1.4.
    case workingDirectory(URL)
    /// BEL.
    case bell
    /// An OSC 8 hyperlink; the id keys ``TerminalSnapshot/links``. Not emitted before Phase 1.4.
    case hyperlink(id: UInt32, uri: String)
    /// Bytes the emulator MUST have written to the child: DA1/DA2, DSR/CPR and DECRQM answers. The owner
    /// writes them to the pty; a host that drops one stalls vim and less.
    case reply([UInt8])
}
