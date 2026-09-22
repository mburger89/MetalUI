import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Lane 4 ("elements, identity and the pipeline") of
// `docs/superpowers/specs/2026-09-17-grids-design.md`: rulings GR-J, GR-K,
// GR-T, GR-V, GR-AF and the element halves of GR-G and GR-H, in
// `docs/superpowers/2026-09-17-grids-decisions.md`.
//
// Every arm name and number is SwiftUI's, read by `docs/probes/swiftui-grid.swift`
// (revision 6), whose header holds the recorded output. The kernel's own rules
// are `Tests/MetalUILayoutTests/NativeGridTests.swift`'s; these tests exercise
// `Grid`, `GridRow` and the four cell modifiers through the ELEMENT API and read
// what the pipeline placed.
//
// **How an arm is read.** A nil-proposal arm is wrapped in `.fixedSize()`, which
// proposes nil×nil to the grid (a window root is proposed the content size, so
// without it every arm would be the finite solve); an arm probed at a concrete
// proposal is the window root at exactly that size. The window is the arm's
// answer plus 20 on each axis, so `CN-J`'s centring offset is the integer 10 and
// a rect rounded absolutely equals the probe's rect rounded relatively. Cell
// rects are read from each leaf's own `prepaint` bounds with the ROOT element's
// origin subtracted; the grid's own rect is the root's, since `.fixedSize()`
// adds no geometry.

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func px(_ v: Double) -> Pixels { Pixels(Float(v)) }

/// The probe's rect, rounded as the kernel stores rects (`NativeGridTests`' `r`).
private func r(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> LayoutRect {
    roundLayout([LayoutRect(x: x, y: y, width: width, height: height)])[0]
}

private func size(_ width: Double, _ height: Double) -> SizeD {
    SizeD(width: width, height: height)
}

/// Where each named cell landed, and the id it was given.
@MainActor
private final class CellProbe {
    var bounds: [String: Bounds<Pixels>] = [:]
    var ids: [String: GlobalElementID] = [:]

    /// The probe's `fx`: a fixed-size leaf.
    func fx(_ name: String, _ width: Double, _ height: Double) -> Cell {
        Cell(name: name, probe: self) { _ in SizeD(width: width, height: height) }
    }

    /// The probe's `fl`: proposal ?? 10 on both axes.
    func fl(_ name: String) -> Cell {
        Cell(name: name, probe: self) { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) }
    }
}

/// One of the probe's leaves as a MetalUI proposal element.
private struct Cell: ProposalElement {
    let name: String
    let probe: CellProbe
    let answer: @Sendable (ProposedSize) -> SizeD

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let answer = answer
        return (pass.requestNativeLeaf { LayoutMeasurement(size: answer($0)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        probe.bounds[name] = bounds
        probe.ids[name] = id
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

@MainActor
private func laidOut<Root: Element>(_ width: Double, _ height: Double,
                                    _ make: () -> Root) -> Frame {
    var root = make()
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)),
                      scaleFactor: 1, recordsElementBounds: true)
    frame.render(&root)
    return frame
}

/// Every recorded cell rect with the root element's own origin subtracted.
@MainActor
private func cells(_ frame: Frame, _ probe: CellProbe) throws -> [String: LayoutRect] {
    let root = try #require(frame.elementBounds[rootID], "the root element recorded no bounds")
    return probe.bounds.mapValues {
        LayoutRect(x: Double($0.origin.x.value - root.origin.x.value),
                   y: Double($0.origin.y.value - root.origin.y.value),
                   width: Double($0.size.width.value), height: Double($0.size.height.value))
    }
}

@MainActor
private func rootSize(_ frame: Frame) throws -> SizeD {
    let root = try #require(frame.elementBounds[rootID], "the root element recorded no bounds")
    return SizeD(width: Double(root.size.width.value), height: Double(root.size.height.value))
}

/// The answer one proposal element gives on its own, with no container: it is
/// registered through a throwaway `Frame` and measured by the kernel directly,
/// so no placement, centring or rounding is involved.
@MainActor
private func measureAlone<E: ProposalElement>(_ element: E, _ width: Double?,
                                              _ height: Double?) -> SizeD {
    var copy = element
    let frame = Frame(contentSize: Size(width: px(400), height: px(400)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (node, _) = copy.requestProposalLayout(rootID, pass: &pass)
    return frame.tree.measureNativeLayout(root: node.layoutNodeID,
                                          proposal: ProposedSize(width: width, height: height)).size
}

// MARK: - 4.1 the probe's arms through the element API

/// **`Grid`, `GridRow` and the four cell modifiers lay out as the probe reads.**
///
/// Eleven arms, each SwiftUI's: GA1 (the shape), GL1 (`Grid(alignment:)`), GA3
/// (explicit spacing), GP2 (a flexible cell at 200×100), GL3
/// (`GridRow(alignment:)`), GX1 (`.gridCellColumns(2)`), GL5
/// (`.gridColumnAlignment(.trailing)`), GL11 (`.gridCellAnchor(.trailing)` on a
/// non-row child), GU9 (`.gridCellUnsizedAxes(.horizontal)`), GF14
/// (`.frame(maxWidth: .infinity)` inside a cell) and GF16 (a `Color` cell).
///
/// Mutations: `Grid` passes `horizontalSpacing` as `verticalSpacing` (GA3's b
/// reads 38 and its c 25 → the arm fails on both axes); `Grid` discards its own
/// `alignment` and always passes `.center` to `requestNativeGrid` (GL1's four
/// rects, and only GL1's).
@MainActor
@Test func gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI() throws {
    do { // GA1 78×58
        let p = CellProbe()
        let frame = laidOut(98, 78) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 58), "GA1 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GA1 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(48, 0, 20, 20), "GA1 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(10, 28, 10, 30), "GA1 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 38, 40, 10), "GA1 d: \(String(describing: rects["d"]))")
    }
    do { // GL1 — Grid(alignment: .topLeading) over GA1's leaves
        // GA1 above is the discriminating control: the same four leaves in the
        // same window, whose `a` sits at y 5 and whose `b` at x 48 under the
        // default `.center`; here both take their slots' leading edge. This arm
        // is what pins the `Grid` ELEMENT's own `alignment` property reaching
        // `requestNativeGrid` — the `LayoutPass` → kernel hop alone is
        // `requestNativeGridForwardsItsAlignmentToTheKernel`'s (lane 1's
        // verifier handed this arm to lane 4; ruling `GR-AP` item 7).
        let p = CellProbe()
        let frame = laidOut(98, 78) {
            Grid(alignment: .topLeading) {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 58), "GL1 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 0, 30, 10), "GL1 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(38, 0, 20, 20), "GL1 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(0, 28, 10, 30), "GL1 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 28, 40, 10), "GL1 d: \(String(describing: rects["d"]))")
    }
    do { // GA3 73×55, spacing 3/5
        let p = CellProbe()
        let frame = laidOut(93, 75) {
            Grid(horizontalSpacing: px(3), verticalSpacing: px(5)) {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(73, 55), "GA3 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GA3 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(43, 0, 20, 20), "GA3 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(10, 25, 10, 30), "GA3 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(33, 35, 40, 10), "GA3 d: \(String(describing: rects["d"]))")
    }
    do { // GP2 at 200×100
        let p = CellProbe()
        let frame = laidOut(200, 100) {
            Grid {
                GridRow { p.fl("a"); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }
        }
        #expect(try rootSize(frame) == size(200, 100), "GP2 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 0, 152, 62), "GP2 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(170, 21, 20, 20), "GP2 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(71, 70, 10, 30), "GP2 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(160, 80, 40, 10), "GP2 d: \(String(describing: rects["d"]))")
    }
    do { // GL3, GridRow(alignment: .top) on row 0
        let p = CellProbe()
        let frame = laidOut(98, 78) {
            Grid {
                GridRow(alignment: .top) { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 58), "GL3 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 0, 30, 10), "GL3 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(48, 0, 20, 20), "GL3 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(10, 28, 10, 30), "GL3 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 38, 40, 10), "GL3 d: \(String(describing: rects["d"]))")
    }
    do { // GX1, .gridCellColumns(2)
        let p = CellProbe()
        let frame = laidOut(120, 58) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 100, 10).gridCellColumns(2) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(100, 38), "GX1 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(10.5, 5, 30, 10), "GX1 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(69.5, 0, 20, 20), "GX1 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(0, 28, 100, 10), "GX1 c: \(String(describing: rects["c"]))")
    }
    do { // GL5, .gridColumnAlignment(.trailing) declared in a later row
        let p = CellProbe()
        let frame = laidOut(98, 78) {
            Grid {
                GridRow { p.fx("a", 10, 10); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 30, 30).gridColumnAlignment(.trailing); p.fx("d", 40, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 58), "GL5 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(20, 5, 10, 10), "GL5 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(48, 0, 20, 20), "GL5 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(0, 28, 30, 30), "GL5 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 38, 40, 10), "GL5 d: \(String(describing: rects["d"]))")
    }
    do { // GL11, .gridCellAnchor(.trailing) on a non-row child
        let p = CellProbe()
        let frame = laidOut(78, 68) {
            Grid {
                GridRow { p.fx("a", 40, 10); p.fx("b", 10, 30) }
                p.fx("x", 10, 10).gridCellAnchor(.trailing)
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(58, 48), "GL11 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 10, 40, 10), "GL11 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(48, 0, 10, 30), "GL11 b: \(String(describing: rects["b"]))")
        #expect(rects["x"] == r(48, 38, 10, 10), "GL11 x: \(String(describing: rects["x"]))")
    }
    do { // GU9, .gridCellUnsizedAxes(.horizontal) at 200×100
        let p = CellProbe()
        let frame = laidOut(200, 100) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                p.fl("x").gridCellUnsizedAxes(.horizontal)
            }
        }
        #expect(try rootSize(frame) == size(58, 100), "GU9 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GU9 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(38, 0, 20, 20), "GU9 b: \(String(describing: rects["b"]))")
        #expect(rects["x"] == r(0, 28, 58, 72), "GU9 x: \(String(describing: rects["x"]))")
    }
    do { // GF14, .frame(maxWidth: .infinity) inside a cell, at 200×100
        let p = CellProbe()
        let frame = laidOut(200, 100) {
            Grid {
                GridRow { p.fx("a", 30, 10).frame(maxWidth: px(.infinity)); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }
        }
        #expect(try rootSize(frame) == size(200, 58), "GF14 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(61, 5, 30, 10), "GF14 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(170, 0, 20, 20), "GF14 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(71, 28, 10, 30), "GF14 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(160, 38, 40, 10), "GF14 d: \(String(describing: rects["d"]))")
    }
    do { // GF16, a Color cell at 200×100 (the probe reads it through a background leaf)
        let p = CellProbe()
        let frame = laidOut(200, 100) {
            Grid {
                GridRow { Color(.accent); p.fx("b", 20, 20) }
                GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
            }
        }
        #expect(try rootSize(frame) == size(200, 100), "GF16 size")
        let rects = try cells(frame, p)
        #expect(rects["b"] == r(170, 21, 20, 20), "GF16 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(71, 70, 10, 30), "GF16 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(160, 80, 40, 10), "GF16 d: \(String(describing: rects["d"]))")
    }
}

// MARK: - 4.2 every proposal modifier carries a cell attribute

/// Registers `cell` and one plain sibling as ONE grid row and returns the plan.
///
/// Registration only — no layout: the question is which marks the plan's walk
/// found, which `NativeGridPlan` answers exactly where a rect comparison would
/// need geometry the wrapper itself changes (lane 3's `GR-AL` item 1).
@MainActor
private func rowPlan<W: ProposalElementGroup>(@ElementBuilder _ cell: () -> W) throws
    -> NativeGridPlan {
    var root = Grid { GridRow { cell(); Rectangle(width: px(10), height: px(10)) } }
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (node, _) = root.requestLayout(rootID, pass: &pass)
    return try #require(frame.tree.nativeGridPlan(node), "the root is not a grid")
}

/// The same with NO enclosing `GridRow`, so a row token written inside `cell`
/// is the only one there is.
@MainActor
private func bareplan<W: ProposalElementGroup>(@ElementBuilder _ cell: () -> W) throws
    -> NativeGridPlan {
    var root = Grid { cell(); Rectangle(width: px(10), height: px(10)) }
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (node, _) = root.requestLayout(rootID, pass: &pass)
    return try #require(frame.tree.nativeGridPlan(node), "the root is not a grid")
}

/// **Every proposal modifier MetalUI spells carries a grid-cell attribute, and
/// every container stops it**, as the probe's GWS/GWA/GWC/GWU/row groups read.
///
/// Nineteen spellings — the unwrapped control, the twelve `ModifiedContent`
/// cases, `.onTap`, `.disabled`, an overlay's primary and its content side, a
/// `.background { }` content side, `HStack { one }` and `ZStack { one }` — each
/// read five ways: the span, the anchor, the column alignment, the unsized axes
/// and the row token. `carries` is the probe's reading for that spelling
/// (GWS/GWA/GWC/GWU 1–14 carry, 15–18 do not).
///
/// The walk itself is the kernel's and is pinned by test 3.10
/// (`cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers`);
/// what is pinned HERE is that each MetalUI spelling registers a node kind the
/// walk agrees with, and that `GridCellModifier` writes the attribute it names.
///
/// Mutation: `GridCellModifier` drops its `.columnAlignment` case (every column
/// alignment arm reads nil; nothing else moves).
@MainActor
@Test func everyProposalModifierCarriesAGridCellAttributeAsTheProbeReads() throws {
    let p = CellProbe()

    func span(_ label: String, _ expected: Int,
              @ElementBuilder _ cell: () -> some ProposalElementGroup) throws {
        let plan = try rowPlan(cell)
        #expect(plan.cells[0].span == expected, "span through \(label): \(plan.cells[0].span)")
    }
    func anchor(_ label: String, _ expected: ProposalAlignment?,
                @ElementBuilder _ cell: () -> some ProposalElementGroup) throws {
        let plan = try rowPlan(cell)
        #expect(plan.cells[0].anchor == expected,
                "anchor through \(label): \(String(describing: plan.cells[0].anchor))")
    }
    func column(_ label: String, _ expected: ProposalAlignment?,
                @ElementBuilder _ cell: () -> some ProposalElementGroup) throws {
        let plan = try rowPlan(cell)
        #expect(plan.columnAlignments[0] == expected,
                "column alignment through \(label): \(String(describing: plan.columnAlignments[0]))")
    }
    func unsized(_ label: String, _ expected: ProposalAxes,
                 @ElementBuilder _ cell: () -> some ProposalElementGroup) throws {
        let plan = try rowPlan(cell)
        #expect(plan.cells[0].unsizedAxes == expected,
                "unsized axes through \(label): \(plan.cells[0].unsizedAxes)")
    }
    func rowToken(_ label: String, _ expected: Bool,
                  @ElementBuilder _ cell: () -> some ProposalElementGroup) throws {
        let plan = try bareplan(cell)
        #expect(plan.cells[0].isRowCell == expected,
                "row token through \(label): \(plan.cells[0].isRowCell)")
    }

    // 0 — the unwrapped control. Its four attributes must arrive, or every
    // "carried" arm below is vacuously equal to a value nothing writes.
    try span("none", 2) { p.fx("a", 10, 10).gridCellColumns(2) }
    try anchor("none", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading) }
    try column("none", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing) }
    try unsized("none", .horizontal) { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal) }
    try rowToken("none", true) { GridRow { p.fx("a", 10, 10) } }

    // 1 — padding.
    try span("padding", 2) { p.fx("a", 10, 10).gridCellColumns(2).padding(Edges(all: px(1))) }
    try anchor("padding", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).padding(Edges(all: px(1)))
    }
    try column("padding", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).padding(Edges(all: px(1)))
    }
    try unsized("padding", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).padding(Edges(all: px(1)))
    }
    try rowToken("padding", true) { GridRow { p.fx("a", 10, 10) }.padding(Edges(all: px(1))) }

    // 2 — a fixed frame.
    try span("frame(12x12)", 2) {
        p.fx("a", 10, 10).gridCellColumns(2).frame(width: px(12), height: px(12))
    }
    try anchor("frame(12x12)", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).frame(width: px(12), height: px(12))
    }
    try column("frame(12x12)", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).frame(width: px(12), height: px(12))
    }
    try unsized("frame(12x12)", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).frame(width: px(12), height: px(12))
    }
    try rowToken("frame(12x12)", true) {
        GridRow { p.fx("a", 10, 10) }.frame(width: px(12), height: px(12))
    }

    // 3 — a flexible frame.
    try span("frame(maxWidth:)", 2) {
        p.fx("a", 10, 10).gridCellColumns(2).frame(maxWidth: px(.infinity))
    }
    try anchor("frame(maxWidth:)", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).frame(maxWidth: px(.infinity))
    }
    try column("frame(maxWidth:)", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).frame(maxWidth: px(.infinity))
    }
    try unsized("frame(maxWidth:)", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).frame(maxWidth: px(.infinity))
    }
    try rowToken("frame(maxWidth:)", true) {
        GridRow { p.fx("a", 10, 10) }.frame(maxWidth: px(.infinity))
    }

    // 4 — fixedSize.
    try span("fixedSize", 2) { p.fx("a", 10, 10).gridCellColumns(2).fixedSize() }
    try anchor("fixedSize", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).fixedSize() }
    try column("fixedSize", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).fixedSize() }
    try unsized("fixedSize", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).fixedSize()
    }
    try rowToken("fixedSize", true) { GridRow { p.fx("a", 10, 10) }.fixedSize() }

    // 5 — aspectRatio.
    try span("aspectRatio", 2) { p.fx("a", 10, 10).gridCellColumns(2).aspectRatio(1) }
    try anchor("aspectRatio", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).aspectRatio(1) }
    try column("aspectRatio", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).aspectRatio(1) }
    try unsized("aspectRatio", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).aspectRatio(1)
    }
    try rowToken("aspectRatio", true) { GridRow { p.fx("a", 10, 10) }.aspectRatio(1) }

    // 6 — layoutPriority.
    try span("layoutPriority", 2) { p.fx("a", 10, 10).gridCellColumns(2).layoutPriority(1) }
    try anchor("layoutPriority", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).layoutPriority(1)
    }
    try column("layoutPriority", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).layoutPriority(1)
    }
    try unsized("layoutPriority", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).layoutPriority(1)
    }
    try rowToken("layoutPriority", true) { GridRow { p.fx("a", 10, 10) }.layoutPriority(1) }

    // 7 — background(ColorToken), a paint-only wrapper with no node of its own.
    try span("background(token)", 2) { p.fx("a", 10, 10).gridCellColumns(2).background(.accent) }
    try anchor("background(token)", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).background(.accent)
    }
    try column("background(token)", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).background(.accent)
    }
    try unsized("background(token)", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).background(.accent)
    }
    try rowToken("background(token)", true) { GridRow { p.fx("a", 10, 10) }.background(.accent) }

    // 8 — clip.
    try span("clip", 2) { p.fx("a", 10, 10).gridCellColumns(2).clip() }
    try anchor("clip", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).clip() }
    try column("clip", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).clip() }
    try unsized("clip", .horizontal) { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).clip() }
    try rowToken("clip", true) { GridRow { p.fx("a", 10, 10) }.clip() }

    // 9 — border.
    try span("border", 2) { p.fx("a", 10, 10).gridCellColumns(2).border(.accent, width: px(1)) }
    try anchor("border", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).border(.accent, width: px(1))
    }
    try column("border", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).border(.accent, width: px(1))
    }
    try unsized("border", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).border(.accent, width: px(1))
    }
    try rowToken("border", true) { GridRow { p.fx("a", 10, 10) }.border(.accent, width: px(1)) }

    // 10 — opacity.
    try span("opacity", 2) { p.fx("a", 10, 10).gridCellColumns(2).opacity(0.5) }
    try anchor("opacity", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).opacity(0.5) }
    try column("opacity", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).opacity(0.5) }
    try unsized("opacity", .horizontal) { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).opacity(0.5) }
    try rowToken("opacity", true) { GridRow { p.fx("a", 10, 10) }.opacity(0.5) }

    // 11 — allowsHitTesting.
    try span("allowsHitTesting", 2) { p.fx("a", 10, 10).gridCellColumns(2).allowsHitTesting(false) }
    try anchor("allowsHitTesting", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).allowsHitTesting(false)
    }
    try column("allowsHitTesting", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).allowsHitTesting(false)
    }
    try unsized("allowsHitTesting", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).allowsHitTesting(false)
    }
    try rowToken("allowsHitTesting", true) { GridRow { p.fx("a", 10, 10) }.allowsHitTesting(false) }

    // 12 — onTap.
    try span("onTap", 2) { p.fx("a", 10, 10).gridCellColumns(2).onTap {} }
    try anchor("onTap", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).onTap {} }
    try column("onTap", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).onTap {} }
    try unsized("onTap", .horizontal) { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).onTap {} }
    try rowToken("onTap", true) { GridRow { p.fx("a", 10, 10) }.onTap {} }

    // 13 — disabled, an `EnvironmentScope` (no node, no index).
    try span("disabled", 2) { p.fx("a", 10, 10).gridCellColumns(2).disabled(true) }
    try anchor("disabled", .topLeading) { p.fx("a", 10, 10).gridCellAnchor(.topLeading).disabled(true) }
    try column("disabled", .trailing) { p.fx("a", 10, 10).gridColumnAlignment(.trailing).disabled(true) }
    try unsized("disabled", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).disabled(true)
    }
    try rowToken("disabled", true) { GridRow { p.fx("a", 10, 10) }.disabled(true) }

    // 14 — an overlay attachment's PRIMARY side.
    try span("overlay primary", 2) {
        p.fx("a", 10, 10).gridCellColumns(2).overlay { Rectangle(width: px(1), height: px(1)) }
    }
    try anchor("overlay primary", .topLeading) {
        p.fx("a", 10, 10).gridCellAnchor(.topLeading).overlay { Rectangle(width: px(1), height: px(1)) }
    }
    try column("overlay primary", .trailing) {
        p.fx("a", 10, 10).gridColumnAlignment(.trailing).overlay { Rectangle(width: px(1), height: px(1)) }
    }
    try unsized("overlay primary", .horizontal) {
        p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal).overlay { Rectangle(width: px(1), height: px(1)) }
    }
    try rowToken("overlay primary", true) {
        GridRow { p.fx("a", 10, 10) }.overlay { Rectangle(width: px(1), height: px(1)) }
    }

    // 15 — an overlay attachment's CONTENT side: not carried.
    try span("overlay content", 1) {
        Rectangle(width: px(1), height: px(1)).overlay { p.fx("a", 10, 10).gridCellColumns(2) }
    }
    try anchor("overlay content", nil) {
        Rectangle(width: px(1), height: px(1)).overlay { p.fx("a", 10, 10).gridCellAnchor(.topLeading) }
    }
    try column("overlay content", nil) {
        Rectangle(width: px(1), height: px(1))
            .overlay { p.fx("a", 10, 10).gridColumnAlignment(.trailing) }
    }
    try unsized("overlay content", []) {
        Rectangle(width: px(1), height: px(1))
            .overlay { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal) }
    }
    try rowToken("overlay content", false) {
        Rectangle(width: px(1), height: px(1)).overlay { GridRow { p.fx("a", 10, 10) } }
    }

    // 16 — a `.background { }` content side: not carried.
    try span("background content", 1) {
        Rectangle(width: px(1), height: px(1)).background { p.fx("a", 10, 10).gridCellColumns(2) }
    }
    try anchor("background content", nil) {
        Rectangle(width: px(1), height: px(1))
            .background { p.fx("a", 10, 10).gridCellAnchor(.topLeading) }
    }
    try column("background content", nil) {
        Rectangle(width: px(1), height: px(1))
            .background { p.fx("a", 10, 10).gridColumnAlignment(.trailing) }
    }
    try unsized("background content", []) {
        Rectangle(width: px(1), height: px(1))
            .background { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal) }
    }
    try rowToken("background content", false) {
        Rectangle(width: px(1), height: px(1)).background { GridRow { p.fx("a", 10, 10) } }
    }

    // 17 — a one-child `HStack`: not carried.
    try span("HStack{one}", 1) { HStack { p.fx("a", 10, 10).gridCellColumns(2) } }
    try anchor("HStack{one}", nil) { HStack { p.fx("a", 10, 10).gridCellAnchor(.topLeading) } }
    try column("HStack{one}", nil) { HStack { p.fx("a", 10, 10).gridColumnAlignment(.trailing) } }
    try unsized("HStack{one}", []) { HStack { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal) } }
    try rowToken("HStack{one}", false) { HStack { GridRow { p.fx("a", 10, 10) } } }

    // 18 — a one-child `ZStack`: not carried.
    try span("ZStack{one}", 1) { ZStack { p.fx("a", 10, 10).gridCellColumns(2) } }
    try anchor("ZStack{one}", nil) { ZStack { p.fx("a", 10, 10).gridCellAnchor(.topLeading) } }
    try column("ZStack{one}", nil) { ZStack { p.fx("a", 10, 10).gridColumnAlignment(.trailing) } }
    try unsized("ZStack{one}", []) { ZStack { p.fx("a", 10, 10).gridCellUnsizedAxes(.horizontal) } }
    try rowToken("ZStack{one}", false) { ZStack { GridRow { p.fx("a", 10, 10) } } }
}

// MARK: - 4.3 a GridRow outside a Grid

/// **A `GridRow` outside a `Grid` is just its cells** (GG1, GG2): it contributes
/// their nodes to the enclosing container and its row mark is inert there.
///
/// Mutation: `GridRow` registers an `HStack` of its cells (GG1's a and b then
/// sit side by side, 58×20, instead of stacking).
@MainActor
@Test func aGridRowOutsideAGridIsItsCells() throws {
    do { // GG1, in a VStack
        let p = CellProbe()
        let frame = laidOut(50, 58) {
            VStack { GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) } }.fixedSize()
        }
        #expect(try rootSize(frame) == size(30, 38), "GG1 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 0, 30, 10), "GG1 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(5, 18, 20, 20), "GG1 b: \(String(describing: rects["b"]))")
    }
    do { // GG2, in an HStack
        let p = CellProbe()
        let frame = laidOut(78, 40) {
            HStack { GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) } }.fixedSize()
        }
        #expect(try rootSize(frame) == size(58, 20), "GG2 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GG2 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(38, 0, 20, 20), "GG2 b: \(String(describing: rects["b"]))")
    }
}

// MARK: - 4.4 a nested GridRow flattens

/// **A `GridRow` inside a `GridRow` flattens into one row, with the OUTERMOST
/// alignment** (GG3, GG10, GG11, GG12; ruling GR-T).
///
/// GG10 and GG11 are each other's reverse and GG12 is the unaligned control, so
/// "the outermost wins" cannot be read as "either one".
///
/// Mutation: the inner `GridRow` marks AFTER the outer one (GG11's a at y 0 and
/// GG10's at y 20 — the two swap).
@MainActor
@Test func aGridRowInsideAGridRowFlattensWithTheOutermostAlignment() throws {
    do { // GG3
        let p = CellProbe()
        let frame = laidOut(91, 40) {
            Grid {
                GridRow { GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }; p.fx("c", 5, 5) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(71, 20), "GG3 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GG3 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(38, 0, 20, 20), "GG3 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(66, 7.5, 5, 5), "GG3 c: \(String(describing: rects["c"]))")
    }
    // GG10, GG11 and GG12: outer alignment, inner alignment, a's y.
    for (label, outer, inner, y) in [("GG10", VerticalAlignment.top, VerticalAlignment.bottom, 0.0),
                                     ("GG11", .bottom, .top, 20.0),
                                     ("GG12", nil, .bottom, 10.0)] as
        [(String, VerticalAlignment?, VerticalAlignment?, Double)] {
        let p = CellProbe()
        let frame = laidOut(66, 50) {
            Grid {
                GridRow(alignment: outer) {
                    GridRow(alignment: inner) { p.fx("a", 10, 10); p.fx("b", 10, 30) }
                    p.fx("c", 10, 20)
                }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(46, 30), "\(label) size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, y, 10, 10), "\(label) a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(18, 0, 10, 30), "\(label) b: \(String(describing: rects["b"]))")
    }
}

// MARK: - 4.5 a cell modifier on a GridRow

/// **A cell modifier on a `GridRow` applies to every cell and loses to a cell's
/// own** (GG5, GG6, GG13, GG14, GG15, GG16; rulings GR-J, GR-T).
///
/// Mutations: (a) `GridCellModifier` marks only the first node its content
/// returns (GG6's d spans one column and the grid reads 108 wide); (b) it marks
/// BEFORE its content registers (GG13's c takes the row's `.bottomTrailing` and
/// lands at (40, 98) instead of (0, 58)).
@MainActor
@Test func aGridCellModifierOnAGridRowAppliesToEachCellAndLosesToTheCellsOwn() throws {
    do { // GG5, an anchor on the row
        let p = CellProbe()
        let frame = laidOut(98, 88) {
            Grid {
                GridRow { p.fx("a", 50, 10); p.fx("b", 20, 50) }
                GridRow { p.fx("c", 10, 10); p.fx("d", 10, 10) }.gridCellAnchor(.topLeading)
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 68), "GG5 size")
        let rects = try cells(frame, p)
        #expect(rects["c"] == r(0, 58, 10, 10), "GG5 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(58, 58, 10, 10), "GG5 d: \(String(describing: rects["d"]))")
    }
    do { // GG6, columns on the row
        let p = CellProbe()
        let frame = laidOut(228, 58) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20); p.fx("e", 5, 5); p.fx("f", 5, 5) }
                GridRow { p.fx("c", 100, 10); p.fx("d", 100, 10) }.gridCellColumns(2)
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(208, 38), "GG6 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(10.5, 5, 30, 10), "GG6 a: \(String(describing: rects["a"]))")
        #expect(rects["c"] == r(0, 28, 100, 10), "GG6 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(108, 28, 100, 10), "GG6 d: \(String(describing: rects["d"]))")
    }
    do { // GG13, a cell's own anchor beats the row's
        let p = CellProbe()
        let frame = laidOut(98, 128) {
            Grid {
                GridRow { p.fx("a", 50, 10); p.fx("b", 20, 50) }
                GridRow { p.fx("c", 10, 10).gridCellAnchor(.topLeading); p.fx("d", 20, 50) }
                    .gridCellAnchor(.bottomTrailing)
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 108), "GG13 size")
        let rects = try cells(frame, p)
        #expect(rects["c"] == r(0, 58, 10, 10), "GG13 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(58, 58, 20, 50), "GG13 d: \(String(describing: rects["d"]))")
    }
    do { // GG14, a cell's own column alignment beats the row's
        let p = CellProbe()
        let frame = laidOut(70, 48) {
            Grid {
                GridRow { p.fx("a", 10, 10).gridColumnAlignment(.leading) }
                    .gridColumnAlignment(.trailing)
                GridRow { p.fx("e", 50, 10) }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(50, 28), "GG14 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 0, 10, 10), "GG14 a: \(String(describing: rects["a"]))")
        #expect(rects["e"] == r(0, 18, 50, 10), "GG14 e: \(String(describing: rects["e"]))")
    }
    do { // GG15, columns ADD: 2 on the cell and 2 on the row span 4
        let p = CellProbe()
        let frame = laidOut(133, 58) {
            Grid {
                GridRow {
                    p.fx("a", 30, 10); p.fx("b", 20, 20)
                    p.fx("e", 5, 5); p.fx("f", 5, 5); p.fx("g", 5, 5)
                }
                GridRow { p.fx("c", 100, 10).gridCellColumns(2); p.fx("d", 1, 1) }
                    .gridCellColumns(2)
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(113, 38), "GG15 size")
        let rects = try cells(frame, p)
        #expect(rects["c"] == r(0, 28, 100, 10), "GG15 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(110, 32.5, 1, 1), "GG15 d: \(String(describing: rects["d"]))")
    }
    do { // GG16, unsized axes UNION at 200×200
        let p = CellProbe()
        let frame = laidOut(200, 200) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                GridRow { p.fl("c").gridCellUnsizedAxes(.vertical); p.fx("d", 40, 10) }
                    .gridCellUnsizedAxes(.horizontal)
            }
        }
        #expect(try rootSize(frame) == size(78, 38), "GG16 size")
        let rects = try cells(frame, p)
        #expect(rects["c"] == r(0, 28, 30, 10), "GG16 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 28, 40, 10), "GG16 d: \(String(describing: rects["d"]))")
    }
}

// MARK: - 4.6 rows through `if` and `for`, and a container holding a row

/// **Rows reach the grid through `if` and `for`, and a container holding a row
/// is a non-row child** (GG8, GG9).
///
/// Mutation: every `GridRow` is given the same row token (GG8's two rows merge
/// into one and the grid reads 143×20).
@MainActor
@Test func rowsReachTheGridThroughIfAndForEachAndAContainerHoldingARowIsNotARow() throws {
    do { // GG8
        let p = CellProbe()
        let frame = laidOut(98, 78) {
            Grid {
                if true { GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) } }
                for _ in 0..<1 { GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) } }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(78, 58), "GG8 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GG8 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(48, 0, 20, 20), "GG8 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(10, 28, 10, 30), "GG8 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(38, 38, 40, 10), "GG8 d: \(String(describing: rects["d"]))")
    }
    do { // GG9
        let p = CellProbe()
        let frame = laidOut(78, 78) {
            Grid {
                GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
                HStack { GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) } }
            }.fixedSize()
        }
        #expect(try rootSize(frame) == size(58, 58), "GG9 size")
        let rects = try cells(frame, p)
        #expect(rects["a"] == r(0, 5, 30, 10), "GG9 a: \(String(describing: rects["a"]))")
        #expect(rects["b"] == r(38, 0, 20, 20), "GG9 b: \(String(describing: rects["b"]))")
        #expect(rects["c"] == r(0, 28, 10, 30), "GG9 c: \(String(describing: rects["c"]))")
        #expect(rects["d"] == r(18, 38, 40, 10), "GG9 d: \(String(describing: rects["d"]))")
    }
}

// MARK: - 4.7 an empty GridRow

/// **An empty `GridRow` is no row at all** (GA7): three declared rows, two laid
/// out, one 8pt gap between them.
///
/// Mutation: a `GridRow` with no cells registers an empty `ZStack` as its cell
/// (the middle row is real, so the answer gains its height and a second gap).
@MainActor
@Test func anEmptyGridRowIsNoRow() throws {
    let p = CellProbe()
    let frame = laidOut(50, 68) {
        Grid {
            GridRow { p.fx("a", 30, 10) }
            GridRow { }
            GridRow { p.fx("c", 10, 30) }
        }.fixedSize()
    }
    #expect(try rootSize(frame) == size(30, 48), "GA7 size")
    let rects = try cells(frame, p)
    #expect(rects["a"] == r(0, 0, 30, 10), "GA7 a: \(String(describing: rects["a"]))")
    #expect(rects["c"] == r(10, 18, 10, 30), "GA7 c: \(String(describing: rects["c"]))")
}

// MARK: - 4.8 a row's identity level

/// **A `GridRow` takes one cursor index and numbers its cells from 0 under its
/// own id** (ruling GR-J): cell (r, c) is `child(child(grid, r), c)`.
///
/// Mutation: `GridRow` forwards `parent` and `cursor` to its content (every cell
/// numbers flat under the grid, so row 1's first cell is `child(grid, 2)`).
@MainActor
@Test func aGridRowTakesOneIndexAndNumbersItsCellsFromZeroUnderItsOwnID() throws {
    let p = CellProbe()
    _ = laidOut(200, 200) {
        Grid {
            GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
            GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
        }
    }
    func cellID(_ row: Int, _ column: Int) -> GlobalElementID {
        GlobalElementID.child(of: GlobalElementID.child(of: rootID, at: row, name: nil),
                              at: column, name: nil)
    }
    #expect(p.ids["a"] == cellID(0, 0), "a: \(String(describing: p.ids["a"]))")
    #expect(p.ids["b"] == cellID(0, 1), "b: \(String(describing: p.ids["b"]))")
    #expect(p.ids["c"] == cellID(1, 0), "c: \(String(describing: p.ids["c"]))")
    #expect(p.ids["d"] == cellID(1, 1), "d: \(String(describing: p.ids["d"]))")
    // The four are distinct, so an implementation that collides two of them
    // cannot pass by accident.
    try #require(Set([p.ids["a"], p.ids["b"], p.ids["c"], p.ids["d"]]).count == 4)
}

// MARK: - 4.9, 4.9b, 4.9c identity when a cell or a row vanishes

/// What each named cell read out of its `@State` slot this frame.
@MainActor
private final class GridStateProbe {
    var reads: [String: Int] = [:]
}

/// A 10×10 cell holding a `@State` counter. `bump` is the stand-in for a click:
/// it increments the counter during layout, so a frame with one bumping cell
/// leaves exactly one slot holding 1.
private struct GridStatefulCell: ProposalElement {
    @State private var count: Int = 0
    let name: String
    let probe: GridStateProbe
    let bump: Bool

    init(_ name: String, _ probe: GridStateProbe, bump: Bool = false) {
        self.name = name
        self.probe = probe
        self.bump = bump
    }

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        if bump { count += 1 }
        probe.reads[name] = count
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) },
                ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// Renders `make` twice against ONE `StateTable`, so `@State` written in the
/// first frame is there to be read in the second.
@MainActor
private func twoFrames<Root: Element>(_ make: (Int) -> Root) {
    let table = StateTable()
    for pass in 0..<2 {
        var root = make(pass)
        Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
              stateTable: table).render(&root)
    }
}

/// **Removing a cell from one row leaves another row's state alone** (ruling
/// GR-J's "why a row has identity").
///
/// Row 1's first cell counts to 1 in frame 0; frame 1 removes row 0's second
/// cell. With a row of its own identity level row 1's ids do not move, so its
/// counter still reads 1.
///
/// Mutation: `GridRow` forwards `parent` and `cursor` (row 1's cells renumber
/// from 2 to 1 and the counter reads 0).
@MainActor
@Test func removingACellFromOneRowKeepsAnotherRowsState() {
    let probe = GridStateProbe()
    twoFrames { pass in
        Grid {
            GridRow {
                GridStatefulCell("a", probe)
                if pass == 0 { GridStatefulCell("b", probe) }
            }
            GridRow {
                GridStatefulCell("c", probe, bump: pass == 0)
                GridStatefulCell("d", probe)
            }
        }
    }
    #expect(probe.reads["c"] == 1, "row 1's own counter: \(String(describing: probe.reads["c"]))")
    #expect(probe.reads["d"] == 0, "row 1's second cell: \(String(describing: probe.reads["d"]))")
}

/// **A vanishing `if` inside a row hands the removed cell's state to the next
/// cell** — pinned WRONG ON PURPOSE (divergence `GR-O` 9, ruling `GR-AF`).
///
/// The framework's trailing-sibling rule is universal, and `OptionalGroup`
/// returns no node without advancing the cursor, so removing row 0's FIRST cell
/// shifts the rest of the row: the cell that was second reads the first's slot
/// (0) and the cell that was third reads the second's (1, the count it did not
/// make). SwiftUI's remedy is `.id()` on the trailing sibling, and no built-in
/// proposal element has one (task 8, `GR-N`), so it cannot be spelled here.
///
/// The change that would fix it: make `OptionalGroup` consume its index when its
/// wrapped value is nil. Then b reads 1 and c reads 0.
@MainActor
@Test func removingACellFromARowHandsItsStateToTheNextCell() {
    let probe = GridStateProbe()
    twoFrames { pass in
        Grid {
            GridRow {
                if pass == 0 { GridStatefulCell("a", probe) }
                GridStatefulCell("b", probe, bump: pass == 0)
                GridStatefulCell("c", probe)
            }
        }
    }
    #expect(probe.reads["b"] == 0, "b took a's slot: \(String(describing: probe.reads["b"]))")
    #expect(probe.reads["c"] == 1, "c adopted b's count: \(String(describing: probe.reads["c"]))")
}

/// **A vanishing whole `GridRow` hands its row's state to the next row** — the
/// same divergence one level up (`GR-AF`, `GR-O` 9), pinned wrong on purpose.
///
/// The change that would fix it is the same one.
@MainActor
@Test func removingAWholeGridRowHandsItsStateToTheNextRow() {
    let probe = GridStateProbe()
    twoFrames { pass in
        Grid {
            if pass == 0 { GridRow { GridStatefulCell("p", probe) } }
            GridRow { GridStatefulCell("q", probe, bump: pass == 0) }
            GridRow { GridStatefulCell("r", probe) }
        }
    }
    #expect(probe.reads["q"] == 0, "q took p's row: \(String(describing: probe.reads["q"]))")
    #expect(probe.reads["r"] == 1, "r adopted q's count: \(String(describing: probe.reads["r"]))")
}

// MARK: - 4.10 a cell modifier is layout- and identity-transparent

/// **`GridCellModifier` contributes no node and consumes no cursor index**
/// (ruling GR-J): a cell's id and the grid's node count are the same with and
/// without it, and a `@State` inside the modified cell survives the attribute's
/// VALUE changing between frames.
///
/// Mutation: `GridCellModifier` consumes a cursor index (b's id moves to
/// `child(row, 2)` and the counter resets).
@MainActor
@Test func aGridCellModifierIsLayoutAndIdentityTransparent() throws {
    let plain = CellProbe()
    let plainFrame = laidOut(200, 200) {
        Grid { GridRow { plain.fx("a", 10, 10); plain.fx("b", 10, 10) } }
    }
    let modified = CellProbe()
    let modifiedFrame = laidOut(200, 200) {
        Grid { GridRow { modified.fx("a", 10, 10); modified.fx("b", 10, 10).gridCellAnchor(.top) } }
    }
    let expected = GlobalElementID.child(of: GlobalElementID.child(of: rootID, at: 0, name: nil),
                                         at: 1, name: nil)
    try #require(plain.ids["b"] == expected, "the control's b: \(String(describing: plain.ids["b"]))")
    #expect(modified.ids["b"] == expected, "the modified b: \(String(describing: modified.ids["b"]))")
    #expect(modifiedFrame.tree.nodeCount == plainFrame.tree.nodeCount,
            "node counts \(modifiedFrame.tree.nodeCount) vs \(plainFrame.tree.nodeCount)")

    // The attribute's VALUE changes between the two frames; the state below it
    // does not reset.
    let probe = GridStateProbe()
    twoFrames { pass in
        Grid {
            GridRow {
                GridStatefulCell("a", probe)
                GridStatefulCell("b", probe, bump: pass == 0)
                    .gridCellAnchor(pass == 0 ? .top : .bottom)
            }
        }
    }
    #expect(probe.reads["b"] == 1, "b across a changing anchor: \(String(describing: probe.reads["b"]))")
}

// MARK: - 4.10b the two untyped group entries

/// **`GridRow`'s and `GridCellModifier`'s UNTYPED `requestGroupLayout` entries
/// forward every node their typed entries registered.**
///
/// Both are one-line shims over the typed entry (`nodes.map(\.layoutNodeID)`),
/// so there is no drift for a copy-comparison to catch (`MC-H`) — but
/// `ProposalElementGroup` refines `ElementGroup`, so a legacy builder group
/// reaches them, and a shim that returned `[]` would silently drop the row's
/// cells with nothing else moving. Lane 4's verifier measured exactly that: both
/// entries changed to `return ([], layout)` left the whole suite green.
///
/// Each arm calls the untyped entry directly, requires the node COUNT first (so
/// a dropping shim fails here rather than trapping later in `requestNativeGrid`)
/// and then reads the marks those ids carry through a grid built from them.
///
/// Mutations: `GridRow.requestGroupLayout` returns `([], layout)` (arm 1's
/// `#require`); `GridCellModifier.requestGroupLayout` the same (arm 2's).
@MainActor
@Test func theUntypedGroupEntriesOfARowAndACellModifierForwardEveryCellNode() throws {
    func plan<G: ProposalElementGroup>(_ make: () -> G) throws -> NativeGridPlan {
        var group = make()
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
        var pass = LayoutPass(frame: frame)
        var cursor = 0
        let (nodes, _) = group.requestGroupLayout(under: rootID, at: &cursor, pass: &pass)
        try #require(nodes.count == 2, "the untyped entry returned \(nodes.count) nodes, not 2")
        let grid = pass.requestNativeGrid(children: nodes.map { ProposalNodeID($0) })
        return try #require(frame.tree.nativeGridPlan(grid.layoutNodeID),
                            "the registered node is not a grid")
    }
    let p = CellProbe()

    // 1 — GridRow's untyped entry: both cells arrive, and both carry its row
    // token, which is what says the ids are the ones it marked.
    let row = try plan { GridRow { p.fx("a", 10, 10); p.fx("b", 10, 10) } }
    #expect(row.cells.map(\.isRowCell) == [true, true],
            "row tokens through the untyped entry: \(row.cells.map(\.isRowCell))")

    // 2 — GridCellModifier's untyped entry over that row: both cells arrive with
    // the attribute it wrote over each of them.
    let modified = try plan {
        GridRow { p.fx("a", 10, 10); p.fx("b", 10, 10) }.gridCellColumns(2)
    }
    #expect(modified.cells.map(\.span) == [2, 2],
            "spans through the untyped entry: \(modified.cells.map(\.span))")
}

// MARK: - 4.11 a form of text cells

/// **A form's value column is offered the remainder of the grid's width**
/// (`GR-V`, GN2's structure), measured with MetalUI's own text.
///
/// Everything is read through `measureNativeLayout`, so no placement, centring
/// or rounding enters: the label column is the wider label's own nil width, the
/// value column is the long value's answer at what is left after the label
/// column and the 8pt gap, and the grid's answer is their sum.
///
/// Mutation: GZ0's control — every group is offered `W′ / ncols`, so the long
/// value is offered 96 instead of the remainder and the grid's answer moves.
@MainActor
@Test func aFormOfTextCellsOffersTheValueColumnTheRemainder() throws {
    let name = ProposalText("Name")
    let address = ProposalText("Address")
    let value = ProposalText("Ada Lovelace")
    let long = ProposalText("110 Burlington Street, Marylebone, London, England")

    let labelColumn = max(measureAlone(name, nil, nil).width, measureAlone(address, nil, nil).width)
    try #require(measureAlone(address, nil, nil).width == labelColumn,
                 "the longer label must be the wider one, or the column is not what it says")
    let offered = 200 - labelColumn - 8
    let longAnswer = measureAlone(long, offered, nil)
    let valueAnswer = measureAlone(value, offered, nil)
    let valueColumn = max(valueAnswer.width, longAnswer.width)
    try #require(longAnswer.height > measureAlone(long, nil, nil).height,
                 "the long value must wrap at \(offered), or the arm measures nothing")

    let form = Grid {
        GridRow { ProposalText("Name"); ProposalText("Ada Lovelace") }
        GridRow {
            ProposalText("Address")
            ProposalText("110 Burlington Street, Marylebone, London, England")
        }
    }
    let answer = measureAlone(form, 200, nil)
    #expect(answer.width == labelColumn + 8 + valueColumn,
            "the form's width \(answer.width) vs \(labelColumn) + 8 + \(valueColumn)")
    let row0 = max(measureAlone(name, nil, nil).height, valueAnswer.height)
    #expect(answer.height == row0 + 8 + longAnswer.height,
            "the form's height \(answer.height) vs \(row0) + 8 + \(longAnswer.height)")
}

// MARK: - 4.12 text rows take the default row spacing

/// **Two rows of text take the 8pt default gap** — pinned WRONG ON PURPOSE
/// (divergence `GR-O` 5; SwiftUI's GS7, GN2 and GN7 all read **0** between two
/// `Text` rows, its font-derived text spacing, which MetalUI does not adopt —
/// `CN-H`'s stacks make the same choice).
///
/// The owner is plan task 11 (text edges, `GR-N`).
///
/// Mutation: a gap of 0 between two rows whose cells are all leaves (the grid's
/// height loses the 8).
@MainActor
@Test func textRowsTakeTheDefaultRowSpacing() throws {
    let grid = Grid {
        GridRow { ProposalText("A"); ProposalText("B") }
        GridRow { ProposalText("C"); ProposalText("D") }
    }
    let answer = measureAlone(grid, nil, nil)
    let line = measureAlone(ProposalText("A"), nil, nil).height
    try #require(line > 0, "a line of text must have a height")
    #expect(answer.height == line + 8 + line,
            "two text rows: \(answer.height) vs \(line) + 8 + \(line) (SwiftUI reads \(line + line))")
}

// MARK: - 4.17 a grid root is centred at its answer

/// **A native grid root is centred at its answer** (`CN-J`), with no grid code
/// of its own: GA1's grid in a 200×200 window is 78×58 at (61, 71) and its cell
/// a is at (61, 76).
///
/// Green on arrival. Mutation: `placeGrid` places cells from (0, 0) instead of
/// the bounds origin (a reads (0, 5)).
@MainActor
@Test func aGridRootIsCentredAtItsAnswer() throws {
    let p = CellProbe()
    let frame = laidOut(200, 200) {
        Grid {
            GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
            GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
        }
    }
    let root = try #require(frame.elementBounds[rootID])
    #expect(root.origin.x.value == 61 && root.origin.y.value == 71,
            "the grid's origin: \(root.origin)")
    #expect(root.size.width.value == 78 && root.size.height.value == 58,
            "the grid's size: \(root.size)")
    let a = try #require(p.bounds["a"])
    #expect(a.origin.x.value == 61 && a.origin.y.value == 76, "a absolute: \(a.origin)")
}

// MARK: - 4.20 the element bounds log

/// **Every cell records its bounds through the group entry, and a `GridRow`
/// records none** (rulings GR-K, `LR-AA` item 3): a row has no node and no
/// bounds, and it hands off by calling its content's `prepaintGroup`, so each
/// cell records through `Element.prepaintGroup` exactly as a stack child does.
///
/// Green on arrival. Mutation: `GridRow.prepaintGroup` re-implements the hand-off
/// without `recordElementBounds` — the `AnyElement` miss (the cells' entries
/// vanish).
@MainActor
@Test func gridCellsRecordTheirBoundsThroughTheElementGroupEntry() throws {
    let p = CellProbe()
    let frame = laidOut(200, 200) {
        Grid {
            GridRow { p.fx("a", 30, 10); p.fx("b", 20, 20) }
            GridRow { p.fx("c", 10, 30); p.fx("d", 40, 10) }
        }
    }
    // The grid itself, at its bounds.
    let grid = try #require(frame.elementBounds[rootID], "the grid recorded no bounds")
    #expect(grid.size.width.value == 78 && grid.size.height.value == 58, "the grid: \(grid.size)")
    // Every cell, at the rect its own prepaint saw.
    for name in ["a", "b", "c", "d"] {
        let id = try #require(p.ids[name], "\(name) never prepainted")
        let logged = try #require(frame.elementBounds[id], "\(name) recorded no bounds")
        let seen = try #require(p.bounds[name])
        #expect(logged.origin.x.value == seen.origin.x.value
                && logged.origin.y.value == seen.origin.y.value
                && logged.size.width.value == seen.size.width.value
                && logged.size.height.value == seen.size.height.value,
                "\(name) logged \(logged) but prepainted \(seen)")
    }
    // Nothing under either row's own id.
    for row in 0..<2 {
        let rowID = GlobalElementID.child(of: rootID, at: row, name: nil)
        #expect(frame.elementBounds[rowID] == nil,
                "row \(row) recorded bounds: \(String(describing: frame.elementBounds[rowID]))")
    }
}
