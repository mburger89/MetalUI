import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lazy containers, lane 2: the grids' window, extents and column count over a BARE `Frame` and a shared
// `StateTable` (spec section 5, tests 3.6-3.8; rulings `LZ-E`, `LZ-L`, `LZ-M`). The shape is
// `LazyStackFrameTests`': a 200 x 200 frame, a `ProposalScrollView` over a grid, the offset written into
// the scroller's `ScrollState` (the stand-in for a wheel), `render` called until the frame asks for
// nothing. Two flexible columns unless a test says otherwise. Red-before (record section 134): the types did
// not exist, so the file failed to compile (`cannot find 'LazyVGrid' in scope`); the mutation named in each
// comment is the real instrument.

/// What the cells did this frame.
@MainActor
private final class CellLog {
    var built: [Int] = []
    /// A placed cell's y and x inside the scroller's content minus the offset that frame painted at.
    var screenY: [Int: Double] = [:]
    var screenX: [Int: Double] = [:]
    var contentExtent: Double?
    var heights: [Int: Double] = [:]
    var base: (Int) -> Double = { _ in 20 }

    func height(_ key: Int) -> Double { heights[key] ?? base(key) }
    func reset() { built = []; screenY = [:]; screenX = [:]; contentExtent = nil }
}

/// A cell of a fixed height, as wide as its track offers (50 when nothing is offered).
private struct GridCell: ProposalElement {
    let key: Int
    let log: CellLog

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
            log.screenX[key] = Double(bounds.origin.x.value - scroller.contentOrigin.x.value)
            log.contentExtent = scroller.contentExtent
        }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let gridID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private let twoColumns = [GridItem(.flexible()), GridItem(.flexible())]

@MainActor
@discardableResult
private func render(_ states: StateTable, count: Int, columns: [GridItem] = twoColumns, log: CellLog,
                    width: Float = 200) -> Frame {
    log.reset()
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(200)), scaleFactor: 1,
                      stateTable: states)
    var root = ProposalScrollView {
        LazyVGrid(columns: columns, spacing: Pixels(0)) {
            ForEach(0..<count) { key in GridCell(key: key, log: log) }
        }
    }
    frame.render(&root)
    return frame
}

@MainActor
private func settle(_ states: StateTable, count: Int, columns: [GridItem] = twoColumns, log: CellLog,
                    width: Float = 200) -> Frame {
    var frame = render(states, count: count, columns: columns, log: log, width: width)
    for _ in 0..<8 where frame.wantsAnotherFrame {
        frame = render(states, count: count, columns: columns, log: log, width: width)
    }
    return frame
}

/// **3.6 (`LZ-E`, `LZ-I`, `LZ-M`).** A 10 000-cell grid of two columns in a 200-point scroller realises the
/// window of ROWS, not cells: rows of 20 (spacing 0), the bottom edge 200 is in row 10, so 0 ..< 10 + 1 + 2 =
/// **13 lines and 26 cells** (units 0 ..< 26), nothing unbounded; the cold frame holds the first 32 lines
/// (64 cells). The eager stand-in (a `VStack` of `HStack` rows holding the same 10 000 cells) builds all
/// 10 000: the ratio is asserted at **>= 300** (10 000 / 26 = 384 at one build per cell).
/// Mutation: the window computed in cells (units 13, lines 7: the cell count is the line count).
@MainActor
@Test func aTenThousandCellLazyVGridRealizesOnlyTheWindow() throws {
    let states = StateTable()
    let log = CellLog()
    let cold = render(states, count: 10_000, log: log)
    #expect(cold.lazyWork == LazyWork(unitsRealized: 64, linesRealized: 32, unbounded: 0), "\(cold.lazyWork)")
    _ = render(states, count: 10_000, log: log)
    let warm = render(states, count: 10_000, log: log)
    #expect(warm.lazyWork == LazyWork(unitsRealized: 26, linesRealized: 13, unbounded: 0), "\(warm.lazyWork)")
    #expect(log.built == Array(0..<26), "built \(log.built)")
    #expect(!warm.wantsAnotherFrame)

    let eagerLog = CellLog()
    let eager = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1,
                      stateTable: StateTable())
    var root = ProposalScrollView {
        VStack(spacing: Pixels(0)) {
            ForEach(0..<5_000) { row in
                HStack(spacing: Pixels(0)) {
                    GridCell(key: 2 * row, log: eagerLog)
                    GridCell(key: 2 * row + 1, log: eagerLog)
                }
            }
        }
    }
    eager.render(&root)
    #expect(eagerLog.built.count == 10_000, "eager built \(eagerLog.built.count)")
    #expect(eagerLog.built.count >= 300 * log.built.count, "eager \(eagerLog.built.count) vs lazy \(log.built.count)")
    #expect(eager.lazyWork == LazyWork(), "a VStack counts no lazy work")
}

/// **3.7a (`LZ-M`, probe C10, G2).** A row is as tall as its tallest realised cell, the others centred in it:
/// cell 1 is 70 tall among cells of 30, so row 0 is 70 tall, cell 0 sits at (70 - 30) / 2 = **20**, cell 1 at 0,
/// and row 1 (cells 2 and 3) starts at **70** (spacing 0). Mutation: a row sized by its first cell (row 1 at 30).
@MainActor
@Test func aRowIsAsTallAsItsTallestRealizedCell() {
    let states = StateTable()
    let log = CellLog()
    log.base = { _ in 30 }
    log.heights[1] = 70
    _ = settle(states, count: 1000, log: log)
    #expect(log.screenY[0] == 20, "\(String(describing: log.screenY[0]))")
    #expect(log.screenY[1] == 0)
    #expect(log.screenY[2] == 70, "\(String(describing: log.screenY[2]))")
    #expect(log.screenY[3] == 70)
}

/// **3.7b (`LZ-M`, probe G2).** 1000 cells of 30 in two columns with cell 600 (row 300, never realised) 130
/// tall: unrealised rows count as the measured rows' mean, so the extent is 500 x 30 = **15 000**, not
/// 15 100 (SwiftUI G2 reads the same). Mutation: the unrealised rows' extent 0 (the extent is 13 x 30 = 390).
@MainActor
@Test func unrealizedRowsCountAsTheMeanOfTheMeasuredOnes() {
    let states = StateTable()
    let log = CellLog()
    log.base = { _ in 30 }
    log.heights[600] = 130
    _ = settle(states, count: 1000, log: log)
    #expect(log.contentExtent == 15_000, "\(String(describing: log.contentExtent))")
}

/// **3.8 (`LZ-L`, divergence 13's mechanism).** `.adaptive(minimum: 45)` in 200 points packs
/// n = floor((200 + 8) / 53) = **3** columns, but the first frame has no stored width and builds ONE column
/// (the cold slice, 32 cells); the frame asks for another and the next builds 3 columns: 13 rows x 3 = **39**
/// cells. Widening the window to 300 points later stores 200 and builds 3, while the layout resolves
/// n = floor(308 / 53) = 5: the frame asks for one more, and the next builds 13 x 5 = **65**.
/// Mutation: the mismatch detection removed (the 300-point frame asks for nothing and the grid stays at 39).
@MainActor
@Test func aStaleAdaptiveWidthIsCorrectedOnTheNextFrame() {
    let adaptive = [GridItem(.adaptive(minimum: 45))]
    let states = StateTable()
    let log = CellLog()
    let first = render(states, count: 10_000, columns: adaptive, log: log)
    #expect(first.lazyWork.unitsRealized == 32, "first frame \(first.lazyWork)")
    #expect(first.wantsAnotherFrame)
    let settled = settle(states, count: 10_000, columns: adaptive, log: log)
    #expect(settled.lazyWork == LazyWork(unitsRealized: 39, linesRealized: 13, unbounded: 0), "\(settled.lazyWork)")
    #expect(log.screenY[0] == log.screenY[1] && log.screenY[1] == log.screenY[2] && log.screenY[3] == 20,
            "cells 0-2 share a row, cell 3 starts the next: \(log.screenY[0] ?? -1) \(log.screenY[2] ?? -1) \(log.screenY[3] ?? -1)")

    let wide = render(states, count: 10_000, columns: adaptive, log: log, width: 300)
    #expect(wide.wantsAnotherFrame, "the stored 200 built 3 columns where 300 packs 5")
    let resettled = settle(states, count: 10_000, columns: adaptive, log: log, width: 300)
    #expect(resettled.lazyWork == LazyWork(unitsRealized: 65, linesRealized: 13, unbounded: 0), "\(resettled.lazyWork)")
    #expect(log.screenY[4] == 0 && log.screenY[5] == 20, "five cells to a row: \(log.screenY[4] ?? -1) \(log.screenY[5] ?? -1)")
}
