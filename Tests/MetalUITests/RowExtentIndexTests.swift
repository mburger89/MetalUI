import Testing
@testable import MetalUI

// Variable-height `List`, lane 1 (rulings `VL-C`, `VL-D`, `VL-E`, `VL-O`):
// `RowExtentIndex`, the per-list height cache — two Fenwick trees (measured
// heights, measured count) so `offset(of: i) = measuredSum(i) + (i −
// measuredCount(i)) × estimate`. Pure: no window, no frame. Every literal is
// derived in the test's comment before the run; heights are small integers,
// so every sum is exact in `Double` and `==` is the honest comparison.
//
// Red-before: against the stub (every query 0, `record` a no-op) each test
// fails on its first `#expect` (record §82 §3).

/// **1.1 (`VL-C`, the fallback).** Nothing measured and no declared estimate:
/// every row counts 24 — `offset(of: 5)` = 5 × 24 = 120, `extent(at: 2)` = 24.
/// Mutation: the fallback 24 → 28 (reads 140 / 28).
@Test func anIndexWithNothingMeasuredEstimatesEveryRowAtTwentyFour() {
    let index = RowExtentIndex<String>(count: 5, declaredEstimate: nil)
    #expect(index.estimate == 24)
    #expect(index.offset(of: 5) == 120)
    #expect(index.extent(at: 2) == 24)
    #expect(index.totalExtent == 120)
    #expect(!index.isMeasured(2))
}

/// **1.2 (`VL-C`, precedence).** Declared 40, rows 0 and 1 measured 10 and 30
/// (mean 20): the unmeasured rows 2 and 3 count 40 — `offset(of: 4)` = 10 + 30
/// + 40 + 40 = 120. Mutation: the mean wins over the declared estimate (reads
/// 20 and 80).
@Test func aDeclaredEstimateWinsOverTheRunningMean() {
    let index = RowExtentIndex<String>(count: 4, declaredEstimate: 40)
    index.record(10, at: 0, id: "a")
    index.record(30, at: 1, id: "b")
    #expect(index.estimate == 40)
    #expect(index.extent(at: 2) == 40)
    #expect(index.offset(of: 4) == 120)
}

/// **1.3 (`VL-C`, divergence 147's index pin).** No declared estimate, count
/// 4, rows 0 and 1 measured 10 and 30: the mean is 20, so the offsets are 0,
/// 10, 40, 60 and the total 80. Mutation: the estimate is the last recorded
/// height (30: offsets 0, 10, 40, 70, total 100).
@Test func theRunningMeanEstimatesUnmeasuredRows() {
    let index = RowExtentIndex<String>(count: 4, declaredEstimate: nil)
    index.record(10, at: 0, id: "a")
    index.record(30, at: 1, id: "b")
    #expect(index.estimate == 20)
    #expect((0...3).map { index.offset(of: $0) } == [0, 10, 40, 60])
    #expect(index.totalExtent == 80)
}

/// **1.4 (`VL-D`).** 1000 rows, declared estimate 24 (so the naive sum is
/// exact whatever is measured); 1500 records at indices drawn from a fixed
/// linear-congruential sequence (some re-records), heights 1…100. Every
/// `offset(of: 0...1000)` equals the naive running sum over a parallel array.
/// Mutation: the Fenwick update stride `i += i & -i` → `i += 1` (each update
/// then touches every later node — the prefix query overcounts).
@Test func prefixOffsetsMatchANaiveSumAfterRecordsInAnyOrder() {
    let count = 1000
    let index = RowExtentIndex<Int>(count: count, declaredEstimate: 24)
    var naive = Array(repeating: 24.0, count: count)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    for _ in 0..<1500 {
        let row = Int(next() % UInt64(count))
        let height = Double(next() % 100 + 1)
        index.record(height, at: row, id: row)
        naive[row] = height
    }
    var sum = 0.0
    var mismatches: [Int] = []
    for i in 0...count {
        if index.offset(of: i) != sum { mismatches.append(i) }
        if i < count { sum += naive[i] }
    }
    #expect(mismatches.isEmpty, "first mismatches: \(mismatches.prefix(5))")
    #expect(index.totalExtent == sum)
}

/// **1.5 (`VL-D`).** Rows 10, 20, 30 (offsets 0, 10, 30; total 60): a `y` on a
/// boundary belongs to the row below it (10 → row 1, 30 → row 2); inside a span
/// → that row (5 → 0, 29.5 → 1, 59 → 2); past the end → the last row (60,
/// 1000 → 2); negative → 0; an empty index → 0. Mutation: the descent's `<=` →
/// `<` (10 → 0, 30 → 1).
@Test func indexContainingAnOffsetFindsTheRowWhoseSpanHoldsIt() {
    let index = RowExtentIndex<String>(count: 3, declaredEstimate: nil)
    index.record(10, at: 0, id: "a")
    index.record(20, at: 1, id: "b")
    index.record(30, at: 2, id: "c")
    let probes: [(Double, Int)] = [(0, 0), (5, 0), (10, 1), (29.5, 1), (30, 2), (59, 2),
                                   (60, 2), (1000, 2), (-5, 0)]
    for (y, expected) in probes {
        #expect(index.index(containing: y) == expected, "y \(y)")
    }
    #expect(RowExtentIndex<String>(count: 0, declaredEstimate: nil).index(containing: 10) == 0)
}

/// **1.6 (`VL-E` item 1).** Declared 24, count 4; row 2 recorded 10, then 30:
/// the second replaces the first — `offset(of: 3)` = 24 + 24 + 30 = 78,
/// `offset(of: 4)` = 102. Mutation: drop the subtract-old step (reads 88 / 112).
@Test func reRecordingARowReplacesItsHeight() {
    let index = RowExtentIndex<String>(count: 4, declaredEstimate: 24)
    index.record(10, at: 2, id: "c")
    index.record(30, at: 2, id: "c")
    #expect(index.offset(of: 3) == 78)
    #expect(index.offset(of: 4) == 102)
    #expect(index.extent(at: 2) == 30)
}

/// **1.7 (`VL-E` item 2, `VL-O` item 2).** Count 3, rows 0 and 1 measured 10
/// and 50 (mean 30, total 10 + 50 + 30 = 90). `forgetMeasurements(width: 200)`
/// returns every row to the fallback (estimate 24, total 72, nothing
/// measured), stores the width, and keeps the ids. Mutations: (a) clear the
/// sums but not the counts (total reads 24); (b) clear the ids too (`id(at:)`
/// reads nil).
@Test func forgettingMeasurementsReturnsEveryRowToTheEstimate() {
    let index = RowExtentIndex<String>(count: 3, declaredEstimate: nil)
    index.record(10, at: 0, id: "a")
    index.record(50, at: 1, id: "b")
    #expect(index.totalExtent == 90, "control: measured before forgetting")
    index.forgetMeasurements(width: 200)
    #expect(index.width == 200)
    #expect(index.estimate == 24)
    #expect(index.totalExtent == 72)
    #expect(!index.isMeasured(0) && !index.isMeasured(1))
    #expect(index.id(at: 0) == "a")
    #expect(index.id(at: 1) == "b")
}

/// **1.8 (`VL-E` item 3).** Declared 24; [a, b, c] measured 10, 20, 30, then
/// rebuilt as [x, c, a, b]: heights follow their ids — x unmeasured 24, c 30,
/// a 10, b 20 — so the offsets are 0, 24, 54, 64 and the total 84; the
/// returned lookup puts c at 1; every id is recorded. Mutation: the rebuild
/// keeps heights by index (offsets 0, 10, 30, 60).
@Test func aRebuildKeepsHeightsByIDAcrossAReorderAndAnInsertion() {
    let index = RowExtentIndex<String>(count: 3, declaredEstimate: 24)
    index.record(10, at: 0, id: "a")
    index.record(20, at: 1, id: "b")
    index.record(30, at: 2, id: "c")
    let lookup = index.rebuild(ids: ["x", "c", "a", "b"])
    #expect(index.count == 4)
    #expect((0...3).map { index.offset(of: $0) } == [0, 24, 54, 64])
    #expect(index.totalExtent == 84)
    #expect(lookup["c"] == 1)
    #expect(index.id(at: 0) == "x" && index.id(at: 3) == "b")
    #expect(!index.isMeasured(0) && index.isMeasured(1))
    #expect(index.rebuilds == 1)
}

/// **1.9 (`VL-E` item 3).** No declared estimate; [a, b, c] measured 10, 20,
/// 90, rebuilt as [a, b, x]: c's height leaves with it — the mean is (10 + 20)
/// / 2 = 15, so x counts 15 and the total is 45. Mutation: the rebuild keeps
/// the old measured total and count (c's 90 stays in the mean: 40, total 70).
@Test func aRebuildDropsHeightsOfIDsNoLongerPresent() {
    let index = RowExtentIndex<String>(count: 3, declaredEstimate: nil)
    index.record(10, at: 0, id: "a")
    index.record(20, at: 1, id: "b")
    index.record(90, at: 2, id: "c")
    index.rebuild(ids: ["a", "b", "x"])
    #expect(index.estimate == 15)
    #expect(index.extent(at: 2) == 15)
    #expect(index.totalExtent == 45)
}

/// **1.10 (`VL-D`).** `index(containing:)` descends one Fenwick level per
/// power of two at or below `count`: `⌊log₂ count⌋ + 1` steps — 17 at 100 000
/// (2¹⁶ = 65 536 ≤ 100 000 < 2¹⁷) and 9 at 500 (2⁸ = 256) — each counted in
/// `nodeVisits`, wherever `y` lands. `offset(of: i)` visits one node per set bit
/// of `i`, so at most 17 / 9. Mutation: a linear prefix scan in `offset(of:)`
/// (50 000 visits at 100 000).
@Test func aLookupAtAHundredThousandRowsVisitsLogarithmicallyManyNodes() {
    for (count, steps) in [(100_000, 17), (500, 9)] {
        let index = RowExtentIndex<Int>(count: count, declaredEstimate: 24)
        index.record(30, at: count / 3, id: count / 3)
        let middle = count / 2
        let before = index.nodeVisits
        let found = index.index(containing: Double(middle) * 24 + 12)
        let descent = index.nodeVisits - before
        // Row `count / 3` (before `middle`) is 6 taller than the estimate, so
        // row `middle` spans `[middle × 24 + 6, middle × 24 + 30)` and holds
        // `middle × 24 + 12`.
        #expect(found == middle, "count \(count): row \(found)")
        #expect(descent == steps, "count \(count): \(descent) visits")
        let mark = index.nodeVisits
        _ = index.offset(of: middle)
        let prefix = index.nodeVisits - mark
        #expect(prefix >= 1 && prefix <= steps, "count \(count): \(prefix) visits")
    }
}
