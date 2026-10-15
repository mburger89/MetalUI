#if canImport(Darwin)
import Testing
import MetalUICore
import MetalUITestSupport
@testable import MetalUI

// `PA-E`, `PA-H`, `PA-J`: the build lane's pins. Counts are thread-filtered and differential or against a floor
// (a debug build logs more than one event per allocation, `PA-O`).

private func id(_ names: String...) -> GlobalElementID {
    var current: GlobalElementID?
    for name in names { current = GlobalElementID.child(of: current, at: 0, name: ElementID(name)) }
    return current!
}

/// **Test 2** (`PA-E`). A steady `mark` of present ids allocates nothing per call beyond the bare loop: the
/// coroutine frame of `storage[id]?.isLive = true` was one allocation each. Counted for 100 and 1000 calls, the
/// per-call difference is 0 once the loop's own cost (`PA-O`) is subtracted by a floor loop that does everything but
/// the `mark` write.
///
/// Mutation that must redden it: restore `storage[id]?.isLive = true` in `StateTable.mark`.
@MainActor
@Test func markAllocatesNothingOnASteadyFrame() throws {
    let table = StateTable()
    let ids = (0..<1000).map { id("e\($0)") }
    for (i, key) in ids.enumerated() { table.withState(key, initial: 0) { $0 = i } }
    for key in ids { table.mark(key) }          // warm: `marked` and the journal reach their size
    func marks(_ n: Int) throws -> Int {
        let slice = Array(ids[0..<n])
        return try #require(countAllocations { for key in slice { table.mark(key) } })
    }
    func floor(_ n: Int) throws -> Int {
        let slice = Array(ids[0..<n])
        var hits = 0
        return try #require(countAllocations { for key in slice { if table.isLive(key) { hits += 1 } } })
    }
    let small = try marks(100) - floor(100), large = try marks(1000) - floor(1000)
    #expect(large - small <= 0, "mark allocated per call: \(small) at 100, \(large) at 1000 (floor-corrected)")
}

/// **Test 4** (`PA-H`). `planLegacyItems`' weights check, now one loop, reports `flexGrow.weights` exactly when two or
/// more distinct positive factors are declared among the non-frame-layer children: none, one factor, equal factors,
/// two factors, a zero and a positive one, a negative and a positive one.
///
/// Mutation that must redden it: `> 0` -> `>= 0` in the loop (the zero-plus-one arm reports).
@MainActor
@Test func planLegacyItemsFlexWeightsMatchTheFilterMapSet() {
    func fields(_ factors: [Float]) -> [UnlowerableField] {
        LayoutDifferential.render(width: 200, height: 100) {
            Box {
                ForEach(Array(factors.enumerated()), id: \.offset) { entry in
                    Box().cssWidth(Pixels(10)).cssHeight(Pixels(10)).flexGrow(entry.element)
                }
            }
            .cssWidth(Pixels(100)).cssHeight(Pixels(50))
        }.unlowerableFields
    }
    let weights = UnlowerableField(site: .box, field: "flexGrow.weights")
    #expect(!fields([]).contains(weights), "none")
    #expect(!fields([0, 0]).contains(weights), "no growth")
    #expect(!fields([1]).contains(weights), "one factor")
    #expect(!fields([2, 2]).contains(weights), "equal factors")
    #expect(fields([1, 2]).contains(weights), "two factors")
    #expect(fields([1, 2, 3]).contains(weights), "three factors")
    #expect(!fields([0, 1]).contains(weights), "a zero is not a factor")
    #expect(!fields([-1, 1]).contains(weights), "a negative is not a factor")
}
#endif
