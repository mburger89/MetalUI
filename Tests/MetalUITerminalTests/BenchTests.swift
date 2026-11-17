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

    /// Reflow of 10,000 scrollback rows of 120 columns (`TRM-AP`; proposed bound 50 ms). Soft-wrapped and hard
    /// lines mixed, a few with colour and wide characters.
    @Test(.enabled(if: TerminalBench.enabled)) func reflowOfTenThousandScrollbackRows() {
        let emulator = TerminalEmulator(cols: 120, rows: 40, scrollback: 20_000)
        var rng = SystemRandomNumberGenerator()
        var text = ""
        var line = 0
        while true {
            let length = [20, 90, 119, 120, 121, 200, 240, 300].randomElement(using: &rng)!
            var body = String((0..<length).map { _ in "abcdefghijklmnopqrstuvwxyz 0123456789".randomElement(using: &rng)! })
            if line % 7 == 0 { body = "\u{1B}[31m" + body + "\u{1B}[0m日本" }
            text += body + "\r\n"
            line += 1
            if line % 500 == 0 {
                emulator.feed(Array(text.utf8))
                text = ""
                if emulator.firstRow + 10_000 < emulator.firstRow + 10_040, emulator.rowText(emulator.firstRow + 10_000) != nil { break }
            }
        }
        var worst = 0.0
        var best = Double.infinity
        let clock = ContinuousClock()
        for _ in 0..<5 {
            for width in [80, 120, 200, 120] {
                let elapsed = clock.measure { emulator.resize(cols: width, rows: 40) }
                let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                worst = max(worst, ms)
                best = min(best, ms)
            }
        }
        var rows = 0
        var row = emulator.firstRow
        while emulator.rowText(row) != nil { rows += 1; row += 1 }
        print("terminal bench: reflow of \(rows) rows (120 columns at the start): best \(Int(best * 10) / 10) ms, worst \(Int(worst * 10) / 10) ms over 80/120/200/120 columns")
        #expect(worst < 50, "the proposed bound")
    }
}
