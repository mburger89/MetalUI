#if os(Windows)

import CPseudoTerminal
import Dispatch
import Foundation

/// A child process on a pseudo-terminal (Windows 10 1809 or later, ConPTY; ruling `TRM-AX`).
///
/// The same API as the POSIX type. The child runs on a pseudo console over two overlapped named pipes, in a
/// job object that kills everything it started when the job closes. The pseudo console (conhost) re-renders
/// what the child draws, so the bytes read are conhost's, not the child's: render them through a
/// ``TerminalEmulator`` rather than comparing them.
///
/// Readiness comes from thread-pool IO (no thread per pty) and is delivered on the queue given to
/// ``onReadable(queue:_:)``. Read it, write to it at any time from any thread, and call ``close()`` when done.
public final class PseudoTerminal: @unchecked Sendable {
    private let core: WindowsPTYCore
    private let pid: Int32

    private init(core: WindowsPTYCore, pid: Int32) {
        self.core = core
        self.pid = pid
    }

    deinit {
        close()
    }

    /// Starts `executable` on a new pseudo console of `size`.
    ///
    /// `env` is the child's whole environment and `argv` its whole argument vector (`argv[0]` included, quoted
    /// into one command line by the rules of `CommandLineToArgvW`); nothing is defaulted, so an `env` without
    /// `SystemRoot` starts a child that may not run. `executable` is a path, or a name searched on `PATH`
    /// (`.exe` assumed). No handle is inherited. A missing executable or directory is
    /// ``PseudoTerminalError/spawnFailed(code:)`` with the `GetLastError` value.
    public static func spawn(executable: String, argv: [String], env: [String: String], cwd: String,
                             size: TerminalSize) throws(PseudoTerminalError) -> PseudoTerminal {
        let core = WindowsPTYCore()
        var application = Array(executable.utf16) + [0]
        var commandLine = Array(WindowsCommandLine.commandLine(argv: argv).utf16) + [0]
        let environment = WindowsCommandLine.environmentBlock(env)
        let directory = Array(cwd.utf16) + [0]
        var result = cpw_result()
        let context = Unmanaged.passRetained(core).toOpaque()
        application.withUnsafeMutableBufferPointer { app in
            commandLine.withUnsafeMutableBufferPointer { line in
                environment.withUnsafeBufferPointer { env in
                    directory.withUnsafeBufferPointer { dir in
                        cpw_spawn(app.baseAddress, line.baseAddress, env.baseAddress, dir.baseAddress,
                                  UInt16(clamping: size.cols), UInt16(clamping: size.rows),
                                  windowsPTYNotify, context, &result)
                    }
                }
            }
        }
        switch result.stage {
        case Int32(CPW_OK):
            core.attach(result.pty)
            return PseudoTerminal(core: core, pid: Int32(bitPattern: result.pid))
        default:
            Unmanaged<WindowsPTYCore>.fromOpaque(context).release()
            let code = Int32(bitPattern: result.code)
            switch result.stage {
            case Int32(CPW_OPEN_FAILED): throw .openFailed(code: code)
            case Int32(CPW_UNSUPPORTED): throw .unsupported("ConPTY needs Windows 10 version 1809 or later")
            default: throw .spawnFailed(code: code)
            }
        }
    }

    /// The child's process identifier.
    public var processID: Int32 { pid }

    // MARK: Reading

    /// Calls `handler` on `queue` whenever the pty has output or has ended.
    ///
    /// Call ``read(into:)`` from the handler until it returns 0. Replaces an earlier handler. After
    /// ``close()`` no handler runs.
    public func onReadable(queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void) {
        core.setHandler(queue: queue, handler)
    }

    /// Reads available output into `buffer`.
    ///
    /// Returns the number of bytes read (more than 0), 0 when nothing is available now, or -1 at end of file
    /// (the child and its console are gone and everything was read, or the pty is closed).
    public func read(into buffer: UnsafeMutableRawBufferPointer) -> Int {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        return core.read(base, buffer.count)
    }

    // MARK: Writing

    /// Queues `bytes` for the child.
    ///
    /// Returns at once whatever the child is doing; bytes are written in order by overlapped writes and never
    /// dropped (until ``close()``).
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        core.write(bytes)
    }

    // MARK: Control

    /// Resizes the pseudo console (`ResizePseudoConsole`); conhost reflows and the child sees the new size.
    public func resize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        core.resize(UInt16(clamping: size.cols), UInt16(clamping: size.rows))
    }

    /// Sends `signal` to the child; a no-op after the child has ended.
    ///
    /// `.interrupt` writes `0x03` to the console input (Ctrl+C for a child in processed-input mode). The others
    /// terminate the job the child runs in, which ends everything it started (`TRM-E`).
    public func signalGroup(_ signal: Signal) {
        switch signal {
        case .interrupt:
            if core.isRunning { core.write([0x03]) }
        case .hangup, .terminate, .kill:
            core.terminate()
        }
    }

    /// Waits, at most `timeout` seconds, until teardown after ``close()`` has finished and every handle is
    /// released; false when it did not, or when it had to give up on a step (a `ClosePseudoConsole` that never
    /// returned). Tests use it to prove the close does not deadlock.
    package func waitUntilReleased(timeout: Double) -> Bool {
        core.waitUntilReleased(timeout: timeout)
    }

    /// Always `nil`: Windows has no foreground process group.
    public func foregroundProcessGroup() -> Int32? { nil }

    /// How the child ended; waits for it, and is the same value on every call.
    ///
    /// A child ended by ``signalGroup(_:)`` (or ``close()``) reports `.exited(1)`.
    public var exitStatus: ExitStatus {
        get async { await core.exitStatus() }
    }

    /// Stops readiness callbacks and tears the pseudo console down; idempotent.
    ///
    /// The job closes (so the child and all it started end), the pseudo console is closed on a short-lived
    /// thread while the output pipe is still read and thrown away (`ClosePseudoConsole` can wait for its
    /// output to be read), and the handles are released once both have finished. The child is still reaped:
    /// ``exitStatus`` still resolves.
    public func close() {
        core.close()
    }
}

/// The state the C engine's callbacks reach. It outlives its ``PseudoTerminal``: the engine holds one retain
/// until teardown has finished (the `CPW_EVENT_RELEASED` callback), so the exit status of a closed pty still
/// arrives.
private final class WindowsPTYCore: @unchecked Sendable {
    private let lock = NSLock()
    private var pty: OpaquePointer?
    private var closed = false
    private var status: PseudoTerminal.ExitStatus?
    private var waiters: [CheckedContinuation<PseudoTerminal.ExitStatus, Never>] = []

    private var queue: DispatchQueue?
    private var handler: (@Sendable () -> Void)?
    private var scheduled = false
    private let releasedGroup = DispatchGroup()
    private var releasedCleanly = false

    init() { releasedGroup.enter() }

    /// True once teardown finished with every step done in time (`clean`), not merely given up on.
    func waitUntilReleased(timeout: Double) -> Bool {
        guard releasedGroup.wait(timeout: .now() + timeout) == .success else { return false }
        lock.lock()
        defer { lock.unlock() }
        return releasedCleanly
    }

    func released(clean: Bool) {
        lock.lock()
        releasedCleanly = clean
        lock.unlock()
        releasedGroup.leave()
    }

    func attach(_ pty: OpaquePointer?) {
        lock.lock()
        self.pty = pty
        lock.unlock()
        // Output may have arrived before the handler or the pointer existed.
        schedule()
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pty != nil && !closed && status == nil
    }

    func setHandler(queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if closed { lock.unlock(); return }
        self.queue = queue
        self.handler = handler
        lock.unlock()
        schedule()
    }

    /// Runs the handler once on the queue if there is something to read (level-triggered, like the POSIX type).
    private func schedule() {
        lock.lock()
        guard !closed, !scheduled, let queue, let pty, cpw_available(pty) != 0 else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            scheduled = false
            if closed { lock.unlock(); return }
            let handler = handler
            lock.unlock()
            handler?()
        }
    }

    func read(_ base: UnsafeMutableRawPointer, _ count: Int) -> Int {
        // Under the lock so the engine cannot be torn down mid-read.
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let pty else { return -1 }
        return Int(cpw_read(pty, base, count))
    }

    func write(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let pty else { return }
        bytes.withUnsafeBytes { cpw_write(pty, $0.baseAddress, $0.count) }
    }

    func resize(_ cols: UInt16, _ rows: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let pty else { return }
        cpw_resize(pty, cols, rows)
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, status == nil, let pty else { return }
        cpw_terminate(pty)
    }

    func close() {
        lock.lock()
        if closed { lock.unlock(); return }
        closed = true
        let pty = self.pty
        self.pty = nil
        handler = nil
        queue = nil
        lock.unlock()
        if let pty { cpw_close(pty) }
    }

    func exitStatus() async -> PseudoTerminal.ExitStatus {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    // MARK: Callbacks from the engine's threads

    func readable() { schedule() }

    func exited(_ code: Int32) {
        lock.lock()
        if status != nil { lock.unlock(); return }
        let outcome = PseudoTerminal.ExitStatus.exited(code)
        status = outcome
        let waiting = waiters
        waiters = []
        lock.unlock()
        for continuation in waiting { continuation.resume(returning: outcome) }
    }
}

private func windowsPTYNotify(_ context: UnsafeMutableRawPointer?, _ event: Int32, _ value: Int32) {
    guard let context else { return }
    if event == Int32(CPW_EVENT_RELEASED) {
        let core = Unmanaged<WindowsPTYCore>.fromOpaque(context)
        core.takeUnretainedValue().released(clean: value != 0)
        core.release()
        return
    }
    let core = Unmanaged<WindowsPTYCore>.fromOpaque(context).takeUnretainedValue()
    if event == Int32(CPW_EVENT_EXITED) { core.exited(value) } else { core.readable() }
}

#endif
