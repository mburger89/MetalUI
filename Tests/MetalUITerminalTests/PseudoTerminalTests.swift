#if !os(Windows)
import Dispatch
import Foundation
import Testing
@testable import MetalUITerminal

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Spec section 8 (rulings TRM-K..TRM-O). Every wait is bounded and none sleeps for timing; every behaviour runs
// under both spawn mechanisms. Run with `--no-parallel`.

/// True when `pid` no longer exists or is a zombie (dead, only unreaped). `kill(pid, 0)` alone cannot tell a zombie
/// from a live process, and an unreaped zombie is what a killed orphan is when PID 1 never waits (a container).
private func processIsDead(_ pid: pid_t) -> Bool {
    if kill(pid, 0) != 0 { return true }
    #if os(Linux)
    // `/proc/<pid>/stat` is `pid (comm) S ...`; comm may hold spaces and parentheses, so read the state after the last `)`.
    guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8) else { return true }
    guard let close = stat.lastIndex(of: ")") else { return false }
    return stat[stat.index(after: close)...].first(where: { $0 != " " }) == "Z"
    #else
    return false
    #endif
}

@Suite(.serialized) struct PseudoTerminalTests {
    // MARK: The child's world

    @Test(arguments: mechanisms) func ttyNamesAPty(_ mechanism: PseudoTerminal.Mechanism) throws {
        let pty = try shell("tty", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitForEnd())
        let name = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(name.hasPrefix("/dev/ttys") || name.hasPrefix("/dev/pts/"), "tty printed \(name)")
    }

    @Test(arguments: mechanisms) func theChildLeadsASessionWhoseControllingTerminalIsThePty(_ mechanism: PseudoTerminal.Mechanism) throws {
        // `/dev/tty` opens only with a controlling terminal; `stty` reads it through fd 0.
        let pty = try shell("echo hold > /dev/tty && echo ctty-ok; read x", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("ctty-ok"))
        #expect(getsid(pty.processID) == pty.processID)
        #expect(getpgid(pty.processID) == pty.processID)
        // tcgetpgrp on the master answers for the controlling terminal's foreground group: the leader's.
        #expect(pty.foregroundProcessGroup() == pty.processID)
    }

    @Test func automaticUsesPosixSpawnAndThatGivesAControllingTerminal() throws {
        let pty = try shell("echo hold > /dev/tty && echo ctty-ok; read x")
        defer { finish(pty) }
        #expect(pty.mechanismUsed == .posixSpawn)
        #expect(Capture(pty).waitFor("ctty-ok"))
    }

    @Test(arguments: mechanisms) func onlyDescriptorsZeroToTwoReachTheChild(_ mechanism: PseudoTerminal.Mechanism) throws {
        // A descriptor the parent leaves open without close-on-exec must not leak.
        let base = open("/dev/null", O_RDONLY)
        let leaks = [12, 30, 31].map { fcntl(base, F_DUPFD, $0) }
        defer { leaks.forEach { close($0) }; close(base) }
        #expect(leaks.allSatisfy { $0 > 10 && $0 < 60 }, "\(leaks)")  // inside the probed range, above the shell's own fd 10
        // fd 10 is the shell's own (the probe `(: <&10)` finds it under a plain `sh -c` too).
        var script = "for i in 0 1 2; do (: <&$i) 2>/dev/null || echo closed$i; done;"
        script += " for i in $(seq 3 60); do [ $i = 10 ] && continue; (: <&$i) 2>/dev/null && echo leak$i; done; echo done"
        let pty = try shell(script, mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("done"))
        #expect(!out.text.contains("leak"), "\(out.text)")
        #expect(!out.text.contains("closed"), "\(out.text)")
    }

    @Test(arguments: mechanisms) func theEnvironmentIsExactlyTheOneGivenAndCwdIsHonoured(_ mechanism: PseudoTerminal.Mechanism) throws {
        let pty = try shell("/usr/bin/env; pwd; echo end", cwd: "/usr", env: ["ONLY": "this one", "TERM": "dumb"],
                            mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("end"))
        let lines = out.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        // The shell adds PWD (and OLDPWD, _) itself; nothing else may appear.
        let variables = lines.filter { $0.contains("=") }.filter { !$0.hasPrefix("PWD=") && !$0.hasPrefix("OLDPWD=") && !$0.hasPrefix("_=") && !$0.hasPrefix("SHLVL=") }
        #expect(variables.sorted() == ["ONLY=this one", "TERM=dumb"], "\(variables)")
        #expect(lines.contains("/usr"))
    }

    @Test(arguments: mechanisms) func aMissingExecutableIsASpawnFailure(_ mechanism: PseudoTerminal.Mechanism) {
        #expect(throws: PseudoTerminalError.spawnFailed(code: ENOENT)) {
            try PseudoTerminal.spawn(executable: "/nonexistent/program", argv: ["x"], env: [:], cwd: "/",
                                     size: TerminalSize(cols: 80, rows: 24), mechanism: mechanism)
        }
    }

    @Test(arguments: mechanisms) func aMissingWorkingDirectoryIsASpawnFailure(_ mechanism: PseudoTerminal.Mechanism) {
        #expect(throws: PseudoTerminalError.spawnFailed(code: ENOENT)) {
            try PseudoTerminal.spawn(executable: "/bin/sh", argv: ["sh", "-c", "true"], env: [:], cwd: "/nonexistent/dir",
                                     size: TerminalSize(cols: 80, rows: 24), mechanism: mechanism)
        }
    }

    // MARK: Size

    @Test(arguments: mechanisms) func theChildSeesTheInitialSizeAndFollowsAResize(_ mechanism: PseudoTerminal.Mechanism) throws {
        let pty = try shell("stty size; read x; stty size; echo end", cols: 91, rows: 17, mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("17 91"))
        pty.resize(cols: 123, rows: 45)
        pty.write(Array("\n".utf8))
        #expect(out.waitFor("45 123"))
    }

    // MARK: Endings

    @Test(arguments: mechanisms) func exitSevenIsExitedSeven(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("exit 7", mechanism: mechanism)
        defer { finish(pty) }
        #expect(await exitStatus(of: pty) == .exited(7))
        #expect(await exitStatus(of: pty) == .exited(7))  // the same value again: reaped exactly once
    }

    @Test(arguments: mechanisms) func killingTheShellIsSignaled(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("kill -9 $$", mechanism: mechanism)
        defer { finish(pty) }
        #expect(await exitStatus(of: pty) == .signaled(9))
    }

    @Test(arguments: mechanisms) func signalGroupKillsAGrandchildToo(_ mechanism: PseudoTerminal.Mechanism) async throws {
        // The grandchild ignores SIGHUP (inherited from the shell's trap) and the leader's exit revokes the tty
        // under it without killing it, so only a signal to the whole group can: neither the hangup nor end of
        // file proves anything here.
        let pty = try shell("trap '' HUP; sleep 300 & echo grandchild=$!; wait", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.wait { text, _, _ in text.contains(where: \.isNewline) && text.contains("grandchild=") })
        let digits = out.text.drop { $0 != "=" }.dropFirst().prefix { $0.isNumber }
        let grandchild = try #require(Int32(digits), "no pid in \(out.text)")
        defer { kill(grandchild, SIGKILL) }
        #expect(kill(grandchild, 0) == 0)
        pty.signalGroup(.kill)
        #expect(await exitStatus(of: pty) == .signaled(SIGKILL))
        // A killed process is a zombie until its parent reaps it, and the grandchild's parent is now whatever
        // adopts orphans: launchd on macOS, but in a container PID 1 may be `tail` or a shell that never calls
        // `wait`, so the zombie stays and `kill(pid, 0)` keeps succeeding. Dead means gone or a zombie. Bounded poll.
        var gone = false
        let deadline = Date(timeIntervalSinceNow: 20)
        while Date() < deadline {
            if processIsDead(grandchild) { gone = true; break }
            usleep(2000)
        }
        #expect(gone, "the grandchild survived signalGroup")
    }

    @Test(arguments: mechanisms) func theLeaderAloneDyingDoesNotKillAnHupIgnoringGrandchild(_ mechanism: PseudoTerminal.Mechanism) async throws {
        // The control for the test above: with the leader killed alone the grandchild lives on.
        let pty = try shell("trap '' HUP; sleep 300 & echo grandchild=$!; wait", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.wait { text, _, _ in text.contains(where: \.isNewline) && text.contains("grandchild=") })
        let digits = out.text.drop { $0 != "=" }.dropFirst().prefix { $0.isNumber }
        let grandchild = try #require(Int32(digits))
        defer { kill(grandchild, SIGKILL) }
        kill(pty.processID, SIGKILL)
        #expect(await exitStatus(of: pty) == .signaled(SIGKILL))
        #expect(kill(grandchild, 0) == 0, "the grandchild died with its leader")
    }

    #if os(Linux)
    // The reaper below Linux 5.3, which has no `pidfd_open`: one timer polls `waitpid`.
    @Test func theSharedReaperFallbackReapsToo() async throws {
        let size = TerminalSize(cols: 80, rows: 24)
        let exited = try PseudoTerminal.spawn(executable: "/bin/sh", argv: ["sh", "-c", "exit 7"], env: testEnvironment, cwd: "/",
                                              size: size, mechanism: .automatic, sharedReaper: true)
        let killed = try PseudoTerminal.spawn(executable: "/bin/sh", argv: ["sh", "-c", "kill -9 $$"], env: testEnvironment, cwd: "/",
                                              size: size, mechanism: .fork, sharedReaper: true)
        defer { finish(exited); finish(killed) }
        #expect(await exitStatus(of: exited) == .exited(7))
        #expect(await exitStatus(of: killed) == .signaled(9))
    }
    #endif

    @Test(arguments: mechanisms) func signalGroupIsANoOpAfterTheReap(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("exit 0", mechanism: mechanism)
        defer { finish(pty) }
        #expect(await exitStatus(of: pty) == .exited(0))
        pty.signalGroup(.kill)
        pty.signalGroup(.hangup)
        #expect(await exitStatus(of: pty) == .exited(0))
    }

    @Test(arguments: mechanisms) func interruptReachesTheChild(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("trap 'exit 3' INT; echo ready; while :; do read x; done", mechanism: mechanism)
        defer { finish(pty) }
        #expect(Capture(pty).waitFor("ready"))
        pty.signalGroup(.interrupt)
        #expect(await exitStatus(of: pty) == .exited(3))
    }

    // MARK: The foreground group

    @Test(arguments: mechanisms) func theForegroundGroupChangesWhileAJobRuns(_ mechanism: PseudoTerminal.Mechanism) throws {
        // `set -m` gives each foreground job its own group on the controlling terminal.
        let pty = try shell("set -m; echo ready; sleep 5", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("ready"))
        #expect(pty.foregroundProcessGroup() != nil)
        var job: Int32?
        let deadline = Date(timeIntervalSinceNow: 20)
        while Date() < deadline {
            if let group = pty.foregroundProcessGroup(), group != pty.processID { job = group; break }
            sched_yield()
        }
        let group = try #require(job, "the foreground group never left the shell")
        #expect(group != pty.processID)
        kill(-group, SIGKILL)
    }

    // MARK: Volume and ordering

    // One mechanism only: a pty moves about 1.7 MB/s on macOS, so each run takes tens of seconds; the fork path
    // is covered by `bytesArriveInOrder` and the megabyte write.
    @Test func fiftyMegabytesArriveComplete() throws {
        let mechanism = PseudoTerminal.Mechanism.automatic
        let size = 50 * 1024 * 1024
        let pty = try shell("stty raw -echo; echo go; yes | head -c \(size)", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty, keep: false)
        // "go\n" is the shell's first bytes; the flood follows. Raw mode: no newline translation.
        #expect(out.waitForEnd(timeout: 120))
        let flood = out.count - 3
        #expect(flood == size, "got \(flood) of \(size)")
        // 'y' (121) and '\n' (10) alternate; the "go\n" prefix adds 'g' + 'o' + 10 (the echo precedes `raw` taking effect, so
        // its newline may be translated: that case adds one more CR).
        let expected = UInt64(size / 2) * (121 + 10) + UInt64(UInt8(ascii: "g")) + UInt64(UInt8(ascii: "o")) + 10
        #expect(out.checksum == expected, "checksum \(out.checksum) vs \(expected)")
    }

    @Test(arguments: mechanisms) func bytesArriveInOrder(_ mechanism: PseudoTerminal.Mechanism) throws {
        let pty = try shell("stty raw -echo; echo go; seq 1 400000", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitForEnd(timeout: 60))
        let expected = "go\n" + (1...400_000).map { "\($0)\n" }.joined()
        #expect(out.text == expected)
    }

    @Test(arguments: mechanisms) func aMegabyteWrittenToAChildThatDoesNotReadDoesNotBlockTheCaller(_ mechanism: PseudoTerminal.Mechanism) throws {
        // Raw mode and no reading: the pty's input queue fills, and a blocking `write(2)` would stop here.
        let pty = try shell("stty raw -echo; echo ready; sleep 300", mechanism: mechanism)
        defer { finish(pty) }
        #expect(Capture(pty).waitFor("ready"))
        let payload = [UInt8](repeating: UInt8(ascii: "x"), count: 1 << 20)
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            pty.write(payload)
            returned.signal()
        }
        #expect(returned.wait(timeout: .now() + 20) == .success, "write blocked")
    }

    @Test(arguments: mechanisms) func aMegabyteWrittenToACatIsDeliveredWhole(_ mechanism: PseudoTerminal.Mechanism) throws {
        // Written in three calls that must arrive in order, none dropped: the child checksums what it reads.
        let pty = try shell("stty raw -echo; echo ready; head -c 1048576 | cksum", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitFor("ready"))
        var payload = [UInt8](repeating: 0, count: 1 << 20)
        var x: UInt32 = 12345
        for i in payload.indices { x = x &* 1_664_525 &+ 1_013_904_223; payload[i] = UInt8(truncatingIfNeeded: x >> 24) }
        let cuts = [0, 300_001, 700_003, payload.count]
        for i in 0..<3 { pty.write(Array(payload[cuts[i]..<cuts[i + 1]])) }
        let expected = "\(posixCRC(payload)) \(payload.count)"
        #expect(out.waitFor(expected), "child printed \(out.text.suffix(80)), expected \(expected)")
    }

    // MARK: Close

    @Test(arguments: mechanisms) func noCallbackRunsAfterCloseEvenDuringOutput(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("stty raw -echo; echo go; yes", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty, keep: false)
        #expect(out.wait { _, count, _ in count > 1 << 16 })
        // Closing on the reader's own queue makes "after" exact: every handler run that follows is a late one.
        let before = out.queue.sync { () -> Int in
            pty.close()
            return out.callbacks
        }
        // The hangup ends `yes`; once it is reaped, anything queued earlier has long been delivered.
        #expect(await exitStatus(of: pty) != nil)
        out.queue.sync {}
        out.queue.sync {}
        #expect(out.callbacks == before, "\(out.callbacks - before) callbacks after close")
    }

    @Test(arguments: mechanisms) func closeIsIdempotentAndLaterCallsAreHarmless(_ mechanism: PseudoTerminal.Mechanism) async throws {
        let pty = try shell("sleep 300", mechanism: mechanism)
        pty.close()
        pty.close()
        pty.write([1, 2, 3])
        pty.resize(cols: 10, rows: 10)
        #expect(pty.foregroundProcessGroup() == nil)
        var byte: UInt8 = 0
        #expect(withUnsafeMutableBytes(of: &byte) { pty.read(into: $0) } == -1)
        // The hangup from the closed master ends the shell (or the kill does), and it is still reaped.
        pty.signalGroup(.kill)
        #expect(await exitStatus(of: pty) != nil)
    }

    @Test(arguments: mechanisms) func endOfFileIsMinusOneOnceTheChildIsGone(_ mechanism: PseudoTerminal.Mechanism) throws {
        let pty = try shell("echo bye", mechanism: mechanism)
        defer { finish(pty) }
        let out = Capture(pty)
        #expect(out.waitForEnd())
        #expect(out.text.contains("bye"))
    }
}
#endif
