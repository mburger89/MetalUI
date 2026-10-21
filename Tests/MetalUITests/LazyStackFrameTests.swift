import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lazy containers, lane 1: the window, the index and the anchor, over a BARE `Frame` and a shared
// `StateTable` (spec section 5, tests 2.3-2.6, 2.8-2.11; rulings `LZ-C`, `LZ-E`, `LZ-G`). The shape
// is `VariableHeightListTests`': a 200 x 200 frame, a `ProposalScrollView` over a `LazyVStack`, the
// offset written into the scroller's `ScrollState` (the stand-in for a wheel), `render` called until
// the frame asks for nothing. Every literal is derived in its test's comment before the run.
//
// **Red-before** (record section 134): the types did not exist, so the file failed to compile; the
// mutation named in each comment is the real instrument.

private func patterned(_ key: Int) -> Double { [20, 40, 60, 80][((key % 4) + 4) % 4] }

/// What the rows did this frame.
@MainActor
private final class RowLog {
    var built: [Int] = []
    /// A placed row's y inside the scroller's content minus the offset that frame painted at.
    var screenY: [Int: Double] = [:]
    /// The scroller's content extent as the rows saw it (`ScrollerFrame.contentExtent`).
    var contentExtent: Double?
    /// The heights the rows answer; a missing key answers `base(key)`.
    var heights: [Int: Double] = [:]
    var base: (Int) -> Double = { _ in 20 }

    func height(_ key: Int) -> Double { heights[key] ?? base(key) }
    func reset() { built = []; screenY = [:]; contentExtent = nil }
}

/// A row of a fixed height, as wide as offered.
private struct Row: ProposalElement {
    let key: Int
    let log: RowLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.built.append(key)
        let height = log.height(key)
        return (pass.requestNativeLeaf { proposal in
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 50
            return LayoutMeasurement(size: SizeD(width: width, height: height))
        }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        if let scroller = pass.frame.activeScrollerFrame, scroller.axis == .vertical {
            log.screenY[key] = Double(bounds.origin.y.value - scroller.contentOrigin.y.value) - scroller.offset
            log.contentExtent = scroller.contentExtent
        }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
/// The lazy stack's id: the scroller's content slot 0.
private let stackID = GlobalElementID.child(of: rootID, at: 0, name: nil)

@MainActor
@discardableResult
private func render(_ states: StateTable, _ keys: [Int], log: RowLog, axis: ScrollAxis = .vertical) -> Frame {
    log.reset()
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      stateTable: states)
    var root = ProposalScrollView(axis) {
        LazyVStack(spacing: Pixels(0)) {
            ForEach(keys, id: \.self) { key in Row(key: key, log: log) }
        }
    }
    frame.render(&root)
    return frame
}

@MainActor
private func setOffset(_ states: StateTable, _ offset: Double) {
    states.withState(rootID, initial: ScrollState()) { $0.offset = offset }
}

@MainActor
private func offset(_ states: StateTable) -> Double? { states.peek(rootID, as: ScrollState.self)?.offset }

@MainActor
private func index(_ states: StateTable) -> RowExtentIndex<AnyHashable>? {
    states.peek(stackID, as: LazyOrigin.self)?.extents as? RowExtentIndex<AnyHashable>
}

/// Frames until a render asks for nothing more, at most 8.
@MainActor
private func settle(_ states: StateTable, _ keys: [Int], log: RowLog) -> Frame {
    var frame = render(states, keys, log: log)
    for _ in 0..<8 where frame.wantsAnotherFrame {
        frame = render(states, keys, log: log)
    }
    return frame
}

/// **2.3 (`LZ-C`).** 1000 rows of 20: the cold frame (viewport unknown) realises the first 32, the
/// next realises the viewport window (200 / 20 = row 10 holds the bottom edge; 0 ..< 10 + 1 + 2 =
/// **13**), and every warm frame after it realises the same 13, builds 13 rows, and rebuilds nothing
/// (`rebuilds` 0: the index is created at the right count). Mutation: rebuild the index on every
/// frame (`rebuilds` rises).
@MainActor
@Test func aWarmFrameRealizesTheSameWindowAndRebuildsNothing() throws {
    let states = StateTable()
    let log = RowLog()
    let keys = Array(0..<1000)
    let cold = render(states, keys, log: log)
    #expect(cold.lazyWork == LazyWork(unitsRealized: 32, linesRealized: 32, unbounded: 0), "\(cold.lazyWork)")
    let first = render(states, keys, log: log)
    let second = render(states, keys, log: log)
    let third = render(states, keys, log: log)
    for (name, frame) in [("first", first), ("second", second), ("third", third)] {
        #expect(frame.lazyWork == LazyWork(unitsRealized: 13, linesRealized: 13, unbounded: 0),
                "\(name): \(frame.lazyWork)")
    }
    #expect(log.built == Array(0..<13), "built \(log.built)")
    #expect(!third.wantsAnotherFrame)
    let held = try #require(index(states), "the stack stored no index")
    #expect(held.rebuilds == 0, "rebuilds \(held.rebuilds)")
}

/// **2.4a (`LZ-E`, window).** Offset 2000 over uniform 20-point rows (all estimates exact): the top
/// row is 100, the viewport's bottom edge 2200 is in row 110, so the window is 100 - 2 ..< 110 + 1 + 2 =
/// **98 ..< 113**: ids 98...112, 15 realised, and the stack's content extent is 1000 * 20. Mutation:
/// the window not recomputed from the offset (rows 0...12 again).
@MainActor
@Test func scrollingRealizesTheNewWindow() throws {
    let states = StateTable()
    let log = RowLog()
    let keys = Array(0..<1000)
    _ = settle(states, keys, log: log)
    setOffset(states, 2000)
    let frame = render(states, keys, log: log)
    #expect(log.built == Array(98...112), "built \(log.built)")
    #expect(frame.lazyWork == LazyWork(unitsRealized: 15, linesRealized: 15, unbounded: 0))
    #expect(log.screenY[100] == 0)
    #expect(log.contentExtent == 20_000)
}

/// **2.5 (`LZ-C`, probe R4).** 1000 rows of 20 with row 500 (never realised) 120 tall: the extent is
/// the measured rows' mean times the count - **20 000**, not 20 100 and not 24-point estimates
/// (24 x 968 + 32 x 20 = 23 904). Once row 500 is realised (offset 10 000) the mean moves and the
/// extent is the index's own total, above 20 000. Mutation: the estimate -> the fallback 24 (the
/// first figure reads 23 904).
@MainActor
@Test func unrealizedChildrenCountAsTheMeanOfTheMeasuredOnes() throws {
    let states = StateTable()
    let log = RowLog()
    log.heights[500] = 120
    let keys = Array(0..<1000)
    _ = settle(states, keys, log: log)
    #expect(log.contentExtent == 20_000, "\(String(describing: log.contentExtent))")
    setOffset(states, 10_000)
    _ = settle(states, keys, log: log)
    let held = try #require(index(states))
    let extent = try #require(log.contentExtent)
    #expect(extent > 20_000)
    #expect(abs(extent - held.totalExtent) <= 0.5, "extent \(extent) vs index \(held.totalExtent)")  // layout rounds to the pixel
}

/// Rows 300 tall (uniform, so a changed pair of rows leaves the measured mean at 300 and the anchor's
/// correction is exactly the change), offset 15 000 settled: row 50 on top (50 x 300), the viewport's
/// bottom edge 15 200 inside row 50 too, so the window is 50 - 2 ..< 50 + 1 + 2 = 48 ..< 53.
@MainActor
private func rowFiftyOnTop() throws -> (StateTable, RowLog, [Int]) {
    let states = StateTable()
    let log = RowLog()
    log.base = { _ in 300 }
    let keys = Array(0..<1000)
    _ = settle(states, keys, log: log)
    setOffset(states, 15_000)
    _ = settle(states, keys, log: log)
    try #require(log.built == Array(48...52), "control: built \(log.built)")
    try #require(log.screenY[50] == 0, "control: row 50 on top")
    return (states, log, keys)
}

/// **2.6a (`VL-G` item 1).** Row 48 (overscan, above the top) grows by 200 and row 52 (below the
/// viewport) shrinks by 200, so the measured mean stays 300: in the frame of the change row 50 is
/// placed at its anchor offset and row 48 grows upward, so row 50's on-screen y stays **0**.
/// Mutation: place from the first realised unit (row 50 reads 200).
@MainActor
@Test func aChildAboveTheTopMeasuredAnewDoesNotMoveTheTopChildInThatFrame() throws {
    let (states, log, keys) = try rowFiftyOnTop()
    log.heights[48] = 500
    log.heights[52] = 100
    render(states, keys, log: log)
    try #require(log.built.contains(48), "control: row 48 realised \(log.built)")
    #expect(log.screenY[50] == 0)
}

/// **2.6b (`VL-G` item 2).** After that frame the stored offset is 15 000 + 200 = **15 200** (`D =
/// offset(of: 50) - 15 000 = 200`: the measured rows above row 50 sum 200 more, the 16 unmeasured
/// ones count the unchanged mean 300) and the next frame draws row 50 at **0** again. Mutation: skip
/// `noteScrollAnchorAdjustment` (offset stays 15 000, row 50 reads 200 below the top).
@MainActor
@Test func theScrollOffsetFollowsTheTopChildWhenAChildAboveItIsMeasured() throws {
    let (states, log, keys) = try rowFiftyOnTop()
    log.heights[48] = 500
    log.heights[52] = 100
    render(states, keys, log: log)
    #expect(offset(states) == 15_200, "\(String(describing: offset(states)))")
    render(states, keys, log: log)
    #expect(log.screenY[50] == 0)
}

/// Rows 20 tall, offset 2000 settled: row 100 on top, window 98 ... 112.
@MainActor
private func rowHundredOnTop() throws -> (StateTable, RowLog, [Int]) {
    let states = StateTable()
    let log = RowLog()
    let keys = Array(0..<1000)
    _ = settle(states, keys, log: log)
    setOffset(states, 2000)
    _ = settle(states, keys, log: log)
    try #require(log.built == Array(98...112), "control: built \(log.built)")
    try #require(log.screenY[100] == 0, "control: row 100 on top")
    return (states, log, keys)
}

/// **2.8 (`VL-G` item 3, `VL-O`).** Three rows inserted before the anchor (ids 1000...1002, 20 tall):
/// the index is rebuilt BY ID, the anchor follows row 100 to index 103 and is placed at its old
/// offset, so row 100 stays at on-screen y **0** in the change frame; the correction (3 x 20 = 60)
/// lands in the stored offset, 2060, and the frame after draws row 100 at 0 again. Mutation:
/// rebuild by position (row 100's neighbours shift: the row at the old anchor index is id 97).
@MainActor
@Test func aDataChangeKeepsTheAnchorByID() throws {
    let (states, log, keys) = try rowHundredOnTop()
    let inserted = [1000, 1001, 1002] + keys
    render(states, inserted, log: log)
    #expect(log.screenY[100] == 0, "row 100 in the change frame: \(String(describing: log.screenY[100]))")
    #expect(offset(states) == 2060, "\(String(describing: offset(states)))")
    render(states, inserted, log: log)
    #expect(log.screenY[100] == 0)
    let held = try #require(index(states))
    #expect(held.rebuilds == 1, "rebuilds \(held.rebuilds)")
}

/// **2.9 (`LZ-G`, `CN-L`).** Duplicate ids dedupe within the realised window only, first wins: data
/// 0, 1, 2, 1, 3 builds each of 0, 1, 2, 3 once (the second 1 is not produced; a doubled node would
/// trap on `CN-L` or build 1 twice). Mutation: no dedupe (built 0, 1, 2, 1, 3).
@MainActor
@Test func duplicateIDsInTheWindowAreProducedOnce() {
    let states = StateTable()
    let log = RowLog()
    render(states, [0, 1, 2, 1, 3], log: log)
    #expect(log.built == [0, 1, 2, 3], "built \(log.built)")
}

/// **2.10 (`LZ-E`, probe R5).** A vertical lazy stack in a HORIZONTAL scroller is not windowed: all 500
/// rows realised, one unbounded container counted. Mutation: the axis test dropped (a cold slice of
/// 32 realised, `unbounded` 0).
@MainActor
@Test func aLazyStackInAScrollerOfTheOtherAxisRealizesEverythingAndCountsIt() {
    let states = StateTable()
    let log = RowLog()
    let frame = render(states, Array(0..<500), log: log, axis: .horizontal)
    #expect(frame.lazyWork == LazyWork(unitsRealized: 500, linesRealized: 500, unbounded: 1), "\(frame.lazyWork)")
    let warm = render(states, Array(0..<500), log: log, axis: .horizontal)
    #expect(warm.lazyWork == LazyWork(unitsRealized: 500, linesRealized: 500, unbounded: 1), "\(warm.lazyWork)")
}

/// **2.11 (`LZ-B`, divergence 636).** A member that is an `if` makes the container eager: every row
/// realised, counted unbounded, and the placement equal to a `VStack`'s of the same children (default
/// spacing 8, `.leading`: the rows at y 0, 28, 56). Mutation: the fallback removed (the `if` is
/// windowed or the container traps).
@MainActor
@Test func anIfMemberMakesTheContainerEagerAndCounted() {
    func placements(lazy: Bool) -> ([Int: Bounds<Pixels>], LazyWork) {
        let states = StateTable()
        let log = RowLog()
        let boundsLog = LeafBoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                          stateTable: states)
        let show = true
        func row(_ key: Int) -> NamedRow { NamedRow(key: key, log: boundsLog) }
        if lazy {
            var root = LazyVStack(alignment: .leading) {
                row(0)
                if show { row(1) }
                ForEach([2, 3], id: \.self) { row($0) }
            }.frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
            frame.render(&root)
        } else {
            var root = VStack(alignment: .leading) {
                row(0)
                if show { row(1) }
                ForEach([2, 3], id: \.self) { row($0) }
            }.frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
            frame.render(&root)
        }
        _ = log
        return (Dictionary(uniqueKeysWithValues: boundsLog.byName.map { (Int($0.key)!, $0.value) }), frame.lazyWork)
    }
    let (lazy, work) = placements(lazy: true)
    let (eager, _) = placements(lazy: false)
    #expect(lazy.count == 4 && lazy == eager, "lazy \(lazy) vs eager \(eager)")
    #expect(lazy[0]?.origin.y == Pixels(0) && lazy[1]?.origin.y == Pixels(28) && lazy[3]?.origin.y == Pixels(84))
    #expect(work.unbounded >= 1, "\(work)")
    #expect(work.unitsRealized == 4, "\(work)")
}

/// **2.11b (`LZ-B`).** The eager fallback is visible against a scroller: a 500-row `ForEach` beside an `if`
/// in a lazy stack in a 200-point scroller realises all **501** children (the `if` taking its one node),
/// counted as one unbounded container, where without the `if` the same scroller realises 13. Mutation:
/// the fallback removed, an unknown member read as one static unit (13 realised, nothing unbounded).
@MainActor
@Test func anIfMemberBesideAForEachRealizesEveryRowInAScroller() {
    let states = StateTable()
    let log = RowLog()
    func run() -> Frame {
        log.reset()
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                          stateTable: states)
        let show = true
        var root = ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                if show { Row(key: -1, log: log) }
                ForEach(0..<500) { Row(key: $0, log: log) }
            }
        }
        frame.render(&root)
        return frame
    }
    _ = run()
    let warm = run()
    #expect(warm.lazyWork == LazyWork(unitsRealized: 501, linesRealized: 501, unbounded: 1), "\(warm.lazyWork)")
    #expect(log.built.count == 501)
}

/// A 50 x 20 leaf logging its placed bounds under its key.
private struct NamedRow: ProposalElement {
    let key: Int
    let log: LeafBoundsLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 50, height: 20)) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.byName[String(key)] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}
