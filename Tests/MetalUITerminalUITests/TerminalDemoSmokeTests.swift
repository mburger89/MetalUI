#if !os(Windows)
import Foundation
import MetalUITerminal
import Testing
@testable import MetalUITerminalDemo

// The terminal demo's real path, headless (`TRM-BI`): a shell on a pty, the emulator and the snapshot source wired by
// `TerminalDemoSession`, the same object `METALUI_TERMINAL_DEMO=1 swift run MetalUIDemo` builds. Waits are bounded and
// poll; the shell is closed before each test returns.

/// Polls `condition` for at most `seconds`.
@MainActor private func eventually(_ seconds: Double = 8, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await condition()
}

/// **1** A command typed into the shell comes back through the pty, the emulator and the source: the computed result
/// (`smoke-42`, never in the typed text) is on a row. Mutation: the read handler drops its feed (no row ever has it).
@MainActor @Test func theDemoShellEchoesACommandThroughTheEmulator() async throws {
    let session = try TerminalDemoSession(shell: "/bin/sh", directory: NSTemporaryDirectory())
    defer { session.close() }
    session.send(Array("echo smoke-$((40+2))\n".utf8))
    let seen = await eventually { await session.allRows().contains { $0 == "smoke-42" } }
    let rows = await session.allRows().filter { !$0.isEmpty }
    #expect(seen, "rows: \(rows)")
}

/// **2** The program's title (OSC 2) becomes the session's title, which the demo shows as the window title and passes as
/// the terminal's accessibility label. Mutation: the title event is ignored (the shell's name stays).
@MainActor @Test func theProgramsTitleBecomesTheSessionsTitle() async throws {
    let session = try TerminalDemoSession(shell: "/bin/sh", directory: NSTemporaryDirectory())
    defer { session.close() }
    #expect(session.title == "sh")
    session.send(Array("printf '\\033]2;demo title\\007'\n".utf8))
    let seen = await eventually { session.title == "demo title" }
    #expect(seen, "title \(session.title)")
}

/// **3** A resize reaches the child: `stty size` reports the pty's new rows and columns. Mutation: `resize` does nothing.
@MainActor @Test func aResizeReachesTheChild() async throws {
    let session = try TerminalDemoSession(shell: "/bin/sh", size: TerminalSize(cols: 80, rows: 24), directory: NSTemporaryDirectory())
    defer { session.close() }
    session.resize(TerminalSize(cols: 100, rows: 30))
    session.send(Array("stty size\n".utf8))
    let seen = await eventually { await session.allRows().contains { $0 == "30 100" } }
    let rows = await session.allRows().filter { !$0.isEmpty }
    #expect(seen, "rows: \(rows)")
}

/// **4** The default shell is `$SHELL` when it is executable, else /bin/sh. Mutation: ignore the environment.
@MainActor @Test func theDefaultShellIsTheEnvironmentsElseBinSh() {
    #expect(TerminalDemoSession.defaultShell(environment: ["SHELL": "/bin/sh"]) == "/bin/sh")
    #expect(TerminalDemoSession.defaultShell(environment: ["SHELL": "/bin/zsh"]) == (FileManager.default.isExecutableFile(atPath: "/bin/zsh") ? "/bin/zsh" : "/bin/sh"))
    #expect(TerminalDemoSession.defaultShell(environment: ["SHELL": "/nonexistent/shell"]) == "/bin/sh")
    #expect(TerminalDemoSession.defaultShell(environment: [:]) == "/bin/sh")
}
#endif
