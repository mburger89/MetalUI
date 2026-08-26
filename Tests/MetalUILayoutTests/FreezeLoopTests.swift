import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

/// A flex child with an **explicit** cross size, for the hand-written tests
/// that pin §9.7 arithmetic and want the cross axis held still.
///
/// The 40 is a constant, not a parameter. It used to be `cross: Double = 40`,
/// and after `growMatchesWebKitOnTheUnusedGolden` stopped passing `cross: 100`
/// to fake the stretch the engine could not do, every call site took the
/// default — a customization point nothing customized, which is the same hazard
/// class in test code as a dead production parameter. Use `fixtureFlexChild`
/// when you want stretch instead; add the parameter back only when a second
/// value genuinely exists.
private func flexChild(_ tree: LayoutTree, grow: Float, shrink: Float,
                       basis: MetalUICore.Dimension) -> LayoutNodeID {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
    s.size = Size(width: .auto, height: px(40))
    return tree.newNode(style: s, children: [])
}

/// A child that mirrors a fixture's `.a { flex: <g> <s> <b>; }` **exactly** —
/// no height, because the fixtures declare none.
///
/// **Leave it that way.** Since §9.4 stretch landed, the missing height is what
/// makes these comparisons exercise stretch at all: the engine fills the
/// container's cross extent exactly as WebKit does, which is why every
/// comparison below is full-rect and no golden was regenerated to get there.
/// Giving these children an explicit height would make stretch unreachable from
/// the corpus while the tests went on looking green.
private func fixtureFlexChild(_ tree: LayoutTree, grow: Float, shrink: Float,
                              basis: MetalUICore.Dimension) -> LayoutNodeID {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
    return tree.newNode(style: s, children: [])
}

private func row(_ tree: LayoutTree, width: Double, _ kids: [LayoutNodeID]) -> LayoutNodeID {
    var s = Style()
    s.flexDirection = .row
    s.size = Size(width: px(width), height: px(40))
    return tree.newNode(style: s, children: kids)
}

@Test func growDistributesFreeSpaceInProportionToFlexGrow() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 2, shrink: 1, basis: px(0))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 700, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 700 - 100 = 600 free, split 1:2.
    #expect(tree.layout(a).width == 200)
    #expect(tree.layout(b).width == 400)
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(a).x == 0)
    #expect(tree.layout(b).x == 200)
    #expect(tree.layout(c).x == 600)
}

@Test func shrinkIsWeightedByBaseSize() {
    // §9.7: shrink is scaled by base size, so equal shrink factors do NOT
    // remove equal amounts. a=200 b=200 c=100 in a 300 row: 200 overflow.
    // Scaled factors: a 1*200=200, b 2*200=400, c frozen. Total 600.
    // a loses 200*(200/600)=66.67 -> 133.33; b loses 200*(400/600)=133.33 -> 66.67.
    //
    // **This test cannot detect the weighting being dropped.** a and b have the
    // same base size, so the common 200 cancels: unweighted factors 1 and 2 out
    // of 3 give exactly the same 133.33 / 66.67 as weighted 200 and 400 out of
    // 600. Deleting `* item.baseSize` leaves this test green — verified by
    // mutation, not by reading. It pins the arithmetic against WebKit's answer
    // for `flex_row_shrink` (which is blind for the same reason); the test that
    // actually pins the weighting is
    // `shrinkWeightingDistinguishesItemsWithDifferentBaseSizes` below, which
    // exists precisely because this one is a §1-shape uniform-value test.
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0, shrink: 1, basis: px(200))
    let b = flexChild(tree, grow: 0, shrink: 2, basis: px(200))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 300, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 133)   // 133.33 rounded
    #expect(tree.layout(b).width == 67)    // 66.67 rounded
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 300)
}

/// The weighting, on items whose base sizes actually differ.
///
/// `shrinkIsWeightedByBaseSize` above uses two 200px items, where weighting by
/// base size and not weighting give the *same* answer — the common factor 200
/// cancels out of `200/600` vs `1/3`. It pins the arithmetic but cannot detect
/// the weighting being dropped. This one can: equal shrink factors on a 300px
/// and a 100px item must remove three times as much from the larger.
///
/// 300 + 100 = 400 in a 200 row: 200 overflow. Weighted factors 1*300 and
/// 1*100, total 400. The 300 loses 200*(300/400) = 150 -> 150; the 100 loses
/// 200*(100/400) = 50 -> 50. Unweighted, both lose 100: 200 and 0.
@Test func shrinkWeightingDistinguishesItemsWithDifferentBaseSizes() {
    let tree = LayoutTree()
    let big = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let small = flexChild(tree, grow: 0, shrink: 1, basis: px(100))
    let root = row(tree, width: 200, [big, small])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(big).width == 150)
    #expect(tree.layout(small).width == 50)
    #expect(tree.layout(small).x == 150)
}

@Test func gapIsRemovedFromFreeSpaceBeforeDistribution() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(220), height: px(40))
    rootStyle.gap = Axes(both: .pixels(Pixels(20)))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 220 - 20 gap = 200 free, split evenly.
    #expect(tree.layout(a).width == 100)
    #expect(tree.layout(b).width == 100)
    #expect(tree.layout(b).x == 120)
}

/// §9.7.4.b — flex factors summing to **less than one** distribute only that
/// fraction of the *initial* free space, and the rest stays unfilled.
///
/// Without the clause the loop distributes all 400 and the three items come out
/// 133/133/134, closing the row. `flex_row_fractional_grow` is the browser's
/// word on it; this pins the same arithmetic without WebKit in the loop.
@Test func flexFactorsSummingBelowOneLeaveFreeSpaceUnfilled() {
    let tree = LayoutTree()
    let kids = (0..<3).map { _ in flexChild(tree, grow: 0.25, shrink: 1, basis: px(0)) }
    let root = row(tree, width: 400, kids)

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 0.25 * 3 = 0.75 of 400 = 300 distributed, 100 each. 100px goes unused.
    for kid in kids { #expect(tree.layout(kid).width == 100) }
    #expect(tree.layout(kids[2]).x + tree.layout(kids[2]).width == 300)
}

/// A lone sub-one factor is the case the clause exists for: without it a single
/// `flex-grow: 0.5` item silently swallows *all* the free space, because
/// `factor / factorTotal` is 1 whenever there is only one unfrozen item.
@Test func aLoneSubOneGrowFactorTakesOnlyItsFraction() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0.5, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 200)
}

@MainActor
@Test func growMatchesWebKitOnTheUnusedGolden() throws {
    // flex_row_fixed_and_grow.json has been committed since M1a Task 4 and
    // nothing has ever compared against it. This is what makes it load-bearing.
    //
    // The tree mirrors the fixture exactly: none of `.a`, `.b` or `.c` declares
    // a height, so all three reach 100 only through §9.4 stretch. It used to
    // hand `a` and `b` an explicit `cross: 100` to stand in for the stretch the
    // engine could not do — restoring that would make this comparison green
    // whether stretch worked or not.
    let golden = try loadGolden("flex_row_fixed_and_grow")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = fixtureFlexChild(tree, grow: 2, shrink: 1, basis: px(0))
    var cs = Style()
    cs.size = Size(width: px(100), height: .auto)
    let c = tree.newNode(style: cs, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(700), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

/// `flex_row_grow_uneven`: 640 row, `1 1 0` / `3 1 0` / `0 0 140px`.
/// 500 free after the fixed 140, split 1:3 -> 125 and 375.
@MainActor
@Test func unevenGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_grow_uneven")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = fixtureFlexChild(tree, grow: 3, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: px(140))
    let root = row(tree, width: 640, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

/// `flex_row_shrink`: 300 row holding 200 + 200 + 100. The browser's answer is
/// the base-size-weighted one, which is the whole point of the fixture.
@MainActor
@Test func shrinkMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_shrink")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 1, basis: px(200))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 2, basis: px(200))
    let c = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 300, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

/// `flex_row_fractional_grow`: three `flex: 0.25 1 0` items in a 400 row.
/// WebKit gives 100/100/100 and leaves 100px of the container empty — the
/// browser's confirmation of §9.7.4.b's sub-one clause.
@MainActor
@Test func fractionalGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_fractional_grow")

    let tree = LayoutTree()
    let kids = (0..<3).map { _ in fixtureFlexChild(tree, grow: 0.25, shrink: 1, basis: px(0)) }
    let root = row(tree, width: 400, kids)

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", kids[0]: "a", kids[1]: "b", kids[2]: "c"],
        golden: golden, tolerance: 0.1)
}

/// §9.7.4.b scales the **initial** free space — the one fixed before the loop
/// starts — not the loop's current `remaining`.
///
/// The two readings only diverge when the loop runs more than once *and* the
/// factors sum below one, which needs a min/max violation to force a second
/// pass. `.a` is `flex: 0.25 1 0` capped at 50, `.b` is `flex: 0.25 1 0`, in a
/// 400 row:
///
/// - Pass 1: initial free space 400, raw sum 0.5, so 200 is distributed —
///   100 each. `a` clamps to 50, a max violation, and freezes.
/// - Pass 2: one unfrozen item, raw sum 0.25. Against the **initial** 400 that
///   is 100, so `b` is 100. Against a free space recomputed as 400 - 50 = 350
///   it would be 87.5.
///
/// WebKit says 50 and 100, so `initialFreeSpace` must be computed once, outside
/// the loop. Nothing else in the corpus can tell the two apart.
@Test func subOneClauseScalesTheInitialFreeSpaceNotTheRemaining() {
    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 0.25
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    capped.maxSize = Size(width: px(50), height: .auto)
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 0.25, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 50)
    #expect(tree.layout(b).width == 100)
    #expect(tree.layout(b).x == 50)
}

/// The browser's word on the case above.
@MainActor
@Test func clampedFractionalGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_fractional_grow_clamped")

    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 0.25
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    capped.maxSize = Size(width: px(50), height: .auto)
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 0.25, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b"],
        golden: golden, tolerance: 0.1)
}

/// §9.7.4.b's magnitude test: the sub-one scaling may only ever *reduce* the
/// remaining free space, never enlarge it.
///
/// `a` is `flex: 0.25 1 0` with `min-width: 350`, `b` is `flex: 0.25 1 0`, in a
/// 400 row. Pass 1 hands both 100; `a` floors up to 350, a min violation, and
/// freezes. Pass 2 then has 50 of remaining free space but a scaled value of
/// 100 (the initial 400 x 0.25) — and the spec uses the scaled value only when
/// its magnitude is the *smaller*, so `b` gets 50 and the row closes exactly on
/// 400.
///
/// **This is a case where WebKit is the outlier, and it is settled, not open.**
/// Measured on all three: the spec says 350/50, Blink (headless Chrome, which
/// shares no layout code with WebKit) says 350/50, and WebKit alone says
/// 350/100, overflowing the container to 450 as if the `abs` guard were absent.
/// Two engines and the specification against one is a WebKit bug, so this
/// engine follows the spec and this test asserts 50.
///
/// Nothing committed encodes WebKit's answer — the probe fixture was generated
/// against the oracle and then deliberately **not** committed — so if WebKit
/// ever fixes this, no golden in the corpus moves and no test here changes.
/// That is the point of leaving it uncommitted. **Do not "correct" this test
/// towards WebKit**; see CLAUDE.md, "Two known divergences from the browsers".
///
/// Note how narrow the divergence is: `flex_row_fractional_shrink` exercises
/// the very same `abs` guard with *negative* free space, and WebKit agrees with
/// us there. Only the positive-free-space second pass differs.
@Test func subOneScalingNeverExceedsTheRemainingFreeSpace() {
    let tree = LayoutTree()
    var floored = Style()
    floored.flexGrow = 0.25
    floored.flexShrink = 1
    floored.flexBasis = px(0)
    floored.minSize = Size(width: px(350), height: .auto)
    let a = tree.newNode(style: floored, children: [])
    let b = fixtureFlexChild(tree, grow: 0.25, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 350)
    #expect(tree.layout(b).width == 50)         // WebKit: 100
    // The row closes on the container rather than overflowing it.
    #expect(tree.layout(b).x + tree.layout(b).width == 400)
}

/// §9.7.4.e — space freed by clamping an item is **redistributed** among the
/// items that are still unfrozen. This is the reason §9.7 is a loop at all.
///
/// Three `flex: 1 1 0` items in a 400 row, the first capped at 50. Pass 1 hands
/// each 133.33; `a` clamps down to 50, a max violation, and freezes alone. Pass
/// 2 shares the recovered space between `b` and `c`: 350 / 2 = 175 each, and the
/// row closes exactly on 400.
///
/// Freezing *every* item on a nonzero violation — the plausible simplification
/// of the three-way branch — stops after pass 1 and leaves 50 + 133 + 133, well
/// short of the container. Nothing but a max/min violation can produce a second
/// pass, so without a fixture of this shape the entire loop body is exercised
/// exactly once and the redistribution it exists for is never observed.
@Test func clampingOneItemRedistributesTheFreedSpaceToTheRest() {
    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 1
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    capped.maxSize = Size(width: px(50), height: .auto)
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 50)
    #expect(tree.layout(b).width == 175)
    #expect(tree.layout(c).width == 175)
    #expect(tree.layout(c).x + tree.layout(c).width == 400)
}

/// The browser's word on the redistribution above.
@MainActor
@Test func growWithAMaxWidthMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_grow_with_max")

    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 1
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    capped.maxSize = Size(width: px(50), height: .auto)
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

// MARK: - Fixes for mutations that the first round of fixtures could not catch.
//
// Each pair below exists because a mutation left all 103 tests green. The cause
// was the same every time: the corpus was uniform along the axis the mutation
// moved. Shape 1 in `docs/practices/verifying-tests-can-fail.md`, three more
// times.

/// A growing item's share is added to its **base size**, not to zero.
///
/// Every growing item in the corpus before this test had `flex-basis: 0`, which
/// makes `baseSize + share` and `share` alone numerically identical — so
/// replacing `items[i].baseSize` with `0` in the distribution step passed the
/// entire suite, leaving `flex: 1 1 100px`, the most ordinary flex declaration
/// there is, completely unguarded.
///
/// 400 row, bases 100 and 0, so 300 free split evenly by equal grow factors:
/// `a` is 100 + 150 = 250 and `b` is 0 + 150 = 150. Under the mutation both are
/// 150 and the row stops 100 short of its container.
@Test func growAddsItsShareOnTopOfANonZeroBasis() {
    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(100))
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 250)
    #expect(tree.layout(b).width == 150)
    #expect(tree.layout(b).x + tree.layout(b).width == 400)
}

/// The browser's word on the non-zero basis above.
@MainActor
@Test func growWithANonZeroBasisMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_grow_nonzero_basis")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(100))
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b"],
        golden: golden, tolerance: 0.1)
}

/// The sub-one clause on the **shrink** side — the only place two more details
/// of §9.7.4.b become observable, because free space is negative here.
///
/// Two items at `flex: 0 0.25 200px` in a 300 row. Raw shrink factors sum to
/// 0.5, initial free space is -100, so the scaled value is -50. Weighted
/// factors are 0.25 x 200 = 50 each, so each item loses 25: 175 and 175,
/// overflowing the container to 350. WebKit agrees.
///
/// Two mutations that the whole corpus was previously blind to:
///
/// - **`abs(scaled) < abs(remaining)` weakened to `scaled < remaining`.**
///   `-50 < -100` is false, so the clause would be skipped and `remaining`
///   stays -100, giving 150 and 150. Every earlier sub-one fixture grew, where
///   free space is positive and the two spellings coincide.
/// - **The base-size weighting leaking into `rawTotal`**, which ruling FS-2
///   forbids: the sum becomes 0.25x200 + 0.25x200 = 100, which is not below 1,
///   so the clause never fires at all — again 150 and 150.
@Test func fractionalShrinkScalesByRawFactorsNotWeightedOnes() {
    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 0.25, basis: px(200))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 0.25, basis: px(200))
    let root = row(tree, width: 300, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 175)
    #expect(tree.layout(b).width == 175)
    // Deliberately overflowing: a sub-one shrink factor does not remove all the
    // overflow, so the line ends past the container's 300.
    #expect(tree.layout(b).x + tree.layout(b).width == 350)
}

/// The browser's word on the fractional shrink above.
@MainActor
@Test func fractionalShrinkMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_fractional_shrink")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 0.25, basis: px(200))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 0.25, basis: px(200))
    let root = row(tree, width: 300, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b"],
        golden: golden, tolerance: 0.1)
}

/// §9.7.4.d clamps against the **main** axis's min/max, which in a column is
/// height — not width.
///
/// Nothing in the suite flexed a column before this, so hardcoding `isRow: true`
/// at `resolveFlexibleLengths`' call site passed everything: the loop would look
/// up `maxSize.width` (auto, hence no bound) and never apply the `max-height`.
///
/// 400-tall column, three `flex: 1 1 0`, the first capped at 50. Pass 1 gives
/// each 133.33; `a` clamps to 50 and freezes; pass 2 shares 350 between `b` and
/// `c` at 175 each. With the axis mutated, all three stay at 133.33 and `a`
/// blows straight through its cap.
@Test func columnFlexClampsAgainstTheHeightNotTheWidth() {
    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 1
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    // Deliberately asymmetric: a row-axis lookup finds `.auto` here and applies
    // no bound at all, which is exactly the mutation this test exists to catch.
    capped.maxSize = Size(width: .auto, height: px(50))
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(100), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).height == 50)
    #expect(tree.layout(b).height == 175)
    #expect(tree.layout(c).height == 175)
    #expect(tree.layout(b).y == 50)
    #expect(tree.layout(c).y + tree.layout(c).height == 400)
}

/// The browser's word on the column clamp above.
@MainActor
@Test func columnGrowWithAMaxHeightMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_grow_with_max")

    let tree = LayoutTree()
    var capped = Style()
    capped.flexGrow = 1
    capped.flexShrink = 1
    capped.flexBasis = px(0)
    capped.maxSize = Size(width: .auto, height: px(50))
    let a = tree.newNode(style: capped, children: [])
    let b = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(100), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

// MARK: - CSS Sizing §4.5, the automatic minimum size (`min-width: auto`).
//
// **Of the four tests below, the first three pin the *automatic* rule and cannot
// be replaced by fixtures; the fourth pins *explicit* `min-width`, which the
// corpus does cover.** The automatic rule is content-based, WebKit's content
// size comes from real text, and nothing in this framework measures any until
// the text system lands in M2 — so every fixture in the corpus is an empty div,
// for which the rule is a no-op. `flex_row_explicit_min` covers *explicit*
// `min-width` only. If these tests are ever weakened, the automatic rule has
// nothing left checking it.
//
// Narrower still than that reads: mutating the automatic minimum to 0, to the
// flex base size, or probing at max-content instead of min-content each reddens
// `automaticMinimumSizeUsesContentSizeNotFlexBasis` and, apart from the base-size
// case, *nothing else*. That one test is the rule's single point of failure until
// M2 supplies a measure function a fixture can reach.

/// `min-width: auto` resolves to the item's **min-content** size — not to 0, and
/// not to its flex base size.
///
/// A 100px row holding bases 300 and 100, both `flex-shrink: 1`. Overflow is
/// 300; weighted by base size `a` would give up 300 x 300/400 = 225 and land on
/// 75. Its content needs 80, so it floors there, freezes, and `b` absorbs the
/// whole remainder: 100 - 80 = 20.
///
/// Every number here is load-bearing against a distinct wrong answer:
/// - automatic minimum resolved to **0**: 75 / 25.
/// - automatic minimum resolved to the **flex base size** — the tempting wrong
///   answer, which would stop every `flex-basis` item shrinking: 300 / 100.
/// - the probe taken at **max-content** rather than min-content, where this
///   measure function reports 300: 300 / 0.
///
/// The floor also has to survive into the §9.7 freeze loop, not merely clamp
/// `hypotheticalMainSize`. Here the base (300) is already above the floor (80),
/// so the hypothetical clamp is a no-op and the *only* place 80 can bind is
/// §9.7.4.d — which is why `FlexItem` carries `minMain` instead of the loop
/// re-resolving it from the style, where `.auto` reads back as nil.
///
/// **Browser cross-check.** The rule itself is unreachable from a fixture, but
/// its arithmetic is not: the same row with an *explicit* `min-width: 80px`
/// was measured in WebKit through a throwaway fixture and gives exactly
/// 80 / 20, at x = 0 and x = 80. Only the source of the 80 differs.
@Test func automaticMinimumSizeUsesContentSizeNotFlexBasis() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 0
    s.flexShrink = 1
    s.flexBasis = px(300)
    s.size = Size(width: .auto, height: px(40))
    let a = tree.newLeaf(style: s) { _, available in
        if case .minContent = available.width { return SizeD(width: 80, height: 40) }
        return SizeD(width: 300, height: 40)
    }
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(100))
    let root = row(tree, width: 100, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 80)
    #expect(tree.layout(b).width == 20)
    #expect(tree.layout(b).x == 80)
}

/// An item with no content has no automatic minimum, so it shrinks freely.
///
/// This is the other half of the rule and the reason the flex base size may not
/// stand in for the content size: two `flex: 0 1 300px` boxes in a 200px row
/// shrink evenly to 100 each. Resolve the automatic minimum to the base size
/// instead and both floor at 300 — this test and Task 3's
/// `shrinkIsWeightedByBaseSize` redden together, which is the cross-task guard
/// on that mutation.
///
/// It passed before the rule was implemented, which is expected: 0 and "no
/// floor" are the same layout. It is here for the mutation above, not to have
/// gone red first.
@Test func anItemWithNoContentHasNoAutomaticMinimum() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let root = row(tree, width: 200, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 100)
    #expect(tree.layout(b).width == 100)
}

/// An explicit `min-width` **replaces** the automatic minimum rather than being
/// combined with it, so an item may be told to shrink below what its content
/// needs.
///
/// `a` is `flex: 0 1 200px; min-width: 150px` and reports a min-content size of
/// 250; `b` is `flex: 0 1 400px`. In a 300px row the overflow is 300, so `a`'s
/// proportional share puts it at 200 - 300 x 200/600 = 100. The explicit 150
/// binds, `a` freezes, and `b` absorbs 400 - 250 = 150.
///
/// The 250 content size is what makes this test say what its name says. Without
/// it `a` has no automatic minimum at all and "explicit overrides automatic" is
/// vacuous. With it, an implementation that let the content suggestion win —
/// or that combined the two with `max` — gives 250 / 50 instead.
///
/// **WebKit agrees on both halves**, measured through throwaway fixtures: 40
/// monospace `W`s (min-content ~384px) inside `min-width: 150px` lay out at
/// exactly 150, and the contentless form of this row is the committed
/// `flex_row_explicit_min` golden below.
@Test func anExplicitMinSizeOverridesTheAutomaticOne() {
    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 0
    s.flexShrink = 1
    s.flexBasis = px(200)
    s.minSize = Size(width: px(150), height: .auto)
    s.size = Size(width: .auto, height: px(40))
    let a = tree.newLeaf(style: s) { _, available in
        if case .minContent = available.width { return SizeD(width: 250, height: 40) }
        return SizeD(width: 400, height: 40)
    }
    let b = flexChild(tree, grow: 0, shrink: 1, basis: px(400))
    let root = row(tree, width: 300, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 150)
    #expect(tree.layout(b).width == 150)
    #expect(tree.layout(b).x == 150)
}

/// The browser's word on the explicit floor.
///
/// `flex_row_explicit_min` uses **unequal** bases on purpose. Equal ones would
/// make the fixture inert: 250 / 250 in a 300px row shrink to 150 / 150 and a
/// `min-width: 120px` never binds, so the whole declaration could be deleted
/// with the golden unchanged. Verified in WebKit — the equal-base form gives
/// 150 / 150 with or without the `min-width`, while this one gives 100 / 200
/// without it and 150 / 150 with it.
@MainActor
@Test func explicitMinWidthMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_explicit_min")

    let tree = LayoutTree()
    var s = Style()
    s.flexGrow = 0
    s.flexShrink = 1
    s.flexBasis = px(200)
    s.minSize = Size(width: px(150), height: .auto)
    let a = tree.newNode(style: s, children: [])
    let b = fixtureFlexChild(tree, grow: 0, shrink: 1, basis: px(400))
    let root = row(tree, width: 300, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b"],
        golden: golden, tolerance: 0.1)
}

/// A **percentage** flex-basis, in a row whose main and cross extents are far
/// apart — the one shape that pins which of the two `flexBaseSize` is handed.
///
/// `collectItems` computes `containerMain` and `containerCross` and passes both
/// to `flexBaseSize`. Task 2 pinned the axis choice *inside* that function, but
/// nothing pinned the wiring into it: transposing the two arguments at the call
/// site left the whole suite green, because every basis in the corpus was in
/// pixels and a pixel basis resolves the same against either extent.
///
/// `flex_row_percent_basis` is 700 wide and 100 tall, so the transposition is
/// arithmetically loud: `50%` is 350 against the main axis and 50 against the
/// cross. `c` is a pixel basis and must not move under either wiring — it is
/// the control that separates "wrong axis" from "percentages broken outright".
@MainActor
@Test func percentageFlexBasisResolvesAgainstTheMainAxis() throws {
    let golden = try loadGolden("flex_row_percent_basis")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: .length(.percent(0.5)))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: .length(.percent(0.25)))
    let c = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: px(120))
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(700), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Spelled out as well as compared, so the numbers the transposition would
    // change are visible without opening the golden: 350 / 175 against 700, not
    // 50 / 25 against 100.
    #expect(tree.layout(a).width == 350)
    #expect(tree.layout(b).width == 175)
    #expect(tree.layout(c).width == 120)

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b", c: "c"],
        golden: golden, tolerance: 0.1)
}

/// §9.7.4.d's `max(0, ...)` — an item whose distributed target goes **negative**.
///
/// This is not an exotic shape. `flex-shrink: 10` beside `flex-shrink: 1`, both
/// 100px, in a 50px row: shrink is weighted by base size, so the factors are
/// 1000 and 100 and `a`'s share of the -150 free space is -136.36, putting its
/// raw target at -36.36. Nothing else in the corpus overflows hard enough or
/// unevenly enough to reach that, which is why deleting the `max(0,` left
/// 113/113 green.
///
/// With the clamp: `a` violates by +36.36, freezes at 0, and `b` absorbs the
/// rest to land on 50 — WebKit agrees exactly. Without it neither item violates,
/// the total violation is 0, the loop freezes the whole line on pass 1, and `a`
/// stores a **negative width** while `b`'s origin is dragged to -36. Both the
/// width and the origin assertions below catch it.
@MainActor
@Test func aShrinkTargetBelowZeroClampsToZeroInsteadOfStoringANegativeWidth() throws {
    let golden = try loadGolden("flex_row_shrink_to_zero")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 10, basis: px(100))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 1, basis: px(100))
    let root = row(tree, width: 50, [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 0)
    #expect(tree.layout(b).width == 50)
    #expect(tree.layout(b).x == 0)

    assertMatchesGolden(
        tree, ids: [root: "root", a: "a", b: "b"],
        golden: golden, tolerance: 0.1)
}
