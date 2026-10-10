import MetalUI
import MetalUITesting
import Testing

// Spec §4.1 tests 1.25–1.27 (MG-12 item 3): laid-out frames by `.id`, gpui's
// `debug_bounds` (ruling `HT-G` item 2) — window content space, logical
// points, from the last build. Literals are derived from the stack rule
// before the run: `HStack(spacing: 0)` of fixed boxes answers the sum of the
// widths and the tallest height, and the root is centred at its answer in the
// 400 × 300 window (`CN-J`).

/// 1.25 — 120 + 80 = 200 wide, 50 tall, centred: origin ((400 − 200) / 2,
/// (300 − 50) / 2) = (100, 125); `a` at (100, 125, 120, 50) and `b` at
/// (220, 125, 80, 50). Mutation: `testingRecordsElementBounds` not set.
@Test @MainActor func frameOfIDReadsLaidOutRects() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Box().frame(width: Pixels(120), height: Pixels(50)).id("a")
            Box().frame(width: Pixels(80), height: Pixels(50)).id("b")
        }
    }
    #expect(try window.frame(ofID: "a") == rect(100, 125, 120, 50))
    #expect(try window.frame(ofID: "b") == rect(220, 125, 80, 50))
    #expect(throws: TestHarnessError.noElement("id \"c\"")) { try window.frame(ofID: "c") }
}

/// 1.26 — one name under two parents is two elements: `frame(ofID:)` throws
/// ambiguous naming the count and `frames(ofID:)` lists both, top to bottom
/// then left to right. The `HStack` of two 40 × 40 columns is 80 × 40 at
/// (160, 130). Mutation: `frames(ofID:)` returns the first only.
@Test @MainActor func frameOfAnAmbiguousIDThrowsAndFramesOfIDListsBoth() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            VStack { Box().frame(width: Pixels(40), height: Pixels(40)).id("x") }
            VStack { Box().frame(width: Pixels(40), height: Pixels(40)).id("x") }
        }
    }
    #expect(throws: TestHarnessError.ambiguous("id \"x\"", count: 2)) { try window.frame(ofID: "x") }
    #expect(try window.frames(ofID: "x") == [rect(160, 130, 40, 40), rect(200, 130, 40, 40)])
}

/// 1.27 — a window opened with `recordsLayout: false` (a benchmark's) records
/// nothing and says so. Mutation: always record.
@Test @MainActor func aWindowNotRecordingLayoutThrowsNotRecorded() throws {
    let window = try harnessWindow(recordsLayout: false) {
        Box().frame(width: Pixels(40), height: Pixels(40)).id("a")
    }
    #expect(throws: TestHarnessError.notRecorded("layout")) { try window.frame(ofID: "a") }
}
