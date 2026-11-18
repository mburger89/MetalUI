import Foundation
import Testing
@testable import MetalUITerminal
#if canImport(Darwin)
import MetalUITestSupport
#endif

// Terminal phase 6 (`TRM-BK`): the counted guards of the emulator core. No clock; every number is a count.
// Mutation (each shown red once, see the record): listed on each test.

/// **1** (`TRM-BK` item 1) Snapshot cost is O(damaged rows): in a 200 x 60 grid of coloured text, one changed row
/// publishes one damaged row, and every other row keeps its storage by identity, across many publishes.
/// Mutation: `publishSnapshot` lists every row (damage count 60), or copies a row it lists as untouched
/// (identity differs).
@Suite struct SnapshotCostTests {
    @Test func oneChangedRowOfSixtyPublishesOneRowAndSharesTheRest() {
        let e = TerminalEmulator(cols: 200, rows: 60)
        var screen = ""
        for r in 0..<60 { screen += "\u{1B}[3\(r % 8)m" + String(repeating: Character(UnicodeScalar(UInt8(33 + r % 90))), count: 190) + "\u{1B}[0m\r\n" }
        e.feed(screen)
        #expect(e.publishSnapshot().damagedRows.count == 60)
        #expect(e.publishSnapshot().damagedRows.isEmpty, "nothing changed, nothing listed")
        let before = e.screen.map { $0.storageAddress }
        #expect(before.allSatisfy { $0 != nil })
        for i in 0..<20 {
            let target = (i * 7) % 59 + 1
            e.feed("\u{1B}[\(target + 1);1H#")
            let snap = e.publishSnapshot()
            #expect(snap.damagedRows.map(\.index) == [target], "\(snap.damagedRows.map(\.index))")
            for r in 0..<60 where r != target { #expect(e.screen[r].storageAddress == before[r], "row \(r) copied") }
            #expect(snap.damagedRows[0].row.storageAddress == e.screen[target].storageAddress, "the listed row is the live one, not a copy")
            #expect(e.screen[target].storageAddress != nil)
        }
    }
}

#if canImport(Darwin) && !DEBUG
/// **2** (`TRM-BK` item 1) The steady-state `feed` of plain text allocates nothing: 2 000 lines of plain text written over
/// one row (no scroll) make at most 2 heap allocations in all on the calling thread (a constant, not per line; the
/// thread-filtered counter of `PA-J`; macOS only and release only, the pattern of `aWarmAsciiLookupAllocatesNothing`: a debug
/// build allocates in slice and iterator plumbing, and how much depends on the toolchain). A scrolling feed allocates
/// for the new scrollback row and for nothing else: at most 1 per line. A line with four SGR sequences allocates nothing per
/// line either (`TRM-BL`: it was 8 001 per 2 000 lines, one per sequence, from `setAttributes` rebuilding the row's spans;
/// now 4 in all, a constant), pinned at 8 in all. Run with `swift test -c release --filter FeedAllocationTests`.
/// Mutation: `feed` copies its input into an array (shown: plain 2 001, sgr 10 001, scroll 4 000; the bounds fail on each); one
/// allocation per CSI (`sgr` copying its parameter array) fails the SGR bound.
@Suite struct FeedAllocationTests {
    @Test func aSteadyFeedAllocatesNothingAndAScrollAllocatesOnlyItsRow() throws {
        let e = TerminalEmulator(cols: 80, rows: 24, scrollback: 100)
        let line = Array((String(repeating: "The quick brown fox jumps over the lazy dog 0123456789. ", count: 2).prefix(79) + "\r").utf8)
        let sgr = Array("\u{1B}[31mred\u{1B}[0m plain \u{1B}[1;32mbold green\u{1B}[0m tail text here\r".utf8)
        let scrolling = Array((String(repeating: "x", count: 79) + "\r\n").utf8)
        for _ in 0..<300 { e.feed(line); e.feed(sgr); e.feed(scrolling) }       // warm: every array at its final capacity
        let plain = try #require(countAllocations {
            line.withUnsafeBytes { raw in for _ in 0..<2000 { e.feed(raw) } }
        })
        let coloured = try #require(countAllocations {
            sgr.withUnsafeBytes { raw in for _ in 0..<2000 { e.feed(raw) } }
        })
        let scroll = try #require(countAllocations {
            scrolling.withUnsafeBytes { raw in for _ in 0..<2000 { e.feed(raw) } }
        })
        print("feed allocations over 2000 lines: plain \(plain), sgr \(coloured), scrolling \(scroll)")
        #expect(plain <= 2, "\(plain) allocations over 2000 plain lines")
        #expect(coloured <= 8, "\(coloured) allocations over 2000 SGR lines")
        #expect(scroll <= 2000 + 2, "\(scroll) allocations over 2000 scrolling lines")
    }
}
#endif
