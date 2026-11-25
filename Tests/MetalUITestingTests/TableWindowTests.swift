@testable import MetalUI
import Testing

// The table's window engine (`TBL-H`, `TBL-G`, `TBL-I`, `TBL-E`; record 388): `UniformWindow`, `ColumnExtentIndex`,
// `TableWidthSolver` and `TableWindowPlanner`. Pure arithmetic, no window; each test names the mutation that reddens it.

// MARK: - UniformWindow (A1)

/// **A1** `UniformWindow.lines` is `List.window`'s arithmetic, pinned by four literals (the rows are `List`'s own, the third is
/// the table's steady window). Mutation: delete `max(0, total − viewport)` from the top's clamp; the last row fails (a raw 1e9
/// offset windows past the data).
@Test func uniformWindowPinsTheListArithmetic() {
    let cases: [(count: Int, extent: Double, offset: Double, viewport: Double, origin: Double, overscan: Int, expected: Range<Int>)] = [
        (40, 28, 300, 112, 300, 2, 0..<6),
        (40, 28, 240, 300, 0, 2, 6..<22),
        (1_000_000, 24, 12000, 572, 0, 2, 498..<526),
        (10, 24, 1e9, 572, 0, 2, 0..<10)
    ]
    for c in cases {
        let got = UniformWindow.lines(count: c.count, extent: c.extent, offset: c.offset, viewport: c.viewport,
                                      origin: c.origin, overscan: c.overscan)
        #expect(got == c.expected, "count \(c.count) offset \(c.offset): \(got)")
    }
}

// MARK: - ColumnExtentIndex (A2)

/// **A2.1** Prefix offsets, containment and the first index at or after a position, over widths `[100, 50, 200, 25]`.
/// Mutation: `<=` to `<` in `index(containing:)`; the probe at 100 answers 0.
@Test func aColumnIndexAnswersPrefixOffsetsAndContainment() {
    let index = ColumnExtentIndex(widths: [100, 50, 200, 25])
    #expect(index.count == 4)
    #expect(index.totalWidth == 375)
    #expect([-1, 0, 1, 2, 3, 4, 9].map(index.offset(of:)) == [0, 0, 100, 150, 350, 375, 375])
    #expect([-5, 0, 99.9, 100, 149, 150, 374, 1000].map(index.index(containing:)) == [0, 0, 0, 1, 1, 2, 3, 3])
    #expect([0, 100, 101, 375, 400].map(index.firstIndex(startingAtOrAfter:)) == [0, 1, 2, 4, 4])
    #expect([0, 1, 2, 3].map(index.width(at:)) == [100, 50, 200, 25])
}

/// **A2.2** A column window is the viewport's columns plus one on each side, clamped. Mutation: overscan on the leading side
/// only; offset 600 answers `5..<14`.
@Test func aColumnWindowIsViewportPlusOneEachSide() {
    let index = ColumnExtentIndex(widths: Array(repeating: 100, count: 200))
    #expect(index.window(offset: 600, viewport: 800, overscan: 1) == 5..<15)
    #expect(index.window(offset: 0, viewport: 800, overscan: 1) == 0..<9)
    #expect(index.window(offset: 19200, viewport: 800, overscan: 1) == 191..<200)
    #expect(index.window(offset: 1e9, viewport: 800, overscan: 1) == 191..<200)
    #expect(ColumnExtentIndex(widths: []).window(offset: 0, viewport: 800, overscan: 1) == 0..<0)
}

/// **A2.3** Uniform widths agree with `UniformWindow` at overscan 1, over a grid of offsets and viewports. Mutation: write
/// `firstIndex(startingAtOrAfter:)` as `index(containing:) + 1`; an offset that lands on a column edge (600 + 800) disagrees.
@Test func aUniformColumnIndexAgreesWithTheUniformWindow() {
    let index = ColumnExtentIndex(widths: Array(repeating: 100, count: 200))
    for offset in [0.0, 50, 600, 999, 19200] {
        for viewport in [1.0, 333, 800] {
            let columns = index.window(offset: offset, viewport: viewport, overscan: 1)
            let lines = UniformWindow.lines(count: 200, extent: 100, offset: offset, viewport: viewport, origin: 0, overscan: 1)
            #expect(columns == lines, "offset \(offset) viewport \(viewport): \(columns) vs \(lines)")
        }
    }
}

// MARK: - TableWidthSolver (A3)

private func spec(fixed: Double? = nil, min: Double? = nil, ideal: Double? = nil, max: Double? = nil) -> TableColumnWidthSpec {
    TableColumnWidthSpec(fixed: fixed, min: min, ideal: ideal, max: max)
}

/// **A3.1** Fixed, ideal, default and override, each clamped (probe `swiftui-table.swift` arm `W1`: a column with no width is 100 wide; `W4`: its minimum is 10). Mutation: drop the clamp; the last column becomes 100 (its max
/// is 60).
@Test func widthsResolveFixedIdealDefaultAndOverride() {
    let specs = [spec(fixed: 80), spec(min: 50, ideal: 150, max: 300), spec(), spec(min: 40, max: 60)]
    #expect(TableWidthSolver.resolve(specs, overrides: [90, 220, nil, nil], viewport: 0) == [80, 220, 100, 60])
}

/// **A3.2** A surplus is shared uniformly among the flexible columns and repeats as a column reaches its max. Mutation: one
/// distribution pass only; the answer is `[100, 150, 200]`.
@Test func surplusGrowsFlexibleColumnsUniformlyUpToTheirMax() {
    let specs = [spec(fixed: 100), spec(ideal: 100, max: 150), spec(ideal: 100)]
    #expect(TableWidthSolver.resolve(specs, overrides: [nil, nil, nil], viewport: 500) == [100, 150, 250])
}

/// **A3.3** A sum above the viewport is never shrunk (arm `W3`). Mutation: scale the widths down to the viewport when the sum
/// exceeds it; the three columns become 166.67.
@Test func noSurplusMeansNoShrink() {
    let specs = Array(repeating: spec(ideal: 300), count: 3)
    #expect(TableWidthSolver.resolve(specs, overrides: [nil, nil, nil], viewport: 500) == [300, 300, 300])
}

/// **A3.4** A column the user sized takes no surplus. Mutation: include overridden columns among the flexible ones; the split is
/// `[190, 210]`.
@Test func anOverriddenColumnTakesNoSurplus() {
    let specs = [spec(ideal: 100), spec(ideal: 100)]
    #expect(TableWidthSolver.resolve(specs, overrides: [120, nil], viewport: 400) == [120, 280])
}

// MARK: - TableWindowPlanner (A4)

/// 1 000 000 rows, 24-point rows, a 28-point header and 200 columns of 100: the spec's fixture.
private let planIndex = ColumnExtentIndex(widths: Array(repeating: 100, count: 200))

private func contextOf(y: Double, x: Double, height: Double = 600, width: Double = 800) -> ScrollContext {
    ScrollContext(offset: y, viewportExtent: height, axis: .vertical,
                  cross: ScrollAxisContext(offset: x, viewportExtent: width, followsEnd: false))
}

private func planOf(_ context: ScrollContext?, rows: Int = 1_000_000, columns: ColumnExtentIndex = planIndex,
                    frozen: Int = 0) -> TableWindowPlan {
    TableWindowPlanner.plan(rowCount: rows, rowHeight: 24, headerHeight: 28, columns: columns, frozenCount: frozen,
                            context: context)
}

/// **A4.1** Both axes window from the two contexts. Mutation: pass `viewportHeight` instead of `viewportHeight − header` to the
/// rows' window; the rows become `498..<527` (the header's 28 points are 1.17 rows).
@Test func aBoundedPlanWindowsBothAxesFromTheContext() {
    let plan = planOf(contextOf(y: 12000, x: 600))
    #expect(plan.mode == .bounded)
    #expect(plan.rows == 498..<526)
    #expect(plan.columns == 5..<15)
    #expect(plan.frozen == 0..<0)
    #expect(plan.offsetX == 600 && plan.offsetY == 12000)
    #expect(plan.viewportWidth == 800 && plan.viewportHeight == 600)
}

/// **A4.2** A raw offset past either end is clamped into the content, so the pins never follow an overscroll (`TBL-E`).
/// Mutation: return the raw offsets; the offsets and the windows fail.
@Test func aPlanClampsARawOffsetPastEitherEnd() {
    let before = planOf(contextOf(y: -500, x: -40))
    #expect(before.offsetX == 0 && before.offsetY == 0)
    #expect(before.rows == 0..<26)
    #expect(before.columns == 0..<9)
    let after = planOf(contextOf(y: 1e12, x: 1e9))
    #expect(after.offsetY == 28 + 24_000_000 - 600)
    #expect(after.rows.upperBound == 1_000_000)
    #expect(after.offsetX == 19200)
    #expect(after.columns == 191..<200)
}

/// **A4.3** A viewport of 0, or no context, is cold: 32 rows and 16 columns, never everything and never unbounded (`TBL-H`).
/// Mutation: cold rows `0..<count`.
@Test func aColdPlanTakesThirtyTwoRowsAndSixteenColumns() {
    let cold = planOf(contextOf(y: 0, x: 0, height: 0, width: 0))
    #expect(cold.mode == .cold)
    #expect(cold.rows == 0..<32)
    #expect(cold.columns == 0..<16)
    let small = planOf(contextOf(y: 0, x: 0, height: 0, width: 0), rows: 10, columns: ColumnExtentIndex(widths: [100, 100, 100]))
    #expect(small.rows == 0..<10)
    #expect(small.columns == 0..<3)
    let none = planOf(nil)
    #expect(none.mode == .cold)
    #expect(none.rows == 0..<32)
}

/// **A4.4** The frozen columns are outside the window and always planned; the scrolling columns window over the band after
/// them. Mutation: ignore the frozen width in the band; the columns become `5..<15`.
@Test func frozenColumnsAreOutsideTheWindowAndAlwaysPlanned() {
    let plan = planOf(contextOf(y: 12000, x: 600), frozen: 2)
    #expect(plan.frozen == 0..<2)
    #expect(plan.columns == 7..<15)
    #expect(plan.digest.frozenWidth == 200)
}

/// **A4.5** `contains` ignores a shift inside the built window and catches every other change. Mutation: omit the digest from
/// `contains`; the width change is no longer stale.
@Test func containmentIgnoresAnInnerShiftAndCatchesEveryOther() {
    let built = planOf(contextOf(y: 12000, x: 600))
    var shifted = built
    shifted.rows = 499..<526
    #expect(TableWindowPlanner.contains(built, shifted))
    var wider = built
    wider.columns = 5..<16
    #expect(!TableWindowPlanner.contains(built, wider))
    var widths = built
    widths.digest.totalWidth += 5
    #expect(!TableWindowPlanner.contains(built, widths))
    var moved = built
    moved.offsetY += 1
    #expect(!TableWindowPlanner.contains(built, moved))
    let cold = planOf(nil)
    #expect(!TableWindowPlanner.contains(cold, built))
    #expect(TableWindowPlanner.contains(built, built))
}
