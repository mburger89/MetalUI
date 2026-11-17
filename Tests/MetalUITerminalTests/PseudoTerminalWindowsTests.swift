#if os(Windows)
import Dispatch
import Foundation
import Testing
import WinSDK
@testable import MetalUITerminal

// Spec section 8 and ruling TRM-AX: ConPTY. conhost re-renders what the child draws, so output is judged on the
// EMULATED screen (fed through TerminalEmulator), never on raw bytes. Every wait is bounded; none sleeps for
// timing. Run with `--no-parallel`.

private let environment = ProcessInfo.processInfo.environment
private let comSpec = environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
private let tempDirectory = NSTemporaryDirectory()
// winbase.h constants, spelled out because the complex ones do not import.
private let waitObject0: DWORD = 0
private let waitTimeout: DWORD = 0x102
private let synchronize: DWORD = 0x0010_0000
private let processTerminate: DWORD = 0x0001

private func cmd(_ args: [String], cols: Int = 80, rows: Int = 24, cwd: String = "C:\\",
                 env: [String: String] = environment) throws -> PseudoTerminal {
    try PseudoTerminal.spawn(executable: comSpec, argv: ["cmd.exe", "/c"] + args, env: env, cwd: cwd,
                             size: TerminalSize(cols: cols, rows: rows))
}

private func powershell(_ command: String, cols: Int = 80, rows: Int = 24) throws -> PseudoTerminal {
    // A bare name: the engine searches PATH for powershell.exe.
    try PseudoTerminal.spawn(executable: "powershell", argv: ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
                             env: environment, cwd: "C:\\", size: TerminalSize(cols: cols, rows: rows))
}

/// What a terminal showing `bytes` would show: every row of a generous screen, joined.
private func screenText(_ bytes: [UInt8], cols: Int = 240, rows: Int = 60) -> String {
    let emulator = TerminalEmulator(cols: cols, rows: rows)
    bytes.withUnsafeBytes { emulator.feed($0) }
    return (0..<rows).compactMap { emulator.rowText($0) }.joined(separator: "\n")
}

extension Capture {
    func screenContains(_ needle: String, timeout: TimeInterval = 30) -> Bool {
        let found = wait(timeout: timeout) { text, _, _ in screenText(Array(text.utf8)).contains(needle) }
        if !found {
            // Say what arrived, so a failure tells "nothing came" from "something came that does not show".
            Issue.record("waiting for \"\(needle)\": \(describe)")
        }
        return found
    }
    var screen: String { screenText(Array(text.utf8)) }

    /// How many bytes arrived, the first 200 characters of the screen they draw and the first 200 raw bytes.
    var describe: String {
        let blanks = CharacterSet.whitespacesAndNewlines
        let drawn = String(screen.trimmingCharacters(in: blanks).prefix(200))
        let raw = String(data.prefix(200).map { $0 < 0x20 || $0 > 0x7e ? String(format: "\\x%02x", $0) : String(UnicodeScalar($0)) }.joined().prefix(400))
        return "\(count) bytes received, ended=\(hitEnd); screen starts: \(drawn.debugDescription); raw starts: \(raw)"
    }
}

/// True once the process `pid` has ended (or never could be opened), within `timeout` seconds.
private func processEnds(_ pid: UInt32, timeout: Double) -> Bool {
    guard let handle = OpenProcess(synchronize, false, pid) else { return true }
    defer { CloseHandle(handle) }
    return WaitForSingleObject(handle, DWORD(timeout * 1000)) == waitObject0
}

private func processIsAlive(_ pid: UInt32) -> Bool {
    guard let handle = OpenProcess(synchronize, false, pid) else { return false }
    defer { CloseHandle(handle) }
    return WaitForSingleObject(handle, 0) == waitTimeout
}

@Suite(.serialized) struct PseudoTerminalWindowsTests {
    // MARK: The child's world

    @Test func cmdEchoShowsOnTheScreenAndEndsTheStream() async throws {
        let pty = try cmd(["echo", "hi-from-cmd"])
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.screenContains("hi-from-cmd"))
        #expect(out.waitForEnd(), "the stream never ended after the child did")
        #expect(await exitStatus(of: pty) == .exited(0))
    }

    @Test func powershellOutputShowsOnTheScreen() throws {
        let pty = try powershell("Write-Output ('marker-' + (6*7))")
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.screenContains("marker-42"))
    }

    @Test func theEnvironmentIsExactlyTheOneGivenAndCwdIsHonoured() throws {
        var env = environment
        env["METALUI_PTY_MARK"] = "mark Ünï 42"
        let pty = try cmd(["echo", "%METALUI_PTY_MARK%", "&", "cd"], cols: 200, cwd: tempDirectory, env: env)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.screenContains("mark Ünï 42"))
        let leaf = URL(fileURLWithPath: tempDirectory).lastPathComponent
        #expect(out.screenContains(leaf))
    }

    @Test func aMissingExecutableIsASpawnFailure() {
        // The directory is missing too, which Windows reports as ERROR_PATH_NOT_FOUND (3); a missing file in an
        // existing directory is ERROR_FILE_NOT_FOUND (2).
        #expect(throws: PseudoTerminalError.spawnFailed(code: 3)) {
            try PseudoTerminal.spawn(executable: "C:\\nonexistent\\program.exe", argv: ["x"], env: environment, cwd: "C:\\",
                                     size: TerminalSize(cols: 80, rows: 24))
        }
        #expect(throws: PseudoTerminalError.spawnFailed(code: 2)) {
            try PseudoTerminal.spawn(executable: "C:\\Windows\\no-such-program.exe", argv: ["x"], env: environment, cwd: "C:\\",
                                     size: TerminalSize(cols: 80, rows: 24))
        }
    }

    @Test func aMissingWorkingDirectoryIsASpawnFailure() {
        #expect(throws: PseudoTerminalError.spawnFailed(code: 267)) {
            try PseudoTerminal.spawn(executable: comSpec, argv: ["cmd.exe", "/c", "exit"], env: environment,
                                     cwd: "C:\\nonexistent\\dir", size: TerminalSize(cols: 80, rows: 24))
        }
    }

    // MARK: Size

    @Test func theChildSeesTheInitialSizeAndFollowsAResize() throws {
        let script = "'W1=' + $Host.UI.RawUI.WindowSize.Width; 'H1=' + $Host.UI.RawUI.WindowSize.Height; "
            + "[void][Console]::ReadLine(); 'W2=' + $Host.UI.RawUI.WindowSize.Width; 'H2=' + $Host.UI.RawUI.WindowSize.Height"
        let pty = try powershell(script, cols: 97, rows: 21)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.screenContains("H1=21"))
        #expect(out.screen.contains("W1=97"))
        pty.resize(cols: 133, rows: 33)
        pty.write(Array("\r".utf8))
        #expect(out.screenContains("H2=33"))
        #expect(out.screen.contains("W2=133"))
    }

    // MARK: Endings

    @Test func exitSevenIsExitedSeven() async throws {
        let pty = try cmd(["exit", "7"])
        defer { finish(pty) }
        #expect(await exitStatus(of: pty) == .exited(7))
        #expect(await exitStatus(of: pty) == .exited(7))   // the same value again
    }

    @Test func signalGroupTerminateAndKillEndTheJob() async throws {
        for signal in [PseudoTerminal.Signal.terminate, .kill, .hangup] {
            let pty = try powershell("Start-Sleep 300")
            defer { finish(pty) }
            _ = Capture(pty)
            pty.signalGroup(signal)
            #expect(await exitStatus(of: pty) == .exited(1), "\(signal)")
        }
    }

    @Test func killingTheJobKillsAGrandchildToo() async throws {
        // A process the shell started detached: ending the shell alone would leave it running.
        let pty = try powershell("$p = Start-Process -PassThru -NoNewWindow ping.exe -ArgumentList '-n','300','127.0.0.1'; "
                                 + "'grandchild=' + $p.Id; Start-Sleep 300")
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.screenContains("grandchild="))
        let digits = out.screen.components(separatedBy: "grandchild=").dropFirst().first?.prefix { $0.isNumber }
        let grandchild = try #require(digits.flatMap { UInt32($0) }, "no pid in \(out.screen)")
        defer {
            if let h = OpenProcess(processTerminate, false, grandchild) { TerminateProcess(h, 1); CloseHandle(h) }
        }
        #expect(processIsAlive(grandchild))
        pty.signalGroup(.kill)
        #expect(await exitStatus(of: pty) == .exited(1))
        #expect(processEnds(grandchild, timeout: 20), "the grandchild survived the job kill")
    }

    @Test func closingTheJobAlsoKillsAGrandchild() async throws {
        // Kill-on-close is what stops a pty that is only closed (or dropped) leaving processes behind.
        let pty = try powershell("$p = Start-Process -PassThru -NoNewWindow ping.exe -ArgumentList '-n','300','127.0.0.1'; "
                                 + "'grandchild=' + $p.Id; Start-Sleep 300")
        let out = Capture(pty)
        #expect(out.screenContains("grandchild="))
        let digits = out.screen.components(separatedBy: "grandchild=").dropFirst().first?.prefix { $0.isNumber }
        let grandchild = try #require(digits.flatMap { UInt32($0) })
        defer {
            if let h = OpenProcess(processTerminate, false, grandchild) { TerminateProcess(h, 1); CloseHandle(h) }
        }
        pty.close()
        #expect(pty.waitUntilReleased(timeout: 90))
        #expect(processEnds(grandchild, timeout: 20), "the grandchild survived close()")
    }

    @Test func signalGroupIsANoOpAfterTheExit() async throws {
        let pty = try cmd(["exit", "0"])
        defer { finish(pty) }
        #expect(await exitStatus(of: pty) == .exited(0))
        pty.signalGroup(.kill)
        pty.signalGroup(.interrupt)
        #expect(await exitStatus(of: pty) == .exited(0))
    }

    @Test func interruptWritesControlCToTheConsole() async throws {
        // cmd.exe /c ping: Ctrl+C ends ping and cmd with STATUS_CONTROL_C_EXIT, which a job kill (1) never gives.
        let pty = try cmd(["ping", "-n", "300", "127.0.0.1"])
        defer { finish(pty) }
        let out = Capture(pty)
        // Not before ping is running and has answered: Ctrl+C sent while cmd is still starting is lost.
        #expect(out.screenContains("Reply from"))
        let before = out.count
        pty.signalGroup(.interrupt)
        let status = await exitStatus(of: pty, timeout: 15)
        #expect(status == .exited(Int32(bitPattern: 0xC000013A)),
                "after the interrupt: status \(String(describing: status)), alive=\(processIsAlive(UInt32(pty.processID))), \(out.count - before) more bytes; \(out.describe); tail raw: \(out.data.suffix(300).map { String(format: "%02x", $0) }.joined(separator: " "))")
    }

    @Test func thereIsNoForegroundGroup() throws {
        let pty = try cmd(["echo", "x"])
        defer { finish(pty) }
        #expect(pty.foregroundProcessGroup() == nil)
        #expect(pty.processID > 0)
    }

    // MARK: Writing

    @Test func bytesWrittenReachTheChildInOrder() throws {
        let pty = try powershell("$a = [Console]::ReadLine(); $b = [Console]::ReadLine(); 'got=' + $a + '+' + $b")
        defer { finish(pty) }
        let out = Capture(pty)
        pty.write(Array("first\r".utf8))
        pty.write(Array("second\r".utf8))
        #expect(out.screenContains("got=first+second"))
    }

    @Test func aMegabyteWrittenToAChildThatDoesNotReadDoesNotBlockTheCaller() throws {
        let pty = try powershell("'ready'; Start-Sleep 300")
        defer { finish(pty) }
        #expect(Capture(pty).screenContains("ready"))
        let payload = [UInt8](repeating: UInt8(ascii: "x"), count: 1 << 20)
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            pty.write(payload)
            returned.signal()
        }
        #expect(returned.wait(timeout: .now() + 20) == .success, "write blocked")
    }

    // MARK: Close

    @Test func noCallbackRunsAfterCloseEvenDuringOutput() async throws {
        let pty = try cmd(["for", "/l", "%i", "in", "(1,1,100000000)", "do", "@echo", "flood-line-%i"])
        defer { finish(pty) }
        let out = Capture(pty, keep: false)
        #expect(out.wait { _, count, _ in count > 1 << 16 }, "\(out.describe)")
        // Closing on the reader's own queue makes "after" exact: every handler run that follows is a late one.
        let before = out.queue.sync { () -> Int in
            pty.close()
            return out.callbacks
        }
        #expect(pty.waitUntilReleased(timeout: 90), "teardown never finished: ClosePseudoConsole deadlocked?")
        #expect(await exitStatus(of: pty) != nil)
        out.queue.sync {}
        out.queue.sync {}
        #expect(out.callbacks == before, "\(out.callbacks - before) callbacks after close")
    }

    @Test func closingWhileNobodyReadsTheOutputDoesNotDeadlock() async throws {
        // No reader is installed, so the buffer fills, reading pauses and conhost blocks writing the pipe:
        // exactly where a plain ClosePseudoConsole would hang. close() drains and discards instead.
        let pty = try cmd(["for", "/l", "%i", "in", "(1,1,100000000)", "do", "@echo", "unread-line-%i"])
        // Let the flood fill the buffer: the output of a child that is never read cannot be waited for, so
        // observe it through the pause: read until the first bytes exist, then stop reading.
        let out = Capture(pty, keep: false)
        #expect(out.wait { _, count, _ in count > 1 << 20 }, "\(out.describe)")
        pty.onReadable(queue: DispatchQueue(label: "ignored")) {}   // replaced handler never reads
        pty.close()
        #expect(pty.waitUntilReleased(timeout: 90), "ClosePseudoConsole deadlocked")
        #expect(await exitStatus(of: pty) != nil)
    }

    @Test func closeIsIdempotentAndLaterCallsAreHarmless() async throws {
        let pty = try powershell("Start-Sleep 300")
        pty.close()
        pty.close()
        pty.write([1, 2, 3])
        pty.resize(cols: 10, rows: 10)
        pty.signalGroup(.interrupt)
        #expect(pty.foregroundProcessGroup() == nil)
        var byte: UInt8 = 0
        #expect(withUnsafeMutableBytes(of: &byte) { pty.read(into: $0) } == -1)
        pty.signalGroup(.kill)
        #expect(await exitStatus(of: pty) != nil)
        #expect(pty.waitUntilReleased(timeout: 90))
    }
}

// MARK: Quoting, round-tripped through the OS

@Suite struct WindowsQuotingRoundTripTests {
    @Test(arguments: [
        ["plain"], ["a b"], ["say \"hi\""], ["C:\\Program Files\\x\\"], ["a\\\"b"], ["tab\tx"], ["\\\\server\\share x"],
        ["a\\\\\"b c"], [""], ["x", "", "y"], ["trailing\\"], ["\"\""], ["multi word", "and \"quoted\"", "back\\slash\\"],
    ])
    func commandLineToArgvWReadsBackWhatWasQuoted(_ arguments: [String]) throws {
        let line = WindowsCommandLine.commandLine(argv: ["program.exe"] + arguments)
        var count: Int32 = 0
        let wide = Array(line.utf16) + [0]
        let argv = try #require(wide.withUnsafeBufferPointer { CommandLineToArgvW($0.baseAddress, &count) })
        defer { LocalFree(argv) }
        let parsed = (1..<Int(count)).map { String(decodingCString: argv[$0]!, as: UTF16.self) }
        #expect(parsed == arguments, "\(line)")
    }
}

// MARK: The resolver against real files

@Suite struct DefaultShellOnDiskTests {
    @Test func theResolverFollowsAFakePathOnDisk() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("metalui-shell-\(UUID().uuidString)")
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "\(a.path.replacingOccurrences(of: "/", with: "\\"));\(b.path.replacingOccurrences(of: "/", with: "\\"))"
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

        #expect(DefaultShell.windows(path: path, comSpec: comSpec, exists: exists) == comSpec)
        FileManager.default.createFile(atPath: a.appendingPathComponent("powershell.exe").path, contents: Data())
        #expect(DefaultShell.windows(path: path, comSpec: comSpec, exists: exists)?.hasSuffix("a\\powershell.exe") == true)
        FileManager.default.createFile(atPath: b.appendingPathComponent("pwsh.exe").path, contents: Data())
        #expect(DefaultShell.windows(path: path, comSpec: comSpec, exists: exists)?.hasSuffix("b\\pwsh.exe") == true)
    }
}
#endif
