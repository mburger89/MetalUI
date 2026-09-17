import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Second critic round, finding 10 (ruling GR-AD), for
// `docs/superpowers/specs/2026-09-17-grids-design.md`.
//
// `Sources/MetalUI/Grid.swift`'s three `LayoutPass` registrars are public API of
// `MetalUI` and, until these tests, nothing called them: the lane-1 verifier
// found that `requestNativeGrid` passing `.center` for every alignment and
// `markNativeGridRow` passing `alignment: nil` both left the whole suite green,
// and the pin was deferred to lane 4. That is CLAUDE.md's "an API that exists,
// compiles and does nothing", so the forwarding is pinned here instead, one
// test per argument that the verifier showed could be dropped, each through a
// real `Frame` (the kernel's own rules are `NativeGridTests.swift`'s).
//
// Each test reads its cells' rects RELATIVE TO THE GRID's own rect, because a
// native root is centred in the window by `CN-J`; each `#require`s a control
// arm that answers differently, so "the figures agree" cannot be vacuous.

@MainActor
private final class GridProbe {
    var grid: ProposalNodeID?
    var cells: [String: ProposalNodeID] = [:]
}

/// Builds one grid through the public `LayoutPass` registrars. `rows` lists the
/// rows, each a list of (name, width, height); `spans` gives a cell's
/// `gridCellColumns` mark.
private struct GridUnderTest: ProposalElement {
    var probe: GridProbe
    var alignment: ProposalAlignment
    var rowAlignments: [ProposalAlignment?]
    var rows: [[(name: String, width: Double, height: Double)]]
    var spans: [String: Int] = [:]
    var horizontalSpacing: Double?
    var verticalSpacing: Double?

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        var children: [ProposalNodeID] = []
        for (index, cells) in rows.enumerated() {
            var marked: [ProposalNodeID] = []
            for cell in cells {
                let size = SizeD(width: cell.width, height: cell.height)
                let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }
                if let span = spans[cell.name] { pass.markNativeGridCell(node, columns: span) }
                probe.cells[cell.name] = node
                marked.append(node)
            }
            pass.markNativeGridRow(marked, alignment: rowAlignments[index])
            children.append(contentsOf: marked)
        }
        let grid = pass.requestNativeGrid(children: children, alignment: alignment,
                                          horizontalSpacing: horizontalSpacing,
                                          verticalSpacing: verticalSpacing)
        probe.grid = grid
        return (grid, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// Lays `element` out in a 140×90 frame and returns each named cell's rect with
/// the grid's own origin subtracted.
@MainActor
private func cellRects(_ element: GridUnderTest, _ probe: GridProbe) -> [String: LayoutRect] {
    var root = element
    let frame = Frame(contentSize: Size(width: Pixels(140), height: Pixels(90)), scaleFactor: 1)
    frame.render(&root)
    let grid = frame.tree.layout(probe.grid!.layoutNodeID)
    return probe.cells.mapValues { node in
        let rect = frame.tree.layout(node.layoutNodeID)
        return LayoutRect(x: rect.x - grid.x, y: rect.y - grid.y, width: rect.width, height: rect.height)
    }
}

private func r(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> LayoutRect {
    LayoutRect(x: x, y: y, width: width, height: height)
}

/// `LayoutPass.requestNativeGrid` hands its `alignment` to the kernel: one row
/// `[a 30x10, b 20x20]` places a at the top of its 20pt row under `.topLeading`
/// and 5pt down under `.center` (GA1, GL1).
///
/// Mutation (the lane-1 verifier's V2): `requestNativeGrid` passes `.center`
/// whatever it was given — a at y 5 in both arms, so the `.topLeading`
/// assertion fails and the control still holds.
@MainActor
@Test func requestNativeGridForwardsItsAlignmentToTheKernel() throws {
    let cells = [[(name: "a", width: 30.0, height: 10.0), (name: "b", width: 20.0, height: 20.0)]]
    let centred = GridProbe()
    let control = cellRects(GridUnderTest(probe: centred, alignment: .center,
                                          rowAlignments: [nil], rows: cells), centred)
    try #require(control["a"] == r(0, 5, 30, 10), "the .center control: \(String(describing: control["a"]))")

    let probe = GridProbe()
    let rects = cellRects(GridUnderTest(probe: probe, alignment: .topLeading,
                                        rowAlignments: [nil], rows: cells), probe)
    #expect(rects["a"] == r(0, 0, 30, 10), "GL1 a: \(String(describing: rects["a"]))")
    #expect(rects["b"] == r(38, 0, 20, 20), "GL1 b: \(String(describing: rects["b"]))")
}

/// `LayoutPass.markNativeGridRow` hands its `alignment` to the kernel: the row
/// alignment overrides the grid's vertically for that row's cells (GL3, GL9).
///
/// Mutation (the lane-1 verifier's V2b): `markNativeGridRow` passes `alignment:
/// nil` — row 0's a falls back to the grid's `.center` at y 5, and the control,
/// which declares no row alignment, is unmoved.
@MainActor
@Test func markNativeGridRowForwardsItsAlignmentToTheKernel() throws {
    let cells = [[(name: "a", width: 30.0, height: 10.0), (name: "b", width: 20.0, height: 20.0)]]
    let centred = GridProbe()
    let control = cellRects(GridUnderTest(probe: centred, alignment: .center,
                                          rowAlignments: [nil], rows: cells), centred)
    try #require(control["a"] == r(0, 5, 30, 10), "the unaligned-row control: \(String(describing: control["a"]))")

    let probe = GridProbe()
    let rects = cellRects(GridUnderTest(probe: probe, alignment: .center,
                                        rowAlignments: [.top], rows: cells), probe)
    #expect(rects["a"] == r(0, 0, 30, 10), "GL3 a: \(String(describing: rects["a"]))")
    #expect(rects["b"] == r(38, 0, 20, 20), "GL3 b: \(String(describing: rects["b"]))")
}

/// `LayoutPass.markNativeGridCell` hands its `columns` count to the kernel:
/// GX1's `[a 30x10, b 20x20] [c 100x10 span 2]` is 100 wide with columns 51 and
/// 41, so b sits at x 59; unmarked, c is a single-column cell, column 0 widens
/// to 100 and b sits at x 108 (GX1, GR-F). `.topLeading` throughout, so no
/// figure here is a half-pixel that the root's centring could round.
///
/// Mutation: `markNativeGridCell` passes `columns: nil` — the spanned arm reads
/// the control's 108 and fails.
@MainActor
@Test func markNativeGridCellForwardsItsColumnCountToTheKernel() throws {
    let rows = [[(name: "a", width: 30.0, height: 10.0), (name: "b", width: 20.0, height: 20.0)],
                [(name: "c", width: 100.0, height: 10.0)]]
    let unmarked = GridProbe()
    let control = cellRects(GridUnderTest(probe: unmarked, alignment: .topLeading,
                                          rowAlignments: [nil, nil], rows: rows), unmarked)
    try #require(control["b"] == r(108, 0, 20, 20), "the unspanned control: \(String(describing: control["b"]))")

    let probe = GridProbe()
    let rects = cellRects(GridUnderTest(probe: probe, alignment: .topLeading, rowAlignments: [nil, nil],
                                        rows: rows, spans: ["c": 2]), probe)
    #expect(rects["a"] == r(0, 0, 30, 10), "GX1 a: \(String(describing: rects["a"]))")
    #expect(rects["b"] == r(59, 0, 20, 20), "GX1 b: \(String(describing: rects["b"]))")
    #expect(rects["c"] == r(0, 28, 100, 10), "GX1 c: \(String(describing: rects["c"]))")
}

/// `LayoutPass.requestNativeGrid` hands its `horizontalSpacing` and
/// `verticalSpacing` to the kernel: GA1 `[a 30x10, b 20x20] [c 10x30, d 40x10]`
/// at 3/5 puts b at x 33 and c at y 25, where the nil-spacing control (the 8pt
/// platform default per pair) puts them at 38 and 28 (GA1, GA3, `GR-D`).
/// `.topLeading` throughout, as in the span test above.
///
/// Mutation (the lane-1 verifier's H1): `requestNativeGrid` forwards
/// `horizontalSpacing: nil, verticalSpacing: nil` whatever it was given — the
/// spaced arm reads the control's 38 and 28 and fails, and the control holds.
@MainActor
@Test func requestNativeGridForwardsItsSpacingToTheKernel() throws {
    let rows = [[(name: "a", width: 30.0, height: 10.0), (name: "b", width: 20.0, height: 20.0)],
                [(name: "c", width: 10.0, height: 30.0), (name: "d", width: 40.0, height: 10.0)]]
    let defaulted = GridProbe()
    let control = cellRects(GridUnderTest(probe: defaulted, alignment: .topLeading,
                                          rowAlignments: [nil, nil], rows: rows), defaulted)
    try #require(control["b"] == r(38, 0, 20, 20), "the default-spacing control b: \(String(describing: control["b"]))")
    try #require(control["c"] == r(0, 28, 10, 30), "the default-spacing control c: \(String(describing: control["c"]))")

    let probe = GridProbe()
    let rects = cellRects(GridUnderTest(probe: probe, alignment: .topLeading, rowAlignments: [nil, nil],
                                        rows: rows, horizontalSpacing: 3, verticalSpacing: 5), probe)
    #expect(rects["a"] == r(0, 0, 30, 10), "GA3 a: \(String(describing: rects["a"]))")
    #expect(rects["b"] == r(33, 0, 20, 20), "GA3 b: \(String(describing: rects["b"]))")
    #expect(rects["c"] == r(0, 25, 10, 30), "GA3 c: \(String(describing: rects["c"]))")
    #expect(rects["d"] == r(33, 25, 40, 10), "GA3 d: \(String(describing: rects["d"]))")
}
