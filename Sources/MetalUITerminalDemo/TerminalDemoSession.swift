import Dispatch
import Foundation
import MetalUI
import MetalUITerminal
import MetalUITerminalUI
import Observation

/// The terminal demo's session (`TRM-BI`, record 379): a shell on a pseudo-terminal, an emulator and the snapshot source
/// between them, wired the way a host such as Alloy wires its own: the public `PseudoTerminal`, `TerminalEmulator` and
/// `TerminalSnapshotSource` only, so the headless smoke test runs the demo's real path. `package`: it is in no product.
///
/// ```swift
/// let session = try TerminalDemoSession()      // `$SHELL`, else /bin/sh (cmd.exe on Windows)
/// TerminalView(snapshotSource: session.source, theme: .xterm, accessibilityLabel: session.title,
///              onInput: session.send, onResize: session.resize, onLink: { _ in nil })
/// ```
@MainActor @Observable
package final class TerminalDemoSession {
    /// The program's title (OSC 0/2), else the shell's name: the window's title and the terminal's accessibility label.
    package private(set) var title: String
    /// The pty's child has ended and its output is drained.
    package private(set) var finished = false

    @ObservationIgnored package let source: TerminalSnapshotSource
    @ObservationIgnored package let pty: PseudoTerminal
    @ObservationIgnored private let queue = DispatchQueue(label: "MetalUITerminalDemo.emulator")

    /// The shell to run: `$SHELL` when it is set and executable, else /bin/sh; `cmd.exe` on Windows.
    package static func defaultShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        #if os(Windows)
        return environment["COMSPEC"] ?? "cmd.exe"
        #else
        if let shell = environment["SHELL"], !shell.isEmpty, FileManager.default.isExecutableFile(atPath: shell) { return shell }
        return "/bin/sh"
        #endif
    }

    /// Starts `shell` on a pty of `size` in `directory`.
    package init(shell: String = TerminalDemoSession.defaultShell(), size: TerminalSize = TerminalSize(cols: 80, rows: 24),
                 directory: String = NSHomeDirectory()) throws {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        let pty = try PseudoTerminal.spawn(executable: shell, argv: [shell], env: environment, cwd: directory, size: size)
        let emulator = TerminalEmulator(cols: size.cols, rows: size.rows)
        let source = TerminalSnapshotSource(emulator: emulator, queue: queue)
        self.pty = pty
        self.source = source
        self.title = (shell as NSString).lastPathComponent
        let name = title
        source.onReply = { [pty] bytes in pty.write(bytes) }   // DA, DSR and colour answers: vim and less wait for them
        source.onEvents = { [weak self] events in
            for case .title(let text) in events { self?.title = text.isEmpty ? name : text }
        }
        pty.onReadable(queue: queue) { [pty, source, weak self] in
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { pty.read(into: $0) }
                if count > 0 {
                    buffer.withUnsafeBytes { source.feed(UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
                } else {
                    if count < 0 {
                        let note = Array("\r\n[process ended]\r\n".utf8)
                        note.withUnsafeBytes { source.feed($0) }
                        DispatchQueue.main.async { MainActor.assumeIsolated { self?.finished = true } }
                    }
                    return
                }
            }
        }
    }

    /// Keys, text and paste, from the view.
    package func send(_ bytes: [UInt8]) { pty.write(bytes) }

    /// The view's grid size changed: the child's window size follows.
    package func resize(_ size: TerminalSize) { pty.resize(cols: size.cols, rows: size.rows) }

    /// Ends the child and closes the pty.
    package func close() {
        pty.signalGroup(.hangup)
        pty.close()
    }

    /// Every row the emulator holds, scrollback first, trailing blanks trimmed, read on its queue (tests).
    package func allRows() async -> [String] {
        await withCheckedContinuation { continuation in
            source.perform { emulator in
                var rows: [String] = []
                var row = emulator.firstRow
                while let text = emulator.rowText(row) { rows.append(text); row += 1 }
                continuation.resume(returning: rows)
            }
        }
    }
}

/// The demo window's content: the terminal filling it, the window titled by the program's title.
@MainActor
package func terminalDemoContent(_ session: TerminalDemoSession) -> some Element {
    VStack(spacing: 0) {
        TerminalView(snapshotSource: session.source, theme: .xterm, accessibilityLabel: session.title,
                     onInput: { session.send($0) }, onResize: { session.resize($0) }, onLink: { _ in nil })
            .font(.system(size: 13, design: .monospaced))
    }
    .navigationTitle("MetalUI — \(session.title)")
}
