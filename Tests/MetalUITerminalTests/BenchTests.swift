import Foundation
import Testing
import MetalUITerminal

/// Gated bench (spec section 7): plain-ASCII parse throughput. Run in release:
/// `METALUI_RUN_TERMINAL_BENCH=1 swift test -c release --filter TerminalBench`.
/// Uses the public API only, so it works without `-enable-testing`.
@Suite struct TerminalBench {
    private static let enabled = ProcessInfo.processInfo.environment["METALUI_RUN_TERMINAL_BENCH"] == "1"

    @Test(.enabled(if: TerminalBench.enabled)) func plainASCIIParseThroughput() {
        let line = Array(String(repeating: "The quick brown fox jumps over the lazy dog 0123456789. ", count: 2).utf8.prefix(79)) + [0x0D, 0x0A]
        var chunk: [UInt8] = []
        while chunk.count < 64 * 1024 { chunk += line }
        let totalBytes = 128 * 1024 * 1024
        let iterations = totalBytes / chunk.count
        let emulator = TerminalEmulator(cols: 80, rows: 24)
        var best = 0.0
        for _ in 0..<4 {
            let clock = ContinuousClock()
            let elapsed = clock.measure {
                chunk.withUnsafeBytes { buffer in
                    for _ in 0..<iterations { emulator.feed(buffer) }
                }
            }
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            best = max(best, Double(chunk.count * iterations) / seconds / 1_000_000)
        }
        print("terminal bench: plain ASCII parse \(Int(best)) MB/s (80-column lines, 64 KiB chunks, best of 4)")
        #expect(best > 20, "a floor far below the 300 MB/s target, so a broken build still fails")
        #expect(emulator.rowText(emulator.firstRow) != nil)
    }
}
