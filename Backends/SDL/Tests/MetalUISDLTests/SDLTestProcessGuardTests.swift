import Foundation
import Testing
import SDLTestProcessGuard
import MetalUISDLGPU

// The test-process guard (rulings TL-B...TL-J, item HG): SDL's signal handlers are off, a watcher
// decides an orphan from `getppid()`, a deadline fires once, the environment parses. Every wait is
// a semaphore with a timeout; nothing sleeps. TL1 and TL2 pin the constructor's environment; the
// end-to-end orphan exit is the probe `docs/probes/sdl-orphan-exit.sh` / `.ps1` (TL-J, WG), not a pin.
// Windows runs every pin but TL2 (WG-F: no SIGTERM there); a PID is always a `muitg_pid_t` (WG-K).

#if os(Windows)
import WinSDK
#endif

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private let orphanSignal = DispatchSemaphore(value: 0)
private let orphanCount = Counter()
private let pollSignal = DispatchSemaphore(value: 0)
private let expireSignal = DispatchSemaphore(value: 0)
private let expireCount = Counter()

private func clearSignals() {
    while orphanSignal.wait(timeout: .now()) == .success {}
    while pollSignal.wait(timeout: .now()) == .success {}
    while expireSignal.wait(timeout: .now()) == .success {}
}

@Suite(.serialized)
struct SDLTestProcessGuardTests {
    /// **TL1.** The constructor set SDL's hint variable before `main`.
    /// Mutation: the constructor's `setenv` removed (TL1, TL2).
    @Test func theTestProcessRunsWithSDLsSignalHandlersOff() {
        let value = ProcessInfo.processInfo.environment["SDL_NO_SIGNAL_HANDLERS"]
        #expect(value == "1")
    }

    /// **TL2.** A process that initialised SDL video still dies to SIGTERM.
    /// Mutation: as TL1.
    #if !os(Windows)
    @Test func aSIGTERMKillsAProcessThatHasInitialisedSDLVideo() async {
        await #expect(processExitsWith: .signal(SIGTERM)) {
            // `make()` initialises video where SDL needs it (on the main thread on macOS), which is
            // what installs SDL's SIGINT/SIGTERM handlers; a process that failed to do so proves nothing.
            let device = SDLGPUDevice.make()
            guard SDL_WasInit(SDL_INIT_VIDEO) != 0 else { exit(3) }
            _ = device
            kill(getpid(), SIGTERM)
            holdUntilKilled()
        }
    }
    #endif

    /// **TL3.** A watcher whose recorded parent is not the parent calls `onOrphan`.
    /// Mutation: the `!=` test inverted (TL3 times out, TL4 sees a spurious orphan).
    @Test func aWatcherWhoseOriginalParentIsNotTheParentExits() {
        clearSignals()
        muitg_watch_parent(aPidThatIsNotOurParent(), 1, { orphanSignal.signal() }, nil)
        #expect(orphanSignal.wait(timeout: .now() + 20) == .success)
    }

    /// **TL4.** A watcher whose parent is unchanged stays quiet over five polls.
    @Test func aWatcherWhoseParentIsUnchangedStaysQuiet() {
        clearSignals()
        let before = orphanCount.count
        muitg_watch_parent(muitg_parent_pid(), 1, { orphanCount.bump() }, { pollSignal.signal() })
        for _ in 0..<5 { #expect(pollSignal.wait(timeout: .now() + 20) == .success) }
        #expect(orphanCount.count == before)
    }

    /// **TL5.** A deadline calls `onExpire` once.
    /// Mutation: the callback invoked in a loop, or never.
    @Test func aDeadlineExpiresOnceAfterItsMilliseconds() {
        clearSignals()
        let before = expireCount.count
        muitg_start_deadline(100, { expireCount.bump(); expireSignal.signal() })
        #expect(expireSignal.wait(timeout: .now() + 20) == .success)
        // Five more polls of a second semaphore would prove "once"; a second expiry would signal again.
        #expect(expireSignal.wait(timeout: .now() + 0.5) == .timedOut)
        #expect(expireCount.count == before + 1)
    }

    /// **TL6.** The deadline variable's parse.
    /// Mutation: the default changed, or "0" mapped to the default.
    @Test func theDeadlineEnvironmentParses() {
        #expect(muitg_parse_deadline_seconds(nil) == 600)
        #expect(muitg_parse_deadline_seconds("") == 600)
        #expect(muitg_parse_deadline_seconds("abc") == 600)
        #expect(muitg_parse_deadline_seconds("-5") == 600)
        #expect(muitg_parse_deadline_seconds("0") == 0)
        #expect(muitg_parse_deadline_seconds("30") == 30)
        #expect(muitg_parse_deadline_seconds("30x") == 600)
        #expect(muitg_parse_deadline_seconds("3 0") == 600)
        #expect(muitg_parse_deadline_seconds("999999999999") == 600)
    }

    /// **TL8.** The constructor armed the deadline the environment names (default 600 s).
    /// Mutation: the constructor's `muitg_arm_deadline` call removed (TL1 cannot see it).
    @Test func theConstructorArmedTheDeadlineBeforeMain() {
        let seconds = ProcessInfo.processInfo.environment["METALUI_TEST_DEADLINE_SECONDS"]
            .map { $0.withCString(muitg_parse_deadline_seconds) } ?? muitg_parse_deadline_seconds(nil)
        #expect(muitg_constructor_armed_deadline_milliseconds() == Int32(seconds) * 1000)
    }

    /// **WG1.** The parent-pid seam answers the parent.
    /// Mutation: POSIX seam stubbed to 0; Windows answer 0 or the process's own id (owed to CI).
    @Test func theParentPidSeamAnswersTheParent() {
        let parent = muitg_parent_pid()
        #expect(parent != 0)
        #if os(Windows)
        #expect(parent != GetCurrentProcessId())
        #expect(muitg_process_started_before_us(parent) != 0)
        #else
        #expect(parent == getppid())
        #endif
    }

    #if os(Windows)
    /// **WG2.** A process that cannot be opened is an orphan, decided before the call returns.
    /// Mutation: the failed-open branch answers "alive" (owed to CI).
    @Test func anUnopenableProcessIsAnOrphanAtOnce() {
        clearSignals()
        muitg_watch_parent(0xFFFF_FFF0, 1_000_000, { orphanSignal.signal() }, nil)
        #expect(orphanSignal.wait(timeout: .now()) == .success)
    }

    /// **WG3.** A process that started after this one is not its parent (PID-reuse guard, WG-C).
    /// Mutation: the creation-time comparison removed or inverted (owed to CI).
    @Test func aProcessStartedAfterUsIsNotOurParent() throws {
        let child = try startLivingChild()
        defer { child.terminate() }
        let pid = muitg_pid_t(truncatingIfNeeded: child.processIdentifier)
        #expect(muitg_process_started_before_us(pid) == 0)
        clearSignals()
        muitg_watch_parent(pid, 1_000_000, { orphanSignal.signal() }, nil)
        #expect(orphanSignal.wait(timeout: .now() + 20) == .success)
    }
    #endif

    /// **TL7.** The probe's hold (TL-J): with `METALUI_TL_HOLD=1` it blocks the helper for two minutes on a
    /// semaphore, the state of a hung GPU wait, so `docs/probes/sdl-orphan-exit.sh` can kill the runner.
    /// Disabled otherwise.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_TL_HOLD"] != nil)) func theProbeHoldBlocksTheHelper() {
        let never = DispatchSemaphore(value: 0)
        _ = never.wait(timeout: .now() + 120)
    }
}

/// A PID that is not this process's parent, as `muitg_pid_t`. POSIX: the parent plus one (a live
/// `getppid()` never equals it). Windows has no reparenting, so it is a spawned child that has
/// already exited (`Process` waited), whose id is dead (WG-K).
private func aPidThatIsNotOurParent() -> muitg_pid_t {
    #if os(Windows)
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
    child.arguments = ["/c", "exit 0"]
    try? child.run()
    child.waitUntilExit()
    return muitg_pid_t(truncatingIfNeeded: child.processIdentifier)
    #else
    return muitg_parent_pid() &+ 1
    #endif
}

#if os(Windows)
/// A child that stays alive for about twenty seconds unless terminated.
private func startLivingChild() throws -> Process {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
    child.arguments = ["/c", "ping -n 20 127.0.0.1 >nul"]
    try child.run()
    return child
}
#endif


/// Blocks the calling process for up to 20 s so a signal must be what ends it. Synchronous so
/// the semaphore wait is not in an async context.
private func holdUntilKilled() {
    let never = DispatchSemaphore(value: 0)
    _ = never.wait(timeout: .now() + 20)
}
