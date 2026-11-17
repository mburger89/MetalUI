#if !os(Windows)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import CPseudoTerminal
import Dispatch
import Foundation

/// A child process on a pseudo-terminal (macOS and Linux; ruling `TRM-K`).
///
/// The child is a session leader whose controlling terminal is the pty and
/// which owns exactly the file descriptors 0-2. Read it from the
/// ``onReadable(queue:_:)`` handler, write to it at any time from any thread,
/// and call ``close()`` when done: a pty that is never closed keeps its master
/// descriptor until the child exits and is reaped.
///
/// Nothing here installs a `SIGCHLD` handler: the child is reaped by a dispatch
/// process source (macOS) or a `pidfd` read source (Linux 5.3+; a shared
/// polling reaper below that).
public final class PseudoTerminal: @unchecked Sendable {
    /// A signal ``signalGroup(_:)`` can send.
    public enum Signal: Sendable {
        /// `SIGHUP`.
        case hangup
        /// `SIGINT`.
        case interrupt
        /// `SIGTERM`.
        case terminate
        /// `SIGKILL`.
        case kill

        var number: Int32 {
            switch self {
            case .hangup: SIGHUP
            case .interrupt: SIGINT
            case .terminate: SIGTERM
            case .kill: SIGKILL
            }
        }
    }

    /// How the child ended.
    public enum ExitStatus: Sendable, Equatable {
        /// It called `exit` with this status.
        case exited(Int32)
        /// A signal with this number killed it.
        case signaled(Int32)
    }

    /// The mechanism that started the child; tests pin each one.
    package enum Mechanism: Sendable {
        /// `posix_spawn` where sound, else `fork`.
        case automatic
        /// `posix_spawn` only.
        case posixSpawn
        /// The async-signal-safe `fork` path only.
        case fork
    }

    private let master: Int32
    private let pid: Int32
    /// The mechanism that ran.
    package let mechanismUsed: Mechanism

    private let lock = NSLock()
    private var closed = false
    private var status: ExitStatus?
    private var waiters: [CheckedContinuation<ExitStatus, Never>] = []
    private var reaped = false

    private var readSource: DispatchSourceRead?
    private var endOfFile = false
    private var readSuspended = false

    private let writeQueue: DispatchQueue
    private var writeSource: DispatchSourceWrite?
    private var writeSourceResumed = false
    private var pending: [[UInt8]] = []   // writeQueue only
    private var pendingHead = 0           // bytes of pending[0] already written
    private var fdUsers = 0               // sources whose cancel handler has yet to run (lock)

    private var reapSource: DispatchSourceProtocol?

    private init(master: Int32, pid: Int32, mechanism: Mechanism, sharedReaper: Bool) {
        self.master = master
        self.pid = pid
        self.mechanismUsed = mechanism
        self.writeQueue = DispatchQueue(label: "MetalUITerminal.PseudoTerminal.write")
        startWriteSource()
        startReaper(sharedReaper: sharedReaper)
    }

    deinit {
        close()
    }

    /// Starts `executable` on a new pty of `size`.
    ///
    /// `env` is the child's whole environment and `argv` its whole argument
    /// vector (`argv[0]` included); nothing is defaulted. The child gets
    /// exactly the descriptors 0-2 and a new session whose controlling
    /// terminal is the pty.
    public static func spawn(executable: String, argv: [String], env: [String: String], cwd: String,
                             size: TerminalSize) throws(PseudoTerminalError) -> PseudoTerminal {
        try spawn(executable: executable, argv: argv, env: env, cwd: cwd, size: size, mechanism: .automatic)
    }

    package static func spawn(executable: String, argv: [String], env: [String: String], cwd: String,
                              size: TerminalSize, mechanism: Mechanism,
                              sharedReaper: Bool = false) throws(PseudoTerminalError) -> PseudoTerminal {
        // Everything the child needs is built before any fork.
        let args = argv.map { strdup($0) } + [nil]
        let vars = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            args.forEach { free($0) }
            vars.forEach { free($0) }
        }
        var result = cpt_result()
        let mode: Int32 = switch mechanism {
        case .automatic: Int32(CPT_AUTO)
        case .posixSpawn: Int32(CPT_POSIX_SPAWN)
        case .fork: Int32(CPT_FORK)
        }
        cpt_spawn(executable, args, vars, cwd, UInt16(clamping: size.cols), UInt16(clamping: size.rows), mode, &result)
        switch result.stage {
        case Int32(CPT_OK):
            let ran: Mechanism = result.mechanism == Int32(CPT_FORK) ? .fork : .posixSpawn
            return PseudoTerminal(master: result.master, pid: result.pid, mechanism: ran, sharedReaper: sharedReaper)
        case Int32(CPT_OPEN_FAILED):
            throw .openFailed(code: result.code)
        default:
            throw .spawnFailed(code: result.code)
        }
    }

    /// The child's process identifier (also its process group and session).
    public var processID: Int32 { pid }

    // MARK: Reading

    /// Calls `handler` on `queue` whenever the pty has output or has ended.
    ///
    /// Call ``read(into:)`` from the handler until it returns 0. Replaces an
    /// earlier handler. After ``close()`` no handler runs.
    public func onReadable(queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if closed { lock.unlock(); return }
        let old = readSource
        readSource = nil
        let oldSuspended = readSuspended
        readSuspended = false
        lock.unlock()
        old?.cancel()
        if oldSuspended { old?.resume() }

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.closed { self.lock.unlock(); return }
            if self.endOfFile {
                // Level-triggered: at end of file the source would fire forever.
                if !self.readSuspended {
                    self.readSuspended = true
                    self.readSource?.suspend()
                }
                self.lock.unlock()
                return
            }
            self.lock.unlock()
            handler()
        }
        source.setCancelHandler { [weak self] in self?.sourceFinished() }
        lock.lock()
        if closed {
            lock.unlock()
            // Never resumed: a source needs no cancel handler to be released.
            return
        }
        fdUsers += 1
        readSource = source
        lock.unlock()
        source.resume()
    }

    /// Reads available output into `buffer`.
    ///
    /// Returns the number of bytes read (more than 0), 0 when nothing is
    /// available now, or -1 at end of file (the child's side is closed, or the
    /// pty is closed).
    public func read(into buffer: UnsafeMutableRawBufferPointer) -> Int {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        // Under the lock so the descriptor cannot be closed (and reused) mid-read.
        lock.lock()
        defer { lock.unlock() }
        if closed || endOfFile { return -1 }
        while true {
            let n = sysRead(master, base, buffer.count)
            if n > 0 { return n }
            if n < 0 && errno == EINTR { continue }
            if n < 0 && errno == EAGAIN { return 0 }
            // 0 is end of file on macOS; EIO is Linux's; anything else ends the stream too.
            endOfFile = true
            return -1
        }
    }

    // MARK: Writing

    /// Queues `bytes` for the child.
    ///
    /// Returns at once whatever the child is doing; bytes are written in order
    /// and never dropped (until ``close()``).
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        writeQueue.async { [self] in
            if isClosed { return }
            pending.append(bytes)
            drainWrites()
        }
    }

    // Writes queue only. A non-blocking write drains what the pty accepts; the
    // write source stays resumed only while something is pending.
    private func drainWrites() {
        while let first = pending.first {
            let n = first.withUnsafeBytes { raw in
                sysWrite(master, raw.baseAddress! + pendingHead, raw.count - pendingHead)
            }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN { break }
                pending.removeAll()
                pendingHead = 0
                break
            }
            pendingHead += n
            if pendingHead == first.count {
                pending.removeFirst()
                pendingHead = 0
            }
        }
        setWriteSourceActive(!pending.isEmpty)
    }

    private func setWriteSourceActive(_ active: Bool) {
        guard let source = writeSource, active != writeSourceResumed else { return }
        writeSourceResumed = active
        if active { source.resume() } else { source.suspend() }
    }

    private func startWriteSource() {
        let source = DispatchSource.makeWriteSource(fileDescriptor: master, queue: writeQueue)
        source.setEventHandler { [weak self] in self?.drainWrites() }
        source.setCancelHandler { [weak self] in self?.sourceFinished() }
        fdUsers += 1
        writeSource = source   // created suspended: `writeSourceResumed` is false
    }

    // MARK: Control

    /// Sets the pty's size, which the kernel reports to the child (`SIGWINCH`).
    public func resize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        lock.lock()
        defer { lock.unlock() }
        if closed { return }
        _ = cpt_set_size(master, UInt16(clamping: size.cols), UInt16(clamping: size.rows))
    }

    /// Sends `signal` to the child's process group; a no-op after the child is reaped.
    public func signalGroup(_ signal: Signal) {
        lock.lock()
        defer { lock.unlock() }
        if reaped { return }
        _ = killpg(pid, signal.number)
    }

    /// The pty's foreground process group, or `nil` when it cannot be read
    /// (closed, or the child has gone).
    public func foregroundProcessGroup() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        if closed { return nil }
        let group = cpt_foreground_group(master)
        return group > 0 ? group : nil
    }

    /// How the child ended; waits for it, and is the same value on every call.
    public var exitStatus: ExitStatus {
        get async {
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
    }

    /// Stops readiness callbacks and closes the master; idempotent.
    ///
    /// The child receives the hangup a closed master causes. It is still
    /// reaped (``exitStatus`` still resolves), and no signal is sent after the reap.
    public func close() {
        lock.lock()
        if closed { lock.unlock(); return }
        closed = true
        let read = readSource
        readSource = nil
        let wasSuspended = readSuspended
        readSuspended = false
        lock.unlock()
        read?.cancel()
        if wasSuspended { read?.resume() }   // a suspended source cannot run its cancel handler
        writeQueue.async { [self] in
            pending.removeAll()
            guard let source = writeSource else { return }
            writeSource = nil
            // A suspended source must be resumed before it can be cancelled.
            source.cancel()
            if !writeSourceResumed { source.resume() }
            writeSourceResumed = true
        }
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    // The master closes when the last source that uses it has finished; a pty
    // closed before any read handler was installed has only the write source.
    private func sourceFinished() {
        lock.lock()
        fdUsers -= 1
        let last = fdUsers == 0
        lock.unlock()
        if last { _ = sysClose(master) }
    }

    // MARK: Reaping

    // `sharedReaper` forces Linux's below-5.3 fallback so a test can run it; macOS has one mechanism.
    private func startReaper(sharedReaper: Bool) {
        #if canImport(Darwin)
        _ = sharedReaper
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: reaperQueue)
        source.setEventHandler { [weak self] in self?.tryReap() }
        reapSource = source
        source.resume()
        tryReap()   // the child may have gone before the source existed
        #else
        let fd = sharedReaper ? -1 : cpt_pidfd_open(pid)
        if fd >= 0 {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: reaperQueue)
            source.setEventHandler { [weak self] in self?.tryReap() }
            source.setCancelHandler { _ = sysClose(fd) }
            reapSource = source
            source.resume()
        } else {
            SharedReaper.shared.add(self)
        }
        tryReap()
        #endif
    }

    /// Reaps the child if it has exited; true once it has been.
    @discardableResult
    func tryReap() -> Bool {
        lock.lock()
        if reaped { lock.unlock(); return true }
        var raw: Int32 = 0
        let r = waitpid(pid, &raw, WNOHANG)
        if r == 0 { lock.unlock(); return false }
        let outcome: ExitStatus
        if r < 0 {
            // ECHILD: someone else reaped it; report a generic failure rather than hang.
            outcome = .exited(-1)
        } else if (raw & 0x7f) == 0 {
            outcome = .exited((raw >> 8) & 0xff)
        } else {
            outcome = .signaled(raw & 0x7f)
        }
        reaped = true
        status = outcome
        let waiting = waiters
        waiters = []
        let source = reapSource
        reapSource = nil
        lock.unlock()
        source?.cancel()
        for continuation in waiting { continuation.resume(returning: outcome) }
        return true
    }
}

private let reaperQueue = DispatchQueue(label: "MetalUITerminal.PseudoTerminal.reap")

/// The fallback below Linux 5.3: one timer polls every unreaped child.
private final class SharedReaper: @unchecked Sendable {
    static let shared = SharedReaper()
    private let lock = NSLock()
    private var terminals: [PseudoTerminal] = []
    private var timer: DispatchSourceTimer?

    func add(_ terminal: PseudoTerminal) {
        lock.lock()
        defer { lock.unlock() }
        terminals.append(terminal)
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: reaperQueue)
        t.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        t.setEventHandler { [self] in poll() }
        timer = t
        t.resume()
    }

    private func poll() {
        lock.lock()
        let current = terminals
        lock.unlock()
        let done = current.filter { $0.tryReap() }
        lock.lock()
        terminals.removeAll { t in done.contains { $0 === t } }
        if terminals.isEmpty { timer?.cancel(); timer = nil }
        lock.unlock()
    }
}

#if canImport(Darwin)
private func sysRead(_ fd: Int32, _ p: UnsafeMutableRawPointer, _ n: Int) -> Int { Darwin.read(fd, p, n) }
private func sysWrite(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { Darwin.write(fd, p, n) }
private func sysClose(_ fd: Int32) -> Int32 { Darwin.close(fd) }
#else
private func sysRead(_ fd: Int32, _ p: UnsafeMutableRawPointer, _ n: Int) -> Int { Glibc.read(fd, p, n) }
private func sysWrite(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int { Glibc.write(fd, p, n) }
private func sysClose(_ fd: Int32) -> Int32 { Glibc.close(fd) }
#endif

/// Why a pty could not be started.
public enum PseudoTerminalError: Error, Sendable, Equatable {
    /// Opening the pty failed (`errno` in `code`).
    case openFailed(code: Int32)
    /// Starting the child failed (`errno` in `code`; `ENOENT` for a missing executable).
    case spawnFailed(code: Int32)
    /// The platform cannot do it.
    case unsupported(String)
}

#endif
