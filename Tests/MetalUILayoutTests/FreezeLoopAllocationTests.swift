import Testing
#if canImport(Darwin)
import Darwin
#endif
import MetalUICore
@testable import MetalUILayout

// Two properties of §9.7's freeze loop that no behavioural test in
// `FreezeLoopTests.swift` can see:
//
// 1. **What it allocates.** Each pass used to build three `filter` arrays of
//    whole `FlexItem` values, a `[Double]` of factors and an `[Int: Double]`
//    of violations, all to produce four sums and a per-index clamp. Measured
//    with the hook below in the debug test build, a two-pass line made 269
//    allocations at 7 items and 2,330 at 67 before the change — a count that
//    rises with the items on the line. Which construct contributes how much
//    was not separated. The allocation test pins that the count no longer
//    rises, and that a pass allocates at most one buffer.
// 2. **That removing them changed no number.** The comparison test runs the
//    engine's function and a copy of the allocating spelling on the same
//    randomised lines and requires every result to agree bit for bit.

// MARK: - Counting allocations on this thread

#if canImport(Darwin)
private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// `MALLOC_LOG_TYPE_ALLOCATE` from libmalloc: set for `malloc`, `calloc`,
/// `realloc` and friends, clear for a bare `free`.
private let mallocLogTypeAllocate: UInt32 = 2

nonisolated(unsafe) private var allocationsSeen = 0
nonisolated(unsafe) private var countedThread: pthread_t?
nonisolated(unsafe) private var chainedLogger: MallocLogger?

/// Runs inside malloc, on every thread. It must not allocate, and it must not
/// be the first reader of a lazily-initialised global — `countAllocations`
/// touches each one before installing it.
nonisolated(unsafe) private let countingLogger: MallocLogger = { type, a1, a2, a3, result, skip in
    if type & mallocLogTypeAllocate != 0,
       let thread = countedThread, pthread_equal(thread, pthread_self()) != 0 {
        allocationsSeen += 1
    }
    chainedLogger?(type, a1, a2, a3, result, skip)
}

/// The number of heap allocations `body` makes **on the calling thread**,
/// counted through libmalloc's `malloc_logger` hook — the one Instruments'
/// allocation tracking uses. Other threads' allocations are ignored, so the
/// runtime's background work cannot move the count.
///
/// **This counts real allocations, not a counter the code under test keeps**:
/// nothing in `Sources/` knows it is being watched. A hook that silently
/// stopped firing would read 0 and make every bound below pass, so the test
/// calibrates it against a known number of buffers before believing it.
private func countAllocations(_ body: () -> Void) throws -> Int {
    let symbol = try #require(
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger"),
        "libmalloc no longer exports malloc_logger: replace this instrument, do not skip it")
    let slot = symbol.assumingMemoryBound(to: MallocLogger?.self)

    _ = countingLogger
    _ = mallocLogTypeAllocate
    chainedLogger = slot.pointee
    allocationsSeen = 0
    countedThread = pthread_self()

    slot.pointee = countingLogger
    body()
    slot.pointee = chainedLogger

    countedThread = nil
    return allocationsSeen
}
#endif

/// Allocates exactly `count` distinct, non-empty buffers the optimiser cannot
/// elide, for calibrating the counter.
@inline(never)
private func allocateBuffers(_ count: Int) -> Int {
    var total = 0
    for i in 0..<count {
        let buffer = ContiguousArray<Double>(repeating: Double(i), count: 16 + i)
        total &+= buffer.count
    }
    return total
}

// MARK: - Lines

private func item(_ tree: LayoutTree, grow: Float, shrink: Float, base: Double,
                  min: Double? = nil, max: Double? = nil) -> FlexItem {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    let node = tree.newNode(style: s, children: [])
    return FlexItem(node: node, baseSize: base, mainEdges: 0,
                    hypotheticalMainSize: clamp(base, min: min, max: max),
                    minMain: min, maxMain: max,
                    targetMainSize: 0, crossSize: 0, stretchEligible: false,
                    minCross: nil, maxCross: nil, frozen: false,
                    marginMain: (0, 0), marginCross: (0, 0))
}

/// A growing line that takes **two passes whatever `fillers` is**: three items
/// capped at 10 violate their max on pass 1 (each is offered at least
/// 10 000 / 67) and freeze; on pass 2 the fillers, which have no bounds, take
/// the rest with no violation and the line freezes whole.
private func growLine(_ tree: LayoutTree, fillers: Int) -> [FlexItem] {
    (0..<3).map { _ in item(tree, grow: 1, shrink: 1, base: 0, max: 10) }
        + (0..<fillers).map { _ in item(tree, grow: 1, shrink: 1, base: 0) }
}

/// A shrinking line that takes **two passes whatever `fillers` is**, from the
/// other violation sign: 50 of overflow shared by `fillers + 1` equal 100s
/// takes at least 50 / 65 ≈ 0.77 from each, which drops the one item floored at
/// 99.9 below its min on pass 1; on pass 2 the fillers absorb what is left.
private func shrinkLine(_ tree: LayoutTree, fillers: Int) -> [FlexItem] {
    [item(tree, grow: 0, shrink: 1, base: 100, min: 99.9)]
        + (0..<fillers).map { _ in item(tree, grow: 0, shrink: 1, base: 100) }
}

private func shrinkContainer(fillers: Int) -> Double { 100 * Double(fillers + 1) - 50 }

// MARK: - Tests

#if canImport(Darwin)
/// The freeze loop's allocations do not grow with the number of items on the
/// line, and a pass allocates at most one buffer.
///
/// Two lines of the same shape, one with 4 unconstrained items and one with 64,
/// each resolved in exactly two passes (see `growLine` and `shrinkLine`). Both
/// violation signs are covered, because §9.7.4.e freezes through a different
/// branch for each.
///
/// **What each half catches, by mutation.** Restoring the allocating spelling
/// reddens all four expectations. Adding a second per-pass
/// `ContiguousArray(repeating:count:)` beside the violations buffer — a
/// temporary whose allocation count does not depend on the items — leaves
/// both equalities green and reddens only the two `<= passes` bounds (4
/// allocations over 2 passes). The loop is allowed exactly one per-pass buffer,
/// the violations.
///
/// Each arm is run once to warm up before it is counted: the first use of a
/// generic specialisation can instantiate metadata on the heap, which would
/// charge the arm that happens to run first. And the counted array is built
/// afresh rather than copied from the warm-up's: two variables sharing one
/// buffer would make the function's first write a copy-on-write allocation,
/// charged to the loop.
///
/// **It holds in the configuration the suite runs, which is debug.** That is
/// why `resolveFlexibleLengths` avoids `reduce` and `contains(where:)` over
/// `[FlexItem]` as well as the `filter`s this was written for: in this
/// package's debug test build each allocates per element, so with them in
/// place the pin stayed red after the `filter`s had gone. A standalone `-O`
/// build of the same sources, before that last change, already made exactly
/// one allocation per pass on both lines at both sizes.
@Test func freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine() throws {
    let calibration = try countAllocations { _ = allocateBuffers(16) }
    try #require(calibration >= 16,
                 "the allocation counter saw \(calibration) of 16 buffers; nothing it reports can be trusted")

    let tree = LayoutTree(generation: 0)
    let passesPerLine = 2

    // **The toolchain's own floor, measured here rather than assumed.** Under
    // Apple's swiftlang build of Swift (Xcode, and every GitHub macOS runner) a
    // bare `for i in items.indices { sum += items[i].baseSize }` registers ONE
    // allocation per element in a debug build; under a swift.org toolchain the
    // same loop registers none. Measured 2026-09-11 with this counter on Swift
    // 6.3.3 (swift-6.3.3-RELEASE) and 6.4 (swiftlang-6.4.0.34.1): 0 vs 67 at 67
    // items, and 16 known buffers read as 16 and as 33. So on a swiftlang
    // toolchain every loop in this function looks like an allocation per item,
    // and an absolute bound measures the toolchain, not `resolveFlexibleLengths`.
    func loopFloor(_ fillers: Int) throws -> Int {
        let items = growLine(tree, fillers: fillers)
        var sum = 0.0
        _ = try countAllocations { for i in items.indices { sum += items[i].baseSize } }
        let floor = try countAllocations { for i in items.indices { sum += items[i].baseSize } }
        _ = sum
        return floor
    }

    func grow(_ fillers: Int) throws -> Int {
        var warm = growLine(tree, fillers: fillers)
        resolveFlexibleLengths(tree, items: &warm, containerMain: 10_000, gap: 0)
        var items = growLine(tree, fillers: fillers)
        return try countAllocations {
            resolveFlexibleLengths(tree, items: &items, containerMain: 10_000, gap: 0)
        }
    }
    func shrink(_ fillers: Int) throws -> Int {
        let container = shrinkContainer(fillers: fillers)
        var warm = shrinkLine(tree, fillers: fillers)
        resolveFlexibleLengths(tree, items: &warm, containerMain: container, gap: 0)
        var items = shrinkLine(tree, fillers: fillers)
        return try countAllocations {
            resolveFlexibleLengths(tree, items: &items, containerMain: container, gap: 0)
        }
    }
    /// The same line through the allocating spelling this change replaced, so
    /// the comparison below is made with ONE instrument in ONE run.
    func referenceGrow(_ fillers: Int) throws -> Int {
        var branches = ReferenceBranches()
        var warm = growLine(tree, fillers: fillers)
        referenceResolveFlexibleLengths(tree, items: &warm, containerMain: 10_000,
                                        gap: 0, branches: &branches)
        var items = growLine(tree, fillers: fillers)
        return try countAllocations {
            referenceResolveFlexibleLengths(tree, items: &items, containerMain: 10_000,
                                            gap: 0, branches: &branches)
        }
    }

    let floorFew = try loopFloor(4), floorMany = try loopFloor(64)
    let growFew = try grow(4), growMany = try grow(64)
    let shrinkFew = try shrink(4), shrinkMany = try shrink(64)
    let refFew = try referenceGrow(4), refMany = try referenceGrow(64)

    // The instrument must see the shape it exists to measure: the spelling this
    // change replaced allocates more as the line grows, on every toolchain.
    try #require(refMany > refFew,
                 "the allocating reference read \(refFew) at 7 items and \(refMany) at 67, so the counter cannot see this function's allocations at all")

    // Portable half: the engine's spelling must cost far less than the one it
    // replaced, and the saving must widen with the line.
    #expect(growMany * 2 <= refMany,
            "grow line at 67 items: engine \(growMany), allocating reference \(refMany)")
    #expect(refMany - growMany > refFew - growFew,
            "the saving must grow with the line: \(refFew - growFew) at 7 items, \(refMany - growMany) at 67")

    if floorMany == 0 {
        // Strict half, valid only where iteration itself allocates nothing.
        #expect(growFew == growMany,
                "grow line (max violations): \(growFew) allocations at 7 items, \(growMany) at 67")
        #expect(shrinkFew == shrinkMany,
                "shrink line (min violations): \(shrinkFew) allocations at 5 items, \(shrinkMany) at 65")
        #expect(growMany <= passesPerLine,
                "grow line: \(growMany) allocations over \(passesPerLine) passes")
        #expect(shrinkMany <= passesPerLine,
                "shrink line: \(shrinkMany) allocations over \(passesPerLine) passes")
    } else {
        // Say so out loud. A toolchain that hides the strict half must not look
        // like one that passed it — this is the line to grep for in a CI log.
        print("""
            FREEZE-ALLOC: strict per-pass bound NOT CHECKED on this toolchain — a bare index \
            loop allocates \(floorFew) at 7 items and \(floorMany) at 67, so every loop in \
            resolveFlexibleLengths reads as one allocation per item. Relative half checked: \
            engine \(growFew)/\(growMany) against reference \(refFew)/\(refMany). \
            Run a swift.org toolchain for the strict half.
            """)
    }
}
#endif

/// Branch counts from `referenceResolveFlexibleLengths`, so the comparison
/// below can require that its random lines actually reached every branch the
/// allocation-free spelling rewrote — a comparison that never took the
/// `totalViolation < 0` branch would agree about it vacuously.
private struct ReferenceBranches {
    var calls = 0
    var growCalls = 0
    var shrinkCalls = 0
    var passes = 0
    var multiPassCalls = 0
    var zeroViolationPasses = 0
    var minViolationPasses = 0
    var maxViolationPasses = 0
    var passesLeavingItemsUnfrozen = 0
    var subOneScaledPasses = 0
    var zeroFactorTotalPasses = 0
    var passesWithFrozenAndUnfrozen = 0
}

/// §9.7 spelled the allocating way — `resolveFlexibleLengths` exactly as it
/// stood at 75d0073, before its per-pass `filter`s, `map` and violation
/// dictionary were folded into loops, with the long comments dropped and branch
/// counters added. It is the oracle for
/// `freezeLoopMatchesItsAllocatingReferenceBitForBit` and is not meant to be
/// kept fast.
///
/// **If you change §9.7's arithmetic on purpose, change it here in the same
/// commit** — this is a second copy of the algorithm, and the comparison below
/// will say so. What it exists to catch is a change to the engine's copy that
/// was meant to alter nothing.
private func referenceResolveFlexibleLengths(
    _ tree: LayoutTree,
    items: inout [FlexItem],
    containerMain: Double,
    gap: Double,
    branches: inout ReferenceBranches
) {
    guard !items.isEmpty else { return }
    branches.calls += 1

    let totalGap = gap * Double(items.count - 1)
    let hypotheticalTotal = items.reduce(0) { $0 + $1.hypotheticalMainSize }
    let usingGrow = hypotheticalTotal + totalGap < containerMain
    if usingGrow { branches.growCalls += 1 } else { branches.shrinkCalls += 1 }

    func rawFactor(_ item: FlexItem) -> Double {
        let s = tree.style(item.node)
        return usingGrow ? Double(s.flexGrow) : Double(s.flexShrink)
    }

    for i in items.indices {
        let inflexible = rawFactor(items[i]) == 0
            || (usingGrow && items[i].baseSize > items[i].hypotheticalMainSize)
            || (!usingGrow && items[i].baseSize < items[i].hypotheticalMainSize)
        if inflexible {
            items[i].targetMainSize = items[i].hypotheticalMainSize
            items[i].frozen = true
        } else {
            items[i].targetMainSize = items[i].baseSize
        }
    }

    let initialFreeSpace = containerMain - totalGap - items.reduce(0) {
        $0 + ($1.frozen ? $1.targetMainSize : $1.baseSize)
    }

    let maximumPasses = items.count + 1
    var passes = 0

    while items.contains(where: { !$0.frozen }) {
        passes += 1
        if passes > maximumPasses {
            Issue.record("the reference freeze loop did not converge")
            for i in items.indices { items[i].frozen = true }
            break
        }
        branches.passes += 1
        if passes == 2 { branches.multiPassCalls += 1 }
        if items.contains(where: \.frozen) { branches.passesWithFrozenAndUnfrozen += 1 }

        let frozenTotal = items.filter(\.frozen).reduce(0) { $0 + $1.targetMainSize }
        let unfrozenBase = items.filter { !$0.frozen }.reduce(0) { $0 + $1.baseSize }
        var remaining = containerMain - totalGap - frozenTotal - unfrozenBase

        let rawTotal = items.filter { !$0.frozen }.reduce(0) { $0 + rawFactor($1) }
        if rawTotal < 1 {
            let scaled = initialFreeSpace * rawTotal
            if abs(scaled) < abs(remaining) {
                remaining = scaled
                branches.subOneScaledPasses += 1
            }
        }

        let factors: [Double] = items.map { item in
            guard !item.frozen else { return 0 }
            return usingGrow
                ? rawFactor(item)
                : rawFactor(item) * max(0, item.baseSize - item.mainEdges)
        }
        let factorTotal = factors.reduce(0, +)

        if factorTotal > 0 {
            for i in items.indices where !items[i].frozen {
                items[i].targetMainSize = items[i].baseSize + remaining * (factors[i] / factorTotal)
            }
        } else {
            branches.zeroFactorTotalPasses += 1
        }

        var totalViolation: Double = 0
        var violation: [Int: Double] = [:]
        for i in items.indices where !items[i].frozen {
            let bounded = max(0, clamp(items[i].targetMainSize,
                                       min: items[i].minMain, max: items[i].maxMain))
            let v = bounded - items[i].targetMainSize
            violation[i] = v
            totalViolation += v
            items[i].targetMainSize = bounded
        }

        if totalViolation == 0 {
            branches.zeroViolationPasses += 1
            for i in items.indices { items[i].frozen = true }
        } else if totalViolation > 0 {
            branches.minViolationPasses += 1
            for (i, v) in violation where v > 0 { items[i].frozen = true }
        } else {
            branches.maxViolationPasses += 1
            for (i, v) in violation where v < 0 { items[i].frozen = true }
        }
        if items.contains(where: { !$0.frozen }) { branches.passesLeavingItemsUnfrozen += 1 }
    }
}

private struct LineRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }
    mutating func chance(_ percent: UInt64) -> Bool { next() % 100 < percent }
}

/// The engine's §9.7 agrees with the allocating spelling it replaced **bit for
/// bit**, on every item of 4 000 seeded random lines.
///
/// The lines draw flex factors (including zeros, and sets summing below one so
/// §9.7.4.b scales), base sizes, main-axis padding and border, min and max
/// bounds, gaps and container sizes from small grids of values, so that ties —
/// a total violation of exactly 0, a sum landing exactly on a bound — happen as
/// often as the arithmetic allows rather than never. A few items arrive already
/// frozen or with a hypothetical size that is not their clamped base; `collectItems`
/// produces neither, and both are here because the two spellings must agree on
/// any input, not only on the inputs today's caller happens to produce.
///
/// The `#require`s at the top are the part that makes agreement mean
/// something: each names a branch of the loop and requires the random lines to
/// have taken it a nontrivial number of times.
@Test func freezeLoopMatchesItsAllocatingReferenceBitForBit() throws {
    var random = LineRandom(state: 0x5EED_F1E7)
    var branches = ReferenceBranches()
    var disagreements: [String] = []

    for line in 0..<4_000 {
        let tree = LayoutTree(generation: UInt64(line))
        let count = 1 + Int(random.next() % 9)
        var items: [FlexItem] = []
        for _ in 0..<count {
            var s = Style()
            s.flexGrow = random.pick([0, 0, 0.2, 0.25, 0.5, 1, 1, 2, 3])
            s.flexShrink = random.pick([0, 0.3, 0.5, 1, 1, 2, 4])
            let node = tree.newNode(style: s, children: [])

            let base = random.pick([0, 10, 25, 40, 50, 50, 100, 120, 33.25])
            let edges = random.chance(35) ? min(base, random.pick([5, 20, 40])) : 0
            let minMain: Double? = random.chance(45) ? random.pick([0, 15, 30, 45, 60, 110]) : nil
            let maxMain: Double? = random.chance(45) ? random.pick([20, 40, 45, 80, 150]) : nil
            var hypothetical = clamp(base, min: minMain, max: maxMain)
            if random.chance(8) { hypothetical += random.pick([-15, 5, 30]) }

            items.append(FlexItem(
                node: node, baseSize: base, mainEdges: edges,
                hypotheticalMainSize: hypothetical,
                minMain: minMain, maxMain: maxMain,
                targetMainSize: random.pick([-999, 0, 17]), crossSize: 11,
                stretchEligible: random.chance(50),
                minCross: nil, maxCross: 7, frozen: random.chance(4),
                marginMain: (1, 2), marginCross: (3, 4)))
        }
        let containerMain = random.pick([0, 20, 50, 100, 150, 180, 200, 240, 300, 450, 1_000, 123.5])
        let gap = random.pick([0, 0, 0, 5, 12.5])

        var engine = items
        var reference = items
        resolveFlexibleLengths(tree, items: &engine, containerMain: containerMain, gap: gap)
        referenceResolveFlexibleLengths(tree, items: &reference, containerMain: containerMain,
                                        gap: gap, branches: &branches)

        try #require(engine.count == reference.count)
        for i in engine.indices {
            let e = engine[i], r = reference[i]
            let agrees = e.targetMainSize.bitPattern == r.targetMainSize.bitPattern
                && e.frozen == r.frozen
                && e.node == r.node
                && e.baseSize.bitPattern == r.baseSize.bitPattern
                && e.hypotheticalMainSize.bitPattern == r.hypotheticalMainSize.bitPattern
            if !agrees, disagreements.count < 10 {
                disagreements.append("line \(line) item \(i): engine \(e.targetMainSize) frozen \(e.frozen), reference \(r.targetMainSize) frozen \(r.frozen)")
            }
        }
    }

    try #require(branches.calls == 4_000)
    try #require(branches.growCalls >= 200, "grow lines: \(branches.growCalls)")
    try #require(branches.shrinkCalls >= 200, "shrink lines: \(branches.shrinkCalls)")
    try #require(branches.multiPassCalls >= 200, "multi-pass lines: \(branches.multiPassCalls)")
    try #require(branches.zeroViolationPasses >= 200, "zero-violation passes: \(branches.zeroViolationPasses)")
    try #require(branches.minViolationPasses >= 200, "min-violation passes: \(branches.minViolationPasses)")
    try #require(branches.maxViolationPasses >= 200, "max-violation passes: \(branches.maxViolationPasses)")
    try #require(branches.passesLeavingItemsUnfrozen >= 200,
                 "passes freezing only some items: \(branches.passesLeavingItemsUnfrozen)")
    try #require(branches.passesWithFrozenAndUnfrozen >= 200,
                 "passes over a mix of frozen and unfrozen items: \(branches.passesWithFrozenAndUnfrozen)")
    try #require(branches.subOneScaledPasses >= 50, "§9.7.4.b scaled passes: \(branches.subOneScaledPasses)")
    try #require(branches.zeroFactorTotalPasses >= 50, "zero factor-total passes: \(branches.zeroFactorTotalPasses)")

    #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
}
