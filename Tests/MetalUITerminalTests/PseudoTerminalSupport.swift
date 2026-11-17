import Dispatch
import Foundation
@testable import MetalUITerminal

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

#if !os(Windows)
/// Both spawn mechanisms run every behaviour test: `posix_spawn` where the platform has it, and the fork path.
let mechanisms: [PseudoTerminal.Mechanism] = [.automatic, .fork]

let testEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]

func shell(_ script: String, cols: Int = 80, rows: Int = 24, cwd: String = "/",
           env: [String: String] = testEnvironment,
           mechanism: PseudoTerminal.Mechanism = .automatic) throws -> PseudoTerminal {
    try PseudoTerminal.spawn(executable: "/bin/sh", argv: ["sh", "-c", script], env: env, cwd: cwd,
                             size: TerminalSize(cols: cols, rows: rows), mechanism: mechanism)
}

#endif

/// Reads a pty on its own serial queue and lets a test wait, with a bound, for what it expects.
final class Capture: @unchecked Sendable {
    let pty: PseudoTerminal
    let queue = DispatchQueue(label: "test.capture")
    private let condition = NSCondition()
    private var bytes: [UInt8] = []
    private var ended = false
    private var total = 0
    private var sum: UInt64 = 0
    private let keep: Bool
    private var _callbacks = 0

    /// `keep: false` counts and sums instead of storing, for floods.
    init(_ pty: PseudoTerminal, keep: Bool = true) {
        self.pty = pty
        self.keep = keep
        pty.onReadable(queue: queue) { [self] in drain() }
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        condition.lock()
        _callbacks += 1
        condition.unlock()
        while true {
            let n = buffer.withUnsafeMutableBytes { pty.read(into: $0) }
            condition.lock()
            if n > 0 {
                total += n
                if keep { bytes.append(contentsOf: buffer[0..<n]) }
                buffer.withUnsafeBufferPointer { p in
                    var local: UInt64 = 0
                    for i in 0..<n { local &+= UInt64(p[i]) }
                    sum &+= local
                }
            } else if n < 0 {
                ended = true
            }
            condition.broadcast()
            condition.unlock()
            if n <= 0 { break }
        }
    }

    var text: String {
        condition.lock()
        defer { condition.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
    var data: [UInt8] { condition.lock(); defer { condition.unlock() }; return bytes }
    var count: Int { condition.lock(); defer { condition.unlock() }; return total }
    var checksum: UInt64 { condition.lock(); defer { condition.unlock() }; return sum }
    var hitEnd: Bool { condition.lock(); defer { condition.unlock() }; return ended }
    var callbacks: Int { condition.lock(); defer { condition.unlock() }; return _callbacks }

    /// Waits until `predicate` holds, at most `timeout` seconds. Returns whether it held.
    @discardableResult
    func wait(timeout: TimeInterval = 30, until predicate: @Sendable (_ text: String, _ count: Int, _ ended: Bool) -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            let text = keep ? String(decoding: bytes, as: UTF8.self) : ""
            if predicate(text, total, ended) { return true }
            if !condition.wait(until: deadline) { return predicate(text, total, ended) }
        }
    }

    func waitFor(_ needle: String, timeout: TimeInterval = 30) -> Bool {
        wait(timeout: timeout) { text, _, _ in text.contains(needle) }
    }
    func waitForEnd(timeout: TimeInterval = 30) -> Bool { wait(timeout: timeout) { _, _, ended in ended } }
}

private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func resume(_ value: T?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

/// The child's exit status, or nil when it did not end within `timeout` seconds.
func exitStatus(of pty: PseudoTerminal, timeout: Double = 30) async -> PseudoTerminal.ExitStatus? {
    await withCheckedContinuation { (continuation: CheckedContinuation<PseudoTerminal.ExitStatus?, Never>) in
        let once = Once(continuation)
        Task { once.resume(await pty.exitStatus) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
    }
}

#if !os(Windows)
/// POSIX `cksum`'s CRC over `bytes` (what `cksum` prints first).
func posixCRC(_ bytes: [UInt8]) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i) << 24
        for _ in 0..<8 { c = (c & 0x8000_0000) != 0 ? (c << 1) ^ 0x04C1_1DB7 : c << 1 }
        table[i] = c
    }
    var crc: UInt32 = 0
    for b in bytes { crc = (crc << 8) ^ table[Int((crc >> 24) ^ UInt32(b)) & 0xff] }
    var length = bytes.count
    while length != 0 {
        crc = (crc << 8) ^ table[Int((crc >> 24) ^ UInt32(length & 0xff)) & 0xff]
        length >>= 8
    }
    return ~crc
}

#endif

/// Always runs: a test that fails mid-way must not leave a child behind.
func finish(_ pty: PseudoTerminal) {
    pty.signalGroup(.kill)
    pty.close()
}
