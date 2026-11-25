import Foundation
import Testing
@testable import MetalUITerminal

/// Terminal phase 6 (`TRM-BK` item 3): a seeded fuzz of the emulator as a whole (parser, screen, scrollback, reflow),
/// resizes and viewport scrolls interleaved with random bytes, escape fragments and well-formed sequences. It must never
/// trap and must keep the invariants after every step. `ParserFuzzTests` (no resizes) is the older, narrower arm.
/// A short run is always on (2 000 iterations); `METALUI_RUN_TERMINAL_FUZZ=1 swift test --filter FuzzSoak` runs
/// 400 000 over several seeds. Mutation: `resize` leaves the cursor unclamped (the cursor invariant fails within
/// the first hundred iterations); the row count invariant is shown by returning `rowCount + 1` rows from `screen`.
@Suite struct FuzzSoakTests {
    private static let longRun = ProcessInfo.processInfo.environment["METALUI_RUN_TERMINAL_FUZZ"] == "1"

    /// Escape-sequence fragments, whole and torn, to splice between random bytes.
    private static let fragments: [[UInt8]] = [
        "\u{1B}[", "\u{1B}]0;title\u{07}", "\u{1B}]8;;http://x\u{1B}\\", "\u{1B}P1$q", "\u{1B}P", "\u{1B}\\", "\u{1B}_", "\u{1B}]52;c;",
        "\u{1B}[?1049h", "\u{1B}[?1049l", "\u{1B}[?47h", "\u{1B}[2J", "\u{1B}[3J", "\u{1B}[H", "\u{1B}[999;999H", "\u{1B}[5;2r",
        "\u{1B}[r", "\u{1B}[?6h", "\u{1B}[3L", "\u{1B}[2M", "\u{1B}[4@", "\u{1B}[9P", "\u{1B}[3S", "\u{1B}[3T", "\u{1B}[38;2;1;2;3m",
        "\u{1B}[38:2::9:8:7m", "\u{1B}[0m", "\u{1B}[1;4:3m", "\u{1B}7", "\u{1B}8", "\u{1B}c", "\u{1B}#8", "\u{1B}(0", "\u{1B}(B",
        "\u{1B}[?7l", "\u{1B}[?7h", "\u{1B}[4h", "\u{1B}[4l", "\u{1B}[6n", "\u{1B}[c", "\r\n", "\n\n\n", "\t\t", "\u{08}\u{08}",
        "漢字", "e\u{301}", "😀", "\u{200D}", "日本語のテキスト", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ].map { Array($0.utf8) }

    private func step(_ e: TerminalEmulator, _ rng: inout SeededRandom) {
        switch Int.random(in: 0..<20, using: &rng) {
        case 0..<7:
            e.feed(FuzzSupport.bytes(count: Int.random(in: 1...120, using: &rng), using: &rng))
        case 7..<13:
            var bytes: [UInt8] = []
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                guard let fragment = Self.fragments.randomElement(using: &rng) else {
                    preconditionFailure("the fragment list is not empty")
                }
                bytes += fragment
            }
            e.feed(bytes)
        case 13..<15:
            e.feed((0..<Int.random(in: 1...80, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        case 15..<18:
            e.resize(cols: Int.random(in: 1...40, using: &rng), rows: Int.random(in: 1...14, using: &rng))
        case 18:
            e.scrollViewport(toOffset: Int.random(in: 0...20, using: &rng))
        default:
            _ = e.drainEvents()
        }
    }

    private func check(_ e: TerminalEmulator, _ label: String) {
        let snap = e.publishSnapshot()
        let c = snap.cursor
        #expect(e.columnCount >= 1 && e.rowCount >= 1, "\(label)")
        // Scrolled back, the cursor's row is the live row plus the offset and the cursor is not visible (by design).
        #expect(c.row >= 0 && c.col >= 0 && c.col < e.columnCount && (c.row < e.rowCount || (snap.viewportOffset > 0 && !c.visible)),
                "\(label): cursor \(c) outside \(e.columnCount)x\(e.rowCount), offset \(snap.viewportOffset)")
        #expect(snap.viewportOffset == 0 || snap.viewportOffset <= e.scrollbackCount, "\(label): offset \(snap.viewportOffset)")
        #expect(e.screen.count == e.rowCount, "\(label): \(e.screen.count) rows for \(e.rowCount)")
        #expect(e.offscreen.count == e.rowCount, "\(label)")
        #expect(e.screen.allSatisfy { $0.usedColumns <= e.columnCount }, "\(label)")
        #expect(e.scrollbackCount <= e.scrollback.capacity, "\(label)")
        #expect(e.regionTop >= 0 && e.regionBottom < e.rowCount, "\(label): region \(e.regionTop)...\(e.regionBottom)")
        #expect(e.tabStops.count == e.columnCount, "\(label)")
        #expect(snap.damagedRows.allSatisfy { $0.index >= 0 && $0.index < e.rowCount }, "\(label)")
        #expect(e.events.count <= 1024, "\(label)")
        #expect(e.rowText(e.firstRow + e.scrollbackCount + e.rowCount - 1) != nil, "\(label): the last row is addressable")
    }

    private func soak(seed: UInt64, iterations: Int) {
        var rng = SeededRandom(seed: seed)
        let e = TerminalEmulator(cols: Int.random(in: 1...30, using: &rng), rows: Int.random(in: 1...10, using: &rng),
                                 scrollback: Int.random(in: 0...50, using: &rng), payloadCap: Int.random(in: 0...64, using: &rng))
        for i in 0..<iterations {
            step(e, &rng)
            check(e, "seed \(seed) iteration \(i)")
        }
    }

    @Test func twoThousandIterationsKeepEveryInvariant() {
        for seed in 1...4 as ClosedRange<UInt64> { soak(seed: seed, iterations: 500) }
    }

    @Test(.enabled(if: FuzzSoakTests.longRun)) func theLongSoak() {
        for seed in 100..<140 as Range<UInt64> { soak(seed: seed, iterations: 10_000) }
    }
}
