import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lazy containers, lane 2: the grids through a real `Window` over the harness (spec section 5, tests
// 3.9-3.12; rulings `LZ-E`, `LZ-H`, `LZ-J`, `LZ-O`, `LZ-P`, `LZ-R`). Counts, never time. Two flexible
// columns of 20-point rows in a 200 x 200 window unless a test says otherwise: 10 rows on screen, 13
// realised (the row holding the bottom edge + 1, + 2 overscan, divergence 637), 26 cells. Red-before (record
// section 134): the types did not exist, so the file failed to compile.

private let twoColumns = [GridItem(.flexible()), GridItem(.flexible())]

@MainActor private func labels(_ window: TestWindow) throws -> [String] {
    try window.elements(role: .staticText).compactMap(\.value)
}

/// **3.9a (`LZ-E`, `LZ-J`).** A wheel to the 100th row realises the new rows and the accessibility tree
/// holds exactly the realised cells: the top row 100 (offset 2000 over uniform rows of 20), the bottom edge
/// 2200 in row 110, so rows 98 ..< 113 = cells 196 ... 225 (30 of them, two to a row). Mutation: the
/// window not recomputed on scroll (cells 0 ... 25 stay).
@Test @MainActor func scrollingAGridRealizesTheNewRowsAndTheAccessibilityTreeFollows() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVGrid(columns: twoColumns, spacing: Pixels(0)) {
                ForEach(0..<10_000) { index in ProposalText("cell \(index)").frame(height: Pixels(20)) }
            }
        }
    }
    window.tick(); window.tick()
    #expect(try Set(labels(window)) == Set((0..<26).map { "cell \($0)" }))
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick(); window.tick()
    let present = try labels(window)
    #expect(Set(present) == Set((196...225).map { "cell \($0)" }), "labels \(present.sorted())")
    #expect(window.lastFrameWork.lazyUnitsRealized == 30 && window.lastFrameWork.lazyLinesRealized == 15,
            "\(window.lastFrameWork.lazyUnitsRealized) \(window.lastFrameWork.lazyLinesRealized)")
}

private final class Serials {
    var next = 0
    var seen: [Int: Int] = [:]
    func mint() -> Int { next += 1; return next }
}

private struct StateCell: Component {
    let index: Int
    let serials: Serials
    @State private var serial = 0
    var content: some ProposalElementGroup {
        let _ = serials.seen[index] = serial
        ProposalText("cell \(index)").frame(height: Pixels(20))
            .onAppear { if serial == 0 { serial = serials.mint() } }
    }
}

/// **3.9b (`LZ-H`, `TB-AH`).** A scrolled-out cell keeps its `@State`: cell 0 mints a serial on its first
/// appearance, the window moves to row 100 (cell 0 unrealised) and back, and cell 0 holds the same serial.
/// Mutation: `noteLoop` called by the lazy `ForEach` together with the windowed parent removed (cell 0 returns
/// fresh with a new serial), as lane 1's 2.7.
@Test @MainActor func aScrolledOutGridCellKeepsItsState() throws {
    let serials = Serials()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVGrid(columns: twoColumns, spacing: Pixels(0)) {
                ForEach(0..<2000) { StateCell(index: $0, serials: serials) }
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    let first = serials.seen[0]
    #expect(first != nil && first != 0, "cell 0's first serial \(String(describing: first))")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick(); window.tick()
    #expect(serials.seen[200] != nil && serials.seen[200] != 0)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 4000)
    window.tick(); window.tick(); window.tick()
    #expect(serials.seen[0] == first, "after the round trip \(String(describing: serials.seen[0]))")
}

private struct EqCell: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        Text("cell \(index)").frame(width: Pixels(60), height: Pixels(20))
    }
    static func == (l: EqCell, r: EqCell) -> Bool { l.index == r.index }
}

/// **3.10 (`LZ-P`, `LZ-S`).** A grid cell is an ordinary occurrence. A click on a `Button` cell fires it, Tab
/// walks the realised cells in order (cell 0, then 1), and a cell out of the window has no element; an
/// `.equatable()` cell is skipped on a warm redraw (26 skips, 0 evaluations: the window stays 13 rows of 2).
/// Mutations: hit registration skipped for units (the click fires nothing); a unit box rebuilt so the memo key
/// differs every frame (skips 0).
@Test @MainActor func aLazyGridCellIsAnOrdinaryOccurrence() throws {
    let log = HarnessLog()
    let buttons = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVGrid(columns: twoColumns, spacing: Pixels(0)) {
                ForEach(0..<1000) { index in Button("Tap \(index)") { log.add("tap \(index)") } }
            }
        }
    }
    buttons.tick(); buttons.tick()
    try buttons.click(try buttons.element(label: "Tap 1"))
    #expect(log.entries == ["tap 1"], "\(log.entries)")
    #expect(throws: TestHarnessError.self) { try buttons.element(label: "Tap 500") }
    buttons.typeKey(.tab)
    #expect(try buttons.focusedElement?.label == "Tap 0")
    buttons.typeKey(.tab)
    #expect(try buttons.focusedElement?.label == "Tap 1")

    let equatable = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVGrid(columns: twoColumns, spacing: Pixels(0)) {
                ForEach(0..<1000) { EqCell(index: $0).equatable() }
            }
        }
    }
    equatable.tick(); equatable.tick()
    equatable.window.setNeedsRedraw(); equatable.tick()
    let work = equatable.lastFrameWork
    #expect(work.lazyUnitsRealized == 26, "\(work.lazyUnitsRealized)")
    #expect(work.contentSkips == 26 && work.contentEvaluations == 0,
            "skips \(work.contentSkips) evaluations \(work.contentEvaluations)")
}

/// **3.11 (`LZ-F`, `LZ-R`, `IV-`).** A lazy grid taints its ancestors for the layout memo: with a `VStack`
/// around the scroller no frame (a plain redraw, a scroll, a resize that changes an adaptive grid's column
/// count) is served by a whole-placement hit, and after the resize the grid holds the new count: in 200
/// points `.adaptive(minimum: 45)` is 3 columns (13 rows, 39 cells), in 300 it is 5 (65). Mutation: make
/// `LazyGridLayout` `Hashable` over its fields without the track list (a root hit appears and the resized
/// grid keeps 3 columns).
@Test @MainActor func aLazyGridTaintsItsAncestorsAndAMemoHitIsNeverStale() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ProposalScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Pixels(45)))], spacing: Pixels(0)) {
                    ForEach(0..<10_000) { _ in Color.gray.frame(height: Pixels(20)) }
                }
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    #expect(window.lastFrameWork.lazyUnitsRealized == 39, "\(window.lastFrameWork.lazyUnitsRealized)")
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.lastFrameWork.layoutMemoRootHits == 0, "warm root hits \(window.lastFrameWork.layoutMemoRootHits)")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick()
    #expect(window.lastFrameWork.layoutMemoRootHits == 0, "scroll root hits \(window.lastFrameWork.layoutMemoRootHits)")
    window.resize(to: sz(300, 200))
    window.tick(); window.tick(); window.tick()
    #expect(window.lastFrameWork.layoutMemoRootHits == 0, "resize root hits \(window.lastFrameWork.layoutMemoRootHits)")
    #expect(window.lastFrameWork.lazyUnitsRealized % 5 == 0 && window.lastFrameWork.lazyUnitsRealized >= 65,
            "\(window.lastFrameWork.lazyUnitsRealized)")
}

private final class ProxyBox {
    var proxy: ScrollViewProxy?
    @MainActor func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

/// **3.12 (`LZ-O`, probe T10).** `scrollTo` reaches a cell that was never realised, through the line index:
/// cells 0 ... 599 sit in rows of 20 and cells 600 ... 1999 in rows of 80 (the estimate from the first rows
/// is wrong for cell 1400, row 700, whose true offset is 300 x 20 + 400 x 80 = 38 000), the request lands
/// on the estimate and the refinement carried into the next frame brings the cell into the 200-point
/// viewport, where it stays. Mutation: the refinement carry removed (the cell stays off screen).
@Test @MainActor func scrollToAnUnrealizedGridCellReachesIt() throws {
    let box = ProxyBox()
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = box.keep(proxy)
                ProposalScrollView {
                    LazyVGrid(columns: twoColumns, spacing: Pixels(0)) {
                        ForEach(0..<2000) { index in
                            ProposalText("cell \(index)").frame(height: Pixels(index < 600 ? 20 : 80))
                        }
                    }
                }
            }
        }
    }
    window.tick(); window.tick()
    #expect(throws: TestHarnessError.self) { try window.element(label: "cell 1400") }
    box.proxy?.scrollTo(1400)
    for _ in 0..<3 { window.tick() }
    let cell = try window.element(label: "cell 1400")
    #expect(cell.frame.origin.y >= Pixels(0) && cell.frame.origin.y + cell.frame.size.height <= Pixels(200),
            "cell 1400 at \(cell.frame)")
    window.tick(); window.tick()
    #expect(try window.element(label: "cell 1400").frame == cell.frame, "the target stays put")
}
