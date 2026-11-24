@testable import MetalUI
import MetalUITesting
import Testing

// G47 / G33 (c): the process-wide `IdentityInterner` behind a scrolling table. A table realises about 28 rows of fresh ids per step,
// and a million-row table never repeats a row, so an interner that only ever added would grow with the scroll distance.

/// **I-T1** Scrolling a million-row table across many distinct rows mints far more ids than the interner holds: the table stays within
/// a few windows' worth. Mutation: `sweep()` returns at once (nothing is ever dropped); then `count` equals `minted` and the bound fails.
@Test @MainActor func scrollingAMillionRowTableKeepsTheInternTableBounded() async throws {
    let w = try tableFixture(rows: 1_000_000, columns: 20)
    try await scrollTable(w, x: 0, y: 12000)
    let interner = IdentityInterner.shared
    let mintedBefore = interner.minted
    let windowIDs = interner.count
    var peak = 0
    var samples: [Int] = []
    let steps = 300
    for _ in 0..<steps {
        // 2400 points is 100 rows: no step re-realises a row the one before it built.
        w.scroll(at: Point(x: Pixels(400), y: Pixels(300)), byDeltaX: 0, deltaY: -2400)
        try await w.runUntilIdle()
        peak = max(peak, interner.count)
        samples.append(interner.count)
    }
    let minted = interner.minted - mintedBefore
    print("INTERN window \(windowIDs) minted \(minted) peak \(peak) samples \(samples.enumerated().filter { $0.offset % 10 == 0 }.map(\.element))")
    #expect(minted > 8 * (peak + 1), "the scroll must mint far more ids than the table may hold: minted \(minted), peak \(peak)")
    // One window is `windowIDs` (or fewer); the sweep runs every 64 builds or when the table doubles, so the peak is a small multiple.
    #expect(peak <= 8 * max(windowIDs, 1_024), "peak \(peak) ids after minting \(minted); a window is \(windowIDs)")
}
