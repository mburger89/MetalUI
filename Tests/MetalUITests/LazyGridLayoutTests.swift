import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lazy containers, lane 2: the grids' layout facts (spec section 5, tests 3.2-3.5; rulings `LZ-K`, `LZ-L`,
// `LZ-M`; probe `docs/probes/swiftui-lazy-containers.swift` arms C5, C7-C14b, whose recorded figures are the
// literals here). The instrument is lane 1's: a `ProbeHost` layout answering 200 x 200 that asks its one
// child (the grid) for its size at the arm's proposal and places it at the host's origin, so every literal
// is absolute; cells are `Cell` leaves of a fixed size that log their placed bounds. Red-before (record
// section 134): the types did not exist, so the file failed to compile (`cannot find 'LazyVGrid' in scope`).

private func bounds(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
           size: Size(width: Pixels(width), height: Pixels(height)))
}

private final class GridAnswer: @unchecked Sendable {
    var size: SizeD?
}

private struct ProbeHost: ProposalLayout {
    let proposal: ProposedSize
    let answer: GridAnswer

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 200, height: 200))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        answer.size = subviews[0].sizeThatFits(self.proposal).size
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading, proposal: self.proposal)
    }
}

private struct Cell: ProposalElement {
    let name: String
    let width: Double
    let height: Double
    let log: LeafBoundsLog

    init(_ name: String, _ width: Double = 10, _ height: Double = 10, log: LeafBoundsLog) {
        self.name = name
        self.width = width
        self.height = height
        self.log = log
    }

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.byName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

/// Renders `grid` under the host at `proposal` and returns the grid's answer.
@MainActor
private func render<Grid: ProposalElementGroup>(_ proposal: ProposedSize, scale: Float = 1,
                                                @ProposalContentBuilder _ grid: () -> Grid) -> SizeD? {
    let answer = GridAnswer()
    var root = ProposalLayoutContainer(ProbeHost(proposal: proposal, answer: answer), content: grid)
    Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: scale).render(&root)
    return answer.size
}

private let at200 = ProposedSize(width: 200, height: 200)

/// Four 10 x 10 cells named c0 ... c3.
@MainActor @ProposalContentBuilder
private func four(_ log: LeafBoundsLog) -> some ProposalElementGroup {
    Cell("c0", log: log)
    Cell("c1", log: log)
    Cell("c2", log: log)
    Cell("c3", log: log)
}

/// **3.2a (probe C8, C8c; `LZ-K`, `LZ-W`).** The grid's `alignment` does two things the probe separates: it
/// places the TRACKS in the proposal and it is the default alignment of a cell in its track (a `GridItem`
/// with no alignment of its own takes the grid's). Two `.fixed(30)` columns, gap 8, tracks 68 wide in 200:
/// `.leading` puts the tracks at 0 and the 10-wide cells at the leading edge of each, c0 at x 0, c1 at
/// 30 + 8 = 38 (a centred cell would be at 10 and 48: that is the separating arm); the default `.center` puts
/// the tracks at (200 - 68) / 2 = 66 and the cells centred, c0 at 66 + 10 = 76, c1 at 66 + 38 + 10 = 114. Rows
/// are 10 + 8 apart: y 0, 18; the grid is 200 wide (`max(proposal, tracks)`) and 28 tall.
/// Mutations: the grid alignment not placing the tracks (leading: c0 at 0 but c1's track moved, centre: 0);
/// the cell taking `.center` always (leading: c0 at 10).
@MainActor
@Test func aLazyVGridPlacesTracksAndCellsByTheGridAlignment() {
    let leading = LeafBoundsLog()
    let leadingSize = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(30))), GridItem(.fixed(Pixels(30)))], alignment: .leading) {
            four(leading)
        }
    }
    #expect(leadingSize == SizeD(width: 200, height: 28))
    #expect(leading.byName["c0"] == bounds(0, 0, 10, 10))
    #expect(leading.byName["c1"] == bounds(38, 0, 10, 10))
    #expect(leading.byName["c2"] == bounds(0, 18, 10, 10))
    #expect(leading.byName["c3"] == bounds(38, 18, 10, 10))

    let centre = LeafBoundsLog()
    let centreSize = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(30))), GridItem(.fixed(Pixels(30)))]) { four(centre) }
    }
    #expect(centreSize == SizeD(width: 200, height: 28))
    #expect(centre.byName["c0"] == bounds(76, 0, 10, 10))
    #expect(centre.byName["c1"] == bounds(114, 0, 10, 10))
    #expect(centre.byName["c2"] == bounds(76, 18, 10, 10))
    #expect(centre.byName["c3"] == bounds(114, 18, 10, 10))
}

/// **3.2b (probe C9, C7, C10, C5; `LZ-K`, `LZ-M`).** An item's own `alignment` places its cells in the
/// track (C9: `.topLeading` and `.bottomTrailing`, cells 10 x 10 and 10 x 20 in row 0 (20 tall), tracks 30,
/// gap 8, origin 66: c0 (66, 0), c1 at 66 + 38 + 20 = 124 with y 0 (bottom of a 20 row), c2 (66, 28), c3 at
/// x 124, y 28 (a 10-tall row), size 200 x 38 = 20 + 8 + 10); the gap after a column is its item's `spacing`
/// and the grid's `spacing:` is the row gap (C7: columns 30 gap 20 and 30, rows 4 apart: tracks 80 wide at
/// 60, c0 at 60 + 10 = 70, c1 at 60 + 50 + 10 = 120, rows y 0 and 14, size 200 x 24); a row is as tall as its
/// tallest cell and the others sit centred in it (C10 at width 100, columns (100 - 8) / 2 = 46: c0 at
/// (46 - 10) / 2 = 18, c1 at 54 + 18 = 72, row 1 holds 10 x 30 and 10 x 10: c2 at y 18, c3 at 18 + 10 = 28,
/// size 100 x 48 = 10 + 8 + 30); minima that exceed the proposal overflow to the right from 0 (C5: two
/// `.flexible(minimum: 120)`: tracks 120, gap 8, width 248, c0 at 55, c1 at 128 + 55 = 183).
/// Mutations: the cell alignment ignored (C9); a row sized by its first cell (C10); the origin on overflow
/// centred (C5: -24 + 55).
@MainActor
@Test func aLazyVGridPlacesCellsInTheirTracksAndSizesRowsByTheirTallestCell() {
    let c9 = LeafBoundsLog()
    let c9Size = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(30)), alignment: .topLeading),
                            GridItem(.fixed(Pixels(30)), alignment: .bottomTrailing)]) {
            Cell("c0", log: c9)
            Cell("c1", 10, 20, log: c9)
            Cell("c2", log: c9)
            Cell("c3", log: c9)
        }
    }
    #expect(c9Size == SizeD(width: 200, height: 38))
    #expect(c9.byName["c0"] == bounds(66, 0, 10, 10))
    #expect(c9.byName["c1"] == bounds(124, 0, 10, 20))
    #expect(c9.byName["c2"] == bounds(66, 28, 10, 10))
    #expect(c9.byName["c3"] == bounds(124, 28, 10, 10))

    let c7 = LeafBoundsLog()
    let c7Size = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(30)), spacing: Pixels(20)),
                            GridItem(.fixed(Pixels(30)), spacing: Pixels(0))], spacing: Pixels(4)) { four(c7) }
    }
    #expect(c7Size == SizeD(width: 200, height: 24))
    #expect(c7.byName["c0"] == bounds(70, 0, 10, 10))
    #expect(c7.byName["c1"] == bounds(120, 0, 10, 10))
    #expect(c7.byName["c2"] == bounds(70, 14, 10, 10))
    #expect(c7.byName["c3"] == bounds(120, 14, 10, 10))

    let c10 = LeafBoundsLog()
    let c10Size = render(ProposedSize(width: 100)) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
            Cell("c0", log: c10)
            Cell("c1", log: c10)
            Cell("c2", 10, 30, log: c10)
            Cell("c3", log: c10)
        }
    }
    #expect(c10Size == SizeD(width: 100, height: 48))
    #expect(c10.byName["c0"] == bounds(18, 0, 10, 10))
    #expect(c10.byName["c1"] == bounds(72, 0, 10, 10))
    #expect(c10.byName["c2"] == bounds(18, 18, 10, 30))
    #expect(c10.byName["c3"] == bounds(72, 28, 10, 10))

    let c5 = LeafBoundsLog()
    let c5Size = render(at200) {
        LazyVGrid(columns: [GridItem(.flexible(minimum: Pixels(120))), GridItem(.flexible(minimum: Pixels(120)))]) {
            four(c5)
        }
    }
    #expect(c5Size == SizeD(width: 248, height: 28))
    #expect(c5.byName["c0"] == bounds(55, 0, 10, 10))
    #expect(c5.byName["c1"] == bounds(183, 0, 10, 10))
    #expect(c5.byName["c2"] == bounds(55, 18, 10, 10))
    #expect(c5.byName["c3"] == bounds(183, 18, 10, 10))
}

/// **3.3 (probe C11).** `LazyHGrid` is the same on the other axis: `rows: [.flexible, .flexible]` at 200 x
/// 100, cells filling a column at a time (c0, c1 then c2, c3). Rows are (100 - 8) / 2 = 46 tall at y 0 and 54,
/// so a 10-tall cell sits at 18 and 72; column 0 is 10 wide (c0, c1), column 1 is as wide as its widest cell
/// (c2 is 30, c3 10), the columns 8 apart: c2 at x 10 + 8 = 18, c3 centred in the 30-wide column at 28;
/// the grid is 48 wide (10 + 8 + 30) and the proposed 100 tall. Mutation: the axes not swapped in the
/// layout (the grid fills 200 wide).
@MainActor
@Test func aLazyHGridIsTheSameOnTheOtherAxis() {
    let log = LeafBoundsLog()
    let size = render(ProposedSize(width: 200, height: 100)) {
        LazyHGrid(rows: [GridItem(.flexible()), GridItem(.flexible())]) {
            Cell("c0", log: log)
            Cell("c1", log: log)
            Cell("c2", 30, 10, log: log)
            Cell("c3", log: log)
        }
    }
    #expect(size == SizeD(width: 48, height: 100))
    #expect(log.byName["c0"] == bounds(0, 18, 10, 10))
    #expect(log.byName["c1"] == bounds(0, 72, 10, 10))
    #expect(log.byName["c2"] == bounds(18, 18, 30, 10))
    #expect(log.byName["c3"] == bounds(28, 72, 10, 10))
}

/// **3.4 (probe LZ4 of `swiftui-lazy-grid-scope.swift`, C12, C13; `LZ-K`).** At a nil width the tracks come
/// from the FIRST row's cells. Two flexible columns, cells a 30, b 20, c 100, d 20 (10 tall): the grid asks
/// 30 + 8 + 20 = 58 and shares it, tracks (58 - 8) / 2 = 25, so a is at (25 - 30) / 2 = -2.5, b at 33 +
/// 2.5 = 35.5, row 1: c at (25 - 100) / 2 = -37.5, d at 35.5, y 0 and 18, size 58 x 28 (SwiftUI's unrounded
/// figures; the kernel snaps every placed edge to a whole point, round half away from zero, on the cumulative
/// edges: a is (-2.5 .. 27.5) = (-3, 31 wide), b (35.5 .. 55.5) = (36, 20), c (-37.5 .. 62.5) = (-38, 101),
/// d (36, 20), asserted below); an adaptive item is
/// ONE column at nil whose width is its cell's (C12: four 10 x 10 cells, size 10 x 64 = 4 x 10 + 3 x 8, each
/// at x 0); no items is 0 x 0 (C13). Mutation: the first row's cells replaced by every realised cell (the
/// width becomes 100 + 8 + 20).
@MainActor
@Test func aNilWidthTakesTheFirstRowAndAnAdaptiveItemMakesOneColumn() {
    let lz4 = LeafBoundsLog()
    let lz4Size = render(ProposedSize()) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
            Cell("a", 30, 10, log: lz4)
            Cell("b", 20, 10, log: lz4)
            Cell("c", 100, 10, log: lz4)
            Cell("d", 20, 10, log: lz4)
        }
    }
    #expect(lz4Size == SizeD(width: 58, height: 28))
    #expect(lz4.byName["a"] == bounds(-3, 0, 31, 10))
    #expect(lz4.byName["b"] == bounds(36, 0, 20, 10))
    #expect(lz4.byName["c"] == bounds(-38, 18, 101, 10))
    #expect(lz4.byName["d"] == bounds(36, 18, 20, 10))

    let c12 = LeafBoundsLog()
    let c12Size = render(ProposedSize()) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Pixels(45)))]) { four(c12) }
    }
    #expect(c12Size == SizeD(width: 10, height: 64))
    #expect(c12.byName["c0"] == bounds(0, 0, 10, 10))
    #expect(c12.byName["c1"] == bounds(0, 18, 10, 10))
    #expect(c12.byName["c2"] == bounds(0, 36, 10, 10))
    #expect(c12.byName["c3"] == bounds(0, 54, 10, 10))

    let none = LeafBoundsLog()
    #expect(render(at200) { LazyVGrid(columns: []) { four(none) } } == SizeD(width: 0, height: 0))
}

/// **3.5 (probe C14, C14b; divergence 635).** A `ForEach` element that produces several views is ONE cell
/// holding a vertical stack, where SwiftUI makes every view a cell (C14b: a and b are cells 0 and 1 of row 0,
/// c is cell 0 of row 1). Two `.fixed(40)` columns, element 0 = a, b (10 x 10), element 1 = c: cell 0 is the
/// stack a over b (spacing 8: 10 + 8 + 10 = 28 tall, 10 wide), cell 1 is c; tracks 40, gap 8, origin
/// (200 - 88) / 2 = 56; row 0 is 28 tall; a at 56 + 15 = 71 (y 0, centred in the 28-tall cell the stack fills),
/// b at (71, 18), c in the second track at 56 + 48 + 15 = 119, y (28 - 10) / 2 = 9; the grid is 200 x 28.
/// SwiftUI's C14b has a (71, 0), b (119, 0), c (71, 18): this arm differs from it in all three.
/// A single `.fixed(40)` column (C14) agrees with SwiftUI: a (95, 0), b (95, 18), c (95, 36), 200 x 46.
/// Mutation: a cell = a node (the stack's two nodes become two cells: a (71, 0), b (119, 0)).
@MainActor
@Test func aForEachElementOfSeveralViewsIsOneGridCell() {
    let two = LeafBoundsLog()
    let twoSize = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(40))), GridItem(.fixed(Pixels(40)))]) {
            ForEach(0..<2) { index in
                if index == 0 {
                    Cell("a", log: two)
                    Cell("b", log: two)
                } else {
                    Cell("c", log: two)
                }
            }
        }
    }
    #expect(twoSize == SizeD(width: 200, height: 28))
    #expect(two.byName["a"] == bounds(71, 0, 10, 10))
    #expect(two.byName["b"] == bounds(71, 18, 10, 10))
    #expect(two.byName["c"] == bounds(119, 9, 10, 10))

    let one = LeafBoundsLog()
    let oneSize = render(at200) {
        LazyVGrid(columns: [GridItem(.fixed(Pixels(40)))]) {
            ForEach(0..<2) { index in
                if index == 0 {
                    Cell("a", log: one)
                    Cell("b", log: one)
                } else {
                    Cell("c", log: one)
                }
            }
        }
    }
    #expect(oneSize == SizeD(width: 200, height: 46))
    #expect(one.byName["a"] == bounds(95, 0, 10, 10))
    #expect(one.byName["b"] == bounds(95, 18, 10, 10))
    #expect(one.byName["c"] == bounds(95, 36, 10, 10))
}

/// **3.13 (`LZ-L`, `LZ-Y`, divergence 638).** An adaptive grid OUTSIDE any scroller still packs by the width
/// of the previous frame: in a 200-point `VStack`, `.adaptive(minimum: 45)` and six 10 x 10 cells, the first
/// frame has no stored width and builds one column (six rows); the grid stores its width in prepaint
/// (`noteWidth`) and the next frames settle at n = floor((200 + 8) / 53) = **3** columns, two rows: c0 c1 c2 at
/// y 0 and c3 c4 c5 at 10 + 8 = 18, the tracks (200 - 16) / 3 = 61.33 wide (c0 centred at 25.67, c1 at 95,
/// c2 at 164.33; the kernel rounds to 26, 95, 164). Every container is unbounded here (no scroller): one
/// counted. Mutation: the width not stored outside a scroller (the grid stays at one column for ever).
@MainActor
@Test func anAdaptiveGridOutsideAScrollerPacksFromItsStoredWidth() {
    let states = StateTable()
    let log = LeafBoundsLog()
    var frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1, stateTable: states)
    func draw() {
        frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1, stateTable: states)
        var root = VStack(alignment: .leading, spacing: Pixels(0)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Pixels(45)))]) {
                Cell("c0", log: log); Cell("c1", log: log); Cell("c2", log: log)
                Cell("c3", log: log); Cell("c4", log: log); Cell("c5", log: log)
            }
        }
        frame.render(&root)
    }
    draw()
    // (The root is centred in the frame, so the rows are compared with c0's own y.)
    let firstTop = log.byName["c0"]?.origin.y ?? Pixels(0)
    #expect(log.byName["c1"]?.origin.y == firstTop + Pixels(10 + 8), "first frame: one column, c1 below c0")
    #expect(frame.wantsAnotherFrame, "the first frame asks for the corrected count")
    for _ in 0..<4 where frame.wantsAnotherFrame { draw() }
    #expect(!frame.wantsAnotherFrame)
    #expect(frame.lazyWork == LazyWork(unitsRealized: 6, linesRealized: 2, unbounded: 1), "\(frame.lazyWork)")
    let top = log.byName["c0"]?.origin.y.value ?? 0
    #expect(log.byName["c0"] == bounds(26, top, 10, 10), "\(String(describing: log.byName["c0"]))")
    #expect(log.byName["c1"] == bounds(95, top, 10, 10))
    #expect(log.byName["c2"] == bounds(164, top, 10, 10))
    #expect(log.byName["c3"] == bounds(26, top + 18, 10, 10))
    #expect(log.byName["c5"] == bounds(164, top + 18, 10, 10))
}
