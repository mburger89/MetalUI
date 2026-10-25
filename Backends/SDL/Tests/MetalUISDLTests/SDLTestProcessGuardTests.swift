import Foundation
import Testing
import SDLTestProcessGuard
import MetalUISDLGPU

// The test-process guard (rulings TL-B...TL-J, item HG): SDL's signal handlers are off, a watcher
// decides an orphan from `getppid()`, a deadline fires once, the environment parses. Every wait is
// a semaphore with a timeout; nothing sleeps. TL1 and TL2 pin the constructor's environment; the
// end-to-end orphan exit is the probe `docs/probes/sdl-orphan-exit.sh` (TL-J), not a pin.

#if !os(Windows)

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
        let value = getenv("SDL_NO_SIGNAL_HANDLERS").map { String(cString: $0) }
        #expect(value == "1")
    }

    /// **TL2.** A process that initialised SDL video still dies to SIGTERM.
    /// Mutation: as TL1.
    @Test func aSIGTERMKillsAProcessThatHasInitialisedSDLVideo() async {
        await #expect(processExitsWith: .signal(SIGTERM)) {
            // `make()` initialises video where SDL needs it (on the main thread on macOS), which is
            // what installs SDL's SIGINT/SIGTERM handlers; a process that failed to do so proves nothing.
            let device = SDLGPUDevice.make()
            guard SDL_WasInit(SDL_INIT_VIDEO) != 0 else { exit(3) }
            _ = device
            kill(getpid(), SIGTERM)
            let never = DispatchSemaphore(value: 0)
            _ = never.wait(timeout: .now() + 20)
        }
    }

    /// **TL3.** A watcher whose recorded parent is not the parent calls `onOrphan`.
    /// Mutation: the `!=` test inverted (TL3 times out, TL4 sees a spurious orphan).
    @Test func aWatcherWhoseOriginalParentIsNotTheParentExits() {
        clearSignals()
        muitg_watch_parent(getppid() &+ 1, 1, { orphanSignal.signal() }, nil)
        #expect(orphanSignal.wait(timeout: .now() + 20) == .success)
    }

    /// **TL4.** A watcher whose parent is unchanged stays quiet over five polls.
    @Test func aWatcherWhoseParentIsUnchangedStaysQuiet() {
        clearSignals()
        let before = orphanCount.count
        muitg_watch_parent(getppid(), 1, { orphanCount.bump() }, { pollSignal.signal() })
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
        #expect(muitg_parse_deadline_seconds("999999999999") == 600)
    }
}

#endif
