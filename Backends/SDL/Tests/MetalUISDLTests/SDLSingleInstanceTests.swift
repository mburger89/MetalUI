// Single-instance launch on SDL (item S7, rulings SN-A..SN-O; spec
// `docs/superpowers/specs/2026-10-19-single-instance-design.md` §5, tests 1-18).
// Every test drives the real transport (a Unix socket in a private temporary
// directory on macOS and Linux, SN-K) and a bare `SingleInstance` primary or an
// `SDLPlatform` over one. Tests never sleep: a forward returns after the
// primary queued the message (the ack follows the enqueue), so delivery is read
// back, not waited for. Windows runs the transport tests that need no
// Unix-only call; the permission, signal and raw-socket cases are
// `#if !os(Windows)` (their twin is human check SI3).
import Dispatch
import Foundation
import MetalUIPlatform
import MetalUICore
import SDLBridge
import Testing
@testable import MetalUISDL

// MARK: - Helpers

/// A fresh private directory with a short path (`sun_path` is 104 bytes on
/// macOS), removed by the caller's `defer`.
private func privateDirectory() throws -> String {
    #if os(Windows)
    let path = NSTemporaryDirectory() + "msi-" + UUID().uuidString.prefix(8)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
    #else
    var template = Array("/tmp/msi-XXXXXX".utf8CString)
    let made = template.withUnsafeMutableBufferPointer { mkdtemp($0.baseAddress!) != nil }
    try #require(made, "mkdtemp failed")
    return String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    #endif
}

private func remove(_ directory: String) { try? FileManager.default.removeItem(atPath: directory) }

private func configuration(_ directory: String, connect: Duration = .seconds(2), read: Duration = .seconds(2),
                           raises: Bool = true, uid: UInt32? = nil) -> SingleInstance.Configuration {
    SingleInstance.Configuration(directory: directory, connectTimeout: connect, readTimeout: read,
                                 raisesWindow: raises, expectedPeerUID: uid)
}

/// The primary role for `id` in `directory`, or an issue.
private func becomePrimary(_ id: String, _ directory: String, raises: Bool = true, uid: UInt32? = nil,
                           read: Duration = .seconds(2),
                           sourceLocation: SourceLocation = #_sourceLocation) -> SingleInstance? {
    let outcome = SingleInstance.claim(id: id, forwarding: [],
                                       configuration: configuration(directory, read: read, raises: raises, uid: uid))
    guard case .primary(let instance) = outcome else {
        Issue.record("expected .primary, got \(outcome)", sourceLocation: sourceLocation)
        return nil
    }
    return instance
}

private func forward(_ id: String, _ directory: String, _ strings: [String],
                     connect: Duration = .seconds(2), read: Duration = .seconds(2)) -> SingleInstance.Outcome {
    SingleInstance.claim(id: id, forwarding: strings,
                         configuration: configuration(directory, connect: connect, read: read))
}

private func isForwarded(_ outcome: SingleInstance.Outcome) -> Bool {
    if case .forwarded = outcome { return true }
    return false
}

private func isPrimary(_ outcome: SingleInstance.Outcome) -> Bool {
    if case .primary = outcome { return true }
    return false
}

private func failure(_ outcome: SingleInstance.Outcome) -> SingleInstance.Failure? {
    if case .unavailable(let failure) = outcome { return failure }
    return nil
}

@MainActor
private func makePlatform(for instance: SingleInstance, hidesWindows: Bool = true) throws -> SDLPlatform {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(options: SDLPlatform.Options(hidesWindows: hidesWindows, singleInstance: instance))
    // SDL's Cocoa backend reports the test process's own command line as an open
    // event on the first pump (`AS-G`): settle it into a discarded handler, so a
    // test reads only what it forwarded.
    platform.pumpEvents()
    platform.onOpenURLs = { _ in }
    platform.onOpenURLs = nil
    return platform
}

private func pushDrop(_ type: UInt32, _ window: UInt32, _ data: String? = nil,
                      sourceLocation: SourceLocation = #_sourceLocation) {
    let pushed = data.map { $0.withCString { mui_push_raw_drop_event(type, window, 0, 0, $0) } }
        ?? mui_push_raw_drop_event(type, window, 0, 0, nil)
    #expect(pushed, "push drop type \(type)", sourceLocation: sourceLocation)
}

/// A run of `work` on another thread, bounded by `seconds`: `nil` when it did
/// not finish, so a mutant that retries for ever fails instead of hanging.
private func finishes<T: Sendable>(within seconds: Double, _ work: @escaping @Sendable () -> T) -> T? {
    let box = LockedBox<T?>(nil)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { box.set(work()); done.signal() }
    guard done.wait(timeout: .now() + seconds) == .success else { return nil }
    return box.get()
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func set(_ new: T) { lock.lock(); value = new; lock.unlock() }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&value); lock.unlock() }
}

private func be32(_ value: Int) -> [UInt8] {
    [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
}

/// A wire message: `"MSI1"`, payload length, then the payload (SN-E).
private func frame(payload: [UInt8], magic: String = "MSI1", declaredLength: Int? = nil) -> [UInt8] {
    Array(magic.utf8) + be32(declaredLength ?? payload.count) + payload
}

private func payload(strings: [[UInt8]], declaredCount: Int? = nil) -> [UInt8] {
    var bytes = be32(declaredCount ?? strings.count)
    for string in strings { bytes += be32(string.count) + string }
    return bytes
}

private func message(_ strings: [String]) -> [UInt8] { frame(payload: payload(strings: strings.map { Array($0.utf8) })) }

// MARK: - Raw clients (Unix)

#if !os(Windows)
private func rawConnect(_ path: String) -> Int32? {
    #if os(Linux)
    let stream = Int32(SOCK_STREAM.rawValue)
    #else
    let stream = SOCK_STREAM
    #endif
    let fd = socket(AF_UNIX, stream, 0)
    guard fd >= 0 else { return nil }
    #if !os(Linux)
    var noSignal: Int32 = 1   // a refused write must be an error, not SIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    #endif
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in bytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { close(fd); return nil }
    return fd
}

private func rawWrite(_ fd: Int32, _ bytes: [UInt8]) {
    var sent = 0
    while sent < bytes.count {
        #if os(Linux)
        let n = bytes[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
        #else
        let n = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        #endif
        if n <= 0 { return }
        sent += n
    }
}

/// The ack byte, or `nil` for a close, a reset or `seconds` with nothing.
private func rawReadAck(_ fd: Int32, seconds: Int32 = 5) -> UInt8? {
    var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&descriptor, 1, seconds * 1000) > 0 else { return nil }
    var byte: UInt8 = 0
    return read(fd, &byte, 1) == 1 ? byte : nil
}

private func rawSend(to path: String, _ bytes: [UInt8]) -> UInt8? {
    guard let fd = rawConnect(path) else { return nil }
    defer { close(fd) }
    rawWrite(fd, bytes)
    return rawReadAck(fd)
}

private func mode(of path: String) -> mode_t? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return info.st_mode
}
#endif

// MARK: - The suite

@Suite(.serialized)
struct SDLSingleInstanceTests {
    /// 1 (SN-E, SN-G). Three forwards of 2, 1 and 3 strings reach the primary
    /// as three batches in the order they were sent.
    ///
    /// Mutations: drain the queue last-in first-out; append every connection
    /// into one batch.
    @Test func aSecondClaimForwardsItsArgumentsAndThePrimaryReceivesThemInOrder() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.order", directory))
        let batches = [["/tmp/a1", "/tmp/a2"], ["/tmp/b1"], ["/tmp/c1", "/tmp/c2", "/tmp/c3"]]
        for batch in batches {
            let outcome = forward("com.test.order", directory, batch)
            #expect(isForwarded(outcome), "\(outcome)")
        }
        #expect(primary.takeMessages() == batches)
    }

    /// 2 (SN-E, SN-G). The sender makes a relative path absolute against its own
    /// working directory; an absolute path and a URL pass as they are; the
    /// platform delivers paths as file URLs and URLs as is.
    ///
    /// Mutations: skip the sender's absolutising; treat every string as a path.
    @MainActor
    @Test func aForwardedPathBecomesAFileURLAndARelativeOneIsMadeAbsoluteByTheSender() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.paths", directory))
        let platform = try makePlatform(for: primary)
        var opened: [[String]] = []
        platform.onOpenURLs = { opened.append($0) }
        let outcome = forward("com.test.paths", directory, ["rel/a b.txt", "/abs/x", "https://x/y"])
        try #require(isForwarded(outcome), "\(outcome)")
        platform.pumpEvents()
        let cwd = FileManager.default.currentDirectoryPath
        #expect(opened == [[SDLWindow.fileURLString(fromPath: cwd + "/rel/a b.txt"),
                            "file:///abs/x", "https://x/y"]], "\(opened)")
    }

    /// 2b (SN-E item "relative"). A Windows drive path is absolute where Windows
    /// is the platform; on Unix it is a relative file name and gets the cwd.
    @Test func aDrivePathIsAbsoluteOnlyOnWindows() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.drive", directory))
        try #require(isForwarded(forward("com.test.drive", directory, ["C:\\x", "\\\\host\\share\\f"])))
        let cwd = FileManager.default.currentDirectoryPath
        #if os(Windows)
        #expect(primary.takeMessages() == [["C:\\x", "\\\\host\\share\\f"]])
        #else
        #expect(primary.takeMessages() == [[cwd + "/C:\\x", cwd + "/\\\\host\\share\\f"]])
        #endif
    }

    /// 3 (SN-G, `AS-Q`). Batches wait for a handler, are delivered once each in
    /// order when one is set, and never again.
    ///
    /// Mutation: drop a batch when there is no handler.
    @MainActor
    @Test func batchesWaitForAHandlerAndAreDeliveredOnceInOrder() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.park", directory))
        let platform = try makePlatform(for: primary)
        try #require(isForwarded(forward("com.test.park", directory, ["/tmp/one"])))
        try #require(isForwarded(forward("com.test.park", directory, ["/tmp/two", "/tmp/three"])))
        platform.pumpEvents()
        var opened: [[String]] = []
        platform.onOpenURLs = { opened.append($0) }
        #expect(opened == [["file:///tmp/one"], ["file:///tmp/two", "file:///tmp/three"]], "\(opened)")
        platform.onOpenURLs = nil
        platform.onOpenURLs = { opened.append($0) }
        platform.pumpEvents()
        #expect(opened.count == 2, "a delivered batch is not delivered again: \(opened)")
    }

    #if !os(Windows)
    /// 4 (SN-C item 2). A leftover file at the socket's name, or an abandoned
    /// bound socket, with no lock held, is stale: a new claim becomes primary.
    ///
    /// Mutation: refuse when the file exists.
    @Test func aStaleSocketFileIsReplacedByANewPrimary() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let paths = try #require(SingleInstance.paths(id: "com.test.stale", directory: directory))
        try Data("not a socket".utf8).write(to: URL(fileURLWithPath: paths.socket))
        let first = try #require(becomePrimary("com.test.stale", directory))
        #expect((mode(of: paths.socket) ?? 0) & S_IFMT == S_IFSOCK, "the stale file was replaced by a socket")
        // The crashed primary's way: a socket bound and abandoned, its file left.
        withExtendedLifetime(first) {}
        // (released below by letting `first` go; its socket file is removed with it)
        let abandoned = try privateDirectory(); defer { remove(abandoned) }
        let other = try #require(SingleInstance.paths(id: "com.test.stale", directory: abandoned))
        let fd = try #require(bindAndAbandon(other.socket))
        close(fd)
        #expect(FileManager.default.fileExists(atPath: other.socket), "the abandoned socket's file is left")
        let second = try #require(becomePrimary("com.test.stale", abandoned))
        withExtendedLifetime(second) {}
    }

    private func bindAndAbandon(_ path: String) -> Int32? {
        #if os(Linux)
        let stream = Int32(SOCK_STREAM.rawValue)
        #else
        let stream = SOCK_STREAM
        #endif
        let fd = socket(AF_UNIX, stream, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.utf8CString.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return bound == 0 ? fd : nil
    }
    #endif

    /// 4b (SN-M item 1). Eight claims at once, one directory: exactly one is
    /// primary and none is a second primary.
    ///
    /// Mutation: claim without `flock`.
    @Test func eightConcurrentClaimsElectExactlyOnePrimary() throws {
        for round in 0..<5 {
            let directory = try privateDirectory(); defer { remove(directory) }
            let outcomes = LockedBox<[SingleInstance.Outcome]>([])
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                let outcome = SingleInstance.claim(id: "com.test.race\(round)", forwarding: ["/tmp/race"],
                                                   configuration: configuration(directory, connect: .seconds(1)))
                outcomes.mutate { $0.append(outcome) }
            }
            let all = outcomes.get()
            let primaries = all.filter(isPrimary)
            #expect(primaries.count == 1, "round \(round): \(primaries.count) primaries among \(all)")
            for outcome in all where !isPrimary(outcome) {
                #expect(isForwarded(outcome) || failure(outcome) == .noListener, "\(outcome)")
            }
            withExtendedLifetime(primaries) {}
        }
    }

    #if !os(Windows)
    /// 5 (SN-C item 2, SN-J). A live primary in another process holds the role (a
    /// claim forwards to it); `SIGKILL` releases it with the socket file left
    /// behind, and the next claim is primary.
    ///
    /// Mutation: take the role without `flock` (the live process's claim then
    /// answers `.primary`; 4b is the separating test for a bind-only election).
    @Test func aKilledPrimaryReleasesTheRole() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let process = Process()
        let executable = try #require(checkExecutable(), "SingleInstanceCheck not found — run `swift build`")
        process.executableURL = executable
        process.arguments = ["primary", directory, "com.test.kill"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let line = readLine(from: output.fileHandleForReading)
        try #require(line == "primary", "the subprocess did not become primary: \(line)")
        let live = forward("com.test.kill", directory, ["/tmp/while-alive"])
        #expect(isForwarded(live), "a live primary holds the role: \(live)")
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        let paths = try #require(SingleInstance.paths(id: "com.test.kill", directory: directory))
        #expect(FileManager.default.fileExists(atPath: paths.socket), "a killed primary leaves its socket file")
        let next = try #require(becomePrimary("com.test.kill", directory))
        withExtendedLifetime(next) {}
    }
    #endif

    /// 6 (SN-A item 3). A second process forwards and exits 0; the primary here
    /// receives its arguments, made absolute.
    ///
    /// Mutation: the check exits 1 on `.forwarded`.
    @Test func aSecondProcessForwardsAndExitsZero() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.process", directory))
        let process = Process()
        let executable = try #require(checkExecutable(), "SingleInstanceCheck not found — run `swift build`")
        process.executableURL = executable
        process.arguments = ["forward", directory, "com.test.process", "/tmp/from-process", "metalui://doc/7"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "status \(process.terminationStatus): \(text)")
        #expect(primary.takeMessages() == [["/tmp/from-process", "metalui://doc/7"]])
    }

    /// 7 (SN-C item 4, SN-F). The lock held and nobody listening is
    /// `.unavailable(.noListener)` within the connect timeout, not a wait for ever.
    ///
    /// Mutation: retry for ever (the bounded wait reports it).
    @Test func aLockHeldWithNoListenerFallsBackToUnavailableWithinTheTimeout() throws {
        #if os(Windows)
        return
        #else
        let directory = try privateDirectory(); defer { remove(directory) }
        let paths = try #require(SingleInstance.paths(id: "com.test.nolistener", directory: directory))
        let holder = try #require(holdLock(paths.lock), "could not hold the lock")
        defer { releaseLock(holder) }
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = finishes(within: 6) {
            forward("com.test.nolistener", directory, ["/tmp/x"], connect: .milliseconds(300))
        }
        let elapsed = start.duration(to: clock.now)
        let reported = try #require(outcome, "the claim did not return within the bound")
        #expect(failure(reported) == .noListener, "\(reported)")
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #endif
    }

    /// 8 (SN-E). Every malformed message is refused or cut off, nothing is
    /// delivered, the listener keeps serving, and a limit's value is exact.
    ///
    /// Mutations: raise each limit by one; replace the UTF-8 / NUL check.
    @Test(arguments: BadMessage.all)
    func aMalformedMessageIsRefusedAndTheListenerKeepsServing(_ bad: BadMessage) throws {
        #if os(Windows)
        return
        #else
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.bad", directory))
        let paths = try #require(SingleInstance.paths(id: "com.test.bad", directory: directory))
        let ack = rawSend(to: paths.socket, bad.bytes)
        #expect(ack != 0x06, "\(bad.name): the primary acknowledged a malformed message (\(String(describing: ack)))")
        #expect(primary.takeMessages().isEmpty, "\(bad.name): something was delivered")
        let good = forward("com.test.bad", directory, ["/tmp/after-\(bad.name.count)"])
        #expect(isForwarded(good), "\(bad.name): the listener stopped serving: \(good)")
        #expect(primary.takeMessages() == [["/tmp/after-\(bad.name.count)"]])
        #endif
    }

    /// 8b (SN-E). The limits' own values are accepted: 1024 strings, a 32768-byte
    /// string, a payload of exactly 1 MiB, an empty batch.
    ///
    /// Mutation: lower each limit by one.
    @Test func theLimitsAreExactlyTheDocumentedOnes() throws {
        #if os(Windows)
        return
        #else
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.limits", directory))
        let paths = try #require(SingleInstance.paths(id: "com.test.limits", directory: directory))
        let many = frame(payload: payload(strings: Array(repeating: [UInt8(ascii: "a")], count: 1024)))
        #expect(rawSend(to: paths.socket, many) == 0x06, "1024 strings")
        #expect(primary.takeMessages().first?.count == 1024)
        let longest = frame(payload: payload(strings: [Array(repeating: UInt8(ascii: "b"), count: 32768)]))
        #expect(rawSend(to: paths.socket, longest) == 0x06, "a 32768-byte string")
        #expect(primary.takeMessages().first?.first?.utf8.count == 32768)
        var strings = Array(repeating: Array(repeating: UInt8(ascii: "c"), count: 32768), count: 31)
        strings.append(Array(repeating: UInt8(ascii: "c"), count: 1_048_576 - 4 - 32 * 4 - 31 * 32768))
        let full = frame(payload: payload(strings: strings))
        try #require(full.count - 8 == 1_048_576, "the payload is exactly 1 MiB")
        #expect(rawSend(to: paths.socket, full) == 0x06, "a 1 MiB payload")
        #expect(primary.takeMessages().first?.count == 32)
        #expect(rawSend(to: paths.socket, frame(payload: payload(strings: []))) == 0x06, "an empty batch")
        #expect(primary.takeMessages() == [[]])
        #endif
    }

    /// 8c (SN-E, "before any allocation"). A declared length over the limit is
    /// refused from the header: the listener never allocates for it.
    ///
    /// Mutation: allocate the declared length before checking it.
    @Test func anOversizeLengthAllocatesNothing() throws {
        #if os(Windows)
        return
        #else
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.alloc", directory))
        let paths = try #require(SingleInstance.paths(id: "com.test.alloc", directory: directory))
        for declared in [1_048_577, 0xFFFF_FFFF] {
            let ack = rawSend(to: paths.socket, Array("MSI1".utf8) + be32(declared))
            #expect(ack != 0x06)
        }
        #expect(SingleInstance.payloadHighWaterMark <= 1_048_576, "\(SingleInstance.payloadHighWaterMark)")
        withExtendedLifetime(primary) {}
        #endif
    }

    #if !os(Windows)
    /// 9 (SN-E). A client that sends half a header and stops is cut off by the
    /// read timeout and does not block the next one.
    ///
    /// Mutation: no deadline.
    @Test func aStalledClientIsCutOffByTheReadTimeoutAndDoesNotBlockTheNextOne() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.stall", directory, read: .milliseconds(300)))
        let paths = try #require(SingleInstance.paths(id: "com.test.stall", directory: directory))
        let stalled = try #require(rawConnect(paths.socket))
        defer { close(stalled) }
        rawWrite(stalled, Array("MSI".utf8))
        let good = forward("com.test.stall", directory, ["/tmp/behind-the-stall"], read: .seconds(4))
        #expect(isForwarded(good), "\(good)")
        #expect(primary.takeMessages() == [["/tmp/behind-the-stall"]])
    }

    /// 10 (SN-E). A connection whose peer is not the expected user is closed
    /// unread: nothing is delivered and the sender is told nothing was taken.
    ///
    /// Mutation: skip the peer check.
    @Test func aPeerOfAnotherUserIsRejectedUnread() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.peer", directory, uid: geteuid() + 1))
        let outcome = forward("com.test.peer", directory, ["/tmp/stranger"])
        #expect(!isForwarded(outcome), "\(outcome)")
        #expect(primary.takeMessages().isEmpty)
        // The control: the right uid is served.
        let other = try privateDirectory(); defer { remove(other) }
        let served = try #require(becomePrimary("com.test.peer", other, uid: geteuid()))
        #expect(isForwarded(forward("com.test.peer", other, ["/tmp/me"])))
        #expect(served.takeMessages() == [["/tmp/me"]])
    }

    /// 11 (SN-C item 3). The directory is private and the socket and lock are
    /// 0600; a group-writable directory and a symlinked one are named, not used.
    ///
    /// Mutations: drop the `umask` section; skip `lstat`.
    @Test func theSocketAndItsDirectoryArePrivate() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.private", directory))
        let paths = try #require(SingleInstance.paths(id: "com.test.private", directory: directory))
        #expect((mode(of: directory) ?? 0) & 0o777 == 0o700)
        #expect((mode(of: paths.socket) ?? 0) & 0o777 == 0o600, "socket mode")
        #expect((mode(of: paths.lock) ?? 0) & 0o777 == 0o600, "lock mode")
        withExtendedLifetime(primary) {}

        let open = try privateDirectory(); defer { remove(open) }
        chmod(open, 0o777)
        #expect(failure(forward("com.test.private", open, [])) == .insecureDirectory)

        let link = directory + "-link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(failure(forward("com.test.private", link, [])) == .insecureDirectory)
    }
    #endif

    #if !os(Windows)
    /// 12 (SN-C item 3). A directory too long for `sun_path` is named, not truncated. Unix only: Windows' named pipe
    /// takes no directory.
    ///
    /// Mutation: truncate the path.
    @Test func anOverlongDirectoryIsNamedNotTruncated() {
        let directory = "/tmp/" + String(repeating: "d", count: 200)
        #expect(failure(forward("com.test.long", directory, [])) == .pathTooLong)
    }
    #endif

    /// 13 (SN-E). The 65th pending message is refused; a drained queue accepts again.
    ///
    /// Mutation: an unbounded queue.
    @Test func theSixtyFifthPendingMessageIsRefused() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.queue", directory))
        for index in 0..<64 {
            let outcome = forward("com.test.queue", directory, ["/tmp/q\(index)"])
            try #require(isForwarded(outcome), "message \(index): \(outcome)")
        }
        let refused = forward("com.test.queue", directory, ["/tmp/q64"])
        #expect(failure(refused) == .refused, "\(refused)")
        #expect(primary.takeMessages().count == 64)
        #expect(isForwarded(forward("com.test.queue", directory, ["/tmp/again"])), "a drained queue accepts again")
        #expect(primary.takeMessages() == [["/tmp/again"]])
    }

    /// 14 (SN-C item 1). Two ids are two independent primaries, each receiving only
    /// its own; an empty id is refused.
    ///
    /// Mutation: ignore the id in the hash.
    @Test func twoIdsAreTwoIndependentPrimaries() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let one = try #require(becomePrimary("com.test.one", directory))
        let two = try #require(becomePrimary("com.test.two", directory))
        try #require(isForwarded(forward("com.test.one", directory, ["/tmp/for-one"])))
        try #require(isForwarded(forward("com.test.two", directory, ["/tmp/for-two"])))
        #expect(one.takeMessages() == [["/tmp/for-one"]])
        #expect(two.takeMessages() == [["/tmp/for-two"]])
        #expect(failure(forward("", directory, [])) == .emptyID)
    }

    /// 14b (SN-C item 1). The names are `msui-<h>.lock`/`.sock`, `h` the first 16 hex
    /// digits of SHA-256 over the id's UTF-8 (the value is Python's `hashlib`'s).
    ///
    /// Mutation: change one round constant of the bridge's SHA-256.
    @Test func theNamesAreTheFirstSixteenHexDigitsOfTheIDsSHA256() throws {
        #if os(Windows)
        return
        #else
        let paths = try #require(SingleInstance.paths(id: "com.test.paths", directory: "/tmp/x"))
        #expect(paths.lock == "/tmp/x/msui-2041e8b5b209fc4a.lock", "\(paths.lock)")
        #expect(paths.socket == "/tmp/x/msui-2041e8b5b209fc4a.sock", "\(paths.socket)")
        #endif
    }

    /// 15 (SN-H). A delivered message raises the key window, else the lowest-id
    /// one; an empty forward raises too; `raisesWindow: false` and
    /// `hidesWindows` do not.
    ///
    /// Mutations: always raise; never raise.
    @MainActor
    @Test func aDeliveredMessageRaisesTheKeyWindowElseTheFirstAndNeverAHiddenOne() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.raise", directory))
        let platform = try makePlatform(for: primary, hidesWindows: false)
        platform.showWindow = { _ in true }   // nothing on screen
        var raised: [UInt32] = []
        platform.raiseWindow = { raised.append($0) }
        let first = try platform.openSDLWindow(title: "one", size: Size(width: Pixels(100), height: Pixels(80)))
        let second = try platform.openSDLWindow(title: "two", size: Size(width: Pixels(100), height: Pixels(80)))
        platform.pumpEvents()
        raised.removeAll()

        try #require(isForwarded(forward("com.test.raise", directory, ["/tmp/r1"])))
        platform.pumpEvents()
        #expect(raised == [min(first.id, second.id)], "no key window: the lowest id: \(raised)")

        var focus = MUIEvent(); focus.kind = UInt32(MUI_EVENT_FOCUS_GAINED); focus.window_id = second.id
        #expect(mui_push_event(&focus))
        platform.pumpEvents()
        raised.removeAll()
        try #require(isForwarded(forward("com.test.raise", directory, ["/tmp/r2"])))
        platform.pumpEvents()
        #expect(raised == [second.id], "the key window: \(raised)")

        raised.removeAll()
        try #require(isForwarded(forward("com.test.raise", directory, [])))
        platform.pumpEvents()
        #expect(raised == [second.id], "an empty forward raises too: \(raised)")

        // raisesWindow: false
        let quietDirectory = try privateDirectory(); defer { remove(quietDirectory) }
        let quiet = try #require(becomePrimary("com.test.quiet", quietDirectory, raises: false))
        let quietPlatform = try makePlatform(for: quiet, hidesWindows: false)
        quietPlatform.showWindow = { _ in true }
        var quietRaised: [UInt32] = []
        quietPlatform.raiseWindow = { quietRaised.append($0) }
        _ = try quietPlatform.openSDLWindow(title: "q", size: Size(width: Pixels(100), height: Pixels(80)))
        try #require(isForwarded(forward("com.test.quiet", quietDirectory, ["/tmp/q"])))
        quietPlatform.pumpEvents()
        #expect(quietRaised.isEmpty, "raisesWindow false: \(quietRaised)")

        // hidesWindows
        let hiddenDirectory = try privateDirectory(); defer { remove(hiddenDirectory) }
        let hiding = try #require(becomePrimary("com.test.hidden", hiddenDirectory))
        let hiddenPlatform = try makePlatform(for: hiding, hidesWindows: true)
        var hiddenRaised: [UInt32] = []
        hiddenPlatform.raiseWindow = { hiddenRaised.append($0) }
        _ = try hiddenPlatform.openSDLWindow(title: "h", size: Size(width: Pixels(100), height: Pixels(80)))
        try #require(isForwarded(forward("com.test.hidden", hiddenDirectory, ["/tmp/h"])))
        hiddenPlatform.pumpEvents()
        #expect(hiddenRaised.isEmpty, "hidesWindows: \(hiddenRaised)")
    }

    /// 16 (SN-G, SN-M item 2). A forward wakes the loop: the wake event is
    /// consumed by the pump (counted, not timed) and the batch is delivered in
    /// `run(maxIterations: 1)`.
    ///
    /// Mutation: no `SDL_PushEvent` (the count stays 0).
    @MainActor
    @Test func theWakeEventEndsABlockedWaitPromptly() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.wake", directory))
        let platform = try makePlatform(for: primary)
        platform.showWindow = { _ in true }
        _ = try platform.openSDLWindow(title: "wake", size: Size(width: Pixels(100), height: Pixels(80)))
        platform.pumpEvents()
        var opened: [[String]] = []
        platform.onOpenURLs = { opened.append($0) }
        let before = SingleInstance.wakesConsumed
        try #require(isForwarded(forward("com.test.wake", directory, ["/tmp/wake"])))
        platform.run(maxIterations: 1)
        #expect(opened == [["file:///tmp/wake"]], "\(opened)")
        #expect(SingleInstance.wakesConsumed - before == 1, "the pump consumed the wake event")
    }

    /// 17 (SN-G). A window-0 drop and a forwarded batch are two batches, never one
    /// accumulator: a forward between the drop's files and its `DROP_COMPLETE`
    /// does not join it.
    ///
    /// Mutation: share one accumulator.
    @MainActor
    @Test func dropDeliveryAndForwardDeliveryDoNotInterleaveABatch() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let primary = try #require(becomePrimary("com.test.interleave", directory))
        let platform = try makePlatform(for: primary)
        platform.pumpEvents()
        var opened: [[String]] = []
        platform.onOpenURLs = { opened.append($0) }
        pushDrop(mui_sdl_event_drop_file, 0, "/tmp/d1")
        pushDrop(mui_sdl_event_drop_file, 0, "/tmp/d2")
        try #require(isForwarded(forward("com.test.interleave", directory, ["/tmp/f1"])))
        pushDrop(mui_sdl_event_drop_complete, 0)
        platform.pumpEvents()
        let sorted = opened.sorted { ($0.first ?? "") < ($1.first ?? "") }
        #expect(sorted == [["file:///tmp/d1", "file:///tmp/d2"], ["file:///tmp/f1"]], "\(opened)")
    }

    /// 18 (SN-J). The claim is released with the object: a fresh claim is primary
    /// and the socket file is gone in between.
    ///
    /// Mutation: no unlink in `deinit` (the file stays).
    @Test func theClaimIsReleasedWhenThePlatformGoesAway() throws {
        let directory = try privateDirectory(); defer { remove(directory) }
        let paths = try #require(SingleInstance.paths(id: "com.test.release", directory: directory))
        var primary: SingleInstance? = becomePrimary("com.test.release", directory)
        try #require(primary != nil)
        #expect(FileManager.default.fileExists(atPath: paths.socket))
        primary = nil
        #expect(!FileManager.default.fileExists(atPath: paths.socket), "the socket file goes with the claim")
        let fresh = try #require(becomePrimary("com.test.release", directory))
        withExtendedLifetime(fresh) {}
        _ = primary
    }
}

// MARK: - Malformed messages

struct BadMessage: Sendable, CustomTestStringConvertible {
    let name: String
    let bytes: [UInt8]
    var testDescription: String { name }

    static var all: [BadMessage] {
        let one = payload(strings: [Array("ok".utf8)])
        return [
            BadMessage(name: "bad magic", bytes: frame(payload: one, magic: "MSI2")),
            BadMessage(name: "truncated count", bytes: frame(payload: [0, 0])),
            BadMessage(name: "truncated string", bytes: frame(payload: be32(1) + be32(10) + Array("abc".utf8))),
            BadMessage(name: "length beyond the payload",
                       bytes: frame(payload: be32(1) + be32(100) + Array("abc".utf8)) + Array(repeating: 0x61, count: 200)),
            BadMessage(name: "payload one over 1 MiB", bytes: Array("MSI1".utf8) + be32(1_048_577)),
            BadMessage(name: "count 1025",
                       bytes: frame(payload: payload(strings: Array(repeating: [0x61], count: 1025)))),
            BadMessage(name: "string 32769",
                       bytes: frame(payload: payload(strings: [Array(repeating: 0x61, count: 32769)]))),
            BadMessage(name: "ill-formed UTF-8", bytes: frame(payload: payload(strings: [[0x61, 0xFF, 0xFE]]))),
            BadMessage(name: "overlong UTF-8", bytes: frame(payload: payload(strings: [[0xC0, 0xAF]]))),
            BadMessage(name: "embedded NUL", bytes: frame(payload: payload(strings: [[0x61, 0x00, 0x62]]))),
            BadMessage(name: "empty string", bytes: frame(payload: payload(strings: [[]]))),
            BadMessage(name: "bytes left in the payload", bytes: frame(payload: one + [1, 2, 3])),
            BadMessage(name: "count above the strings", bytes: frame(payload: payload(strings: [[0x61]], declaredCount: 2))),
        ]
    }
}

// MARK: - The subprocess

private func checkExecutable() -> URL? {
    var directories: [URL] = []
    if let main = Bundle.main.executableURL { directories.append(main.deletingLastPathComponent()) }
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        directories.append(URL(fileURLWithPath: bundle.bundlePath).deletingLastPathComponent())
    }
    for argument in CommandLine.arguments where argument.contains(".xctest") {
        var url = URL(fileURLWithPath: argument)
        while url.pathComponents.count > 1, !url.lastPathComponent.hasSuffix(".xctest") { url.deleteLastPathComponent() }
        directories.append(url.deletingLastPathComponent())
    }
    #if os(Windows)
    let name = "SingleInstanceCheck.exe"
    #else
    let name = "SingleInstanceCheck"
    #endif
    for directory in directories {
        let candidate = directory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    return nil
}

/// The first line the subprocess prints (blocking: it prints once ready).
private func readLine(from handle: FileHandle) -> String {
    var bytes: [UInt8] = []
    while let chunk = try? handle.read(upToCount: 1), let byte = chunk.first, byte != 10 { bytes.append(byte) }
    return String(decoding: bytes, as: UTF8.self)
}

#if !os(Windows)
/// Holds the lock file's `flock` as a second process would; `nil` on failure.
private func holdLock(_ path: String) -> Int32? {
    let fd = open(path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { return nil }
    return fd
}
private func releaseLock(_ fd: Int32) { close(fd) }
#else
private func holdLock(_ path: String) -> Int32? { nil }
private func releaseLock(_ fd: Int32) {}
#endif
